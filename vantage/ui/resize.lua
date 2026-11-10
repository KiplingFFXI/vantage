local resize = {};

local function clamp(value, low, high)
    return math.max(low, math.min(high, value));
end

local function bands(rect, size)
    return math.min(size or 16, rect.width / 3), math.min(size or 16, rect.height / 3);
end

function resize.grip(rect, x, y, size)
    if x < rect.x or y < rect.y or x > rect.x + rect.width or y > rect.y + rect.height then return nil; end
    local bx, by = bands(rect, size);
    local horizontal = x <= rect.x + bx and 'left' or x >= rect.x + rect.width - bx and 'right' or nil;
    local vertical = y <= rect.y + by and 'top' or y >= rect.y + rect.height - by and 'bottom' or nil;
    return vertical and horizontal and vertical .. '_' .. horizontal or horizontal or vertical;
end

function resize.axes(edge)
    return edge ~= nil and (edge:find('left', 1, true) ~= nil or edge:find('right', 1, true) ~= nil),
        edge ~= nil and (edge:find('top', 1, true) ~= nil or edge:find('bottom', 1, true) ~= nil);
end

function resize.active_edge(edge, dx, dy, previous)
    local horizontal, vertical = resize.axes(edge);
    local prior_horizontal, prior_vertical = resize.axes(previous);
    local x = horizontal and (dx ~= 0 or prior_horizontal) and (edge:find('left', 1, true) and 'left' or 'right') or nil;
    local y = vertical and (dy ~= 0 or prior_vertical) and (edge:find('top', 1, true) and 'top' or 'bottom') or nil;
    return x and y and y .. '_' .. x or x or y;
end

function resize.rect(start, edge, dx, dy, limits)
    limits = limits or {};
    local out = { x = start.x, y = start.y, width = start.width, height = start.height };
    local sw, sh = limits.screen_width or 16384, limits.screen_height or 16384;
    local minw, minh = math.min(limits.min_width or 1, sw), math.min(limits.min_height or 1, sh);
    local maxw, maxh = math.max(minw, math.min(limits.max_width or sw, sw)), math.max(minh, math.min(limits.max_height or sh, sh));
    if edge and edge:find('left', 1, true) then
        local anchor = clamp(start.x + start.width, minw, sw);
        out.width = clamp(start.width - dx, minw, math.min(maxw, anchor));
        out.x = anchor - out.width;
    elseif edge and edge:find('right', 1, true) then
        out.x = clamp(start.x, 0, sw - minw);
        out.width = clamp(start.width + dx, minw, math.min(maxw, sw - out.x));
    end
    if edge and edge:find('top', 1, true) then
        local anchor = clamp(start.y + start.height, minh, sh);
        out.height = clamp(start.height - dy, minh, math.min(maxh, anchor));
        out.y = anchor - out.height;
    elseif edge and edge:find('bottom', 1, true) then
        out.y = clamp(start.y, 0, sh - minh);
        out.height = clamp(start.height + dy, minh, math.min(maxh, sh - out.y));
    end
    return out;
end

function resize.cursor(imgui, edge)
    if not imgui.SetMouseCursor then return; end
    if not edge then
        if ImGuiMouseCursor_ResizeAll then imgui.SetMouseCursor(ImGuiMouseCursor_ResizeAll); end;
        return;
    end;
    local horizontal, vertical = resize.axes(edge);
    local cursor;
    if horizontal and vertical then
        cursor = (edge == 'top_left' or edge == 'bottom_right') and ImGuiMouseCursor_ResizeNWSE or ImGuiMouseCursor_ResizeNESW;
    else cursor = horizontal and ImGuiMouseCursor_ResizeEW or ImGuiMouseCursor_ResizeNS; end
    if cursor ~= nil then imgui.SetMouseCursor(cursor); end
end

local handles = {
    { 'top_left', 0, 0 }, { 'top', 0.5, 0 }, { 'top_right', 1, 0 },
    { 'left', 0, 0.5 }, { 'right', 1, 0.5 },
    { 'bottom_left', 0, 1 }, { 'bottom', 0.5, 1 }, { 'bottom_right', 1, 1 },
};
local no_handles = {};

-- Where the displays are, by label, from this Present and the one before (which holds the displays drawn after
-- this one). Each display gives its window as it draws. kind says what else it is: 'party' for the party list
-- strips, 'hint' for one known only from its size label. A display that is on but has nothing to show this
-- Present keeps the place it last had. Size labels and lock notes keep clear of all of them. The host calls
-- resize.frame each Present, after the settings window and before the displays. The entries are reused, so a Present
-- allocates nothing here.
local present, displays = 0, {};
function resize.frame() present = present + 1; end;

