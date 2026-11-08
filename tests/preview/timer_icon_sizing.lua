local defaults, hud = require('ui.defaults'), require('ui.hud')
local imgui = require('imgui')
require('ui.icons').prepare()
local sets = {}
for index, mode in ipairs({ 'bars', 'expanded', 'icons' }) do
    local settings = defaults.make()
    settings.style.icon_size, settings.style.bar_height = 48, 25
    settings.style.icon_art = 'Original FFXI'
    settings.style.font_size = 16
    for key, panel in pairs(settings.panels) do panel.enabled = key == 'self_buffs' end
    local panel = settings.panels.self_buffs
    panel.x, panel.y, panel.width, panel.height_limit = 20 + (index - 1) * 370, 20, 350, 600
    panel.mode = mode
    panel.title = mode .. ': 48px icons / 25px rows'
    sets[#sets + 1] = settings
end
local view, original = hud.sample(100), imgui.Begin
view.rows = { view.rows[1], view.rows[2] }
return function()
    for index, settings in ipairs(sets) do
        imgui.Begin = function(name, ...) return original(name .. '_icon_size_' .. index, ...) end
        local ok, err = pcall(hud.draw, view, settings, 100, {})
        imgui.Begin = original
        if not ok then error(err) end
    end
end
