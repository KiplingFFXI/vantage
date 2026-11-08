local defaults, hud = require('ui.defaults'), require('ui.hud')
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function stock()
    local s = defaults.make()
    require('original_skin_fixture')(s)
    return s
end
local function full_bars()
    local s = stock()
    for id in pairs(defaults.recast_panels) do
        local p = s.panels[id]
        p.bar_style, p.bar_thickness = 'full', 4
    end
    return s
end
for id in pairs(defaults.recast_panels) do
    local p = defaults.make().panels[id]
    assert(p.bar_style == 'rail' and p.bar_thickness == 8)
end
local before = full_bars()
before.panels.spell_recasts.x, before.panels.spell_recasts.width = 511, 333
before.panels.spell_recasts.labels[10057] = 'My Haste'
before.panels.spell_recasts.include = {[10057]=true}
local loaded = defaults.tidy(defaults.copy(before))
for id in pairs(defaults.recast_panels) do
    assert(equal(loaded.panels[id], before.panels[id]), 'A load keeps a recast panel as it was saved.')
end
assert(equal(before.style, loaded.style), 'A load retains fonts, native artwork and opacity.')
assert(defaults.tidy(loaded).panels.spell_recasts.bar_style == 'full', 'An explicit full-bar choice persists.')
for _, custom in ipairs({
    {colors={fill_start={.2,.3,.4,1}}}, {effect_colors={[10057]={.2,.3,.4,1}}},
    {field_colors={name={.2,.3,.4,1}}}, {row_height=45},
    {bar_thickness=6}, {gradient=true}, {warning_mark=true},
}) do
    local s = full_bars()
    for k, v in pairs(custom) do s.panels.spell_recasts[k] = v end
    local p = defaults.tidy(s).panels.spell_recasts
    assert(p.bar_style == 'full', 'A load preserves customized recast appearance.')
    for k, v in pairs(custom) do assert(equal(p[k], v)) end
end

-- The same native rail geometry separates captions from the gauge in every timer layout.
local skin, fonts, pictures = require('ui.client_skin'), require('ui.fonts'), require('ui.recast_icons')
local gauges, captions, images = {}, {}, {}
local countdown = require('ui.countdown_text')
local draw_countdown = countdown.draw
countdown.draw = function(list, font, value, x, y, size, ink, options)
    local _, top, _, bottom = countdown.padding(options)
    local height = size + top + bottom
    captions[#captions+1] = {text=value,x=x,y=y,size=height}
    return draw_countdown(list,font,value,x,y,size,ink,options)
end
skin.panel = function() return true end
skin.gauge = function(_, x, y, w, h) gauges[#gauges+1]={x=x,y=y,w=w,h=h}; return true end
fonts.draw = function(_, _, value, x, y, size) captions[#captions+1]={text=value,x=x,y=y,size=size}; return true end
fonts.measure = function(_, text, size) return #text*size*.5 end
fonts.is_bitmap = function() return true end
fonts.failed = function() return false end
pictures.draw = function(_, _, _, x, y, size, opacity) images[#images+1]={x=x,y=y,size=size,opacity=opacity}; return true end
MOCK.screen = {1600,1200}
for _, mode in ipairs({'bars','expanded','icons'}) do
    local settings = defaults.tidy(stock())
    -- The recast tints are off at first; on, the sample rows' lock times are captions that must clear the gauge too.
    settings.recast_tints.mp, settings.recast_tints.spell_lock, settings.recast_tints.ability_lock = true, true, true
    settings.style.icon_size, settings.style.font_size, settings.style.bar_height = 32, 16, 36
    settings.style.status_time_color = false
    for key, panel in pairs(settings.panels) do panel.enabled = key == 'spell_recasts' end
    local p = settings.panels.spell_recasts
    p.mode, p.x, p.y, p.width, p.show_heading, p.wrap = mode, 10, 10, 500, false, true
    p.show_total = mode == 'expanded'
    gauges, captions, images = {}, {}, {}
    hud.draw(hud.sample(100), settings, 100, {})
    assert(#gauges==(mode=='icons' and 0 or 2) and #images==2 and #captions>=(mode=='icons' and 2 or 4),
        'Icons only keeps recast pictures and countdowns; bar layouts retain native rails.')
    for _, gauge in ipairs(gauges) do assert(gauge.h == 8, 'Native recast gauges retain the status rail height.') end
    for _, caption in ipairs(captions) do
        for _, gauge in ipairs(gauges) do
            assert(caption.y + caption.size <= gauge.y or caption.y >= gauge.y + gauge.h,
                'Recast captions never overlap the bright native gauge in '..mode..' mode.')
        end
    end
    for _, picture in ipairs(images) do assert(picture.size == 32 and picture.opacity == 1, 'Native icon size and brightness are retained.') end
end