function resize.occupy(label, rect, kind)
    local entry = displays[label];
    if not entry then entry = {}; displays[label] = entry; end;
    entry.x, entry.y, entry.width, entry.height = rect.x, rect.y, rect.width, rect.height;
    entry.kind, entry.present = kind, present;
end;

function resize.keep(label)
    local entry = displays[label];
    if entry then entry.present = present; end;
end;

local function current(entry) return entry.present >= present - 1; end;

local function overlaps(a, x, y, width, height)
    return x < a.x + a.width and a.x < x + width and y < a.y + a.height and a.y < y + height;
end;

-- Whether a box at x, y keeps clear of every display but the one named label.
local function clear(label, x, y, width, height)
    for name, other in pairs(displays) do
        if name ~= label and current(other) and overlaps(other, x, y, width, height) then return false; end;
    end;
    return true;
end;

-- Where a note width by height goes beside the display at rect: above it, or below it or inside its top edge where the
-- space above is another display's.
local function beside(rect, label, width, height, screen)
    local x = clamp(rect.x, 2, screen.x - width - 2);
    for try = 1, 3 do
        local y = try == 1 and rect.y - height - 3 or try == 2 and rect.y + rect.height + 3 or rect.y + 3;
        if y >= 2 and y + height <= screen.y - 2 and clear(label, x, y, width, height) then return x, y; end;
    end;
    local y = rect.y - height - 3;
    if y < 2 then y = rect.y + rect.height + 3; end;
    return x, y;
end;

-- What a note hands ImGui, refilled for each call as the binding copies it, and the font its lines are measured in.
local note_min, note_max, note_at = { 0, 0 }, { 0, 0 }, { 0, 0 };
local note_font, note_size;
local function note_width(value) return require('ui.text_metrics').width(note_font, value, note_size); end;

-- A small dark box of text lines for the display at rect, which has to be on screen, placed beside it.
local function note(list, rect, text, look, label)
    local imgui, fonts = require('imgui'), require('ui.fonts');
    local metrics = require('ui.text_metrics');
    local screen = imgui.GetIO().DisplaySize;
    if screen.x < 32 or screen.y < 32 or rect.x >= screen.x or rect.y >= screen.y
        or rect.x + rect.width <= 0 or rect.y + rect.height <= 0 then return; end;
    local font, size = look and look.font or 'Agave', clamp(look and look.font_size or 16, 16, 20);
    note_font, note_size = font, size;
    local lines = metrics.lines(text, math.min(320, screen.x - 4) - 12, note_width, metrics.token(font, size));
    local width, height = 0, math.min(screen.y - 4, #lines * (size + 2) + 8);
    for _, line in ipairs(lines) do width = math.max(width, note_width(line)); end;
    width = math.min(screen.x - 4, width + 12);
    local x, y = beside(rect, label, width, height, screen);
    x, y = math.floor(clamp(x, 2, screen.x - width - 2)), math.floor(clamp(y, 2, screen.y - height - 2));
    -- Draw outside the panel without adding another mouse target.
    note_min[1], note_min[2], note_max[1], note_max[2] = 0, 0, screen.x, screen.y;
    list:PushClipRect(note_min, note_max, false);
    note_min[1], note_min[2], note_max[1], note_max[2] = x, y, x + width, y + height;
    list:AddRectFilled(note_min, note_max, 0xFA171717, 3);
    list:AddRect(note_min, note_max, 0xFFE6D5A8, 3, 0, 1);
    note_min[1], note_min[2], note_max[1], note_max[2] = x + 4, y + 2, x + width - 4, y + height - 2;
    list:PushClipRect(note_min, note_max, true);
    fonts.push(font, size);
    for index, line in ipairs(lines) do
        local top = y + 4 + (index - 1) * (size + 2);
        if not fonts.draw(list, font, line, x + 6, top, size, 0xFFFFFFFF) then
            note_at[1], note_at[2] = x + 6, top;
            list:AddText(imgui.GetFont(), size, note_at, 0xFFFFFFFF, line);
        end;
    end;
    fonts.pop();
    list:PopClipRect();
    list:PopClipRect();
end;

-- The name and size above the display, or below it or inside its top edge where the space above is another
-- display's.
function resize.label(list, rect, label, look)
    if not label or label == '' then return; end;
    local dimensions = ('%d x %d px'):format(math.floor(rect.width + 0.5), math.floor(rect.height + 0.5));
    note(list, rect, label .. '\n' .. dimensions, look, label);
end;

-- While Shift is held with the pointer on a locked display, a note says where to unlock it, placed like a size
-- label so a display drawn later does not cover it. It takes no input, so Shift still never moves a locked
-- display. label is the display's own.
function resize.locked(list, rect, look, label)
    local mx, my = require('imgui').GetMousePos();
    if type(mx) ~= 'number' or type(my) ~= 'number' or mx < rect.x or my < rect.y
        or mx >= rect.x + rect.width or my >= rect.y + rect.height then return; end;
    note(list, rect, 'Locked: unlock it on the main page', look, label);
end;

-- The SAMPLE tag a previewed display wears at its top right corner. Inside it covers the frame's empty corner;
-- outside, for a box or panel whose corners hold its own text or icons, it sits just above, or below near the top
-- of the screen.
-- The tag's points, refilled for each tag, as ImGui copies them.
local ORIGIN, screen_far, tag_at, tag_far, text_at = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };
-- The SAMPLE tags drawn outside their displays this Present, x1, y1, x2, y2 each in one reused table, so edit mode puts
-- a display's name clear of them. A Present holds far fewer than the 32 kept.
local outside_tags, outside_count, outside_present = {}, 0, -1;
function resize.sample(list, rect, look, outside)
    if rect.width < 40 or rect.height < 12 then return; end;
    local imgui, fonts = require('imgui'), require('ui.fonts');
    local font, size = look and look.font or 'Agave', 11;
    local width = require('ui.text_metrics').width(font, 'SAMPLE', size) + 6;
    local x, y = math.floor(rect.x + rect.width - width - 2), math.floor(rect.y + 2);
    if outside then
        y = math.floor(rect.y - size - 5);
        if y < 0 then y = math.floor(rect.y + rect.height + 2); end;
        if outside_present ~= present then outside_present, outside_count = present, 0; end;
        if outside_count < 32 then
            local at = outside_count * 4;
            outside_tags[at + 1], outside_tags[at + 2], outside_tags[at + 3], outside_tags[at + 4] = x, y, x + width, y + size + 3;
            outside_count = outside_count + 1;
        end;
        local screen = imgui.GetIO().DisplaySize;
        screen_far[1], screen_far[2] = screen.x, screen.y;
        list:PushClipRect(ORIGIN, screen_far, false);
    end;
    tag_at[1], tag_at[2], tag_far[1], tag_far[2] = x, y, x + width, y + size + 3;
    list:AddRectFilled(tag_at, tag_far, 0xD8171717, 2);
    fonts.push(font, size);
    if not fonts.draw(list, font, 'SAMPLE', x + 3, y + 1, size, 0xFF5AD8FF) then
        text_at[1], text_at[2] = x + 3, y + 1;
        list:AddText(imgui.GetFont(), size, text_at, 0xFF5AD8FF, 'SAMPLE');
    end;
    fonts.pop();
    if outside then list:PopClipRect(); end;
