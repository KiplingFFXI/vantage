-- Each display's own Shift drag, through the real vantage.lua, snaps as edit mode's drag does (ui/snap.lua), by the
-- snapping switches: a timer panel and the alert notices (ui/hud.lua), the party cooldown list
-- (ui/cooldown_list.lua), the Phantom Roll and pet displays (ui/element_box.lua), the ready pulse's screen spot
-- (ui/ready_pulse.lua) and a party list strip, beside the game's party list or in a panel of its own
-- (ui/native_party_hud.lua). Only a display ticked for Grid mode snaps, and only while Grid mode is on: until then,
-- and for a display not ticked, a drag follows the pointer exactly with no grid and no line, in edit mode too, which
-- draws no grid of its own. A move snaps its nearest edge, a resize only the edge it pulls. While a ticked display's
-- drag is under way the grid shows behind every display with Show the grid on, and the line it snapped to over them;
-- both go when the drag ends. With every switch off a drag follows the pointer exactly, and a locked display never
-- moves. The displays not dragged stay where they are. The game's party list is read from the press that may start a
-- Shift drag, with Grid mode on and a display ticked for it unlocked, so a drag snaps to it from its first move, and
-- not while Shift is only held. Only the client readers, the game's party list, the chat log and the mouse are
-- fixtures.
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

-- The mouse, each window's place, the areas the displays take a drag in, and the lines drawn behind and over them.
local imgui = require('imgui');
local mouse = { x = -1, y = -1, down = false, pressed = false };
local function inside(rect)
    return mouse.x >= rect.x and mouse.x < rect.x + rect.width and mouse.y >= rect.y and mouse.y < rect.y + rect.height;
end;
local begin, next_pos, next_size = imgui.Begin, imgui.SetNextWindowPos, imgui.SetNextWindowSize;
local place, size, window, cursor, item, active = { 0, 0 }, { 0, 0 }, { x = 0, y = 0 }, { 0, 0 }, nil, nil;
local items = {};
rawset(imgui, 'SetNextWindowPos', function(value, ...) place = { value[1], value[2] }; return next_pos(value, ...); end);
rawset(imgui, 'SetNextWindowSize', function(value, ...) size = { value[1], value[2] }; return next_size(value, ...); end);
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
local function across(list, x)
    for _, line in ipairs(list) do if line[1] == x and line[2] == 0 and line[3] == x and line[4] == 900 then return true; end; end;
    return false;
end;
local function down(list, y)
    for _, line in ipairs(list) do if line[1] == 0 and line[2] == y and line[3] == 1600 and line[4] == y then return true; end; end;
    return false;
end;
-- The grid on the 1600 x 900 screen: a line every 16 px across (99) and down (56), and the two middle lines.
local function grid(list) return #list == 99 + 56 + 2 and across(list, 16) and down(list, 16) and across(list, 800) and down(list, 450); end;

local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local s = app.state.settings;
local elements = require('ui.elements');
MOCK.key_shift = true;
MOCK.chat = { x = 0, y = 700, width = 600, height = 200 };
-- Every display on, unlocked and apart: Self buffs, the notices (a test notice), the cooldown list, the Phantom Roll
-- and pet displays (samples), the pulse's screen spot and the party strip (samples) beside the game's party list.
for key, panel in pairs(s.panels) do panel.enabled = key == 'self_buffs'; end;
s.panels.self_buffs.locked, s.panels.self_buffs.x, s.panels.self_buffs.y = false, 64, 96;
s.alerts.notice_locked, s.alerts.notice_x, s.alerts.notice_y, s.alerts.notice_width = false, 496, 96, 300;
s.party_cooldowns.enabled, s.party_cooldowns.preview = true, true;
s.party_cooldowns.list.enabled, s.party_cooldowns.list.locked, s.party_cooldowns.list.x, s.party_cooldowns.list.y = true, false, 896, 96;
s.rolls.enabled, s.rolls.preview, s.rolls.locked, s.rolls.x, s.rolls.y = true, true, false, 64, 400;
s.pet.enabled, s.pet.preview, s.pet.locked, s.pet.x, s.pet.y = true, true, false, 496, 400;
s.ready_pulse.enabled, s.ready_pulse.spot, s.ready_pulse.locked, s.ready_pulse.x, s.ready_pulse.y = true, 'screen', false, 1296, 96;
s.party_ui.enabled, s.party_ui.preview, s.party_ui.locked = true, true, false;
local rule = require('ui.defaults').rule('notice');
rule.chat, rule.sound, rule.duration = false, '', 30;
app.callbacks.test_alert(rule);
for _ = 1, 6 do frame(0.2); end;

