-- Light up debuffs you can remove, for a level 75 White Mage who has learned the -na spells, Cursna and Erase: the
-- debuffs it can cure light up on Party members' timers and beside a copy of the game's party list, and the buffs and
-- Weakness don't.
local C = require('preview.readme.common');
local overlay = require('ui.native_party_hud');
require('ui.icons').prepare();

local CURES = { [14] = true, [15] = true, [16] = true, [17] = true, [18] = true, [19] = true, [20] = true, [143] = true };
MOCK.player.main_job, MOCK.player.main_level, MOCK.player.sub_job, MOCK.player.sub_level = 3, 75, 4, 37;
AshitaCore:GetMemoryManager():GetPlayer().HasSpell = function(_, id) return CURES[id] == true; end;

local s = C.settings();
local p = s.panels.party;
p.enabled, p.x, p.y, p.width, p.dispel_light = true, 16, 16, 300, true;
s.party_ui.enabled, s.party_ui.effects.cleanse_light = true, true;

local NAMES = { 'Cinder', 'Aster', 'Bramble', 'Dawn', 'Elm', 'Fable' };
local function on(member, effect, name, kind, left, total)
    return C.row({ effect = effect, name = name, kind = kind, scope = 'party', entity = 1000 + member,
        entity_name = NAMES[member], left = left, total = total, status = left and 'estimated' or 'unknown',
        source = kind == 'buff' and 'You' or nil, mine = kind == 'buff' });
end;
local view = C.view({
    on(3, 33, 'Haste', 'buff', 122, 180),
    on(5, 33, 'Haste', 'buff', 76, 180),
    on(3, 4, 'Paralysis', 'debuff'),
    on(2, 6, 'Silence', 'debuff'),
    on(4, 13, 'Slow', 'debuff'),
    on(5, 1, 'Weakness', 'debuff'),
    on(6, 3, 'Poison', 'debuff'),
});
view.context.job, view.context.job_name = 3, 'WHM';

local roster, geometry, party_list = C.party_list({
    { name = 'Cinder', job = 3, subjob = 4, hp = 978, max_hp = 978, mp = 1062, max_mp = 1279, tp = 0, leader = true },
    { name = 'Aster', job = 5, hp = 1016, max_hp = 1104, mp = 734, max_mp = 1146, tp = 0 },
    { name = 'Bramble', job = 7, hp = 1497, max_hp = 1741, mp = 159, max_mp = 331, tp = 870 },
    { name = 'Dawn', job = 10, hp = 1007, max_hp = 1144, mp = 343, max_mp = 602, tp = 120 },
    { name = 'Elm', job = 1, hp = 1299, max_hp = 1644, mp = 0, max_mp = 0, tp = 640 },
    { name = 'Fable', job = 6, hp = 1298, max_hp = 1338, mp = 0, max_mp = 0, tp = 450 },
}, 466, 86);
local function effect(id, name, kind, left, total, status)
    return { effect = id, name = name, kind = kind, status = status or (left and 'estimated' or 'unknown'), remaining = left,
        total = total, present = true, key = name .. (left or 0) };
end;
local subjects = {
    [1001] = { known = true, complete = true, source = 'server', effects = { effect(43, 'Refresh', 'buff', 98, 150, 'server'),
        effect(40, 'Protect', 'buff', 1460, 1800, 'server'), effect(41, 'Shell', 'buff', 1395, 1800, 'server') } },
    [1002] = { known = true, complete = true, source = 'server', effects = { effect(40, 'Protect', 'buff'),
        effect(41, 'Shell', 'buff'), effect(6, 'Silence', 'debuff') } },
    [1003] = { known = true, complete = true, source = 'server', effects = { effect(33, 'Haste', 'buff', 122, 180),
        effect(40, 'Protect', 'buff'), effect(41, 'Shell', 'buff'), effect(4, 'Paralysis', 'debuff') } },
    [1004] = { known = true, complete = true, source = 'server', effects = { effect(40, 'Protect', 'buff'),
        effect(41, 'Shell', 'buff'), effect(13, 'Slow', 'debuff') } },
    [1005] = { known = true, complete = true, source = 'server', effects = { effect(33, 'Haste', 'buff', 76, 180),
        effect(1, 'Weakness', 'debuff') } },
    [1006] = { known = true, complete = true, source = 'server', effects = { effect(40, 'Protect', 'buff'),
        effect(41, 'Shell', 'buff'), effect(3, 'Poison', 'debuff') } },
};

return function()
    party_list(s.style);
    C.draw({ { settings = s, view = view } });
    overlay.draw(roster, subjects, s.party_ui, C.now, { native_geometry = geometry, settings = s, global_style = s.style,
        shift = false });
end;
