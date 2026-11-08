-- The countdown text styles, one to a panel of self buff icons: bold, shadow and outline.
local C = require('preview.readme.common');
require('ui.icons').prepare();
local rows = {
    C.row({ effect = 33, name = 'Haste', left = 161, total = 180 }),
    C.row({ effect = 43, name = 'Refresh', left = 41, total = 150 }),
    C.row({ effect = 116, name = 'Phalanx', left = 25, total = 180 }),
    C.row({ effect = 40, name = 'Protect', left = 1460, total = 1800 }),
    C.row({ effect = 41, name = 'Shell', left = 1395, total = 1800 }),
};
local styles = { { 'Bold', true, false, false }, { 'Shadow', false, true, false }, { 'Outline', false, false, true } };
local sets = {};
for index, style in ipairs(styles) do
    local s = C.settings();
    local p = s.panels.self_buffs;
    p.enabled, p.mode, p.stack_direction = true, 'icons', 'horizontal';
    p.x, p.y, p.width = 16 + (index - 1) * 260, 40, 240;
    -- Big icons with the countdown over the picture, so the shadow and the outline show against it.
    s.style.icon_size, p.icon_countdown_position, p.icon_countdown_size = 40, 'inside', 20;
    p.countdown_bold, p.countdown_shadow, p.countdown_outline = style[2], style[3], style[4];
    sets[index] = { settings = s, view = C.view(rows), caption = style[1], x = p.x };
end;
return function()
    for index, set in ipairs(sets) do C.caption(index, set.x, 8, set.caption); end;
    C.draw(sets);
end;
