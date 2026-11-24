-- A guess over an effect it takes off. Phoenix refuses a new effect over its negative unless it's as strong, and over
-- the effect that blocks it (status_effect_container.cpp CanGainStatusEffect :367-396). One it only removes goes when
-- the new one lands (OverwriteStatusEffect :455-467, AddStatusEffect :513). A weapon skill also checks for its own
-- effect and the one that blocks it (weaponskills.lua handleWeaponskillEffect :1108-1118).
local tracker = require('core.tracker');
local catalog = require('core.catalog');
-- The client names Sleep II and Lullaby.
AshitaCore.GetResourceManager = function() return { GetString = function(_, kind, id)
    return kind == 'buffs.names' and ({ [19] = 'sleep', [193] = 'lullaby' })[id] or nil;
end }; end;
local ME, CRAB = 1001, 0x1000222;
local snapshot = { valid = true, id = ME, zone = 1, name = 'Me', self_known = true, self_effects = {}, party = {},
    entities = { [CRAB] = { id = CRAB, name = 'Land Crab', kind = 'monster' } }, target = { id = CRAB, name = 'Land Crab', kind = 'monster' } };
local settings = { tracking = { max_entities = 64, stale_seconds = 180 } };
local model;
local function rows(now)
    local found = {};
    for _, row in ipairs(model:view(now, settings, snapshot).rows) do
        if row.entity_id == CRAB then found[row.effect] = row; end
    end
    return found;
end
-- What the crab does to itself, reported.
local function reported(effect, at)
    model:observe({ { kind = 'apply', entity_id = CRAB, effect = effect, source = CRAB, scope = 'enemy', duration = 60,
        action_category = 11, spell = 600, drops = catalog.drops(effect) } }, at, snapshot);
    model:reconcile(snapshot, at);
end
-- A guess from your weapon skill.
local function guessed(effect, at)
    model:observe({ { kind = 'apply', entity_id = CRAB, effect = effect, source = ME, scope = 'enemy', duration = 180, guessed = true,
        action_category = 3, spell = 83, drops = catalog.drops(effect) } }, at, snapshot);
    model:reconcile(snapshot, at);
end
local function fresh()
    model = tracker.new();
    model:reconcile(snapshot, 0);
end

-- Defense Down takes Defense Boost off and has no negative (status_effects.yaml :1446-1455).
fresh();
reported(93, 10);
assert(rows(10)[93], 'Fixture: the crab shows Defense Boost.');
guessed(149, 12);
local now = rows(12);
assert(now[149] and now[149].source == ME, 'Armor Break\'s Defense Down shows over the Defense Boost.');
assert(not now[93], 'And the Defense Boost it took off is gone.');

-- Petrification takes Terror off, as one of its exclusion group (status_effects.yaml :86-97, :281-290).
fresh();
reported(28, 10);
guessed(7, 12);
now = rows(12);
assert(now[7] and not now[28], 'A guessed Petrification shows over Terror and takes it off.');

-- Slow's negative is Haste (:161-168), so a Slow is refused over a Haste as strong, and Vantage can't see how strong.
fresh();
reported(33, 10);
guessed(13, 12);
now = rows(12);
assert(now[33] and not now[13], 'A guessed Slow changes nothing over a Haste.');

-- Sleep's negative is Sleep II and Lullaby blocks it (:27-37), so neither lets a guessed Sleep on.
fresh();
reported(19, 10);
guessed(2, 12);
now = rows(12);
assert(now[19] and not now[2], 'A guessed Sleep changes nothing over a Sleep II.');
fresh();
reported(193, 10);
guessed(2, 12);
now = rows(12);
assert(now[193] and not now[2], 'A guessed Sleep changes nothing over a Lullaby.');

-- Each elemental damage over time is blocked by the one that takes it off (:1228-1290), so Gale Axe's Choke changes
-- nothing over a Frost, and the Rasp it would take off stays. Over a Rasp alone it lands and takes the Rasp off.
fresh();
reported(129, 10);
reported(131, 10);
guessed(130, 12);
now = rows(12);
assert(now[129] and now[131] and not now[130], 'A guessed Choke changes nothing over a Frost, and the Rasp stays.');
fresh();
reported(131, 10);
guessed(130, 12);
now = rows(12);
assert(now[130] and not now[131], 'Over a Rasp alone, a guessed Choke lands and takes it off.');

-- Petrification and Stun block each other (:86-97, :124-131).
fresh();
reported(7, 10);
guessed(10, 12);
now = rows(12);
assert(now[7] and not now[10], 'A guessed Stun changes nothing over a Petrification.');

-- Once the one it takes off has run out, a guess lands as before.
fresh();
reported(33, 10);
guessed(13, 71);
now = rows(71);
assert(now[13] and not now[33], 'Past the Haste\'s time, a guessed Slow lands.');
