-- Outside Arrange on screen, a display's Shift drag that starts while another change's Undo step is still open (it
-- closes at the save 0.6 s after its last change) is a step of its own. Real vantage.lua, ui/element_box.lua (the
-- Phantom Roll display), ui/native_party_hud.lua (the Party list strip), ui/edit_mode.lua (an arrow press, then Escape)
-- and ui/settings_window.lua's own changed helper, which a slider row calls with save false. Only the client readers,
-- the game's party list, the chat log, the keys and the mouse are fixtures.
local store = require('core.store');
local copy = store.copy;
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 17, level = 75, self_known = true, self_effects = {},
    party = {}, entities = { [1001] = { id = 1001, index = 0x400, name = 'Tester', kind = 'player' } } };
package.loaded['core.client'] = { load = function() end, read = function() return copy(snapshot); end,
    visibility = function() return copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local game = { available = true, groups = { { x = 1300, y = 600, width = 200, height = 40,
    rows = { [0] = { x = 1300, y = 600, width = 200, height = 40, slot = 0 } } } } };
package.loaded['core.native_party_ui'] = { status = function() return { available = true }; end,
    treasure_open = function() return false; end, geometry = function() return game; end };

local imgui = require('imgui');
local mouse = { x = -1, y = -1, down = false, pressed = false };
local function inside(rect)
    return mouse.x >= rect.x and mouse.x < rect.x + rect.width and mouse.y >= rect.y and mouse.y < rect.y + rect.height;
end;
local begin, next_pos, next_size = imgui.Begin, imgui.SetNextWindowPos, imgui.SetNextWindowSize;
local place, window, cursor, item, active = { 0, 0 }, { x = 0, y = 0 }, { 0, 0 }, nil, nil;
local items = {};
rawset(imgui, 'SetNextWindowPos', function(value, ...) place = { value[1], value[2] }; return next_pos(value, ...); end);
rawset(imgui, 'SetNextWindowSize', function(value, ...) return next_size(value, ...); end);
rawset(imgui, 'Begin', function(name, ...) window = { x = place[1], y = place[2] }; return begin(name, ...); end);
rawset(imgui, 'SetCursorPos', function(value) cursor = { window.x + value[1], window.y + value[2] }; end);
rawset(imgui, 'SetCursorScreenPos', function(value) cursor = { value[1], value[2] }; end);
rawset(imgui, 'InvisibleButton', function(id, extent)
    item = { id = id, x = cursor[1], y = cursor[2], width = extent[1], height = extent[2] };
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
-- Edit mode's keys: an arrow press and Escape, taken while one of its windows has focus.
local keys, focused = {}, false;
rawset(imgui, 'IsKeyPressed', function(key) return keys[key] == true; end);
rawset(imgui, 'IsWindowFocused', function() return focused; end);
-- An item is active while a box is being typed in, and while a pressed button is held.
local typing_box = false;
rawset(imgui, 'IsAnyItemActive', function() return typing_box or (mouse.down and active ~= nil); end);
local function lines()
    local list = setmetatable({ lines = {} }, { __index = function() return function() end; end });
    list.AddLine = function(self, from, to) self.lines[#self.lines + 1] = { from[1], from[2], to[1], to[2] }; end;
    list.GetClipRectMin = function() return 0, 0; end;
    list.GetClipRectMax = function() return 1600, 900; end;
    return list;
end;
local back, front = lines(), lines();
rawset(imgui, 'GetBackgroundDrawList', function() return back; end);
rawset(imgui, 'GetForegroundDrawList', function() return front; end);
local function frame(seconds)
    back.lines, front.lines = {}, {};
    MOCK.frame(seconds or 1 / 60);
    mouse.pressed = false;
end;

local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local s = app.state.settings;
MOCK.key_shift = true;
MOCK.chat = { x = 0, y = 700, width = 600, height = 200 };
for key, panel in pairs(s.panels) do panel.enabled = key == 'self_buffs'; end;
s.panels.self_buffs.locked, s.panels.self_buffs.x, s.panels.self_buffs.y = false, 64, 96;
s.rolls.enabled, s.rolls.preview, s.rolls.locked, s.rolls.x, s.rolls.y = true, true, false, 64, 400;
s.party_ui.enabled, s.party_ui.preview, s.party_ui.locked = true, true, false;
for _ = 1, 6 do frame(0.2); end;
for _, id in ipairs({ '##vantage_rolls_layout', '##native_move_1' }) do assert(items[id], 'Fixture: ' .. id .. ' takes a drag.'); end;

local function center(id) local r = items[id]; return r.x + r.width / 2, r.y + r.height / 2; end;
-- Press, one move, hold a frame, release, two frames after: 6 frames of 1/60 s.
local function drag(id, dx, dy)
    local x, y = center(id);
    active, mouse.x, mouse.y, mouse.down, mouse.pressed = nil, x, y, true, true;
    frame();
    mouse.x, mouse.y = x + dx, y + dy;
    frame();
    frame();
    mouse.down = false;
    frame();
    frame(); frame();
end;
local function settle() mouse.down = false; frame(0.7); frame(); frame(); end;
local function strip() local g = app.state.settings.party_ui.groups[1]; return tostring(g.native_x) .. ',' .. tostring(g.native_y); end;
local function roll() local r = app.state.settings.rolls; return r.x .. ',' .. r.y; end;
local function steps()
    local names = {};
    for _, entry in ipairs(app.state.history) do names[#names + 1] = entry.label; end;
    return #app.state.history .. ' step(s) [' .. table.concat(names, ', ') .. ']';
end;
local function undo() MOCK.fire('command', { command = '/vg undo' }); frame(); frame(); end;
local report, wrong = {}, {};

-- A. A Party list strip Shift drag, then 0.2 s after its release a Shift drag of the Phantom Roll display.
settle(); app.state.history, app.state.redo = {}, {};
local strip0, roll0 = strip(), roll();
drag('##native_move_1', -30, 12);
local strip1 = strip();
assert(strip1 ~= strip0, 'Fixture: the strip moved.');
local open = app.state.transaction and app.state.transaction.label or 'none';
frame(0.15);
drag('##vantage_rolls_layout', 40, 25);
local roll1 = roll();
assert(roll1 ~= roll0, 'Fixture: Phantom Roll moved.');
local label = app.callbacks.history_status().undo_label;
settle();
local count = #app.state.history;
local summary = steps();
undo();
report[#report + 1] = 'A strip drag then Phantom Roll 0.2 s later: open at the roll press: ' .. open .. '; ' .. summary
    .. '; Undo reads ' .. tostring(label) .. '; one Undo: strip ' .. strip0 .. ' -> ' .. strip1 .. ' -> ' .. strip()
    .. ', Phantom Roll ' .. roll0 .. ' -> ' .. roll1 .. ' -> ' .. roll();
if count ~= 2 or strip() ~= strip1 then wrong[#wrong + 1] = 'A'; end;

-- C (control). The same, with 0.8 s between the strip's release and the Phantom Roll drag: two steps.
undo(); settle(); app.state.history, app.state.redo = {}, {};
strip0, roll0 = strip(), roll();
drag('##native_move_1', -20, 8);
strip1 = strip();
frame(0.8);
drag('##vantage_rolls_layout', 30, 15);
roll1 = roll();
settle();
count, summary = #app.state.history, steps();
undo();
report[#report + 1] = 'C the same 0.8 s apart: ' .. summary .. '; one Undo: strip ' .. strip1 .. ' -> ' .. strip()
    .. ', Phantom Roll ' .. roll1 .. ' -> ' .. roll();
assert(count == 2 and strip() == strip1 and roll() == roll0, 'Control: 0.8 s apart they are two steps. ' .. report[#report]);

-- B, a control. A settings-window change made as a slider row makes it (settings_window.lua changed with save false),
-- then 0.1 s later a Shift drag of the Phantom Roll display. The window is open, away from the display. The window
-- saves on the first frame with the mouse up and nothing active, so a slider's step is closed before the press.
undo(); settle(); app.state.history, app.state.redo = {}, {};
s = app.state.settings;
s.window.open, s.window.x, s.window.y, s.window.width, s.window.height = true, 700, 40, 860, 500;
frame(); frame(); frame();
local helpers = require('ui.settings_window').main_helpers;
s = app.state.settings;
local opacity0 = s.style.opacity;
roll0 = roll();
helpers.changed(function() app.state.settings.style.opacity = 0.5; end, false, 'Opacity');
frame(0.1);
local slider_open = app.state.transaction and app.state.transaction.label or 'none';
drag('##vantage_rolls_layout', 40, 25);
roll1 = roll();
assert(roll1 ~= roll0, 'Fixture: Phantom Roll moved with the window open.');
label = app.callbacks.history_status().undo_label;
settle();
count, summary = #app.state.history, steps();
undo();
report[#report + 1] = 'B slider-style Opacity (mouse up, no item active) then Phantom Roll 0.1 s later: step open at the press: '
    .. slider_open .. '; ' .. summary .. '; Undo reads ' .. tostring(label)
    .. '; one Undo: opacity ' .. tostring(opacity0) .. ' -> 0.5 -> ' .. tostring(app.state.settings.style.opacity)
    .. ', Phantom Roll ' .. roll0 .. ' -> ' .. roll1 .. ' -> ' .. roll();
assert(slider_open == 'none' and count == 2 and app.state.settings.style.opacity == 0.5,
    'Control: a slider step closes on its release frame. ' .. report[#report]);
undo(); settle();

-- B2. A value typed in a box: the box stays active, so the window's own save after a change waits, and the step stays
-- open until the save 0.6 s after the last key. 0.1 s after it, a Shift drag of Phantom Roll, whose press takes the
-- active item from the box.
app.state.history, app.state.redo = {}, {};
s = app.state.settings;
opacity0, roll0 = s.style.opacity, roll();
typing_box = true; frame();
helpers.changed(function() app.state.settings.style.opacity = 0.6; end, false, 'Opacity');
frame(0.1);
local typed_open = app.state.transaction and app.state.transaction.label or 'none';
typing_box = false;
drag('##vantage_rolls_layout', 40, 25);
roll1 = roll();
assert(roll1 ~= roll0, 'Fixture: Phantom Roll moved after typing.');
label = app.callbacks.history_status().undo_label;
settle();
count, summary = #app.state.history, steps();
undo();
report[#report + 1] = 'B2 typed Opacity (box active) then Phantom Roll 0.1 s later: step open at the press: ' .. typed_open
    .. '; ' .. summary .. '; Undo reads ' .. tostring(label) .. '; one Undo: opacity ' .. tostring(opacity0) .. ' -> 0.6 -> '
    .. tostring(app.state.settings.style.opacity) .. ', Phantom Roll ' .. roll0 .. ' -> ' .. roll1 .. ' -> ' .. roll();
if count ~= 2 or app.state.settings.style.opacity ~= 0.6 then wrong[#wrong + 1] = 'B2'; end;
undo(); settle();
app.state.settings.window.open = false;
frame(); frame();

-- D. Arrange on screen: pick Phantom Roll, one arrow press, Escape ends it, then 0.2 s after the press a Shift drag of
-- the display outside Arrange on screen.
app.state.history, app.state.redo = {}, {};
MOCK.key_shift = false;
MOCK.fire('command', { command = '/vg edit' });
frame(); frame();
assert(require('ui.edit_mode').active(), 'Fixture: Arrange on screen is on.');
local hit = items['##edit_hit_rolls'];
assert(hit, 'Fixture: edit mode outlines Phantom Roll.');
active, mouse.x, mouse.y, mouse.down, mouse.pressed = nil, hit.x + 10, hit.y + 10, true, true;
frame(); mouse.down = false; frame();
settle();
assert(require('ui.edit_mode').selected() == 'rolls', 'Fixture: Phantom Roll is picked.');
app.state.history, app.state.redo = {}, {};
roll0 = roll();
focused = true; frame();
keys[ImGuiKey_RightArrow] = true; frame(); keys[ImGuiKey_RightArrow] = nil;
local nudged = roll();
assert(nudged ~= roll0, 'Fixture: the arrow press moved it.');
keys[ImGuiKey_Escape] = true; frame(); keys[ImGuiKey_Escape] = nil;
focused = false;
assert(not require('ui.edit_mode').active(), 'Fixture: Escape ended Arrange on screen.');
MOCK.key_shift = true;
frame(0.1);
drag('##vantage_rolls_layout', 40, 25);
roll1 = roll();
assert(roll1 ~= nudged, 'Fixture: the Shift drag moved it.');
settle();
count, summary = #app.state.history, steps();
undo();
report[#report + 1] = 'D arrow press, Escape, Shift drag: ' .. summary .. '; one Undo: Phantom Roll ' .. roll0 .. ' -> '
    .. nudged .. ' -> ' .. roll1 .. ' -> ' .. roll();
if count ~= 2 or roll() ~= nudged then wrong[#wrong + 1] = 'D'; end;

-- E. The same Party list strip dragged twice, the second 0.2 s after the first's release, as Arrange on screen makes
-- two steps of two drags.
undo(); settle(); app.state.history, app.state.redo = {}, {};
strip0 = strip();
drag('##native_move_1', -24, 10);
strip1 = strip();
frame(0.15);
drag('##native_move_1', -16, 6);
local strip2 = strip();
assert(strip2 ~= strip1, 'Fixture: the second strip drag moved it.');
settle();
count, summary = #app.state.history, steps();
undo();
report[#report + 1] = 'E strip drag twice 0.2 s apart: ' .. summary .. '; one Undo: strip ' .. strip0 .. ' -> ' .. strip1 .. ' -> '
    .. strip2 .. ' -> ' .. strip();
if count ~= 2 or strip() ~= strip1 then wrong[#wrong + 1] = 'E'; end;

assert(#wrong == 0, 'A Shift drag joins the open step of another change in: ' .. table.concat(wrong, ', ') .. ' || '
    .. table.concat(report, ' || '));
return 'Each Shift drag is an Undo step of its own';
