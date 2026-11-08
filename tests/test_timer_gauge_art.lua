local stock = { id = 'stock', width = 64, height = 64 }
local modified = { id = 'xiview', width = 64, height = 64 }
local pieces = {}
for _, name in ipairs({ 'newtex', 'corner', 'hfr1', 'vfr1' }) do
    local size = name == 'newtex' and 128 or 32
    pieces[name] = { id = name, width = size, height = size }
end
package.loaded['ui.client_assets'] = {
    texture = function(kind, name)
        if kind == 'window' then return pieces[name] end
        if name == 'gauge' then
            if kind == 'xiview_font' then return modified end
            if kind == 'original_font' then return stock end
        end
    end,
    status = function() return { available = true } end,
    icon_status = function() return { available = true } end,
    icon_texture = function() return nil end,
}
local defaults = require('ui.defaults')
local skin = require('ui.client_skin')
local original_skin = require('original_skin_fixture')
local settings = defaults.make()
original_skin(settings)
local panel = settings.panels.self_buffs
local images = {}
local list = { AddImage = function(_, id, first, last, uv1, uv2)
    images[#images + 1] = { id = id, first = first, last = last, uv1 = uv1, uv2 = uv2 }
end }
local function paint(fraction)
    images = {}
    return skin.gauge(list, 10, 20, 108, 8, fraction, settings.style, panel, { 1, 1, 1, 1 })
end
assert(paint(.25) and images[4].id == 'stock')
settings.style.gauge_art = 'XI View'
assert(paint(.25) and #images == 4)
for _, image in ipairs(images) do assert(image.id == 'xiview') end
assert(images[4].last[1] - images[4].first[1] == 25,
    'Changing art must preserve the duration fraction and geometry.')
assert(paint(nil) and #images == 3, 'Unknown time must not acquire a fill from the new artwork.')
assert(skin.reason(1, 'XI View') == nil and skin.gauge_reason(settings.style) == nil)
settings.style.font = 'Tahoma Bold'
assert(paint(.5) and images[1].id == 'xiview', 'Gauge selection is independent of font selection.')
modified.height = 32
assert(paint(.5) and images[1].id == 'stock', 'Unexpected atlas geometry must use the stock fallback.')
assert(skin.gauge_reason(settings.style):find('Stock client gauges', 1, true))
modified.height, modified.width = 64, 128
assert(paint(.5) and images[1].id == 'stock')
modified = nil
assert(paint(.5) and images[1].id == 'stock')
stock.height = 32
assert(not paint(.5) and #images == 0, 'An invalid stock atlas must leave regular rendering available.')
assert(skin.gauge_reason(settings.style):find('Regular bars', 1, true))
assert(skin.reason(1, 'XI View') == 'The client gauge artwork is unavailable.')
modified = { id = 'xiview', width = 64, height = 64 }
assert(paint(.5) and images[1].id == 'xiview' and skin.reason(1, 'XI View') == nil,
    'A valid XI View atlas does not depend on stock gauge availability.')
stock.height = 64
panel.gradient = true
assert(not paint(.5) and #images == 0, 'Custom gradients keep their existing rendering path.')
panel.gradient = false
settings.style.theme = 'Classic FFXI'
assert(not paint(.5), 'The Classic FFXI palette must retain its existing bars.')
original_skin(settings)
assert(settings.style.gauge_art == 'Original FFXI' and settings.style.font == 'Original FFXI')
local customized = defaults.copy(settings)
customized.style.gauge_art = nil
customized.style.font, customized.style.opacity = 'Tahoma Bold', .63
customized = defaults.tidy(customized)
assert(customized.style.gauge_art == 'Original FFXI' and customized.style.font == 'Tahoma Bold' and customized.style.opacity == .63,
    'Tidying adds stock artwork without replacing saved customization.')
customized.style.gauge_art = 'invalid'
assert(defaults.tidy(customized).style.gauge_art == 'Original FFXI')
settings.style.gauge_art = 'XI View'
assert(defaults.tidy(defaults.copy(settings)).style.gauge_art == 'XI View')

local window = require('ui.settings_window')
local hud = require('ui.hud')
local imgui = require('imgui')
settings.window.open, settings.window.tab = true, 'Home'
settings.window.sections['Home/More look'] = true
settings.style.gauge_art, settings.style.font = 'Original FFXI', 'Tahoma Bold'
local events = {}
local cb = { now = function() return 100 end,
    changed = function(phase) events[#events + 1] = phase end,
    save = function() events[#events + 1] = 'save'; return true end }
imgui.BeginCombo = function(label) return label == '##main_gauge_art' end
MOCK.clicks['XI View##XI View'] = true
window.draw(settings, hud.sample(100), cb)
assert(settings.style.gauge_art == 'XI View' and settings.style.font == 'Tahoma Bold')
assert(events[1] == 'before' and events[2] == 'after' and events[3] == 'save',
    'The new selector must use the same undo transaction and save path as existing controls.')
assert(#MOCK.font_stack == 0 and #MOCK.commands == 0)
