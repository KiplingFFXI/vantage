local overlay = {};
local layout = require('ui.party_layout');
local resize = require('ui.resize');
local elements = require('ui.elements');
local snap = require('ui.snap');
local theme = require('ui.party_theme');
local fonts = require('ui.fonts');
local party_hud = require('ui.party_hud');
local labels = require('ui.party_labels');
local effect_filters = require('core.effect_filters');
local dispel = require('core.dispel');
local countdown = require('ui.countdown_text');
local party_distance = require('core.party_distance');
local strip_keys = require('ui.party_defaults').strips;
local gesture;
-- Each strip's name on its size label, lock note and place, as edit mode names them.
local strip_labels = { 'Your party', 'Alliance 1', 'Alliance 2' };
local unavailable_reason = 'Effect information is unavailable. A blank list does not confirm that this member has no effects.';
-- The vectors the window and its paint hand ImGui, refilled for each call: the binding copies them and keeps none.
local ZERO, ONE, corner, far_corner, extent = { 0, 0 }, { 1, 1 }, { 0, 0 }, { 0, 0 }, { 0, 0 };
local clip_min, clip_max, text_at = { 0, 0 }, { 0, 0 }, { 0, 0 };
-- What a draw hands back when there's nothing, the same empty table each time: no caller adds to it.
local NONE = {};
-- What a draw works out for its rows and cells. party_layout tells one draw from the next by this table, so two are
-- taken in turn, each emptied as its draw starts, and a draw still brings a cache the last one didn't have.
local effect_caches, cache_turn = { {}, {} }, 1;

local function clamp(value, low, high)
    return math.max(low, math.min(high, value));
end

local function side_for(config, saved)
    return saved.native_side == 'left' and 'left' or saved.native_side == 'right' and 'right' or config.native.side;
end

local metrics = require('ui.text_metrics');
local render_cache = require('ui.render_cache');
local function measured(look, value)
    return metrics.width(look.font, value, look.font_size);
end

local function paint_caption(imgui, list, look, value, x, y, ink)
    fonts.paint(imgui, list, look, value, x, y, look.font_size, ink);
end

local function caption(imgui, list, look, value, x, y, width, rgba)
    if width <= 0 then return; end;
    local ink = theme.u32(rgba or look.colors.text, look.opacity);
    clip_min[1], clip_min[2], clip_max[1], clip_max[2] = x, y, x + width, y + look.font_size + 3;
    list:PushClipRect(clip_min, clip_max, true);
    local ok, err = pcall(paint_caption, imgui, list, look, value, x, y, ink);
    list:PopClipRect();
    if not ok then error(err, 0); end;
end

-- Whether this frame's strips show the members' party cooldowns (core/party_cooldowns.lua), set by overlay.draw, and
-- the one-entry lists the samples hand the first sample members.
local show_cooldowns = false;
local sample_cooldowns = { {}, {}, {}, {}, {} };
-- The sample members' effects, made once and moved to each frame's time, and the map of them by member each frame.
local sample_subjects, shown_samples = nil, {};
-- Where a row's party cooldown cells go: count cells of size px across width from x, nearest the game's window
-- first. Kept on the row from frame to frame.
local function cooldown_cells(item, x, y, width, size, count, align_right)
    local cells = item.cooldown_cells or {};
    cells.x, cells.y, cells.width, cells.height, cells.cell, cells.count, cells.align_right = x, y, width, size, size, count, align_right;
    item.cooldown_cells = cells;
    return cells;
end

-- A member's distance (core/party_distance.lua) in tenths and whether it's past the warning pick: the sample for their
-- slot while samples show, else their own, never on your row. nil when there's none.
local function distance_of(config, roster, member)
    if config.preview then return party_distance.sample(member.slot, member.group, config.distance_warn); end;
    if member.id == roster.id then return nil; end;
    return member.tenths, member.far;
end

-- The main page's Ending soon and alerts color, or the Phoenix skin's when there's no style.
local phoenix_warning;
local function warning_color(style)
    if type(style) == 'table' and type(style.warning_color) == 'table' then return style.warning_color; end;
    phoenix_warning = phoenix_warning or require('ui.theme').colors('Phoenix').warning_color;
    return phoenix_warning;
end

-- How tall a number may be beside the game's list, as a share of the row, for each Distance size past Small
-- (ui/party_defaults.lua).
local DISTANCE_SHARE = { medium = 0.7, large = 0.8, largest = 0.9 };

-- The distance's text size and column beside the game's list, for the Distance size pick. Small is the size the numbers
-- started at, 0.6 of the icons' room and never under 8 px. Past Small the size is the biggest whose digits, with their
-- outline and shadow, are no taller than the pick's share of the room or of the step between rows, whichever is less,
-- so there's space before the next member's number. It's never under Small, as every font but Original FFXI and XI
-- View is measured by its whole line, which is taller than its digits, and can fit under it. Where the step isn't a
-- whole pixel the rooms overlap by 1 px, which is why the step counts too. The search starts from the digits' height
-- at 16 px, moves one pixel at a time and stays from Small to twice the room. The column fits the widest number at
-- that size, plus 4 px before the icons.
local function distance_fit(look, options, room, pitch, pick)
    local font, share = look.font, DISTANCE_SHARE[pick];
    local small, most = math.max(8, math.floor(room * 0.6 + 0.5)), math.max(8, room * 2);
    local size = small;
    if share then
        if type(pitch) == 'number' and pitch >= 1 then room = math.min(room, math.floor(pitch + 0.001)); end;
        local digits, tallest = '0123456789', math.floor(room * share + 0.001);
        local _, top, _, bottom = countdown.padding(options);
        local ink = select(2, countdown.measure(font, digits, 16, options, true)) - top - bottom;
        size = math.max(small, math.min(most, math.floor((tallest - top - bottom) * 16 / math.max(1, ink))));
        while size > small and select(2, countdown.measure(font, digits, size, options, true)) > tallest do
            size = size - 1;
        end;
        while size < most and select(2, countdown.measure(font, digits, size + 1, options, true)) <= tallest do
            size = size + 1;
        end;
    end;
    local zeros = countdown.measure(font, '00.0', size, options, true);
    local eights = countdown.measure(font, '88.8', size, options, true);
    return size, math.ceil(math.max(zeros, eights)) + 4;
end

-- A member's distance in its column beside the game's list, in the countdowns' look and color, or ink past the pick.
-- It's right-aligned so the points line up, against the game's window on the left side and 4 px short of the icons
-- on the right. Gives the member when the mouse is on the column.
local function paint_distance(list, look, config, roster, item, plain, ink, mx, my)
    local cell, member = item.distance_cell, item.member;
    local tenths, far = distance_of(config, roster, member);
    if not tenths then return nil; end;
    local text = party_distance.text(tenths);
    local width, height = countdown.measure(look.font, text, cell.size, item.options, true);
    local right = cell.align_right and cell.x + cell.width or cell.x + cell.width - 4;
    countdown.draw(list, look.font, text, right - width, cell.y + math.max(0, (cell.height - height) / 2), cell.size,
        far and ink or plain, item.options, true, text_at);
    if mx and mx >= cell.x and mx < cell.x + cell.width and my >= cell.y and my < cell.y + cell.height then return member; end;
