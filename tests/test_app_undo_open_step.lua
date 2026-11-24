-- A change is one Undo step from the moment it's made, though vantage.lua closes it only when it saves, 0.6 s after the
-- last change. So with no earlier step, an arrow press in Arrange on screen leaves the bar's Undo live, the settings
-- window's Undo says what it undoes, and Undo puts the change back.
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
-- Whether the bar drew its Undo greyed this frame.
local function undo_greyed()
    local calls = MOCK.imgui_calls;
    for index, call in ipairs(calls) do
        if call[1] == 'Button' and call[2] == 'Undo##edit_undo' then
            local before = calls[index - 1];
            return before and before[1] == 'BeginDisabled' and before[2] == true;
        end;
    end;
    error('Fixture: the bar has Undo.');
end;

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
-- No step yet: Undo is greyed.
app.state.history, app.state.redo = {}, {};
frame();
assert(undo_greyed(), 'Fixture: with no step, Undo is greyed.');
local start_x = s.rolls.x;
-- An arrow press, its step still open.
focused = true; frame();
pressed[ImGuiKey_RightArrow] = true; frame(); pressed[ImGuiKey_RightArrow] = nil;
assert(s.rolls.x == start_x + 1 and app.state.transaction, 'Fixture: the press moved it and its step is open.');
frame();
assert(app.state.transaction, 'Fixture: the step is still open a frame later.');
assert(not undo_greyed(), 'Right after an arrow press, Undo is live, though its step closes only at the save.');
local status = app.callbacks.history_status();
assert(status.undo == 1 and status.undo_label == 'Nudge Phantom Roll',
    'The open step counts, with its name: ' .. tostring(status.undo) .. ', ' .. tostring(status.undo_label));
-- Undo takes the open step.
assert(app.callbacks.undo(), 'Undo takes the open step.');
assert(app.state.settings.rolls.x == start_x, 'and puts the press back: ' .. app.state.settings.rolls.x - start_x);
assert(app.callbacks.history_status().undo == 0 and app.callbacks.history_status().redo == 1, 'Then there is one step to redo.');
command('/vg edit');
return 'A change still open is an Undo step';
