-- ui/snap.lua, the one snapping every move uses: edit mode's drags and each display's own Shift drag. Only a display
-- ticked for Grid mode snaps, and only while Grid mode is on; any other move runs no search and shows no line and no
-- grid. A move snaps its nearest edge or middle, and a resize only the edge it pulls, to the nearest line within the
-- snap distance, from the lines the snapping switches choose: the grid's, the screen's, the other displays',
-- the game's party list's and the chat log's. With every switch off nothing snaps. A display that follows the one moved
-- is no line. The lines a snap met are drawn once, the grid only with Show the grid on, and neither on a list the
-- renderer doesn't give. The search makes nothing.
local snap, elements, defaults = require('ui.snap'), require('ui.elements'), require('ui.defaults');
local imgui, theme, bit = require('imgui'), require('ui.theme'), require('bit');
local s = defaults.make();
local e = s.edit_mode;
local SW, SH = 1600, 900;
local SWITCHES = { 'snap_grid', 'snap_screen', 'snap_elements', 'snap_party', 'snap_chat' };
-- Every switch off but the one named.
local function only(switch)
    for _, name in ipairs(SWITCHES) do e[name] = name == switch; end;
end;
-- The lines snap.guides draws for a display drawn at rect, as { x1, y1, x2, y2, color }.
local drawn = {};
local list = { AddLine = function(_, from, to, color) drawn[#drawn + 1] = { from[1], from[2], to[1], to[2], color }; end };
local function guides(rect)
    drawn = {};
    snap.guides(list, 0xFFFFFFFF, SW, SH, rect);
    return drawn;
end;
local function across(line, x) return line[1] == x and line[2] == 0 and line[3] == x and line[4] == SH; end;
local function down(line, y) return line[1] == 0 and line[2] == y and line[3] == SW and line[4] == y; end;
-- No display drawn: two Presents make every record stale.
local function clear() elements.frame(); elements.frame(); elements.party_list, elements.chat = nil, nil; end;

-- Fresh settings have Grid mode off with no display ticked for it, and once it is on snap to everything, 8 px away at
-- most, on a 16 px grid that shows.
assert(e.grid_mode == false and type(e.grid_displays) == 'table' and next(e.grid_displays) == nil,
    'Grid mode starts off, with no display ticked for it.');
assert(e.grid == 16 and e.snap_distance == 8 and e.show_grid, 'Fixture: the edit mode defaults.');
for _, name in ipairs(SWITCHES) do assert(e[name] == true, name .. ' starts on.'); end;
-- So fresh settings snap nothing, and nor does Grid mode on with nothing ticked: a display 3 px from grid lines stays.
local function stays(id)
    local x, y = snap.move(s, id, 323, 165, 100, 40, SW, SH);
    return x == 0 and y == 0;
end;
clear();
assert(stays('rolls'), 'With Grid mode off nothing snaps.');
e.grid_mode = true;
assert(stays('rolls'), 'With Grid mode on and nothing ticked nothing snaps.');
-- A tick keeps each display once, in the displays' own order, and only a ticked display snaps.
snap.tick(s, 'self_debuffs', true); snap.tick(s, 'rolls', true); snap.tick(s, 'self_buffs', true); snap.tick(s, 'rolls', true);
assert(table.concat(e.grid_displays, ' ') == 'self_buffs self_debuffs rolls', 'Ticked in order: ' .. table.concat(e.grid_displays, ' '));
assert(not stays('rolls') and stays('target'), 'A ticked display snaps; one not ticked stays put.');
snap.tick(s, 'target', true); snap.tick(s, 'target', false);
assert(table.concat(e.grid_displays, ' ') == 'self_buffs self_debuffs rolls' and not snap.ticked(s, 'target'), 'An untick takes it out.');
e.grid_mode = false;
assert(stays('rolls') and snap.ticked(s, 'rolls'), 'Grid mode off: a ticked display stays put and keeps its tick.');
e.grid_mode = true;

-- The grid: either edge snaps to the nearest grid line, across and down.
clear(); only('snap_grid');
local dx, dy = snap.move(s, 'rolls', 323, 165, 100, 40, SW, SH);
assert(dx == -3 and dy == 3, 'The left edge snaps 3 px left to 320, the bottom 3 px down to 208: ' .. dx .. ', ' .. dy);
local lines = guides({ x = 320, y = 168, width = 100, height = 40 });
assert(#lines == 2 and across(lines[1], 320) and down(lines[2], 208), 'The two lines it met are drawn across the screen.');
assert(#guides({ x = 320, y = 168, width = 100, height = 40 }) == 0, 'Each is drawn once.');
-- Each only where the display was drawn on it, after its rows, its least size and the screen's edges.
snap.move(s, 'rolls', 323, 165, 100, 40, SW, SH);
lines = guides({ x = 330, y = 168, width = 100, height = 40 });
assert(#lines == 1 and down(lines[1], 208), 'A display drawn 10 px off the line it met across shows only the line it is on.');
snap.move(s, 'rolls', 323, 165, 100, 40, SW, SH);
assert(#guides() == 0, 'With no display drawn no line shows.');
dx = snap.move(s, 'rolls', 334, 0, 99, 40, SW, SH);
assert(dx == -1, 'The right edge snaps when it is the nearer: 433 to 432 is 1 px, ' .. dx);
e.grid = 24;
dx = snap.move(s, 'rolls', 50, 0, 100, 40, SW, SH);
assert(dx == -2, 'The grid size is the one set: 50 snaps to 48, ' .. dx);
e.grid = 16;
-- The snap distance is the one set: a line just past it is not met; one at it is.
e.snap_distance = 2;
assert(snap.move(s, 'rolls', 323, 0, 100, 40, SW, SH) == 0, 'A line 3 px off is past a 2 px distance.');
e.snap_distance = 3;
assert(snap.move(s, 'rolls', 323, 0, 100, 40, SW, SH) == -3, 'A line 3 px off is met at a 3 px distance.');
e.snap_distance = 8;
guides();

-- The screen: its edges and its middle lines.
only('snap_screen');
assert(snap.move(s, 'rolls', 745, 0, 100, 40, SW, SH) == 5, 'Its middle snaps to the screen\'s middle.');
assert(across(guides({ x = 750, y = 0, width = 100, height = 40 })[1], 800), 'The screen\'s middle line is drawn.');
assert(snap.move(s, 'rolls', 1495, 0, 100, 40, SW, SH) == 5, 'Its right edge snaps to the screen\'s right edge.');
assert(snap.move(s, 'rolls', 4, 0, 100, 40, SW, SH) == -4, 'Its left edge snaps to the screen\'s left edge.');
assert(select(2, snap.move(s, 'rolls', 0, 428, 100, 40, SW, SH)) == 2, 'Its middle snaps to the screen\'s middle down.');
guides();

-- The other displays: their edges and middles, where they were drawn this Present or the one before.
only('snap_elements');
elements.frame(); elements.frame();
elements.record('self_debuffs', { x = 200, y = 150, width = 300, height = 200 });
assert(snap.move(s, 'self_buffs', 495, 0, 80, 40, SW, SH) == 5, 'Its left edge snaps to another display\'s right edge.');
assert(across(guides({ x = 500, y = 0, width = 80, height = 40 })[1], 500), 'That edge is the line drawn.');
assert(snap.move(s, 'self_buffs', 307, 0, 80, 40, SW, SH) == 3, 'Its middle snaps to another display\'s middle.');
assert(select(2, snap.move(s, 'self_buffs', 0, 104, 80, 40, SW, SH)) == 6, 'Its bottom snaps to another display\'s top.');
-- Not to itself, to a display that is off, or to one not drawn lately.
assert(snap.move(s, 'self_debuffs', 205, 0, 300, 200, SW, SH) == 0, 'A display is no line for itself.');
s.panels.self_debuffs.enabled = false;
assert(snap.move(s, 'self_buffs', 495, 0, 80, 40, SW, SH) == 0, 'A display that is off is no line.');
s.panels.self_debuffs.enabled = true;
elements.frame();
assert(snap.move(s, 'self_buffs', 495, 0, 80, 40, SW, SH) == 5, 'One drawn the Present before is.');
elements.frame();
assert(snap.move(s, 'self_buffs', 495, 0, 80, 40, SW, SH) == 0, 'One drawn longer ago is not.');
-- A display that follows the one moved moves with it, so it is no line: by its anchor, through another display that
-- follows it, or by a panel's attachment.
elements.frame();
elements.record('self_debuffs', { x = 200, y = 150, width = 300, height = 200 });
elements.record('target', { x = 600, y = 150, width = 300, height = 200 });
local anchor = s.panels.self_debuffs.anchor;
anchor.to, anchor.element = 'element', 'self_buffs';
assert(snap.move(s, 'self_buffs', 495, 0, 80, 40, SW, SH) == 0, 'A display anchored to it is no line.');
s.panels.target.anchor.to, s.panels.target.anchor.element = 'element', 'self_debuffs';
assert(snap.move(s, 'self_buffs', 895, 0, 80, 40, SW, SH) == 0, 'Nor is one anchored to that one.');
assert(snap.move(s, 'self_debuffs', 895, 0, 80, 40, SW, SH) == 0, 'Nor is a display a line for the one it follows directly.');
anchor.to, anchor.element = 'none', '';
assert(snap.move(s, 'self_buffs', 495, 0, 80, 40, SW, SH) == 5 and snap.move(s, 'self_buffs', 895, 0, 80, 40, SW, SH) == 5,
    'Once it follows nothing, both are lines again.');
s.panels.target.anchor.to, s.panels.target.anchor.element = 'none', '';
guides();

-- The game's party list, where Vantage knows it.
only('snap_party');
elements.party_list = { x = 1300, y = 600, width = 200, height = 40 };
assert(snap.move(s, 'rolls', 1196, 0, 100, 40, SW, SH) == 4, 'Its right edge snaps to the party list\'s left edge.');
assert(across(guides({ x = 1200, y = 0, width = 100, height = 40 })[1], 1300), 'The party list\'s edge is the line drawn.');
elements.party_list = nil;
assert(snap.move(s, 'rolls', 1196, 0, 100, 40, SW, SH) == 0, 'With the party list unknown there is no party list line.');

-- The chat log, where Vantage knows it.
only('snap_chat');
elements.chat = { x = 0, y = 700, width = 600, height = 200 };
assert(select(2, snap.move(s, 'rolls', 150, 655, 100, 40, SW, SH)) == 5, 'Its bottom snaps to the chat log\'s top.');
assert(down(guides({ x = 150, y = 660, width = 100, height = 40 })[1], 700), 'The chat log\'s top is the line drawn.');
elements.chat = nil;
assert(select(2, snap.move(s, 'rolls', 150, 655, 100, 40, SW, SH)) == 0, 'With the chat log unknown there is no chat line.');

-- The nearest line wins, whichever switch gives it.
for _, name in ipairs(SWITCHES) do e[name] = true; end;
elements.frame(); elements.frame();
elements.record('self_debuffs', { x = 200, y = 150, width = 300, height = 200 });
assert(snap.move(s, 'self_buffs', 499, 0, 80, 40, SW, SH) == 1, 'Another display\'s edge 1 px off beats the grid line 3 px off.');
assert(across(guides({ x = 500, y = 0, width = 80, height = 40 })[1], 500), 'The nearest line is the one drawn.');

-- Every switch off: nothing snaps, wherever the display goes, and no line is drawn.
only(nil);
elements.party_list, elements.chat = { x = 1300, y = 600, width = 200, height = 40 }, { x = 0, y = 700, width = 600, height = 200 };
for _, place in ipairs({ { 323, 165 }, { 745, 428 }, { 495, 104 }, { 1196, 655 }, { 320, 160 } }) do
    dx, dy = snap.move(s, 'self_buffs', place[1], place[2], 80, 40, SW, SH);
    assert(dx == 0 and dy == 0, 'With every switch off nothing snaps: ' .. place[1] .. ', ' .. place[2]);
end;
assert(#guides({ x = 320, y = 160, width = 80, height = 40 }) == 0, 'With every switch off no line is drawn.');
elements.party_list, elements.chat = nil, nil;

-- A resize snaps only the edge it pulls; the edges across from it stay put.
clear(); only('snap_grid');
local start = { x = 203, y = 153, width = 294, height = 194 };
local wanted = { left = { 5, 0 }, right = { -1, 0 }, top = { 0, 7 }, bottom = { 0, 5 }, top_left = { 5, 7 }, top_right = { -1, 7 },
    bottom_left = { 5, 5 }, bottom_right = { -1, 5 } };
for edge, shift in pairs(wanted) do
    dx, dy = snap.edge(s, 'rolls', start, edge, SW, SH);
    assert(dx == shift[1] and dy == shift[2], edge .. ' shifts only the edges it pulls: ' .. dx .. ', ' .. dy);
    local rect = snap.resize(s, 'rolls', start, edge, 0, 0, { screen_width = SW, screen_height = SH });
    lines = guides(rect);
    assert(#lines == (shift[1] ~= 0 and 1 or 0) + (shift[2] ~= 0 and 1 or 0), edge .. ' draws only its own lines.');
    local left, right = rect.x, rect.x + rect.width;
    local top, bottom = rect.y, rect.y + rect.height;
    assert(left == 203 + (edge:find('left', 1, true) and 5 or 0) and right == 497 + (edge:find('right', 1, true) and -1 or 0)
        and top == 153 + (edge:find('top', 1, true) and 7 or 0) and bottom == 347 + (edge:find('bottom', 1, true) and 5 or 0),
        edge .. ' resizes to the grid with the edges across from it kept: ' .. left .. ', ' .. top .. ', ' .. right .. ', ' .. bottom);
end;
dx, dy = snap.edge(s, 'rolls', start, nil, SW, SH);
assert(dx == 0 and dy == 0 and #guides(start) == 0, 'No edge pulled, nothing shifts.');
-- A resize's line shows only where the edge it pulls was drawn: here the bottom held at its least height.
snap.edge(s, 'rolls', start, 'bottom', SW, SH);
assert(#guides({ x = 203, y = 153, width = 294, height = 190 }) == 0, 'A bottom edge drawn 9 px short of its line shows none.');
snap.edge(s, 'rolls', start, 'right', SW, SH);
assert(#guides({ x = 496, y = 153, width = 294, height = 194 }) == 0, 'Nor does the edge across from the one pulled.');
-- A snap never takes a resize past its limits.
local small = snap.resize(s, 'rolls', { x = 100, y = 100, width = 50, height = 50 }, 'right', -10, 0,
    { min_width = 50, screen_width = SW, screen_height = SH });
assert(small.x == 100 and small.width == 50, 'The smallest width holds against a snap: ' .. small.width);
local edge_of_screen = snap.resize(s, 'rolls', { x = 1500, y = 100, width = 90, height = 50 }, 'right', 6, 0,
    { screen_width = SW, screen_height = SH });
assert(edge_of_screen.x == 1500 and edge_of_screen.width == 100, 'A snap to the last grid line, the screen\'s edge, stays on the screen: '
    .. edge_of_screen.width);
guides();
-- A line at a half pixel, another display's middle: the edge pulled lands on the whole pixel nearest it, so with a
-- display's place and size whole pixels the edge across from it stays put.
only('snap_elements');
elements.frame(); elements.frame();
elements.record('self_debuffs', { x = 896, y = 96, width = 301, height = 200 });
dx = snap.edge(s, 'rolls', { x = 1050, y = 400, width = 300, height = 60 }, 'left', SW, SH);
assert(dx == -3, 'A left edge 3.5 px right of a line at 1046.5 moves 3 px, to 1047: ' .. dx);
lines = guides({ x = 1047, y = 400, width = 303, height = 60 });
assert(#lines == 1 and lines[1][1] == 1046.5, 'The line shows where the edge caught it.');
dx = snap.edge(s, 'rolls', { x = 700, y = 400, width = 343, height = 60 }, 'right', SW, SH);
assert(dx == 4, 'A right edge 3.5 px left of it moves 4 px, to 1047: ' .. dx);
local pulled = snap.resize(s, 'rolls', { x = 1050, y = 400, width = 300, height = 60 }, 'left', 0, 0, { screen_width = SW, screen_height = SH });
assert(pulled.x == 1047 and pulled.width == 303, 'Whole pixels, the right edge kept at 1350: ' .. pulled.x .. ', ' .. pulled.width);
guides();

-- Each frame of a ticked display's drag: the grid with Show the grid on, behind every display, and the line it snapped
-- to over them, in the accent color.
local back, front = {}, {};
local back_list = { AddLine = function(_, from, to) back[#back + 1] = { from[1], from[2], to[1], to[2] }; end };
local front_list = { AddLine = function(_, from, to, color) front[#front + 1] = { from[1], from[2], to[1], to[2], color }; end };
local give_back, give_front = back_list, front_list;
rawset(imgui, 'GetBackgroundDrawList', function() return give_back; end);
rawset(imgui, 'GetForegroundDrawList', function() return give_front; end);
for _, name in ipairs(SWITCHES) do e[name] = true; end;
local at = { x = 320, y = 168, width = 100, height = 40 };
snap.move(s, 'rolls', 323, 165, 100, 40, SW, SH);
snap.show(s, 'rolls', SW, SH, at);
-- A line every 16 px across (99) and down (56), and the two middle lines.
assert(#back == 99 + 56 + 2 and across(back[1], 16) and down(back[100], 16), 'The grid shows: ' .. #back .. ' lines.');
assert(across(back[156], 800) and down(back[157], 450), 'With the screen\'s middle lines.');
assert(#front == 2 and across(front[1], 320) and down(front[2], 208), 'The lines it snapped to show over it.');
assert(front[1][5] == bit.bor(theme.u32(s.style.accent_color), 0xFF000000), 'In the accent color, solid.');
back, front = {}, {};
e.show_grid = false;
snap.move(s, 'rolls', 323, 165, 100, 40, SW, SH);
snap.show(s, 'rolls', SW, SH, at);
assert(#back == 0 and #front == 2, 'With Show the grid off only the lines it snapped to show.');
e.show_grid = true;
-- A list the renderer doesn't give is left out, and the lines met are still cleared.
give_back, give_front = false, nil;
snap.move(s, 'rolls', 323, 165, 100, 40, SW, SH);
snap.show(s, 'rolls', SW, SH, at);
give_back, give_front = back_list, front_list;
back, front = {}, {};
snap.show(s, 'rolls', SW, SH, at);
assert(#back == 157 and #front == 0, 'Without the lists nothing is drawn, and no old line waits for the next frame.');

-- The gate: while Grid mode is off, and for a display not ticked for it, a move and a resize run no search, and a
-- drag's frame draws no grid and no line and leaves none for the next. What they read of the edit mode settings shows
-- it: only the switch and the ticks.
local real, read = s.edit_mode, {};
s.edit_mode = setmetatable({}, { __index = function(_, key) read[key] = true; return real[key]; end, __newindex = real });
local function searched()
    for key in pairs(read) do if key ~= 'grid_mode' and key ~= 'grid_displays' then return key; end end;
    return nil;
end;
elements.frame(); elements.frame();
elements.record('self_debuffs', { x = 200, y = 150, width = 300, height = 200 });
elements.party_list, elements.chat = { x = 1300, y = 600, width = 200, height = 40 }, { x = 0, y = 700, width = 600, height = 200 };
snap.move(s, 'rolls', 323, 165, 100, 40, SW, SH);
assert(searched(), 'Fixture: a ticked display\'s move searches, and what it reads shows it.');
for _, case in ipairs({ { false, 'rolls' }, { false, 'target' }, { true, 'target' } }) do
    real.grid_mode = case[1];
    snap.move(s, 'rolls', 323, 165, 100, 40, SW, SH);
    read, back, front = {}, {}, {};
    dx, dy = snap.move(s, case[2], 323, 165, 100, 40, SW, SH);
    local ex, ey = snap.edge(s, case[2], start, 'bottom_right', SW, SH);
    local rect = snap.resize(s, case[2], start, 'bottom_right', 0, 0, { screen_width = SW, screen_height = SH });
    snap.show(s, case[2], SW, SH, at);
    local what = (case[1] and 'Grid mode on, ' or 'Grid mode off, ') .. case[2] .. (snap.ticked(s, case[2]) and ' ticked' or ' not ticked');
    assert(dx == 0 and dy == 0 and ex == 0 and ey == 0 and rect.x == start.x and rect.y == start.y and rect.width == start.width
        and rect.height == start.height, what .. ': nothing snaps.');
    assert(not searched(), what .. ': no search runs, but it read ' .. tostring(searched()));
    assert(#back == 0 and #front == 0 and #guides(at) == 0, what .. ': no grid and no line, now or for the next frame.');
end;
s.edit_mode, real.grid_mode = real, true;
elements.party_list, elements.chat = nil, nil;
rawset(imgui, 'GetBackgroundDrawList', nil);
rawset(imgui, 'GetForegroundDrawList', nil);

-- The search makes nothing: every switch on, displays, the party list and the chat log to search, a move, a resize's
-- edge, the lines met and the grid drawn on a list that keeps nothing. Measured as test_element_draw_allocation.lua
-- measures, with the collector stopped and the compiler off; a table made in the loop shows.
local quiet = { AddLine = function() end };
clear();
for _, id in ipairs({ 'self_debuffs', 'target', 'cooldown_list', 'pulse', 'pet' }) do
    elements.record(id, { x = 300, y = 300, width = 120, height = 60 });
end;
s.party_cooldowns.enabled, s.party_cooldowns.list.enabled, s.ready_pulse.enabled, s.pet.enabled = true, true, true, true;
s.ready_pulse.spot = 'screen';
elements.party_list, elements.chat = { x = 1300, y = 600, width = 200, height = 40 }, { x = 0, y = 700, width = 600, height = 200 };
local leak, made = false, nil;
local function moves(count)
    for i = 1, count do
        snap.move(s, 'self_buffs', 100 + i % 400, 50 + i % 300, 80, 40, SW, SH);
        snap.edge(s, 'self_buffs', start, 'bottom_right', SW, SH);
        snap.guides(quiet, 0xFFFFFFFF, SW, SH, start);
        snap.grid(quiet, e, SW, SH);
        if leak then made = {}; end;
    end;
end;
local function measure(count)
    jit.off(); jit.flush();
    moves(60);
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    moves(6);
    local before = collectgarbage('count');
    moves(count);
    local each = (collectgarbage('count') - before) / count;
    collectgarbage('restart');
    jit.on();
    return each;
end;
local each = measure(600);
assert(each < 0.002, ('The search makes %.4f KB a move; nothing expected'):format(each));
leak = true;
each = measure(600);
leak = false;
assert(each >= 0.002 and made, ('A table made each move shows as %.4f KB a move'):format(each));
elements.party_list, elements.chat = nil, nil;
clear();
return 'One snapping for every move, by the snapping switches';