end

-- A member's distance at the end of their name's first line in a panel of its own, at y, in the text color or the
-- warning color past the pick. Gives where it starts, or nil when there's none.
local function paint_panel_distance(imgui, list, look, config, roster, item, warning, y)
    local tenths, far = distance_of(config, roster, item.member);
    if not tenths then return nil; end;
    local text = party_distance.text(tenths);
    local width = math.ceil(measured(look, text)) + 1;
    local x = item.distance_right - width;
    caption(imgui, list, look, text, x, y, width, far and warning or nil);
    return x;
end

-- Whether base still holds every effect setting, and nothing more.
local function same_settings(base, effects)
    for key, value in pairs(effects) do if base[key] ~= value then return false; end; end;
    for key in pairs(base) do if effects[key] == nil then return false; end; end;
    return true;
end

-- A detached strip's effect options: the strip's effect settings, then wrapping, the font and the room. Kept in held
-- from frame to frame until a setting, the font or the room changes.
local function detached_options(held, effects, look, measure_key, available)
    local options = held.options;
    if options and held.source == effects and held.font == look.font
        and held.measure_key == measure_key and held.available == available and same_settings(held.base, effects) then
        return options;
    end;
    local base = {};
    options = {};
    for key, value in pairs(effects) do options[key], base[key] = value, value; end;
    options.selection_options, options.wrap, options.rows, options.auto_rows = effects, true, 32, true;
    options.measure_key = measure_key;
    options.countdown_font = look.font;
    held.options, held.base, held.source, held.font = options, base, effects, look.font;
    held.measure_key, held.available = measure_key, available;
    return options;
end

