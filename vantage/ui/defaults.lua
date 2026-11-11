local theme = require('ui.theme')
local defaults = {}

defaults.panel_order = { 'self_buffs', 'self_debuffs', 'target', 'party', 'watch', 'spell_recasts', 'ability_recasts', 'item_recasts', 'recasts' }
defaults.recast_panels = { spell_recasts = 'spell', ability_recasts = 'ability', item_recasts = 'item', recasts = 'all' }
local separate_recasts, combined_recasts = { 'spell_recasts', 'ability_recasts', 'item_recasts' }, { 'recasts' }
function defaults.recast_panel_order(settings)
    return settings.recast_display == 'combined' and combined_recasts or separate_recasts
end
function defaults.panel_enabled(settings, id)
    local p = settings.panels[id]
    if not p or not p.enabled then return false end
    if id == 'recasts' then return settings.recast_display == 'combined' end
    return not defaults.recast_panels[id] or settings.recast_display ~= 'combined'
end
defaults.panel_names = { self_buffs = 'Self buffs', self_debuffs = 'Self debuffs', target = 'Target timers', party = 'Party members\' timers',
    watch = 'Watched enemy timers', spell_recasts = 'Spell recasts', ability_recasts = 'Ability recasts', item_recasts = 'Item recasts', recasts = 'Recasts' }
defaults.field_ids = { 'name', 'target', 'source', 'elapsed', 'total', 'time' }
-- Panel box choices. Shared follows the shared Background and Border.
defaults.panel_boxes = { 'shared', 'both', 'background', 'border', 'none' }
defaults.countdown_keys = { 'countdown_bold', 'countdown_shadow', 'countdown_outline', 'countdown_outline_color' }
-- The light of what you can take off, the color the overhead icons' light starts with too, and the panels that have it.
defaults.dispel_color = { 1, 0.82, 0.25, 1 }
defaults.lit_panels = { target = true, watch = true, self_debuffs = true, party = true }

-- Party timers and watched enemies start as bars, which name whose effect each row is.
local function panel(id, x, y, enabled)
    local bars = defaults.recast_panels[id] or id == 'party' or id == 'watch'
    local result = { enabled = enabled, x = x, y = y, width = 300, locked = true, mode = bars and 'bars' or 'icons',
        sort = defaults.recast_panels[id] and 'remaining' or 'longest', direction = 'drain',
        stack_direction = bars and 'vertical' or 'horizontal', growth = 'right', item_width = 280,
        max_rows = 32, height_limit = 700, show_icon = true, show_name = true, show_time = true, show_target = id == 'party' or id == 'watch',
        show_source = false, show_elapsed = false, show_total = false, mine_only = false, filter = '',
        include = {}, exclude = {}, order = {}, pinned = {}, groups = {}, members = {}, title = defaults.panel_names[id], labels = {},
        empty = 'hide', group_by = 'none', show_heading = true, box = 'shared', warning_seconds = 10, horizon = 300,
        show_fill = true, show_text = true, bar_style = defaults.recast_panels[id] and 'rail' or 'full', fill_direction = 'right',
        row_height = 0, bar_thickness = defaults.recast_panels[id] and 8 or 4, gradient = false, warning_enabled = true, warning_mark = false,
        recast_categories = id == 'recasts' and { spell = true, ability = true, item = true } or nil,
        colors = {}, effect_colors = {}, field_order = { 'name', 'target', 'source', 'elapsed', 'total', 'time' },
        field_labels = {}, field_colors = {}, field_priority = {}, field_alignments = {},
        field_dividers = {}, field_newlines = {}, label_position = 'before', label_separator = ' ', separator = '  ',
        alignment = 'left', priority_overflow = false,
        known_only = false, auto_width = false, auto_height = true, min_width = 160, max_width = 700,
        dock_match_width = false, wrap = false,
        icon_countdown_position = 'below', icon_countdown_size = 0, icon_countdown_gap = 0,
        countdown_bold = false, countdown_shadow = true,
        countdown_outline = not defaults.recast_panels[id], countdown_outline_color = { 0, 0, 0, 1 } }
    if not defaults.recast_panels[id] then result.blink_icons, result.blink_seconds = true, 15 end
    -- What you can take off now lights up as over heads: mob buffs on the target and watched enemy panels, debuffs on
    -- the self debuffs and party panels. The light is off at first, though the overhead icons start with theirs on;
    -- turned on, it has its glow.
    if defaults.lit_panels[id] then
        result.dispel_light, result.dispel_glow, result.dispel_color = false, true, defaults.copy(defaults.dispel_color)
    end
    -- Watched enemies can list the enemies you debuff as well as the ones you watch.
    if id == 'watch' then result.list_debuffed = false end
    -- Party members' timers can show only what job abilities put on.
    if id == 'party' then result.abilities_only = false end
    return result
