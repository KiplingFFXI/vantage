-- Another player's Requiem, Elegy, Threnody and Lullaby last their base times 1 and a tenth of the singer's instrument
-- bonus to them, with the part of a second dropped, then twice that under Troubadour (Phoenix
-- globals/spells/enfeebling_song.lua :111, :135-136). Only your own gear is read, so theirs counts from the base up to
-- what the best instrument a level 75 bard can use gives: Requiem +4 (Requiem Flute), Threnody +3 (Sorrowful Harp), Elegy
-- +2 (Horn +1) and Lullaby +2 (Nursemaid's Harp, Cradle Horn) (sql/item_mods.sql). Their party listing says whether
-- Troubadour was up. A monster's song is its base alone. Your own Requiem Flute under Troubadour drops the part of a
-- second before it doubles. Real 0x028s through observer.read.
local observer = require('core.observer');
local catalog = require('core.catalog');
local SELF, DAVE, MOB = 1001, 1003, 0x1000123;
local function snapshot(dave)
    return { valid = true, id = SELF, name = 'Tester', zone = 102, job = 1, level = 75, self_known = true, self_effects = {},
        party = { { id = DAVE, name = 'Dave', scope = 'party', valid = true, effects = dave or {} } },
        entities = { [SELF] = { name = 'Tester' }, [DAVE] = { name = 'Dave', kind = 'player' },
            [MOB] = { name = 'Goblin Bard', kind = 'monster' } } };
end
-- A song from actor that lands (237) on target, naming effect.
local function sing(actor, spell, target, effect)
    return MOCK.packet(0x028, MOCK.action_bytes(actor, 4, spell, { { id = target, rows = { { message = 237, param = effect } } } }));
end
local function landed(events, target)
    for _, event in ipairs(events) do if event.kind == 'apply' and event.entity_id == target then return event; end end
end
local function range(event) return event and (tostring(event.duration_min) .. ' to ' .. tostring(event.duration)) or 'nothing'; end

-- Foe Requiem VI (373, Requiem 192): 144 up to floor(144 * 1.4) = 201, and 288 to 402 under Troubadour.
local requiem = landed(observer.read(sing(DAVE, 373, MOB, 192), 1, snapshot()), MOB);
assert(requiem and requiem.duration == 201 and requiem.duration_min == 144 and requiem.basis == 'Duration range by the singer\'s instrument',
    'A party bard\'s Foe Requiem VI counts 144 to 201 seconds: ' .. range(requiem) .. ', ' .. tostring(requiem and requiem.basis));
requiem = landed(observer.read(sing(DAVE, 373, MOB, 192), 1, snapshot({ { effect = 348 } })), MOB);
assert(requiem and requiem.duration == 402 and requiem.duration_min == 288, 'Under Troubadour, 288 to 402: ' .. range(requiem));
-- Soul Voice makes no enfeebling song longer.
requiem = landed(observer.read(sing(DAVE, 373, MOB, 192), 1, snapshot({ { effect = 52 } })), MOB);
assert(requiem and requiem.duration == 201 and requiem.duration_min == 144, 'Soul Voice changes nothing: ' .. range(requiem));
-- Carnage Elegy (422, 180 s, +2), a Threnody (454, 60 s, +3) and Foe Lullaby (463, 30 s, +2).
local elegy = landed(observer.read(sing(DAVE, 422, MOB, 194), 1, snapshot()), MOB);
assert(elegy and elegy.duration == 216 and elegy.duration_min == 180, 'Carnage Elegy, 180 to 216: ' .. range(elegy));
local threnody = landed(observer.read(sing(DAVE, 454, MOB, 217), 1, snapshot()), MOB);
assert(threnody and threnody.duration == 78 and threnody.duration_min == 60, 'Fire Threnody, 60 to 78: ' .. range(threnody));
local lullaby = landed(observer.read(sing(DAVE, 463, MOB, 2), 1, snapshot()), MOB);
assert(lullaby and lullaby.duration == 36 and lullaby.duration_min == 30, 'Foe Lullaby, 30 to 36: ' .. range(lullaby));
-- A monster's Horde Lullaby (376) on you is its base alone.
lullaby = landed(observer.read(sing(MOB, 376, SELF, 2), 1, snapshot()), SELF);
assert(lullaby and lullaby.duration == 30 and lullaby.duration_min == 30, 'A monster\'s Horde Lullaby: ' .. range(lullaby));

-- Your own Foe Requiem VI with a Requiem Flute (17852) in the range slot, under Troubadour: floor(144 * 1.4) * 2 = 402.
local upper, lower = catalog.duration('spells', 373, 192, { items = { [2] = 17852 }, buffs = { [348] = true } });
assert(upper == 402 and lower == 402, 'Your own Requiem Flute under Troubadour gives 402: ' .. tostring(lower) .. ' to ' .. tostring(upper));
upper, lower = catalog.duration('spells', 373, 192, { items = { [2] = 17852 }, buffs = {} });
assert(upper == 201 and lower == 201, 'And 201 without it: ' .. tostring(lower) .. ' to ' .. tostring(upper));
-- A buff song drops it before Troubadour too (globals/spells/enhancing_song.lua :227, :252-253). Valor Minuet IV (397)
-- with gear that gives Minuet +1 and Song duration +13% (23161, past the era but in the gear list): floor(120 * 1.23) * 2.
upper, lower = catalog.duration('spells', 397, 198, { items = { [0] = 23161 }, buffs = { [348] = true } });
assert(upper == 294 and lower == 294, 'Your own Minuet under Troubadour gives 294: ' .. tostring(lower) .. ' to ' .. tostring(upper));
return 'Another player\'s enfeebling songs count the range their instrument can give';