end;

-- The top and bottom of a SAMPLE tag drawn outside its display this Present that a box at x, y, width wide and height
-- high would touch, or nil.
function resize.sample_tag(x, y, width, height)
    if outside_present ~= present then return nil; end;
    for index = 0, outside_count - 1 do
        local at = index * 4;
        if x < outside_tags[at + 3] and x + width > outside_tags[at + 1] and y < outside_tags[at + 4] and y + height > outside_tags[at + 2] then
            return outside_tags[at + 2], outside_tags[at + 4];
        end;
    end;
    return nil;
end;

-- The tooltips and lists the settings window drew this Present, which no sample may cover: up to four, x1, y1, x2, y2
-- each in one reused table. The window draws before the displays, so its tooltip has its place first. popup says one
-- of them is an open list.
local covers, cover_count, cover_present, cover_popup = {}, 0, -1, false;
function resize.cover(imgui, popup)
    if cover_present ~= present then cover_count, cover_present, cover_popup = 0, present, false; end;
    if popup then cover_popup = true; end;
    if cover_count >= 4 then return; end;
    local x, y = imgui.GetWindowPos();
    local width, height = imgui.GetWindowSize();
    if type(x) ~= 'number' or type(y) ~= 'number' or type(width) ~= 'number' or type(height) ~= 'number' then return; end;
    local at = cover_count * 4;
    covers[at + 1], covers[at + 2], covers[at + 3], covers[at + 4] = x, y, x + width, y + height;
    cover_count = cover_count + 1;
end;

-- A SAMPLE tag drawn outside its display sits just above or below it (resize.sample).
local TAG = 16;
-- Whether the display at rect, band px higher and lower for its tag, is under a tooltip or list the settings window
-- drew this Present, or a list not known here, such as a color picker's, is open.
local function covered(imgui, rect, band)
    -- The host counts a new Present after the settings window draws, so what the window drew this frame has the count before.
    local open = cover_present == present - 1;
    if not (open and cover_popup) and imgui.IsPopupOpen and imgui.IsPopupOpen('', ImGuiPopupFlags_AnyPopup or 3072) then return true; end;
    if not open then return false; end;
    local top, bottom = rect.y - band, rect.y + rect.height + band;
    for index = 0, cover_count - 1 do
        local at = index * 4;
        if rect.x < covers[at + 3] and rect.x + rect.width > covers[at + 1] and top < covers[at + 4] and bottom > covers[at + 2] then return true; end;
    end;
    return false;