end

function defaults.rule(id)
    return { id = id or 'rule_1', name = 'New alert', enabled = true, domain = 'status', event = 'remaining', effect = 0, scope = 'self',
        entity_id = 0, thresholds = { 30, 10 }, unit = 'seconds', visual = true, chat = false, sound = '',
        emphasis = true, combat = 'any', jobs = {}, cooldown = 10, repeat_seconds = 0, duration = 4,
        volume = -1, flash = false, flash_color = { 1, 0.86, 0.45, 0.8 }, flash_seconds = 4 }
end

function defaults.make()
    local result = {
        party_ui = require('ui.party_defaults').make(),
        effect_filters = require('core.effect_filters').make(),
        overhead = require('ui.overhead_defaults').make(),
        durations = require('core.durations').make(),
        recast_tints = require('core.recast_tints').make(),
        ready_pulse = require('core.ready_pulse').make(),
        party_cooldowns = require('core.party_cooldowns').make(),
        rolls = require('core.rolls').make(),
        pet = require('core.pet').make(),
        edit_mode = require('core.anchors').make_edit(),
        enabled = true, recast_display = 'separate', window = { open = false, x = 100, y = 80, width = 960, height = 680, tab = 'Home',
            sections = {}, peek = true },
        preview = false, replace_game_buffs = false,
        shared_layout = false, shared_scope = 'placement', job_profiles = {}, active_profile = '',
        visibility = { hide_events = true, hide_map = true, hide_ui = true, hide_typing = false },
        style = { theme = 'Phoenix', window_type = 1, gauge_art = 'Original FFXI', icon_art = 'Client', recast_icon_art = 'Original FFXI', recast_icon_source = 'effect', font = 'Agave', font_size = 16, scale = 1, opacity = 0.92, background = true, minimal = false,
            rounding = 5, border = true, bar_height = 25, gap = 4, icon_size = 28, title_size = 15,
            text_shadow = true, hover = true,
            status_time_color = true, text_outline = false,
            outline_color = { 0, 0, 0, 0.8 } },
        panels = { self_buffs = panel('self_buffs', 40, 120, true), self_debuffs = panel('self_debuffs', 355, 120, true),
            target = panel('target', 670, 120, true), party = panel('party', 40, 420, false), watch = panel('watch', 355, 420, false),
            spell_recasts = panel('spell_recasts', 670, 420, false), ability_recasts = panel('ability_recasts', 985, 420, false),
            item_recasts = panel('item_recasts', 985, 120, false), recasts = panel('recasts', 670, 420, true) },
        watch_ids = {}, alerts = { enabled = true, muted = false, quiet_events = true, volume = 70, rules = {},
            notice_x = 985, notice_y = 10, notice_width = 440, notice_height = 0, notice_locked = true, max_notices = 4 },
        tracking = { stale_seconds = 180, max_entities = 64, follow_subtarget = true },
        diagnostics = { record = false, max_entries = 200 },
        chat_colors = { tag_brackets = 81, tag_word = 6, replies = 106 },
        window_style = { font_size = 17 },
    }
    theme.apply(result, 'Phoenix')
    result.style.label_color = result.style.label_color or { unpack(result.style.text_color) }
    result.style.value_color = result.style.value_color or { unpack(result.style.text_color) }
    result.style.detail_color = result.style.detail_color or { unpack(result.style.unknown_color) }
    result.style.accent_color = result.style.accent_color or { unpack(result.style.title_color) }
    require('ui.appearance').apply(result, 'Original FFXI')
    -- Every display's anchor and When to show (core/anchors.lua, core/conditions.lua).
    require('ui.elements').fill(result)
    return result
