-- Snapping for every move: edit mode's drags, and each display's own Shift drag once it is unlocked. Only a display
-- ticked for Grid mode snaps, and only while Grid mode is on (settings.edit_mode.grid_mode and grid_displays); any
-- other move goes where the pointer puts it, with no search, no line and no grid. A ticked display being moved snaps
-- its nearest edge or middle, and a resize snaps the edge being pulled, to the nearest line within the snap distance:
-- the grid's, the screen's center and edges, the other displays', the game's party list's and the chat log's, as
-- settings.edit_mode chooses. With every switch off nothing snaps. A display that follows the one being moved moves
-- with it, so it is no line to snap to. While a ticked display is dragged the grid shows if Show the grid is on, with the line it snapped to
-- where the display ended on it. The search keeps its best so far here, so a drag makes nothing each frame.
local snap = {};
local elements = require('ui.elements');
local resize = require('ui.resize');
local theme = require('ui.theme');
local bit = require('bit');
local floor, abs = math.floor, math.abs;

local best, best_line, reach;
-- The lines the last snap met, drawn once by snap.guides, which edge met each ('first' or 'last' for the edge a resize
-- pulls, nil for a move's edges and middle), and the line ends, refilled for each line.
local guide_x, guide_y, edge_x, edge_y;
local from, to = { 0, 0 }, { 0, 0 };

-- Whether display id is ticked for Grid mode, with Grid mode on or off.
function snap.ticked(settings, id)
    local e = type(settings) == 'table' and settings.edit_mode;
    local list = type(e) == 'table' and e.grid_displays;
    if type(list) ~= 'table' then return false; end
    for index = 1, #list do
        if list[index] == id then return true; end
    end
    return false;
end

-- Whether display id snaps: Grid mode is on and id is ticked for it.
function snap.on(settings, id)
    return type(settings) == 'table' and type(settings.edit_mode) == 'table' and settings.edit_mode.grid_mode == true
        and snap.ticked(settings, id);
end

-- Ticks or unticks display id for Grid mode, the list kept in the displays' own order.
function snap.tick(settings, id, on)
    local list = {};
    for _, element in ipairs(elements.movable) do
        local other = element.id;
        if other == id and on or other ~= id and snap.ticked(settings, other) then list[#list + 1] = other; end
    end
    settings.edit_mode.grid_displays = list;
end

local function consider(target, point)
    if point == nil then return; end
    local delta = target - point;
    if abs(delta) <= reach and (best == nil or abs(delta) < abs(best)) then best, best_line = delta, target; end
end

local function lines(rect, axis, first, middle, last)
    if not rect then return; end
    local low = axis == 'x' and rect.x or rect.y;
    local span = axis == 'x' and rect.width or rect.height;
    consider(low, first); consider(low + span / 2, first); consider(low + span, first);
    consider(low, middle); consider(low + span / 2, middle); consider(low + span, middle);
    consider(low, last); consider(low + span / 2, last); consider(low + span, last);
end

-- Whether other follows id, by its anchor, itself or through the displays it follows.
local function rides(settings, other, id)
    local at = elements.follows(settings, other);
    for _ = 1, #elements.list do
        if at == nil then return false; end
        if at == id then return true; end
        at = elements.follows(settings, at);
    end
    return false;
end

-- The shift that puts first, middle or last on the nearest line along one axis, or 0. An edge gives first only.
local function nearest(settings, id, first, middle, last, axis, screen_size)
    local e = settings.edit_mode;
    best, best_line, reach = nil, nil, e.snap_distance;
    if e.snap_grid then
        local grid = e.grid;
        consider(floor(first / grid + 0.5) * grid, first);
        if last then consider(floor(last / grid + 0.5) * grid, last); end
    end
    if e.snap_screen then
        for step = 0, 2 do
            local target = screen_size * step / 2;
            consider(target, first); consider(target, middle); consider(target, last);
        end
    end
    if e.snap_elements then
        for _, element in ipairs(elements.movable) do
            local other = element.id;
            if other ~= id and elements.on(settings, other) and not rides(settings, other, id) then
                lines(elements.drawn(other), axis, first, middle, last);
            end
        end
    end
    if e.snap_party then lines(elements.party_list, axis, first, middle, last); end
    if e.snap_chat then lines(elements.chat, axis, first, middle, last); end
    if axis == 'x' then guide_x = best_line; else guide_y = best_line; end
    return best or 0;
end

-- How far display id, moved to x, y at width by height, shifts to snap. Returns the shift across and down.
function snap.move(settings, id, x, y, width, height, screen_width, screen_height)
    edge_x, edge_y = nil, nil;
    if not snap.on(settings, id) then guide_x, guide_y = nil, nil; return 0, 0; end
    return nearest(settings, id, x, x + width / 2, x + width, 'x', screen_width),
        nearest(settings, id, y, y + height / 2, y + height, 'y', screen_height);
end

-- The shift that puts an edge at at on the whole pixel nearest the line shift away. A line can sit at a half pixel (a
-- middle), and a display's places and sizes are whole pixels, so half a pixel would move the edge across.
local function whole(at, shift)
    if shift == 0 then return 0; end
    return floor(at + shift + 0.5) - at;
end

-- How far the edge or edges a resize of id pulls (edge as resize.active_edge names it) shift to snap; the edges across
-- from them stay put. Returns the shift across and down.
function snap.edge(settings, id, rect, edge, screen_width, screen_height)
    guide_x, guide_y, edge_x, edge_y = nil, nil, nil, nil;
    if not edge or not snap.on(settings, id) then return 0, 0; end
    local dx, dy = 0, 0;
    local right, bottom = rect.x + rect.width, rect.y + rect.height;
    if edge:find('left', 1, true) then dx, edge_x = whole(rect.x, nearest(settings, id, rect.x, nil, nil, 'x', screen_width)), 'first';
    elseif edge:find('right', 1, true) then dx, edge_x = whole(right, nearest(settings, id, right, nil, nil, 'x', screen_width)), 'last'; end
    if edge:find('top', 1, true) then dy, edge_y = whole(rect.y, nearest(settings, id, rect.y, nil, nil, 'y', screen_height)), 'first';
    elseif edge:find('bottom', 1, true) then dy, edge_y = whole(bottom, nearest(settings, id, bottom, nil, nil, 'y', screen_height)), 'last'; end
    return dx, dy;
end

-- A resize of id from start, dx and dy pulling edge, within limits (as resize.rect takes them), with the pulled edge
-- snapped.
function snap.resize(settings, id, start, edge, dx, dy, limits)
    local rect = resize.rect(start, edge, dx, dy, limits);
    local shift_x, shift_y = snap.edge(settings, id, rect, edge, limits.screen_width, limits.screen_height);
    if shift_x == 0 and shift_y == 0 then return rect; end
    return resize.rect(start, edge, dx + shift_x, dy + shift_y, limits);
end

-- The grid on list: a faint line every e.grid pixels and the screen's center lines.
function snap.grid(list, e, width, height)
    local faint, center = 0x18FFFFFF, 0x50FFFFFF;
    for x = e.grid, width - 1, e.grid do
        from[1], from[2], to[1], to[2] = x, 0, x, height;
        list:AddLine(from, to, faint, 1);
    end
    for y = e.grid, height - 1, e.grid do
        from[1], from[2], to[1], to[2] = 0, y, width, y;
        list:AddLine(from, to, faint, 1);
    end
    from[1], from[2], to[1], to[2] = width / 2, 0, width / 2, height;
    list:AddLine(from, to, center, 1);
    from[1], from[2], to[1], to[2] = 0, height / 2, width, height / 2;
    list:AddLine(from, to, center, 1);
end

-- Whether rect has a point on line along axis, within a pixel: the pulled edge (edge 'first' or 'last') for a
-- resize, an edge or the middle for a move.
local function landed(rect, axis, line, edge)
    local low = axis == 'x' and rect.x or rect.y;
    local high = low + (axis == 'x' and rect.width or rect.height);
    if edge ~= 'last' and abs(low - line) < 1 then return true; end
    if edge ~= 'first' and abs(high - line) < 1 then return true; end
    return edge == nil and abs((low + high) / 2 - line) < 1;
end

-- The lines the last snap met, across the screen in color, each only where rect, the display as it is drawn after its
-- rows, its least size and the screen's edges, ended on it. Each is drawn once, and none without a list or a rect.
function snap.guides(list, color, width, height, rect)
    if not rect or guide_x and not landed(rect, 'x', guide_x, edge_x) then guide_x = nil; end
    if not rect or guide_y and not landed(rect, 'y', guide_y, edge_y) then guide_y = nil; end
    if list and guide_x then from[1], from[2], to[1], to[2] = guide_x, 0, guide_x, height; list:AddLine(from, to, color, 1); end
    if list and guide_y then from[1], from[2], to[1], to[2] = 0, guide_y, width, guide_y; list:AddLine(from, to, color, 1); end
    guide_x, guide_y = nil, nil;
end

-- Each frame of a drag of display id, in edit mode or with Shift: while it snaps, the grid while Show the grid is on,
-- behind every display, and the line the drag snapped to over them where rect, the display as it is drawn, ended on
-- it. A display that doesn't snap shows neither. A list the renderer doesn't give is left out.
function snap.show(settings, id, width, height, rect)
    if not snap.on(settings, id) then guide_x, guide_y = nil, nil; return; end
    local imgui = require('imgui');
    local e = settings.edit_mode;
    local back = e.show_grid and imgui.GetBackgroundDrawList();
    if back then snap.grid(back, e, width, height); end
    snap.guides(imgui.GetForegroundDrawList(), bit.bor(theme.u32(settings.style.accent_color), 0xFF000000), width, height, rect);
end

return snap;
