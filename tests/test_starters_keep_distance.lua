-- A starter keeps the distance to each member showing (core/starters.lua). The distance shows only on Party list, which
-- can be on with no effects for it (ui/party_defaults.lua show_beside). So a starter that turns Party list off leaves
-- it on with no effects while it shows the distance, and still shows as in use.
local defaults, party, starters = require('ui.defaults'), require('ui.party_defaults'), require('core.starters');
local function fresh() return defaults.tidy(defaults.make()); end;

local s = fresh();
party.show_beside(s, 'distance', true);
assert(s.party_ui.enabled and s.party_ui.distance and s.party_ui.effects.kind == 'none', 'Fixture: Party list shows the distance alone.');
local shown = { melee = 'none', tank = 'debuff', healer = 'all', support = 'all', ['crowd control'] = 'debuff', pet = 'none' };
for _, entry in ipairs(starters.list) do
    local after = assert(starters.apply(s, entry.id));
    assert(after.party_ui.enabled and after.party_ui.distance, 'The ' .. entry.name .. ' starter keeps the distance showing, but Party list is '
        .. (after.party_ui.enabled and 'on' or 'off') .. ' with distance ' .. tostring(after.party_ui.distance) .. '.');
    assert(after.party_ui.effects.kind == shown[entry.id], entry.name .. ' shows ' .. shown[entry.id] .. ' there: ' .. after.party_ui.effects.kind);
    assert(starters.matching(after) == entry.id, entry.name .. ' shows as in use: ' .. tostring(starters.matching(after)));
end;

-- After a starter that shows effects there, one that doesn't leaves the distance there alone.
local melee = assert(starters.apply(assert(starters.apply(s, 'healer')), 'melee'));
assert(melee.party_ui.enabled and melee.party_ui.distance and melee.party_ui.effects.kind == 'none', 'Melee after Healer keeps the distance alone.');
assert(starters.matching(melee) == 'melee', 'Melee after Healer shows as in use.');
-- Effects shown with the distance aren't Melee's.
melee.party_ui.effects.kind = 'all';
assert(starters.matching(melee) == nil, 'Party buffs on is not Melee.');

-- Party list turned off on its own tab keeps the distance pick but shows nothing, so a starter leaves it off.
local off = fresh();
party.show_beside(off, 'distance', true);
party.switch(off.party_ui, false);
assert(off.party_ui.distance and not off.party_ui.enabled, 'Fixture: the distance is picked, with Party list off.');
local after = assert(starters.apply(off, 'melee'));
assert(not after.party_ui.enabled, 'A starter doesn\'t show a distance that wasn\'t showing.');
assert(starters.matching(after) == 'melee', 'It shows as in use.');

-- Without the distance, Melee and Pet turn Party list off as before, Party cooldowns beside the list with it, as every
-- starter sets Party cooldowns.
local strips = fresh();
party.show_beside(strips, 'cooldowns', true);
assert(strips.party_ui.enabled and strips.party_cooldowns.enabled and strips.party_cooldowns.strips, 'Fixture: Party cooldowns show beside the list alone.');
for _, id in ipairs({ 'melee', 'pet' }) do
    after = assert(starters.apply(strips, id));
    assert(not after.party_ui.enabled and not after.party_cooldowns.enabled, id .. ' turns Party list and Party cooldowns off.');
    assert(starters.matching(after) == id, id .. ' shows as in use.');
end;
