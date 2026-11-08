local layout = {};
-- The buffs and debuffs of each party list strip row: which effects show, in what order, and their cells.
local countdown = require('ui.countdown_text');
local metrics, render_cache = require('ui.text_metrics'), require('ui.render_cache');
local effect_ordering = require('core.effect_order');

local finite = require('ui.numbers').finite;

-- Between low and high. A value that isn't a finite number takes fallback, which is kept between them too.
local function number(value, low, high, fallback)
    return math.max(low, math.min(high, finite(value) and value or fallback));
end

function layout.inside(rect, x, y)
    return x >= rect.x and y >= rect.y and x < rect.x + rect.width and y < rect.y + rect.height;
end

function layout.effect_time(effect)
    if tonumber(effect.effect)==269 and effect.domain~='recast' then return ''; end
    -- A duration override that counts up (core/durations.lua) shows the time since the effect landed.
    if effect.count_up == true and type(effect.elapsed) == 'number' and effect.elapsed >= 0 then return countdown.time(effect.elapsed); end
    local left = effect.remaining;
    if type(left) ~= 'number' or left ~= left or left < 0 or left == math.huge then return ''; end
    return countdown.time(left);
end

local function selected(map, id)
    if type(map) ~= 'table' then return false; end
    if map[id] == true or map[tostring(id)] == true then return true; end
    for _, value in ipairs(map) do if value == id then return true; end end
    return false;
end

local selection_plans, selection_orders = render_cache.new(256), render_cache.new(64);
local selection_revision = render_cache.revisions(64,
    {'fit_all','kind','include','exclude','pinned','sort','max','show_copy_image','show_third_eye'});
-- The key of the Always show tick of the effects that have one, by id.
local always = {};
for _, tick in ipairs(require('ui.overhead_defaults').always) do
    for _, id in ipairs(tick.ids) do always[id] = tick.key; end
end

local function effect_order(options, revision)
    local saved = selection_orders:get(revision);
    if saved then return saved; end;
    local pinned, sort = require('core.store').copy(options.pinned or {}), options.sort or 'longest';
    local function less(a, b)
        local ap, bp = selected(pinned, a.effect), selected(pinned, b.effect);
        if ap ~= bp then return ap; end;
        if sort == 'longest' then
            local longer = effect_ordering.longest(a, b);
            if longer ~= nil then return longer; end;
        elseif sort == 'oldest' then
            local older = effect_ordering.oldest(a, b);
            if older ~= nil then return older; end;
        elseif sort == 'remaining' then
            local av = type(a.remaining) == 'number' and a.remaining >= 0 and a.remaining or math.huge;
            local bv = type(b.remaining) == 'number' and b.remaining >= 0 and b.remaining or math.huge;
            if av ~= bv then return av < bv; end;
        elseif (a.name or '') ~= (b.name or '') then return (a.name or '') < (b.name or ''); end;
        if a.effect ~= b.effect then return (tonumber(a.effect) or 0) < (tonumber(b.effect) or 0); end;
        return tostring(a.key or '') < tostring(b.key or '');
    end;
    return selection_orders:put(revision, less);
end;

