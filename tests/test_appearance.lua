local defaults, theme = require('ui.defaults'), require('ui.theme')
local party_theme = require('ui.party_theme')
local appearance = require('ui.appearance')

local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function seed()
    local s = defaults.make()
    s.enabled, s.preview, s.recast_display = false, true, 'combined'
    s.style.font, s.style.font_size, s.style.scale = 'Global custom', 29, 1.4
    s.style.gauge_art, s.style.icon_art, s.style.recast_icon_art = 'XI View', 'XI View', 'XI View'
    s.style.minimal, s.style.background, s.style.border, s.style.window_type = true, false, false, 6
    s.window.x, s.window.y, s.window.width, s.window.height = 701, 309, 1444, 999
    s.window_style.font_size = 31
    for index, key in ipairs(defaults.panel_order) do
        local p = s.panels[key]
        p.x, p.y, p.width, p.height_limit, p.row_height = index * 111, index * 23, 412, 777, 46
        p.enabled, p.locked, p.bar_style, p.bar_thickness, p.gradient = index % 2 == 0, false, 'full', 11, true
        p.mode, p.max_rows, p.wrap, p.show_icon, p.show_name = 'icons', 29, true, false, false
        p.include, p.labels, p.field_order = { 33, 40 }, { ['33'] = 'My label' }, { 'time', 'name' }
        p.colors, p.field_colors, p.effect_colors = { background = { 1, 0, 0, 1 } }, { time = { 0, 1, 0, 1 } }, { ['33'] = { 0, 0, 1, 1 } }
    end
    local p = s.party_ui
    p.enabled, p.locked = true, true
    p.native.width = 589
    p.name_display = 'job'
    p.effects.max, p.effects.icon_size = 23, 41
    p.effects.include = { 33 }
    p.style.opacity, p.style.icon_art = 0.6, 'XI View'
    for _, group in ipairs(p.groups) do
        group.native_detached = true
        group.detached_width, group.detached_height, group.native_x, group.native_y = 521, 199, -17, 44
    end
    s.alerts.notice_x, s.alerts.notice_y, s.alerts.notice_width, s.alerts.notice_height = 503, 207, 901, 600
    s.alerts.rules = { defaults.rule('custom') }
    s.alerts.rules[1].flash_color, s.alerts.rules[1].sound = { 0.2, 0.3, 0.4, 0.5 }, 'Custom.wav'
    return s
end

local function nonappearance(s, native, matching)
    local out = defaults.copy(s)
    local function strip(style, global)
        for _, key in ipairs({ 'theme', 'window_type', 'minimal', 'background', 'border' }) do style[key] = nil end
        if matching then
            for _, key in ipairs({ 'font', 'gauge_art', 'icon_art' }) do style[key] = nil end
            if global then style.recast_icon_art = nil end
        end
        if global then
            for key in pairs(theme.colors('Phoenix')) do style[key] = nil end
        else
            style.colors = nil
            for _, key in ipairs(party_theme.color_keys) do style[key .. '_color'] = nil end
        end
    end
    strip(out.style, true)
    for _, p in pairs(out.panels) do
        -- A color set for one effect or one row part stays through a skin pick.
        p.colors = nil
        if native then p.bar_style, p.bar_thickness, p.gradient = nil, nil, nil end
    end
    strip(out.party_ui.style)
    return out
end

