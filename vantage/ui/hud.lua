local defaults = require('ui.defaults')
local theme = require('ui.theme')
local fonts = require('ui.fonts')
local countdown = require('ui.countdown_text')
local icons = require('ui.icons')
local effect_blink = require('ui.effect_blink')
local recast_icons = require('ui.recast_icons')
local skin = require('ui.client_skin')
local fields = require('ui.fields')
local layout = require('ui.layout')
local resize = require('ui.resize')
local metrics = require('ui.text_metrics')
local render_cache = require('ui.render_cache')
local catalog = require('core.catalog')
local effect_filters = require('core.effect_filters')
local effect_order = require('core.effect_order')
local dispel = require('core.dispel')
local elements = require('ui.elements')
local conditions = require('core.conditions')
local snap = require('ui.snap')
local finite = require('ui.numbers').finite
local clear = require('table.clear')
local hud = {}
local gesture, hover_key, hover_at, last_layout
local notice_gesture
-- Where edit mode places the notices with none up, kept so its frames make nothing.
local empty_notices = { x = 0, y = 0, width = 0, height = 0 }
local minimum_width
-- A table that stands in for a missing one and is never written to.
local NONE = {}

-- Saved lists can name an effect or a member by its number or by the number as text, so the text of each number is
-- made once and kept. Bounded, as members come and go.
local id_texts = render_cache.new(4096)
local function text_of(id)
    if type(id) ~= 'number' or id ~= id then return tostring(id) end
    return id_texts:get(id) or id_texts:put(id, tostring(id))
end

local function selected(values, id)
    if values[id] == true then return true end
    -- An empty list names nothing, so it needs no text.
    if next(values) == nil then return false end
    if values[text_of(id)] == true then return true end
    for _, value in ipairs(values) do if value == id then return true end end
    return false
end

-- The panel's own name for a row's effect, else its name.
local function label_of(panel, row)
    local labels = panel.labels
    local name = labels[row.effect]
    if not name and next(labels) ~= nil then name = labels[text_of(row.effect)] end
    return name or row.name
end

-- The color the panel gives an effect, if it gives one.
local function effect_color(panel, effect)
    local colors = panel.effect_colors
    local color = colors[effect]
    if not color and next(colors) ~= nil then color = colors[text_of(effect)] end
    return color
end

local function any(values)
    return next(values) ~= nil
end

local function in_scope(row, key, settings, context)
    local recast_kind = defaults.recast_panels[key]
    if recast_kind == 'all' then
        return row.domain == 'recast' and settings.panels[key].recast_categories[row.kind] == true
    end
    if recast_kind then return row.domain == 'recast' and row.kind == recast_kind end
    if row.domain == 'recast' then return false end
    if key == 'self_buffs' then return row.scope == 'self' and row.kind ~= 'debuff' end
    if key == 'self_debuffs' then return row.scope == 'self' and row.kind == 'debuff' end
    if key == 'party' then return row.scope == 'party' end
    if key == 'target' then return context.target and row.entity_id == context.target.id end
    if key == 'watch' then
        -- Samples have no list to be on, so the sample mob counts as watched.
        return context.sample and row.scope == 'enemy' or selected(settings.watch_ids or NONE, row.entity_id)
            or settings.panels.watch.list_debuffed and (row.mine or row.by_pet) and row.kind == 'debuff' and row.scope == 'enemy'
    end
    return false
end

-- into, when given, is a table to fill in place of a new one.
local function effect_filter_context(view, settings, compiled, into)
    local rules = effect_filters.compile(compiled or settings.effect_filters)
    local result = into or {}
    result.rules, result.recipients = rules, rules.active
        and (view.effect_recipients or effect_filters.recipients(view.context, nil)) or nil
    return result
end

-- How filter_rows sorts, set for each sort so it makes no closure: the panel, its My order ranks while it sorts by them,
-- and whether each row is pinned while the panel pins any.
local sorting, pinning, ranks, pins = nil, false, {}, {}
local function sorts_before(a, b)
    local panel = sorting
    if pinning then
        local pa, pb = pins[a], pins[b]
        if pa ~= pb then return pa end
    end
    if panel.group_by ~= 'none' then
        local ga = panel.group_by == 'target' and (a.entity_name or '') or (a.group or '')
        local gb = panel.group_by == 'target' and (b.entity_name or '') or (b.group or '')
        if ga ~= gb then return ga < gb end
    end
    if panel.sort == 'longest' then
        local longer = effect_order.longest(a, b)
        if longer ~= nil then return longer end
    elseif panel.sort == 'oldest' then
        local older = effect_order.oldest(a, b)
        if older ~= nil then return older end
    elseif panel.sort == 'fixed' then
        local ra, rb = ranks[a.effect] or math.huge, ranks[b.effect] or math.huge
        if ra ~= rb then return ra < rb end
    elseif panel.sort == 'remaining' then
        local ra, rb = a.deadline or math.huge, b.deadline or math.huge
        if ra ~= rb then return ra < rb end
    end
    local na, nb = a.name or '', b.name or ''
    if na ~= nb then return na < nb end
    if a.entity_id ~= b.entity_id then return (a.entity_id or 0) < (b.entity_id or 0) end
    return tostring(a.key) < tostring(b.key)
end

