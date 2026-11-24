-- Arrange on screen (ui/edit_mode.lua) through vantage.lua: each change on the bar is an Undo step of its own, even
-- right after an arrow press whose step is still open, and an arrow press right after a Grid size step is its own too.
-- A quick run of presses on one display still shares one step.
local store = require('core.store');
local imgui = require('imgui');
local elements, edit = require('ui.elements'), require('ui.edit_mode');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 17, level = 75, self_known = true, self_effects = {},
    party = {}, entities = { [1001] = { id = 1001, index = 0x400, name = 'Tester', kind = 'player' } } };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local last_button, activate, focused, pressed = nil, nil, false, {};
rawset(imgui, 'GetBackgroundDrawList', function() return imgui.GetWindowDrawList(); end);
rawset(imgui, 'GetForegroundDrawList', function() return imgui.GetWindowDrawList(); end);
rawset(imgui, 'InvisibleButton', function(label) last_button = label; return false; end);
rawset(imgui, 'IsItemActivated', function() return activate ~= nil and last_button == '##edit_hit_' .. activate; end);
rawset(imgui, 'IsWindowFocused', function() return focused; end);
rawset(imgui, 'IsKeyPressed', function(key) return pressed[key] == true; end);
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local s = app.state.settings;
s.rolls.enabled, s.rolls.preview = true, true;
s.rolls.x, s.rolls.y = 300, 40;
local function command(line) local event = { command = line }; MOCK.fire('command', event); assert(event.blocked, line); end;
local function frame(seconds)
    MOCK.imgui_calls = {};
    MOCK.frame(seconds or 1 / 60);
    activate = nil;
end;
local function settle() MOCK.mouse_down = false; frame(0.7); frame(); end;
local function labels(from)
    local out = {};
    for index = from + 1, #app.state.history do out[#out + 1] = app.state.history[index].label; end;
    return table.concat(out, ', ');
end;
local function press(key) pressed[key] = true; frame(); pressed[key] = nil; frame(); end;

frame();
command('/vg edit');
frame();
local e = s.edit_mode;
e.snap_grid, e.snap_screen, e.snap_elements, e.snap_party, e.snap_chat = false, false, false, false, false;
local rect = elements.drawn('rolls');
MOCK.key_shift, MOCK.mouse_x, MOCK.mouse_y, MOCK.mouse_down = false, rect.x + 10, rect.y + 10, true;
activate = 'rolls'; frame();
settle();
assert(edit.selected() == 'rolls', 'Fixture: picked.');
focused = true; frame();

-- Two presses, then Snap while moving ticked inside the 0.6 s the presses' step stays open.
local count, start_x, grid_mode = #app.state.history, s.rolls.x, e.grid_mode;
press(ImGuiKey_RightArrow); press(ImGuiKey_RightArrow);
assert(s.rolls.x == start_x + 2, 'Fixture: the presses moved it.');
MOCK.clicks['Snap while moving##edit_grid_mode'] = true; frame();
assert(e.grid_mode ~= grid_mode, 'Fixture: the tick turned Snap while moving.');
settle();
assert(labels(count) == 'Nudge Phantom Roll, Snap while moving',
    'Two presses and a quick tick are two steps, the presses one: ' .. labels(count));

-- A Grid size step, then an arrow press inside the 0.6 s the step stays open.
if not e.grid_mode then MOCK.clicks['Snap while moving##edit_grid_mode'] = true; frame(); settle(); end;
assert(e.grid_mode, 'Fixture: Snap while moving is on, so the Snapping fold shows.');
count = #app.state.history;
local grid, x, bump = e.grid, s.rolls.x, false;
-- The Grid box's + button: a step that, like a run of them, stays open until the save.
rawset(imgui, 'InputInt', function(label, value)
    if bump and label == '##edit_grid' then bump, value[1] = false, value[1] + 1; return true; end
    return false;
end);
MOCK.mouse_down, bump = true, true; frame();
MOCK.mouse_down = false; frame();
assert(e.grid == grid + 1 and app.state.transaction, 'Fixture: the box took a step, still open: ' .. e.grid - grid);
press(ImGuiKey_RightArrow);
assert(s.rolls.x == x + 1, 'Fixture: the press moved it.');
settle();
assert(labels(count) == 'Grid size, Nudge Phantom Roll', 'A Grid size step and a quick press are two steps: ' .. labels(count));
-- Undo puts back the press alone.
command('/vg undo');
assert(app.state.settings.rolls.x == x and app.state.settings.edit_mode.grid == grid + 1, 'Undo puts back the press alone.');
command('/vg edit');
return 'Each change on the bar is an Undo step of its own';
