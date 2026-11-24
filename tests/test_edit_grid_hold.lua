-- Holding + or - on the edit mode bar's Grid box: ImGui repeats the step while it is held, so InputInt hands back a
-- new number on each repeat frame with the mouse down. One hold is one Undo step and no save while it is held, as
-- the main page's Grid size slider is. It is saved after the mouse comes up. A single click is one step too, and a
-- typed number still saves at once.
local store = require('core.store');
local imgui = require('imgui');
local edit = require('ui.edit_mode');
local snapshot = { valid = true, id = 1001, name = 'Bench', zone = 102, job = 17, level = 75, self_known = true, self_effects = {},
    party = {}, entities = { [1001] = { id = 1001, index = 0x400, name = 'Bench', kind = 'player' } } };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
-- A box typed in (typed) hands back the typed number every frame, as ImGui's InputInt does. Letting go of it (left)
-- is IsItemDeactivatedAfterEdit. typing says the box has the keys.
local last_button, activate, typed, left, last_box, typing, io = nil, nil, {}, {}, nil, false, imgui.GetIO;
rawset(imgui, 'InvisibleButton', function(label) last_button = label; return false; end);
rawset(imgui, 'IsItemActivated', function() return activate ~= nil and last_button == '##edit_hit_' .. activate; end);
rawset(imgui, 'IsWindowFocused', function() return false; end);
rawset(imgui, 'InputInt', function(label, value)
    last_box = label;
    local entry = typed[label];
    if entry then value[1] = entry; return true; end;
    return false;
end);
rawset(imgui, 'IsItemActive', function() return typed[last_box] ~= nil and not left[last_box]; end);
rawset(imgui, 'IsItemDeactivatedAfterEdit', function() return left[last_box] == true; end);
rawset(imgui, 'GetIO', function() local value = io(); value.WantTextInput = typing; return value; end);
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local s = app.state.settings;
s.rolls.enabled, s.rolls.preview = true, true;
local function frame(seconds) MOCK.imgui_calls = {}; MOCK.frame(seconds or 1 / 60); activate = nil; end;
local function steps() return #app.state.history; end;
local function settle() MOCK.mouse_down = false; frame(0.7); frame(); end;
local event = { command = '/vg edit' }; MOCK.fire('command', event);
frame();
MOCK.key_shift = false;
local rect = require('ui.elements').drawn('rolls');
MOCK.mouse_x, MOCK.mouse_y = rect.x + 10, rect.y + 10;
activate = 'rolls'; frame();
assert(edit.selected() == 'rolls', 'Fixture: Phantom Roll is picked.');
s.edit_mode.grid_mode = true;
frame(); settle();
app.state.history, app.state.redo = {}, {};
local saves, save = 0, app.callbacks.save;
app.callbacks.save = function(...) saves = saves + 1; return save(...); end;
local from = s.edit_mode.grid;

-- The + button held: three repeat frames with the mouse down the whole time.
MOCK.mouse_down = true;
for value = from + 1, from + 3 do typed['##edit_grid'] = value; frame(); end;
assert(s.edit_mode.grid == from + 3, 'Fixture: the hold moved the grid 3.');
assert(steps() == 0 and saves == 0, 'Nothing is saved while the step button is held: ' .. steps() .. ' steps, ' .. saves .. ' saves');
-- Let go, and the save after it comes.
MOCK.mouse_down, typed['##edit_grid'], left['##edit_grid'] = false, nil, true; frame();
left['##edit_grid'] = nil; frame(0.7); frame();
assert(steps() == 1 and saves == 0 and app.state.dirty == false,
    'One hold of + is one Undo step, saved once the mouse comes up: ' .. steps() .. ' steps, ' .. saves .. ' saves');
assert(app.state.history[1].label == 'Grid size' and app.state.history[1].settings.edit_mode.grid == from,
    'Its Undo step is Grid size and puts back the number from before the hold.');

-- A single click on a step button: one step, saved after the mouse comes up.
MOCK.mouse_down, typed['##edit_grid'] = true, from + 4; frame();
assert(s.edit_mode.grid == from + 4, 'A click on a step button sets it at once.');
MOCK.mouse_down, typed['##edit_grid'], left['##edit_grid'] = false, nil, true; frame();
left['##edit_grid'] = nil; frame(0.7); frame();
assert(steps() == 2 and saves == 0 and app.state.dirty == false, 'A single click is one Undo step and is saved: ' .. steps() .. ' steps');

-- A typed number still takes and saves at once, on Enter or when the box loses focus.
typing, typed['##edit_grid'] = true, 40; frame();
assert(s.edit_mode.grid == from + 4 and steps() == 2, 'Typing a grid size changes nothing yet.');
left['##edit_grid'] = true; frame();
assert(s.edit_mode.grid == 40 and steps() == 3 and saves == 1, 'Enter saves a typed number at once: ' .. steps() .. ' steps, ' .. saves .. ' saves');
typing, typed['##edit_grid'], left['##edit_grid'] = false, nil, nil; frame();
app.callbacks.save = save;
MOCK.fire('unload');
return true;