-- The third result is the order of every effect the selection kept, before the limit, as places in the subject's
-- effects.
function layout.effects(subject, options, cache)
    options = options or {};
    local saved;
    if cache and subject then
        local key = options.selection_options or options;
        cache[key] = cache[key] or {};
        saved = cache[key];
        if saved[subject] then return saved[subject][1], saved[subject][2], saved[subject][3]; end
    end
    local revision = selection_revision(options, options.selection_options);
    local signature = {tostring(revision) .. ':'};
    local less = effect_order(options, revision);
    local source = subject and subject.effects or {};
    for index, effect in ipairs(source) do
        signature[index + 1] = render_cache.key(effect.effect, effect.kind, effect.present, effect.name, effect.key,
            effect.first_seen, effect.first_sequence);
    end;
    local selection_key = table.concat(signature);
    local previous = selection_plans:get(selection_key);
    local sort = options.sort or 'longest';
    if previous and (sort == 'remaining' or sort == 'longest') then
        for index = 2, #previous.order do
            if less(source[previous.order[index]], source[previous.order[index - 1]]) then previous = nil; break; end;
        end;
    end;
    if previous then
        local current = {};
        for index, position in ipairs(previous.indices) do current[index] = source[position]; end;
        if saved then saved[subject] = {current, previous.hidden, previous.order}; end;
        return current, previous.hidden, previous.order;
    end;
    local filtered, has_include = {}, false;
    for _, value in pairs(options.include or {}) do if value == true or type(value) == 'number' then has_include = true; break; end end
    for _, effect in ipairs(subject and subject.effects or {}) do
        if #filtered >= 96 then break; end
        local id, kind = effect.effect, effect.kind or 'neutral';
        local shown, tick = options.kind == nil or options.kind == 'all' or options.kind == kind, options.kind ~= 'none' and always[id];
        -- Ticked beats Show. Unticked hides it, unless it's on Show only, which shows it either way.
        if tick and options[tick] ~= false then shown = true; elseif tick and not has_include then shown = false; end
        if effect.present ~= false and shown
            and not selected(options.exclude, id) and (not has_include or selected(options.include, id)) then
            filtered[#filtered + 1] = effect;
        end
    end
    table.sort(filtered, less);
    local positions, complete_order = {}, {};
    for index, effect in ipairs(source) do positions[effect] = index; end;
    for index, effect in ipairs(filtered) do complete_order[index] = positions[effect]; end;
    local limit = options.fit_all and 96 or math.floor(number(options.max, 0, 96, 12));
    local hidden = math.max(0, #filtered - limit);
    for index = #filtered, limit + 1, -1 do filtered[index] = nil; end
    local indices = {};
    for index, effect in ipairs(filtered) do indices[index] = positions[effect]; end;
    selection_plans:put(selection_key, {indices=indices,hidden=hidden,order=complete_order});
    if saved then saved[subject] = { filtered, hidden, complete_order }; end
    return filtered, hidden, complete_order;
end

-- The fields of an effect the selection reads, in the order kept_effects keeps them.
local SELECTED_FIELDS = 8;

-- The draw's cache and the settings table the selection revision was last worked out for, and that revision.
local checked_cache, checked_identity, checked_revision;

-- The selection revision of options, worked out once a draw: every row a draw plans selects by the same settings, so
-- one check of them does for all of its rows. Each draw brings a new cache, so the next one checks them again.
local function selection_of(options, cache)
    local identity = options.selection_options or options;
    if cache and cache == checked_cache and identity == checked_identity then return checked_revision; end;
    local revision = selection_revision(options, options.selection_options);
    if cache then checked_cache, checked_identity, checked_revision = cache, identity, revision; end;
    return revision;
end

-- layout.effects for a strip row, kept in holder from frame to frame. The list is worked out again only when the
-- subject's effects, a field the selection reads, the selection settings or, sorted by time left, their order
-- change; otherwise the same list comes back and nothing is made.
function layout.kept_effects(holder, subject, options, cache)
    local source = subject and subject.effects;
    if type(source) ~= 'table' then
        -- Nothing to choose from: the same empty list each frame.
        local empty = holder.empty or {};
        holder.source, holder.empty = nil, empty;
        return empty, 0;
    end;
    local revision = selection_of(options, cache);
    local count, fields = #source, holder.fields;
    if holder.source == source and holder.revision == revision and holder.count == count then
        local same, at = true, 0;
        for index = 1, count do
            local effect = source[index];
            if fields[at + 1] ~= effect or fields[at + 2] ~= effect.effect or fields[at + 3] ~= effect.kind
                or fields[at + 4] ~= effect.present or fields[at + 5] ~= effect.name
                or fields[at + 6] ~= effect.key or fields[at + 7] ~= effect.first_seen or fields[at + 8] ~= effect.first_sequence then
                same = false;
                break;
            end;
            at = at + SELECTED_FIELDS;
        end;
        local sort = options.sort or 'longest';
        if same and (sort == 'remaining' or sort == 'longest') then
            local less, order = effect_order(options, revision), holder.order;
            for index = 2, #order do
                if less(source[order[index]], source[order[index - 1]]) then same = false; break; end;
            end;
        end;
        if same then return holder.list, holder.hidden; end;
    end;
    local list, hidden, order = layout.effects(subject, options, cache);
    if not fields then fields = {}; holder.fields = fields; end;
    local at = 0;
    for index = 1, count do
        local effect = source[index];
        fields[at + 1], fields[at + 2], fields[at + 3] = effect, effect.effect, effect.kind;
        fields[at + 4], fields[at + 5], fields[at + 6] = effect.present, effect.name, effect.key;
        fields[at + 7], fields[at + 8] = effect.first_seen, effect.first_sequence;
        at = at + SELECTED_FIELDS;
    end;
    for index = #fields, at + 1, -1 do fields[index] = nil; end;
    holder.source, holder.revision, holder.count, holder.list, holder.hidden, holder.order = source, revision, count, list, hidden, order;
    return list, hidden;
end

local function icon_countdown(text, icon_size, options, pixel_scale, width, height)
    if text == '' then return nil; end;
    local measure = function(value)
        return countdown.icon_metrics(options.countdown_font, value, icon_size, options, pixel_scale);
    end;
    local bounds = measure(text);
    local below = options.icon_countdown_position ~= 'inside';
    local fallback = below and options.fixed_countdown_slot
        and icon_size + bounds.gap + bounds.height > height;
    below = below and not fallback;
    if not below and (bounds.width > icon_size or bounds.height > icon_size) then
        local fitted = setmetatable({}, { __index = options });
        local physical_size = math.max(1, math.floor(bounds.size * pixel_scale));
        repeat
            physical_size = math.max(1, physical_size - 1);
            fitted.icon_countdown_size = physical_size / pixel_scale;
            bounds = countdown.icon_metrics(options.countdown_font, text, icon_size, fitted, pixel_scale);
        until physical_size <= 1 or bounds.width <= icon_size and bounds.height <= icon_size;
    end;
    local lines, used_height, used_width = {}, 0, 0;
    local values = below and metrics.lines(text, width, function(value) return measure(value).width; end) or { text };
    for _, value in ipairs(values) do
        local line = below and measure(value) or bounds;
        lines[#lines + 1] = { text = value, width = line.width, height = line.height, y = used_height };
        used_height, used_width = used_height + line.height, math.max(used_width, line.width);
    end;
    -- Native strips retain the game's fixed row spacing even for wrapped countdowns.
    if below and options.fixed_countdown_slot and icon_size + bounds.gap + used_height > height then
        local inside = setmetatable({ icon_countdown_position = 'inside' }, { __index = options });
        local result = icon_countdown(text, icon_size, inside, pixel_scale, width, height);
        result.fallback = true;
        return result;
    end;
    return { size = bounds.size, width = used_width, height = used_height, gap = bounds.gap,
        below = below, fallback = fallback, lines = lines };
end;

-- Each effect is an icon cell, with its countdown while countdowns show. options.cell_gap is the space between cells,
-- 3 px unless a strip sets its own. Icons keep their size: as many as fit show, and an area narrower than one icon
-- shows none.
local function build_effect_cells(effects, options, rect)
    local gap = options.cell_gap or 3;
    local pixel_scale = number(options.pixel_scale, 1/512, 512, 1);
    local cell_height = number(options.icon_size, 10/pixel_scale, 128/pixel_scale, 20/pixel_scale);
    if not (rect.width >= cell_height) then return {}, #effects, 0; end;
    local cell_width = cell_height;
    local timers;
    local icon_height, icon_column = cell_height, cell_height;
    if options.timers then
        timers = {};
        for _, effect in ipairs(effects) do
            local timer = layout.effect_time(effect);
            if timer ~= '' then
                local bounds = countdown.icon_metrics(options.countdown_font, timer, icon_height, options, pixel_scale);
                if options.icon_countdown_position ~= 'inside' and not options.fixed_countdown_slot then
                    icon_column = math.min(rect.width, math.max(icon_column, bounds.width));
                end;
            end;
        end;
        cell_width = math.max(cell_width, icon_column);
        for _, effect in ipairs(effects) do
            local plan = icon_countdown(layout.effect_time(effect), icon_height, options, pixel_scale, icon_column, rect.height);
            timers[effect] = plan;
            if plan and plan.below then cell_height = math.max(cell_height, icon_height + plan.gap + plan.height); end;
        end;
    end;
    local columns = math.max(1, math.floor((rect.width + gap) / (cell_width + gap)));
    local rows = options.fixed_countdown_slot and 1 or not options.fit_all and options.wrap == false and 1 or (options.fit_all or options.auto_rows) and math.max(1, math.min(96, math.floor((rect.height + gap) / (cell_height + gap))))
        or math.floor(number(options.rows, 1, 8, 2));
    local cells, strip, used, previous_kind, max_y = {}, 0, 0, nil, rect.y;
    local sorted = effects;
    if options.separate then
        sorted = {};
        for _, kind in ipairs({ 'buff', 'debuff', 'neutral' }) do
            for _, effect in ipairs(effects) do if (effect.kind or 'neutral') == kind then sorted[#sorted + 1] = effect; end end
        end
    end
    for _, effect in ipairs(sorted) do
        local kind = effect.kind or 'neutral';
        if options.separate and previous_kind and kind ~= previous_kind then
            strip, used = strip + math.ceil(used / columns), 0;
        end
        local row = strip + math.floor(used / columns);
        if row >= rows then break; end
        local y = rect.y + row * (cell_height + gap);
        if y + cell_height > rect.y + rect.height then break; end
        cells[#cells + 1] = { effect = effect, x = rect.x + (used % columns) * (cell_width + gap), y = y,
            width = cell_width, height = cell_height, countdown = timers and timers[effect] or nil, icon_size = icon_height,
            icon_column_width = icon_column };
        used, previous_kind, max_y = used + 1, kind, y + cell_height;
    end
    if options.growth == 'left' then
        for _, cell in ipairs(cells) do cell.x = rect.x + rect.width - (cell.x - rect.x) - cell.width; end;
    end
    -- A strip beside the game's rows keeps each row against the side nearest them.
    if rect.align_right ~= nil then
        local edges = {};
        for _, cell in ipairs(cells) do
            local edge = rect.align_right and cell.x + cell.width or cell.x;
            edges[cell.y] = edges[cell.y] and (rect.align_right and math.max(edges[cell.y], edge) or math.min(edges[cell.y], edge)) or edge;
        end
        local edge = rect.x + (rect.align_right and rect.width or 0);
        for _, cell in ipairs(cells) do cell.x = cell.x + edge - edges[cell.y]; end
    end
    return cells, #effects - #cells, max_y - rect.y;
end

local cell_plans = render_cache.new(128);
-- Where a draw's cache keeps the sizes asked for during that draw.
local drawn_sizes = {};

-- The cells of these effects in an area of this size at 0, 0, kept by everything they are worked out from.
local function cell_plan(effects, options, rect)
    local left, top, right, bottom = countdown.padding(options);
    local parts = {render_cache.key(options.measure_key, options.icon_size, options.pixel_scale,
        options.countdown_font, options.icon_countdown_position, options.icon_countdown_size, options.icon_countdown_gap,
        options.timers, options.wrap,
        options.fit_all, options.auto_rows, options.rows, options.separate, options.growth, options.fixed_countdown_slot, rect.align_right,
        rect.width, rect.height, left, top, right, bottom, options.cell_gap)};
    for index, effect in ipairs(effects) do
        parts[index + 1] = render_cache.key(effect.kind, options.timers and layout.effect_time(effect) or '');
    end;
    local key = table.concat(parts);
    local saved = cell_plans:get(key);
    if not saved then
        local cells, omitted, height = build_effect_cells(effects, options,
            {x=0,y=0,width=rect.width,height=rect.height,align_right=rect.align_right});
        local indices = {};
        for index, effect in ipairs(effects) do indices[effect] = index; end;
        for _, cell in ipairs(cells) do cell.effect_index, cell.effect = indices[cell.effect], nil; end;
        saved = cell_plans:put(key, {cells=cells,omitted=omitted,height=height});
    end;
    return saved;
end;

-- Geometry is reusable; effect state always comes from this frame's rows.
local function placed_cells(saved, effects, rect)
    local result = {};
    for index, source in ipairs(saved.cells) do
        local cell = {};
        for field, value in pairs(source) do if field ~= 'effect_index' then cell[field] = value; end; end;
        cell.x, cell.y, cell.effect = source.x + rect.x, source.y + rect.y, effects[source.effect_index];
        result[index] = cell;
    end;
    return result;
end;

-- With sizing set only omitted and the height are wanted, so no cells are copied (the first result is nil); the kept
-- first cell, whose size every cell of the strip shares, comes back too, not to be changed. With a draw's cache, the
-- same effects, options and area size are answered once per draw.
function layout.effect_cells(effects, options, rect, sizing, cache)
    if not options.measure_key then return build_effect_cells(effects, options, rect); end;
    local sizes;
    if sizing and cache then
        local by_effects = cache[drawn_sizes];
        if not by_effects then by_effects = {}; cache[drawn_sizes] = by_effects; end;
        local by_options = by_effects[effects];
        if not by_options then by_options = {}; by_effects[effects] = by_options; end;
        sizes = by_options[options];
        if not sizes then sizes = {}; by_options[options] = sizes; end;
        for _, size in ipairs(sizes) do
            if size.width == rect.width and size.height == rect.height and size.align_right == rect.align_right then
                return nil, size.omitted, size.used, size.cell;
            end;
        end;
    end;
    local saved = cell_plan(effects, options, rect);
    if sizes then
        sizes[#sizes + 1] = {width=rect.width,height=rect.height,align_right=rect.align_right,omitted=saved.omitted,used=saved.height,
            cell=saved.cells[1]};
    end;
    if sizing then return nil, saved.omitted, saved.height, saved.cells[1]; end;
    return placed_cells(saved, effects, rect), saved.omitted, saved.height;
end;

-- layout.effect_cells for a strip row, kept in holder from frame to frame. The same effects list and options table,
-- an area of the same size and each effect's kind and countdown text give the cells of the frame before, moved to the
-- area; only a change works them out again.
function layout.kept_cells(holder, effects, options, rect)
    if not options.measure_key then return layout.effect_cells(effects, options, rect); end;
    local count, texts = #effects, holder.texts;
    local same = texts ~= nil and holder.effects == effects and holder.options == options and holder.count == count
        and holder.width == rect.width and holder.height == rect.height and holder.align_right == rect.align_right;
    if same then
        local at = 0;
        for index = 1, count do
            local effect = effects[index];
            if texts[at + 1] ~= effect.kind or texts[at + 2] ~= (options.timers and layout.effect_time(effect) or '') then
                same = false;
                break;
            end;
            at = at + 2;
        end;
    end;
    if not same then
        local saved = cell_plan(effects, options, rect);
        if not texts then texts = {}; holder.texts = texts; end;
        local at = 0;
        for index = 1, count do
            local effect = effects[index];
            texts[at + 1], texts[at + 2] = effect.kind, options.timers and layout.effect_time(effect) or '';
            at = at + 2;
        end;
        for index = #texts, at + 1, -1 do texts[index] = nil; end;
        holder.cells = placed_cells(saved, effects, rect);
        holder.saved, holder.effects, holder.options, holder.count = saved, effects, options, count;
        holder.width, holder.height, holder.align_right, holder.x, holder.y = rect.width, rect.height, rect.align_right, rect.x, rect.y;
        return holder.cells, saved.omitted, saved.height;
    end;
    local cells, saved = holder.cells, holder.saved;
    if holder.x ~= rect.x or holder.y ~= rect.y then
        for index, source in ipairs(saved.cells) do
            local cell = cells[index];
            cell.x, cell.y = source.x + rect.x, source.y + rect.y;
        end;
        holder.x, holder.y = rect.x, rect.y;
    end;
    return cells, saved.omitted, saved.height;
end;

-- How tall a strip row's effects are, from the list kept_effects worked out, its sizing kept in holder.
function layout.kept_effect_height(holder, subject, effects, options, width)
    if width <= 0 then return 0; end
    if not subject or not subject.effects or #subject.effects == 0 then return 0; end
    local rect = holder.rect;
    if not rect then rect = { x = 0, y = 0 }; holder.rect = rect; end;
    rect.width, rect.height = width, (options.fit_all or options.auto_rows) and 1048576 or 2048;
    local _, _, used_height = layout.kept_cells(holder, effects, options, rect);
    return used_height;
end

-- Each slot's rank in the group layout.groups is sorting, refilled for each group.
local slot_ranks = {};
local function by_rank(a, b)
    local aa, bb = tonumber(a.slot) or 0, tonumber(b.slot) or 0;
    local ar, br = slot_ranks[aa % 6] or (aa % 6 + 10), slot_ranks[bb % 6] or (bb % 6 + 10);
    if ar == br then return aa < bb; end
    return ar < br;
end

-- into, when given, holds the three lists of the call before, emptied and refilled here.
function layout.groups(roster, config, into)
    local groups = into or { {}, {}, {} };
    if into then
        for _, members in ipairs(into) do for index = #members, 1, -1 do members[index] = nil; end end
    end
    for _, member in ipairs(roster.members or {}) do
        local group = tonumber(member.group);
        if group and group >= 1 and group <= 3 and group == math.floor(group) and member.active ~= false
            and (config.include_self ~= false or member.id ~= roster.id) then
            groups[group][#groups[group] + 1] = member;
        end
    end
    for index, members in ipairs(groups) do
        for slot in pairs(slot_ranks) do slot_ranks[slot] = nil; end
        local saved = config.groups and config.groups[index];
        if saved and saved.order then
            for rank, slot in ipairs(saved.order) do slot_ranks[tonumber(slot)] = rank; end
        end
        table.sort(members, by_rank);
    end
    return groups;
end

return layout;
