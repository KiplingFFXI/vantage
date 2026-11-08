-- Party list buffs beside a copy of the game's party list, with each icon's time left, and the party's long
-- cooldowns nearest the list.
local C = require('preview.readme.common');
local overlay = require('ui.native_party_hud');
require('ui.icons').prepare();
require('ui.recast_icons').prepare();
C.resources();
local s = C.settings();
s.party_ui.enabled, s.party_ui.effects.timers = true, true;
s.party_cooldowns.enabled, s.party_cooldowns.strips = true, true;
local roster, geometry, party_list = C.party_list({
    { name = 'Aster', job = 5, hp = 1016, max_hp = 1104, mp = 734, max_mp = 1146, tp = 0, leader = true },
    { name = 'Bramble', job = 7, hp = 1497, max_hp = 1741, mp = 159, max_mp = 331, tp = 870 },
    { name = 'Cinder', job = 3, hp = 978, max_hp = 978, mp = 1062, max_mp = 1279, tp = 0 },
    { name = 'Dawn', job = 10, hp = 1007, max_hp = 1144, mp = 343, max_mp = 602, tp = 120 },
    { name = 'Elm', job = 1, hp = 1299, max_hp = 1644, mp = 0, max_mp = 0, tp = 640 },
    { name = 'Fable', job = 6, hp = 1298, max_hp = 1338, mp = 0, max_mp = 0, tp = 450 },
}, 380, 16);
local function effect(id, name, kind, left, total, status)
    return { effect = id, name = name, kind = kind, status = status or (left and 'estimated' or 'unknown'), remaining = left,
        total = total, present = true, key = name .. (left or 0) };
end;
local function cooldown(ability, left) return { ability = ability, deadline = C.now + left }; end;
local subjects = {
    [1001] = { known = true, complete = true, source = 'server', effects = { effect(33, 'Haste', 'buff', 161, 180, 'server'),
        effect(43, 'Refresh', 'buff', 98, 150, 'server'), effect(40, 'Protect', 'buff', 1460, 1800, 'server'), effect(41, 'Shell', 'buff', 1395, 1800, 'server') } },
    [1002] = { known = true, complete = true, source = 'server', effects = { effect(33, 'Haste', 'buff', 122, 180),
        effect(43, 'Refresh', 'buff', 64, 150), effect(40, 'Protect', 'buff'), effect(41, 'Shell', 'buff') },
        cooldowns = { cooldown(22, 4290) } },
    [1003] = { known = true, complete = true, source = 'server', effects = { effect(43, 'Refresh', 'buff', 141, 150),
        effect(40, 'Protect', 'buff'), effect(41, 'Shell', 'buff') }, cooldowns = { cooldown(18, 6060) } },
    [1004] = { known = true, complete = true, source = 'server', effects = { effect(43, 'Refresh', 'buff', 37, 150),
        effect(40, 'Protect', 'buff'), effect(41, 'Shell', 'buff'), effect(136, 'STR Down', 'debuff') } },
    [1005] = { known = true, complete = true, source = 'server', effects = { effect(33, 'Haste', 'buff', 76, 180),
        effect(56, 'Berserk', 'buff'), effect(40, 'Protect', 'buff'), effect(41, 'Shell', 'buff') }, cooldowns = { cooldown(32, 74) } },
    [1006] = { known = true, complete = true, source = 'server', effects = { effect(33, 'Haste', 'buff', 18, 180),
        effect(40, 'Protect', 'buff'), effect(41, 'Shell', 'buff'), effect(3, 'Poison', 'debuff') } },
};
return function()
    party_list(s.style);
    overlay.draw(roster, subjects, s.party_ui, C.now, { native_geometry = geometry, settings = s, global_style = s.style,
        cooldowns = s.party_cooldowns, shift = false });
end;