local SWITCHES = { 'snap_grid', 'snap_screen', 'snap_elements', 'snap_party', 'snap_chat' };
local function only(switch) for _, name in ipairs(SWITCHES) do s.edit_mode[name] = name == switch; end; end;
local function all(on) for _, name in ipairs(SWITCHES) do s.edit_mode[name] = on; end; end;
local displays = {
    { name = 'Self buffs', hit = '##move_self_buffs', resizes = true, lock = function(value) s.panels.self_buffs.locked = value; end },
    { name = 'Alert notices', hit = '##notice_layout', resizes = true, lock = function(value) s.alerts.notice_locked = value; end },
    { name = 'Party cooldowns', hit = '##cooldown_list_layout', resizes = true,
        lock = function(value) s.party_cooldowns.list.locked = value; end },
    { name = 'Phantom Roll', hit = '##vantage_rolls_layout', resizes = true, lock = function(value) s.rolls.locked = value; end },
    { name = 'Pet', hit = '##vantage_pet_layout', resizes = true, lock = function(value) s.pet.locked = value; end },
    { name = 'Ready pulse', hit = '##ready_pulse_spot', lock = function(value) s.ready_pulse.locked = value; end },
    { name = 'Party strip', hit = '##native_move_1', lock = function(value) s.party_ui.locked = value; end },
};
for _, display in ipairs(displays) do assert(items[display.hit], 'Fixture: ' .. display.name .. ' takes a drag.'); end;
local function rect(id) local value = items[id]; return { x = value.x, y = value.y, width = value.width, height = value.height }; end;
local function places()
    local result = {};
    for _, display in ipairs(displays) do result[display.hit] = rect(display.hit); end;
    return result;
end;
-- How far a span from first to first + length shifts to put its nearer end on the 16 px grid, within 8 px, and the
-- grid line it meets: the first end wins a tie, as ui/snap.lua looks at it first.
local function on_grid(first, length)
    local shift, line;
    for _, point in ipairs({ first, first + length }) do
        local target = math.floor(point / 16 + 0.5) * 16;
        local delta = target - point;
        if math.abs(delta) <= 8 and (shift == nil or math.abs(delta) < math.abs(shift)) then shift, line = delta, target; end;
    end;
    return shift or 0, line;
end;
-- A Shift drag: pressed at x, y, moved by dx, dy, held a frame and let go. Returns the lines drawn behind and over the
-- displays in the frame after it moved, held there, and in the frame it was let go. A strip, and edit mode, draw a
-- display where the frame before moved it, so its line shows from the frame it is drawn on it.
local function drag(x, y, dx, dy)
    active, mouse.x, mouse.y, mouse.down, mouse.pressed = nil, x, y, true, true;
    frame();
    mouse.x, mouse.y = x + dx, y + dy;
    frame();
    frame();
    local moving = { back = back.lines, front = front.lines };
    mouse.down = false;
    frame();
    local ended = { back = back.lines, front = front.lines };
    frame(); frame();
    return moving, ended;
end;
local function middle(r) return r.x + r.width / 2, r.y + r.height / 2; end;
-- The other displays didn't move.
local function others_kept(before, moved, why)
    local now = places();
    for id, value in pairs(before) do
        if id ~= moved then
            local at = now[id];
            assert(at.x == value.x and at.y == value.y and at.width == value.width and at.height == value.height,
                why .. ': ' .. id .. ' stays where it was.');
        end;
    end;
