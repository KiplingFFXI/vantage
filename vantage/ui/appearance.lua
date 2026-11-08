local theme = require('ui.theme')
local copy, equal = require('core.store').copy, require('core.customization').equal
local appearance = { names = {} }
local known = {}

for _, name in ipairs(theme.names) do
    appearance.names[#appearance.names + 1], known[name] = name, true
end
appearance.names[#appearance.names + 1], known['XI View'] = 'XI View', true

local function preset(name)
    local native = name == 'Original FFXI' or name == 'XI View'
    return { theme = native and 'Original FFXI' or name, native = native, minimal = name == 'Minimal',
        font = native and name or 'Agave', gauge_art = name == 'XI View' and name or 'Original FFXI',
        icon_art = native and name or 'Client', recast_icon_art = name == 'XI View' and name or 'Original FFXI' }
end

-- The parts of XI View the last look given to uses_xiview draws with, which its warmup steps make: art (its font file's
-- textures, for the font and the gauges), face (its bitmap font), icons (its status icons) and actions (its action
-- icons). A part no step makes is made on its first use, as for a look without XI View.
local xiview_parts = {}

-- Whether a saved look draws anything with XI View: the main font or artwork, or the party list buffs' own icons while
-- they are on. Which parts it draws with is kept for the warmup steps.
function appearance.uses_xiview(settings)
    local style = type(settings) == 'table' and type(settings.style) == 'table' and settings.style or {}
    -- A display that is off draws nothing.
    local party = type(settings) == 'table' and type(settings.party_ui) == 'table' and settings.party_ui or {}
    local party_icons = party.enabled == true and type(party.style) == 'table' and party.style.icon_art == 'XI View'
    xiview_parts = { art = style.font == 'XI View' or style.gauge_art == 'XI View', face = style.font == 'XI View',
        icons = style.icon_art == 'XI View' or party_icons, actions = style.recast_icon_art == 'XI View' }
    return xiview_parts.art or xiview_parts.icons or xiview_parts.actions
end

-- What XI View draws with as warmup steps: its art read and uploaded, its face, its status icons and its action icons
-- one file at a time, each only for a part the look uses (uses_xiview). Each makes what it needs from the stock art
-- first.
function appearance.warmup_steps()
    local assets = require('ui.client_assets')
    local client_fonts = require('ui.client_fonts')
    local actions = require('ui.action_icons')
    local steps = {}
    local function gate(step, part)
        local run = step.run
        step.run = function() if xiview_parts[part] then run() end end
        steps[#steps + 1] = step
    end
    for _, step in ipairs(assets.xiview_steps()) do gate(step, 'art') end
    gate(assets.step('fonts.face.xiview', function() return client_fonts.current('XI View') end, function()
        client_fonts.prepare()
        client_fonts.available('XI View')
    end), 'face')
    gate(assets.step('icons.pack.xiview', function() return assets.icons_loaded('xiview') end, function()
        require('ui.icons').prepare()
        assets.icon_status('xiview')
    end), 'icons')
    local stock = actions.warmup_steps('Original FFXI')
    for _, step in ipairs(actions.warmup_steps('XI View')) do
        local run = step.run
        step.run = function()
            for _, needed in ipairs(stock) do needed.run() end
            run()
        end
        gate(step, 'actions')
    end
    return steps
end

-- Reads, parses and uploads what XI View draws with for the parts the last look given to uses_xiview uses: its font,
-- its status icons and its action icons, so that look never waits for one of them while it plays.
function appearance.preload_xiview()
    for _, step in ipairs(appearance.warmup_steps()) do step.run() end
end

local function window_type(value)
    if type(value) ~= 'number' or value ~= value or math.abs(value) == math.huge then return 1 end
    return math.floor(math.max(1, math.min(8, value)))
end

local function frame(style, choice, kind)
    style.theme, style.window_type = choice.theme, kind
    style.minimal, style.background, style.border = choice.minimal, not choice.minimal, not choice.minimal
end

local function match(style, choice, recast)
    style.font, style.gauge_art, style.icon_art = choice.font, choice.gauge_art, choice.icon_art
    if recast then style.recast_icon_art = choice.recast_icon_art end
end

-- Overhead icons take a skin's look as the other displays do: their countdown and light colors start again.
local overhead_fresh = require('ui.overhead_defaults').make()
function appearance.overhead_look(config)
    if type(config) ~= 'table' then return end
    config.countdown_color, config.dispel_color = copy(overhead_fresh.countdown_color), copy(overhead_fresh.dispel_color)
end

-- The Phantom Roll and pet displays the same way: their own colors start again.
local element_fresh = { rolls = require('core.rolls').make(), pet = require('core.pet').make() }
appearance.element_colors = { rolls = { 'lucky_color', 'unlucky_color', 'missed_color' }, pet = { 'hp_color', 'mp_color', 'tp_color' } }
function appearance.element_look(settings)
    for key, colors in pairs(appearance.element_colors) do
        local config = settings[key]
        if type(config) == 'table' then
            for _, color in ipairs(colors) do config[color] = copy(element_fresh[key][color]) end
        end
    end
end

-- The caller owns Undo and saving. Applying a look never changes the layout or tracking choices.
function appearance.apply(settings, name, options)
    if type(settings) ~= 'table' or type(settings.style) ~= 'table' or not known[name] then return false end
    options = type(options) == 'table' and options or {}
    local choice, matching = preset(name), options.matching ~= false
    local kind = window_type(options.window_type or settings.style.window_type)
    theme.apply(settings, choice.theme)
    frame(settings.style, choice, kind)
    if matching then match(settings.style, choice, true) end
    for _, panel in pairs(settings.panels or {}) do
        if type(panel) == 'table' then
            -- A color set for one effect or one row part stays: only the panel's own colors follow the skin.
            panel.colors = {}
            if choice.native then panel.bar_style, panel.bar_thickness, panel.gradient = 'rail', 8, false end
        end
    end

    -- The party list buffs wear the timer panels' look. With matching fonts and artwork they take the skin's icons.
    local party = settings.party_ui
    if matching and type(party) == 'table' and type(party.style) == 'table' then party.style.icon_art = choice.icon_art end
    appearance.overhead_look(settings.overhead)
    appearance.element_look(settings)
    return true
end

function appearance.candidate(settings)
    local style = type(settings) == 'table' and settings.style or nil
    if type(style) ~= 'table' then return 'Phoenix' end
    if style.theme == 'Original FFXI' and style.font == 'XI View' and style.gauge_art == 'XI View'
        and style.icon_art == 'XI View' and style.recast_icon_art == 'XI View' then return 'XI View' end
    return known[style.theme] and style.theme or 'Phoenix'
end

local function same_color(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end
    for i = 1, 4 do
        if type(a[i]) ~= 'number' or a[i] ~= a[i] or math.abs(a[i] - b[i]) > 0.002 then return false end
    end
    return true
end

local function overrides(colors)
    return type(colors) == 'table' and next(colors) ~= nil
end

-- The party list buffs' own icons: their own choice, or the timer panels' where they have none.
local function party_icons(settings)
    local party = type(settings.party_ui) == 'table' and settings.party_ui or {}
    local own = type(party.style) == 'table' and party.style.icon_art or nil
    if own ~= nil then return own end
    return type(settings.style) == 'table' and settings.style.icon_art or nil
end

local summary_cache
local panel_fields = { 'colors', 'bar_style', 'bar_thickness', 'gradient' }
-- The overhead icons' own look: their countdown and light colors.
local function overhead_look(settings)
    local config = type(settings.overhead) == 'table' and settings.overhead or {}
    return { countdown_color = copy(config.countdown_color), dispel_color = copy(config.dispel_color) }
end
-- And the Phantom Roll and pet displays': their colors.
local function element_summary(settings, key)
    local config, out = type(settings[key]) == 'table' and settings[key] or {}, {}
    for _, color in ipairs(appearance.element_colors[key]) do out[color] = copy(config[color]) end
    return out
end
local function same_summary(settings, previous)
    if not previous or not equal(settings.style, previous.style) then return false end
    local overhead, saved = type(settings.overhead) == 'table' and settings.overhead or {}, previous.overhead
    if not equal(overhead.countdown_color, saved.countdown_color) or not equal(overhead.dispel_color, saved.dispel_color) then return false end
    for key in pairs(appearance.element_colors) do
        if not equal(element_summary(settings, key), previous.elements[key]) then return false end
    end
    if party_icons(settings) ~= previous.party_icons then return false end
    local count = 0
    for id, panel in pairs(settings.panels or {}) do
        if type(panel) == 'table' then
            count = count + 1
            local saved = previous.panels[id]
            if not saved then return false end
            for _, key in ipairs(panel_fields) do if not equal(panel[key], saved[key]) then return false end end
        end
    end
    if count ~= previous.panel_count then return false end
    return true
end
local function summary_snapshot(settings)
    local out = { style=copy(settings.style), panels={}, panel_count=0 }
    out.party_icons = party_icons(settings)
    for id, panel in pairs(settings.panels or {}) do
        if type(panel) == 'table' then
            out.panels[id], out.panel_count = {}, out.panel_count + 1
            for _, key in ipairs(panel_fields) do out.panels[id][key] = copy(panel[key]) end
        end
    end
    out.overhead = overhead_look(settings)
    out.elements = {}
    for key in pairs(appearance.element_colors) do out.elements[key] = element_summary(settings, key) end
    return out
end

function appearance.describe(settings)
    local mixed, differences = 'Mixed / customized', {}
    if type(settings) ~= 'table' or type(settings.style) ~= 'table' then return mixed, differences end
    if summary_cache and summary_cache.owner == settings and same_summary(settings, summary_cache.source) then
        return summary_cache.name, summary_cache.differences
    end
    -- look names the display for appearance.replaced.
    local function differs(label, page, panel, look)
        differences[#differences + 1] = { label=label, page=page, panel=panel, look=look }
    end
    local name = appearance.candidate(settings)
    local choice, style = preset(name), settings.style
    if theme.current(settings) ~= choice.theme or style.font ~= choice.font or style.gauge_art ~= choice.gauge_art
        or style.icon_art ~= choice.icon_art or style.recast_icon_art ~= choice.recast_icon_art
        or (style.minimal == true) ~= choice.minimal or (style.background ~= false) == choice.minimal
        or (style.border ~= false) == choice.minimal then differs('Shared timer appearance', 'Home', nil, 'style') end
    for id, panel in pairs(settings.panels or {}) do
        if type(panel) == 'table' then
            if overrides(panel.colors) or choice.native and (panel.bar_style ~= 'rail' or panel.bar_thickness ~= 8 or panel.gradient) then
                local defaults = require('ui.defaults')
                differs(defaults.panel_names[id] or id, 'Display', id, 'panel')
            end
        end
    end
    if type(settings.party_ui) == 'table' and party_icons(settings) ~= choice.icon_art then
        differs('Party buff icons', 'Display', 'party_ui', 'party_ui')
    end
    local overhead = type(settings.overhead) == 'table' and overhead_look(settings)
    if overhead and (not same_color(overhead.countdown_color, overhead_fresh.countdown_color)
        or not same_color(overhead.dispel_color, overhead_fresh.dispel_color)) then
        differs('Overhead icons', 'Display', 'overhead', 'overhead')
    end
    for _, entry in ipairs({ { 'rolls', 'Phantom Roll', 'Display', 'rolls' }, { 'pet', 'Pet display', 'Display', 'pet' } }) do
        local own = type(settings[entry[1]]) == 'table' and element_summary(settings, entry[1])
        local fresh, changed = element_fresh[entry[1]], false
        for _, color in ipairs(own and appearance.element_colors[entry[1]] or {}) do
            if not same_color(own[color], fresh[color]) then changed = true end
        end
        if changed then differs(entry[2], entry[3], entry[4], entry[1]) end
    end
    local current = #differences > 0 and mixed or name
    summary_cache = { owner=settings, source=summary_snapshot(settings), name=current, differences=differences }
    return current, differences
end

-- What describe compares on one display, read the same way from either settings table.
local function own(value)
    if type(value) == 'table' and next(value) == nil then return nil end
    return value
end
local function display_look(settings, entry)
    local style = settings.style
    if entry.look == 'style' then
        return { theme=theme.current(settings), font=style.font, gauge_art=style.gauge_art, icon_art=style.icon_art,
            recast_icon_art=style.recast_icon_art, minimal=style.minimal == true, background=style.background ~= false,
            border=style.border ~= false }
    elseif entry.look == 'panel' then
        local panel, out = settings.panels and settings.panels[entry.panel] or {}, {}
        for _, key in ipairs(panel_fields) do out[key] = own(panel[key]) end
        return out
    elseif entry.look == 'party_ui' then
        return { icon_art = party_icons(settings) }
    elseif entry.look == 'overhead' then
        return overhead_look(settings)
    elseif appearance.element_colors[entry.look] then
        return element_summary(settings, entry.look)
    end
end
-- Saved colors round a little, as describe allows.
local function close(a, b)
    if type(a) == 'number' and type(b) == 'number' then return math.abs(a - b) <= 0.002 end
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    for key, value in pairs(a) do if not close(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

-- The displays with their own look that a change would draw differently, so a question names only what it replaces.
-- Without the changed settings, every display with its own look.
function appearance.replaced(settings, result)
    local _, differences = appearance.describe(settings)
    if type(result) ~= 'table' or type(result.style) ~= 'table' then return differences end
    local out = {}
    for _, entry in ipairs(differences) do
        if not close(display_look(settings, entry), display_look(result, entry)) then out[#out + 1] = entry end
    end
    return out
end

if VANTAGE_TEST_MODE then
    function appearance.current(settings)
        return (appearance.describe(settings))
    end
end

return appearance
