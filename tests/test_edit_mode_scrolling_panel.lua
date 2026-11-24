-- Edit mode picks and moves a party group in a panel of its own that scrolls, as it does one that fits. Through the real
-- vantage.lua, ui/native_party_hud.lua and ui/edit_mode.lua. In edit mode such a panel leaves the mouse and the keys to
-- edit mode and shows no scrollbar, as nothing could use it. Out of edit mode it takes the mouse again for its wheel,
-- scrollbar and own Shift drag.
-- ImGui gives the mouse to the front-most window under it that takes the mouse (no NoMouseInputs), from the windows of
-- the frame before, and only that window's items can be hovered or pressed. A press focuses that window, or none on the
-- game itself, and edit mode takes the arrow keys only while one of its own windows has focus. A window made with
-- NoBringToFrontOnFocus, as each of edit mode's outline windows is, goes behind every other window, so a panel's own
-- window gets a click on its outline unless it has NoInputs. The mouse model below does that. The other fixtures are
-- the client readers, the party (the 18 sample members) and the game's party list, which isn't read: both groups are in
-- panels of their own.
local store = require('core.store');
local bit = require('bit');
local roster = require('ui.party_hud').sample(18, 100);
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 230, job = 1, job_name = 'WAR', self_known = true,
    self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end,
    visibility = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
package.loaded['core.roster'] = { read = function() return roster; end };
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, status = function() return {}; end,
    geometry = function() return { available = false, groups = {} }; end };
package.loaded['ui.hud'] = { draw = function() end, draw_notices = function() end, cancel_gesture = function() end };

local imgui = require('imgui');
local NO_MOUSE, BEHIND = ImGuiWindowFlags_NoMouseInputs, ImGuiWindowFlags_NoBringToFrontOnFocus;
local NO_INPUTS, NO_SCROLLBAR, NO_WHEEL = ImGuiWindowFlags_NoInputs, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoScrollWithMouse;
assert(type(NO_MOUSE) == 'number' and type(BEHIND) == 'number' and type(NO_INPUTS) == 'number' and type(NO_SCROLLBAR) == 'number'
    and type(NO_WHEEL) == 'number', 'Fixture: ImGui\'s window flags are loaded.');
local mouse = { x = -1, y = -1, down = false, pressed = false };
-- made: each window by name, in the order ImGui made it, and whether it went behind. shown: this frame's windows with
-- the place, size and flags each Begin had. last: the frame before's. under: the window that has the mouse this frame.
-- focus: the window the last press went to. keys: the keys pressed this frame.
local made, count, shown, last, under, focus, keys = {}, 0, {}, {}, nil, nil, {};
local place, size, stack, cursor, item, active = nil, nil, {}, { 0, 0 }, nil, nil;
local function inside(r, x, y) return x >= r.x and x < r.x + r.width and y >= r.y and y < r.y + r.height; end;
-- Whether window a is in front of window b. One made with NoBringToFrontOnFocus goes behind every window made before
-- it, and any other one in front of them.
local function in_front(a, b)
    a, b = made[a], made[b];
    if a.behind ~= b.behind then return b.behind; end;
    if a.behind then return a.order < b.order; end;
    return a.order > b.order;
end;
local function window_under(x, y)
    local found;
    for name, r in pairs(last) do
        if bit.band(r.flags, NO_MOUSE) == 0 and inside(r, x, y) and (found == nil or in_front(name, found)) then found = name; end;
    end;
    return found;
