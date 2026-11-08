-- Hold Shift to see through settings holds for a whole drag. Once the window is see-through and the left button goes
-- down it stays so until the button is released or Shift is let go, whatever becomes active under it and wherever the
-- pointer goes, the title bar and the edges too, and the mouse still reaches what is being dragged there. The rest stays:
-- typing and popups stop it, a settings control already active keeps the window solid, and a press on the title bar or
-- an edge moves or resizes settings. test_peek_panel_drag.lua drags a real panel across it.
local defaults = require('ui.defaults');
local app = dofile(ADDON_DIR .. '/vantage.lua');
local window = require('ui.settings_window');
local imgui = require('imgui');
MOCK.fire('load'); app.refresh(0);

local BOX = { x = 100, y = 100, width = 800, height = 600 };
local INSIDE, TITLE, EDGE, OUTSIDE = { 500, 400 }, { 500, 108 }, { 100, 400 }, { 1200, 400 };
local shift, active, popup, typing = false, false, false, false;
rawset(imgui, 'IsAnyItemActive', function() return active; end);
rawset(imgui, 'IsPopupOpen', function() return popup; end);
local clicked = false;
rawset(imgui, 'IsMouseClicked', function() return clicked; end);
rawset(imgui, 'IsWindowHovered', function() return true; end);
local io = imgui.GetIO;
rawset(imgui, 'GetIO', function()
    local value = io();
    value.WantTextInput = typing;
    return value;
end);

local s = defaults.tidy(defaults.make());
s.window.open, s.window.tab = true, 'Home';
s.window.x, s.window.y, s.window.width, s.window.height = BOX.x, BOX.y, BOX.width, BOX.height;
app.state.settings = s;
local view = { rows = {}, context = { valid = true, job = 3, entities = {} } };
local callbacks = setmetatable({}, { __index = function(_, key)
    if key == 'shift' then return shift; end;
    return app.callbacks[key];
end });
MOCK.window_size = { BOX.width, BOX.height };
MOCK.window_pos['Vantage##settings'] = { BOX.x, BOX.y };

-- One frame with the pointer at point and the button down or up. Returns whether the window was see-through: it drew
-- no controls and took no mouse.
local function frame(point, down, press)
    MOCK.mouse_x, MOCK.mouse_y, MOCK.mouse_down, clicked = point[1], point[2], down, press == true;
    MOCK.imgui_calls = {};
    window.draw(s, view, callbacks);
    clicked = false;
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Checkbox' or call[1] == 'Button' then return false; end; end;
    return true;
end;
local function let_go() shift, active, popup, typing = false, false, false, false; frame(OUTSIDE, false); window.cancel_resize(); end;

frame(OUTSIDE, false);
assert(not frame(INSIDE, false), 'Fixture: without Shift the window is solid.');
shift = true;
assert(frame(INSIDE, false), 'Fixture: with Shift it is see-through.');

-- A press under the window: what it presses becomes active, and the window stays see-through.
assert(frame(INSIDE, true, true), 'The press itself.');
active = true;
assert(frame(INSIDE, true), 'What is under it being dragged doesn\'t bring the window back.');
assert(frame(INSIDE, true), 'Nor on the frames after.');
-- Across the title bar and an edge, drawn see-through and leaving the mouse to the drag.
assert(frame(TITLE, true), 'Over the title bar it stays see-through.');
assert(not window.blocks_input(s, TITLE[1], TITLE[2], true, false), 'and the drag goes on over the title bar.');
assert(frame(EDGE, true), 'Over an edge too.');
assert(not window.blocks_input(s, EDGE[1], EDGE[2], true, false), 'and over an edge.');
assert(frame(OUTSIDE, true) and frame(INSIDE, true), 'Out and back.');
-- Letting go ends it: on the title bar the window is back for its own drag.
active = false;
assert(not frame(TITLE, false), 'Released over the title bar, the window is solid.');
assert(window.blocks_input(s, TITLE[1], TITLE[2], true, false), 'and takes the mouse there again.');
assert(frame(INSIDE, false), 'See-through again inside.');
let_go();

-- This window draws first, so on the frame the button comes up what was dragged still counts as active.
shift = true;
frame(INSIDE, false);
frame(INSIDE, true, true);
active = true;
assert(frame(INSIDE, true), 'Fixture: held.');
assert(frame(INSIDE, false), 'The frame the button comes up, it stays see-through.');
active = false;
assert(frame(INSIDE, false), 'and on the frame after.');
let_go();

-- Shift let go ends it too, button still down.
shift = true;
frame(INSIDE, false);
frame(INSIDE, true, true);
active = true;
assert(frame(INSIDE, true), 'Fixture: held.');
shift = false;
assert(not frame(INSIDE, true), 'Shift let go brings the window back.');
shift = true;
assert(not frame(INSIDE, true), 'Shift again doesn\'t pick the old press back up while something is active.');
let_go();

-- Typing and popups stop it, even in the middle of a press.
shift = true;
frame(INSIDE, false);
frame(INSIDE, true, true);
assert(frame(INSIDE, true), 'Fixture: held.');
typing = true;
assert(not frame(INSIDE, true), 'Typing stops it.');
typing = false;
assert(window.blocks_input(s, INSIDE[1], INSIDE[2], false, false), 'Fixture: no Shift, the window takes the mouse.');
let_go();
shift = true;
frame(INSIDE, false);
frame(INSIDE, true, true);
popup = true;
assert(not frame(INSIDE, true), 'A popup stops it.');
popup = false;
let_go();

-- A settings control already active when Shift goes down keeps the window solid for that press.
active = true;
assert(not frame(INSIDE, true), 'Fixture: a slider being dragged.');
shift = true;
assert(not frame(INSIDE, true), 'Shift over a control in use changes nothing.');
assert(not frame(TITLE, true) and not frame(INSIDE, true), 'Nor as the pointer moves.');
let_go();

-- A press on the title bar or an edge moves or resizes settings.
shift = true;
frame(INSIDE, false);
assert(not frame(TITLE, false), 'Fixture: over the title bar the window is solid.');
assert(not frame(TITLE, true, true), 'A press on the title bar keeps it solid.');
assert(window.blocks_input(s, TITLE[1], TITLE[2], true, false), 'and settings has the mouse.');
assert(not frame({ TITLE[1] + 40, TITLE[2] + 300 }, true), 'Moving the window, it stays solid inside it too.');
frame({ TITLE[1] + 40, TITLE[2] + 300 }, false);
let_go();
s.window.x, s.window.y, s.window.width, s.window.height = BOX.x, BOX.y, BOX.width, BOX.height;
shift = true;
frame(OUTSIDE, false);
assert(not frame(EDGE, false) and not frame(EDGE, true, true), 'A press on an edge keeps it solid.');
let_go();

-- Peek off: nothing holds, and Shift over the window keeps it solid.
s.window.peek = false;
shift = true;
assert(not frame(INSIDE, false) and not frame(INSIDE, true, true) and not frame(TITLE, true), 'Turned off, it never goes see-through.');
assert(not window.peek_held, 'Nothing is held with it off.');
let_go();
s.window.peek = true;

-- Shut in the middle of a press, it doesn't come back held.
shift = true;
frame(INSIDE, false);
frame(INSIDE, true, true);
assert(window.peek_held, 'Fixture: held.');
s.window.open = false;
frame(INSIDE, true);
assert(not window.peek_held, 'A shut window holds nothing.');
s.window.open = true;
let_go();
