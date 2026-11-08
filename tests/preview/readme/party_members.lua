-- Party members' timers: the buffs a Red Mage put on the party and a debuff on one member, each named with whose it is.
local C = require('preview.readme.common');
require('ui.icons').prepare();
local function on(member, effect, name, kind, left, total)
    return C.row({ effect = effect, name = name, kind = kind, scope = 'party', entity = 1000 + member,
        entity_name = ({ 'Aster', 'Bramble', 'Cinder', 'Dawn', 'Elm', 'Fable' })[member], left = left, total = total,
        status = left and 'estimated' or 'unknown', source = kind == 'buff' and 'You' or nil, mine = kind == 'buff' });
end;
local rows = {
    on(2, 33, 'Haste', 'buff', 122, 180),
    on(2, 43, 'Refresh', 'buff', 64, 150),
    on(3, 43, 'Refresh', 'buff', 141, 150),
    on(4, 43, 'Refresh', 'buff', 37, 150),
    on(5, 33, 'Haste', 'buff', 76, 180),
    on(6, 33, 'Haste', 'buff', 18, 180),
    on(6, 3, 'Poison', 'debuff'),
};
local s = C.settings();
local p = s.panels.party;
p.enabled, p.x, p.y, p.width = true, 16, 16, 300;
return function() C.draw({ { settings = s, view = C.view(rows) } }); end;