end;

-- While the settings window is open, a display showing samples draws over it on the foreground draw list, as overhead
-- samples do, so the window can't hide them. The one the mouse is over, or its SAMPLE tag, stays in its own window
-- behind the settings, for as long as the mouse is on it, so the controls under it and its details show; so does one
-- under a tooltip or list of the settings window. Clicks go to the settings either way. over says the display shows
-- samples with the window open, and tagged that it wears its tag outside. Returns the list to draw on and whether it
-- is the foreground's, clipped as the display's window clips; the display pops that clip before it ends its window.
local clip_min, clip_max = { 0, 0 }, { 0, 0 };
function resize.sample_list(imgui, over, rect, mx, my, tagged)
    local list = imgui.GetWindowDrawList();
    local band = tagged and TAG or 0;
    if not over or mx >= rect.x and my >= rect.y - band and mx < rect.x + rect.width and my < rect.y + rect.height + band
        or covered(imgui, rect, band) then return list, false; end;
    local top = imgui.GetForegroundDrawList();
    if not top then return list, false; end;
    local x1, y1 = list:GetClipRectMin();
    local x2, y2 = list:GetClipRectMax();
    if type(x1) ~= 'number' or type(y1) ~= 'number' or type(x2) ~= 'number' or type(y2) ~= 'number' then
        x1, y1, x2, y2 = rect.x, rect.y, rect.x + rect.width, rect.y + rect.height;
    end;
    clip_min[1], clip_min[2], clip_max[1], clip_max[2] = x1, y1, x2, y2;
    top:PushClipRect(clip_min, clip_max, false);
    return top, true;
end;

-- What a hint hands ImGui, refilled for each call as the binding copies it.
local hint_min, hint_max = { 0, 0 }, { 0, 0 };
local function edge_line(list, x1, y1, x2, y2)
    hint_min[1], hint_min[2], hint_max[1], hint_max[2] = x1, y1, x2, y2;
    list:AddLine(hint_min, hint_max, 0xFFFFFFFF, 2);
end;
-- move_only leaves out the handles on the edges and corners, for a display that moves but can't be resized.
function resize.hint(list, rect, color, edge, label, look, move_only)
    if rect.width <= 0 or rect.height <= 0 then return; end;
    -- A display that gave its window this Present keeps that; the label only fills in for one that didn't.
    local entry = label and displays[label];
    if label and not (entry and entry.present == present) then resize.occupy(label, rect, 'hint'); end;
    color = require('bit').bor(color, 0xFF000000);
    local bx, by = bands(rect);
    local width, height = math.min(8, bx), math.min(8, by);
    local inset = math.min(1, rect.width / 4, rect.height / 4);
    hint_min[1], hint_min[2] = rect.x + inset, rect.y + inset;
    hint_max[1], hint_max[2] = rect.x + rect.width - inset, rect.y + rect.height - inset;
    list:AddRect(hint_min, hint_max, 0xFF000000, 0, 0, 3);
    list:AddRect(hint_min, hint_max, color, 0, 0, 1);
    for _, handle in ipairs(move_only and no_handles or handles) do
        local x = rect.x + bx / 2 + (rect.width - bx) * handle[2];
        local y = rect.y + by / 2 + (rect.height - by) * handle[3];
        local active = edge == handle[1];
        hint_min[1], hint_min[2] = math.max(rect.x, x - width / 2), math.max(rect.y, y - height / 2);
        hint_max[1], hint_max[2] = math.min(rect.x + rect.width, x + width / 2), math.min(rect.y + rect.height, y + height / 2);
        list:AddRectFilled(hint_min, hint_max, active and 0xFFFFFFFF or color);
        list:AddRect(hint_min, hint_max, 0xFF000000, 0, 0, active and 2 or 1);
    end;
    if edge then
        local left, right = rect.x + bx / 2, rect.x + rect.width - bx / 2;
        local top, bottom = rect.y + by / 2, rect.y + rect.height - by / 2;
        if edge:find('left', 1, true) then edge_line(list, left, top, left, bottom); end;
        if edge:find('right', 1, true) then edge_line(list, right, top, right, bottom); end;
        if edge:find('top', 1, true) then edge_line(list, left, top, right, top); end;
        if edge:find('bottom', 1, true) then edge_line(list, left, bottom, right, bottom); end;
    end
    resize.label(list, rect, label, look);
end

return resize;
