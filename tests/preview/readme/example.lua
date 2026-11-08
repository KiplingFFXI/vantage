-- The main README picture: a level 75 Red Mage's own buffs and debuffs as icons, the crab it fights in Target
-- timers, its spell and ability recasts, the party's long cooldowns, and the party list buffs beside a copy of
-- the game's party list.
local C = require('preview.readme.common');
local overlay = require('ui.native_party_hud');
require('ui.icons').prepare();
require('ui.recast_icons').prepare();
C.resources();
C.can_dispel();

local s = C.settings();
local function panel(key, mode, x, y, width)
    local p = s.panels[key];
    p.enabled, p.mode, p.x, p.y, p.width = true, mode, x, y, width;
    p.stack_direction = mode == 'icons' and 'horizontal' or 'vertical';
    return p;
end;
panel('self_buffs', 'icons', 16, 16, 300);
panel('self_debuffs', 'icons', 332, 16, 120);
local target = panel('target', 'bars', 16, 80, 300);
target.show_source, target.dispel_light = true, true;
panel('spell_recasts', 'bars', 332, 80, 250);
panel('ability_recasts', 'bars', 332, 276, 250);

local rows = {
    C.row({ effect = 33, name = 'Haste', left = 161, total = 180 }),
    C.row({ effect = 43, name = 'Refresh', left = 98, total = 150 }),
    C.row({ effect = 116, name = 'Phalanx', left = 133, total = 180 }),
    C.row({ effect = 37, name = 'Stoneskin', left = 241, total = 300 }),
    C.row({ effect = 36, name = 'Blink', left = 205, total = 300 }),
    C.row({ effect = 40, name = 'Protect', left = 1460, total = 1800 }),
    C.row({ effect = 41, name = 'Shell', left = 1395, total = 1800 }),
    C.row({ effect = 251, name = 'Food', left = 2580, total = 3600 }),
    C.row({ effect = 136, name = 'STR Down', kind = 'debuff', left = 47, total = 60 }),
    C.row({ effect = 3, name = 'Poison', kind = 'debuff', left = 19, total = 30 }),
    C.row({ effect = 134, name = 'Dia', kind = 'debuff', scope = 'enemy', left = 94, total = 120, status = 'estimated', source = 'You', mine = true }),
    C.row({ effect = 13, name = 'Slow', kind = 'debuff', scope = 'enemy', left = 142, total = 180, status = 'estimated', source = 'You', mine = true }),
    C.row({ effect = 4, name = 'Paralysis', kind = 'debuff', scope = 'enemy', left = 51, total = 120, status = 'estimated', source = 'You', mine = true }),
    C.row({ effect = 5, name = 'Blindness', kind = 'debuff', scope = 'enemy', left = 98, total = 180, status = 'estimated', source = 'You', mine = true }),
    C.row({ effect = 93, name = 'Defense Boost', kind = 'buff', scope = 'enemy' }),
    C.row({ effect = 191, name = 'Magic Def. Boost', kind = 'buff', scope = 'enemy' }),
    C.recast('spell', 54, 21, 30),
    C.recast('spell', 53, 12, 20),
    C.recast('spell', 109, 7, 18),
    C.recast('spell', 260, 3, 10),
    C.recast('ability', 20, 4320, 7200),
    C.recast('ability', 83, 432, 600),
    C.recast('ability', 74, 181, 600),
};
local view = C.view(rows);

-- The party's long cooldowns, soonest first.
local watch = s.party_cooldowns;
watch.enabled, watch.strips = true, false;
watch.list.enabled, watch.list.x, watch.list.y, watch.list.width = true, 678, 16, 300;
local function use(member, name, ability, job, left, recast)
    return { ability = ability, name = name, job = job, recast = recast, special = recast == 7200, member = 1000 + member,
        member_name = ({ 'Aster', 'Bramble', 'Cinder', 'Dawn', 'Elm', 'Fable' })[member], deadline = C.now + left,
        start = C.now + left - recast };
end;
view.cooldowns = { use(5, 'Warcry', 32, 1, 74, 300), use(2, 'Sentinel', 48, 7, 166, 300), use(3, 'Divine Seal', 74, 3, 352, 600),
    use(2, 'Invincible', 22, 7, 4290, 7200), use(3, 'Benediction', 18, 3, 6060, 7200) };

-- The party list buffs beside the copy of the game's party list.
s.party_ui.enabled = true;
local roster, geometry, party_list = C.party_list({
    { name = 'Aster', job = 5, hp = 1016, max_hp = 1104, mp = 734, max_mp = 1146, tp = 0, leader = true },
    { name = 'Bramble', job = 7, hp = 1497, max_hp = 1741, mp = 159, max_mp = 331, tp = 870 },
    { name = 'Cinder', job = 3, hp = 978, max_hp = 978, mp = 1062, max_mp = 1279, tp = 0 },
    { name = 'Dawn', job = 10, hp = 1007, max_hp = 1144, mp = 343, max_mp = 602, tp = 120 },
    { name = 'Elm', job = 1, hp = 1299, max_hp = 1644, mp = 0, max_mp = 0, tp = 640 },
    { name = 'Fable', job = 6, hp = 1298, max_hp = 1338, mp = 0, max_mp = 0, tp = 450 },
}, 838, 196);
local function effect(id, name, kind, left, total, status)
    return { effect = id, name = name, kind = kind, status = status or (left and 'estimated' or 'unknown'), remaining = left,
        total = total, present = true, key = name .. (left or 0) };
end;
local subjects = {
    [1001] = { known = true, complete = true, source = 'server', effects = { effect(33, 'Haste', 'buff', 161, 180, 'server'),
        effect(43, 'Refresh', 'buff', 98, 150, 'server'), effect(40, 'Protect', 'buff', 1460, 1800, 'server'), effect(41, 'Shell', 'buff', 1395, 1800, 'server') } },
    [1002] = { known = true, complete = true, source = 'server', effects = { effect(33, 'Haste', 'buff', 122, 180),
        effect(43, 'Refresh', 'buff', 64, 150), effect(40, 'Protect', 'buff'), effect(41, 'Shell', 'buff'), effect(62, 'Sentinel', 'buff') } },
    [1003] = { known = true, complete = true, source = 'server', effects = { effect(43, 'Refresh', 'buff', 141, 150),
        effect(40, 'Protect', 'buff'), effect(41, 'Shell', 'buff') } },
    [1004] = { known = true, complete = true, source = 'server', effects = { effect(43, 'Refresh', 'buff', 37, 150),
        effect(40, 'Protect', 'buff'), effect(41, 'Shell', 'buff'), effect(136, 'STR Down', 'debuff') } },
    [1005] = { known = true, complete = true, source = 'server', effects = { effect(33, 'Haste', 'buff', 76, 180),
        effect(56, 'Berserk', 'buff'), effect(40, 'Protect', 'buff'), effect(41, 'Shell', 'buff') } },
    [1006] = { known = true, complete = true, source = 'server', effects = { effect(33, 'Haste', 'buff', 18, 180),
        effect(40, 'Protect', 'buff'), effect(41, 'Shell', 'buff'), effect(3, 'Poison', 'debuff') } },
};

return function()
    party_list(s.style);
    C.draw({ { settings = s, view = view } });
    overlay.draw(roster, subjects, s.party_ui, C.now, { native_geometry = geometry, settings = s, global_style = s.style,
        cooldowns = s.party_cooldowns, shift = false });
end;