end;

-- Grid mode starts off, with nothing ticked. While it is off each display goes exactly where it is dragged, moved or
-- pulled by an edge, with no grid and no line, ticked or not; while it is on, so does a display not ticked, though
-- every other is. The press of a drag reads no party list then, nor with Grid mode on and nothing ticked.
local snap = require('ui.snap');
local e = s.edit_mode;
assert(e.grid_mode == false and next(e.grid_displays) == nil, 'Grid mode starts off, with nothing ticked.');
-- The id each display is ticked for Grid mode by, and the recast panel a later pull takes.
local ticks = { 'self_buffs', 'notices', 'cooldown_list', 'rolls', 'pet', 'pulse', 'strip_1' };
for index, display in ipairs(displays) do display.id = ticks[index]; end;
local function tick_all(on, but)
    for _, display in ipairs(displays) do snap.tick(s, display.id, on and display.id ~= but); end;
    snap.tick(s, 'ability_recasts', on);
end;
local function unread(why)
    mouse.down = true; frame();
    assert(elements.party_list == nil, why .. ': the press reads no party list.');
    mouse.down = false; frame(0.2); frame(0.2);
end;
local function free(why, setup)
    for _, display in ipairs(displays) do
        setup(display);
        local before = places();
        local r = before[display.hit];
        local x, y = middle(r);
        local moving, ended = drag(x, y, 37, 21);
        local after = rect(display.hit);
        assert(after.x == r.x + 37 and after.y == r.y + 21 and after.width == r.width and after.height == r.height,
            why .. ': ' .. display.name .. ' goes exactly where it is dragged: ' .. after.x .. ', ' .. after.y .. ' for '
            .. (r.x + 37) .. ', ' .. (r.y + 21));
        assert(#moving.back + #moving.front + #ended.back + #ended.front == 0, why .. ': ' .. display.name .. ' shows no grid and no line.');
        others_kept(before, display.hit, why .. ', ' .. display.name .. ' moved');
        drag(x + 37, y + 21, -37, -21);
        if display.resizes then
            moving, ended = drag(r.x + r.width - 1, r.y + r.height / 2, 37, 0);
            after = rect(display.hit);
            assert(after.x == r.x and after.y == r.y and after.width == r.width + 37,
                why .. ': ' .. display.name .. '\'s right edge goes exactly where it is pulled: ' .. after.width .. ' for ' .. (r.width + 37));
            assert(#moving.back + #moving.front + #ended.back + #ended.front == 0, why .. ': ' .. display.name .. '\'s pull shows no grid and no line.');
            drag(r.x + r.width + 36, r.y + r.height / 2, -37, 0);
        end;
        local back_at = rect(display.hit);
        assert(back_at.x == r.x and back_at.y == r.y and back_at.width == r.width, 'Fixture: ' .. display.name .. ' is dragged back.');
    end;
end;
free('Grid mode off', function() end);
unread('Grid mode off');
tick_all(true);
free('Grid mode off, every display ticked', function() end);
unread('Grid mode off, every display ticked');
e.grid_mode = true;
free('Grid mode on, the display dragged not ticked', function(display) tick_all(true, display.id); end);
tick_all(false);
unread('Grid mode on, nothing ticked');
tick_all(true);

-- The game's party list is read from the press that may start a Shift drag, in that frame, as a drag can snap to it.
assert(elements.party_list == nil, 'With Shift held and nothing pressed, the party list is not read.');
mouse.down = true; frame();
assert(elements.party_list and elements.party_list.x == 1300, 'With Shift held, the press reads the party list in its frame.');
mouse.down = false; frame(0.2); frame(0.2);
assert(elements.party_list == nil, 'Let go, it is read no more.');
MOCK.key_shift = false; mouse.down = true; frame(0.2); frame(0.2);
assert(elements.party_list == nil, 'Without Shift, and no display following it, the party list is not read.');
MOCK.key_shift = true; s.edit_mode.snap_party = false; frame(0.2); frame(0.2);
assert(elements.party_list == nil, 'Nor while nothing snaps to it.');
s.edit_mode.snap_party = true;
for _, display in ipairs(displays) do display.lock(true); end;
frame(0.2); frame(0.2);
assert(elements.party_list == nil, 'Nor while every display is locked.');
s.pet.locked, s.pet.enabled = false, false;
frame(0.2); frame(0.2);
assert(elements.party_list == nil, 'Nor while the only display unlocked is off.');
s.pet.enabled = true;
frame(0.2); frame(0.2);
assert(elements.party_list and elements.party_list.x == 1300, 'Turned on, unlocked and ticked, it has the party list read.');
snap.tick(s, 'pet', false); frame(0.2); frame(0.2);
assert(elements.party_list == nil, 'Nor while the only display unlocked is not ticked for Grid mode.');
snap.tick(s, 'pet', true); e.grid_mode = false; frame(0.2); frame(0.2);
assert(elements.party_list == nil, 'Nor while Grid mode is off.');
e.grid_mode = true;
for _, display in ipairs(displays) do display.lock(false); end;
mouse.down = false; frame(0.2); frame(0.2);
assert(#back.lines == 0 and #front.lines == 0, 'With Shift held and nothing dragged, no grid or line shows.');

-- Each display's move: its nearer edge snaps to the grid, the grid shows while it moves and the line it met over it,
-- and both go when it is let go.
only('snap_grid');
for _, display in ipairs(displays) do
    local before = places();
    local r = before[display.hit];
    local x, y = middle(r);
    local moving, ended = drag(x, y, 37, 21);
    local shift_x, line_x = on_grid(r.x + 37, r.width);
    local shift_y, line_y = on_grid(r.y + 21, r.height);
    local after = rect(display.hit);
    assert(shift_x ~= 0 and shift_y ~= 0, 'Fixture: ' .. display.name .. ' lands off the grid.');
    assert(after.x == r.x + 37 + shift_x and after.y == r.y + 21 + shift_y,
        display.name .. ' moves to the grid: ' .. after.x .. ', ' .. after.y .. ' for ' .. (r.x + 37) .. ', ' .. (r.y + 21));
    assert(after.width == r.width and after.height == r.height, display.name .. ' keeps its size as it moves.');
    assert(grid(moving.back), display.name .. ': the grid shows while it moves.');
    assert(#moving.front == 2 and across(moving.front, line_x) and down(moving.front, line_y),
        display.name .. ': the lines it snapped to show while it moves.');
    assert(#ended.back == 0 and #ended.front == 0, display.name .. ': the grid and the lines go when it is let go.');
    others_kept(before, display.hit, display.name .. ' moved');
end;

-- A Shift click that doesn't move changes nothing, with the display a few px off the grid: no move, no Undo step and
-- no save.
local saved, save = 0, app.callbacks.save;
app.callbacks.save = function(...) saved = saved + 1; return save(...); end;
for _, display in ipairs(displays) do
    all(false);
    local r = rect(display.hit);
    local off = 3;
    while on_grid(r.x + off, r.width) == 0 or on_grid(r.y + off, r.height) == 0 do off = off + 1; end;
    local x, y = middle(r);
    drag(x, y, off, off);
    only('snap_grid');
    local before, steps, count = places(), #app.state.history, saved;
    r = before[display.hit];
    assert(on_grid(r.x, r.width) ~= 0 and on_grid(r.y, r.height) ~= 0, 'Fixture: ' .. display.name .. ' sits off the grid: '
        .. r.x .. ', ' .. r.y .. ' ' .. r.width .. 'x' .. r.height);
    x, y = middle(r);
    active, mouse.x, mouse.y, mouse.down, mouse.pressed = nil, x, y, true, true;
    frame(); frame(); frame();
    mouse.down = false;
    frame(); frame();
    local after = rect(display.hit);
    assert(after.x == r.x and after.y == r.y and #app.state.history == steps and saved == count,
        display.name .. ': a Shift click that doesn\'t move changes nothing: ' .. after.x .. ', ' .. after.y .. ' for ' .. r.x .. ', ' .. r.y
        .. ', ' .. (#app.state.history - steps) .. ' Undo steps, ' .. (saved - count) .. ' saves');
    others_kept(before, display.hit, display.name .. ' clicked');
end;
app.callbacks.save = save;

-- Each resize snaps only the edge it pulls: its right edge to the grid, its left edge and its height kept.
for _, display in ipairs(displays) do
    if display.resizes then
        local before = places();
        local r = before[display.hit];
        local moving = drag(r.x + r.width - 1, r.y + r.height / 2, 37, 0);
        local shift, line = on_grid(r.x + r.width + 37, 0);
        local after = rect(display.hit);
        assert(shift ~= 0, 'Fixture: ' .. display.name .. '\'s edge lands off the grid.');
        assert(after.x == r.x and after.y == r.y and after.width == r.width + 37 + shift,
            display.name .. '\'s right edge snaps to the grid: ' .. after.x .. ', ' .. after.width .. ' for ' .. (r.width + 37));
        assert(grid(moving.back) and #moving.front == 1 and across(moving.front, line),
            display.name .. ': only the pulled edge\'s line shows.');
        others_kept(before, display.hit, display.name .. ' resized');
    end;
end;

-- With every switch off a drag follows the pointer exactly and no line shows; the grid still shows while it moves.
all(false);
for _, display in ipairs(displays) do
    local before = places();
    local r = before[display.hit];
    local x, y = middle(r);
    local moving = drag(x, y, -21, -13);
    local after = rect(display.hit);
    assert(after.x == r.x - 21 and after.y == r.y - 13, display.name .. ' follows the pointer exactly with every switch off.');
    assert(grid(moving.back) and #moving.front == 0, display.name .. ': the grid shows, and no line, with every switch off.');
    others_kept(before, display.hit, display.name .. ' moved freely');
end;
-- With Show the grid off, no grid shows while it moves; the line it snapped to still does.
all(true); only('snap_grid');
s.edit_mode.show_grid = false;
for _, display in ipairs(displays) do
    local r = rect(display.hit);
    local x, y = middle(r);
    local moving = drag(x, y, 37, 21);
    assert(#moving.back == 0 and #moving.front > 0, display.name .. ': with Show the grid off only the line shows.');
end;
s.edit_mode.show_grid = true;

-- A locked display never moves, and nothing shows.
for _, display in ipairs(displays) do
    display.lock(true);
    frame(0.2);
    local before = places();
    local r = before[display.hit];
    local moving, ended;
    if r then
        local x, y = middle(r);
        moving, ended = drag(x, y, 37, 21);
        assert(#moving.back == 0 and #moving.front == 0, display.name .. ': nothing shows for a locked display.');
    end;
    display.lock(false);
    frame(0.2);
    assert(not r or rect(display.hit).x == r.x and rect(display.hit).y == r.y, display.name .. ' locked doesn\'t move.');
end;

-- What a move snaps to, each by its own switch, through Self buffs' drag: the screen's middle, another display's edge,
-- the game's party list and the chat log. The others go back to where they started.
s.alerts.notice_x, s.alerts.notice_y, s.alerts.notice_width = 496, 96, 300;
local list = s.party_cooldowns.list;
list.x, list.y, list.width, list.height = 896, 96, 300, 0;
s.rolls.x, s.rolls.y, s.rolls.width, s.rolls.height = 64, 400, 320, 0;
s.pet.x, s.pet.y, s.pet.width, s.pet.height = 496, 400, 280, 0;
s.ready_pulse.x, s.ready_pulse.y = 1296, 96;
s.party_ui.groups[1].native_x, s.party_ui.groups[1].native_y = 0, 0;
s.panels.self_buffs.width = 300;
local function place_buffs(x, y)
    s.panels.self_buffs.x, s.panels.self_buffs.y = x, y;
    frame(0.2); frame();
    return rect('##move_self_buffs');
end;
only('snap_screen');
local r = place_buffs(640, 256);
assert(r.width == 300, 'Fixture: Self buffs is back to 300 px.');
local moving = drag(r.x + r.width / 2, r.y + r.height / 2, 803 - r.width / 2 - r.x, 0);
assert(rect('##move_self_buffs').x == 800 - r.width / 2 and #moving.front == 1 and across(moving.front, 800),
    'Its middle snaps to the screen\'s middle: ' .. rect('##move_self_buffs').x);
only('snap_elements');
local notices = rect('##notice_layout');
assert(notices.x == 496 and notices.width == 300, 'Fixture: the notices are back at the start.');
r = place_buffs(notices.x + notices.width + 16, 256);
moving = drag(r.x + r.width / 2, r.y + r.height / 2, -12, 0);
assert(rect('##move_self_buffs').x == notices.x + notices.width and #moving.front == 1
    and across(moving.front, notices.x + notices.width), 'Its left edge snaps to the notices\' right edge: ' .. rect('##move_self_buffs').x);
only('snap_party');
r = place_buffs(1024, 512);
moving = drag(r.x + r.width / 2, r.y + r.height / 2, 0, 595 - r.height - r.y);
assert(rect('##move_self_buffs').y + r.height == 600 and #moving.front == 1 and down(moving.front, 600),
    'Its bottom snaps to the game\'s party list\'s top: ' .. rect('##move_self_buffs').y);
only('snap_chat');
r = place_buffs(64, 608);
moving = drag(r.x + r.width / 2, r.y + r.height / 2, 0, 703 - r.height - r.y);
assert(rect('##move_self_buffs').y + r.height == 700 and #moving.front == 1 and down(moving.front, 700),
    'Its bottom snaps to the chat log\'s top: ' .. rect('##move_self_buffs').y);

-- A party strip in a panel of its own moves and resizes, snapping as the others do.
only('snap_grid');
local strip = s.party_ui.groups[1];
strip.native_detached, strip.detached_x, strip.detached_y, strip.detached_width, strip.detached_height = true, 1104, 496, 300, 240;
frame(0.2); frame();
local before = places();
r = before['##native_move_1'];
local x, y = middle(r);
moving = drag(x, y, 37, 21);
local shift_x, line_x = on_grid(r.x + 37, r.width);
local shift_y = on_grid(r.y + 21, r.height);
local after = rect('##native_move_1');
assert(after.x == r.x + 37 + shift_x and after.y == r.y + 21 + shift_y and grid(moving.back) and across(moving.front, line_x),
    'A strip in a panel of its own moves to the grid: ' .. after.x .. ', ' .. after.y .. ' from ' .. r.x .. ', ' .. r.y .. ' '
    .. r.width .. 'x' .. r.height .. ', ' .. #moving.back .. ' lines behind, ' .. #moving.front .. ' over, line ' .. tostring(line_x));
others_kept(before, '##native_move_1', 'The strip of its own moved');
r = rect('##native_move_1');
moving = drag(r.x + r.width - 1, r.y + r.height / 2, 37, 0);
local shift, line = on_grid(r.x + r.width + 37, 0);
after = rect('##native_move_1');
assert(after.x == r.x and after.width == r.width + 37 + shift and #moving.front == 1 and across(moving.front, line),
    'Its right edge snaps to the grid: ' .. after.width);

-- A line at a half pixel, the middle of the cooldown list 301 px wide: a resize pulls an edge onto it at the whole
-- pixel nearest it, so the edge across stays put, on every display that resizes. The cooldown list's own line is the
-- middle of Phantom Roll, 321 px wide.
only('snap_elements');
local recasts = s.panels.ability_recasts;
recasts.enabled, recasts.locked, recasts.empty, recasts.x, recasts.y = true, false, 'show', 64, 600;
list.width = 301;
frame(0.2); frame();
local half = rect('##cooldown_list_layout');
assert(half.x == 896 and half.width == 301, 'Fixture: the cooldown list\'s middle is at 1046.5.');
local pulls = {
    { name = 'Self buffs', hit = '##move_self_buffs', put = function(x, y) s.panels.self_buffs.x, s.panels.self_buffs.y = x, y; end },
    { name = 'A recast panel', hit = '##move_ability_recasts', put = function(x, y) recasts.x, recasts.y = x, y; end },
    { name = 'Alert notices', hit = '##notice_layout', put = function(x, y) s.alerts.notice_x, s.alerts.notice_y = x, y; end },
    { name = 'Phantom Roll', hit = '##vantage_rolls_layout', put = function(x, y) s.rolls.x, s.rolls.y = x, y; end },
    { name = 'Pet', hit = '##vantage_pet_layout', put = function(x, y) s.pet.x, s.pet.y = x, y; end },
    { name = 'A strip in a panel of its own', hit = '##native_move_1', put = function(x, y) strip.detached_x, strip.detached_y = x, y; end },
};
for _, pull in ipairs(pulls) do
    local from = rect(pull.hit);
    pull.put(1050, 560);
    frame(0.2); frame();
    r = rect(pull.hit);
    assert(r.x == 1050 and r.y == 560, 'Fixture: ' .. pull.name .. ' starts 3.5 px right of the line: ' .. r.x .. ', ' .. r.y);
    moving = drag(r.x + 1, r.y + r.height / 2, -3, 0);
    after = rect(pull.hit);
    assert(math.abs(after.x - 1046.5) < 1 and after.x + after.width == r.x + r.width and across(moving.front, 1046.5),
        pull.name .. '\'s left edge snaps to the line at a half pixel with its right edge kept: ' .. after.x .. ' + ' .. after.width
        .. ' = ' .. (after.x + after.width) .. ' for ' .. (r.x + r.width));
    pull.put(from.x, from.y);
    frame(0.2); frame();
end;
s.rolls.width = 321;
frame(0.2); frame();
half = rect('##vantage_rolls_layout');
assert(half.width == 321, 'Fixture: Phantom Roll\'s middle is at a half pixel.');
local line_at = half.x + 160.5;
list.x, list.y = line_at + 3.5, 560;
frame(0.2); frame();
r = rect('##cooldown_list_layout');
moving = drag(r.x + 1, r.y + r.height / 2, -3, 0);
after = rect('##cooldown_list_layout');
assert(math.abs(after.x - line_at) < 1 and after.x + after.width == r.x + r.width and across(moving.front, line_at),
    'The cooldown list\'s left edge snaps to the line at a half pixel with its right edge kept: ' .. after.x .. ' + ' .. after.width
    .. ' = ' .. (after.x + after.width) .. ' for ' .. (r.x + r.width));
list.x, list.y, list.width, s.rolls.width = 896, 96, 300, 320;

-- The line a resize met shows only where the edge it pulls was drawn: the notices' bottom, pulled 13 px, holds at
-- their least height of 80 px, short of the grid line it met, and a recast panel's grows a row at a time.
only('snap_grid');
s.alerts.notice_x, s.alerts.notice_y = 496, 106;
frame(0.2); frame();
r = rect('##notice_layout');
assert(r.y == 106 and r.height + 13 < 80, 'Fixture: the notices are shorter than their least height: ' .. r.height);
moving = drag(r.x + r.width / 2, r.y + r.height - 1, 0, 13);
after = rect('##notice_layout');
assert(after.y == 106 and after.height == 80 and #moving.front == 0,
    'Held at 80 px, 6 px short of the grid line at 192, the notices show no line: ' .. after.height .. ', ' .. #moving.front .. ' lines');
s.alerts.notice_y = 96;
recasts.x, recasts.y = 1104, 420;
frame(0.2); frame();
r = rect('##move_ability_recasts');
moving = drag(r.x + r.width / 2, r.y + r.height - 1, 0, 13);
after = rect('##move_ability_recasts');
assert(after.height > r.height and (after.y + after.height) % 16 ~= 0, 'Fixture: the recast panel grows by rows, off the grid: '
    .. after.y .. ' + ' .. after.height);
assert(#moving.front == 0, 'Its bottom drawn off the grid line it met, the recast panel shows no line: ' .. #moving.front .. ' lines');
recasts.enabled = false;
frame(0.2); frame();

-- Edit mode's drag lands where a Shift drag does: the same snapping.
strip.native_detached = false;
all(true); only('snap_grid');
r = place_buffs(64, 96);
local function command(line) local event = { command = line }; MOCK.fire('command', event); assert(event.blocked, line); end;
command('/vg edit');
frame(); frame();
assert(#back.lines == 0 and #front.lines == 0, 'Edit mode draws no grid while nothing is dragged.');
local outline = rect('##edit_hit_self_buffs');
assert(outline.x == r.x and outline.y == r.y, 'Fixture: edit mode outlines Self buffs where it is.');
x, y = middle(outline);
moving = drag(x, y, 37, 21);
shift_x = on_grid(r.x + 37, r.width);
shift_y = on_grid(r.y + 21, r.height);
assert(s.panels.self_buffs.x == r.x + 37 + shift_x and s.panels.self_buffs.y == r.y + 21 + shift_y and grid(moving.back),
    'Edit mode\'s drag snaps as a Shift drag does: ' .. s.panels.self_buffs.x .. ', ' .. s.panels.self_buffs.y);
assert(#back.lines == 0 and #front.lines == 0, 'Edit mode: the grid and the line go when it is let go.');
-- A Shift click on its outline that doesn't move changes nothing, with the display 3 px off the grid.
s.panels.self_buffs.x, s.panels.self_buffs.y = s.panels.self_buffs.x + 3, s.panels.self_buffs.y + 3;
frame(); frame();
outline = rect('##edit_hit_self_buffs');
local steps = #app.state.history;
active, mouse.x, mouse.y, mouse.down, mouse.pressed = nil, outline.x + outline.width / 2, outline.y + outline.height / 2, true, true;
frame(); frame(); frame();
mouse.down = false;
frame(); frame();
assert(rect('##edit_hit_self_buffs').x == outline.x and rect('##edit_hit_self_buffs').y == outline.y and #app.state.history == steps,
    'Edit mode: a Shift click that doesn\'t move changes nothing: ' .. s.panels.self_buffs.x .. ', ' .. s.panels.self_buffs.y);
-- In edit mode too a display not ticked, and every display while Grid mode is off, goes exactly where it is dragged,
-- with no grid and no line.
for _, case in ipairs({ { true, false, 'Edit mode, Self buffs not ticked' }, { false, true, 'Edit mode, Grid mode off' } }) do
    e.grid_mode = case[1];
    snap.tick(s, 'self_buffs', case[2]);
    frame(); frame();
    outline = rect('##edit_hit_self_buffs');
    x, y = middle(outline);
    local from_x, from_y = s.panels.self_buffs.x, s.panels.self_buffs.y;
    local moving_now, ended_now = drag(x, y, 37, 21);
    assert(s.panels.self_buffs.x == from_x + 37 and s.panels.self_buffs.y == from_y + 21, case[3] .. ': it goes exactly where it is dragged: '
        .. s.panels.self_buffs.x .. ', ' .. s.panels.self_buffs.y .. ' for ' .. (from_x + 37) .. ', ' .. (from_y + 21));
    assert(#moving_now.back + #moving_now.front + #ended_now.back + #ended_now.front == 0, case[3] .. ': no grid and no line.');
end;
e.grid_mode = true;
command('/vg edit');
frame();
MOCK.fire('unload');
return 'Every display\'s Shift drag snaps as edit mode does';
