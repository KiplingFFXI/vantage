-- Edit mode (ui/edit_mode.lua) through vantage.lua: /vg edit and the Home and bar buttons turn it on and off, and
-- ending it leaves every display where it is. Each display on the screen gets an outline that a click picks, drawn
-- over the display on its own window. A Shift
-- drag moves an unlocked display, snapping as chosen; without Shift nothing moves, and Shift never moves a locked one.
-- A locked display is unlocked in the bar. While the bar or an outline has focus, the arrow keys move the picked
-- display 1 px, 10 with Shift, and Escape ends edit mode; the keys are captured only then, through ImGui's own flag,
-- and the bar doesn't take focus as it opens, unless the settings window covers both its spots.
-- The Grid box takes a typed number on Enter or when it loses focus, a step
-- button at once, and Escape there only puts its number back, so the next Escape ends edit mode. A typed spot is on the
-- Size and place tab. Each move is one Undo step, and lands a display drawn at a half pixel on a whole one. A display that moves
-- with something keeps following it. Overhead icons aren't in edit mode.
-- The bar holds Snap while moving, the same tick as the main page's. With it on, Snapping holds the picked display's
-- tick, locked or not, the Grid box, the snapping switches and Snap distance. With it off, none of them.
local store = require('core.store');
local imgui = require('imgui');
local elements, edit, anchors = require('ui.elements'), require('ui.edit_mode'), require('core.anchors');
local snap = require('ui.snap');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 17, level = 75, self_known = true, self_effects = {},
    party = {}, entities = { [1001] = { id = 1001, index = 0x400, name = 'Tester', kind = 'player' } } };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
