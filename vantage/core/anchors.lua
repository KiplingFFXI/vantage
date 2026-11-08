-- Where an anchored display goes. Each display keeps an anchor beside its own place (ui/elements.lua names them): to
-- a point of the screen, beside another display, beside the game's party list or beside the chat log. Its saved x and
-- y stay as its fallback spot, used while it has no anchor or its anchor isn't on screen. This file only works places
-- out; it reads nothing from the game. It also holds the edit mode settings (settings.edit_mode): Grid mode, the
-- displays ticked for it, the grid and what a move of one of them snaps to.
local anchors = {};
local numbers = require('ui.numbers');
local finite = numbers.finite;

anchors.kinds = { 'none', 'screen', 'element', 'party', 'chat' };
anchors.points = { 'top_left', 'top', 'top_right', 'left', 'center', 'right', 'bottom_left', 'bottom', 'bottom_right' };
anchors.sides = { 'below', 'above', 'left', 'right' };
anchors.aligns = { 'start', 'center', 'end' };

-- How far across the screen and down each point is.
local across = { top_left = 0, top = 0.5, top_right = 1, left = 0, center = 0.5, right = 1, bottom_left = 0, bottom = 0.5, bottom_right = 1 };
local down = { top_left = 0, top = 0, top_right = 0, left = 0.5, center = 0.5, right = 0.5, bottom_left = 1, bottom = 1, bottom_right = 1 };

function anchors.make()
    return { to = 'none', point = 'top_left', dx = 0, dy = 0, element = '', side = 'below', align = 'start', gap = 4, offset = 0 };
end

-- Grid mode starts off with no display ticked for it (grid_displays, a list of ids).
function anchors.make_edit()
    return { grid_mode = false, grid_displays = {}, grid = 16, show_grid = true, snap_grid = true, snap_screen = true,
        snap_elements = true, snap_party = true, snap_chat = true, snap_distance = 8 };
end

local function choice(value, choices, fallback)
    for _, item in ipairs(choices) do if value == item then return value; end end
    return fallback;
end

local function number(value, low, high, fallback)
    return numbers.clamp_round(value, low, high, fallback);
end

-- An anchor from a save or a hand edit. ids names the displays it may follow; own is the display's own id, which it
-- can't follow. An anchor to a display that isn't one of them has no anchor.
function anchors.tidy(value, own, ids)
    local fresh = anchors.make();
    value = type(value) == 'table' and value or {};
    local out = {};
    out.to = choice(value.to, anchors.kinds, 'none');
    out.point = choice(value.point, anchors.points, fresh.point);
    out.dx, out.dy = number(value.dx, -16000, 16000, 0), number(value.dy, -16000, 16000, 0);
    out.element = type(value.element) == 'string' and value.element or '';
    if out.element == own or ids and out.element ~= '' and not ids[out.element] then out.element = ''; end
    if out.to == 'element' and out.element == '' then out.to = 'none'; end
    out.side = choice(value.side, anchors.sides, fresh.side);
    out.align = choice(value.align, anchors.aligns, fresh.align);
    out.gap = number(value.gap, -300, 300, fresh.gap);
    out.offset = number(value.offset, -2000, 2000, 0);
    return out;
end

-- movable is the displays a move can tick for Grid mode (ui/elements.lua elements.movable): the list keeps each of
-- theirs once, in their order, and nothing else.
function anchors.tidy_edit(value, movable)
    local fresh = anchors.make_edit();
    value = type(value) == 'table' and value or {};
    for _, key in ipairs({ 'grid_mode', 'show_grid', 'snap_grid', 'snap_screen', 'snap_elements', 'snap_party', 'snap_chat' }) do
        if type(value[key]) ~= 'boolean' then value[key] = fresh[key]; end
    end
    local ticked, list = {}, {};
    for _, id in ipairs(type(value.grid_displays) == 'table' and value.grid_displays or {}) do
        if type(id) == 'string' then ticked[id] = true; end
    end
    for _, element in ipairs(movable or {}) do
        if ticked[element.id] then list[#list + 1] = element.id; end
    end
    value.grid_displays = list;
    value.grid = number(value.grid, 4, 256, fresh.grid);
    value.snap_distance = number(value.snap_distance, 1, 32, fresh.snap_distance);
    return value;
end

function anchors.active(anchor)
    return type(anchor) == 'table' and anchor.to ~= nil and anchor.to ~= 'none';
end

-- Where a width x height display goes on a screen_width x screen_height screen under anchor, beside target (a
-- rectangle) for the kinds that follow one. Returns x, y, or nothing while the target isn't there.
function anchors.position(anchor, width, height, target, screen_width, screen_height)
    if anchor.to == 'screen' then
        local fx, fy = across[anchor.point] or 0, down[anchor.point] or 0;
        return (screen_width - width) * fx + anchor.dx, (screen_height - height) * fy + anchor.dy;
    end
    if type(target) ~= 'table' or not finite(target.x) or not finite(target.y) or not finite(target.width) or not finite(target.height) then return; end
    local side, gap, align, offset = anchor.side, anchor.gap, anchor.align, anchor.offset;
    local x, y;
    if side == 'left' or side == 'right' then
        x = side == 'right' and target.x + target.width + gap or target.x - width - gap;
        y = target.y + (align == 'center' and (target.height - height) / 2 or align == 'end' and target.height - height or 0) + offset;
    else
        y = side == 'below' and target.y + target.height + gap or target.y - height - gap;
        x = target.x + (align == 'center' and (target.width - width) / 2 or align == 'end' and target.width - width or 0) + offset;
    end
    return x, y;
end

-- Moves an anchored display by dx, dy, keeping its anchor: a screen anchor's distance from its point, or the gap
-- and the offset along the side it is on.
function anchors.move(anchor, dx, dy)
    if anchor.to == 'screen' then
        anchor.dx, anchor.dy = number(anchor.dx + dx, -16000, 16000, 0), number(anchor.dy + dy, -16000, 16000, 0);
        return;
    end
    local side = anchor.side;
    local across_side = side == 'left' or side == 'right';
    local gap = side == 'below' and dy or side == 'above' and -dy or side == 'right' and dx or -dx;
    anchor.gap = number(anchor.gap + gap, -300, 300, anchor.gap);
    anchor.offset = number(anchor.offset + (across_side and dy or dx), -2000, 2000, anchor.offset);
end

return anchors;
