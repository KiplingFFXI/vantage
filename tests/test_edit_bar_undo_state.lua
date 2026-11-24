-- The Arrange on screen bar's Undo and Redo (ui/edit_mode.lua) are greyed while there is no step to take, as the
-- settings window's are, and each one's grey ends right after its button.
local defaults = require('ui.defaults');
local elements, edit = require('ui.elements'), require('ui.edit_mode');
local imgui = require('imgui');
rawset(imgui, 'GetBackgroundDrawList', function() return imgui.GetWindowDrawList(); end);
rawset(imgui, 'GetForegroundDrawList', function() return imgui.GetWindowDrawList(); end);
local s = defaults.tidy(defaults.make());
s.rolls.enabled = true;
local history = { undo = 0, redo = 0 };
local undone, redone = 0, 0;
local callbacks = { changed = function() end, save = function() return true; end,
    history_status = function() return history; end,
    undo = function() undone = undone + 1; return false, 'There is no earlier change to restore.'; end,
    redo = function() redone = redone + 1; return false, 'There is no change to redo.'; end };
local function draw()
    for index, element in ipairs(elements.movable) do elements.record(element.id, { x = index * 10, y = 100, width = 120, height = 30 }); end;
    MOCK.imgui_calls = {};
    edit.draw(s, callbacks);
end;
-- Whether the button is drawn greyed: the BeginDisabled right before it, and its EndDisabled right after.
local function greyed(label)
    local calls = MOCK.imgui_calls;
    for index, call in ipairs(calls) do
        if call[1] == 'Button' and call[2] == label then
            local before, after = calls[index - 1], calls[index + 1];
            assert(before and before[1] == 'BeginDisabled' and after and after[1] == 'EndDisabled',
                label .. ' sits in its own disabled scope: ' .. tostring(before and before[1]) .. ', ' .. tostring(after and after[1]));
            return before[2] == true;
        end;
    end;
    error('The bar has ' .. label);
end;
local function balanced()
    local depth = 0;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'BeginDisabled' then depth = depth + 1; elseif call[1] == 'EndDisabled' then depth = depth - 1; end;
        assert(depth >= 0, 'No EndDisabled comes before its BeginDisabled.');
    end;
    return depth == 0;
end;
edit.start();

draw();
assert(greyed('Undo##edit_undo') and greyed('Redo##edit_redo') and balanced(), 'With no step to take, Undo and Redo are greyed.');
history.undo = 1;
draw();
assert(not greyed('Undo##edit_undo') and greyed('Redo##edit_redo') and balanced(), 'With a step to undo, Undo is live.');
history.undo, history.redo = 0, 2;
draw();
assert(greyed('Undo##edit_undo') and not greyed('Redo##edit_redo') and balanced(), 'With a step to redo, Redo is live.');
-- A click on a live button still does its step, and the scopes stay balanced.
history.undo = 1;
MOCK.clicks['Undo##edit_undo'] = true;
draw();
assert(undone == 1 and balanced(), 'A click on Undo undoes.');
MOCK.clicks['Redo##edit_redo'] = true;
draw();
assert(redone == 1 and balanced(), 'A click on Redo redoes.');
MOCK.clicks = {};
edit.stop();
return 'The bar greys Undo and Redo with no step to take';