-- Lays out a detached strip's rows from y into held.rows, each row's item kept in held.items. Returns the minimum
-- width, the width and x it settles on, and where the rows end.
local function detached_rows(held, members, subjects, config, saved, group, width, y, w, look, measure_key, cache)
    local effects, measure_text, rows, used = config.effects, held.measure_text, held.rows, 0;
    -- The distance goes at the end of each name's first line, as wide as its widest number with 6 px before it, and
    -- the name wraps short of it.
    local room = config.distance and math.ceil(math.max(measure_text('00.0'), measure_text('88.8'))) + 6 or 0;
    local minimum = math.max(40,math.ceil(math.max(measure_text('W'),measure_text('M'),measure_text('0'))+30)) + room;
    minimum = math.max(minimum, effects.icon_size + 30);
    w = math.min(math.max(w,minimum),width);
    local x = clamp(saved.detached_x or 40,0,width-w);
    local available,top = math.max(1,w-30),y+6;
    local options = detached_options(held, effects, look, measure_key, available);
    for _, member in ipairs(members) do
        if type(member.id) == 'number' and member.id > 0 and type(member.slot) == 'number'
            and member.slot == math.floor(member.slot) and math.floor(member.slot / 6)+1 == group then
            local lines = metrics.lines(labels.member_name(member, config), math.max(1, available - room), measure_text,
                options.measure_key);
            local subject = subjects[member.id];
            used = used + 1;
            local item = held.items[used];
            if not item then
                item = { selection = {}, sizing = {}, cells = {} };
                held.items[used] = item;
            end;
            -- Worked out once a frame here; the paint draws this list.
            item.effects = layout.kept_effects(item.selection, subject, options, cache);
            -- The member's party cooldowns take the start of the effect area, one cell each, as many as fit. The
            -- effects go after them while a whole icon fits there, and on the rows below them when not.
            local watched = show_cooldowns and subject and subject.cooldowns or nil;
            local size = options.icon_size;
            local fit = watched and math.min(#watched, math.floor((available + 3) / (size + 3))) or 0;
            local reserved = fit * (size + 3);
            local under = fit > 0 and #item.effects > 0 and available - reserved < size;
            local effect_width = under and available or math.max(1, available - reserved);
            local effect_height = layout.kept_effect_height(item.sizing, subject, item.effects, options, effect_width);
            local label_height = #lines*(look.font_size+2);
            local area, cooldown_y = item.area or {}, top+label_height+3;
            if under then
                area.x, area.y, area.width, area.height = x+6, cooldown_y+size+3, effect_width, effect_height;
            else
                area.x, area.y, area.width = x+6+reserved, cooldown_y, effect_width;
                area.height = math.max(effect_height, fit > 0 and size or 0);
            end;
            item.cooldowns = fit > 0 and watched or nil;
            item.cooldown_area = fit > 0 and cooldown_cells(item, x+6, cooldown_y, reserved, size, fit, false) or nil;
            item.member, item.options, item.area, item.label_y, item.label_lines = member, options, area, top, lines;
            -- The name has a line of its own above the cooldowns and effects, so it starts at the row's start with the
            -- whole width it was wrapped to, wherever the cooldowns put the effects. The distance ends at the row's
            -- end.
            item.label_x, item.label_width = x+6, math.max(1, available - room);
            item.distance_right = room > 0 and x+6+available or nil;
            rows[used] = item;
            top = area.y+area.height+8;
        end;
    end;
    for index = #rows, used + 1, -1 do rows[index] = nil; end;
    return minimum, w, x, top;
end

-- held keeps the plan, its rows, each row's item and the options from frame to frame; a new one makes every table new.
local function detached_plan(members, subjects, config, saved, group, width, height, cache, look, held)
    local w = math.min(saved.detached_width or config.native.width, width);
    local h = math.min(saved.detached_height or 240, height);
    local x, y = clamp(saved.detached_x or 40, 0, width-w), clamp(saved.detached_y or 160, 0, height-h);
    local measure_key = metrics.token(look.font,look.font_size);
    -- Widths measured with this font and size; the measure reads the look of this frame. They're capped, as members
    -- come and go all session.
    if held.widths_key ~= measure_key then held.widths, held.widths_key = render_cache.new(512), measure_key; end;
    held.look = look;
    if not held.measure_text then
        held.measure_text = function(value)
            local widths = held.widths;
            local width = widths:get(value);
            if width == nil then width = widths:put(value, measured(held.look, value)); end;
            return width;
        end;
    end;
    fonts.push(look.font, look.font_size);
    -- On an error, minimum holds it.
    local ok, minimum, settled, left, top = pcall(detached_rows, held, members, subjects, config, saved, group, width, y, w, look,
        measure_key, cache);
    fonts.pop();
    if not ok then error(minimum, 0); end;
    w, x = settled, left;
    if #held.rows == 0 then return nil; end;
    local plan = held.plan or {};
    held.plan = plan;
    plan.group, plan.rows, plan.x, plan.y, plan.width, plan.height, plan.detached = group, held.rows, x, y, w, h, true;
    plan.content_height, plan.look, plan.min_width = top-y, look, minimum;
    return plan;
end

function overlay.snap(config, group, rect, geometry)
    if config.native.snap == false or not geometry or not geometry.available then return false; end;
    local frame = geometry.groups and geometry.groups[group];
    if not frame or math.abs(rect.y-frame.y) > 12 then return false; end;
    local left = math.abs(rect.x+rect.width-(frame.x-config.native.gap));
    local right = math.abs(rect.x-(frame.x+frame.width+config.native.gap));
    if math.min(left,right) > 12 then return false; end;
    local saved = config.groups[group];
    saved.native_side = left <= right and 'left' or 'right';
    saved.native_detached, saved.native_x, saved.native_y = false, 0, 0;
    return true;
end

function overlay.cancel_layout_gesture()
    if not gesture then return; end;
    local previous = gesture;
    gesture = nil;
    if previous.started and previous.callbacks.end_edit then previous.callbacks.end_edit(); end;
    if previous.dirty and previous.callbacks.changed then previous.callbacks.changed(); end;
end

-- Whether the Party, Alliance 1 or Alliance 2 strip is switched on.
function overlay.shown(config, group)
    local strips = config.strips;
    return type(strips) ~= 'table' or strips[strip_keys[group]] ~= false;
end

-- The room in whole pixels for each member's icons beside the game's rows, never less than the row's height: the whole
-- pitch, the step between the group's rows, rounded up, so one member's icons touch the next member's. Where the step
-- isn't a whole number of pixels they overlap by at most 1 px and never leave a gap. Without a pitch it is the row's
-- height. The 0.001 keeps a row or step that float error put a hair off a whole pixel on that pixel.
function overlay.room(row_height, pitch)
    local room = math.floor(row_height + 0.001);
    if type(pitch) == 'number' then room = math.max(room, math.ceil(pitch - 0.001)); end;
    return room;
end

-- Space in a stack beside the game's list, which Icon size beside the game's list makes when it's bigger than the rows:
-- under each name, after each member, and between one group's stack and the next.
local NAME_GAP, MEMBER_GAP, STACK_GAP = 2, 4, 8;
local SIDES = { 'left', 'right' };

-- How tall one member is in a stack at icon size px, and how tall their icons are: the icon, with the countdown under
-- it while that's where countdowns go, as tall as any of the digits and h, m and s it may show. The icons' height is
-- kept in sizes by px until the font or the countdowns change, so a frame measures nothing. A client font's isn't
-- kept, as it measures true only once it's loaded.
local function stack_line(sizes, look, effects, px)
    local below = effects.timers == true and effects.icon_countdown_position ~= 'inside';
    if sizes.font ~= look.font or sizes.below ~= below or sizes.countdown_size ~= effects.icon_countdown_size
        or sizes.countdown_gap ~= effects.icon_countdown_gap or sizes.bold ~= effects.countdown_bold
        or sizes.shadow ~= effects.countdown_shadow or sizes.outline ~= effects.countdown_outline then
        sizes.font, sizes.below, sizes.countdown_size, sizes.countdown_gap = look.font, below, effects.icon_countdown_size,
            effects.icon_countdown_gap;
        sizes.bold, sizes.shadow, sizes.outline = effects.countdown_bold, effects.countdown_shadow, effects.countdown_outline;
        for key in pairs(sizes.cells) do sizes.cells[key] = nil; end;
    end;
    local cell = sizes.cells[px];
    if not cell then
        cell = px;
        if below then
            local _, _, height, gap = countdown.icon_values(look.font, '0123456789hms', px, effects);
            cell = cell + gap + math.ceil(height);
        end;
        if not fonts.is_bitmap(look.font) then sizes.cells[px] = cell; end;
    end;
    return look.font_size + 2 + NAME_GAP + cell + MEMBER_GAP, cell;
end

-- Whether the stacks at icon size px fit on the screen. A group stacks when px is bigger than its room. On each side of
-- the game's lists the lowest group's stack ends where its last row does, and each one above it ends STACK_GAP over the
-- stack under it when that's higher than its own last row. Fills sizes.bottom with where each one ends.
local function pile(sizes, look, effects, px, height)
    local line, piled = stack_line(sizes, look, effects, px), sizes.piled;
    for _, side in ipairs(SIDES) do
        local limit = height;
        for group = 1, 3 do piled[group] = false; end;
        for _ = 1, 3 do
            local lowest;
            for group = 1, 3 do
                if not piled[group] and sizes.count[group] > 0 and sizes.side[group] == side and sizes.room[group] < px
                    and (not lowest or sizes.last[group] > sizes.last[lowest]) then lowest = group; end;
            end;
            if not lowest then break; end;
            piled[lowest] = true;
            local bottom = math.min(sizes.last[lowest], limit);
            local top = bottom - sizes.count[lowest] * line + MEMBER_GAP;
            if top < 0 then return false; end;
            sizes.bottom[lowest], limit = bottom, top - STACK_GAP;
        end;
    end;
    return true;
end

local function new_sizes()
    return { count = { 0, 0, 0 }, room = { 0, 0, 0 }, last = { 0, 0, 0 }, side = {}, piled = {}, bottom = {}, size = {},
        stacked = {}, cells = {} };
end

-- The icon size Icon size beside the game's list gives each group beside the game's list, in sizes.size: nil fills
-- each row, a smaller size goes in the middle of each row, and a bigger one makes a stack (sizes.stacked). When the
-- stacks don't fit on the screen they all take the biggest size that does, and a group whose rows are at least that
-- big fills them. sizes.wanted says a group's rows are smaller than the size picked, and sizes.any that one stacks.
local function beside_sizes(roster, config, geometry, look, height, sizes)
    local chosen = config.native.icon_size or 0;
    sizes.chosen, sizes.wanted, sizes.any = chosen, false, false;
    for group = 1, 3 do
        local frame, saved = geometry and geometry.available and geometry.groups[group], config.groups[group];
        local count, room, last = 0, 0, 0;
        if frame and overlay.shown(config, group) and not saved.native_detached then
            for _, member in ipairs(roster.members) do
                local row = frame.rows[member.slot];
                if member.group == group and row and (config.include_self or member.id ~= roster.id) then
                    count, room = count + 1, math.max(room, overlay.room(row.height, frame.pitch));
                    last = math.max(last, row.y + row.height);
                end;
            end;
        end;
        sizes.count[group], sizes.room[group], sizes.last[group], sizes.side[group] = count, room, last, side_for(config, saved);
        sizes.size[group], sizes.stacked[group] = nil, false;
        if count > 0 and chosen > room then sizes.wanted = true; end;
    end;
    if chosen <= 0 then return sizes; end;
    local px = chosen;
    if not pile(sizes, look, config.effects, px, height) then
        -- Found by halves: a smaller size makes every stack shorter, and one no bigger than each group's room makes none.
        local low, high = 1, chosen - 1;
        px = 0;
        while low <= high do
            local middle = math.floor((low + high) / 2);
            if pile(sizes, look, config.effects, middle, height) then px, low = middle, middle + 1; else high = middle - 1; end;
        end;
        if px > 0 then pile(sizes, look, config.effects, px, height); end;
    end;
    for group = 1, 3 do
        local room = sizes.room[group];
        if sizes.count[group] > 0 then
            if px > room then sizes.size[group], sizes.stacked[group], sizes.any = px, true, true;
            elseif chosen < room then sizes.size[group] = chosen; end;
        end;
    end;
    return sizes;
end

-- A stack's members go in the order of the game's rows, top to bottom.
local function by_row(a, b) return a.row.y < b.row.y or a.row.y == b.row.y and a.member.slot < b.member.slot; end

-- The tallest of a group's member rows, and how many there are, from the game's geometry.
local function tallest(frame)
    local height, count = 0, 0;
    for _, row in pairs(frame.rows or {}) do height, count = math.max(height, row.height), count + 1; end;
    return type(frame.row_height) == 'number' and frame.row_height or height, count;
end

-- For each shown strip whose group the game's party list has, in group order, the room its members' icons get, so
-- the settings and the strips agree: { group, row_height, pitch, room, measured_by,
-- attached, members }. pitch is nil when nothing measured it, and measured_by says where it came from: 'rows',
-- 'empty_slots', 'session' or 'none'. attached is false for a strip in a panel of its own. members counts the group's
-- rows, yours included. geometry is core/native_party_ui's, as native.geometry or its live_status() gives it, or the
-- copy its status() gives. Without one the list is empty. out, when given, is the list to fill, its entries used
-- again, so a page that asks each frame makes nothing.
function overlay.rooms(config, geometry, out)
    out = out or {};
    local count = 0;
    if type(geometry) == 'table' and geometry.available and type(geometry.groups) == 'table' then
        for group = 1, 3 do
            local frame = geometry.groups[group];
            if type(frame) == 'table' and overlay.shown(config, group) then
                local height, members = tallest(frame);
                local pitch, saved = frame.pitch, config.groups[group];
                count = count + 1;
                local entry = out[count] or {};
                out[count] = entry;
                entry.group, entry.row_height, entry.pitch = group, height, pitch;
                entry.room = overlay.room(height, pitch);
                entry.measured_by = frame.measured_by or (pitch and 'rows' or 'none');
                entry.attached, entry.members = not (type(saved) == 'table' and saved.native_detached), members;
            end;
        end;
    end;
    for index = #out, count + 1, -1 do out[index] = nil; end;
    return out;
end

-- A copy of the strips' effect settings, made again only when a setting changes or another table holds them. A plan
-- asks once for all its rows, not once a row, and a row whose options were made from this copy is up to date.
local made_from = {};
local function effect_settings(effects)
    if made_from.source ~= effects or not same_settings(made_from.base, effects) then
        local base = {};
        for key, value in pairs(effects) do base[key] = value; end;
        made_from.source, made_from.base = effects, base;
    end;
    return made_from.base;
end

-- A row's effect options: the strip's effect settings, then the row's font and sizes. Icons are room big, the row's
-- whole room or the size Icon size beside the game's list gives, whatever size the panel setting holds, and touch with
-- no space between them. A row kept from the frame before keeps its table until
-- a setting, the font or the row's room changes. base is the copy effect_settings gives.
local function row_options(item, effects, look, measure_key, room, base)
    local options = item.options;
    local stale = not options or item.source ~= effects or item.font ~= look.font or item.measure_key ~= measure_key
        or item.room ~= room or item.base ~= base;
    if not stale then return options; end;
    options = {};
    for key, value in pairs(effects) do options[key] = value; end;
    options.selection_options = effects;
    options.countdown_font = look.font;
    options.measure_key = measure_key;
    options.icon_size, options.cell_gap = room, 0;
    options.fixed_countdown_slot = true;
    options.rows, options.wrap, options.separate = 1, false, false;
    item.options, item.base, item.source, item.font, item.measure_key, item.room = options, base, effects, look.font, measure_key, room;
    return options;
end

-- What the draw keeps from frame to frame: the plans it hands out, the members of each group, and for each group the
-- plan beside the game's window and the plan moved off it, their rows and each row's options, effects and cells, and
-- the icon sizes beside the game's list.
local kept = { plans = {}, members = { {}, {}, {} },
    groups = { { rows = {}, items = {} }, { rows = {}, items = {} }, { rows = {}, items = {} } },
    detached = { { rows = {}, items = {} }, { rows = {}, items = {} }, { rows = {}, items = {} } }, sizes = new_sizes() };

-- A gesture keeps the plan it started on, so a kept plan the next frames refill is copied for it.
local function held_plan(plan)
    local copy = {};
    for key, value in pairs(plan) do copy[key] = value; end;
    return copy;
end

-- The offsets x and y put a strip beside the game's list at on the screen: kept to the ones its plan says still move
-- it, then to the saved range, in whole pixels.
local function drawn_offsets(plan, x, y)
    if plan and plan.offset_x_min then
        x, y = clamp(x, plan.offset_x_min, plan.offset_x_max), clamp(y, plan.offset_y_min, plan.offset_y_max);
    end;
    return math.floor(clamp(x, -2000, 2000)), math.floor(clamp(y, -2000, 2000));
end

-- Edit mode moves a group's strip from where it is drawn, and saves no more than still moves it.
function overlay.drawn_offsets(group, x, y) return drawn_offsets(kept.groups[group].plan, x, y); end

-- What the last draw made of Icon size beside the game's list at size: whether a group's rows are smaller than it, and
-- whether any group stacks. Both nil when the last draw went by another size.
function overlay.stacks(size)
    local sizes = kept.sizes;
    if sizes.chosen ~= size then return nil, nil; end;
    return sizes.wanted, sizes.any;
end

local function plan_into(store, roster, subjects, config, geometry, width, height, cache, global_style, revision)
    local plans, members, count = store and store.plans or {}, nil, 0;
    overlay.no_room = false;
    if width <= 0 or height <= 0 then
        for index = #plans, 1, -1 do plans[index] = nil; end;
        return plans;
    end;
    local look = theme.party(config, global_style, revision);
    local sizes = beside_sizes(roster, config, geometry, look, height, store and store.sizes or new_sizes());
    -- The copy of the effect settings, asked for by the first strip beside the game's list.
    local settings;
    for group = 1, 3 do
        local frame, saved = geometry and geometry.available and geometry.groups[group], config.groups[group];
        local shown = overlay.shown(config, group);
        if saved.native_detached and shown then
            members = members or layout.groups(roster, config, store and store.members);
            local held = store and store.detached[group] or { rows = {}, items = {} };
            local plan = detached_plan(members[group], subjects, config, saved, group, width, height, cache, look, held);
            if plan then count = count + 1; plans[count] = plan; end;
        elseif frame and shown then
            settings = settings or effect_settings(config.effects);
            local held = store and store.groups[group];
            local rows, items, needed, used = held and held.rows or {}, held and held.items, 0, 0;
            -- The size Icon size beside the game's list gives this group's icons, nil to fill each row, and whether
            -- they go in a stack.
            local px, stacked = sizes.size[group], sizes.stacked[group];
            local measure_key = metrics.token(look.font,look.font_size);
            -- How far the members' rooms reach above the game's first row and below its last, and the biggest room.
            local above, below, icon = 0, 0, 0;
            for _, member in ipairs(roster.members) do
                local row = frame.rows[member.slot];
                if member.group == group and row and (config.include_self or member.id ~= roster.id) then
                    used = used + 1;
                    local item = items and items[used];
                    if not item then
                        item = { selection = {}, cells = {} };
                        if items then items[used] = item; end;
                    end;
                    local room = overlay.room(row.height, frame.pitch);
                    icon = math.max(icon, room);
                    local size = px or room;
                    local options = row_options(item, config.effects, look, measure_key, size, settings);
                    -- Worked out once a frame here; the paint draws this list.
                    item.effects = layout.kept_effects(item.selection, subjects[member.id], options, cache);
                    local cell, gap = options.icon_size, options.cell_gap;
                    -- The member's party cooldowns go nearest the game's window, after the distance while it's on,
                    -- a cell of the icons' size each, 3 px apart.
                    local subject = subjects[member.id];
                    item.cooldowns = show_cooldowns and subject and subject.cooldowns or nil;
                    local reserved = item.cooldowns and #item.cooldowns * (math.max(1, size) + 3) or 0;
                    needed = math.max(needed, math.max(#item.effects, 1) * (cell + gap) - gap + reserved);
                    -- A room taller than the row is centred on it in whole pixels; otherwise the row is the area.
                    item.shift, item.span, item.size = 0, row.height, size;
                    if stacked then
                        -- In a stack the member's name goes over their icons. It's measured again only when it changes.
                        local name = labels.member_name(member, config);
                        if item.name ~= name or item.name_key ~= measure_key then
                            item.name, item.name_key, item.name_width = name, measure_key, math.ceil(measured(look, name)) + 1;
                        end;
                        item.label_lines = item.label_lines or {};
                        item.label_lines[1] = name;
                        needed = math.max(needed, item.name_width);
                    elseif room > row.height then
                        item.shift, item.span = (room - row.height) / 2, room;
                        above = math.max(above, item.shift - (row.y - frame.y));
                        below = math.max(below, row.y - item.shift + room - frame.y - frame.height);
                    end;
                    item.member, item.row = member, row;
                    rows[used] = item;
                end;
            end;
            for index = #rows, used + 1, -1 do rows[index] = nil; end;
            if stacked then table.sort(rows, by_row); end;
            -- The distance gets a column of its own nearest the game's window on every row, as wide as its widest
            -- number, so the icons don't move when a number changes. Its text is the size Distance size picks, for
            -- the row, or for the icons in a stack.
            local column, distance_size = 0, 0;
            if config.distance and used > 0 then
                distance_size, column = distance_fit(look, rows[1].options, stacked and px or icon,
                    not stacked and frame.pitch or nil, config.distance_size);
            end;
            -- The strip grows with its buffs, and a stack with its names too, up to Longest row, and always has room
            -- for one whole icon, with the distance's column added.
            local least = px or icon;
            local strip_width = math.min(math.max(config.native.width, least), needed) + column;
            local side, gap = side_for(config,saved), config.native.gap;
            local base = side == 'left' and frame.x - gap or frame.x + frame.width + gap;
            local edge = math.max(0, math.min(width, base + (saved.native_x or 0)));
            -- The strip's window takes the rooms' reach too, kept on the screen. A stack's starts where beside_sizes
            -- ended it less its height, on a whole pixel.
            local origin, low, reach, line, cell_height = frame.y, above, frame.height + below, 0, 0;
            if stacked then
                line, cell_height = stack_line(sizes, look, config.effects, px);
                reach = used * line - MEMBER_GAP;
                origin, low = sizes.bottom[group] - reach, 0;
            end;
            local top = math.max(low, math.min(height - reach, origin + (saved.native_y or 0)));
            if stacked then top = math.floor(top); end;
            local offset_y = top - frame.y;
            -- Keep the strip outside the frame. Effects past its room are left out.
            local available = side == 'left' and math.max(0, edge) or math.max(0, width - edge);
            for other, bounds in pairs(geometry.groups) do
                if other ~= group and top - low < bounds.y + bounds.height and top + reach > bounds.y then
                    if side == 'left' and bounds.x < edge then
                        available = math.min(available, math.max(0, edge - bounds.x - bounds.width - gap));
                    elseif side == 'right' and bounds.x + bounds.width > edge then
                        available = math.min(available, math.max(0, bounds.x - gap - edge));
                    end;
                end;
            end;
            strip_width = math.floor(math.min(strip_width, available));
            -- Icons are never made smaller than their size, so a strip narrower than one shows none.
            if strip_width < least + column and #rows > 0 then overlay.no_room = true; end;
            if strip_width >= 12 and #rows > 0 then
                -- On whole pixels, so a game menu scale other than 1 never puts icons between pixels.
                local x = math.floor((side == 'left' and edge - strip_width or edge) + 0.5);
                -- Without room for the distance's column and one icon, a row shows nothing, as the line on Size and
                -- place says, rather than half a number.
                local fits = column > 0 and strip_width >= least + column;
                for index, item in ipairs(rows) do
                    local row, area = item.row, item.area or {};
                    if stacked then
                        -- Each member's line in a stack: the name, then the icons and any countdown under them.
                        item.label_y = top + (index - 1) * line;
                        area.x, area.y, area.width = x, item.label_y + look.font_size + 2 + NAME_GAP, strip_width;
                        area.height, area.align_right = cell_height, side == 'left';
                    else
                        area.x, area.y, area.width = x, math.floor(row.y + offset_y - item.shift + 0.5), strip_width;
                        area.height, area.align_right = math.min(item.span, height - area.y), side == 'left';
                    end;
                    item.area = area;
                    if fits then
                        local cell = item.distance_box or {};
                        cell.x = area.align_right and area.x + area.width - column or area.x;
                        cell.y, cell.width, cell.height, cell.size, cell.align_right = area.y, column, area.height, distance_size,
                            area.align_right;
                        item.distance_box, item.distance_cell = cell, cell;
                        area.width = area.width - column;
                        if not area.align_right then area.x = area.x + column; end;
                    else
                        item.distance_cell = nil;
                        if column > 0 then area.width = 0; end;
                    end;
                    if stacked then
                        -- The name sits over the icons against the side nearest the game's window, cut at the strip's
                        -- width.
                        item.label_width = math.max(1, math.min(item.name_width, area.width));
                        item.label_x = area.align_right and area.x + area.width - item.label_width or area.x;
                    elseif px then
                        -- Icons smaller than the row go in the middle of it, and the distance stays by the row.
                        area.y, area.height = math.floor(area.y + (area.height - px) / 2 + 0.5), px;
                    end;
                    -- Effects past the cooldowns' room are left out, and cooldowns past the strip's.
                    local watched = item.cooldowns;
                    local size = math.max(1, math.min(math.floor(area.height), item.size));
                    local fit = watched and math.min(#watched, math.floor((area.width + 3) / (size + 3))) or 0;
                    if fit > 0 then
                        local reserved = fit * (size + 3);
                        item.cooldown_area = cooldown_cells(item, area.align_right and area.x + area.width - reserved or area.x, area.y, reserved,
                            size, fit, area.align_right);
                        area.width = math.max(0, area.width - reserved);
                        if not area.align_right then area.x = area.x + reserved; end;
                    else item.cooldowns, item.cooldown_area = nil, nil; end;
                end;
                local plan = held and held.plan or {};
                if held then held.plan = plan; end;
                -- The window goes on whole pixels too, rounded outward: ImGui drops the fractions of a window's place
                -- and size, and would cut off the pixels of an icon rounded half a pixel down.
                local window_y = math.floor(top - low);
                plan.group, plan.rows, plan.x, plan.y, plan.look, plan.stacked = group, rows, x, window_y, look, stacked;
                plan.width, plan.height = strip_width, math.max(1, math.min(math.ceil(top + reach) - window_y, height - window_y));
                -- The whole offsets that still move the strip: past them it stays at the screen's edge, so a move saves
                -- no more than these and a drag back moves it from its first pixel.
                plan.offset_x_min, plan.offset_x_max = math.ceil(-base), math.floor(width - base);
                plan.offset_y_min = math.ceil(low - origin);
                plan.offset_y_max = math.floor(math.max(low, height - reach) - origin);
                count = count + 1;
                plans[count] = plan;
            end;
        end;
    end;
    for index = #plans, count + 1, -1 do plans[index] = nil; end;
    return plans;
end

-- The members and effects the strips were last planned with, so a panel of its own can be sized for them.
local last = {};

-- The game's party windows, read again only for another roster or screen size. The host makes a new roster at each
-- refresh, ten times a second and as soon as the party changes, so they are read then and not every frame. The host
-- reads them here too for the displays that move with the party list, so a refresh reads them once.
local listed = {};
local function party_list(roster, width, height)
    if listed.roster ~= roster or listed.width ~= width or listed.height ~= height then
        listed.roster, listed.width, listed.height = roster, width, height;
        listed.geometry = require('core.native_party_ui').geometry(roster, width, height);
    end;
    return listed.geometry;
end
overlay.party_list = party_list;

-- store is what the draw keeps from frame to frame; without one every table is new.
function overlay.plan(roster, subjects, config, geometry, width, height, cache, global_style, store, revision)
    last.roster, last.subjects = roster, subjects;
    return plan_into(store, roster, subjects, config, geometry, width, height, cache, global_style, revision);
end

-- How a group's panel of its own lays out at width on a screen_width by screen_height screen, with the members and
-- effects the strips were last planned with: the width it settles on and how tall its contents are. nil when the
-- strips haven't been planned or that group had no members then.
function overlay.panel_size(config, group, width, screen_width, screen_height, global_style)
    if type(last.roster) ~= 'table' or width <= 0 or screen_width <= 0 or screen_height <= 0 then return nil; end;
    local saved = {};
    for key, value in pairs(config.groups[group]) do saved[key] = value; end;
    saved.detached_x, saved.detached_y, saved.detached_width, saved.detached_height = 0, 0, width, screen_height;
    local members = layout.groups(last.roster, config)[group];
    local plan = detached_plan(members, last.subjects or {}, config, saved, group, screen_width, screen_height, {},
        theme.party(config, global_style), { rows = {}, items = {} });
    if not plan then return nil; end;
    return plan.width, plan.content_height;
end

-- One strip's paint, inside its window, refilled into strip and handed to paint_strip so no closure is made a frame.
-- It gives back list and on_top as soon as it has them, for the caller to pop the clip even when the paint fails,
-- and the hovered effect, member, subject, label, cooldown and distance, which carry over from one strip to the next.
local strip = {};
local function paint_strip(c)
    if not c.visible then return; end;
    local imgui, config, callbacks, roster, subjects, now, plan, look = c.imgui, c.config, c.callbacks, c.roster, c.subjects,
        c.now, c.plan, c.look;
    local mx, my, movable, blocked, screen, label = c.mx, c.my, c.movable, c.blocked, c.screen, c.label;
    local effect_cache, removable, light = c.effect_cache, c.removable, c.light;
    local hovered, hovered_member, hovered_subject, hovered_label, hovered_cooldown = c.hovered, c.hovered_member,
        c.hovered_subject, c.hovered_label, c.hovered_cooldown;
    local list, on_top;
    -- Samples go over an open settings window.
    list, on_top = resize.sample_list(imgui, config.preview and callbacks.samples_over, plan, mx, my);
    c.list, c.on_top = list, on_top;
    local scroll = plan.detached and imgui.GetScrollY and imgui.GetScrollY() or 0;
    if plan.detached then
        theme.frame(list, plan, look, look.colors.border);
    end;
    local hover = not callbacks.shift and not movable and not roster.typing and not callbacks.input_blocked and layout.inside(plan,mx,my)
        and (plan.detached or not blocked);
    for _, item in ipairs(plan.rows) do
        local subject = subjects[item.member.id];
        local unavailable = not subject or subject.known == false;
        local area, from = item.drawn_area or {}, item.area;
        area.x, area.y, area.width, area.height, area.align_right = from.x, from.y-scroll, from.width, from.height, from.align_right;
        item.drawn_area = area;
        if plan.detached or plan.stacked then
            -- The mouse on the distance points at it, not the name.
            local number_x;
            local top = item.label_y-scroll;
            if item.distance_right and top+look.font_size >= plan.y and top < plan.y+plan.height then
                number_x = paint_panel_distance(imgui, list, look, config, roster, item, c.warning, top);
                if number_x and hover and mx >= number_x and my >= top and my < top+look.font_size then c.hovered_distance = item.member; end;
            end;
            for line,value in ipairs(item.label_lines) do
                local y = item.label_y-scroll+(line-1)*(look.font_size+2);
                if y+look.font_size >= plan.y and y < plan.y+plan.height then
                    caption(imgui,list,look,value,item.label_x,y,item.label_width);
                    if hover and my >= y and my < y+look.font_size and not (line == 1 and number_x and mx >= number_x) then
                        hovered_label=item.member;
                        if unavailable then
                            hovered={unknown_subject=true,reason=unavailable_reason};
                            hovered_member,hovered_subject=item.member,subject;
                        end;
                    end;
                end;
            end;
        end;
        if area.height >= 10 and area.y+area.height > plan.y and area.y < plan.y+plan.height then
            local effect = party_hud.paint_effects(list, look, subject, item.options, area,
                hover and mx or nil, my, effect_cache, now, item.effects, item.cells, removable, light);
            if effect then hovered, hovered_member, hovered_subject = effect, item.member, subject;
            elseif unavailable and hover and layout.inside(area,mx,my) then
                hovered={unknown_subject=true,reason=unavailable_reason};
                hovered_member,hovered_subject=item.member,subject;
            end;
        end;
        local cells = item.cooldowns and item.cooldown_area;
        if cells and cells.cell >= 10 and cells.y-scroll+cells.cell > plan.y and cells.y-scroll < plan.y+plan.height then
            local hit = party_hud.paint_cooldowns(list, look, item.options, item.cooldowns, cells, now, hover and mx or nil, my,
                callbacks.global_style, scroll);
            if hit then hovered_cooldown, hovered_member = hit, item.member; end;
        end;
        if item.distance_cell and not plan.detached then
            local hit = paint_distance(list, look, config, roster, item, c.plain, c.ink, hover and mx or nil, my);
            if hit then c.hovered_distance = hit; end;
        end;
    end;
    if config.preview or movable then
        corner[1], corner[2], far_corner[1], far_corner[2] = plan.x, plan.y, plan.x + plan.width, plan.y + plan.height;
        list:AddRect(corner, far_corner, 0xFFFFFFFF);
    end;
    if not movable and callbacks.shift and not roster.typing and config.locked and not callbacks.input_blocked then
        resize.locked(list, plan, look, label);
    end;
    if movable then
        corner[1], corner[2], extent[1], extent[2] = plan.x, plan.y, plan.width, plan.height;
        imgui.SetCursorScreenPos(corner);
        imgui.InvisibleButton('##native_move_' .. plan.group, extent);
        local saved = config.groups[plan.group];
        -- A strip beside the game's rows only moves, from its edges too. A panel of its own also resizes from
        -- its edges; the strip becomes one only from its switch in the settings.
        if imgui.IsItemActivated() and not gesture then
            -- A move starts from the offsets the strip is drawn at, which a save past the screen's edge isn't.
            local from_x, from_y = drawn_offsets(plan, saved.native_x or 0, saved.native_y or 0);
            gesture = { config = config, group = plan.group, callbacks = callbacks, mx = mx, my = my,
                x = from_x, y = from_y, plan = held_plan(plan), side = config.native.side,
                resize = plan.detached and resize.grip(plan, mx, my) or nil,
                screen_width = screen.x, screen_height = screen.y };
        end;
        if gesture and gesture.group == plan.group and imgui.IsItemActive() then
            resize.cursor(imgui, gesture.resize);
            local dx, dy = mx - gesture.mx, my - gesture.my;
            local horizontal,vertical = resize.axes(gesture.resize);
            -- A move snaps as edit mode's does, and a resize the edge being pulled, when the caller gives the settings
            -- and the strip is ticked to snap while Snap while moving is on.
            local settings, id = callbacks.settings, 'strip_' .. plan.group;
            if gesture.dirty or horizontal and dx ~= 0 or vertical and dy ~= 0 or not gesture.resize and (dx ~= 0 or dy ~= 0) then
                gesture.active_edge = resize.active_edge(gesture.resize,dx,dy,gesture.active_edge);
                local updates = {};
                local shift_x, shift_y = 0, 0;
                if settings and not gesture.resize then
                    shift_x, shift_y = snap.move(settings,id,gesture.plan.x+dx,gesture.plan.y+dy,gesture.plan.width,gesture.plan.height,screen.x,screen.y);
                end;
                if gesture.plan.detached then
                    local limits = {min_width=gesture.plan.min_width or 40,min_height=40,max_width=900,max_height=16000,
                        screen_width=screen.x,screen_height=screen.y};
                    local rect = settings and gesture.resize and snap.resize(settings,id,gesture.plan,gesture.active_edge,dx,dy,limits)
                        or resize.rect(gesture.plan,gesture.active_edge,dx,dy,limits);
                    if not gesture.resize then
                        rect.x,rect.y = clamp(gesture.plan.x+dx+shift_x,0,screen.x-rect.width),clamp(gesture.plan.y+dy+shift_y,0,screen.y-rect.height);
                    end;
                    updates.native_detached = true;
                    updates.detached_x,updates.detached_y = math.floor(rect.x),math.floor(rect.y);
                    -- A move keeps the saved size, which a small screen can draw smaller; only a resize saves one.
                    if gesture.resize then
                        updates.detached_width,updates.detached_height = math.floor(rect.width),math.floor(rect.height);
                    end;
                else
                    updates.native_x,updates.native_y = drawn_offsets(gesture.plan,gesture.x+dx+shift_x,gesture.y+dy+shift_y);
                end;
                local changed = false;
                for key,value in pairs(updates) do if saved[key] ~= value then changed=true; end; end;
                if changed then
                    if not gesture.started and gesture.callbacks.begin_edit then gesture.callbacks.begin_edit(); end;
                    gesture.started,gesture.dirty = true,true;
                    for key,value in pairs(updates) do saved[key]=value; end;
                end;
            end;
            -- The strip is drawn this frame where the last step put it, so its line shows once it is drawn on it.
            if settings then snap.show(settings, id, screen.x, screen.y, plan); end;
        end;
        local grip;
        if gesture and gesture.group == plan.group then grip = gesture.resize;
        elseif not gesture and plan.detached and imgui.IsItemHovered() then grip = resize.grip(plan,mx,my); end;
        resize.hint(list,plan,theme.u32(look.colors.title,look.opacity),grip,label,look,not plan.detached);
        if not gesture and imgui.IsItemHovered() then resize.cursor(imgui, plan.detached and resize.grip(plan, mx, my) or nil); end;
    end;
    -- A panel of its own draws on its draw list, which ImGui doesn't count, so this empty item gives the window its
    -- scroll range. It stops 18 px short of the window's width, to stay clear of the scrollbar.
    if plan.detached then
        extent[1], extent[2] = math.max(1, plan.width - 18), plan.content_height;
        imgui.SetCursorPos(ZERO); imgui.Dummy(extent);
    end;
    c.hovered, c.hovered_member, c.hovered_subject, c.hovered_label, c.hovered_cooldown = hovered, hovered_member,
        hovered_subject, hovered_label, hovered_cooldown;
end

function overlay.draw(roster, subjects, config, now, callbacks)
    callbacks = callbacks or {};
    local imgui, bit = require('imgui'), require('bit');
    -- Strips that aren't planned say nothing of the room beside the game's list, here or with no screen below.
    if not config.enabled or not roster or not roster.valid or roster.hidden or roster.map or roster.in_event
        or not config.show_solo and #roster.members <= 1 then overlay.no_room = false; overlay.cancel_layout_gesture(); return false, NONE; end;
    local movable = callbacks.shift and not roster.typing and not config.locked and not callbacks.input_blocked;
    local watch = callbacks.cooldowns;
    show_cooldowns = type(watch) == 'table' and watch.enabled == true and watch.strips == true;
    -- Debuffs you can remove light in Party list's own glow and color, and Erase doesn't reach the alliance strips.
    local near, far, light;
    if config.effects.cleanse_light then
        near, far = dispel.cleansable(now, config.preview);
        light = config.effects;
    end;
    if config.preview then
        if not sample_subjects then sample_subjects = select(2, party_hud.sample(18, now)); end;
        party_hud.sample_time(sample_subjects, now);
        -- The party cooldown samples are made for the first sample members, by name, one each.
        local estimates = show_cooldowns and require('core.party_cooldowns').samples(now);
        for id in pairs(shown_samples) do shown_samples[id] = nil; end;
        for _, member in ipairs(roster.members) do
            local subject, estimate = sample_subjects[1001 + member.slot], estimates and estimates[member.slot + 1];
            local own = estimate and sample_cooldowns[member.slot + 1];
            if own then own[1] = estimate; end;
            if subject then subject.cooldowns = own or nil; end;
            shown_samples[member.id] = subject;
        end;
        subjects = shown_samples;
    end;
    local filters = effect_filters.compile(callbacks.effect_filters);
    if filters.active then
        local recipients = callbacks.effect_recipients or effect_filters.recipients(nil, roster);
        subjects = effect_filters.subjects(filters, subjects, recipients);
    end;
    local screen = imgui.GetIO().DisplaySize;
    if screen.x <= 0 or screen.y <= 0 then overlay.no_room = false; overlay.cancel_layout_gesture(); return false, NONE; end;
    if gesture and (gesture.screen_width ~= screen.x or gesture.screen_height ~= screen.y or gesture.side ~= config.native.side) then overlay.cancel_layout_gesture(); end;
    local geometry = callbacks.native_geometry or party_list(roster, math.floor(screen.x), math.floor(screen.y));
    cache_turn = 3 - cache_turn;
    local effect_cache = effect_caches[cache_turn];
    for key in pairs(effect_cache) do effect_cache[key] = nil; end;
    local plans = overlay.plan(roster, subjects, config, geometry, screen.x, screen.y, effect_cache, callbacks.global_style, kept, callbacks.revision);
    if gesture and (gesture.config ~= config or not movable or not imgui.IsMouseDown(0)) then
        if gesture.config == config and movable and not imgui.IsMouseDown(0) and gesture.dirty and not gesture.resize then
            for _, plan in ipairs(plans) do
                if plan.group == gesture.group and plan.detached and overlay.snap(config, plan.group, plan, geometry) then
                    plans = overlay.plan(roster, subjects, config, geometry, screen.x, screen.y, effect_cache, callbacks.global_style, kept, callbacks.revision);
                    break;
                end;
            end;
        end;
        overlay.cancel_layout_gesture();
    end;
    if #plans == 0 then overlay.cancel_layout_gesture(); return false, NONE, geometry.available and geometry.groups or NONE; end;
    if gesture then
        local found;
        for _, plan in ipairs(plans) do if plan.group == gesture.group then found = true; break; end end;
        if not found then overlay.cancel_layout_gesture(); end;
    end;
    local mx, my = imgui.GetMousePos();
    local flags = require('ui.frame_policy').overlay_flags();
    local blocked = callbacks.input_blocked or imgui.IsWindowHovered and imgui.IsWindowHovered(ImGuiHoveredFlags_AnyWindow or 0);
    strip.imgui, strip.config, strip.callbacks, strip.roster, strip.subjects, strip.now = imgui, config, callbacks, roster, subjects, now;
    strip.mx, strip.my, strip.movable, strip.blocked, strip.screen = mx, my, movable, blocked, screen;
    strip.effect_cache, strip.light = effect_cache, light;
    strip.hovered, strip.hovered_member, strip.hovered_subject, strip.hovered_label, strip.hovered_cooldown = nil, nil, nil, nil, nil;
    strip.hovered_distance = nil;
    for _, plan in ipairs(plans) do
        local look = plan.look;
        local removable = near and (plan.group == 1 and near or far);
        -- A panel of its own that scrolls keeps the mouse for its wheel and scrollbar, except in edit mode. There edit
        -- mode's outline behind it takes the click that picks it, the Shift drag and the keys. Nothing could use the
        -- scrollbar then, so it shows none.
        local scrolling = plan.detached and plan.content_height > plan.height and not roster.typing and not callbacks.input_blocked
            and not callbacks.editing;
        local panel_flags = (not plan.detached or movable or callbacks.editing) and bit.bor(flags, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoScrollWithMouse or 0) or flags;
        if not movable and not scrolling then panel_flags = bit.bor(panel_flags, ImGuiWindowFlags_NoInputs); end;
        imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, ZERO);
        imgui.PushStyleVar(ImGuiStyleVar_WindowMinSize, ONE);
        imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
        corner[1], corner[2], extent[1], extent[2] = plan.x, plan.y, plan.width, plan.height;
        imgui.SetNextWindowPos(corner, ImGuiCond_Always);
        imgui.SetNextWindowSize(extent, ImGuiCond_Always);
        local label = strip_labels[plan.group];
        resize.occupy(label, plan, 'party');
        -- Edit mode finds each strip where it was drawn.
        elements.record('strip_' .. plan.group, plan);
        local visible = imgui.Begin('##vantage_native_' .. plan.group, true, panel_flags);
        if visible then elements.opened('strip_' .. plan.group, imgui.GetWindowDrawList()); end
        fonts.push(look.font, look.font_size);
        -- The clip a sample over the settings window pushes comes off after the paint, even one that failed.
        strip.visible, strip.plan, strip.look, strip.label, strip.removable = visible, plan, look, label, removable;
        -- The distance's colors for this strip: the countdowns' color and the warning color at the strips' Opacity
        -- beside the game's list. A panel of its own takes the warning color, and its name paint adds Opacity.
        local warning = config.distance and warning_color(callbacks.global_style) or nil;
        strip.warning, strip.plain, strip.ink = warning, 0, 0;
        if warning and not plan.detached then
            strip.plain, strip.ink = theme.u32(look.gauge_text_color, look.opacity), theme.u32(warning, look.opacity);
        end;
        strip.list, strip.on_top = nil, nil;
        local ok, err = pcall(paint_strip, strip);
        local list, on_top = strip.list, strip.on_top;
        if on_top then list:PopClipRect(); end;
        fonts.pop(); imgui.End(); imgui.PopStyleVar(3);
        if not ok then overlay.cancel_layout_gesture(); error(err, 0); end;
    end;
    local hovered, hovered_member, hovered_subject, hovered_label, hovered_cooldown = strip.hovered, strip.hovered_member,
        strip.hovered_subject, strip.hovered_label, strip.hovered_cooldown;
    local hovered_distance = strip.hovered_distance;
    -- Nothing of this frame is kept past it.
    strip.subjects, strip.roster, strip.plan, strip.hovered, strip.hovered_member, strip.hovered_subject = nil, nil, nil, nil, nil, nil;
    strip.hovered_label, strip.hovered_cooldown, strip.list, strip.hovered_distance, strip.warning = nil, nil, nil, nil, nil;
    if hovered_cooldown and not imgui.IsMouseDown(0) then
        imgui.BeginTooltip(); imgui.PushTextWrapPos(360);
        imgui.TextUnformatted(require('core.party_cooldowns').details(hovered_cooldown, now));
        imgui.PopTextWrapPos(); imgui.EndTooltip();
    elseif hovered and not imgui.IsMouseDown(0) then party_hud.effect_tooltip(imgui, hovered, hovered_member, hovered_subject);
    elseif hovered_label and not imgui.IsMouseDown(0) then
        imgui.BeginTooltip(); imgui.TextUnformatted(hovered_label.name or 'Member'); imgui.EndTooltip();
    elseif hovered_distance and not imgui.IsMouseDown(0) then
        imgui.BeginTooltip(); imgui.PushTextWrapPos(360);
        imgui.TextUnformatted(party_distance.details(hovered_distance, config));
        imgui.PopTextWrapPos(); imgui.EndTooltip();
    end;
    return false, NONE, geometry.available and geometry.groups or NONE;
end

if VANTAGE_TEST_MODE then
    overlay._kept = kept;
end

return overlay;
