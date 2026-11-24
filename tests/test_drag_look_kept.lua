-- A drag only moves a display, so while it goes on the settings window's look (theme.window) and Party list's look
-- (theme.party) are kept: a frame of the drag makes neither again. Through the real vantage.lua: each display's own
-- Shift drag, and Arrange on screen's drag and arrow presses, with the settings window open away from them and Party
-- list's samples beside the game's party list. A look change made in the middle of a drag still shows on the next frame.
-- Then a moving frame of an Arrange on screen drag makes no more than the same drag held still, counted with the
-- collector stopped and the compiler off, as the allocation tests count. Only the client readers, the game's party
-- list, the chat log, the keys and the mouse are fixtures.
local store = require('core.store');
local copy = store.copy;
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 17, level = 75, self_known = true, self_effects = {},
    party = {}, entities = { [1001] = { id = 1001, index = 0x400, name = 'Tester', kind = 'player' } } };
package.loaded['core.client'] = { load = function() end, read = function() return copy(snapshot); end,
    visibility = function() return copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
-- The game's party window for your own party, with your row in it.
local game = { available = true, groups = { { x = 1300, y = 600, width = 200, height = 40,
    rows = { [0] = { x = 1300, y = 600, width = 200, height = 40, slot = 0 } } } } };
package.loaded['core.native_party_ui'] = { status = function() return { available = true }; end,
    treasure_open = function() return false; end, geometry = function() return game; end };
-- The stand-in keeps a copy of each draw call by weak key. With the collector stopped that table never lets go and grows
-- now and then, which is the stand-in's and not a frame's, so here it keeps nothing.
MOCK.drawn = setmetatable({}, { __newindex = function() end });

-- The mouse, each window's place and the areas the displays take a drag in.
local imgui = require('imgui');
local mouse = { x = -1, y = -1, down = false, pressed = false };
local function inside(rect)
    return mouse.x >= rect.x and mouse.x < rect.x + rect.width and mouse.y >= rect.y and mouse.y < rect.y + rect.height;
end;
local begin, next_pos = imgui.Begin, imgui.SetNextWindowPos;
local place, window, cursor, item, active = { 0, 0 }, { x = 0, y = 0 }, { 0, 0 }, nil, nil;
local items = {};
rawset(imgui, 'SetNextWindowPos', function(value, ...) place[1], place[2] = value[1], value[2]; return next_pos(value, ...); end);
rawset(imgui, 'Begin', function(name, ...) window.x, window.y = place[1], place[2]; return begin(name, ...); end);
rawset(imgui, 'SetCursorPos', function(value) cursor[1], cursor[2] = window.x + value[1], window.y + value[2]; end);
rawset(imgui, 'SetCursorScreenPos', function(value) cursor[1], cursor[2] = value[1], value[2]; end);
rawset(imgui, 'InvisibleButton', function(id, extent)
    item = items[id] or {};
    item.id, item.x, item.y, item.width, item.height = id, cursor[1], cursor[2], extent[1], extent[2];
    items[id] = item;
    if mouse.pressed and inside(item) then active = id; end;
    return false;
end);
rawset(imgui, 'IsItemHovered', function() return item ~= nil and inside(item); end);
rawset(imgui, 'IsItemActivated', function() return mouse.pressed and item ~= nil and active == item.id; end);
rawset(imgui, 'IsItemActive', function() return mouse.down and item ~= nil and active == item.id; end);
rawset(imgui, 'IsMouseClicked', function() return mouse.pressed; end);
rawset(imgui, 'IsMouseDown', function() return mouse.down; end);
rawset(imgui, 'GetMousePos', function() return mouse.x, mouse.y; end);
rawset(imgui, 'IsAnyItemActive', function() return false; end);
-- Arrange on screen's keys, taken while one of its windows has focus.
local keys, focused = {}, false;
rawset(imgui, 'IsKeyPressed', function(key) return keys[key] == true; end);
rawset(imgui, 'IsWindowFocused', function() return focused; end);
local lines = setmetatable({}, { __index = function(t, k) local f = function() end; rawset(t, k, f); return f; end });
lines.GetClipRectMin = function() return 0, 0; end;
lines.GetClipRectMax = function() return 1600, 900; end;
rawset(imgui, 'GetBackgroundDrawList', function() return lines; end);
rawset(imgui, 'GetForegroundDrawList', function() return lines; end);
local calls = {};
local function frame(seconds)
    for i = #calls, 1, -1 do calls[i] = nil; end;
    MOCK.imgui_calls = calls;
    MOCK.frame(seconds or 1 / 60);
    mouse.pressed = false;
end;

-- The two looks, counted as they are made, and the font the settings window's look pushes.
local theme, party_theme, fonts = require('ui.theme'), require('ui.party_theme'), require('ui.fonts');
local window_looks, party_looks, pushed = 0, 0, nil;
local window_defaults, resolve, push_window = theme.window_defaults, party_theme.resolve, fonts.push_window;
theme.window_defaults = function(...) window_looks = window_looks + 1; return window_defaults(...); end;
party_theme.resolve = function(...) party_looks = party_looks + 1; return resolve(...); end;
fonts.push_window = function(name, ...) pushed = name; return push_window(name, ...); end;

local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local s = app.state.settings;
local elements, edit = require('ui.elements'), require('ui.edit_mode');
MOCK.key_shift = true;
MOCK.chat = { x = 0, y = 700, width = 600, height = 200 };
-- Every display on, unlocked and apart, as tests/test_snap_drags.lua has them, with snapping off.
for key, panel in pairs(s.panels) do panel.enabled = key == 'self_buffs'; end;
s.panels.self_buffs.locked, s.panels.self_buffs.x, s.panels.self_buffs.y = false, 64, 96;
s.alerts.notice_locked, s.alerts.notice_x, s.alerts.notice_y, s.alerts.notice_width = false, 496, 96, 300;
s.party_cooldowns.enabled, s.party_cooldowns.preview = true, true;
s.party_cooldowns.list.enabled, s.party_cooldowns.list.locked, s.party_cooldowns.list.x, s.party_cooldowns.list.y = true, false, 896, 96;
s.rolls.enabled, s.rolls.preview, s.rolls.locked, s.rolls.x, s.rolls.y = true, true, false, 64, 400;
s.pet.enabled, s.pet.preview, s.pet.locked, s.pet.x, s.pet.y = true, true, false, 496, 400;
s.ready_pulse.enabled, s.ready_pulse.spot, s.ready_pulse.locked, s.ready_pulse.x, s.ready_pulse.y = true, 'screen', false, 1296, 96;
s.party_ui.enabled, s.party_ui.preview, s.party_ui.locked = true, true, false;
local e = s.edit_mode;
e.snap_grid, e.snap_screen, e.snap_elements, e.snap_party, e.snap_chat = false, false, false, false, false;
local rule = require('ui.defaults').rule('notice');
rule.chat, rule.sound, rule.duration = false, '', 600;
app.callbacks.test_alert(rule);
-- The settings window open on Phantom Roll's Size and place tab, below the displays dragged and right of them.
require('ui.panel_frame').open('rolls', 'place');
app.callbacks.open_page('Display');
s = app.state.settings;
s.window.x, s.window.y, s.window.width, s.window.height = 900, 300, 600, 420;
for _ = 1, 6 do frame(0.2); end;
assert(app.state.settings_window_shown, 'Fixture: the settings window is open.');
local displays = {
    { name = 'Self buffs', hit = '##move_self_buffs' },
    { name = 'Alert notices', hit = '##notice_layout' },
    { name = 'Party cooldowns', hit = '##cooldown_list_layout' },
    { name = 'Phantom Roll', hit = '##vantage_rolls_layout' },
    { name = 'Pet', hit = '##vantage_pet_layout' },
    { name = 'Ready pulse', hit = '##ready_pulse_spot' },
};
for _, display in ipairs(displays) do assert(items[display.hit], 'Fixture: ' .. display.name .. ' takes a drag.'); end;
local function settle() mouse.down, mouse.pressed = false, false; frame(0.7); frame(); frame(); end;

-- A drag under way: count frames that move it 1 px one way and back, then as many held still. Returns the looks each
-- made and how far the settings moved on.
local flip = 0;
local function moving() flip = 1 - flip; mouse.x = mouse.x + (flip == 1 and 1 or -1); frame(); end;
local function still() frame(); end;
local function counted(count, step)
    local made_window, made_party, revision = window_looks, party_looks, app.callbacks.settings_revision();
    for _ = 1, count do step(); end;
    return window_looks - made_window, party_looks - made_party, app.callbacks.settings_revision() - revision;
end;

local report, wrong = {}, {};
local function judge(name, count)
    local window_moving, party_moving, bumps = counted(count, moving);
    -- Party list draws before Arrange on screen, so it sees that drag's last move on the frame after.
    still();
    local window_still, party_still = counted(count, still);
    report[#report + 1] = ('%s: over %d moving frames %d settings changes, %d window looks, %d party looks; held still %d, %d')
        :format(name, count, bumps, window_moving, party_moving, window_still, party_still);
    assert(bumps >= count / 2, 'Fixture: ' .. name .. '\'s drag moved it. ' .. report[#report]);
    assert(party_still == 0 and party_looks > 0, 'Fixture: Party list\'s look is made once and kept. ' .. report[#report]);
    if window_moving ~= window_still or party_moving ~= party_still then wrong[#wrong + 1] = name; end;
end;

-- Each display's own Shift drag.
for _, display in ipairs(displays) do
    settle();
    local hit = items[display.hit];
    active, mouse.x, mouse.y, mouse.down, mouse.pressed = nil, hit.x + hit.width / 2, hit.y + hit.height / 2, true, true;
    frame();
    mouse.x = mouse.x + 5; frame();
    judge(display.name, 20);
    settle();
end;

-- Arrange on screen: a drag of Phantom Roll, then arrow presses on it.
MOCK.key_shift = false;
MOCK.fire('command', { command = '/vg edit' });
frame(); frame();
assert(edit.active(), 'Fixture: Arrange on screen is on.');
local function start_drag()
    local hit = items['##edit_hit_rolls'];
    assert(hit, 'Fixture: Arrange on screen outlines Phantom Roll.');
    MOCK.key_shift, active, mouse.x, mouse.y, mouse.down, mouse.pressed = true, nil, hit.x + 10, hit.y + 10, true, true;
    frame();
    mouse.x = mouse.x + 5; frame();
    assert(edit._gesture() and edit._gesture().dirty, 'Fixture: the drag is under way.');
    -- The drag's first move saved the step before it, and Party list, drawn before Arrange on screen, sees that save on
    -- the frame after.
    frame();
end;
local function stop_drag() MOCK.key_shift = false; settle(); assert(not edit._gesture(), 'Fixture: the drag ended.'); end;
start_drag();
judge('Arrange on screen drag', 20);
stop_drag();
assert(edit.selected() == 'rolls', 'Fixture: Phantom Roll is picked.');
focused = true; frame();
local function nudge() keys[ImGuiKey_RightArrow] = not keys[ImGuiKey_RightArrow] or nil; frame(); end;
local made_window, made_party = window_looks, party_looks;
for _ = 1, 20 do nudge(); end;
keys[ImGuiKey_RightArrow] = nil;
report[#report + 1] = ('Arrow presses: %d window looks, %d party looks over 20 frames'):format(window_looks - made_window, party_looks - made_party);
if window_looks ~= made_window or party_looks ~= made_party then wrong[#wrong + 1] = 'Arrow presses'; end;
focused = false;
settle();

-- A look change in the middle of a drag shows on the next frame: the main font, which both looks follow.
start_drag();
moving(); moving();
made_window, made_party = window_looks, party_looks;
local font = s.style.font == 'Ashita' and 'Agave' or 'Ashita';
app.callbacks.changed('before', 'Font'); s.style.font = font; app.callbacks.changed('after');
moving();
assert(window_looks > made_window and party_looks > made_party and pushed == font,
    ('A font picked mid-drag shows at once: %d window looks, %d party looks, the window pushes %s for %s')
    :format(window_looks - made_window, party_looks - made_party, tostring(pushed), font));
stop_drag();
app.callbacks.undo();

-- What a moving frame of an Arrange on screen drag makes, against the same drag held still: the median of each frame
-- counted on its own, as now and then a table of the stand-in's grows in a frame.
local function regrow(n) if n > 0 then return 1 + regrow(n - 1); end return 0; end
local out, sorted = {}, {};
local function measure(count, step)
    jit.off(); jit.flush();
    for _ = 1, 30 do step(); end;
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    -- A full collection shrinks the Lua stack, and the next frames grow it back once, which is LuaJIT's and not a frame's.
    regrow(300);
    for _ = 1, 30 do step(); end;
    for i = 1, count do
        local before = collectgarbage('count');
        step();
        out[i] = collectgarbage('count') - before;
    end;
    collectgarbage('restart');
    jit.on();
    for i = 1, count do sorted[i] = out[i]; end;
    table.sort(sorted);
    return sorted[math.floor((count + 1) / 2)];
end;
start_drag();
local moved = measure(120, moving);
local held = measure(120, still);
stop_drag();
MOCK.fire('command', { command = '/vg edit' });
assert(moved - held < 0.5, ('A moving frame of a drag makes %.2f KB more than one held still (%.2f against %.2f). '):format(
    moved - held, moved, held) .. table.concat(report, ' | '));
assert(#wrong == 0, 'A drag that only moves a display makes the looks again on every moving frame (' .. table.concat(wrong, ', ')
    .. '): ' .. table.concat(report, ' | '));
return ('Looks kept while a drag moves a display: %s; a moving frame makes %.2f KB, one held still %.2f KB'):format(
    table.concat(report, ' | '), moved, held);
