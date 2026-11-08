-- The four timer layouts side by side with the same self buffs: bars, expanded bars, icons and text.
local C = require('preview.readme.common');
require('ui.icons').prepare();
local rows = {
    C.row({ effect = 33, name = 'Haste', left = 161, total = 180 }),
    C.row({ effect = 43, name = 'Refresh', left = 41, total = 150 }),
    C.row({ effect = 116, name = 'Phalanx', left = 133, total = 180 }),
    C.row({ effect = 40, name = 'Protect', left = 1460, total = 1800 }),
    C.row({ effect = 41, name = 'Shell', left = 1395, total = 1800 }),
    C.row({ effect = 251, name = 'Food', left = 2580, total = 3600 }),
};
local layouts = { { 'bars', 'Bars', 230 }, { 'expanded', 'Expanded bars', 230 }, { 'icons', 'Icons', 230 }, { 'text', 'Text', 190 } };
local sets, x = {}, 16;
for index, layout in ipairs(layouts) do
    local s = C.settings();
    local p = s.panels.self_buffs;
    p.enabled, p.mode, p.x, p.y, p.width = true, layout[1], x, 40, layout[3];
    p.stack_direction = layout[1] == 'icons' and 'horizontal' or 'vertical';
    p.show_total = layout[1] == 'expanded';
    sets[index] = { settings = s, view = C.view(rows), caption = layout[2], x = x };
    x = x + layout[3] + 16;
end;
return function()
    for index, set in ipairs(sets) do C.caption(index, set.x, 8, set.caption); end;
    C.draw(sets);
end;
