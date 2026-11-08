-- The party cooldowns list: the long cooldowns party members used, soonest first, with who used them.
local C = require('preview.readme.common');
require('ui.icons').prepare();
require('ui.recast_icons').prepare();
C.resources();
local s = C.settings();
local watch = s.party_cooldowns;
watch.enabled, watch.strips = true, false;
watch.list.enabled, watch.list.x, watch.list.y, watch.list.width = true, 16, 16, 320;
local function use(member, name, ability, job, left, recast)
    return { ability = ability, name = name, job = job, recast = recast, special = recast == 7200, member = 1000 + member,
        member_name = ({ 'Aster', 'Bramble', 'Cinder', 'Dawn', 'Elm', 'Fable' })[member], deadline = C.now + left,
        start = C.now + left - recast };
end;
local view = C.view({});
view.cooldowns = { use(5, 'Berserk', 31, 1, 61, 300), use(5, 'Warcry', 32, 1, 74, 300), use(2, 'Sentinel', 48, 7, 166, 300),
    use(3, 'Divine Seal', 74, 3, 352, 600), use(1, 'Convert', 83, 5, 431, 600), use(2, 'Invincible', 22, 7, 4290, 7200),
    use(3, 'Benediction', 18, 3, 6060, 7200) };
return function() C.draw({ { settings = s, view = view } }); end;