end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = copy(entry) end
    return result
end
defaults.copy = copy

-- Whether any display shows samples now, which makes Show samples End samples.
function defaults.samples_showing(settings)
    return settings.preview and defaults.any_timer_on(settings) or settings.party_ui.preview or settings.overhead.preview
        or settings.party_cooldowns.preview or settings.rolls.preview or settings.pet.preview
end

-- Samples only on what is on: a display that is off stays off. Says whether any display took them.
defaults.no_samples = 'Samples show on the timer panels, Party list buffs, Overhead icons, the Party cooldowns list, Phantom Roll and Pet. Turn one on first.'
function defaults.samples_on(settings)
    local any = false
    if defaults.any_timer_on(settings) then settings.preview, any = true, true end
    for _, config in ipairs({ settings.party_ui, settings.overhead, settings.rolls, settings.pet }) do
        if config.enabled then config.preview, any = true, true end
    end
    -- Party cooldown samples show on their list.
    local watch = settings.party_cooldowns
    if watch.enabled and watch.list.enabled then watch.preview, any = true, true end
    return any
end

function defaults.samples_off(settings)
    settings.preview = false
    for _, config in ipairs({ settings.party_ui, settings.overhead, settings.party_cooldowns, settings.rolls, settings.pet }) do config.preview = false end
end

-- Whether Ready pulse plays on recast rows while no recast panel is on to draw any.
function defaults.pulse_has_no_row(settings)
    local pulse = settings.ready_pulse
    if not pulse.enabled or pulse.spot ~= 'row' then return false end
    for _, id in ipairs(defaults.recast_panel_order(settings)) do
        if defaults.panel_enabled(settings, id) then return false end
    end
    return true
end

function defaults.any_timer_on(settings)
    for _, id in ipairs(defaults.panel_order) do
        if settings.enabled and defaults.panel_enabled(settings, id) then return true end
    end
    return false
end

-- Replace the game's buff icons (core/game_buffs.lua): whether the settings ask for it now, and when its tick is on
-- but they don't, a line saying why. The game's row holds your buffs and your debuffs, so both self panels must be on
-- to stand in for it, and samples aren't your effects.
function defaults.game_buffs_replaced(settings)
    if settings.replace_game_buffs ~= true then return false end
    if not settings.enabled or not defaults.panel_enabled(settings, 'self_buffs') or not defaults.panel_enabled(settings, 'self_debuffs') then
        return false, 'This needs Self buffs and Self debuffs on. Until then the game draws its own buff icons.'
    end
    if settings.preview then return false, 'While samples show, the game draws its own buff icons.' end
    return true
end

-- The panel for all recasts shows nothing with no kind ticked, so turning it on ticks them all.
function defaults.ensure_recast_kind(panel)
    local kinds = panel.recast_categories
    if not kinds or kinds.spell or kinds.ability or kinds.item then return end
    kinds.spell, kinds.ability, kinds.item = true, true, true
end

function defaults.copy_countdown(source, target)
    for _, key in ipairs(defaults.countdown_keys) do target[key] = copy(source[key]) end
end

local numbers = require('ui.numbers')
local finite = numbers.finite