end;
-- Set before vantage.lua loads, so its ImGui scope wrappers go round these.
local next_pos, next_size, begin, finish = imgui.SetNextWindowPos, imgui.SetNextWindowSize, imgui.Begin, imgui.End;
rawset(imgui, 'SetNextWindowPos', function(value, ...) place = { value[1], value[2] }; return next_pos(value, ...); end);
rawset(imgui, 'SetNextWindowSize', function(value, ...) size = { value[1], value[2] }; return next_size(value, ...); end);
rawset(imgui, 'Begin', function(name, open, flags)
    flags = flags or 0;
    if not made[name] then count = count + 1; made[name] = { order = count, behind = bit.band(flags, BEHIND) ~= 0 }; end;
    local r = { name = name, x = place and place[1] or 0, y = place and place[2] or 0, width = size and size[1] or 0,
        height = size and size[2] or 0, flags = flags };
    place, size, item = nil, nil, nil;
    shown[name], stack[#stack + 1] = r, r;
    return begin(name, open, flags);
end);
rawset(imgui, 'End', function(...) stack[#stack], item = nil, nil; return finish(...); end);
rawset(imgui, 'SetCursorPos', function(value)
    local w = stack[#stack] or { x = 0, y = 0 };
    cursor = { w.x + value[1], w.y + value[2] };
end);
rawset(imgui, 'SetCursorScreenPos', function(value) cursor = { value[1], value[2] }; end);
rawset(imgui, 'InvisibleButton', function(id, extent)
    local w = stack[#stack];
    item = { id = id, x = cursor[1], y = cursor[2], width = extent[1], height = extent[2] };
    item.hovered = w ~= nil and w.name == under and inside(item, mouse.x, mouse.y);
    if mouse.pressed and item.hovered then active = id; end;
    return false;
end);
rawset(imgui, 'IsItemHovered', function() return item ~= nil and item.hovered; end);
rawset(imgui, 'IsItemActivated', function() return mouse.pressed and item ~= nil and active == item.id; end);
rawset(imgui, 'IsItemActive', function() return mouse.down and item ~= nil and active == item.id; end);
rawset(imgui, 'IsMouseClicked', function() return mouse.pressed; end);
rawset(imgui, 'IsMouseDown', function() return mouse.down; end);
rawset(imgui, 'GetMousePos', function() return mouse.x, mouse.y; end);
rawset(imgui, 'IsWindowFocused', function() return stack[#stack] ~= nil and stack[#stack].name == focus; end);
rawset(imgui, 'IsKeyPressed', function(key) return keys[key] == true; end);
local function frame(seconds)
    last, shown = shown, {};
    under = window_under(mouse.x, mouse.y);
    if not mouse.down then active = nil; end;
    MOCK.imgui_calls = {};
    MOCK.frame(seconds or 1 / 60);
    if mouse.pressed then focus = under; end;
    mouse.pressed = false;
end;
local function click(x, y)
    mouse.x, mouse.y, mouse.down, mouse.pressed = x, y, true, true;
    frame();
    mouse.down = false;
    frame(); frame();
end;
local function drag(x, y, dx, dy)
    mouse.x, mouse.y, mouse.down, mouse.pressed = x, y, true, true;
    frame();
    mouse.x, mouse.y = x + dx, y + dy;
    frame(); frame();
    mouse.down = false;
    frame(); frame();
end;
local function press(key) keys[key] = true; frame(); keys[key] = nil; frame(); end;
local function middle(r) return r.x + r.width / 2, r.y + r.height / 2; end;
local function takes_mouse(name) return shown[name] ~= nil and bit.band(shown[name].flags, NO_MOUSE) == 0; end;
local function has(name, flags) return shown[name] ~= nil and bit.band(shown[name].flags, flags) == flags; end;

local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local s = app.state.settings;
local p = s.party_ui;
-- Your party and Alliance 1 each in a panel of its own, with samples, unlocked. Your party's panel is too short for its
-- six members, so it scrolls. Alliance 1's has room for them. Alliance 2 is off.
p.enabled, p.preview, p.locked, p.strips.alliance2 = true, true, false, false;
local mine, other = p.groups[1], p.groups[2];
mine.native_detached, mine.detached_x, mine.detached_y, mine.detached_width, mine.detached_height = true, 100, 400, 300, 80;
other.native_detached, other.detached_x, other.detached_y, other.detached_width, other.detached_height = true, 500, 50, 300, 800;
s.window.open, MOCK.key_shift = false, false;
for _ = 1, 6 do frame(0.2); end;
local first, second = shown['##vantage_native_1'], shown['##vantage_native_2'];
assert(first and second and not shown['##vantage_native_3'] and app.state.problem == nil,
    'Fixture: Your party and Alliance 1 are drawn, each in a panel of its own: ' .. tostring(app.state.problem));
assert(first.x == 100 and first.y == 400 and first.width == 300 and first.height == 80 and second.x == 500 and second.y == 50
    and second.height == 800, 'Fixture: the panels are where they were put: ' .. first.x .. ', ' .. first.y .. ' ' .. first.width
    .. 'x' .. first.height .. '; ' .. second.x .. ', ' .. second.y .. ' ' .. second.width .. 'x' .. second.height);
local kept = require('ui.native_party_hud')._kept.detached;
local tall, roomy = kept[1].plan, kept[2].plan;
assert(tall.content_height > tall.height and roomy.content_height <= roomy.height,
    'Fixture: Your party\'s panel scrolls and Alliance 1\'s fits: ' .. tall.content_height .. ' in ' .. tall.height .. ', '
    .. roomy.content_height .. ' in ' .. roomy.height);
-- Outside edit mode, with Shift up, the panel that scrolls keeps the mouse and its scrollbar, so the wheel scrolls it.
-- The one that fits leaves the mouse to the game.
mouse.x, mouse.y = middle(first);
frame(); frame();
assert(takes_mouse('##vantage_native_1') and not takes_mouse('##vantage_native_2') and under == '##vantage_native_1'
    and not has('##vantage_native_1', NO_SCROLLBAR) and not has('##vantage_native_1', NO_WHEEL),
    'Fixture: outside edit mode the panel that scrolls has the mouse and its scrollbar, and the one that fits leaves the mouse: '
    .. tostring(under));

-- Edit mode on: each panel gets an outline window of edit mode's own, behind the displays, that takes the mouse.
local edit = require('ui.edit_mode');
local event = { command = '/vg edit on' };
MOCK.fire('command', event);
mouse.x, mouse.y = -1, -1;
frame(); frame();
assert(event.blocked and edit.active() and app.callbacks.editing, 'Fixture: /vg edit on turns edit mode on.');
first, second = shown['##vantage_native_1'], shown['##vantage_native_2'];
local outline, room = shown['##vantage_edit_strip_1'], shown['##vantage_edit_strip_2'];
assert(first and second and outline and room and app.state.problem == nil, 'Fixture: in edit mode both panels and their outlines are drawn: '
    .. tostring(app.state.problem));
assert(outline.x == first.x and outline.y == first.y and outline.width == first.width and outline.height == first.height
    and room.x == second.x and room.y == second.y and room.width == second.width and room.height == second.height,
    'Fixture: each outline is over its panel.');
assert(takes_mouse('##vantage_edit_strip_1') and takes_mouse('##vantage_edit_strip_2') and made['##vantage_edit_strip_1'].behind
    and not made['##vantage_native_1'].behind, 'Fixture: the outlines take the mouse and sit behind the displays.');
-- In edit mode the panel that scrolls leaves the mouse, the wheel and the keys to its outline, as the one that fits does.
assert(has('##vantage_native_1', NO_INPUTS) and has('##vantage_native_2', NO_INPUTS),
    'In edit mode the panel that scrolls leaves the mouse and the keys to edit mode, as the one that fits does: '
    .. tostring(bit.band(first.flags, NO_INPUTS)) .. ' of ' .. NO_INPUTS);
assert(has('##vantage_native_1', NO_SCROLLBAR) and has('##vantage_native_1', NO_WHEEL),
    'In edit mode the panel that scrolls shows no scrollbar, as nothing could use it.');
-- The panel that fits: a Shift drag on its outline picks it and moves it, so the mouse model reaches edit mode's outline.
MOCK.key_shift = true;
local x0, y0 = other.detached_x, other.detached_y;
local x, y = middle(second);
drag(x, y, -40, 20);
assert(edit.selected() == 'strip_2' and other.detached_x == x0 - 40 and other.detached_y == y0 + 20 and app.state.problem == nil,
    'Fixture: in edit mode a Shift drag on Alliance 1\'s panel, which fits, picks it and moves it: ' .. tostring(edit.selected())
    .. ', ' .. other.detached_x .. ', ' .. other.detached_y);
assert(edit._message() == nil, 'Fixture: nothing has been said in the bar yet.');

-- The panel that scrolls: a click on its outline picks it and says to hold Shift and drag. The keys stay with edit
-- mode, so an arrow moves it, and a Shift drag moves it.
MOCK.key_shift = false;
x, y = middle(shown['##vantage_native_1']);
click(x, y);
assert(edit.selected() == 'strip_1' and edit._message() == 'Hold Shift and drag to move it.',
    'In edit mode a click on Your party\'s panel, which scrolls, picks it and says to hold Shift and drag, as it does for a panel '
    .. 'that fits. Picked: ' .. tostring(edit.selected()) .. '; the window with the mouse: ' .. tostring(under)
    .. '; the panel\'s window leaves the mouse to edit mode: ' .. tostring(not takes_mouse('##vantage_native_1')));
local from_x, from_y = mine.detached_x, mine.detached_y;
press(ImGuiKey_RightArrow);
assert(focus == '##vantage_edit_strip_1' and mine.detached_x == from_x + 1 and mine.detached_y == from_y,
    'After that click the keys stay with edit mode, so the right arrow moves Your party 1 px. Focus: ' .. tostring(focus)
    .. '; at ' .. mine.detached_x .. ', ' .. mine.detached_y .. ' from ' .. from_x .. ', ' .. from_y);
MOCK.key_shift = true;
from_x, from_y = mine.detached_x, mine.detached_y;
x, y = middle(shown['##vantage_native_1']);
drag(x, y, 30, -10);
assert(edit.selected() == 'strip_1' and mine.detached_x == from_x + 30 and mine.detached_y == from_y - 10,
    'In edit mode a Shift drag on Your party\'s panel, which scrolls, moves it: ' .. mine.detached_x .. ', ' .. mine.detached_y
    .. ' for ' .. (from_x + 30) .. ', ' .. (from_y - 10));
MOCK.key_shift = false;

-- Locked, a click on it still picks it, and in edit mode a Shift drag moves it all the same.
x, y = middle(shown['##vantage_native_2']);
click(x, y);
assert(edit.selected() == 'strip_2', 'Fixture: a click on Alliance 1\'s panel picks it.');
p.locked = true;
frame();
x, y = middle(shown['##vantage_native_1']);
click(x, y);
assert(edit.selected() == 'strip_1' and edit._message() == 'Hold Shift and drag to move it.',
    'Locked, a click on Your party\'s panel, which scrolls, picks it and says how to move it: ' .. tostring(edit.selected())
    .. ', ' .. tostring(edit._message()));
MOCK.key_shift = true;
from_x, from_y = mine.detached_x, mine.detached_y;
drag(x, y, 30, -10);
assert(mine.detached_x == from_x + 30 and mine.detached_y == from_y - 10, 'Locked, a Shift drag in edit mode moves it too.');
MOCK.key_shift = false;
p.locked = false;

-- Edit mode off: the panel that scrolls takes the mouse again, with its scrollbar, and its own Shift drag moves it.
event = { command = '/vg edit off' };
MOCK.fire('command', event);
frame();
x, y = middle(shown['##vantage_native_1']);
mouse.x, mouse.y = x, y;
frame(); frame();
assert(event.blocked and not edit.active() and not shown['##vantage_edit_strip_1'], 'Fixture: /vg edit off turns edit mode off.');
assert(takes_mouse('##vantage_native_1') and under == '##vantage_native_1' and not has('##vantage_native_1', NO_SCROLLBAR)
    and not has('##vantage_native_1', NO_WHEEL), 'Out of edit mode the panel that scrolls has the mouse and its scrollbar again.');
MOCK.key_shift = true;
from_x, from_y = mine.detached_x, mine.detached_y;
drag(x, y, 20, 15);
assert(mine.detached_x == from_x + 20 and mine.detached_y == from_y + 15 and app.state.problem == nil,
    'Out of edit mode its own Shift drag moves it: ' .. mine.detached_x .. ', ' .. mine.detached_y .. ' for ' .. (from_x + 20)
    .. ', ' .. (from_y + 15));
MOCK.key_shift = false;
MOCK.fire('unload');
return 'Edit mode picks, nudges and Shift-drags a party group panel that scrolls, as it does one that fits, and gives it back the mouse after';
