-- Target timers with Light up buffs you can remove on, for a Red Mage who has learned Dispel: the crab's own buffs
-- light up, as bars and as icons.
local C = require('preview.readme.common');
require('ui.icons').prepare();
C.can_dispel();
local rows = {
    C.row({ effect = 134, name = 'Dia', kind = 'debuff', scope = 'enemy', left = 94, total = 120, status = 'estimated', source = 'You', mine = true }),
    C.row({ effect = 13, name = 'Slow', kind = 'debuff', scope = 'enemy', left = 142, total = 180, status = 'estimated', source = 'You', mine = true }),
    C.row({ effect = 4, name = 'Paralysis', kind = 'debuff', scope = 'enemy', left = 51, total = 120, status = 'estimated', source = 'You', mine = true }),
    C.row({ effect = 93, name = 'Defense Boost', kind = 'buff', scope = 'enemy' }),
    C.row({ effect = 191, name = 'Magic Def. Boost', kind = 'buff', scope = 'enemy' }),
};
local sets = {};
for index, layout in ipairs({ { 'bars', 16, 300 }, { 'icons', 332, 220 } }) do
    local s = C.settings();
    local p = s.panels.target;
    p.enabled, p.mode, p.x, p.y, p.width, p.dispel_light = true, layout[1], layout[2], 16, layout[3], true;
    p.stack_direction = layout[1] == 'icons' and 'horizontal' or 'vertical';
    p.show_source = layout[1] == 'bars';
    sets[index] = { settings = s, view = C.view(rows) };
end;
return function() C.draw(sets); end;
