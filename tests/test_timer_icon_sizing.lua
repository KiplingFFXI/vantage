local defaults, hud, icons = require('ui.defaults'), require('ui.hud'), require('ui.icons')
local settings = defaults.make()
local panel, style = settings.panels.self_buffs, settings.style
panel.stack_direction = 'vertical'
style.icon_size, style.bar_height = 48, 25
for _, mode in ipairs({ 'bars', 'expanded', 'icons' }) do
    panel.mode = mode
    for _, scale in ipairs({ 0.5, 1, 2.5 }) do
        style.scale = scale
        local rect = hud.bounds(panel, style, 1, 1600, 1200)
        assert(rect.icon_width == 48 * scale, 'The selected icon size holds in ' .. mode)
        if mode=='icons' then assert(rect.row_height==48*scale, 'Icons only has no tile padding.')
        else assert(rect.row_height >= 52 * scale, 'The bar row fits the square icon and its vertical padding.') end
    end
end
panel.mode, style.scale = 'bars', 1
local rect = hud.bounds(panel, style, 1, 1600, 1200)
assert(rect.row_height == 52, 'A 48px icon grows the default 25px bar to 52px.')
panel.show_icon = false
rect = hud.bounds(panel, style, 1, 1600, 1200)
assert(rect.icon_width == 0 and rect.row_height == 25, 'Hidden icons leave the compact geometry unchanged.')
panel.show_icon, panel.row_height = true, 80
assert(hud.bounds(panel, style, 1, 1600, 1200).row_height == 80, 'Larger custom rows keep their height.')
panel.row_height = 0
rect = hud.bounds(panel, style, 1, 1600, 1200, 110)
assert(rect.row_height == 110 and rect.icon_width == 48, 'Wrapped text can grow a row without shrinking its chosen icon.')

for key, value in pairs(settings.panels) do value.enabled = key == 'self_buffs' end
panel.width, panel.height_limit = 700, 1100
local view = hud.sample(100)
view.rows = { view.rows[1], view.rows[2] }
icons._set_loader_for_tests(function() return 777 end)
for _, mode in ipairs({ 'bars', 'expanded', 'icons' }) do
    panel.mode = mode
    for _, scale in ipairs({ 0.5, 1, 2.5 }) do
        style.scale = scale
        MOCK.imgui_calls = {}
        hud.draw(view, settings, 100, {})
        local pictures = {}
        for _, call in ipairs(MOCK.imgui_calls) do
            if call[1] == 'draw:AddImage' and call[2] == 777 then pictures[#pictures + 1] = MOCK.drawn[call] end
        end
        assert(#pictures == 2, 'Both timer icons render in ' .. mode)
        for _, call in ipairs(pictures) do
            assert(call[4][1] - call[3][1] == 48 * scale, 'The renderer paints the selected icon width.')
            assert(call[4][2] - call[3][2] == 48 * scale, 'The renderer preserves square icon proportions.')
        end
        if mode ~= 'icons' then assert(pictures[2][3][2] > pictures[1][4][2], 'Adjacent rows do not overlap their icons.') end
    end
end
assert(style.icon_size == 48 and style.bar_height == 25 and panel.row_height == 0, 'Rendering preserves saved size settings.')
assert(#MOCK.font_stack == 0, 'Timer rendering leaves the font stack balanced.')
