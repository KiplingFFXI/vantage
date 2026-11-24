-- A Shift resize or move of the settings window whose button comes up in the same frame as the pointer's last move is
-- one Undo step, and one Undo puts the window back, through the app's own Undo. ImGui keeps a window's place and size
-- from frame to frame, and applies SetNextWindowPos and SetNextWindowSize given ImGuiCond_Appearing only on a frame the
-- window appears (it was not drawn the frame before). The shared mock applies every call whatever the condition, so
-- this fixture keeps the settings window's rect itself, the way ImGui does.
local store = require('core.store');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {},
    party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window, imgui = require('ui.settings_window'), require('imgui');
ImGuiCond_Appearing = ImGuiCond_Appearing or 8;

-- ImGui's side: the window rect it keeps, and when it was last drawn.
local frame_no, win, next_pos, next_size = 0, { drawn = -10 }, nil, nil;
local function applies(cond, appearing)
    if cond == nil or cond == 0 or cond == ImGuiCond_Always then return true; end
    if cond == ImGuiCond_Appearing then return appearing; end
    error('Condition not modeled: ' .. tostring(cond));
end
local real_begin = imgui.Begin;
imgui.SetNextWindowPos = function(pos, cond) next_pos = { pos[1], pos[2], cond }; end;
imgui.SetNextWindowSize = function(size, cond) next_size = { size[1], size[2], cond }; end;
imgui.Begin = function(name, open, flags)
    if name == 'Vantage##settings' then
        local appearing = win.drawn < frame_no - 1;
        if next_pos and applies(next_pos[3], appearing) then win.x, win.y = next_pos[1], next_pos[2]; end
        if next_size and applies(next_size[3], appearing) then win.width, win.height = next_size[1], next_size[2]; end
        win.drawn = frame_no;
    end
    next_pos, next_size = nil, nil;
    return real_begin(name, open, flags);
end;
imgui.GetWindowPos = function() return win.x, win.y; end;
imgui.GetWindowSize = function() return win.width, win.height; end;

local clicked = false;
imgui.IsMouseClicked = function() return clicked; end;
imgui.IsAnyItemActive = function() return false; end;
imgui.IsPopupOpen = function() return false; end;
local next_open = false;
imgui.SetNextItemOpen = function(open) next_open = open; end;
imgui.CollapsingHeader = function() return next_open; end;

local cb = app.callbacks;
app.state.settings.window.open, app.state.settings.window.tab = true, 'Help';
MOCK.hovered = true;
local view = { rows = {}, context = { valid = true, job = 3, party = {}, entities = {} } };
local function frame()
    frame_no = frame_no + 1;
    MOCK.imgui_calls = {};
    window.draw(app.state.settings, view, cb);
    clicked = false;
end
local function rect(r) return ('%dx%d at %d,%d'):format(r.width, r.height, r.x, r.y); end
local function saved() return rect(app.state.settings.window); end
local function same(a, b) return a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height; end
local lines = {};
local function log(text) lines[#lines + 1] = text; end
local function labels(count)
    local out, history = {}, app.state.history;
    for index = math.max(1, #history - count + 1), #history do out[#out + 1] = history[index].label; end
    return table.concat(out, ', ');
end

-- One Shift gesture: press at the corner or on the title, move by (dx, dy) with the button down, then let go in a frame
-- where the pointer moves (rx, ry) more. Returns the Undo steps it added, whether one Undo put the window back, and
-- whether the window was drawn where it was saved.
local function gesture(name, where, dx, dy, rx, ry)
    cb.shift, MOCK.mouse_down = false, false;
    frame();
    local start = { x = win.x, y = win.y, width = win.width, height = win.height };
    -- The bottom right corner, or a spot on the title clear of the edge bands.
    local px, py = start.x + start.width - 1, start.y + start.height - 1;
    if where == 'title' then px, py = start.x + 300, start.y + 20; end
    local undo_before = cb.history_status().undo;
    cb.shift, MOCK.mouse_down, clicked, MOCK.mouse_x, MOCK.mouse_y = true, true, true, px, py;
    frame();
    MOCK.mouse_x, MOCK.mouse_y = MOCK.mouse_x + dx, MOCK.mouse_y + dy;
    frame();
    local last_drawn = rect(win);
    MOCK.mouse_x, MOCK.mouse_y, MOCK.mouse_down = MOCK.mouse_x + rx, MOCK.mouse_y + ry, false;
    frame();
    local release_drawn = rect(win);
    cb.shift = false;
    frame(); frame();
    local added = cb.history_status().undo - undo_before;
    local shown = same(win, app.state.settings.window);
    local final = { x = app.state.settings.window.x, y = app.state.settings.window.y };
    log(('%s: start %s; last drag frame drew %s; release frame drew %s; saved %s; Undo steps added %d (%s)'):format(
        name, rect(start), last_drawn, release_drawn, saved(), added, labels(added)));
    cb.undo(); frame();
    local after_one = { x = win.x, y = win.y, width = win.width, height = win.height };
    log(('  after one Undo: saved %s, window drawn %s, back at start: %s'):format(saved(), rect(win), tostring(same(after_one, start))));
    local undone = 1;
    while not same(win, start) and undone < added do
        cb.undo(); frame(); undone = undone + 1;
    end
    return added, same(after_one, start), shown, final.x - start.x, final.y - start.y;
end

-- The pointer stops before the button comes up.
local still_steps, still_back = gesture('Resize, still at release', 'corner', 100, 60, 0, 0);
-- The button comes up while the pointer is still moving.
local moving_steps, moving_back, moving_shown = gesture('Resize, moving at release', 'corner', 100, 60, 10, 10);
-- A Shift move by the title, also let go while moving.
local move_steps, move_back, move_shown, moved_x, moved_y = gesture('Move by title, moving at release', 'title', 100, 60, 10, 10);
MOCK.fire('unload');
local report = table.concat(lines, ' | ');
assert(still_steps == 1 and still_back, 'Fixture: a resize let go still is one step that one Undo takes back: ' .. report);
assert(moving_steps == 1 and moving_back, 'One Shift resize let go mid-move is one Undo step that one Undo takes back: ' .. report);
assert(moving_shown, 'The window shows the size saved where the button came up: ' .. report);
assert(move_steps == 1 and move_back and move_shown, 'One Shift move let go mid-move is one Undo step, shown where it was saved: ' .. report);
assert(moved_x == 110 and moved_y == 70, ('A Shift move goes where the button came up: moved %d, %d of 110, 70. '):format(moved_x, moved_y) .. report);
return 'A Shift resize let go mid-move is one Undo step';