assert(#appearance.names == #theme.names + 1 and appearance.names[#appearance.names] == 'XI View')
for _, name in ipairs(appearance.names) do
    local s = seed()
    local before, native = defaults.copy(s), name == 'Original FFXI' or name == 'XI View'
    assert(appearance.apply(s, name), 'An explicit preset is recognized: ' .. name)
    assert(appearance.current(s) == name, 'Every surface agrees after applying ' .. name)
    assert(appearance.candidate(s) == name, 'The selection remains usable for ' .. name)
    assert(equal(nonappearance(before, native, true), nonappearance(s, native, true)), 'The preset preserves every nonappearance setting: ' .. name)
    -- The party list buffs wear the timer panels' look, window type and all.
    assert(s.style.window_type == 6 and theme.window(s).window_type == 6 and party_theme.party(s.party_ui, s.style).window_type == 6,
        'The existing global window type is shared')
    assert(s.style.font_size == 29 and s.style.scale == 1.4 and s.window_style.font_size == 31,
        'Matching fonts preserves the chosen text sizes and scale')
    assert(s.panels.self_buffs.colors ~= s.panels.recasts.colors, 'Cleared overrides remain independent tables')
    local once = defaults.copy(s)
    assert(appearance.apply(s, name) and equal(s, once), 'Reapplying a preset is idempotent')
end

for kind = 1, 8 do
    local s = seed()
    assert(appearance.apply(s, 'Original FFXI', { window_type = kind }))
    assert(appearance.current(s) == 'Original FFXI' and theme.window(s).window_type == kind)
    local look = party_theme.party(s.party_ui, s.style)
    assert(look.theme == 'Original FFXI' and look.window_type == kind and look.font == 'Original FFXI', 'The party list buffs wear the selected native skin')
    assert(equal(theme.window(s).text, theme.window_defaults({ style = { theme = 'Original FFXI', window_type = kind } }).text), 'Menu text uses the selected native skin palette')
end

for _, name in ipairs({ 'Original FFXI', 'XI View', 'Mint', 'Minimal' }) do
    local s, native = seed(), name == 'Original FFXI' or name == 'XI View'
    local before = defaults.copy(s)
    assert(appearance.apply(s, name, { matching = false, window_type = 7 }))
    assert(equal(nonappearance(before, native, false), nonappearance(s, native, false)), 'Optional matching preserves every independently chosen font and artwork: ' .. name)
    assert(s.style.font == 'Global custom')
    assert(appearance.current(s) == 'Mixed / customized', 'Independent font choices remain truthfully labeled')
end

local s = seed()
local before = defaults.copy(s)
assert(not appearance.apply(s, 'Invalid') and equal(s, before), 'Invalid names never partially apply')
assert(not appearance.apply({}, 'Phoenix') and not appearance.apply(nil, 'Phoenix'))
assert(appearance.candidate(nil) == 'Phoenix' and appearance.current(nil) == 'Mixed / customized')
local changes = {
    function(v) v.panels.self_buffs.colors.fill_start = { 1, 0, 0, 1 } end,
    function(v) v.style.minimal = true end,
    function(v) v.style.background_color = { 1, 0, 0, 1 } end,
    -- The party list buffs' own icons.
    function(v) v.party_ui.style.icon_art = 'Client' end,
}
for _, change in ipairs(changes) do
    assert(appearance.apply(s, 'Original FFXI'))
    change(s)
    local untouched = defaults.copy(s)
    assert(appearance.current(s) == 'Mixed / customized', 'A local override cannot masquerade as one uniform preset')
    assert(equal(s, untouched), 'Reading the appearance summary never modifies settings')
end

-- A skin pick keeps colors set for one effect and row text colors, so they don't make the look read as changed.
for _, change in ipairs({
    function(v) v.panels.recasts.effect_colors['10057'] = { 1, 0, 0, 1 } end,
    function(v) v.panels.ability_recasts.field_colors.time = { 1, 0, 0, 1 } end,
}) do
    assert(appearance.apply(s, 'Original FFXI'))
    change(s)
    assert(appearance.current(s) == 'Original FFXI', 'What a skin pick keeps is not a look of its own')
end
assert(appearance.apply(s, 'Mint'))
assert(s.panels.recasts.effect_colors['10057'][1] == 1 and s.panels.ability_recasts.field_colors.time[1] == 1,
    'A skin pick leaves them as they are')

appearance.apply(s, 'Minimal')
defaults.tidy(s)
assert(appearance.current(s) == 'Minimal', 'Minimal survives settings normalization')
local look = party_theme.party(s.party_ui, s.style)
assert(look.minimal and not look.background and not look.border, 'The party list buffs are frameless with the rest')
local profiles = require('core.profiles')
local saved = profiles.capture(s)
assert(saved.style.minimal, 'Named profiles retain the frameless preset')
local full = profiles.capture_layout(s, 'presentation')
assert(full.presentation.style.minimal, 'Presentation sharing includes the selected appearance')
local placement = profiles.capture_layout(s, 'placement')
assert(placement.party_ui.style == nil, 'Placement sharing does not impose an appearance')
local fresh = defaults.make()
assert(not party_theme.party(fresh.party_ui, fresh.style).minimal, 'Existing defaults remain framed')

-- Every group of the party list buffs wears the skin applied to the timer panels; only the party's icons and opacity
-- are its own.
s = defaults.make()
s.party_ui.style.opacity = 0.6
assert(appearance.apply(s, 'Original FFXI', { window_type = 4 }))
assert(appearance.current(s) == 'Original FFXI')
look = party_theme.party(s.party_ui, s.style)
assert(look.theme == 'Original FFXI' and look.window_type == 4 and look.font == 'Original FFXI' and look.icon_art == 'Original FFXI'
    and look.opacity == 0.6, 'The party list buffs wear the applied skin with their own opacity')