-- Saved numbers keep this rounding: whole-number keys round halves up.
local function number(value, low, high, fallback, integer)
    return (integer and numbers.clamp_round or numbers.clamp)(value, low, high, fallback)
end

local function text(value, fallback, length)
    if type(value) ~= 'string' then return fallback end
    return value:gsub('[%c]', ''):gsub('##', ''):sub(1, length or 100)
end

local function fill(value, base)
    if type(value) ~= 'table' then return copy(base) end
    for key, entry in pairs(base) do
        if type(entry) == 'table' then
            value[key] = fill(value[key], entry)
        elseif type(value[key]) ~= type(entry) then
            value[key] = entry
        end
    end
    return value
end

local function choice(value, choices, fallback)
    for _, allowed in ipairs(choices) do if value == allowed then return value end end
    return fallback
end

-- How many ids a panel's list or map keeps, and how many thresholds a rule keeps: far more than anyone picks, and few
-- enough that what reads them every frame stays cheap, whatever a hand edit or an import holds.
local LIST_MOST, THRESHOLDS_MOST = 256, 16
-- Copy Image (66) shows its shadows as icons 444, 445 and 446, and every copy leaves the tracker as 66, so an effect id
-- one of them names reads as 66 too, or it would never match.
local copy_image = { [444] = 66, [445] = 66, [446] = 66 }

