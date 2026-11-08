-- The stock look a fixture starts from: the skin, its font and art at their native sizes, and every panel on plain
-- rails.
local recommended = { font = 'Original FFXI', gauge_art = 'Original FFXI', icon_art = 'Original FFXI', recast_icon_art = 'Original FFXI',
    font_size = 16, title_size = 16, scale = 1, opacity = 1, rounding = 0,
    bar_height = 36, gap = 4, icon_size = 32, background = true, border = true, text_shadow = false, text_outline = false,
    status_time_color = false };

return function(settings)
    require('ui.theme').apply(settings, 'Original FFXI');
    for key, value in pairs(recommended) do settings.style[key] = value; end;
    for _, key in ipairs(require('ui.defaults').panel_order) do
        local panel = settings.panels[key];
        panel.bar_style, panel.bar_thickness, panel.gradient, panel.warning_mark = 'rail', 8, false, false;
        panel.colors, panel.effect_colors, panel.field_colors = {}, {}, {};
        panel.row_height = 0;
    end;
end;
