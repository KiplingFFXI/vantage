-- Edit mode (ui/edit_mode.lua) through vantage.lua: /vg edit and the Home and bar buttons turn it on and off, and
-- ending it leaves every display where it is. Each display on the screen gets an outline that a click picks. A Shift
-- drag moves an unlocked display, snapping as chosen; without Shift nothing moves, and Shift never moves a locked one.
-- A locked display is unlocked in the bar. While the bar or an outline has focus, the arrow keys move the picked
-- display 1 px, 10 with Shift, and Escape ends edit mode; the keys are captured only then, through ImGui's own flag,
-- and the bar doesn't take focus as it opens. The Grid box takes a typed number on Enter or when it loses focus, a step
-- button at once, and Escape there only puts its number back, so the next Escape ends edit mode. A typed spot is on the
-- Size and place tab. Each move is one Undo step, and lands a display drawn at a half pixel on a whole one. A display that moves
-- with something keeps following it. Overhead icons aren't in edit mode.
-- With Grid mode on the bar holds the picked display's tick for it, the one on the main page, locked or not, and
-- the Grid box and the snapping switches; with it off, none of them.
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
assert(not began('Vantage edit mode##vantage_edit_bar') and not began('##vantage_edit_rolls'), 'Edit mode starts off.');
command('/vg edit');
assert(edit.active() and MOCK.printed[#MOCK.printed]:find('Edit mode is on', 1, true), '/vg edit turns it on.');
frame();
local shows, bar_flags = began('Vantage edit mode##vantage_edit_bar');
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
-- Each outline's name is drawn at 14 px, and its box is as wide as the name at that size, whatever size the window's
-- font is: here 28 px, where the name measures twice as wide.
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
        local width = edge[3][1] - edge[2][1];
        assert(box[3][1] - edge[2][1] == math.min(width - 1, #text[6] * 8 * 14 / 28 + 7), 'The tag fits its name: ' .. text[6]);
        tags = tags + 1;
    end;
end;
assert(tags >= 5, 'Fixture: every outline has its tag.');
assert(app.callbacks.editing, 'The displays are told edit mode is on.');
local start_x, start_y = s.rolls.x, s.rolls.y;

-- A click picks a display; without Shift nothing moves.
MOCK.key_shift = false;
local rect = elements.drawn('rolls');
MOCK.mouse_x, MOCK.mouse_y, MOCK.mouse_down = rect.x + 10, rect.y + 10, true;
activate = 'rolls'; frame();
assert(edit.selected() == 'rolls', 'A click on its outline picks it.');
local plain = edit._message();
assert(plain == 'Phantom Roll is locked. Unlock it here to move it.', 'A click on a locked display says it is locked: ' .. tostring(plain));
boxes = {}; frame();
local bar_buttons = {};
for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Button' then bar_buttons[#bar_buttons + 1] = call[2]; end; end;
assert(not boxes['X##edit_x'] and not boxes['Y##edit_y'] and not boxes['W##edit_w'] and not boxes['H##edit_h']
    and not table.concat(bar_buttons, '|'):find('edit_bar_side', 1, true), 'The bar has no typed spot, which is on Place, and it stays at the top.');
MOCK.mouse_x = rect.x + 90; frame();
assert(s.rolls.x == start_x and s.rolls.y == start_y and steps() == 0, 'A drag without Shift moves nothing.');
settle();
-- Shift never moves a locked display.
assert(s.rolls.locked, 'Fresh displays are locked.');
MOCK.key_shift, MOCK.mouse_down, MOCK.mouse_x = true, true, rect.x + 10;
activate = 'rolls'; frame();
MOCK.mouse_x, MOCK.mouse_y = rect.x + 120, rect.y + 60; frame();
assert(s.rolls.x == start_x and s.rolls.y == start_y and steps() == 0 and edit._gesture() == nil, 'Shift never moves a locked display.');
assert(edit._message():find('locked', 1, true), 'It says it is locked.');
assert(edit._message() == plain, 'The same as a click without Shift.');
settle();
-- The arrow keys don't move it either.
focused = true;
pressed[ImGuiKey_RightArrow] = true; frame(); pressed[ImGuiKey_RightArrow] = nil;
assert(s.rolls.x == start_x and steps() == 0, 'The keys don\'t move a locked display.');
focused = false;
-- Unlocked in the bar, as one Undo step.
MOCK.key_shift = false;
MOCK.clicks['Locked##edit_lock'] = true; frame();
assert(s.rolls.locked == false and steps() == 1 and app.state.history[1].label == 'Unlock Phantom Roll', 'The bar unlocks it.');
-- Unlocked, a drag without Shift still moves nothing.
MOCK.key_shift, MOCK.mouse_down, MOCK.mouse_x, MOCK.mouse_y = false, true, rect.x + 10, rect.y + 10;
activate = 'rolls'; frame();
MOCK.mouse_x = rect.x + 90; frame();
assert(s.rolls.x == start_x and s.rolls.y == start_y and steps() == 1, 'Unlocked, a drag without Shift moves nothing.');
assert(edit._message():find('Hold Shift', 1, true) and edit._gesture() == nil, 'The bar says to hold Shift.');
settle();

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
assert(steps() == 2 and app.state.history[2].label == 'Move Phantom Roll', 'The drag is one Undo step.');
command('/vg undo');
assert(app.state.settings.rolls.x == start_x and app.state.settings.rolls.y == start_y, 'Undo puts it back.');
command('/vg redo');
s = app.state.settings; e = s.edit_mode;
assert(s.rolls.x == start_x + 50, 'Redo moves it again.');
frame();
-- While Grid mode is off the bar has no tick for it, no Grid box and no snapping switches. With it on the bar has the
-- picked display's tick, the one on the main page: a click on either is one Undo step and a save.
local function checkbox(label)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Checkbox' and call[2] == label then return call[3][1]; end; end;
    return nil;
end;
boxes = {}; frame();
assert(e.grid_mode == false and checkbox('Use Grid mode##edit_grid_tick') == nil and boxes['##edit_grid'] == nil
    and checkbox('Grid##edit_snap_grid') == nil, 'Grid mode off, the bar has no tick, no Grid box and no snapping switches.');
e.grid_mode = true;
boxes = {}; frame();
assert(checkbox('Use Grid mode##edit_grid_tick') == false and boxes['##edit_grid'] == 16 and checkbox('Grid##edit_snap_grid') == false,
    'Grid mode on, the bar has the picked display\'s tick, the Grid box and the snapping switches.');
local saves, save = 0, app.callbacks.save;
app.callbacks.save = function(...) saves = saves + 1; return save(...); end;
local ticked_from = steps();
MOCK.clicks['Use Grid mode##edit_grid_tick'] = true; frame();
assert(snap.ticked(s, 'rolls') and steps() == ticked_from + 1 and app.state.history[steps()].label == 'Tick Phantom Roll for Grid mode'
    and saves == 1, 'The bar ticks Phantom Roll for Grid mode, as one Undo step and a save: ' .. (steps() - ticked_from) .. ', ' .. saves);
-- Shift held hides the settings window.
MOCK.key_shift = false;
s.window.open, s.window.tab = true, 'Home';
frame(); frame();
assert(checkbox('Phantom Roll##grid_tick_rolls') == true, 'The main page shows the same tick.');
MOCK.clicks['Phantom Roll##grid_tick_rolls'] = true; frame();
assert(not snap.ticked(s, 'rolls') and steps() == ticked_from + 2 and app.state.history[steps()].label == 'Untick Phantom Roll for Grid mode'
    and saves == 2, 'The page unticks it, as one Undo step and a save: ' .. (steps() - ticked_from) .. ', ' .. saves);
frame();
assert(checkbox('Use Grid mode##edit_grid_tick') == false, 'The bar shows the same tick.');
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
-- A step button takes as it is pressed, and letting go adds nothing.
MOCK.mouse_down, typed['##edit_grid'] = true, 25; frame();
assert(e.grid == 25 and steps() == count + 2, 'A click on a step button sets it at once, as one Undo step.');
MOCK.mouse_down, typed['##edit_grid'], left['##edit_grid'] = false, nil, true; frame();
left['##edit_grid'] = nil; frame();
assert(e.grid == 25 and steps() == count + 2, 'Letting go of the step button adds nothing.');

-- An anchored display keeps its anchor and moves away from it.
s.rolls.anchor = { to = 'screen', point = 'bottom_right', dx = -10, dy = -10, element = '', side = 'below', align = 'start', gap = 4, offset = 0 };
frame(); frame();
assert(elements.anchored('rolls'), 'Fixture: its anchor places it.');
local fallback_x = s.rolls.x;
pressed[ImGuiKey_LeftArrow] = true; frame(); pressed[ImGuiKey_LeftArrow] = nil;
assert(s.rolls.anchor.to == 'screen' and s.rolls.anchor.dx == -11 and s.rolls.x == fallback_x, 'A move changes its distance from the anchor, not its fallback spot.');
settle();
-- Locked again in the bar, the keys stop.
MOCK.clicks['Locked##edit_lock'] = true; frame();
assert(s.rolls.locked, 'The bar locks it again.');
local dx = s.rolls.anchor.dx;
pressed[ImGuiKey_LeftArrow] = true; frame(); pressed[ImGuiKey_LeftArrow] = nil;
assert(s.rolls.anchor.dx == dx, 'A locked display stays.');
settle();
-- Its tick works in the bar while it is locked, as a tick moves nothing.
local locked_from, saved_from = steps(), saves;
MOCK.clicks['Use Grid mode##edit_grid_tick'] = true; frame();
assert(s.rolls.locked and not snap.ticked(s, 'rolls') and steps() == locked_from + 1 and saves == saved_from + 1,
    'A locked display\'s tick works in the bar, as one Undo step and a save.');
MOCK.clicks['Use Grid mode##edit_grid_tick'] = true; frame();
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

-- Escape while it has focus ends it, leaving every display where it is.
local kept = store.copy(s);
pressed[ImGuiKey_Escape] = true; frame(); pressed[ImGuiKey_Escape] = nil;
assert(not edit.active(), 'Escape with focus ends edit mode.');
assert(store.equal(kept.rolls, s.rolls) and store.equal(kept.panels, s.panels), 'Every display stays where it is.');
frame();
assert(not began('Vantage edit mode##vantage_edit_bar') and not app.callbacks.editing, 'The bar is gone.');
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
MOCK.clicks['Edit mode##main'] = true;
frame(); frame();
assert(edit.active(), 'The main page\'s Edit mode button turns it on.');
assert(#MOCK.commands == 0, 'Nothing is sent to the game.');
MOCK.key_shift, focused = false, false;
for _, name in ipairs({ 'GetBackgroundDrawList', 'GetForegroundDrawList', 'InvisibleButton', 'IsItemActivated', 'IsWindowFocused', 'IsKeyPressed',
    'SetNextFrameWantCaptureKeyboard', 'InputInt', 'IsItemActive', 'IsItemDeactivatedAfterEdit' }) do rawset(imgui, name, nil); end;
rawset(imgui, 'GetIO', io);
MOCK.fire('unload');
return true;