-- Filtering never changes the tracker rows or mistakes an unseen effect for an absent one. into, when given, is a list to
-- fill in place of a new one.
function hud.filter_rows(view, panel, key, settings, filtering, into)
    local result, context = into or {}, view.context or NONE
    if into then clear(into) end
    filtering = filtering or effect_filter_context(view, settings)
    local filters, recipients = filtering.rules, filtering.recipients
    local query = panel.filter:lower()
    for _, row in ipairs(view.rows or {}) do
        local wanted = row.present ~= false and in_scope(row, key, settings, context)
        if wanted and filters.active and effect_filters.hide(filters, row,
            effect_filters.context(recipients, row.entity_id, row)) then wanted = false end
        -- Every recast is your own, so Only effects I cast leaves recasts alone.
        if wanted and panel.mine_only and not row.mine and not row.by_pet and row.domain ~= 'recast' then wanted = false end
        if wanted and panel.abilities_only and not catalog.from_ability(row) then wanted = false end
        if wanted and panel.known_only and (row.status == 'unknown' or not row.deadline) then wanted = false end
        if wanted and any(panel.include) and not selected(panel.include, row.effect) then wanted = false end
        if wanted and selected(panel.exclude, row.effect) then wanted = false end
        if wanted and any(panel.members) and not context.sample and not selected(panel.members, row.entity_id) then wanted = false end
        if wanted and query ~= '' then
            local words = (row.name or '') .. ' ' .. (row.entity_name or '') .. ' ' .. (row.source_name or '') .. ' ' .. tostring(row.effect)
            wanted = words:lower():find(query, 1, true) ~= nil
        end
        if wanted and any(panel.groups) then
            wanted = false
            for group, on in pairs(panel.groups) do if on and row.group == group then wanted = true; break end end
        end
        if wanted then result[#result + 1] = row end
    end
    -- With nothing pinned no row is, so pins are only looked up when the panel has some, once a row.
    sorting, pinning = panel, next(panel.pinned) ~= nil
    if pinning then for _, row in ipairs(result) do pins[row] = selected(panel.pinned, row.effect) end end
    if panel.sort == 'fixed' then
        clear(ranks)
        for rank, id in ipairs(panel.order) do ranks[id] = rank end
    end
    table.sort(result, sorts_before)
    if pinning then clear(pins) end
    sorting = nil
    return result
end

-- Each time text is made once, by what it shows (whole seconds under a minute, then minutes, then hours), so a ticking
-- countdown makes nothing. Bounded, as a long timer's hours each make one.
local time_texts = render_cache.new(16384)
function hud.time(seconds)
    if type(seconds) ~= 'number' then return '--' end
    seconds = math.max(0, seconds)
    if not finite(seconds) then return countdown.time(seconds) end
    local key = seconds >= 3600 and 20000 + math.floor(seconds / 3600) or seconds >= 60 and 10000 + math.floor(seconds / 60)
        or math.ceil(seconds)
    return time_texts:get(key) or time_texts:put(key, countdown.time(seconds))
end

function hud.remaining(row, now)
    return row.deadline and math.max(0, row.deadline - now) or nil
end

-- A duration override that counts up (core/durations.lua) shows the time since the effect landed instead.
function hud.counts_up(row)
    return row.count_up == true and row.domain ~= 'recast' and type(row.start) == 'number' and row.start == row.start
end

-- The seconds a row's timer shows: what is left, or the time since it landed when it counts up.
function hud.counter(row, now)
    if hud.counts_up(row) then return math.max(0, now - row.start) end
    return hud.remaining(row, now)
end

function hud.timer_text(row, now)
    if tonumber(row.effect)==269 and row.domain~='recast' then return '' end
    if hud.counts_up(row) then return hud.time(hud.counter(row, now)) end
    if row.status == 'unknown' or type(row.deadline)~='number' or row.deadline~=row.deadline or math.abs(row.deadline)==math.huge then return '' end
    if row.status == 'estimated' and row.duration_min and row.total and row.duration_min < row.total and row.start then
        return hud.time(math.max(0, row.start + row.duration_min - now)) .. ' - ' .. hud.time(hud.remaining(row, now))
    end
    return hud.time(hud.remaining(row, now))
end

-- A deadline that isn't a finite number has no countdown (hud.timer_text), so it has no bar either.
function hud.fraction(row, panel, now)
    if not finite(row.deadline) or row.status == 'unknown' then return nil end
    local left = hud.remaining(row, now)
    local span = row.total and row.total > 0 and row.total or panel.horizon
    local fraction = math.max(0, math.min(1, left / span))
    if panel.direction == 'fill' then fraction = 1 - fraction end
    return fraction
end

function hud.details(row, now, panel)
    local labels = panel and panel.labels
    local name = labels and (labels[row.effect] or labels[tostring(row.effect)]) or row.name
    if row.domain == 'recast' then
        local result, left = { name or 'Recast', 'Client ' .. (row.kind or '') .. ' cooldown' }, hud.timer_text(row, now)
        if left ~= '' then result[#result + 1] = 'Remaining: ' .. left end
        if row.total then result[#result + 1] = 'Observed cooldown: ' .. hud.time(row.total)
        elseif left ~= '' then result[#result + 1] = 'The full cooldown was not seen. The bar spans the last ' .. hud.time(panel.horizon) .. '.' end
        if row.reason then result[#result + 1] = row.reason end
        -- What its tint stands for (core/recast_tints.lua).
        if row.locked then
            local lock = row.lock_deadline and row.lock_deadline - now
            result[#result + 1] = (row.kind == 'spell' and 'Spells are locked' or 'Abilities are locked')
                .. (lock and lock > 0 and ' for ' .. hud.time(lock) or '') .. '.'
        elseif row.tint_mp then result[#result + 1] = 'Your MP is below its cost.' end
        if row.icon_ambiguous then
            result[#result + 1] = row.action_icons and #row.action_icons > 1
                and 'Shared timer: the icon group shows up to four distinct action pictures.'
                or 'The client has not identified an action picture for this timer.'
        end
        result[#result + 1] = 'A finished recast does not confirm MP, TP, charges, equipment, or target requirements.'
        return table.concat(result, '\n')
    end
    local out = { name .. '  (#' .. tostring(row.effect) .. ')' }
    if row.entity_name then out[#out + 1] = 'On ' .. row.entity_name end
    if row.source_name then out[#out + 1] = 'From ' .. row.source_name .. (row.by_pet and ' (your pet)' or '') end
    local said = #out + 1
    if countdown.indefinite(row) then
        out[#out + 1] = 'Level Sync is active without a fixed countdown.'
    elseif row.status == 'server' then
        out[#out + 1] = 'The client supplied this remaining time.'
    elseif hud.counts_up(row) then
        out[#out + 1] = 'Your duration override counts up from when it landed.'
    elseif row.status == 'estimated' and row.timing == 'override' then
        out[#out + 1] = 'Estimated from your duration override. It can end sooner.'
    elseif row.status == 'estimated' and row.timing == 'learned' then
        out[#out + 1] = 'Estimated from the times learned from your casts. It can end sooner.'
    elseif row.status == 'estimated' and (row.timing == 'fixed' or row.timing == 'follow') then
        out[#out + 1] = row.reason
    elseif row.status == 'estimated' then
        out[#out + 1] = 'Estimated from an observed application and Phoenix rules. It can end sooner.'
    else
        out[#out + 1] = row.present == true and 'The effect is present. It has no countdown.'
            or 'The effect was observed. It has no countdown.'
    end
    if hud.counts_up(row) then out[#out + 1] = 'Since it landed: ' .. hud.timer_text(row, now)
    elseif row.deadline then out[#out + 1] = 'Remaining: ' .. hud.timer_text(row, now) end
    if row.duration_min and row.total and row.duration_min < row.total then
        out[#out + 1] = 'Modeled duration: ' .. hud.time(row.duration_min) .. ' to ' .. hud.time(row.total) .. '. The bar uses the modeled upper bound. Unseen bonuses or resistance can put the actual duration outside this range.'
    elseif row.total then
        out[#out + 1] = 'Full duration: ' .. hud.time(row.total)
    elseif row.deadline then
        out[#out + 1] = 'The full duration was not seen. The bar spans the last ' .. hud.time(panel.horizon) .. '.'
    end
    -- A count up already says its time since it landed.
    if row.start and not hud.counts_up(row) then out[#out + 1] = 'Elapsed: ' .. hud.time(now - row.start) end
    if row.observed_at then out[#out + 1] = 'Last observed: ' .. hud.time(now - row.observed_at) .. ' ago' end
    -- A reason that repeats the line about its timer, as a count up's does, is said once.
    if not countdown.indefinite(row) and row.reason and row.reason ~= '' and row.reason ~= out[said] then out[#out + 1] = row.reason end
    return table.concat(out, '\n')
end

-- into, when given, is a table to fill in place of a new one: everything it held is cleared first.
function hud.bounds(panel, style, count, width, height, measured_height, measured_width, into)
    local scale = style.scale
    local min_width = minimum_width(panel, style)
    local w = math.min(math.max(panel.width, min_width), width)
    local icon_only = panel.mode == 'icons'
    local row_height = icon_only and style.icon_size * scale
        or math.max(panel.row_height and panel.row_height > 0 and panel.row_height or panel.mode ~= 'text' and style.bar_height or 0,
            panel.show_text ~= false and style.font_size + 8 or 1) * scale * (panel.mode == 'expanded' and 1.65 or 1)
    if not icon_only then
        row_height = math.max(row_height, (panel.row_height or 0) * scale)
        if panel.show_icon then row_height = math.max(row_height, (style.icon_size + 4) * scale) end
    end
    local icon_width = (icon_only or panel.show_icon) and style.icon_size * scale or 0
    row_height = math.max(row_height, measured_height or 0)
    local title_size = style.title_size > 0 and style.title_size or style.font_size
    local padding, bottom, gap = (icon_only and 4 or 8) * scale, (icon_only and 4 or 5) * scale, style.gap * scale
    local heading = icon_only and padding or not style.minimal and panel.show_heading and (title_size + 14) * scale or 6 * scale
    local inner = math.max(1, w - 2 * padding)
    local preferred = icon_only and math.max(icon_width, measured_width or icon_width)
        or math.max((panel.item_width or 280) * scale, minimum_width(panel, style, true) - 16 * scale)
    -- Sizes worked out from a whole number of cells divide back to it only up to float error, so each count
    -- allows for that.
    local maximum_columns = math.max(1, math.floor((inner + gap) / (preferred + gap) + 1e-9))
    -- Never shorter than one row. A bars panel keeps a line below its row as well. Rows past the room or the row limit
    -- are left out with nothing in their place.
    local min_height = icon_only and heading + row_height + bottom or math.max(80, heading + row_height + bottom + 20 * scale)
    local limit = math.min(math.max(panel.height_limit, min_height), height)
    local capacity = math.max(0, math.floor((limit - heading - bottom + gap) / (row_height + gap) + 1e-9))
    local fits = math.min(panel.max_rows, maximum_columns * capacity)
    local shown = math.min(count, panel.max_rows, maximum_columns * capacity)
    local vertical = panel.stack_direction == 'vertical' or panel.stack_direction == nil and not icon_only
    local rows_per_column = math.max(1, math.min(shown, capacity))
    local columns = vertical and math.max(1, math.ceil(shown / rows_per_column)) or math.min(maximum_columns, math.max(1, shown))
    local cell_width = icon_only and math.min(preferred, inner) or (inner - (columns - 1) * gap) / columns
    local lines = math.max(1, vertical and rows_per_column or math.ceil(shown / columns))
    local wanted = heading + (icon_only and bottom or 8*scale) + lines * (row_height + gap) - gap
    local h = panel.auto_height == false and limit or math.min(wanted, limit)
    local rect = into or {}
    if into then clear(into) end
    rect.x, rect.y = math.max(0, math.min(panel.x, width - w)), math.max(0, math.min(panel.y, height - h))
    rect.width, rect.height, rect.row_height, rect.heading, rect.columns, rect.shown = w, h, row_height, heading, columns, shown
    rect.icon_width, rect.min_width, rect.min_height, rect.cell_width = icon_width, min_width, min_height, cell_width
    rect.rows_per_column, rect.vertical, rect.padding = rows_per_column, vertical, padding
    rect.growth_left, rect.fits = panel.growth == 'left', fits
    return rect
end

if VANTAGE_TEST_MODE then
    function hud.field_lines(row, panel, now, name)
        local lines = {}
        if panel.show_name then lines[#lines + 1] = name or row.name end
        if panel.show_target and row.entity_name then lines[#lines + 1] = row.entity_name end
        if panel.show_source and row.source_name then lines[#lines + 1] = 'by ' .. row.source_name end
        if panel.show_elapsed and row.start then lines[#lines + 1] = 'Elapsed ' .. hud.time(now - row.start) end
        if panel.show_total and row.total then
            lines[#lines + 1] = row.duration_min and row.duration_min < row.total
                and 'Range ' .. hud.time(row.duration_min) .. ' - ' .. hud.time(row.total) or 'Total ' .. hud.time(row.total)
        end
        return lines
    end
end

local function inside(x, y, left, top, width, height)
    return x >= left and x < left + width and y >= top and y < top + height
end

-- Text in the look's font: a shadow a pixel down and right unless the bitmap font draws its own, the outline a pixel
-- each way when the look has one, then the text.
local OUTLINE = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
local function draw_text(list, x, y, value, color, size, shadow, style)
    local imgui = require('imgui')
    local baked_shadow = fonts.is_bitmap(style.font) and not fonts.failed(style.font)
    if shadow and not baked_shadow then fonts.paint(imgui, list, style, value, x + 1, y + 1, size, imgui.col32(200, 0, 0, 0)) end
    if style.text_outline then
        local ink = theme.u32(style.outline_color)
        for _, offset in ipairs(OUTLINE) do fonts.paint(imgui, list, style, value, x + offset[1], y + offset[2], size, ink) end
    end
    fonts.paint(imgui, list, style, value, x, y, size, theme.u32(color))
end

-- Ashita draws a clip as a viewport of whole pixels and stretches the clip's own range over it, so a clip off
-- whole pixels shifts and squeezes what it holds. Clips are pushed on whole pixels, rounded outward.
local floor, ceil = math.floor, math.ceil
-- The clip corners, the corners of each box, line and picture, a countdown's place and the icon tint are refilled for
-- each use; the icon UVs never change. The binding copies a vector when it is called and keeps none, and theme.u32
-- reads the tint without keeping it.
local clip_min, clip_max, UV0, UV1, tint = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 1, 1 }, { 1, 1, 1, 1 }
local corner, far, countdown_point = { 0, 0 }, { 0, 0 }, { 0, 0 }
local darker = { 0, 0, 0, 1 }
local function push_clip(list, x0, y0, x1, y1)
    clip_min[1], clip_min[2], clip_max[1], clip_max[2] = floor(x0), floor(y0), ceil(x1), ceil(y1)
    list:PushClipRect(clip_min, clip_max, true)
end

-- What you can take off now lights up, as it does over heads: a glow behind its icon when the panel asks for one, and
-- a bright border (core/dispel.lua decides). On the target and watched enemy panels that is a mob's buff
-- (data/dispelable.lua), never its debuffs. On the self debuffs and party panels it is a debuff (data/cleansable.lua),
-- and Erase reaches every row, as alliance members aren't party rows. The corners and the glow's color are refilled
-- for each use.
local DISPELABLE = dispel.buffs
local light_min, light_max, glow = { 0, 0 }, { 0, 0 }, { 0, 0, 0, 0 }
-- True or false on the enemy panels, and the debuffs you can remove on the others.
local function lights(panel, key, settings, now)
    if not panel.dispel_light then return false end
    local sample = settings.preview
    if key == 'target' or key == 'watch' then return sample or dispel.ready(now) end
    return (key == 'self_debuffs' or key == 'party') and (dispel.cleansable(now, sample))
end
local function lit(row, ready)
    if ready == true then return row.scope == 'enemy' and row.kind ~= 'debuff' and row.domain ~= 'recast' and DISPELABLE[row.effect] == true end
    return ready and row.domain ~= 'recast' and ready[row.effect] == true
end
local function light_behind(list, panel, x, y, width, height)
    if not panel.dispel_glow then return end
    local color, reach = panel.dispel_color, math.max(2, floor(math.min(width, height) / 8 + 0.5))
    glow[1], glow[2], glow[3], glow[4] = color[1], color[2], color[3], color[4] * 0.35
    light_min[1], light_min[2], light_max[1], light_max[2] = x - reach, y - reach, x + width + reach, y + height + reach
    list:AddRectFilled(light_min, light_max, theme.u32(glow), reach)
end
local function light_edge(list, panel, x, y, width, height)
    local thickness = math.max(1, floor(math.min(width, height) / 12 + 0.5))
    light_min[1], light_min[2] = x - thickness * 0.5, y - thickness * 0.5
    light_max[1], light_max[2] = x + width + thickness * 0.5, y + height + thickness * 0.5
    list:AddRect(light_min, light_max, theme.u32(panel.dispel_color), 0, 0, thickness)
end

-- Recast tints (core/recast_tints.lua): a wash over a spell row you can't afford, and a grey wash and a lock over a
-- row locked by an effect on you, with the lock's time left when it is known. Both go under the row's text and
-- countdown, so they never hide it. The corners and the lock's ink are refilled for each use.
local tint_min, tint_max, lock_ink, LOCK_EDGE = { 0, 0 }, { 0, 0 }, { 0, 0, 0, 1 }, { 0, 0, 0, 0.75 }
-- The lock's time is drawn as a countdown, shadowed so it reads on any icon.
local LOCK_TIME = { countdown_shadow = true }
-- Where a row with no icon draws its last countdown, found before the row is drawn so its lock can go just before it:
-- its place and its font size. bar_text visits find_clock with the row's runs.
local lock_clock = { x = nil, y = nil, size = nil, scale = 1 }
local function find_clock(run, tx, ty, clipped)
    if run.countdown and clipped > 0 then lock_clock.x, lock_clock.y, lock_clock.size = tx, ty, run.size * lock_clock.scale end
end
local function tint_of(row, tints)
    if row.domain ~= 'recast' or type(tints) ~= 'table' then return nil end
    if row.locked then
        local key = row.kind == 'spell' and 'spell_lock' or 'ability_lock'
        if tints[key] then return tints[key .. '_color'], true end
    end
    if row.tint_mp and tints.mp then return tints.mp_color, false end
end
local function wash(list, color, x, y, width, height)
    tint_min[1], tint_min[2], tint_max[1], tint_max[2] = x, y, x + width, y + height
    list:AddRectFilled(tint_min, tint_max, theme.u32(color))
end
-- A lock size px tall at x, y in the lock's color, its body edged dark: the shackle, then the body.
local function padlock(list, color, x, y, size)
    lock_ink[1], lock_ink[2], lock_ink[3] = color[1], color[2], color[3]
    local ink, wide = theme.u32(lock_ink), size * 0.8
    local body, arm = floor(size * 0.55 + 0.5), wide * 0.6
    tint_min[1], tint_min[2] = x + (wide - arm) / 2, y
    tint_max[1], tint_max[2] = tint_min[1] + arm, y + size - body + arm / 2
    list:AddRect(tint_min, tint_max, ink, arm / 2, 0, math.max(1, floor(size / 7 + 0.5)))
    tint_min[1], tint_min[2], tint_max[1], tint_max[2] = x, y + size - body, x + wide, y + size
    list:AddRectFilled(tint_min, tint_max, ink, math.max(1, size / 8))
    list:AddRect(tint_min, tint_max, theme.u32(LOCK_EDGE), math.max(1, size / 8), 0, 1)
end
-- The lock and its time left at the top left of an icon, within it.
local function locked_icon(list, row, color, x, y, size, style, now)
    local glyph = math.max(6, floor(size * 0.38 + 0.5))
    padlock(list, color, x + 1, y + 1, glyph)
    local left = row.lock_deadline and row.lock_deadline - now
    if not left or left <= 0 or size - glyph - 3 < 6 then return end
    push_clip(list, x, y, x + size, y + size)
    countdown.draw(list, style.font, countdown.time(left), x + glyph + 2, y, glyph + 1, theme.u32(style.text_color), LOCK_TIME, true,
        countdown_point)
    list:PopClipRect()
end

-- Where each recast row's icon was last drawn on a panel, for a ready pulse on its row (ui/ready_pulse.lua). Only
-- hud.draw notes them, never a preview, and only while the pulse goes on rows. Each spot's table is kept.
local spots, spot_frame, recording = {}, 0, false
local spot_count = 0
-- What hud.draw hands the party cooldown list and the pulses about moving them, refilled each frame.
local moving = {}
local function note_spot(row, x, y, size)
    if not recording or row.domain ~= 'recast' or not row.key then return end
    local spot = spots[row.key]
    if not spot then
        if spot_count >= 256 then spots, spot_count = {}, 0 end
        spot = {}
        spots[row.key], spot_count = spot, spot_count + 1
    end
    spot.x, spot.y, spot.size, spot.frame = x, y, size, spot_frame
end

local function clipped_text(list, x, y, value, color, size, width, shadow, style)
    if width < 3 then return end
    push_clip(list, x, y, x + width, y + size + 4)
    draw_text(list, x, y, value, color, size, shadow, style)
    list:PopClipRect()
end

local function ending_soon(row, panel, now)
    local remaining = hud.remaining(row, now)
    return panel.warning_enabled and remaining and remaining <= panel.warning_seconds
end

local function row_color(row, panel, style, now)
    local color = effect_color(panel, row.effect)
        or (row.status == 'estimated' and style.estimate_color or row.kind == 'debuff' and style.debuff_color or style.buff_color)
    if ending_soon(row, panel, now) then color = panel.colors.warning or style.warning_color end
    return color
end

local function measure(style, text, size, run)
    if run and run.countdown then return countdown.measure(style.font, text, size * style.scale, run, run.countdown_compact) end
    return metrics.width(style.font, text, size * style.scale, style.font_size * style.scale)
end

minimum_width = function(panel, style, content_only)
    local scale, text, largest = style.scale, 0, 0
    if panel.mode == 'icons' then
        local _, width = countdown.icon_values(style.font, '0', style.icon_size, panel, scale)
        local glyph = width * scale
        return math.max(24, math.ceil(math.max(style.icon_size * scale, glyph) + 8 * scale))
    end
    if panel.show_text ~= false then
        for _, id in ipairs(defaults.field_ids) do
            if panel['show_' .. id] then
                local base = panel.mode == 'icons' and (id == 'time' and 12 or math.min(style.font_size, 13)) or style.font_size
                largest = math.max(largest, base)
            end
        end
    end
    if largest > 0 then text = math.max(measure(style, 'W', largest), measure(style, 'M', largest), measure(style, '0', largest)) end
    local icon = panel.show_icon and style.icon_size * scale or 0
    local content = panel.mode == 'icons' and math.max(icon, text) or icon + (icon > 0 and 5 * scale or 0) + text
    return math.max(content_only and 1 or 160, math.ceil(content + 28 * scale))
end

local function icon_entry(text, panel, style, color)
    local size, _, height = countdown.icon_values(style.font,text,style.icon_size,panel,style.scale)
    return {id='time',text=text,size=size,icon_countdown_height=height,countdown_compact=true,color=color,
        countdown=true,countdown_bold=panel.countdown_bold,countdown_shadow=panel.countdown_shadow,
        countdown_outline=panel.countdown_outline,countdown_outline_color=panel.countdown_outline_color}
end

-- Ending soon comes first, as the countdown is all an icon has to say it with. Row text's colors are for the other layouts.
local function icon_time_color(row, panel, style, now)
    local colors = panel.colors or {}
    if ending_soon(row, panel, now) then return colors.warning or style.warning_color end
    return colors.value or style.status_time_color and row_color(row,panel,style,now) or style.value_color or style.text_color
end

function hud.entries(row, panel, style, now)
    if panel.mode == 'icons' then
        local text = hud.timer_text(row, now)
        if text == '' then return {} end
        return {icon_entry(text,panel,style,icon_time_color(row,panel,style,now))}
    end
    local name = label_of(panel, row)
    -- A row with no bar has its countdown to say it's ending soon with.
    return fields.build(row, panel, style, now, hud.time, hud.timer_text(row, now), name, row_color(row, panel, style, now),
        not panel.show_fill and ending_soon(row, panel, now))
end

-- A probe wraps as the widest text of each piece's shape, so it never takes fewer lines than a countdown it
-- stands for.
local function icon_lines(entries, style, width, probe)
    local lines = {}
    for _, entry in ipairs(entries) do
        local token, width_of
        if probe then token, width_of = probe.key .. ':shape', probe.width
        else
            token = metrics.token(style.font, entry.size * style.scale) .. ':' .. tostring(entry.countdown_bold)
                .. ':' .. tostring(entry.countdown_shadow) .. ':' .. tostring(entry.countdown_outline) .. ':compact'
            width_of = function(value) return measure(style,value,entry.size,entry) end
        end
        local wrapped = metrics.lines(entry.text, width, width_of, token)
        for _, value in ipairs(wrapped) do
            -- Nothing writes to a run, so text that didn't wrap is the entry's own.
            local run = entry
            if value ~= entry.text then
                run = {}
                for key, item in pairs(entry) do run[key] = item end
                run.text = value
            end
            lines[#lines + 1] = {run}
        end
    end
    return lines
end

-- Countdowns get wider when they change unit ('1m' to '60s'), so a timed icon panel fits the widest one
-- under an hour. Each timer also counts as every shape it can still reach, so cells never grow as timers
-- count down.
local reached = { 9, 59, 99, 599, 999, 3599, 5999, 9999, 35999, 59999, 99999, 359999, 599999, 999999, 3599999, 5999999, 9999999 }
local digits = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' }

-- A countdown's shape by its text, kept as the few texts a timer shows come back each second. Bounded, as a long
-- timer's hours each make one.
local shape_texts = render_cache.new(1024)
local function shape_of(seconds)
    local text = hud.time(seconds)
    return shape_texts:get(text) or shape_texts:put(text, (text:gsub('%d', '#')))
end

-- A shape is a countdown with '#' for each digit, and its probe stands for every text of that shape, so it
-- measures the widest of them. Bitmap countdowns are measured by their ink, from the leftmost to the rightmost
-- inked pixel of any glyph, and a glyph's ink can start past its own advance or reach past the glyphs after it.
-- So two kinds of text are measured: one digit in every place, the widest when widths add up, and the text
-- whose two edge glyphs and the digits between them push those edges farthest apart. Kept per font, size and
-- countdown style, and per readiness, since a bitmap font still loading measures with fallback metrics.
local probe_sets = render_cache.new(64)
local function probe_set(panel, style)
    -- An empty text measures nothing.
    local size = countdown.icon_values(style.font, '', style.icon_size, panel, style.scale)
    local ready = not fonts.is_bitmap(style.font) or fonts.countdown_renderer(style.font) ~= nil
    local key = render_cache.key(metrics.token(style.font, size * style.scale), size, style.scale, panel.countdown_bold == true,
        panel.countdown_shadow == true, panel.countdown_outline == true, ready)
    local set = probe_sets:get(key)
    if set then return set end
    local sample = icon_entry('0', panel, style)
    local pixels = math.max(1, sample.size * style.scale)
    local left_pad, top_pad, right_pad, bottom_pad = countdown.padding(sample)
    local inks, advances, glyphs, shapes, entries, probes, pair_height = {}, {}, {}, {}, {}, {}, nil
    local reference, spacing
    -- heights: how tall each probe's lines are in the room a panel gives them (probe_height), as a panel asks each frame.
    set = { key = key, heights = {} }
    local function ink(text)
        local saved = inks[text]
        if not saved then
            local width, height = metrics.countdown(style.font, text, pixels, true)
            saved = { width, height }
            inks[text] = saved
        end
        return saved[1], saved[2]
    end
    local function advance(text)
        if not advances[text] then advances[text] = metrics.countdown(style.font, text, pixels, false) end
        return advances[text]
    end
    -- How far a glyph's ink reaches left (left) and right (right) of where it starts, each up to a constant: the
    -- glyph and a reference digit with spaces between them, wide enough that each sets one edge. Spaces carry no
    -- ink in a bitmap font. The spaces double until both answers hold still.
    local function glyph(character)
        local saved = glyphs[character]
        if saved then return saved end
        saved = { advance = advance(character), inked = ink(character) > 0 }
        -- Text not measured yet throws before drawing, so nothing is kept until it all measured.
        if saved.inked and reference == nil then
            local found = false
            for _, digit in ipairs(digits) do if ink(digit) > 0 then found = digit; break end end
            local space = advance(' ')
            spacing, reference = space > 0 and math.ceil((2 * pixels + 8) / space) or 64, found
        end
        if saved.inked and reference then
            local count, left, right = spacing, nil, nil
            for _ = 1, 4 do
                local gap = (' '):rep(count)
                local width = advance(gap)
                local starts = ink(character .. gap .. reference) - saved.advance - width
                local ends = ink(reference .. gap .. character) - advance(reference) - width
                if starts == left and ends == right then break end
                left, right, count = starts, ends, count * 2
            end
            saved.left, saved.right = left, right
        end
        glyphs[character] = saved
        return saved
    end
    -- The tallest pair of digits: ink height doesn't depend on order, so with two digit places this is the most
    -- any pair of them adds.
    local function digit_pairs()
        if pair_height then return pair_height end
        local tallest = 0
        for _, first in ipairs(digits) do
            for _, second in ipairs(digits) do tallest = math.max(tallest, select(2, ink(first .. second))) end
        end
        pair_height = tallest
        return tallest
    end
    -- The widest and tallest a text of this shape gets, with the countdown padding.
    function set.measure(shape)
        local saved = shapes[shape]
        if saved then return saved[1], saved[2] end
        local places, widest, tallest = {}, 0, 0
        for character in shape:gmatch('.') do places[#places + 1] = character == '#' and digits or { character } end
        local function try(text)
            local width, height = ink(text)
            widest, tallest = math.max(widest, width), math.max(tallest, height)
        end
        local open = select(2, shape:gsub('#', ''))
        if open == 0 then try(shape) else for _, digit in ipairs(digits) do try((shape:gsub('#', digit))) end end
        -- The best option at each place for a part it can play. Only inked glyphs set an edge.
        local function best(place, value, inked)
            local top, pick
            for _, character in ipairs(places[place]) do
                local info = glyph(character)
                if not inked or info.inked and info.left then
                    local amount = value(info)
                    if top == nil or amount > top then top, pick = amount, character end
                end
            end
            return top, pick
        end
        local count, part = #places, {}
        for place = 1, count do
            local wide, wide_pick = best(place, function(info) return info.advance end)
            local thin, thin_pick = best(place, function(info) return -info.advance end)
            local opens, opens_pick = best(place, function(info) return info.advance + info.left end, true)
            local closes, closes_pick = best(place, function(info) return info.right end, true)
            local both, both_pick = best(place, function(info) return info.left + info.right end, true)
            local back, back_pick = best(place, function(info) return info.right - info.advance end, true)
            local start, start_pick = best(place, function(info) return info.left end, true)
            part[place] = { wide = wide, wide_pick = wide_pick, thin = -thin, thin_pick = thin_pick, opens = opens,
                opens_pick = opens_pick, closes = closes, closes_pick = closes_pick, both = both, both_pick = both_pick,
                back = back, back_pick = back_pick, start = start, start_pick = start_pick }
        end
        -- One glyph sets each edge. When the left edge comes first the width is its advance past its ink start,
        -- the advances between and the other glyph's ink end. When the right edge comes first (its ink reaches past
        -- the glyphs after it) it is that glyph's ink end past its advance, less the advances between, and the
        -- later glyph's ink start.
        local top, chosen
        for i = 1, count do
            local a = part[i]
            if a.both and (top == nil or a.both > top) then top, chosen = a.both, { i, i, a.both_pick, a.both_pick } end
            local wide, thin = 0, 0
            for j = i + 1, count do
                local b = part[j]
                if a.opens and b.closes and (top == nil or a.opens + wide + b.closes > top) then
                    top, chosen = a.opens + wide + b.closes, { i, j, a.opens_pick, b.closes_pick }
                end
                if a.back and b.start and (top == nil or a.back - thin + b.start > top) then
                    top, chosen = a.back - thin + b.start, { i, j, a.back_pick, b.start_pick, true }
                end
                wide, thin = wide + b.wide, thin + b.thin
            end
        end
        if chosen then
            local text, i, j = {}, chosen[1], chosen[2]
            for place = 1, count do text[place] = part[place].wide_pick end
            if chosen[5] then for place = i + 1, j - 1 do text[place] = part[place].thin_pick end end
            text[i], text[j] = chosen[3], chosen[4]
            try(table.concat(text))
        end
        if open > 0 then
            local fixed = shape:gsub('#', '')
            for _, digit in ipairs(digits) do tallest = math.max(tallest, select(2, ink(fixed .. digit))) end
            if open > 1 then tallest = math.max(tallest, digit_pairs()) end
        end
        saved = { widest + left_pad + right_pad, tallest + top_pad + bottom_pad }
        shapes[shape] = saved
        return saved[1], saved[2]
    end
    function set.width(shape) return (set.measure(shape)) end
    local function entry(shape)
        local saved = entries[shape]
        if not saved then
            local width, height = set.measure(shape)
            saved = {}
            for name, value in pairs(sample) do saved[name] = value end
            saved.text, saved.probe_width, saved.probe_height, saved.icon_countdown_height = shape, width, height, height / style.scale
            entries[shape] = saved
        end
        return saved
    end
    -- The shapes a timer with this much left still shows: its own and each one it passes on the way down.
    local function reach(left)
        local below = 0
        for index, value in ipairs(reached) do
            if value >= left then break end
            below = index
        end
        local own = shape_of(left)
        local name = below .. ':' .. own
        local saved = probes[name]
        if not saved then
            local seen = {}
            saved = { name = name }
            for index = 0, below do
                local shape = index == 0 and own or shape_of(reached[index])
                if not seen[shape] then seen[shape] = true; saved[#saved + 1] = shape end
            end
            probes[name] = saved
        end
        return saved
    end
    -- The probes for one timer: a shape for each it can still show; an estimated range pairs every shape of
    -- its two sides, the time to its shortest end and then the time to its longest.
    function set.probes(head, tail)
        local heads = reach(head)
        local tails = tail and reach(tail)
        local name = heads.name .. (tails and '|' .. tails.name or '')
        local saved = probes[name .. '|probes']
        if not saved then
            saved = {}
            for _, head in ipairs(heads) do
                if tails then for _, tail in ipairs(tails) do saved[#saved + 1] = entry(head .. ' - ' .. tail) end
                else saved[#saved + 1] = entry(head) end
            end
            probes[name .. '|probes'] = saved
        end
        return saved
    end
    return probe_sets:put(key, set)
end

-- An auto-width bar fits the widest text a countdown can still show: its own shape and each it passes on the
-- way down (under an hour, every one, as for icons), each digit the widest. Bar countdowns measure by
-- advance, so no text of a shape is wider than that. Kept per face, size and countdown style, and per plain run
-- (elapsed time) apart from countdown runs, which measure differently.
local bar_countdowns = render_cache.new(64)
local function countdown_set(style, run)
    local key = render_cache.key(metrics.token(style.font, run.size * style.scale), run.countdown == true, run.countdown_bold == true,
        run.countdown_shadow == true, run.countdown_outline == true, run.countdown_compact == true)
    local set = bar_countdowns:get(key)
    if not set then
        set = { digit = '0', texts = {}, widths = {} }
        local best
        for _, digit in ipairs(digits) do
            local width = measure(style, digit, run.size, run)
            if not best or width > best then set.digit, best = digit, width end
        end
        bar_countdowns:put(key, set)
    end
    return set
end
-- The text and its width. own is hud.time(left) when the caller has it.
local function widest_countdown(set, style, run, left, own)
    local below = 0
    for index, value in ipairs(reached) do
        if value >= left then break end
        below = index
    end
    own = own or hud.time(left)
    local name = below .. ':' .. own:gsub('%d', '#')
    local text = set.texts[name]
    if text then return text, set.widths[name] end
    local candidates = { own }
    for index = 1, below do candidates[#candidates + 1] = hud.time(reached[index]) end
    candidates[#candidates + 1] = hud.time(3599)
    for _, value in ipairs(reached) do if value < 3599 then candidates[#candidates + 1] = hud.time(value) end end
    local most
    for _, candidate in ipairs(candidates) do
        candidate = candidate:gsub('%d', set.digit)
        local width = measure(style, candidate, run.size, run)
        if not most or width > most then text, most = candidate, width end
    end
    set.texts[name], set.widths[name] = text, most
    return text, most
end
-- The widest text for the row's countdown, and its width when it is one clock. clock is the row's countdown
-- text, as hud.timer_text gives it.
local function widest_clock(row, panel, style, now, run, set, clock)
    set = set or countdown_set(style, run)
    if row.status == 'estimated' and row.duration_min and row.total and row.duration_min < row.total and row.start then
        return widest_countdown(set, style, run, math.max(0, row.start + row.duration_min - now)) .. ' - '
            .. widest_countdown(set, style, run, hud.remaining(row, now))
    end
    return widest_countdown(set, style, run, hud.counter(row, now), clock)
end
-- Elapsed time counts up to the total at most, so it fits the wider of its own shape and the total's, each
-- digit the widest.
local function widest_elapsed(set, style, run, own, total)
    local bound = total and hud.time(total) or ''
    local name = 'elapsed:' .. own:gsub('%d', '#') .. ':' .. bound:gsub('%d', '#')
    local text = set.texts[name]
    if not text then
        local most
        for _, candidate in ipairs({ own, bound }) do
            candidate = candidate:gsub('%d', set.digit)
            local width = measure(style, candidate, run.size, run)
            if not most or width > most then text, most = candidate, width end
        end
        set.texts[name] = text
    end
    return text
end

-- The probes for an icon panel's timed rows, each once, the hour's first, and their set. The list is kept and refilled
-- by the next call, so a caller reads it before asking again. effective_panel asks for a panel that sizes itself, and
-- panel_rect asks again right after (again) for the same rows at the same time: that takes the first asking's.
local timer_probes, probes_seen, asked = {}, {}, {}
local function add_probes(list)
    for _, entry in ipairs(list) do
        if not probes_seen[entry] then probes_seen[entry] = true; timer_probes[#timer_probes + 1] = entry end
    end
end
local function icon_countdowns(rows, panel, style, now, again)
    if again then
        local same = asked.rows == rows and asked.panel == panel and asked.style == style and asked.now == now
        asked.rows = nil
        if same then return timer_probes, asked.set end
    end
    clear(timer_probes)
    clear(probes_seen)
    local set
    for index = 1, math.min(#rows, panel.max_rows) do
        local row = rows[index]
        if hud.timer_text(row, now) ~= '' then
            if not set then
                set = probe_set(panel, style)
                add_probes(set.probes(3599))
            end
            if row.status == 'estimated' and row.duration_min and row.total and row.duration_min < row.total and row.start then
                add_probes(set.probes(math.max(0, row.start + row.duration_min - now), hud.counter(row, now)))
            else add_probes(set.probes(hud.counter(row, now))) end
        end
    end
    if not again then asked.rows, asked.panel, asked.style, asked.now, asked.set = rows, panel, style, now, set end
    return timer_probes, set
end

local function text_lines(row, panel, style, now, width)
    local entries = hud.entries(row, panel, style, now)
    if panel.mode == 'icons' then return icon_lines(entries, style, width) end
    local standard_order = true
    for i, id in ipairs(defaults.field_ids) do if panel.field_order[i] ~= id then standard_order = false end end
    if panel.mode == 'expanded' and standard_order and not next(panel.field_newlines) then
        local main, detail = {}, {}
        for _, entry in ipairs(entries) do
            if entry.id == 'name' or entry.id == 'target' or entry.id == 'time' then main[#main + 1] = entry
            else
                entry.size = math.min(13, style.font_size)
                detail[#detail + 1] = entry
            end
        end
        if detail[1] then detail[1].newline = true end
        for _, entry in ipairs(detail) do main[#main + 1] = entry end
        entries = main
    end
    return fields.lines(entries, width, panel, function(t, size, run) return measure(style, t, size, run) end)
end

local function run_height(run, scale)
    local top, bottom = 0, 0
    if run.countdown then local _; _, top, _, bottom = countdown.padding(run) end
    return run.icon_countdown_height and run.icon_countdown_height * scale or run.size * scale + top + bottom
end

-- An entry that didn't wrap is its own one run.
local function entry_height(entry, scale)
    if not entry.runs then return math.max(0, run_height(entry, scale)) end
    local height = 0
    for _, run in ipairs(entry.runs) do height = math.max(height, run_height(run, scale)) end
    return height
end

local function lines_height(lines, scale, compact)
    local total = 0
    for index, line in ipairs(lines) do
        local size = 0
        for _, entry in ipairs(line) do size = math.max(size, entry_height(entry, scale)) end
        total = total + size + (compact and (index < #lines and 1 or 0) or 2 * scale)
    end
    return total
end

-- Text only is a bar row with just its name and countdown: no icon, no bar. The saved fields stay as chosen.
local function text_only(p)
    p.show_icon, p.show_fill, p.show_text = false, false, true
    for _, field in ipairs(defaults.field_ids) do p['show_' .. field] = field == 'name' or field == 'time' end
end

-- Each panel's working copy, refilled every frame so its keys keep their room. A settings table that is replaced lets
-- its copies go.
local panel_copies = setmetatable({}, { __mode = 'k' })

-- A bars row's lines, and a row's width for Auto width, are kept from frame to frame for as long as everything they are
-- worked out from stays the same: the settings that shape the panel's fields, which its signature stands for, and the
-- row's own texts, times and colors. A countdown's row is worked out again when its text changes, once a second. They
-- are kept by panel and row, for the rows asked for in this frame and the last; hud.draw counts its frames in
-- layout_frame.
local layout_frame = 0
local signatures, signature_serial, sign_changed = {}, 0, false
local function sign(saved, n, ...)
    for index = 1, select('#', ...) do
        local value = select(index, ...)
        n = n + 1
        if saved[n] ~= value then saved[n], sign_changed = value, true end
    end
    return n
end
-- A number that changes whenever a setting that shapes the panel's fields changes. The settings are compared with the
-- panel's last ones, colors by which table they are and the font by its measuring tokens.
local function field_signature(key, p, s)
    local saved = signatures[key]
    if not saved then
        saved = { count = 0, serial = 0 }
        signatures[key] = saved
    end
    sign_changed = false
    local colors, size = p.colors or NONE, s.font_size * s.scale
    local n = sign(saved, 0, p.mode, p.show_text, p.label_position, p.label_separator, p.alignment, p.wrap, p.separator,
        p.priority_overflow, p.countdown_bold, p.countdown_shadow, p.countdown_outline, p.countdown_outline_color, colors.label,
        colors.detail, colors.value, next(p.field_newlines or NONE) ~= nil, s.font, s.font_size, s.scale, s.status_time_color,
        s.value_color, s.text_color, s.label_color, s.detail_color, metrics.token(s.font, size, size),
        metrics.token(s.font, math.min(13, s.font_size) * s.scale, size), metrics.token(s.font, math.max(1, size)))
    local labels, tints, priorities = p.field_labels or NONE, p.field_colors or NONE, p.field_priority or NONE
    local alignments, newlines, dividers = p.field_alignments or NONE, p.field_newlines or NONE, p.field_dividers or NONE
    for _, id in ipairs(p.field_order or defaults.field_ids) do
        n = sign(saved, n, id, p['show_' .. id], labels[id], tints[id], priorities[id], alignments[id], newlines[id], dividers[id])
    end
    if saved.count ~= n then saved.count, sign_changed = n, true end
    if sign_changed then
        signature_serial = signature_serial + 1
        saved.serial = signature_serial
    end
    return saved.serial
end

-- Each panel's kept rows: lines by row for bars and widths by row for Auto width, each in a map for this frame and one
-- for the last.
local row_stores = {}
local function row_store(key)
    local store = row_stores[key]
    if not store then
        store = { frame = -1, lines = {}, old_lines = {}, widths = {}, old_widths = {} }
        row_stores[key] = store
    end
    if store.frame ~= layout_frame then
        store.frame = layout_frame
        store.lines, store.old_lines = store.old_lines, store.lines
        store.widths, store.old_widths = store.old_widths, store.widths
        clear(store.lines)
        clear(store.widths)
    end
    return store
end
local function kept(current, last, id)
    local found = current[id]
    if found == nil then
        found = last[id]
        if found ~= nil then current[id] = found end
    end
    return found
end

-- What a row's lines or width comes from besides the panel's signature, filled for one row at a time: the texts it
-- shows, its times, its countdown and, for lines, its countdown's color and the room they get. A width also comes from
-- the times its countdown still passes (head and tail, as widest_clock counts them).
local LINE_INPUTS = { 'signature', 'name', 'target', 'source', 'elapsed', 'total', 'shortest', 'status', 'started', 'timed', 'up',
    'clock', 'color', 'soon', 'room' }
local WIDTH_INPUTS = { 'signature', 'name', 'target', 'source', 'elapsed', 'total', 'shortest', 'status', 'started', 'timed', 'up',
    'clock', 'head', 'tail', 'head_text', 'tail_text' }
local inputs = {}
local function row_inputs(row, p, now, signature)
    inputs.signature, inputs.name, inputs.target, inputs.source = signature, label_of(p, row), row.entity_name, row.source_name
    inputs.elapsed = p.show_elapsed and row.start and hud.time(now - row.start) or nil
    inputs.total, inputs.shortest, inputs.status = row.total, row.duration_min, row.status
    inputs.started, inputs.timed, inputs.up = row.start ~= nil, row.deadline ~= nil, row.count_up == true
    inputs.clock = p.show_time and hud.timer_text(row, now) or nil
    return inputs
end
local function same_inputs(record, names)
    for index = 1, #names do
        local name = names[index]
        if record[name] ~= inputs[name] then return false end
    end
    return true
end
local function keep_inputs(names)
    local record = {}
    for index = 1, #names do
        local name = names[index]
        record[name] = inputs[name]
    end
    return record
end

-- A bars row's lines in this much room, and how tall they are. A panel of several columns can lay its rows out in more
-- than one room each frame, narrower once it has measured them, so a row keeps its lines for its last few rooms.
local ROOMS = 4
local function row_lines(store, row, p, style, now, signature, room)
    row_inputs(row, p, now, signature)
    inputs.color, inputs.soon, inputs.room = row_color(row, p, style, now), (not p.show_fill and ending_soon(row, p, now)) and true or false, room
    local id = row.key or row
    local first = kept(store.lines, store.old_lines, id)
    local record = first
    while record do
        if same_inputs(record, LINE_INPUTS) then return record end
        record = record.other
    end
    record = keep_inputs(LINE_INPUTS)
    record.lines = text_lines(row, p, style, now, room)
    record.height = lines_height(record.lines, style.scale)
    -- The new lines go first, with what was kept for other rooms behind them. What was kept for this room goes.
    local last, count, other = record, 1, first
    while other and count < ROOMS do
        if other.room ~= room then
            last.other = other
            last, count = other, count + 1
        end
        other = other.other
    end
    last.other = nil
    store.lines[id] = record
    return record
end

-- How many of the times under an hour and past it (reached) a countdown with this much left has passed.
local function below_of(left)
    local below = 0
    for index, value in ipairs(reached) do
        if value >= left then break end
        below = index
    end
    return below
end

-- Auto width's measure: a countdown or elapsed time measures as the widest text it can still show, for the row
-- measuring names.
local measuring = { row = nil, panel = nil, style = nil, now = 0 }
local function widest_width(t, size, run)
    local row, p, style, now = measuring.row, measuring.panel, measuring.style, measuring.now
    if run and run.countdown and run.clock and run.clock ~= '' then
        local clock = run.clock
        local at = t:find(clock, 1, true)
        if at then
            local text, width = widest_clock(row, p, style, now, run, countdown_set(style, run), clock)
            -- A run that is the clock alone measures as its widest text did.
            if width and #t == #clock and size == run.size then return width end
            t = t:sub(1, at - 1) .. text .. t:sub(at + #clock)
        end
    elseif run and run.id == 'elapsed' and row.start then
        local own = hud.time(now - row.start)
        local at = t:find(own, 1, true)
        if at then t = t:sub(1, at - 1) .. widest_elapsed(countdown_set(style, run), style, run, own, row.total) .. t:sub(at + #own) end
    end
    return measure(style, t, size, run)
end

-- How wide a row's fields are on their widest line, for Auto width.
local function row_width(store, row, p, style, now, signature)
    row_inputs(row, p, now, signature)
    inputs.head, inputs.tail, inputs.head_text, inputs.tail_text = nil, nil, nil, nil
    if inputs.clock and inputs.clock ~= '' then
        if row.status == 'estimated' and row.duration_min and row.total and row.duration_min < row.total and row.start then
            local head, tail = math.max(0, row.start + row.duration_min - now), hud.remaining(row, now)
            inputs.head, inputs.tail, inputs.head_text, inputs.tail_text = below_of(head), below_of(tail), hud.time(head), hud.time(tail)
        else inputs.head = below_of(hud.counter(row, now)) end
    end
    local id = row.key or row
    local record = kept(store.widths, store.old_widths, id)
    if record and same_inputs(record, WIDTH_INPUTS) then return record.width end
    record = keep_inputs(WIDTH_INPUTS)
    measuring.row, measuring.panel, measuring.style, measuring.now = row, p, style, now
    local line, maximum = 0, 0
    for i, entry in ipairs(hud.entries(row, p, style, now)) do
        if entry.newline then maximum, line = math.max(maximum, line), 0 end
        line = line + fields.width(entry, widest_width)
            + (i > 1 and measure(style, entry.divider or p.separator, entry.size) or 0)
    end
    record.width = math.max(line, maximum)
    store.widths[id] = record
    return record.width
end

-- screen_height, when given, is the most a panel can be tall there, as hud.bounds clamps it.
local function effective_panel(key, panel, style, rows, now, context, screen_height)
    local p = panel_copies[panel]
    if p then
        for name in pairs(p) do if panel[name] == nil then p[name] = nil end end
    else
        p = {}
        panel_copies[panel] = p
    end
    for name, value in pairs(panel) do p[name] = value end
    if p.mode == 'text' then text_only(p) end
    if p.auto_width and p.mode == 'icons' then
        local cell, row_height = style.icon_size * style.scale, style.icon_size * style.scale
        for _,entry in ipairs(icon_countdowns(rows,p,style,now)) do
            local width,height=entry.probe_width,entry.probe_height
            cell=math.max(cell,width)
            row_height=math.max(row_height,(p.icon_countdown_position=='inside' and 0
                or (style.icon_size+(p.icon_countdown_gap or 0))*style.scale)+height)
        end
        local count,gap=math.max(1,math.min(#rows,p.max_rows)),style.gap*style.scale
        local capacity=math.max(1,math.floor((math.min(p.height_limit,screen_height or math.huge)-8*style.scale+gap)/(row_height+gap)+1e-9))
        local wanted=p.stack_direction=='vertical' and math.ceil(count/capacity) or count
        local columns=math.min(wanted,math.max(1,math.floor((p.max_width-8*style.scale+gap)/(cell+gap))))
        p.width=math.max(p.min_width,math.min(p.max_width,columns*(cell+gap)-gap+8*style.scale))
    end
    if p.auto_width and p.mode ~= 'icons' then
        local widest, store, signature = 0, row_store(key), field_signature(key, p, style)
        -- Rows past Most shown aren't laid out, so they leave the width alone.
        for index = 1, math.min(#rows, p.max_rows) do
            widest = math.max(widest, row_width(store, rows[index], p, style, now, signature))
        end
        local title = p.title ~= '' and p.title or 'Vantage'
        if not style.minimal and p.show_heading then widest = math.max(widest, measure(style, title, style.title_size > 0 and style.title_size or style.font_size) + 30 * style.scale) end
        local wanted=widest+(p.show_icon and style.icon_size+33 or 28)*style.scale
        if p.stack_direction=='horizontal' then
            local cell=math.max((p.item_width or 280)*style.scale,minimum_width(p,style,true)-16*style.scale)
            local columns=math.min(math.max(1,math.min(#rows,p.max_rows)),math.max(1,math.floor((p.max_width-16*style.scale+style.gap*style.scale)/(cell+style.gap*style.scale))))
            wanted=columns*(cell+style.gap*style.scale)-style.gap*style.scale+16*style.scale
        end
        p.width = math.max(p.min_width, math.min(p.max_width, wanted))
    end
    local chat = layout.chat(context)
    if chat and p.dock_match_width and p.anchor and p.anchor.to == 'chat' then p.width = chat.width end
    return p
end

-- An icon panel's rows show the same few countdowns from frame to frame, so the lines made for one are kept: by what
-- the panel's countdowns look like and the room they get, then by color, then by text. Like metrics.lines's, they are
-- read only. Each level is bounded, as a load or an Undo brings new color tables, and a panel shows up to 64 rows.
local icon_line_sets = render_cache.new(32)
local no_lines = {}
local function icon_line_set(panel, style, width)
    local size = countdown.icon_values(style.font, '', style.icon_size, panel, style.scale)
    -- A bitmap font still loading measures with fallback metrics, so readiness counts, as it does for a probe set.
    local ready = not fonts.is_bitmap(style.font) or fonts.countdown_renderer(style.font) ~= nil
    local key = render_cache.key(metrics.token(style.font, size * style.scale), size, style.scale, width, ready, panel.countdown_bold,
        panel.countdown_shadow, panel.countdown_outline, panel.countdown_outline_color)
    return icon_line_sets:get(key) or icon_line_sets:put(key, render_cache.new(16))
end

local function kept_icon_lines(set, row, panel, style, now, width)
    local text = hud.timer_text(row, now)
    if text == '' then return no_lines end
    local color = icon_time_color(row, panel, style, now)
    local shade = color or no_lines
    local by_text = set:get(shade) or set:put(shade, render_cache.new(128))
    return by_text:get(text) or by_text:put(text, icon_lines({ icon_entry(text, panel, style, color) }, style, width))
end

-- How tall a probe's lines are in this much room, kept in its probe set by the room, a few at a time.
local function probe_height(set, entry, style, width)
    if width ~= width then return lines_height(icon_lines({ entry }, style, width, set), style.scale, true) end
    local by_width = set.heights[entry]
    if not by_width then
        by_width = { count = 0 }
        set.heights[entry] = by_width
    end
    local height = by_width[width]
    if height == nil then
        height = lines_height(icon_lines({ entry }, style, width, set), style.scale, true)
        if by_width.count >= 16 then
            clear(by_width)
            by_width.count = 0
        end
        by_width[width], by_width.count = height, by_width.count + 1
    end
    return height
end

-- Each panel's place and its rows' lines, kept and refilled each frame. hud.bounds clears the place, and what else goes
-- on it is set again after.
local panel_places = {}
local function panel_rect(key, panel, style, rows, now, width, height)
    local place = panel_places[key]
    if not place then
        place = { rect = {}, lines = {}, layouts = {} }
        panel_places[key] = place
    end
    local icon_only,preferred,countdowns,probe=panel.mode=='icons',nil,nil,nil
    if icon_only then
        countdowns,probe=icon_countdowns(rows,panel,style,now,true)
        preferred=style.icon_size*style.scale
        for _,entry in ipairs(countdowns) do preferred=math.max(preferred,entry.probe_width) end
    end
    local rect=hud.bounds(panel,style,#rows,width,height,nil,preferred,place.rect)
    local wanted=rect.row_height
    local prepared,layouts,store,signature=place.lines,place.layouts,nil,nil
    if not icon_only then store,signature=row_store(key),field_signature(key,panel,style) end
    for attempt=1,math.max(1,math.min(#rows+1,64)) do
        local available=rect.cell_width-(icon_only and 0 or 12*style.scale)
        if not icon_only and rect.icon_width>0 then available=available-rect.icon_width-5*style.scale end
        clear(prepared)
        clear(layouts)
        local set=icon_only and icon_line_set(panel,style,math.max(1,available))
        for index=1,math.min(#rows,panel.max_rows) do
            if set then prepared[index]=kept_icon_lines(set,rows[index],panel,style,now,math.max(1,available))
            else
                local kept_row=row_lines(store,rows[index],panel,style,now,signature,math.max(1,available))
                prepared[index],layouts[index]=kept_row.lines,kept_row
                local extra=panel.show_fill and panel.bar_style=='rail' and panel.bar_thickness+2 or 0
                wanted=math.max(wanted,kept_row.height+(extra+6)*style.scale)
            end
        end
        if countdowns then
            for _,entry in ipairs(countdowns) do
                local timer_height=probe_height(probe,entry,style,math.max(1,available))
                wanted=math.max(wanted,(panel.icon_countdown_position=='inside' and 0 or style.icon_size*style.scale)
                    +(timer_height>0 and timer_height+(panel.icon_countdown_position=='inside' and 0 or (panel.icon_countdown_gap or 0)*style.scale) or 0))
            end
        end
        local previous=rect.cell_width
        rect=hud.bounds(panel,style,#rows,width,height,wanted,preferred,place.rect)
        rect.row_lines,rect.row_layouts=prepared,layouts
        if math.abs(previous-rect.cell_width)<.001 then break end
    end
    return rect
end

local function visible_entries(lines)
    local displayed, seen = {}, {}
    for line_index, line in ipairs(lines) do
        for entry_index, entry in ipairs(line) do
            if not seen[entry.id] then
                displayed[#displayed + 1] = { id = entry.id, newline = line_index > 1 and entry_index == 1 }
                seen[entry.id] = true
            end
        end
    end
    return displayed
end

local function cell_position(rect,index,gap)
    local column=rect.vertical and math.floor((index-1)/rect.rows_per_column) or (index-1)%rect.columns
    local row=rect.vertical and (index-1)%rect.rows_per_column or math.floor((index-1)/rect.columns)
    local offset=column*(rect.cell_width+gap)
    local left=rect.growth_left and rect.x+rect.width-rect.padding-rect.cell_width-offset or rect.x+rect.padding+offset
    return left,rect.y+rect.heading+row*(rect.row_height+gap)
end

local function effect_emphasis(view,row,now,colors,style)
    local active=view.emphasis and (view.emphasis[row.key] or view.emphasis[row.instance])
    local color=colors.warning or style.warning_color
    for _,notice in ipairs(view.notices or NONE) do
        if notice.emphasis and notice.key==row.key and notice.instance==row.instance then
            if notice.flash and (notice.flash_ends or notice.ends)>now then
                active=math.floor(now*4)%2==0
                color=notice.flash_color or color
            elseif not notice.flash and notice.ends>now then active=true end
        end
    end
    return active,color
end

-- Where each run of a row's lines goes in the room bar_cell gives it: by line, its height and, for each piece, its place,
-- runs and their widths. Kept with the row's lines for that room.
local function place_runs(kept_row, available, p, s)
    if kept_row.places and kept_row.place_room == available then return kept_row.places end
    local scale, places = s.scale, {}
    local function width_of(t, size, run) return measure(s, t, size, run) end
    for index, line in ipairs(kept_row.lines) do
        local size, items = 0, {}
        for _, item in ipairs(fields.positions(line, available, p.separator, width_of)) do
            local entry = item.entry
            size = math.max(size, entry_height(entry, scale))
            local runs, spans = entry.runs or { entry }, {}
            for run_index, run in ipairs(runs) do spans[run_index] = measure(s, run.text, run.size, run) end
            items[#items + 1] = { x = item.x, width = item.width, runs = runs, spans = spans }
        end
        places[index] = { size = size, items = items }
    end
    kept_row.places, kept_row.place_room = places, available
    return places
end

-- Where bar row i sits and its text starts, or nil once a row no longer fits above the bottom edge. The cell is kept and
-- refilled for each row.
local bar_place = {}
local function bar_cell(rect, i, p, s)
    local scale = s.scale
    local left, top = cell_position(rect, i, s.gap * scale)
    -- The same allowance for float error as hud.bounds counts its rows with, so a row it counts gets a cell.
    if top + rect.row_height > rect.y + rect.height - 5 * scale + 1e-9 then return nil end
    local bar_left = left + rect.icon_width + (rect.icon_width > 0 and 5 * scale or 0)
    local bar_width = left + rect.cell_width - bar_left
    local available = bar_width - 12 * scale
    local kept_row = rect.row_layouts[i]
    local text_top = top + math.max(3 * scale, (rect.row_height - kept_row.height - (p.show_fill and p.bar_style == 'rail' and p.bar_thickness * scale or 0)) / 2)
    local cell = bar_place
    cell.left, cell.top, cell.bar_left, cell.bar_width, cell.text_left = left, top, bar_left, bar_width, bar_left + 6 * scale
    cell.available, cell.text_top, cell.places = available, text_top, place_runs(kept_row, available, p, s)
    return cell
end

-- Visits every text run of a bar row where paint puts it.
local function bar_text(cell, s, visit)
    local scale, text_top, text_left, places = s.scale, cell.text_top, cell.text_left, cell.places
    for index = 1, #places do
        local line = places[index]
        local items = line.items
        for item_index = 1, #items do
            local item = items[item_index]
            local runs, spans, at = item.runs, item.spans, 0
            for run_index = 1, #runs do
                local span = spans[run_index]
                visit(runs[run_index], text_left + item.x + at, text_top, math.min(span, item.width - at))
                at = at + span
            end
        end
        text_top = text_top + line.size + 2 * scale
    end
end

-- What draw_run draws with, set for each bar row: the list and look, and for a locked row with no icon, where its lock
-- goes, which the text before it on its line stops short of.
local bar_run = { list = nil, style = nil, lock_x = nil, lock_y = nil, ahead = nil }
local function draw_run(run, tx, ty, clipped)
    local list, s, lock_x = bar_run.list, bar_run.style, bar_run.lock_x
    local scale = s.scale
    if lock_x and not run.countdown and ty == bar_run.lock_y and tx < bar_run.ahead then clipped = math.max(0, math.min(clipped, lock_x - 2 * scale - tx)) end
    if run.countdown and clipped > 0 then
        push_clip(list, tx, ty, tx + clipped, ty + entry_height(run, scale) + 4)
        countdown.draw(list, s.font, run.text, tx, ty, run.size * scale, theme.u32(run.color), run, nil, countdown_point)
        list:PopClipRect()
    elseif not run.countdown then
        clipped_text(list, tx, ty, run.text, run.color, run.size * scale, clipped, s.text_shadow, s)
    end
end

local function paint_icons(view,settings,key,rows,rect,now,mouse,panel,into)
    local list,style=into or require('imgui').GetWindowDrawList(),settings.style
    local scale,hovered=style.scale,nil
    local ready=lights(panel,key,settings,now)
    local tints=settings.recast_tints
    rect.rows,rect.painted=rows,rect.shown
    push_clip(list,rect.x,rect.y,rect.x+rect.width,rect.y+rect.height)
    for index=1,rect.shown do
        local row=rows[index]
        local left,top=cell_position(rect,index,style.gap*scale)
        local icon_x=left+(rect.cell_width-rect.icon_width)/2
        local emphasis,emphasis_color=effect_emphasis(view,row,now,panel.colors,style)
        if row.domain=='recast' then
            recast_icons.draw(list,row,style.recast_icon_art,icon_x,top,rect.icon_width,1,recast_icons.status_art(style))
            local tinted,locked=tint_of(row,tints)
            if tinted then
                wash(list,tinted,icon_x,top,rect.icon_width,rect.icon_width)
                if locked then locked_icon(list,row,tinted,icon_x,top,rect.icon_width,style,now) end
            end
            note_spot(row,icon_x,top,rect.icon_width)
        else
            local picture=icons.status(row.icon or row.effect,style.icon_art)
            local light=lit(row,ready)
            if light then light_behind(list,panel,icon_x,top,rect.icon_width,rect.icon_width) end
            if picture then
                -- A flash tints the icon but keeps its own opacity, so the icon is always drawn.
                if emphasis then tint[1],tint[2],tint[3]=emphasis_color[1],emphasis_color[2],emphasis_color[3] end
                local ink=emphasis and theme.u32(tint) or 0xFFFFFFFF
                corner[1],corner[2],far[1],far[2]=icon_x,top,icon_x+rect.icon_width,top+rect.icon_width
                list:AddImage(picture,corner,far,UV0,UV1,effect_blink.tint(row,panel,now,ink))
            end
            if light then light_edge(list,panel,icon_x,top,rect.icon_width,rect.icon_width) end
        end
        local lines=rect.row_lines[index]
        local timer_y=panel.icon_countdown_position=='inside' and top+math.max(0,rect.icon_width-lines_height(lines,scale,true))
            or top+rect.icon_width+(panel.icon_countdown_gap or 0)*scale
        for _,line in ipairs(lines) do
            local entry=line[1]
            local timer_width=measure(style,entry.text,entry.size,entry)
            local timer_x=left+math.max(0,(rect.cell_width-timer_width)/2)
            push_clip(list,left,timer_y,left+rect.cell_width,timer_y+entry_height(entry,scale)+2*scale)
            countdown.draw(list,style.font,entry.text,timer_x,timer_y,entry.size*scale,
                theme.u32(emphasis and emphasis_color or entry.color),entry,true,countdown_point)
            list:PopClipRect()
            timer_y=timer_y+entry_height(entry,scale)+1
        end
        if mouse and inside(mouse.x,mouse.y,left,top,rect.cell_width,rect.row_height) then hovered=row end
    end
    list:PopClipRect()
    return hovered
end

-- What a panel's box draws: its backdrop and its border. Shared follows the shared switches.
local function panel_box(p, s)
    local box = p.box
    if box == 'both' then return true, true end
    if box == 'background' then return true, false end
    if box == 'border' then return false, true end
    if box == 'none' then return false, false end
    return s.background, s.border
end
hud.panel_box = panel_box

-- A plain theme draws the outline on the window's edge, which ImGui clips by the window border size. A panel that
-- draws one, from its own pick or from the shared Border, opens its window with none, so the outline shows.
-- Every other panel keeps ImGui's border size.
local function own_outline(p, s)
    local _, border = panel_box(p, s)
    return border and p.mode ~= 'icons' and not s.minimal and not skin.active(s)
end

-- ImGui puts a window on whole pixels, cutting its position and size toward zero. A box drawn on the window's edge
-- goes on those pixels too, or the part past a cut edge is clipped.
local function pixel(value)
    return value < 0 and ceil(value) or floor(value)
end

-- A heading's title with the samples' mark, made once for each title. Bounded, as a title is typed a letter at a time.
local sample_titles = render_cache.new(64)
local function sample_title(title)
    return sample_titles:get(title) or sample_titles:put(title, title .. '  /  Sample')
end

-- edge: the panel's own window was opened with no border size (own_outline), so its box goes on that window's pixels.
-- into: the list hud.draw paints on, else the window's.
local function paint(view, settings, key, rows, rect, now, mouse, effective, edge, into)
    local imgui = require('imgui')
    local p, s, list = effective or settings.panels[key], settings.style, into or imgui.GetWindowDrawList()
    if p.mode=='icons' then return paint_icons(view,settings,key,rows,rect,now,mouse,p,into) end
    local scale, x, y, colors = s.scale, rect.x, rect.y, p.colors
    local background, border = panel_box(p, s)
    local native_panel = skin.panel(list, rect, s, colors, nil, background, border)
    local x0, y0, x1, y1 = x, y, x + rect.width, y + rect.height
    if edge then
        x0, y0 = pixel(x), pixel(y)
        x1, y1 = x0 + pixel(rect.width), y0 + pixel(rect.height)
    end
    if not native_panel and not s.minimal and background then
        corner[1], corner[2], far[1], far[2] = x0, y0, x1, y1
        list:AddRectFilled(corner, far, theme.u32(skin.fallback_background(s, colors.background), s.opacity), s.rounding)
    end
    if not native_panel and not s.minimal and border then
        corner[1], corner[2], far[1], far[2] = x0, y0, x1, y1
        list:AddRect(corner, far, theme.u32(colors.border or s.border_color, s.opacity), s.rounding, 0, 1)
    end
    if not s.minimal and p.show_heading then
        local title = p.title ~= '' and p.title or defaults.panel_names[key]
        if settings.preview then title = sample_title(title) end
        local size = (s.title_size > 0 and s.title_size or s.font_size) * scale
        -- The rows it shows, never the ones its room or row limit left out. A count too wide for its place ends as far in
        -- from the right edge as the title starts from the left, and the title stops short of it.
        local count = text_of(rect.shown)
        local count_x, title_width = x + rect.width - 32 * scale, rect.width - 50 * scale
        local count_width, edge_x = metrics.width(s.font, count, size, s.font_size * scale), x + rect.width - 9 * scale
        if count_x + count_width > edge_x then
            count_x = edge_x - count_width
            title_width = math.min(title_width, count_x - 9 * scale - (x + 9 * scale))
        end
        clipped_text(list, x + 9 * scale, y + 6 * scale, title, colors.title or s.title_color, size, title_width, s.text_shadow, s)
        draw_text(list, count_x, y + 6 * scale, count, colors.detail or s.detail_color, size, false, s)
    end
    local row_y, hovered = y + rect.heading
    push_clip(list, x + 4, row_y, x + rect.width - 4, y + rect.height - 4)
    if #rows == 0 and not s.minimal then
        local text = view.valid == false and 'Waiting for character data' or 'No matching effects'
        clipped_text(list, x + 10 * scale, row_y + 4 * scale, text, colors.detail or s.detail_color, s.font_size * scale, rect.width - 20 * scale, false, s)
    end
    local ready = lights(p, key, settings, now)
    local tints = settings.recast_tints
    rect.rows, rect.painted = rows, 0
    bar_run.list, bar_run.style = list, s
    for i = 1, rect.shown do
        local row = rows[i]
        local cell = bar_cell(rect, i, p, s)
        if not cell then break end
        rect.painted = i
        local left, top = cell.left, cell.top
        local width,color=rect.cell_width,row_color(row,p,s,now)
        local emphasis,emphasis_color=effect_emphasis(view,row,now,colors,s)
        local picture = p.show_icon and row.domain ~= 'recast' and icons.status(row.icon or row.effect, s.icon_art) or nil
        local icon_width = rect.icon_width
        local bar_left, bar_width = cell.bar_left, cell.bar_width
        local fill_top = p.bar_style == 'rail' and top + rect.row_height - math.min(p.bar_thickness * scale, rect.row_height) or top
        if p.show_fill then
            local fraction = hud.fraction(row, p, now)
            local gauge_color = colors.fill_start or color
            local remaining = hud.remaining(row, now)
            if p.warning_enabled and remaining and remaining <= p.warning_seconds
                or effect_color(p, row.effect) then gauge_color = color end
            local native_gauge = skin.gauge(list, bar_left, fill_top, bar_width, top + rect.row_height - fill_top, fraction, s, p, gauge_color)
            if not native_gauge then
                corner[1], corner[2], far[1], far[2] = bar_left, fill_top, left + width, top + rect.row_height
                list:AddRectFilled(corner, far, theme.u32(colors.track or s.track_color, s.opacity), s.rounding)
            end
            if fraction then
                local start = p.fill_direction == 'left' and bar_left + bar_width * (1 - fraction) or bar_left
                local finish = p.fill_direction == 'left' and bar_left + bar_width or bar_left + bar_width * fraction
                local first, last = colors.fill_start or color, colors.fill_end or color
                local remaining = hud.remaining(row, now)
                if p.warning_enabled and remaining and remaining <= p.warning_seconds
                    or effect_color(p, row.effect) then first, last = color, color
                elseif p.gradient and first[1] == last[1] and first[2] == last[2] and first[3] == last[3] then
                    -- One color has nothing to run to, so it runs to a darker shade of itself.
                    darker[1], darker[2], darker[3], darker[4] = first[1] * 0.55, first[2] * 0.55, first[3] * 0.55, first[4] or 1
                    last = darker
                end
                local alpha = (p.bar_style == 'rail' and 0.9 or 0.3) * s.opacity
                corner[1], corner[2], far[1], far[2] = start, fill_top, finish, top + rect.row_height
                if not native_gauge and p.gradient then
                    if p.fill_direction == 'left' then first, last = last, first end
                    list:AddRectFilledMultiColor(corner, far, theme.u32(first, alpha), theme.u32(last, alpha), theme.u32(last, alpha), theme.u32(first, alpha))
                elseif not native_gauge then list:AddRectFilled(corner, far, theme.u32(first, alpha), s.rounding) end
                if p.warning_mark then
                    local span = row.total and row.total > 0 and row.total or p.horizon
                    local at = math.min(1, p.warning_seconds / span)
                    if p.direction == 'fill' then at = 1 - at end
                    if p.fill_direction == 'left' then at = 1 - at end
                    local marker = bar_left + bar_width * at
                    corner[1], corner[2], far[1], far[2] = marker, fill_top, marker, top + rect.row_height
                    list:AddLine(corner, far, theme.u32(colors.warning or s.warning_color), 1)
                end
            end
            if row.status == 'estimated' then
                -- The dashes share one color and one pair of corners.
                local ink, right, base = theme.u32(color), left + width, top + rect.row_height - 1
                for mark = bar_left, left + width - 2, 8 * scale do
                    corner[1], corner[2], far[1], far[2] = mark, base, math.min(mark + 4 * scale, right), base
                    list:AddLine(corner, far, ink, 1)
                end
            end
        end
        if emphasis then
            corner[1], corner[2], far[1], far[2] = bar_left, top, left + width, top + rect.row_height
            list:AddRect(corner, far, theme.u32(emphasis_color), s.rounding, 0, 2)
        end
        -- A lit buff lights its icon, or its bar when the row shows no icon.
        local light = lit(row, ready)
        if light and picture then light_behind(list, p, left, top + 2 * scale, icon_width, icon_width)
        elseif light then light_edge(list, p, bar_left, top, left + width - bar_left, rect.row_height) end
        if p.show_icon and row.domain == 'recast' then
            local size,icon_x = icon_width,left
            if not recast_icons.draw(list, row, s.recast_icon_art, icon_x, top + 2 * scale, size, 1, recast_icons.status_art(s)) then
                corner[1], corner[2], far[1], far[2] = icon_x, top + 2 * scale, icon_x + size, top + 2 * scale + size
                list:AddRect(corner, far, theme.u32(color), math.min(3 * scale, size / 4))
            end
        elseif picture then
            corner[1], corner[2], far[1], far[2] = left, top + 2 * scale, left + icon_width, top + 2 * scale + icon_width
            list:AddImage(picture, corner, far, UV0, UV1, effect_blink.tint(row,p,now,0xFFFFFFFF))
            if light then light_edge(list, p, left, top + 2 * scale, icon_width, icon_width) end
        end
        -- A tinted recast washes its bar and icon; a locked one also shows its lock on the icon, or beside its
        -- countdown when the row has no icon.
        local tinted, locked = tint_of(row, tints)
        if tinted then
            wash(list, tinted, bar_left, top, left + width - bar_left, rect.row_height)
            if p.show_icon then
                wash(list, tinted, left, top + 2 * scale, icon_width, icon_width)
                if locked then locked_icon(list, row, tinted, left, top + 2 * scale, icon_width, s, now) end
            end
        end
        if p.show_icon then note_spot(row, left, top + 2 * scale, icon_width) else note_spot(row, bar_left, top, rect.row_height) end
        -- With no icon the lock goes just before the countdown, and the text before it on its line stops short of it.
        local lock_x, lock_y, lock_size, lock_text, ahead
        if locked and not p.show_icon then
            lock_clock.x, lock_clock.y, lock_clock.size, lock_clock.scale = nil, nil, nil, scale
            bar_text(cell, s, find_clock)
            lock_size = math.max(8, floor((lock_clock.size or s.font_size * scale) + 0.5))
            local left_lock = row.lock_deadline and row.lock_deadline - now
            lock_text = left_lock and left_lock > 0 and hud.time(left_lock) or ''
            local spread = lock_size * 0.8 + (lock_text ~= '' and countdown.measure(s.font, lock_text, lock_size, LOCK_TIME, true) + 2 * scale or 0)
            local clock_x = lock_clock.x
            lock_x = math.max(bar_left + 2 * scale, (clock_x and clock_x - 4 * scale or left + width - 6 * scale) - spread)
            lock_y, ahead = lock_clock.y or cell.text_top, clock_x or math.huge
        end
        bar_run.lock_x, bar_run.lock_y, bar_run.ahead = lock_x, lock_y, ahead
        bar_text(cell, s, draw_run)
        if lock_x then
            padlock(list, tinted, lock_x, lock_y + 1, lock_size - 2)
            if lock_text ~= '' then
                countdown.draw(list, s.font, lock_text, lock_x + lock_size * 0.8 + 2 * scale, lock_y, lock_size, theme.u32(s.text_color), LOCK_TIME, true,
                    countdown_point)
            end
        end
        if mouse and inside(mouse.x, mouse.y, left, top, width, rect.row_height) then hovered = row end
    end
    list:PopClipRect()
    return hovered
end

-- The window flags of notices and timer panels. Each set is worked out on its first use, once ImGui's constants
-- are set.
local NOTICE_FLAGS = { 'NoTitleBar', 'NoResize', 'NoMove', 'NoCollapse', 'NoScrollbar', 'NoSavedSettings', 'NoBackground',
    'NoFocusOnAppearing', 'NoNav', 'NoDocking' }
local PANEL_FLAGS = { 'NoTitleBar', 'NoResize', 'NoMove', 'NoCollapse', 'NoScrollbar', 'NoScrollWithMouse', 'NoSavedSettings',
    'NoBackground', 'NoFocusOnAppearing', 'NoNav', 'NoDocking' }
local flag_sets = {}
local function flags(names)
    local result = flag_sets[names]
    if result then return result end
    result = 0
    local bit = require('bit')
    for _, name in ipairs(names) do result = bit.bor(result, _G['ImGuiWindowFlags_' .. name] or 0) end
    flag_sets[names] = result
    return result
end
-- A window's padding and least size, which never change.
local ZERO, ONE = { 0, 0 }, { 1, 1 }

function hud.cancel_notice_gesture()
    local prior = notice_gesture
    notice_gesture = nil
    if prior and prior.dirty and prior.callbacks.save then prior.callbacks.save() end
end

-- Across at -1 is centered.
local function notice_left(opts, screen, width)
    return opts.notice_x < 0 and math.floor((screen.x - width) / 2) or opts.notice_x
end

-- What draw_notices keeps and refills each frame: the notices up, each shown one with its lines, how many of them it
-- shows and how tall it is, the box they go in and each one's box, their window's place and size, and the look they
-- wrap in, which notice_measure measures with.
local notice_layout = { up = {}, entries = {}, rect = { x = 0, y = 0, width = 0, height = 0 },
    box = { x = 0, y = 0, width = 0, height = 0 }, at = { 0, 0 }, size = { 0, 0 }, look = nil }
local function notice_measure(value)
    local look = notice_layout.look
    return measure(look, value, look.font_size)
end

function hud.draw_notices(view, settings, now, callbacks)
    local imgui = require('imgui')
    callbacks = callbacks or {}
    local notices, entries, opts, s = notice_layout.up, notice_layout.entries, settings.alerts, settings.style
    clear(notices)
    -- Anchors beside the chat log follow it where Vantage can read it.
    elements.chat = layout.chat(view.context)
    if not opts.enabled or opts.muted then hud.cancel_notice_gesture(); return end
    local editing = callbacks.editing == true
    -- Their conditions hide the notices, not the alerts; samples and edit mode show them anyway.
    if not editing and not settings.preview and not conditions.shown('notices') then hud.cancel_notice_gesture(); return end
    for _, notice in ipairs(view.notices or NONE) do
        if notice.visual and notice.ends > now then notices[#notices + 1] = notice end
    end
    local screen, scale = imgui.GetIO().DisplaySize, s.scale
    -- With no notice up, the box keeps its last place. Edit mode places it as one notice would be.
    if #notices == 0 and not editing then hud.cancel_notice_gesture(); resize.keep('Alerts'); return end
    if screen.x <= 0 or screen.y <= 0 then hud.cancel_notice_gesture(); return end
    if #notices == 0 then
        local width = math.min(opts.notice_width * scale, screen.x)
        local height = math.min(opts.notice_height and opts.notice_height > 0 and opts.notice_height * scale or ((s.font_size + 3) + 14) * scale, screen.y)
        local rect = empty_notices
        rect.x, rect.y, rect.width, rect.height = notice_left(opts, screen, width), opts.notice_y, width, height
        elements.place(settings, 'notices', rect, screen.x, screen.y)
        layout.clamp(rect, screen.x, screen.y)
        elements.record('notices', rect)
        resize.keep('Alerts')
        return
    end
    local shift = callbacks.shift and not editing
    if callbacks.shift == nil then shift = imgui.GetIO().KeyShift == true and not editing end
    local mx, my = imgui.GetMousePos()
    local down = imgui.IsMouseDown(ImGuiMouseButton_Left or 0)
    local over_settings = settings.window.open and (not settings.window.peek or resize.grip(settings.window, mx, my))
        and inside(mx, my, settings.window.x, settings.window.y, settings.window.width, settings.window.height)
    if callbacks.settings_blocks_input then over_settings = callbacks.settings_blocks_input(mx, my, shift, (view.context or NONE).chat_open) end
    local movable = shift and not (view.context or NONE).chat_open and not opts.notice_locked and not over_settings
    if notice_gesture and (notice_gesture.settings ~= settings or not movable or not down
        or notice_gesture.sw ~= screen.x or notice_gesture.sh ~= screen.y) then hud.cancel_notice_gesture() end
    if notice_gesture then
        local g = notice_gesture
        g.active_edge = resize.active_edge(g.edge, mx - g.mx, my - g.my, g.active_edge)
        local rect = snap.resize(settings, 'notices', g.rect, g.active_edge, mx - g.mx, my - g.my, { min_width = 240 * scale,
            min_height = 80 * scale, max_width = 900 * scale, max_height = 16000 * scale, screen_width = screen.x, screen_height = screen.y })
        if not g.edge then
            rect.x, rect.y = g.rect.x + mx - g.mx, g.rect.y + my - g.my
            local dx, dy = snap.move(settings, 'notices', rect.x, rect.y, rect.width, rect.height, screen.x, screen.y)
            rect.x, rect.y = rect.x + dx, rect.y + dy
            layout.clamp(rect, screen.x, screen.y)
        end
        local horizontal, vertical = resize.axes(g.active_edge)
        if g.dirty or horizontal and mx ~= g.mx or vertical and my ~= g.my or not g.edge and (mx ~= g.mx or my ~= g.my) then
            local x, y = math.floor(rect.x), math.floor(rect.y)
            local width = horizontal and math.floor(rect.width / scale + 0.5) or opts.notice_width
            local height = vertical and math.floor(rect.height / scale + 0.5) or opts.notice_height
            if x ~= opts.notice_x or y ~= opts.notice_y or width ~= opts.notice_width or height ~= opts.notice_height then
                if not g.dirty and callbacks.changed then callbacks.changed('before', 'Notice layout') end
                opts.notice_x, opts.notice_y, opts.notice_width, opts.notice_height = x, y, width, height
                -- A Shift drag detaches an anchored display.
                if opts.notice_anchor then opts.notice_anchor.to = 'none' end
                g.dirty = true
                if callbacks.changed then callbacks.changed('after') end
            end
        end
    end
    local width = math.min(opts.notice_width * scale, screen.x)
    local x = math.min(notice_left(opts, screen, width), screen.x - width)
    local y = math.max(0, math.min(opts.notice_y, screen.y - 30))
    fonts.push(s.font, s.font_size * scale)
    -- metrics.lines keeps each wrap by its text, its room and a token for how it was measured. The notices' token
    -- carries their name, so they never get a wrap measured another way in the same font.
    local token, count, total = metrics.token(s.font, s.font_size * scale) .. ':notice', 0, 0
    notice_layout.look = s
    for index = math.max(1, #notices - opts.max_notices + 1), #notices do
        local notice = notices[index]
        local content = (notice.estimated and '[Estimated] ' or '') .. (notice.message or '')
        local lines = metrics.lines(content, width - 24 * scale, notice_measure, token)
        local height = math.max(1, #lines) * (s.font_size + 3) * scale + 14 * scale
        count = count + 1
        local entry = entries[count]
        if not entry then
            entry = {}
            entries[count] = entry
        end
        entry.notice, entry.lines, entry.shown, entry.height = notice, lines, #lines, height
        total = total + height + 5 * scale
    end
    -- Notices past Notices shown at once, or past the height, are left out with nothing in their place, the oldest
    -- first: the ones drawn run from first to count. The newest shows the lines that fit when it is too tall alone.
    local fixed = opts.notice_height and opts.notice_height > 0
    local height = math.min(fixed and opts.notice_height * scale or total, screen.y)
    local first = 1
    if total > height then
        local used, room = 0, math.max(1, height)
        first = count + 1
        for index = count, 1, -1 do
            local entry = entries[index]
            if used + entry.height > room then
                if first > count then
                    entry.shown = math.min(math.max(0, math.floor((room - 14 * scale) / ((s.font_size + 3) * scale))), #entry.lines)
                    entry.height, first = room, index
                end
                break
            end
            first, used = index, used + entry.height + 5 * scale
        end
    end
    y = math.max(0, math.min(y, screen.y - height))
    local rect = notice_layout.rect
    rect.x, rect.y, rect.width, rect.height = x, y, width, height
    -- The anchor keeps placing it until a drag moves it, which detaches it.
    if (not notice_gesture or not notice_gesture.dirty) and elements.place(settings, 'notices', rect, screen.x, screen.y) then
        layout.clamp(rect, screen.x, screen.y)
        x, y = rect.x, rect.y
    end
    if notice_gesture then snap.show(settings, 'notices', screen.x, screen.y, rect) end
    resize.occupy('Alerts', rect)
    elements.record('notices', rect)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, ZERO)
    imgui.PushStyleVar(ImGuiStyleVar_WindowMinSize, ONE)
    local at, size = notice_layout.at, notice_layout.size
    at[1], at[2], size[1], size[2] = x, y, width, height
    imgui.SetNextWindowPos(at, ImGuiCond_Always)
    imgui.SetNextWindowSize(size, ImGuiCond_Always)
    local window_flags = flags(NOTICE_FLAGS)
    if not movable then window_flags = require('bit').bor(window_flags, ImGuiWindowFlags_NoInputs or 0) end
    if imgui.Begin('##vantage_notices', true, window_flags) then
        local list, box = imgui.GetWindowDrawList(), notice_layout.box
        elements.opened('notices', list)
        for index = first, count do
            local entry = entries[index]
            local fade = math.min(1, math.max(0, entry.notice.ends - now) / 0.35)
            box.x, box.y, box.width, box.height = x, y, width, entry.height
            if not skin.panel(list, box, s, NONE, s.opacity * fade)
                and not s.minimal and s.background then
                corner[1], corner[2], far[1], far[2] = x, y, x + width, y + entry.height
                list:AddRectFilled(corner, far, theme.u32(skin.fallback_background(s), s.opacity * fade), s.rounding)
            end
            if not s.minimal and s.background then
                corner[1], corner[2], far[1], far[2] = x, y, x + 3 * scale, y + entry.height
                list:AddRectFilled(corner, far, theme.u32(s.warning_color, fade), s.rounding)
            end
            for i = 1, entry.shown do
                clipped_text(list, x + 11 * scale, y + 7 * scale + (i - 1) * (s.font_size + 3) * scale, entry.lines[i],
                    s.text_color, s.font_size * scale, width - 20 * scale, s.text_shadow, s)
            end
            y = y + entry.height + 5 * scale
        end
        if movable then
            imgui.SetCursorPos(ZERO)
            imgui.InvisibleButton('##notice_layout', size)
            local grip
            if notice_gesture then grip = notice_gesture.edge
            elseif imgui.IsItemHovered() then grip = resize.grip(rect, mx, my) end
            resize.hint(list, rect, theme.u32(s.accent_color), grip, 'Alerts', s)
            if imgui.IsItemHovered() then
                local edge = grip
                resize.cursor(imgui, edge)
                if not notice_gesture and imgui.IsMouseClicked(ImGuiMouseButton_Left or 0) then
                    -- The drag starts from where the box is now, in a table of its own, as the box is refilled each frame.
                    notice_gesture = { settings = settings, callbacks = callbacks, mx = mx, my = my, edge = edge, sw = screen.x, sh = screen.y,
                        rect = { x = rect.x, y = rect.y, width = rect.width, height = rect.height } }
                end
            -- The pointer can run ahead of the notices mid-drag; the cursor stays until the drag ends.
            elseif notice_gesture and imgui.IsItemActive() then resize.cursor(imgui, notice_gesture.edge) end
        elseif shift and not (view.context or NONE).chat_open and opts.notice_locked and not over_settings then
            resize.locked(list, rect, s, 'Alerts')
        end
    end
    imgui.End()
    imgui.PopStyleVar(2)
    fonts.pop()
end

-- The fields a row showed when its panel last drew it, for the copy command: each field once, and whether it starts a
-- line. nil for a row the panel didn't draw.
local function drawn_fields(rect, row)
    local rows, lines = rect.rows, rect.row_lines
    if row.key == nil or not rows or not lines then return nil end
    for index = math.min(rect.painted or 0, #rows), 1, -1 do
        if rows[index].key == row.key then return visible_entries(lines[index]) end
    end
end

function hud.copy_text(view, settings, panel_id, details, now, layout_override, resolved)
    now = now or view.now or 0
    if now == 0 then for _, row in ipairs(view.rows or {}) do if row.deadline and row.remaining then now = row.deadline - row.remaining; break end end end
    if not resolved and settings.preview then view = hud.sample(now, settings.recast_tints) end
    local result = {}
    local filtering = effect_filter_context(view, settings)
    for _, key in ipairs(defaults.panel_order) do
        local p = settings.panels[key]
        if (not panel_id and defaults.panel_enabled(settings, key)) or panel_id == key then
            local rows = hud.filter_rows(view, p, key, settings, filtering)
            if #rows > 0 then
                result[#result + 1] = p.title ~= '' and p.title or defaults.panel_names[key]
                local geometry = layout_override or last_layout
                local visible = geometry and geometry.settings == settings and geometry.rectangles[key]
                local count = math.min(#rows, visible and visible.shown or p.max_rows)
                local shown = p
                if p.mode == 'text' then shown = defaults.copy(p); text_only(shown) end
                for index = 1, count do
                    local entries = hud.entries(rows[index], shown, settings.style, now)
                    local displayed = visible and drawn_fields(visible, rows[index])
                    if displayed then
                        local by_id, filtered = {}, {}
                        for _, entry in ipairs(entries) do by_id[entry.id] = entry end
                        for _, field in ipairs(displayed) do
                            local entry = by_id[field.id]
                            if entry then entry.newline = field.newline; filtered[#filtered + 1] = entry end
                        end
                        entries = filtered
                    end
                    result[#result + 1] = details and hud.details(rows[index], now, p)
                        or fields.text(entries, p.separator)
                end
            end
        end
    end
    return table.concat(result, '\n')
end

local function cancel_panel_gesture()
    local prior = gesture
    gesture, hover_key, hover_at = nil, nil, nil
    if prior and prior.dirty and prior.callbacks.save then prior.callbacks.save() end
end

function hud.cancel_gesture()
    cancel_panel_gesture()
    require('ui.cooldown_list').cancel_gesture()
    require('ui.roll_display').cancel_gesture()
    require('ui.pet_display').cancel_gesture()
    require('ui.ready_pulse').cancel_gesture()
end

-- The party cooldown list, the Phantom Roll and pet displays and the ready pulses go over the panels, with the panels'
-- rules for moving. row_spots are where the panels drew each recast row, or none while the panels aren't drawn;
-- panel_hovered is a panel row whose details show instead of theirs.
local NO_SPOTS = {}
local function draw_overlays(view, settings, now, callbacks, can_gesture, over_settings, mx, my, down, screen, hover, row_spots, panel_hovered)
    moving.shift, moving.over_settings, moving.mx, moving.my, moving.down = can_gesture, over_settings, mx, my, down
    moving.screen_width, moving.screen_height, moving.hover = screen.x, screen.y, hover
    -- In edit mode each display shows its box, empty or hidden by When to show, and edit mode moves it.
    moving.editing = callbacks.editing == true
    local list_row = require('ui.cooldown_list').draw(view, settings, now, callbacks, moving)
    local roll = require('ui.roll_display').draw(view, settings, now, callbacks, moving)
    local pet_part = require('ui.pet_display').draw(view, settings, now, callbacks, moving)
    require('ui.ready_pulse').draw(view.pulses, settings, now, callbacks, moving, row_spots, spot_frame)
    if (list_row or roll or pet_part) and not panel_hovered then
        local imgui = require('imgui')
        imgui.BeginTooltip()
        imgui.PushTextWrapPos(360)
        imgui.TextUnformatted(list_row and require('core.party_cooldowns').details(list_row, now)
            or roll and require('core.rolls').details(roll, now) or require('ui.pet_display').details(pet_part, now))
        imgui.PopTextWrapPos()
        imgui.EndTooltip()
    end
end

-- What hud.draw keeps and refills each frame. By panel: its rows and the list they go in, its working copy, its place
-- (the copy command reads the places through last_layout), and its window's place, size and names. Then the filters,
-- the pointer and the samples.
local drawing = { rows = {}, lists = {}, panels = {}, rects = {}, windows = {}, filtering = {}, mouse = { x = 0, y = 0 },
    sample = nil }
last_layout = { settings = nil, rectangles = drawing.rects }
local function panel_window(key)
    local window = drawing.windows[key]
    if not window then
        window = { at = { 0, 0 }, size = { 0, 0 }, name = '##vantage_' .. key, button = '##move_' .. key }
        drawing.windows[key] = window
    end
    return window
end
local sample_view, fill_sample

-- Works out each panel's rows, working copy and place for this frame, then places the anchored ones. A second call in a
-- frame keeps the rows the first one found.
local function place_panels(view, settings, now, context, screen, filtering, editing, can_gesture)
    local s = settings.style
    for _, key in ipairs(defaults.panel_order) do
        local p = settings.panels[key]
        -- A panel When to show hides isn't drawn, unless samples or edit mode show it.
        if defaults.panel_enabled(settings, key) and (editing or settings.preview or conditions.shown(key)) then
            local rows = drawing.rows[key]
            if not rows then
                local list = drawing.lists[key]
                if not list then
                    list = {}
                    drawing.lists[key] = list
                end
                rows = hud.filter_rows(view, p, key, settings, filtering, list)
                drawing.rows[key] = rows
            end
            if #rows > 0 or p.empty == 'show' or settings.preview or can_gesture and not p.locked or editing then
                drawing.panels[key] = effective_panel(key, p, s, rows, now, context, screen.y)
                drawing.rects[key] = panel_rect(key, drawing.panels[key], s, rows, now, screen.x, screen.y)
            end
        end
    end
    layout.resolve(drawing.panels, drawing.rects, context, screen.x, screen.y, settings)
end

function hud.draw(view, settings, now, callbacks)
    local imgui = require('imgui')
    local interaction_now = now
    callbacks = callbacks or {}
    local context, s = view.context or {}, settings.style
    hud.draw_notices(view, settings, now, callbacks)
    -- The party cooldowns and the ready pulses are live whatever the panels sample.
    local live = view
    if settings.preview then
        -- The samples are made once, and their times refilled each frame.
        drawing.sample = drawing.sample or sample_view()
        view = fill_sample(drawing.sample, now, settings.recast_tints)
    end
    local screen = imgui.GetIO().DisplaySize
    if screen.x <= 0 or screen.y <= 0 then hud.cancel_gesture(); return end
    local shift = callbacks.shift
    if shift == nil then shift = imgui.GetIO().KeyShift == true end
    local editing = callbacks.editing == true
    -- Edit mode moves every display itself, so the panels' own Shift drags wait.
    local can_gesture = shift and not context.chat_open and not editing
    local mx, my = imgui.GetMousePos()
    local over_settings = settings.window.open and (not (settings.window.peek and can_gesture) or resize.grip(settings.window, mx, my))
        and inside(mx, my, settings.window.x, settings.window.y, settings.window.width, settings.window.height)
    if callbacks.settings_blocks_input then over_settings = callbacks.settings_blocks_input(mx, my, shift, context.chat_open) end
    local down = imgui.IsMouseDown(ImGuiMouseButton_Left or 0)
    -- A row's details show as a panel's do: with Show details when I point at a timer on, not over the settings, typing,
    -- Shift or a press.
    local hover = s.hover and not over_settings and not context.chat_open and not shift and not down and not editing
    -- Paused panels, or panels their own rules hide, don't take the party cooldown list or the screen spot's pulses
    -- with them, as they don't take the alert notices. Pulses on rows wait for the rows.
    -- Edit mode shows them while typing, so they can be placed.
    if not settings.enabled or (settings.visibility.hide_typing and context.chat_open and not editing) or not settings.preview and ((settings.visibility.hide_events and context.in_event)
        or (settings.visibility.hide_map and context.map) or (settings.visibility.hide_ui and context.hidden)) then
        cancel_panel_gesture()
        draw_overlays(live, settings, interaction_now, callbacks, can_gesture, over_settings, mx, my, down, screen, hover, NO_SPOTS, nil)
        return
    end
    if gesture and (gesture.settings ~= settings or not down or not can_gesture or over_settings or settings.panels[gesture.key].locked or not defaults.panel_enabled(settings, gesture.key)
        or gesture.sw ~= screen.x or gesture.sh ~= screen.y) then
        hud.cancel_gesture()
    end
    fonts.push(s.font, s.font_size * s.scale)
    layout_frame = layout_frame + 1
    clear(drawing.rows)
    clear(drawing.panels)
    clear(drawing.rects)
    local filtering = effect_filter_context(view, settings, callbacks.effect_filters, drawing.filtering)
    place_panels(view, settings, now, context, screen, filtering, editing, can_gesture)
    local horizontal, vertical = resize.axes(gesture and gesture.resize)
    if gesture and (gesture.dirty or horizontal and mx ~= gesture.mx or vertical and my ~= gesture.my
        or not gesture.resize and (mx ~= gesture.mx or my ~= gesture.my)) then
        local p = settings.panels[gesture.key]
        if not gesture.dirty and callbacks.changed then callbacks.changed('before', 'Timer panel layout') end
        local rect
        gesture.active_edge = resize.active_edge(gesture.resize, mx - gesture.mx, my - gesture.my, gesture.active_edge)
        if gesture.resize then
            rect = snap.resize(settings, gesture.key, gesture, gesture.active_edge, mx - gesture.mx, my - gesture.my,
                { min_width = gesture.min_width, min_height = gesture.min_height or 80, max_width = 1400, max_height = 16000, screen_width = screen.x, screen_height = screen.y })
        else
            rect = { x = gesture.x + mx - gesture.mx, y = gesture.y + my - gesture.my, width = gesture.width, height = gesture.height }
            local dx, dy = snap.move(settings, gesture.key, rect.x, rect.y, rect.width, rect.height, screen.x, screen.y)
            rect.x, rect.y = rect.x + dx, rect.y + dy
        end
        layout.clamp(rect, screen.x, screen.y)
        local before = { p.x, p.y, p.width, p.height_limit, p.wrap, p.auto_width, p.auto_height, p.anchor and p.anchor.to }
        if p.anchor then p.anchor.to = 'none' end
        p.x, p.y = math.floor(rect.x), math.floor(rect.y)
        if gesture.resize then
            local horizontal, vertical = resize.axes(gesture.active_edge)
            p.wrap = true
            if horizontal then p.width, p.auto_width = math.floor(rect.width), false end
            if vertical then p.height_limit, p.auto_height = math.floor(rect.height), false end
        end
        -- Holding still mid-drag is not an edit.
        local after = { p.x, p.y, p.width, p.height_limit, p.wrap, p.auto_width, p.auto_height, p.anchor and p.anchor.to }
        local moved = false
        for index = 1, 8 do if before[index] ~= after[index] then moved = true end end
        if moved and callbacks.changed then callbacks.changed('after') end
        gesture.dirty = true
        place_panels(view, settings, now, context, screen, filtering, editing, can_gesture)
    end
    -- While a panel ticked for Grid mode is dragged the grid shows, with the line it snapped to where the panel ended
    -- on it.
    if gesture then snap.show(settings, gesture.key, screen.x, screen.y, drawing.rects[gesture.key]) end
    last_layout.settings = settings
    local hovered, hovered_panel
    local pulses = settings.ready_pulse
    spot_frame, recording = spot_frame + 1, type(pulses) == 'table' and pulses.enabled and pulses.spot == 'row'
    -- Sample panels go over an open settings window (resize.sample_list), outside edit mode.
    local samples_over = settings.preview and settings.window.open and not editing
    for _, key in ipairs(defaults.panel_order) do
        local p, rect = settings.panels[key], drawing.rects[key]
        local label = elements.label(key)
        -- A panel on with nothing to show keeps its last place, so the party's strips don't grow into it.
        if rect then resize.occupy(label, rect); elements.record(key, rect) elseif defaults.panel_enabled(settings, key) then resize.keep(label) end
        -- Keep empty anchors in the layout even when Minimal hides them.
        local visible = rect and (not s.minimal or #drawing.rows[key] > 0 or can_gesture and not p.locked)
        if visible then
            local movable = can_gesture and not p.locked and not over_settings
            local window_flags = flags(PANEL_FLAGS)
            if not movable then window_flags = require('bit').bor(window_flags, ImGuiWindowFlags_NoInputs or 0) end
            local outline = own_outline(drawing.panels[key], s)
            local window = panel_window(key)
            imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, ZERO)
            imgui.PushStyleVar(ImGuiStyleVar_WindowMinSize, ONE)
            if outline then imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0) end
            window.at[1], window.at[2], window.size[1], window.size[2] = rect.x, rect.y, rect.width, rect.height
            imgui.SetNextWindowPos(window.at, ImGuiCond_Always)
            imgui.SetNextWindowSize(window.size, ImGuiCond_Always)
            if imgui.Begin(window.name, true, window_flags) then
                elements.opened(key, imgui.GetWindowDrawList())
                local list, on_top = resize.sample_list(imgui, samples_over, rect, mx, my, drawing.panels[key].mode == 'icons')
                local mouse
                if hover then
                    mouse = drawing.mouse
                    mouse.x, mouse.y = mx, my
                end
                local row = paint(view, settings, key, drawing.rows[key], rect, now, mouse, drawing.panels[key], outline, list)
                if row then hovered, hovered_panel = row, p end
                -- Icon panels have no heading to say Sample, so a previewed one wears a tag.
                if settings.preview and drawing.panels[key].mode == 'icons' then
                    resize.sample(list, rect, s, true)
                end
                if not movable and can_gesture and p.locked and not over_settings then
                    resize.locked(list, rect, s, label)
                end
                if movable then
                    imgui.SetCursorPos(ZERO)
                    imgui.InvisibleButton(window.button, window.size)
                    if imgui.IsItemHovered() then
                        corner[1], corner[2], far[1], far[2] = rect.x, rect.y, rect.x + rect.width, rect.y + rect.height
                        list:AddRect(corner, far, theme.u32(s.accent_color), 3, 0, 2)
                        if imgui.IsMouseClicked(ImGuiMouseButton_Left or 0) and not gesture then
                            gesture = { key = key, settings = settings, callbacks = callbacks, sw = screen.x, sh = screen.y,
                                mx = mx, my = my, x = rect.x, y = rect.y, width = rect.width, height = rect.height, min_width = rect.min_width,min_height=rect.min_height,
                                resize = resize.grip(rect, mx, my) }
                        end
                    end
                    local grip
                    if gesture and gesture.key == key then grip = gesture.resize
                    elseif not gesture and imgui.IsItemHovered() then grip = resize.grip(rect, mx, my) end
                    resize.hint(list, rect, theme.u32(s.accent_color), grip, label, s)
                    -- The cursor stays on a held drag, also when the pointer runs ahead of the panel.
                    if imgui.IsItemHovered() or gesture and gesture.key == key and imgui.IsItemActive() then resize.cursor(imgui, grip) end
                end
                if on_top then list:PopClipRect() end
            end
            imgui.End()
            imgui.PopStyleVar(outline and 3 or 2)
        end
    end
    recording = false
    draw_overlays(live, settings, interaction_now, callbacks, can_gesture, over_settings, mx, my, down, screen, hover, spots, hovered)
    if hovered then
        if hover_key ~= hovered.key then hover_key, hover_at = hovered.key, interaction_now end
        if interaction_now - (hover_at or interaction_now) >= 0.35 then
            imgui.BeginTooltip()
            imgui.PushTextWrapPos(360)
            imgui.TextUnformatted(hud.details(hovered, now, hovered_panel))
            imgui.PopTextWrapPos()
            imgui.EndTooltip()
        end
    else hover_key, hover_at = nil, nil end
    fonts.pop()
end

-- The samples' rows: effect, name, kind, scope, entity, entity name, duration, status, source and whether the full
-- duration shows. fill_sample works out each one's times from now. The party member's Divine Seal is from a job
-- ability, so Only effects from job abilities leaves one to see.
local SAMPLE_ROWS = {
    { 33, 'Haste', 'buff', 'self', 1001, 'You', 180, 'server', 'Party member', true },
    { 41, 'Shell', 'buff', 'self', 1001, 'You', 82, 'server', 'You', true },
    { 40, 'Protect', 'buff', 'self', 1001, 'You', 900, 'server', nil, false },
    { 214, 'March', 'buff', 'self', 1001, 'You', 120, 'server', nil, false },
    { 214, 'March', 'buff', 'self', 1001, 'You', 92, 'server', nil, false },
    { 251, 'Food', 'buff', 'self', 1001, 'You', 1800, 'server', nil, false },
    { 4, 'Paralysis', 'debuff', 'self', 1001, 'You', 28, 'server', nil, true },
    { 13, 'Slow', 'debuff', 'self', 1001, 'You', nil, 'unknown', nil, false },
    { 2, 'Sleep', 'debuff', 'enemy', 16781313, 'Training Crab', 35, 'estimated', 'You', true },
    { 134, 'Dia', 'debuff', 'enemy', 16781313, 'Training Crab', 60, 'estimated', 'You', true },
    { 42, 'Regen', 'buff', 'party', 1002, 'Party member', nil, 'unknown', 'You', false },
    { 3, 'Poison', 'debuff', 'party', 1002, 'Party member', 45, 'server', nil, true },
    { 10004, 'Cure IV', 'spell', 'recast', 1001, 'You', 20, 'server', 'You', true },
    { 10057, 'Haste', 'spell', 'recast', 1001, 'You', 15, 'server', 'You', true },
    { 20005, 'Provoke', 'ability', 'recast', 1001, 'You', 30, 'server', 'You', true },
    { 45762, 'Empress Band', 'item', 'recast', 1001, 'You', 300, 'server', 'You', true },
    { 78, 'Divine Seal', 'buff', 'party', 1002, 'Party member', 60, 'estimated', 'Party member', true },
}
-- What a sample recast row takes from its action's picture.
local PREVIEW_ICON_KEYS = { 'spell_id', 'ability_id', 'item_id', 'list_icon_hq', 'list_icon_nq', 'list_icon_id', 'ability_element' }

-- The samples' view and rows, without their times.
sample_view = function()
    local context = { sample = true, id = 1001, name = 'You', job = 5, job_name = 'RDM', valid = true, combat = true,
        target = { id = 16781313, name = 'Training Crab', kind = 'enemy' },
        party = { { id = 1002, name = 'Party member', slot = 1, group = 1, scope = 'party', valid = true } },
        entities = { [16781313] = { id = 16781313, name = 'Training Crab', kind = 'enemy' } } }
    local rows = {}
    for index, spec in ipairs(SAMPLE_ROWS) do
        local effect, name, kind, scope, entity, entity_name, duration, status, source, total = unpack(spec, 1, 10)
        local row = { key = 'sample_' .. (index - 1), instance = index, effect = effect, name = name, kind = kind, group = catalog.get(effect).group,
            scope = scope, entity_id = entity, entity_name = entity_name, status = status, present = scope == 'self' or scope == 'party' or nil,
            total = total and duration or nil, source_name = source, mine = source == 'You' }
        if scope == 'recast' then
            row.domain, row.group, row.present = 'recast', kind .. '_recasts', true
            row.recast_id = effect - (kind == 'spell' and 10000 or kind == 'ability' and 20000 or 30000)
        end
        rows[index] = row
    end
    local recipients = effect_filters.recipients(context, { valid = true, id = context.id, members = {
        { id = context.id, name = context.name, job = context.job, slot = 0, group = 1, scope = 'self', available = true },
        { id = 1002, name = 'Party member', job = 3, slot = 1, group = 1, scope = 'party', available = true },
    } })
    return { now = 0, valid = true, self_known = true, context = context, rows = rows,
        subjects = context.entities, effect_recipients = recipients }
end

-- The samples' times from now, each timer starting over on its own cycle within two minutes, and the recast pictures.
-- tints: settings.recast_tints, so a sample recast row is marked only while its tint is on, as a live row is; with none
-- given, each tint's row is marked.
fill_sample = function(view, now, tints)
    local cycle = now - math.floor(now / 120) * 120
    local source = require('core.recasts')
    view.now = now
    for index, spec in ipairs(SAMPLE_ROWS) do
        local row, duration, total = view.rows[index], spec[7], spec[10]
        local left = duration and math.max(1, duration - cycle % math.max(2, duration)) or nil
        row.deadline, row.remaining = left and now + left, left
        row.start, row.observed_at = total and now - (duration - left) or nil, now - 8
        if row.domain == 'recast' and source.preview_icon then
            local metadata = source.preview_icon(row.kind, row.kind == 'ability' and 547 or row.recast_id)
            for _, key in ipairs(PREVIEW_ICON_KEYS) do row[key] = metadata and metadata[key] or nil end
        end
    end
    -- Each recast tint shows, as its switch and color say (core/recast_tints.lua): Cure IV costs more MP than you have,
    -- and a Silence and an Amnesia lock Haste and Provoke for a while.
    local cure, haste, provoke = view.rows[13], view.rows[14], view.rows[15]
    local every = type(tints) ~= 'table'
    cure.tint_mp = (every or tints.mp) and true or nil
    if every or tints.spell_lock then haste.locked, haste.lock_deadline = true, now + 45 - cycle % 45
    else haste.locked, haste.lock_deadline = nil, nil end
    if every or tints.ability_lock then provoke.locked, provoke.lock_deadline = true, now + 20 - cycle % 20
    else provoke.locked, provoke.lock_deadline = nil, nil end
    return view
end

function hud.sample(now, tints)
    return fill_sample(sample_view(), now, tints)
end

return hud