-- most keeps the first most ids, and fold, when given, turns an id into the one it stands for.
local function ids(value, maximum, minimum, most, fold)
    local result, seen = {}, {}
    if type(value) ~= 'table' then return result end
    local function add(id)
        if finite(id) and id >= (minimum or 1) and id <= maximum and id == math.floor(id) then
            id = fold and fold[id] or id
            if not seen[id] and #result < (most or math.huge) then result[#result + 1], seen[id] = id, true end
        end
    end
    for _, id in ipairs(value) do
        add(id)
    end
    local mapped = {}
    for key, enabled in pairs(value) do if enabled == true and tonumber(key) then mapped[#mapped + 1] = tonumber(key) end end
    table.sort(mapped)
    for _, id in ipairs(mapped) do add(id) end
    return result
end

-- most keeps the lowest most ids, and fold, when given, turns an id into the one it stands for.
local function selection(value, maximum, minimum, most, fold)
    local result = {}
    if type(value) ~= 'table' then return result end
    local function add(id)
        if finite(id) and id >= (minimum or 1) and id <= maximum and id == math.floor(id) then result[fold and fold[id] or id] = true end
    end
    for key, enabled in pairs(value) do
        if enabled == true then add(tonumber(key)) end
    end
    for _, id in ipairs(value) do add(id) end
    if most then
        local kept = {}
        for id in pairs(result) do kept[#kept + 1] = id end
        table.sort(kept)
        for index = most + 1, #kept do result[kept[index]] = nil end
    end
    return result
end

-- A map by effect id, such as a panel's labels or colors: each id in range, folded as in selection, with its value
-- through tidy, the lowest LIST_MOST of them. A real 66 comes before the icons folded into it, so its value wins.
local function effect_map(value, maximum, fold, tidy)
    local found = {}
    for key, entry in pairs(value) do
        local effect = tonumber(key)
        if finite(effect) and effect >= 0 and effect <= maximum and effect == math.floor(effect) then found[#found + 1] = { effect, entry } end
    end
    table.sort(found, function(a, b) return a[1] < b[1] end)
    local result, count = {}, 0
    for _, item in ipairs(found) do
        local effect = fold and fold[item[1]] or item[1]
        if result[effect] == nil and count < LIST_MOST then result[effect], count = tidy(item[2]), count + 1 end
    end
    return result
end

local function rgba(value, fallback)
    local result = {}
    for i = 1, 4 do result[i] = number(type(value) == 'table' and value[i], 0, 1, fallback[i]) end
    return result
end

local function field_map(value, transform)
    local result = {}
    if type(value) == 'table' then
        for _, key in ipairs(defaults.field_ids) do
            if value[key] ~= nil then result[key] = transform(value[key]) end
        end
    end
    return result
end

local function field_order(value)
    local result, seen = {}, {}
    for _, key in ipairs(type(value) == 'table' and value or {}) do
        if choice(key, defaults.field_ids) and not seen[key] then result[#result + 1], seen[key] = key, true end
    end
    for _, key in ipairs(defaults.field_ids) do if not seen[key] then result[#result + 1] = key end end
    return result
end

function defaults.tidy(settings)
    if type(settings) ~= 'table' or next(settings) == nil then settings = defaults.make() end
    -- These two come before the fill, which would put the default's numbered entries beside a list given as an object
    -- ("1" to "3", from a hand edit or /vg set).
    settings.party_ui = require('ui.party_defaults').tidy(settings.party_ui)
    settings.overhead = require('ui.overhead_defaults').tidy(settings.overhead)
    settings = fill(settings, defaults.make())
    -- A display is a table, a newer Vantage's too. Anything else in the map, from a hand edit or /vg set, goes, as what
    -- reads every display takes each one as a table.
    for id, p in pairs(settings.panels) do if type(p) ~= 'table' then settings.panels[id] = nil end end
    theme.tidy_window(settings)
    settings.recast_display = choice(settings.recast_display, { 'separate', 'combined' }, 'separate')
    settings.effect_filters = require('core.effect_filters').tidy(settings.effect_filters)
    settings.durations = require('core.durations').tidy(settings.durations)
    settings.recast_tints = require('core.recast_tints').tidy(settings.recast_tints)
    settings.ready_pulse = require('core.ready_pulse').tidy(settings.ready_pulse)
    settings.party_cooldowns = require('core.party_cooldowns').tidy(settings.party_cooldowns)
    settings.rolls = require('core.rolls').tidy(settings.rolls)
    settings.pet = require('core.pet').tidy(settings.pet)
    settings.edit_mode = require('core.anchors').tidy_edit(settings.edit_mode, require('ui.elements').movable)
    local s, w = settings.style, settings.window
    s.font = text(s.font, 'Agave', 2048)
    s.theme = choice(s.theme, theme.names, 'Phoenix')
    s.window_type = number(s.window_type, 1, 8, 1, true)
    s.gauge_art = choice(s.gauge_art, { 'Original FFXI', 'XI View' }, 'Original FFXI')
    s.icon_art = choice(s.icon_art, { 'Client', 'Original FFXI', 'XI View' }, 'Original FFXI')
    s.recast_icon_art = choice(s.recast_icon_art, { 'Original FFXI', 'XI View' }, 'Original FFXI')
    s.recast_icon_source = choice(s.recast_icon_source, { 'effect', 'action' }, 'effect')
    for key, range in pairs({ font_size = { 8, 48, 16 }, title_size = { 0, 48, 15 },
        scale = { 0.5, 2.5, 1 }, opacity = { 0.05, 1, 0.92 }, rounding = { 0, 24, 5 }, bar_height = { 18, 64, 25 },
        gap = { 0, 16, 4 }, icon_size = { 12, 64, 28 } }) do s[key] = number(s[key], range[1], range[2], range[3]) end
    s.scale = number(s.scale, 0.5, 2.5, 1)
    s.title_size = number(settings.style.title_size, 0, 48, 15)
    -- Each color is a new list: one given as an object ({"1": ...} from a hand edit, or /vg set) can't keep keys
    -- of both kinds, which no save could write. Its "1" to "4" are the values given; the fill above put the
    -- numbered defaults beside them.
    for key, fallback in pairs(theme.colors(s.theme)) do
        local value, color = s[key], {}
        for i = 1, 4 do color[i] = number(type(value) == 'table' and (value[tostring(i)] or value[i]), 0, 1, fallback[i]) end
        s[key] = color
    end
    for key, range in pairs({ x = { 0, 16000, 100 }, y = { 0, 16000, 80 }, width = { 560, 2400, 960 }, height = { 400, 1800, 680 } }) do
        w[key] = number(w[key], range[1], range[2], range[3])
    end
    w.tab = choice(w.tab, { 'Home', 'Display', 'Durations', 'Profiles', 'Help' }, 'Home')
    for key, value in pairs(w.sections) do if type(key) ~= 'string' or #key > 160 or type(value) ~= 'boolean' then w.sections[key] = nil end end
    for _, id in ipairs(defaults.panel_order) do
        local p = settings.panels[id]
        if not defaults.recast_panels[id] then
            p.blink_icons = p.blink_icons == true
            p.blink_seconds = number(p.blink_seconds, 1, 300, 15, true)
        end
        if defaults.lit_panels[id] then p.dispel_color = rgba(p.dispel_color, defaults.dispel_color) end
        if id == 'watch' then p.list_debuffed = p.list_debuffed == true end
        if id == 'party' then p.abilities_only = p.abilities_only == true end
        if id == 'recasts' then
            for _, kind in ipairs({ 'spell', 'ability', 'item' }) do p.recast_categories[kind] = p.recast_categories[kind] == true end
        end
        -- A recast's id is its kind's base plus its own id, and items start at 30000, so the top one is 30000 + 65534.
        local effect_max = defaults.recast_panels[id] and 95534 or 65534
        p.mode = choice(p.mode, { 'bars', 'expanded', 'icons', 'text' }, defaults.recast_panels[id] and 'bars' or 'icons')
        p.stack_direction = choice(p.stack_direction, { 'horizontal', 'vertical' }, p.mode == 'icons' and 'horizontal' or 'vertical')
        p.growth = choice(p.growth, { 'right', 'left' }, 'right')
        p.sort = choice(p.sort, defaults.recast_panels[id] and { 'remaining', 'name', 'fixed' } or { 'longest', 'oldest', 'remaining', 'name', 'fixed' },
            defaults.recast_panels[id] and 'remaining' or 'longest')
        p.direction = choice(p.direction, { 'drain', 'fill' }, 'drain')
        p.empty = choice(p.empty, { 'hide', 'show' }, 'hide')
        p.box = choice(p.box, defaults.panel_boxes, 'shared')
        p.group_by = choice(p.group_by, { 'none', 'target', 'group' }, 'none')
        p.bar_style = choice(p.bar_style, { 'full', 'rail' }, defaults.recast_panels[id] and 'rail' or 'full')
        p.fill_direction = choice(p.fill_direction, { 'right', 'left' }, 'right')
        p.alignment = choice(p.alignment, { 'left', 'center', 'right' }, 'left')
        p.label_position = choice(p.label_position, { 'before', 'after', 'hidden' }, 'before')
        p.icon_countdown_position = choice(p.icon_countdown_position, { 'below', 'inside' }, 'below')
        p.icon_countdown_size = number(p.icon_countdown_size, 0, 64, 0, true)
        if p.icon_countdown_size > 0 then p.icon_countdown_size = math.max(6, p.icon_countdown_size) end
        p.icon_countdown_gap = number(p.icon_countdown_gap, 0, 16, 0, true)
        p.countdown_outline_color = rgba(p.countdown_outline_color, { 0, 0, 0, 1 })
        for key, range in pairs({ x = { 0, 16000, 40 }, y = { 0, 16000, 120 }, width = { 24, 1400, 300 }, item_width = { 80, 1400, 280 },
            max_rows = { 1, 64, 32 }, height_limit = { 24, 16000, 700 }, warning_seconds = { 0, 300, 10 }, horizon = { 10, 86400, 300 },
            row_height = { 0, 100, 0 }, bar_thickness = { 1, 32, defaults.recast_panels[id] and 8 or 4 }, min_width = { 24, 1400, 160 }, max_width = { 24, 2400, 700 } }) do
            p[key] = number(p[key], range[1], range[2], range[3], true)
        end
        p.max_width = math.max(p.min_width, p.max_width)
        p.field_order = field_order(p.field_order)
        p.field_labels = field_map(p.field_labels, function(v) return text(v, '', 80) end)
        p.field_colors = field_map(p.field_colors, function(v) return rgba(v, s.text_color) end)
        p.field_newlines = field_map(p.field_newlines, function(v) return v == true or nil end)
        p.field_priority = field_map(p.field_priority, function(v) return number(v, 0, 1000, 50, true) end)
        p.field_alignments = field_map(p.field_alignments, function(v) return choice(v, { 'left', 'center', 'right' }) end)
        p.field_dividers = field_map(p.field_dividers, function(v) return text(v, '', 20) end)
        p.separator, p.label_separator = text(p.separator, '  ', 20), text(p.label_separator, ' ', 20)
        local colors = {}
        for _, key in ipairs({ 'background', 'border', 'track', 'title', 'label', 'value', 'detail', 'fill_start', 'fill_end', 'warning' }) do
            if p.colors[key] ~= nil then colors[key] = rgba(p.colors[key], s.text_color) end
        end
        p.colors = colors
        -- A timer panel's effect ids fold Copy Image's icons into 66; a recast panel's ids are recasts, kept as they are.
        local fold = not defaults.recast_panels[id] and copy_image or nil
        p.effect_colors = effect_map(p.effect_colors, effect_max, fold, function(value) return rgba(value, s.buff_color) end)
        p.title, p.filter = text(p.title, defaults.panel_names[id], 80), text(p.filter, '', 80)
        p.include, p.exclude = selection(p.include, effect_max, 0, LIST_MOST, fold), selection(p.exclude, effect_max, 0, LIST_MOST, fold)
        p.pinned = selection(p.pinned, effect_max, 0, LIST_MOST, fold)
        p.members, p.order = selection(p.members, 4294967295, nil, LIST_MOST), ids(p.order, effect_max, 0, LIST_MOST, fold)
        p.labels = effect_map(p.labels, effect_max, fold, function(label) return text(label, '', 80) end)
        for key, enabled in pairs(p.groups) do if type(key) ~= 'string' or enabled ~= true then p.groups[key] = nil end end
    end
    settings.watch_ids = ids(settings.watch_ids, 4294967295)
    local rules, rule_ids = {}, {}
    for i, entry in ipairs(settings.alerts.rules) do
        if type(entry) == 'table' and #rules < 128 then
            local base = defaults.rule('rule_' .. i)
            -- A rule's thresholds are the player's list: fill would pad a short one from the default's two.
            if type(entry.thresholds) == 'table' then base.thresholds = entry.thresholds end
            local r = fill(entry, base)
            r.id = text(r.id, 'rule_' .. i, 80)
            if r.id == '' or rule_ids[r.id] then
                local suffix = 0
                repeat suffix = suffix + 1; r.id = 'rule_' .. i .. '_' .. suffix until not rule_ids[r.id]
            end
            rule_ids[r.id] = true
            r.name = text(r.name, 'Alert', 80)
            -- A blank name would leave the rule nothing to show in its list and notices.
            if not r.name:find('%S') then r.name = 'Alert' end
            r.domain = choice(r.domain, { 'status', 'recast' }, 'status')
            r.event = choice(r.event, r.domain == 'recast' and { 'started', 'ready', 'remaining' } or { 'gain', 'remaining', 'removed', 'missing' }, 'remaining')
            r.scope = choice(r.scope, { 'self', 'party', 'alliance', 'target', 'watch', 'all' }, 'self')
            if r.domain == 'recast' then r.scope = 'self' end
            -- Only My party, Other alliance parties and Anyone can narrow to one member.
            if r.scope == 'self' or r.scope == 'target' or r.scope == 'watch' then r.entity_id = 0 end
            r.unit = choice(r.unit, { 'seconds', 'percent' }, 'seconds')
            r.combat = choice(r.combat, { 'any', 'in', 'out' }, 'any')
            r.effect, r.entity_id = number(r.effect, 0, r.domain == 'recast' and 95534 or 65534, 0, true), number(r.entity_id, 0, 4294967295, 0, true)
            if r.domain == 'status' then r.effect = copy_image[r.effect] or r.effect end
            r.jobs = selection(r.jobs, 18)
            r.thresholds = ids(r.thresholds, r.unit == 'percent' and 100 or 86400, nil, THRESHOLDS_MOST)
            table.sort(r.thresholds, function(a, b) return a > b end)
            if #r.thresholds == 0 then r.thresholds = { 10 } end
            r.cooldown = number(r.cooldown, 0, 3600, 10)
            r.repeat_seconds = number(r.repeat_seconds, 0, 3600, 0)
            r.duration = number(r.duration, 1, 30, 4)
            r.volume = number(r.volume, -1, 100, -1, true)
            r.flash_seconds = number(r.flash_seconds, 0.1, 30, 4)
            r.flash_color = rgba(r.flash_color, s.warning_color)
            r.sound = text(r.sound, '', 160):match('[^\\/]*$') or ''
            if not r.sound:lower():match('%.wav$') and not r.sound:lower():match('%.mp3$') then r.sound = '' end
            rules[#rules + 1] = r
        end
    end
    settings.alerts.rules = rules
    settings.alerts.volume = number(settings.alerts.volume, 0, 100, 70, true)
    for key, range in pairs({ notice_x = { -1, 16000, 985 }, notice_y = { 0, 16000, 10 },
        notice_width = { 240, 900, 440 }, max_notices = { 1, 8, 4 } }) do
        settings.alerts[key] = number(settings.alerts[key], range[1], range[2], range[3], true)
    end
    settings.alerts.notice_height = number(settings.alerts.notice_height, 0, 16000, 0, true)
    if settings.alerts.notice_height > 0 then settings.alerts.notice_height = math.max(80, settings.alerts.notice_height) end
    settings.tracking.stale_seconds = number(settings.tracking.stale_seconds, 15, 1800, 180, true)
    settings.tracking.max_entities = number(settings.tracking.max_entities, 8, 128, 64, true)
    settings.shared_scope = choice(settings.shared_scope, { 'placement', 'presentation' }, 'placement')
    -- The screen size a fresh install or an apply last placed the displays for.
    local placed = settings.placement_screen
    if type(placed) == 'table' then
        local width, height = number(placed.width, 0, 16000, 0, true), number(placed.height, 0, 16000, 0, true)
        settings.placement_screen = width > 0 and height > 0 and { width = width, height = height } or nil
    else
        settings.placement_screen = nil
    end
    settings.diagnostics.max_entries = number(settings.diagnostics.max_entries, 20, 2000, 200, true)
    for key, fallback in pairs({ tag_brackets = 81, tag_word = 6, replies = 106 }) do
        local value = number(settings.chat_colors[key], 1, 255, fallback, true)
        -- A chat color is a byte in the chat text, so 10 and 13, a newline and a return, aren't allowed.
        settings.chat_colors[key] = value ~= 10 and value ~= 13 and value or fallback
    end
    settings.active_profile = text(settings.active_profile, '', 80)
    local job_profiles = {}
    for key, name in pairs(settings.job_profiles) do
        local job = tonumber(key)
        if finite(job) and job >= 1 and job <= 18 and job == math.floor(job) and type(name) == 'string' then
            job_profiles[tostring(job)] = text(name, '', 40)
        end
    end
    settings.job_profiles = job_profiles
    -- The main job these settings were last saved on, for the job links.
    local job = settings.profile_job
    settings.profile_job = finite(job) and job >= 1 and job <= 18 and job == math.floor(job) and job or nil
    require('ui.elements').tidy(settings)
    return settings
end

return defaults
