-- Arrange on screen (ui/edit_mode.lua) through vantage.lua: an arrow press, then a Shift drag before the press's Undo
-- step has closed, are two Undo steps. The drag closes the press's step as it starts, so one Undo puts back the drag
-- alone.
local store = require('core.store');
local imgui = require('imgui');
local elements, edit = require('ui.elements'), require('ui.edit_mode');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 17, level = 75, self_known = true, self_effects = {},
    party = {}, entities = { [1001] = { id = 1001, index = 0x400, name = 'Tester', kind = 'player' } } };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
-- The ImGui calls edit mode makes, with what the fixture answers.
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
local function steps() return #app.state.history; end;
local function settle() MOCK.mouse_down = false; frame(0.7); frame(); end;

frame();
command('/vg edit');
frame();
local e = s.edit_mode;
e.snap_grid, e.snap_screen, e.snap_elements, e.snap_party, e.snap_chat = false, false, false, false, false;
-- A click picks Phantom Roll.
local rect = elements.drawn('rolls');
MOCK.key_shift, MOCK.mouse_x, MOCK.mouse_y, MOCK.mouse_down = false, rect.x + 10, rect.y + 10, true;
activate = 'rolls'; frame();
settle();
assert(edit.selected() == 'rolls', 'Fixture: picked.');
local count, start_x = steps(), s.rolls.x;
-- An arrow press.
focused = true; frame();
pressed[ImGuiKey_RightArrow] = true; frame(); pressed[ImGuiKey_RightArrow] = nil;
assert(s.rolls.x == start_x + 1, 'Fixture: the press moved it.');
-- A Shift drag right after it, inside the 0.6 s the press's step stays open.
rect = elements.drawn('rolls');
MOCK.key_shift, MOCK.mouse_down, MOCK.mouse_x, MOCK.mouse_y = true, true, rect.x + 10, rect.y + 10;
activate = 'rolls'; frame();
MOCK.mouse_x = rect.x + 60; frame();
MOCK.key_shift = false; frame(); frame();
assert(s.rolls.x > start_x + 40, 'Fixture: the drag moved it: ' .. s.rolls.x - start_x);
settle();
local labels = {};
for index = count + 1, steps() do labels[#labels + 1] = app.state.history[index].label; end;
assert(steps() == count + 2, 'The arrow press and the drag are two Undo steps, but there are ' .. (steps() - count)
    .. ': ' .. table.concat(labels, ', '));
assert(labels[1] == 'Nudge Phantom Roll' and labels[2] == 'Move Phantom Roll', 'Each has its own name: ' .. table.concat(labels, ', '));
-- One Undo puts back the drag alone, and the next the press.
command('/vg undo');
assert(app.state.settings.rolls.x == start_x + 1, 'Undo puts back the drag alone: ' .. app.state.settings.rolls.x - start_x);
command('/vg undo');
assert(app.state.settings.rolls.x == start_x, 'and the next Undo the press.');
command('/vg edit');
return 'An arrow press and a quick Shift drag are two Undo steps';
