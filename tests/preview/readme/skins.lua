-- The same Self buffs panel in each skin. The status icons stay the stock client's, which is what a skin's Client
-- icons are on a game without other icon packs.
local C = require('preview.readme.common');
local appearance, theme = require('ui.appearance'), require('ui.theme');
require('ui.icons').prepare();
local rows = {
    C.row({ effect = 33, name = 'Haste', left = 161, total = 180 }),
    C.row({ effect = 43, name = 'Refresh', left = 41, total = 150 }),
    C.row({ effect = 40, name = 'Protect', left = 1460, total = 1800 }),
};
local sets = {};
for index, name in ipairs(theme.names) do
    local s = C.settings();
    appearance.apply(s, name);
    s.style.icon_art = 'Original FFXI';
    local p = s.panels.self_buffs;
    local column, line = (index - 1) % 3, math.floor((index - 1) / 3);
    p.enabled, p.mode, p.stack_direction = true, 'bars', 'vertical';
    p.x, p.y, p.width = 16 + column * 246, 36 + line * 186, 230;
    sets[index] = { settings = s, view = C.view(rows), caption = name, x = p.x, y = p.y - 28 };
end;
return function()
    for index, set in ipairs(sets) do C.caption(index, set.x, set.y, set.caption); end;
    C.draw(sets);
end;