-- The ImGui calls edit mode makes, with what the fixture answers.
local last_button, activate, focused, pressed, typed, captured, boxes = nil, nil, false, {}, {}, 0, {};
rawset(imgui, 'GetBackgroundDrawList', function() return imgui.GetWindowDrawList(); end);
rawset(imgui, 'GetForegroundDrawList', function() return imgui.GetWindowDrawList(); end);
rawset(imgui, 'InvisibleButton', function(label) last_button = label; return false; end);
rawset(imgui, 'IsItemActivated', function() return activate ~= nil and last_button == '##edit_hit_' .. activate; end);
rawset(imgui, 'IsWindowFocused', function() return focused; end);
rawset(imgui, 'IsKeyPressed', function(key) return pressed[key] == true; end);
rawset(imgui, 'SetNextFrameWantCaptureKeyboard', function(value) if value then captured = captured + 1; end; end);
-- A box being typed in (typed) hands back the typed number every frame, as ImGui's InputInt does, and has the keys
-- (typing, GetIO().WantTextInput). Enter, Escape or a click away (left) is IsItemDeactivatedAfterEdit; Escape and a
-- step button let go hand back the number the box was given. A box typed in, or a step button held, is the active
-- item until it is left. boxes holds the number each box was given.
local typing, left, last_box, io = false, {}, nil, imgui.GetIO;
rawset(imgui, 'InputInt', function(label, value)
    boxes[label], last_box = value[1], label;
    local entry = typed[label];
    if entry then value[1] = entry; return true; end;
    return false;
end);
rawset(imgui, 'IsItemActive', function() return typed[last_box] ~= nil and not left[last_box]; end);
rawset(imgui, 'IsItemDeactivatedAfterEdit', function() return left[last_box] == true; end);
rawset(imgui, 'GetIO', function() local value = io(); value.WantTextInput = typing; return value; end);
-- Each window hands out a draw list of its own, which marks each call with its window and how many windows were open,
-- so the test sees where an outline went and that no window's clip cuts it.
local stack, lists = {}, {};
local begin_window, end_window = imgui.Begin, imgui.End;
rawset(imgui, 'Begin', function(name, ...) stack[#stack + 1] = name; return begin_window(name, ...); end);
rawset(imgui, 'End', function(...) stack[#stack] = nil; return end_window(...); end);
rawset(imgui, 'GetWindowDrawList', function()
    local name = stack[#stack] or '';
    local list = lists[name];
    if not list then
        list = setmetatable({}, { __index = function(_, method)
            return function(_, ...)
                local call = { 'draw:' .. method, ... };
                call.window, call.open = name, #stack;
                MOCK.imgui_calls[#MOCK.imgui_calls + 1] = call;
                MOCK.drawn[call] = MOCK.copy_arguments('draw:' .. method, ...);
            end;
        end });
        lists[name] = list;
    end;
    return list;
end);
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local s = app.state.settings;
s.rolls.enabled, s.rolls.preview, s.pet.enabled, s.pet.preview = true, true, true, true;
s.rolls.x, s.rolls.y = 300, 40;
local function command(line) local event = { command = line }; MOCK.fire('command', event); assert(event.blocked, line); end;
local function frame(seconds)
    MOCK.imgui_calls = {};
    MOCK.frame(seconds or 1 / 60);
    activate = nil;
end;
local function began(name)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Begin' and call[2] == name then return true, call[4]; end; end;
    return false;
end;
local function steps() return #app.state.history; end;
local function settle() MOCK.mouse_down = false; frame(0.7); frame(); end;

-- On and off.
frame();
assert(not began('Arrange on screen##vantage_edit_bar') and not began('##vantage_edit_rolls'), 'Edit mode starts off.');
command('/vg edit');
assert(edit.active() and MOCK.printed[#MOCK.printed]:find('Arrange on screen is on', 1, true), '/vg edit turns it on.');
frame();
local shows, bar_flags = began('Arrange on screen##vantage_edit_bar');
assert(shows, 'The bar shows.');
local asks = false;
for _, call in ipairs(MOCK.imgui_calls) do asks = asks or call[1] == 'BeginCombo' and call[2] == '##edit_pick' and call[3] == 'Pick a display'; end;
assert(asks, 'With nothing picked the bar\'s list reads Pick a display, which fits it.');
assert(type(ImGuiWindowFlags_NoFocusOnAppearing) == 'number' and require('bit').band(bar_flags, ImGuiWindowFlags_NoFocusOnAppearing) ~= 0,
    'The bar doesn\'t take focus as it opens, so the keys stay with the game until it or an outline is clicked.');
for _, id in ipairs({ 'rolls', 'pet', 'self_buffs', 'self_debuffs', 'target' }) do
    assert(began('##vantage_edit_' .. id), 'Each display on the screen gets an outline: ' .. id);
end;
assert(not began('##vantage_edit_overhead'), 'Overhead icons sit over heads, so edit mode has no outline for them.');
-- Each outline's name sits just above it, clear of the display's own heading and icons, or just below it near the top
-- of the screen, as Alerts is at its first spot. It is drawn at 14 px in a box
-- as wide as the name at that size, whatever size the window's font is: here 28 px, where the name measures twice as wide.
rawset(imgui, 'GetFontSize', function() return 28; end);
frame();
rawset(imgui, 'GetFontSize', nil);
local tags = 0;
for index, call in ipairs(MOCK.imgui_calls) do
    local text = MOCK.drawn[call];
    if call[1] == 'draw:AddText' and text[3] == 14 then
        local box, edge;
        for back = index - 1, 1, -1 do
            local earlier = MOCK.imgui_calls[back];
            if not box and earlier[1] == 'draw:AddRectFilled' then box = MOCK.drawn[earlier];
            elseif box and earlier[1] == 'draw:AddRect' then edge = MOCK.drawn[earlier]; break; end;
        end;
        local above = math.floor(edge[2][2] - 20);
        local y = above >= 0 and above or math.floor(edge[3][2] + 2);
        assert(box[2][1] == math.floor(edge[2][1]) and box[3][1] - box[2][1] == #text[6] * 8 * 14 / 28 + 7
            and box[2][2] == y and box[3][2] == y + 18, 'The name sits just above its display, in a box that fits it: ' .. text[6]);
        tags = tags + 1;
    end;
end;
assert(tags >= 5, 'Fixture: every outline has its tag.');
-- Each outline and name go on the display's own window once every window has ended: edit mode's windows sit behind
-- the displays, and a window cuts what is drawn in it at its edge. A display with no window up, as Alerts with no
-- alert to show, has them on edit mode's window under it.
frame();
local placed = {};
for index, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'draw:AddText' and MOCK.drawn[call][3] == 14 then
        -- The name, its box and the outline's two lines.
        local name, parts = MOCK.drawn[call][6], { call };
        for back = index - 1, 1, -1 do
            if #parts == 4 then break; end;
            if MOCK.imgui_calls[back][1]:find('^draw:') then parts[#parts + 1] = MOCK.imgui_calls[back]; end;
        end;
        assert(#parts == 4 and parts[2][1] == 'draw:AddRectFilled' and parts[3][1] == 'draw:AddRect' and parts[4][1] == 'draw:AddRect',
            'Fixture: the name comes after its box and the outline: ' .. name);
        for _, part in ipairs(parts) do
            assert(part.window == call.window and part.open == 0, 'The outline and name are drawn on one window with no window open: ' .. name);
        end;
        placed[name:match('^(.-)  %(') or name] = call.window;
    end;
end;
assert(placed['Phantom Roll'] == '##vantage_rolls' and placed['Pet'] == '##vantage_pet' and placed['Self buffs'] == '##vantage_self_buffs',
    'An outline and name go on the display\'s own window, over the display.');
assert(placed['Alerts'] == '##vantage_edit_notices', 'Alerts with no alert up has its outline on edit mode\'s window.');
-- Near the top of the screen the name sits just below its display instead. And it steps above a SAMPLE tag it would
-- touch: here Phantom Roll's at its top right, with Phantom Roll at its narrowest and the name measuring wide in a 9 px font.
local function tag_box(label)
    for index, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddText' and MOCK.drawn[call][3] == 14 and MOCK.drawn[call][6]:find(label, 1, true) == 1 then
            for back = index - 1, 1, -1 do
                if MOCK.imgui_calls[back][1] == 'draw:AddRectFilled' then return MOCK.drawn[MOCK.imgui_calls[back]]; end;
            end;
        end;
    end;
end;
local rolls_y, rolls_width = s.rolls.y, s.rolls.width;
s.rolls.y = 4; frame();
local rolls = elements.drawn('rolls');
assert(rolls.y == 4 and tag_box('Phantom Roll')[2][2] == math.floor(rolls.y + rolls.height + 2), 'Near the top of the screen the name sits just below its display.');
s.rolls.y, s.rolls.width = rolls_y, 200;
rawset(imgui, 'GetFontSize', function() return 9; end);
frame();
rawset(imgui, 'GetFontSize', nil);
rolls = elements.drawn('rolls');
local sample;
for _, call in ipairs(MOCK.imgui_calls) do
    local drawn = MOCK.drawn[call];
    if call[1] == 'draw:AddRectFilled' and drawn[4] == 0xD8171717 and drawn[2][1] >= rolls.x and drawn[3][1] <= rolls.x + rolls.width then sample = drawn; end;
end;
local stepped = tag_box('Phantom Roll');
assert(sample and stepped[3][1] > sample[2][1] and stepped[3][2] <= sample[2][2] and stepped[2][2] >= 0,
    'The name steps above the SAMPLE tag it would touch.');
s.rolls.width = rolls_width;
assert(app.callbacks.editing, 'The displays are told edit mode is on.');
local start_x, start_y = s.rolls.x, s.rolls.y;

-- A click picks a display; without Shift nothing moves.
MOCK.key_shift = false;
local rect = elements.drawn('rolls');
MOCK.mouse_x, MOCK.mouse_y, MOCK.mouse_down = rect.x + 10, rect.y + 10, true;
activate = 'rolls'; frame();
assert(edit.selected() == 'rolls', 'A click on its outline picks it.');
local plain = edit._message();
assert(plain == 'Hold Shift and drag to move it.', 'A click without Shift says how to move it: ' .. tostring(plain));
boxes = {}; frame();
local bar_buttons = {};
for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Button' then bar_buttons[#bar_buttons + 1] = call[2]; end; end;
assert(not boxes['X##edit_x'] and not boxes['Y##edit_y'] and not boxes['W##edit_w'] and not boxes['H##edit_h']
    and not table.concat(bar_buttons, '|'):find('edit_bar_side', 1, true), 'The bar has no typed spot, which is on Place, and it stays at the top.');
MOCK.mouse_x = rect.x + 90; frame();
assert(s.rolls.x == start_x and s.rolls.y == start_y and steps() == 0, 'A drag without Shift moves nothing.');
settle();
-- A lock stops only a Shift drag outside edit mode: here a locked display moves, and Undo puts it back.
assert(s.rolls.locked, 'Fresh displays are locked.');
MOCK.key_shift, MOCK.mouse_down, MOCK.mouse_x = true, true, rect.x + 10;
activate = 'rolls'; frame();
MOCK.mouse_x, MOCK.mouse_y = rect.x + 120, rect.y + 60; frame();
settle();
assert(s.rolls.x ~= start_x and steps() == 1 and app.state.history[1].label == 'Move Phantom Roll', 'Shift moves a locked display in edit mode.');
command('/vg undo');
s = app.state.settings;
assert(s.rolls.x == start_x and s.rolls.y == start_y and s.rolls.locked and steps() == 0, 'Undo puts it back, still locked.');
-- The arrow keys move it too.
MOCK.key_shift = false;
focused = true; frame();
pressed[ImGuiKey_RightArrow] = true; frame(); pressed[ImGuiKey_RightArrow] = nil;
focused = false;
assert(s.rolls.x == start_x + 1, 'The keys move a locked display.');
settle();
assert(steps() == 1, 'As one Undo step.');
command('/vg undo');
s = app.state.settings;
assert(s.rolls.x == start_x and steps() == 0, 'Undo puts that back too.');
-- The bar has no lock of its own, and no outline says locked, as a lock means nothing here.
frame();
local bar_ticks = {};
for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Checkbox' then bar_ticks[#bar_ticks + 1] = call[2]; end; end;
assert(not table.concat(bar_ticks, '|'):find('Locked', 1, true), 'The bar has no Locked tick: ' .. table.concat(bar_ticks, '|'));

-- A Shift drag moves it from where it was drawn, snapping as chosen, and is one Undo step.
local e = s.edit_mode;
e.snap_grid, e.snap_screen, e.snap_elements, e.snap_party, e.snap_chat = false, false, false, false, false;
MOCK.key_shift, MOCK.mouse_down, MOCK.mouse_x, MOCK.mouse_y = true, true, rect.x + 10, rect.y + 10;
activate = 'rolls'; frame();
MOCK.mouse_x, MOCK.mouse_y = rect.x + 47, rect.y + 31; frame();
assert(s.rolls.x == start_x + 37 and s.rolls.y == start_y + 21, 'With snapping off it follows the mouse: ' .. s.rolls.x .. ', ' .. s.rolls.y);
MOCK.mouse_x = rect.x + 60; frame();
assert(s.rolls.x == start_x + 50, 'It keeps following.');
-- Letting go of Shift ends the drag where it is.
MOCK.key_shift = false;
MOCK.mouse_x = rect.x + 200; frame(); frame();
assert(s.rolls.x == start_x + 50 and edit._gesture() == nil, 'Without Shift the drag stops.');
MOCK.key_shift = true;
settle();
assert(steps() == 1 and app.state.history[1].label == 'Move Phantom Roll', 'The drag is one Undo step.');
command('/vg undo');
assert(app.state.settings.rolls.x == start_x and app.state.settings.rolls.y == start_y, 'Undo puts it back.');
command('/vg redo');
s = app.state.settings; e = s.edit_mode;
assert(s.rolls.x == start_x + 50, 'Redo moves it again.');
frame();
-- While Snap while moving is off the bar has its tick and nothing else of snapping. With it on, Snapping has the picked
-- display's tick, the Grid box, the switches and Snap distance: a click on the tick is one Undo step and a save.
local function checkbox(label)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Checkbox' and call[2] == label then return call[3][1]; end; end;
    return nil;
end;
boxes = {}; frame();
assert(e.grid_mode == false and checkbox('This display snaps##edit_grid_tick') == nil and boxes['##edit_grid'] == nil
    and checkbox('Grid##edit_snap_grid') == nil and checkbox('Snap while moving##edit_grid_mode') == false,
    'Off, the bar has Snap while moving and no tick, Grid box or snapping switches.');
e.grid_mode = true;
boxes = {}; frame();
assert(checkbox('This display snaps##edit_grid_tick') == false and boxes['##edit_grid'] == 16 and checkbox('Grid##edit_snap_grid') == false
    and boxes['##edit_snap_distance'] == e.snap_distance, 'On, the bar has the picked display\'s tick, the Grid box, the snapping switches and Snap distance.');
-- At a big Settings text size the boxes have room for 256 beside their step buttons, the list for the picked display's
-- name, and the help line wraps before the screen's edge (1600 wide here) instead of running past it.
rawset(imgui, 'CalcTextSize', function(text) return #tostring(text) * 20, 40; end);
rawset(imgui, 'GetFrameHeight', function() return 42; end);
frame();
rawset(imgui, 'CalcTextSize', nil);
rawset(imgui, 'GetFrameHeight', nil);
local function width_before(kind, label)
    local width;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'SetNextItemWidth' then width = call[2];
        elseif call[1] == kind and call[2] == label then return width; end;
    end;
end;
-- The fixture's InputInt isn't logged, so a box is found by its name before it.
local function box_width(name)
    local seen = false;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'TextUnformatted' and call[2] == name then seen = true;
        elseif seen and call[1] == 'SetNextItemWidth' then return call[2]; end;
    end;
end;
for _, name in ipairs({ 'Grid', 'Snap distance' }) do
    assert((box_width(name) or 0) >= 3 * 20 + 2 * 42, 'A number box fits 256 and its step buttons at a big text size: ' .. name);
end;
assert((width_before('BeginCombo', '##edit_pick') or 0) >= #'Phantom Roll' * 20 + 42, 'The display list fits the picked display\'s name.');
local wrap_at, wrapped_help;
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'PushTextWrapPos' then wrap_at = call[2];
    elseif call[1] == 'PopTextWrapPos' then wrap_at = nil;
    elseif call[1] == 'TextUnformatted' and tostring(call[2]):find('^Click a display to pick it') then wrapped_help = wrap_at; end;
end;
assert(wrapped_help and wrapped_help <= 1600 - 12, 'The help line wraps before the screen\'s edge: ' .. tostring(wrapped_help));
-- So do the lines about the picked display: hidden by its rules, or not on the screen.
local function wrap_of(pattern)
    local at, found;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'PushTextWrapPos' then at = call[2];
        elseif call[1] == 'PopTextWrapPos' then at = nil;
        elseif call[1] == 'TextUnformatted' and tostring(call[2]):find(pattern) then found = at or false; end;
    end;
    return found;
end;
local conditions = require('core.conditions');
local shown_by_rules = conditions.shown;
conditions.shown = function() return false; end;
frame();
conditions.shown = shown_by_rules;
local hidden_wrap = wrap_of('^Its When to show rules hide it');
assert(hidden_wrap and hidden_wrap <= 1600 - 12, 'The line about When to show rules wraps before the screen\'s edge: ' .. tostring(hidden_wrap));
local drawn_now = elements.drawn;
elements.drawn = function(id) if id == 'rolls' then return nil; end; return drawn_now(id); end;
frame();
elements.drawn = drawn_now;
local gone_wrap = wrap_of(' is not on the screen now%.$');
assert(gone_wrap and gone_wrap <= 1600 - 12, 'The line about a display not on the screen wraps before its edge: ' .. tostring(gone_wrap));
frame();
local saves, save = 0, app.callbacks.save;
app.callbacks.save = function(...) saves = saves + 1; return save(...); end;
local ticked_from = steps();
MOCK.clicks['This display snaps##edit_grid_tick'] = true; frame();
assert(snap.ticked(s, 'rolls') and steps() == ticked_from + 1 and app.state.history[steps()].label == 'Snap Phantom Roll'
    and saves == 1, 'The bar ticks Phantom Roll to snap, as one Undo step and a save: ' .. (steps() - ticked_from) .. ', ' .. saves);
MOCK.clicks['This display snaps##edit_grid_tick'] = true; frame();
assert(not snap.ticked(s, 'rolls') and steps() == ticked_from + 2 and app.state.history[steps()].label == 'Stop snapping Phantom Roll'
    and saves == 2, 'Again, it unticks it, as one Undo step and a save: ' .. (steps() - ticked_from) .. ', ' .. saves);
-- Shift held hides the settings window.
MOCK.key_shift = false;
s.window.open, s.window.tab = true, 'Home';
frame(); frame();
assert(checkbox('Snap while moving##main_grid_mode') == true and checkbox('Snap while moving##edit_grid_mode') == true,
    'The main page and the bar show the same Snap while moving.');
s.window.open = false;
frame();
-- Snapping to the grid, with Phantom Roll ticked: an edge lands on a grid line near where the mouse put it.
snap.tick(s, 'rolls', true);
e.snap_grid, e.grid = true, 16;
rect = elements.drawn('rolls');
local before_x = s.rolls.x;
MOCK.key_shift, MOCK.mouse_down, MOCK.mouse_x, MOCK.mouse_y = true, true, rect.x + 10, rect.y + 10;
activate = 'rolls'; frame();
MOCK.mouse_x, MOCK.mouse_y = rect.x + 10 + 23, rect.y + 10 + 5; frame();
rect = elements.drawn('rolls'); frame();
rect = elements.drawn('rolls');
assert(math.abs(s.rolls.x - (before_x + 23)) <= e.snap_distance and (rect.x % 16 == 0 or (rect.x + rect.width) % 16 == 0),
    'An edge snaps to the grid: ' .. s.rolls.x);
settle();
-- Either edge snaps to the nearest grid line. Edit mode snaps by ui/snap.lua, as every Shift drag does.
assert(snap.move(s, 'rolls', 323, 0, 100, 40, 1600, 900) == -3, 'Its left edge snaps to the grid.');
assert(snap.move(s, 'rolls', 330, 0, 100, 40, 1600, 900) == 2, 'Its right edge snaps to the grid.');
-- Snapping to other displays, the screen, the party list and the chat log, as each is chosen.
e.snap_grid = false;
elements.record('pet', { x = 700, y = 300, width = 200, height = 100 });
e.snap_elements = true;
local shift = snap.move(s, 'rolls', 896, 0, 120, 40, 1600, 900);
assert(shift == 4, 'A left edge 4 px short of another display\'s right edge snaps to it: ' .. tostring(shift));
e.snap_elements, e.snap_screen = false, true;
shift = snap.move(s, 'rolls', 745, 0, 100, 40, 1600, 900);
assert(shift == 5, 'Its middle snaps to the screen\'s center.');
e.snap_screen, e.snap_party = false, true;
elements.party_list = { x = 1300, y = 700, width = 200, height = 120 };
shift = snap.move(s, 'rolls', 1100, 0, 197, 40, 1600, 900);
assert(shift == 3, 'Its right edge snaps to the party list\'s left edge.');
e.snap_party, e.snap_chat = false, true;
elements.chat = { x = 12, y = 520, width = 900, height = 344 };
assert(select(2, snap.move(s, 'rolls', 0, 470, 100, 45, 1600, 900)) == 5, 'Its bottom snaps to the chat log\'s top.');
e.snap_chat = false;
assert(select(2, snap.move(s, 'rolls', 0, 470, 100, 45, 1600, 900)) == 0, 'With snapping off nothing snaps.');
elements.party_list = nil;

-- The arrow keys move the picked display 1 px, 10 with Shift, only while the bar or an outline has focus.
frame();
local x0 = s.rolls.x;
MOCK.key_shift = false;
pressed[ImGuiKey_RightArrow] = true; frame(); pressed[ImGuiKey_RightArrow] = nil;
assert(s.rolls.x == x0, 'Without focus the keys go to the game.');
local held = captured;
frame();
assert(captured == held, 'Without focus the keyboard isn\'t captured.');
focused = true;
frame();
assert(captured > held, 'With focus edit mode captures the keyboard through ImGui.');
local count = steps();
pressed[ImGuiKey_RightArrow] = true; frame(); pressed[ImGuiKey_RightArrow] = nil;
assert(s.rolls.x == x0 + 1, 'Right arrow moves it 1 px.');
pressed[ImGuiKey_DownArrow] = true; frame(); pressed[ImGuiKey_DownArrow] = nil;
local y0 = s.rolls.y;
MOCK.key_shift = true;
pressed[ImGuiKey_LeftArrow] = true; frame(); pressed[ImGuiKey_LeftArrow] = nil;
assert(s.rolls.x == x0 + 1 - 10, 'Shift and an arrow move it 10 px.');
MOCK.key_shift = false;
pressed[ImGuiKey_UpArrow] = true; frame(); pressed[ImGuiKey_UpArrow] = nil;
assert(s.rolls.y == y0 - 1, 'Up moves it up.');
settle();
assert(steps() == count + 1, 'A quick run of arrow presses is one Undo step.');
pressed[ImGuiKey_RightArrow] = true; frame(); pressed[ImGuiKey_RightArrow] = nil;
settle();
assert(steps() == count + 2, 'A press after a pause is another.');
-- Not while typing in chat.
snapshot.chat_open = true; frame(0.2);
local typing_x = s.rolls.x;
pressed[ImGuiKey_RightArrow] = true; frame(); pressed[ImGuiKey_RightArrow] = nil;
assert(s.rolls.x == typing_x, 'Typing in chat, the keys stay with chat.');
snapshot.chat_open = false; frame(0.2);
-- The Grid box: a typed number takes once, on Enter or when the box loses focus, as one Undo step.
count = steps();
typing, typed['##edit_grid'] = true, 24; frame();
assert(e.grid == 16 and steps() == count, 'Typing a grid size changes nothing yet.');
left['##edit_grid'] = true; frame();
typing, typed['##edit_grid'], left['##edit_grid'] = false, nil, nil; frame();
assert(e.grid == 24 and steps() == count + 1, 'Enter or a click away sets it, as one Undo step: ' .. e.grid);
-- A step button takes as it is pressed, and is one Undo step once the mouse comes up.
MOCK.mouse_down, typed['##edit_grid'] = true, 25; frame();
assert(e.grid == 25 and steps() == count + 1, 'A click on a step button sets it at once.');
MOCK.mouse_down, typed['##edit_grid'], left['##edit_grid'] = false, nil, true; frame();
left['##edit_grid'] = nil; settle();
assert(e.grid == 25 and steps() == count + 2, 'After letting go of the step button it is one Undo step.');
-- Snap distance takes a typed number the same way, kept from 1 to 32.
typing, typed['##edit_snap_distance'] = true, 99; frame();
assert(e.snap_distance ~= 32 and steps() == count + 2, 'Typing a snap distance changes nothing yet.');
left['##edit_snap_distance'] = true; frame();
typing, typed['##edit_snap_distance'], left['##edit_snap_distance'] = false, nil, nil; frame();
assert(e.snap_distance == 32 and steps() == count + 3 and app.state.history[steps()].label == 'Snap distance',
    'Enter or a click away sets it, kept to 32, as one Undo step: ' .. e.snap_distance);

-- An anchored display keeps its anchor and moves away from it.
s.rolls.anchor = { to = 'screen', point = 'bottom_right', dx = -10, dy = -10, element = '', side = 'below', align = 'start', gap = 4, offset = 0 };
frame(); frame();
assert(elements.anchored('rolls'), 'Fixture: its anchor places it.');
local fallback_x = s.rolls.x;
pressed[ImGuiKey_LeftArrow] = true; frame(); pressed[ImGuiKey_LeftArrow] = nil;
assert(s.rolls.anchor.to == 'screen' and s.rolls.anchor.dx == -11 and s.rolls.x == fallback_x, 'A move changes its distance from the anchor, not its fallback spot.');
settle();
-- Still locked, the keys move it here.
assert(s.rolls.locked, 'Fixture: it is still locked.');
local dx = s.rolls.anchor.dx;
pressed[ImGuiKey_LeftArrow] = true; frame(); pressed[ImGuiKey_LeftArrow] = nil;
assert(s.rolls.anchor.dx == dx - 1 and s.rolls.locked, 'A locked display moves in edit mode, and stays locked.');
settle();
-- Its tick works in the bar while it is locked, as a tick moves nothing.
local locked_from, saved_from = steps(), saves;
MOCK.clicks['This display snaps##edit_grid_tick'] = true; frame();
assert(s.rolls.locked and not snap.ticked(s, 'rolls') and steps() == locked_from + 1 and saves == saved_from + 1,
    'A locked display\'s tick works in the bar, as one Undo step and a save.');
MOCK.clicks['This display snaps##edit_grid_tick'] = true; frame();
assert(snap.ticked(s, 'rolls') and steps() == locked_from + 2 and saves == saved_from + 2, 'And ticks it again.');
app.callbacks.save = save;

-- A panel that moves with another panel or the chat log is drawn where that puts it. Edit mode moves it from there as
-- one Undo step, and it keeps moving with it.
local debuffs = s.panels.self_debuffs;
debuffs.locked, debuffs.anchor = false, { to = 'element', element = 'self_buffs', side = 'below', align = 'start', gap = 4, offset = 0, point = 'top_left', dx = 0, dy = 0 };
debuffs.x, debuffs.y = 355, 120;
frame(); frame();
local own, attached = elements.drawn('self_buffs'), elements.drawn('self_debuffs');
assert(attached.x == own.x and attached.y == own.y + own.height + debuffs.anchor.gap and attached.x ~= 355,
    'Fixture: Moves with places it below Self buffs.');
local drawn_x, drawn_y = attached.x, attached.y;
MOCK.key_shift = false;
activate = 'self_debuffs'; frame();
assert(edit.selected() == 'self_debuffs', 'Fixture: it is picked.');
count = steps();
pressed[ImGuiKey_RightArrow] = true; frame(); pressed[ImGuiKey_RightArrow] = nil;
frame();
attached = elements.drawn('self_debuffs');
assert(debuffs.anchor.to == 'element' and debuffs.anchor.offset == 1 and debuffs.x == 355 and debuffs.y == 120 and attached.x == drawn_x + 1
    and attached.y == drawn_y, 'An arrow moves it 1 px from where it was drawn and it keeps following: ' .. attached.x .. ', ' .. attached.y);
settle();
assert(steps() == count + 1, 'as one Undo step.');
debuffs.anchor = { to = 'chat', element = '', side = 'above', align = 'start', gap = 4, offset = 0, point = 'top_left', dx = 0, dy = 0 };
debuffs.x, debuffs.y = 355, 120;
frame(); frame();
local docked = elements.drawn('self_debuffs');
assert(docked.x == MOCK.chat.x and docked.y == MOCK.chat.y - docked.height - 4, 'Fixture: Moves with places it above the chat log.');
drawn_x, drawn_y = docked.x, docked.y;
count = steps();
pressed[ImGuiKey_UpArrow] = true; frame(); pressed[ImGuiKey_UpArrow] = nil;
frame();
docked = elements.drawn('self_debuffs');
assert(debuffs.anchor.to == 'chat' and debuffs.anchor.gap == 5 and docked.x == drawn_x and docked.y == drawn_y - 1,
    'An arrow moves it from where it was drawn and it keeps following: ' .. docked.x .. ', ' .. docked.y);
settle();
assert(steps() == count + 1, 'as one Undo step.');
-- One its anchor puts past the screen's edge is drawn at the edge. A move starts from there, so an arrow away from the
-- edge moves it at once, and a drag stops at the edge, so the way back has no stretch where nothing moves.
local screen_width = require('imgui').GetIO().DisplaySize.x;
debuffs.anchor = { to = 'screen', point = 'top_right', dx = 50, dy = 40, element = '', side = 'below', align = 'start', gap = 4, offset = 0 };
frame(); frame();
local edge = elements.drawn('self_debuffs');
local edge_x = edge.x;
assert(elements.anchored('self_debuffs') and edge_x + edge.width == screen_width, 'Fixture: its anchor puts it past the right edge.');
count = steps();
pressed[ImGuiKey_LeftArrow] = true; frame(); pressed[ImGuiKey_LeftArrow] = nil;
frame();
assert(debuffs.anchor.dx == -1 and elements.drawn('self_debuffs').x == edge_x - 1,
    'An arrow away from the edge moves it at once: ' .. debuffs.anchor.dx);
settle();
assert(steps() == count + 1, 'as one Undo step.');
debuffs.anchor.dx = -20;
frame(); frame();
local near = elements.drawn('self_debuffs');
local near_x, near_y = near.x, near.y;
count = steps();
MOCK.key_shift, MOCK.mouse_down, MOCK.mouse_x, MOCK.mouse_y = true, true, near_x + 10, near_y + 10;
activate = 'self_debuffs'; frame();
MOCK.mouse_x = near_x + 110; frame();
assert(debuffs.anchor.dx == 0, 'A drag past the edge stops at it: ' .. debuffs.anchor.dx);
MOCK.mouse_x = near_x; frame(); frame();
assert(debuffs.anchor.dx == -30 and elements.drawn('self_debuffs').x == near_x - 10,
    'and moves back at once: ' .. debuffs.anchor.dx);
settle();
MOCK.key_shift = false;
assert(steps() == count + 1, 'as one Undo step.');
-- Undo steps are counted from none from here, as Undo keeps the last 20.
app.state.history, app.state.redo = {}, {};
debuffs.locked, debuffs.anchor = true, anchors.make();

-- A display drawn at a half pixel, anchored to the screen's center with an odd width: an arrow moves it exactly 1 px.
s.rolls.locked, s.rolls.width = false, 321;
s.rolls.anchor = { to = 'screen', point = 'center', dx = 0, dy = 0, element = '', side = 'below', align = 'start', gap = 4, offset = 0 };
activate = 'rolls'; frame(); frame();
local half = elements.drawn('rolls').x;
assert(edit.selected() == 'rolls' and half == 639.5, 'Fixture: Phantom Roll is picked, drawn at 639.5: ' .. half);
count = steps();
pressed[ImGuiKey_RightArrow] = true; frame(); pressed[ImGuiKey_RightArrow] = nil;
settle();
assert(elements.drawn('rolls').x == half + 1 and steps() == count + 1,
    'At a half pixel the right arrow moves it 1 px, as one Undo step: ' .. elements.drawn('rolls').x);
pressed[ImGuiKey_LeftArrow] = true; frame(); pressed[ImGuiKey_LeftArrow] = nil;
settle();
assert(elements.drawn('rolls').x == half and steps() == count + 2, 'And the left arrow moves it back 1 px, as one Undo step.');
-- The Grid box's Escape changes nothing.
local grid_now = e.grid;
typing, typed['##edit_grid'] = true, 40; frame();
typed['##edit_grid'], left['##edit_grid'] = nil, true; frame();
typing, left['##edit_grid'] = false, nil; frame();
assert(e.grid == grid_now and steps() == count + 2, 'Escape in Grid changes nothing.');
s.rolls.locked = true;

-- A display placed on the screen but drawn at a half pixel: the alert notices at 579.5. An arrow moves the number on its
-- Size and place tab by exactly one each way, as one Undo step, and it lands on a whole pixel.
local function pick(id)
    activate = id; frame(); frame();
    assert(edit.selected() == id, 'Fixture: ' .. id .. ' is picked.');
end;
local function arrow(key) pressed[key] = true; frame(); pressed[key] = nil; frame(); end;
local half_cases = {
    { 'notices', 'The notices at a half pixel', 579.5, function()
        s.alerts.notice_locked, s.alerts.notice_x, s.alerts.notice_width = false, 579.5, 441;
    end },
};
for _, case in ipairs(half_cases) do
    local id, name, half, setup = case[1], case[2], case[3], case[4];
    for _, move in ipairs({
        { 'The right arrow', 1, function() arrow(ImGuiKey_RightArrow); end },
        { 'The left arrow', -1, function() arrow(ImGuiKey_LeftArrow); end },
    }) do
        setup(); frame(); frame();
        pick(id);
        local spot = half + 0.5;
        assert(elements.drawn(id).x == half, 'Fixture: ' .. name .. ' is drawn at ' .. half .. ': ' .. elements.drawn(id).x);
        app.state.history, app.state.redo = {}, {};
        move[3]();
        settle();
        local x = elements.drawn(id).x;
        assert(x == spot + move[2] and steps() == 1,
            name .. ': ' .. move[1] .. ' moves its number by exactly ' .. move[2] .. ' and puts it there, as one Undo step: ' .. x .. ', ' .. steps());
    end;
end;
-- A plain drag lands on the whole pixel nearest where the mouse puts it. The notices dragged 37.3 px from 579.5, to
-- 616.8, land on 617; dragged 37 px, to 616.5, half way between two, on the one to the right, as from a whole pixel.
-- A drag that snaps an edge to a whole line lands on that line.
local grid_was = e.grid;
local function drag(by, ticked)
    half_cases[1][4]();
    snap.tick(s, 'notices', ticked);
    e.snap_grid, e.grid = ticked, 16;
    frame(); frame();
    pick('notices');
    local from = elements.drawn('notices');
    MOCK.key_shift, MOCK.mouse_down, MOCK.mouse_x, MOCK.mouse_y = true, true, from.x + 10, from.y + 10;
    activate = 'notices'; frame();
    MOCK.mouse_x = from.x + 10 + by; frame();
    settle();
    MOCK.key_shift = false;
    snap.tick(s, 'notices', false);
    e.snap_grid, e.grid = false, grid_was;
    return elements.drawn('notices').x, s.alerts.notice_x;
end;
for _, case in ipairs({ { 37.3, 617 }, { 37, 617 } }) do
    local x, saved = drag(case[1], false);
    assert(x == case[2] and saved == case[2], 'A plain drag of ' .. case[1] .. ' px from 579.5 lands on ' .. case[2] .. ': ' .. x .. ', ' .. tostring(saved));
end;
local x, saved = drag(37, true);
assert(x == 615 and saved == 615, 'Dragged 37 px to 616.5 on a 16 px grid, its right edge snaps to the line at 1056: ' .. x);
s.alerts.notice_locked, debuffs.locked = true, true;

-- Across at Centered stays Centered while a move doesn't go across: an arrow up or down, or a drag straight down. So
-- does an Across typed past the screen's edge, kept for a bigger screen. A drag across and back to where it started
-- puts Centered back.
s.alerts.notice_locked, s.alerts.notice_x, s.alerts.notice_width = false, -1, 440;
frame(); frame();
pick('notices');
local notice_y = s.alerts.notice_y;
app.state.history, app.state.redo = {}, {};
arrow(ImGuiKey_DownArrow);
settle();
assert(s.alerts.notice_x == -1 and s.alerts.notice_y == notice_y + 1 and elements.drawn('notices').x == 580 and steps() == 1,
    'Down moves the notices 1 px, as one Undo step, and Across stays Centered: ' .. s.alerts.notice_x .. ', ' .. s.alerts.notice_y);
s.alerts.notice_locked = true;
s.ready_pulse.enabled, s.ready_pulse.spot, s.ready_pulse.locked, s.ready_pulse.x = true, 'screen', false, -1;
pick('pulse');
local pulse_y = s.ready_pulse.y;
arrow(ImGuiKey_UpArrow);
settle();
assert(s.ready_pulse.x == -1 and s.ready_pulse.y == pulse_y - 1 and elements.drawn('pulse').x == 768,
    'Up moves the ready pulse 1 px and Across stays Centered: ' .. s.ready_pulse.x .. ', ' .. s.ready_pulse.y);
local spot = elements.drawn('pulse');
pulse_y = s.ready_pulse.y;
MOCK.key_shift, MOCK.mouse_down, MOCK.mouse_x, MOCK.mouse_y = true, true, spot.x + 10, spot.y + 10;
activate = 'pulse'; frame();
MOCK.mouse_y = spot.y + 50; frame();
settle();
assert(s.ready_pulse.x == -1 and s.ready_pulse.y == pulse_y + 40,
    'A drag straight down moves the pulse down and Across stays Centered: ' .. s.ready_pulse.x .. ', ' .. s.ready_pulse.y);
spot = elements.drawn('pulse');
MOCK.mouse_down, MOCK.mouse_x, MOCK.mouse_y = true, spot.x + 10, spot.y + 10;
activate = 'pulse'; frame();
MOCK.mouse_x = spot.x + 30; frame();
assert(s.ready_pulse.x == 788, 'Fixture: the drag moves the pulse across: ' .. s.ready_pulse.x);
MOCK.mouse_x = spot.x + 10; frame();
settle();
MOCK.key_shift = false;
assert(s.ready_pulse.x == -1 and elements.drawn('pulse').x == 768,
    'A drag across and back to where it started puts Centered back: ' .. s.ready_pulse.x);
s.ready_pulse.enabled, s.ready_pulse.locked = false, true;
local pet_x, pet_y = s.pet.x, s.pet.y;
s.pet.locked, s.pet.x = false, 5000;
frame(); frame();
pick('pet');
arrow(ImGuiKey_DownArrow);
settle();
assert(s.pet.x == 5000 and s.pet.y == pet_y + 1 and elements.drawn('pet').x == 1600 - elements.drawn('pet').width,
    'Down keeps an Across typed past the screen\'s edge: ' .. s.pet.x .. ', ' .. s.pet.y);
s.pet.locked, s.pet.x, s.pet.y = true, pet_x, pet_y;
-- At Size 0.85, as a save writes it and a load reads it back, the pulse at an Across typed past the screen's edge is
-- drawn at a fraction of a pixel. A drag straight down from a whole pixel, as a mouse gives, keeps that Across, and a
-- drag straight across keeps a Down typed past the bottom edge. So does a drag straight down with the pulse ticked for
-- Snap while moving, sitting on the screen's edge it snaps to. A drag right and down pushes into the edge it sits on, so it
-- goes across and Across becomes where the pulse is drawn.
local scale = s.style.scale;
local function drag_pulse(by_x, by_y)
    frame(); frame();
    local from = elements.drawn('pulse');
    MOCK.key_shift, MOCK.mouse_down, MOCK.mouse_x, MOCK.mouse_y = true, true, math.floor(from.x) + 10, math.floor(from.y) + 10;
    activate = 'pulse'; frame();
    MOCK.mouse_x, MOCK.mouse_y = MOCK.mouse_x + by_x, MOCK.mouse_y + by_y; frame();
    settle();
    MOCK.key_shift = false;
end;
s.style.scale = tonumber(string.format('%.14g', 0.85000002384185791015625));
s.ready_pulse.enabled, s.ready_pulse.locked, s.ready_pulse.x, s.ready_pulse.y = true, false, 5000, 260;
frame(); frame();
local fraction = elements.drawn('pulse').x;
assert(fraction ~= math.floor(fraction), 'Fixture: at Size 0.85 the pulse is drawn at a fraction of a pixel: ' .. fraction);
drag_pulse(0, 40);
assert(s.ready_pulse.x == 5000 and s.ready_pulse.y == 300 and elements.drawn('pulse').x == fraction,
    'At Size 0.85 a drag straight down keeps an Across typed past the screen\'s edge: ' .. s.ready_pulse.x .. ', ' .. s.ready_pulse.y);
s.ready_pulse.x, s.ready_pulse.y = 300, 5000;
drag_pulse(40, 0);
assert(s.ready_pulse.x == 340 and s.ready_pulse.y == 5000,
    'At Size 0.85 a drag straight across keeps a Down typed past the screen\'s edge: ' .. s.ready_pulse.x .. ', ' .. s.ready_pulse.y);
snap.tick(s, 'pulse', true);
e.snap_screen = true;
assert(snap.on(s, 'pulse'), 'Fixture: Snap while moving is on and the pulse is ticked for it.');
s.ready_pulse.x, s.ready_pulse.y = 5000, 260;
drag_pulse(0, 40);
snap.tick(s, 'pulse', false);
e.snap_screen = false;
assert(s.ready_pulse.x == 5000 and s.ready_pulse.y == 300,
    'Ticked to snap, on the screen\'s edge it snaps to, a drag straight down at Size 0.85 keeps that Across: ' .. s.ready_pulse.x);
s.style.scale = scale;
s.ready_pulse.x, s.ready_pulse.y = 5000, 260;
drag_pulse(20, 40);
assert(s.ready_pulse.x == 1536 and s.ready_pulse.y == 300 and elements.drawn('pulse').x == 1536,
    'A drag right and down that pushes into the edge sets Across to where the pulse is drawn: ' .. s.ready_pulse.x);
s.ready_pulse.enabled, s.ready_pulse.locked, s.ready_pulse.x, s.ready_pulse.y = false, true, -1, 260;
-- At Size 1.3 as a save writes it and a load reads it back, on a 1366 by 768 screen, the notices at a Down typed past
-- the bottom edge are drawn at 508 and a fraction. Ticked to snap with Screen edges on, a drag 40 across and 4
-- down pushes them into that edge, and the snap puts them back on it. So the move down is the mouse's 4 plus the
-- snap's -4, which is 0, and Down stays, as the notices' own move keeps it. From 508 and a fraction, 4 down crosses
-- 512, where the sum rounds, so a move worked out as where they land less where they started comes out just off 0.
local kept_alerts = store.copy(s.alerts);
s.style.scale, MOCK.screen = tonumber(string.format('%.14g', 1.2999999523162842)), { 1366, 768 };
s.alerts.notice_locked, s.alerts.notice_x, s.alerts.notice_y, s.alerts.notice_width, s.alerts.notice_height = false, 300, 5000, 300, 200;
snap.tick(s, 'notices', true);
e.snap_screen = true;
assert(snap.on(s, 'notices'), 'Fixture: Snap while moving is on and the notices are ticked for it.');
frame(); frame();
local low = elements.drawn('notices').y;
assert(low > 508 and low < 509 and low + 4 - 4 ~= low,
    'Fixture: the notices are drawn at 508 and a fraction, where 4 down and back up rounds: ' .. low);
MOCK.key_shift, MOCK.mouse_down, MOCK.mouse_x, MOCK.mouse_y = true, true, 330, math.floor(low) + 30;
activate = 'notices'; frame();
MOCK.mouse_x, MOCK.mouse_y = MOCK.mouse_x + 40, MOCK.mouse_y + 4; frame();
settle();
MOCK.key_shift = false;
snap.tick(s, 'notices', false);
e.snap_screen = false;
assert(s.alerts.notice_x == 340 and s.alerts.notice_y == 5000 and elements.drawn('notices').y == low,
    'A drag across and 4 px into the bottom edge, which the snap takes back, keeps a Down typed past that edge: '
    .. s.alerts.notice_x .. ', ' .. s.alerts.notice_y);
s.style.scale, MOCK.screen = scale, nil;
s.alerts.notice_locked, s.alerts.notice_x, s.alerts.notice_y = kept_alerts.notice_locked, kept_alerts.notice_x, kept_alerts.notice_y;
s.alerts.notice_width, s.alerts.notice_height = kept_alerts.notice_width, kept_alerts.notice_height;

-- Escape while typing in Grid only puts the box's number back: nothing moves or changes, with no Undo step, and edit
-- mode stays on. Escape lets go of the box on the frame it is pressed, and an Escape on the next frame ends edit mode,
-- as Escape does when no box has the keys.
pick('rolls');
s.rolls.locked = false;
local kept_rolls, kept_grid = store.copy(s.rolls), e.grid;
app.state.history, app.state.redo = {}, {};
typing, typed['##edit_grid'] = true, 333; frame();
pressed[ImGuiKey_Escape], typed['##edit_grid'], left['##edit_grid'] = true, nil, true; frame();
assert(edit.active(), 'Fixture: the first Escape leaves edit mode on.');
pressed[ImGuiKey_Escape], typing, left['##edit_grid'] = nil, false, nil; frame();
assert(edit.active() and store.equal(kept_rolls, s.rolls) and e.grid == kept_grid and steps() == 0,
    'Escape while typing in Grid only puts its number back, and edit mode stays on.');
typing, typed['##edit_grid'] = true, 333; frame();
pressed[ImGuiKey_Escape], typed['##edit_grid'], left['##edit_grid'] = true, nil, true; frame();
assert(edit.active(), 'Fixture: the first Escape leaves edit mode on.');
typing, left['##edit_grid'] = false, nil; frame();
pressed[ImGuiKey_Escape] = nil;
assert(not edit.active() and steps() == 0, 'An Escape on the next frame ends edit mode.');
command('/vg edit on'); frame();
s.rolls.locked = true;

-- The strips move by their offset from the game's party window.
local strip_from = edit._capture(s, 'strip_1', { x = 1500, y = 800, width = 180, height = 40 }, {});
assert(strip_from.kind == 'strip', 'A strip beside the game\'s party list moves by its offset.');
assert(edit._apply(s, strip_from, -12, 7, { x = 1600, y = 900 }) and s.party_ui.groups[1].native_x == -12 and s.party_ui.groups[1].native_y == 7,
    'Its offset moves.');

-- The Escape that closes the bar's Pick a display list ends nothing else. ImGui closes the list on that Escape before
-- edit mode sees the key, so it was open the frame before.
local open_list, begin_combo = false, imgui.BeginCombo;
rawset(imgui, 'BeginCombo', function(label, ...)
    if label == '##edit_pick' and open_list then return true; end
    return begin_combo(label, ...);
end);
focused, open_list = true, true; frame();
open_list, pressed[ImGuiKey_Escape] = false, true; frame(); pressed[ImGuiKey_Escape] = nil;
assert(edit.active(), 'The Escape that closes the list leaves edit mode on.');
frame();
rawset(imgui, 'BeginCombo', begin_combo);

-- Escape while it has focus ends it, leaving every display where it is.
local kept = store.copy(s);
pressed[ImGuiKey_Escape] = true; frame(); pressed[ImGuiKey_Escape] = nil;
assert(not edit.active(), 'Escape with focus ends edit mode.');
assert(store.equal(kept.rolls, s.rolls) and store.equal(kept.panels, s.panels), 'Every display stays where it is.');
frame();
assert(not began('Arrange on screen##vantage_edit_bar') and not app.callbacks.editing, 'The bar is gone.');
-- Escape without focus does nothing to edit mode; Done ends it too.
command('/vg edit on'); focused = false;
pressed[ImGuiKey_Escape] = true; frame(); pressed[ImGuiKey_Escape] = nil;
assert(edit.active(), 'Without focus Escape goes to the game.');
MOCK.clicks['Done##edit_done'] = true; frame();
assert(not edit.active(), 'Done ends it.');
command('/vg edit on'); command('/vg edit off');
assert(not edit.active() and MOCK.printed[#MOCK.printed]:find('stays where it is', 1, true), '/vg edit off ends it.');
command('/vg edit sideways');
assert(MOCK.printed[#MOCK.printed]:find('Usage: /vg edit', 1, true), 'A wrong word gets the usage line.');
-- The main page's button.
app.state.settings.window.open, app.state.settings.window.tab = true, 'Home';
MOCK.clicks['Arrange on screen##main'] = true;
frame(); frame();
assert(edit.active(), 'The main page\'s Edit mode button turns it on.');
assert(#MOCK.commands == 0, 'Nothing is sent to the game.');
-- Where the settings window reaches both the top middle and the bottom middle, as its first spot does on a 1280x720
-- screen, the bar takes focus as it opens, which brings it in front of the window, and a click on the window leaves
-- the bar in front. The window comes in front as it appears, with the bar in front of it the same frame, and a window
-- that comes to cover the bar during a drag has it come forward once the mouse is up. Where the bottom middle is
-- clear, the bar opens as before and the window comes forward when clicked.
local function fronted()
    local asked = false;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'SetNextWindowFocus' then asked = true;
        elseif call[1] == 'Begin' then
            if call[2] == 'Arrange on screen##vantage_edit_bar' then return asked, call[4]; end;
            asked = false;
        end;
    end;
    return false;
end;
local bit = require('bit');
local function window_flags() return select(2, began('Vantage##settings')) or 0; end;
local function in_front() return bit.band(window_flags(), ImGuiWindowFlags_NoBringToFrontOnFocus) == 0; end;
local place = app.state.settings.window;
place.x, place.y, place.width, place.height = 20, 20, 1400, 860;
command('/vg edit off'); frame(); command('/vg edit on'); frame();
local asked, bar_flags = fronted();
assert(asked and bit.band(bar_flags, ImGuiWindowFlags_NoFocusOnAppearing) ~= 0 and edit.covered(),
    'With no spot clear of the settings window, the bar comes in front of it as it opens.');
-- The window's page ends above the bar's top, so its last rows can scroll out from under it.
assert(edit.covered_top() and edit.covered_top() <= 900 - 6 - 3 * 26, 'While it covers the window, the bar says where its top is.');
frame();
assert(not fronted() and not in_front(), 'After that a click on the window leaves the bar in front.');
place.open = false; frame();
place.open = true; frame(); frame();
assert(began('Vantage##settings') and in_front() and fronted(), 'The window comes in front as it appears, and the bar in front of it.');
frame();
assert(not fronted() and not in_front(), 'The frame after, the bar stays in front.');
place.height = 300; frame();
assert(not edit.covered() and not edit.covered_top(), 'A shorter window leaves the bottom middle clear.');
MOCK.mouse_down = true;
place.height = 860; frame();
assert(edit.covered() and not fronted(), 'While a drag on the window goes on, the bar waits.');
MOCK.mouse_down = false; frame();
assert(fronted(), 'Once the mouse is up the bar comes forward.');
frame();
assert(not fronted(), 'It comes forward once.');
place.width, place.height = 900, 300;
command('/vg edit off'); frame(); command('/vg edit on'); frame();
assert(not fronted() and not edit.covered(), 'With the bottom middle clear, the bar takes no focus as it opens.');
frame();
assert(in_front(), 'And a click brings the window forward as before.');
-- The bar's look is the settings window's, kept until the settings count a change, past half a second too.
local theme = require('ui.theme');
local made, window_defaults = 0, theme.window_defaults;
theme.window_defaults = function(...) made = made + 1; return window_defaults(...); end;
frame(0.7); frame(0.7);
theme.window_defaults = window_defaults;
assert(edit.active() and made == 0, 'With no change, the bar\'s look isn\'t made again: ' .. made);
MOCK.key_shift, focused = false, false;
for _, name in ipairs({ 'GetBackgroundDrawList', 'GetForegroundDrawList', 'InvisibleButton', 'IsItemActivated', 'IsWindowFocused', 'IsKeyPressed',
    'SetNextFrameWantCaptureKeyboard', 'InputInt', 'IsItemActive', 'IsItemDeactivatedAfterEdit', 'Begin', 'End', 'GetWindowDrawList' }) do
    rawset(imgui, name, nil);
end;
rawset(imgui, 'GetIO', io);
MOCK.fire('unload');
return true;
