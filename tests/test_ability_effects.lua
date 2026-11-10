-- data/ability_effects.lua, what Only effects from job abilities keeps when it didn't see what put an effect on. Each id
-- is an effect the catalog names, and none is one a spell gives too, as that copy could be the spell's.
local catalog = require('core.catalog');
local list, names, durations = require('data.ability_effects'), require('data.catalog'), require('data.effects');
local count = 0;
for id, value in pairs(list) do
    count = count + 1;
    assert(value == true and names[id] ~= nil, 'The catalog names effect ' .. tostring(id) .. '.');
end
assert(count > 80, 'Fixture: the whole list loads: ' .. count);
for spell, info in pairs(durations.spells) do
    for effect in pairs(info.by_effect or { [info.effect or 0] = true }) do
        assert(not list[effect], 'Spell ' .. spell .. ' gives effect ' .. effect .. ' too, so it stays off the list.');
    end
end

-- What was seen to put it on decides, with blood pacts and rolls as abilities. A monster's move or an added effect isn't
-- one. What wasn't seen goes by the list: Berserk is on it, and Protect isn't.
local BERSERK, PROTECT = 56, 40;
for kind, wanted in pairs({ abilities = true, pacts = true, rolls = true, spells = false, skills = false, procs = false }) do
    assert(catalog.from_ability({ effect = BERSERK, action_kind = kind }) == wanted
        and catalog.from_ability({ effect = PROTECT, action_kind = kind }) == wanted, kind .. ' decides.');
end
assert(catalog.from_ability({ effect = BERSERK }) and not catalog.from_ability({ effect = PROTECT }), 'Not seen, the list decides.');
return count .. ' effects only job abilities give';
