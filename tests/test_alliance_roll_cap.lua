-- A Corsair in the alliance's other party. Phoenix keeps 2 of a Corsair's rolls on each target, 1 when their main job
-- isn't COR, and on the Corsair their own Bust counts too. A new roll over that takes off the one that ends first
-- (globals/job_utils/corsair.lua applyCorsairEffect :523-565), and that wear-off goes only to the target and the
-- Corsair. Their party's listing shows it, and an alliance member's rows go by the count. Real 0x028s through
-- observer.read and the tracker, as test_alliance_shadows.lua does.
local observer = require('core.observer');
local SELF, ALLY, COR, FRIEND, OTHER = 1001, 1002, 1007, 1008, 1009;
-- The client's party: the Corsair is in slot 6, a COR main until a test changes it, and the other Corsair in slot 8.
local slots = { [6] = { job = 17, zone2 = 0, updated = 1700000000 }, [7] = { job = 1, zone2 = 0, updated = 1700000000 },
    [8] = { job = 17, zone2 = 0, updated = 1700000000 } };
local party = {
    GetMemberMainJob = function(_, slot) return slots[slot] and slots[slot].job; end,
    GetMemberZone2 = function(_, slot) return slots[slot] and slots[slot].zone2; end,
    GetMemberLastUpdatedTimestamp = function(_, slot) return slots[slot] and slots[slot].updated; end,
};
AshitaCore.GetMemoryManager = function() return { GetParty = function() return party; end }; end;
local function snapshot()
    return { valid = true, id = SELF, name = 'Tester', zone = 151, job = 6, level = 75, self_known = true, self_revision = 1,
        self_timer_revision = 1, self_effects = {},
        party = { { id = ALLY, name = 'Ally', scope = 'party', slot = 1, group = 1, zone = 151 },
            { id = COR, name = 'Cor', scope = 'alliance', slot = 6, group = 2, zone = 151 },
            { id = FRIEND, name = 'Friend', scope = 'alliance', slot = 7, group = 2, zone = 151 },
            { id = OTHER, name = 'Other', scope = 'alliance', slot = 8, group = 2, zone = 151 } },
        entities = { [SELF] = { id = SELF, name = 'Tester', kind = 'player' }, [ALLY] = { id = ALLY, name = 'Ally', kind = 'player' },
            [COR] = { id = COR, name = 'Cor', kind = 'player' }, [FRIEND] = { id = FRIEND, name = 'Friend', kind = 'player' },
            [OTHER] = { id = OTHER, name = 'Other', kind = 'player' } } };
end;
local function action(actor, ability, rows)
    local targets = {};
    for i, row in ipairs(rows) do targets[i] = { id = row[1], rows = { { message = row[2], param = row[3] } } }; end
    return MOCK.packet(0x028, MOCK.action_bytes(actor, 6, ability, targets));
end
-- The Corsair's own row is 420, a Double-Up 424 and a bust 426, the others' 421 and 427, the param the total
-- (corsair.lua applyRoll). Chaos Roll 105 is effect 317, Hunter's Roll 108 is 320, Ninja Roll 110 is 322 and
-- Samurai Roll 104 is 316.
local function roll(ability, total) return action(COR, ability, { { COR, 420, total }, { FRIEND, 421, total } }); end
local tracker;
local function step(now, packets)
    local snap, observations = snapshot(), {};
    for _, packet in ipairs(packets) do for _, o in ipairs(observer.read(packet, now, snap)) do observations[#observations + 1] = o; end end
    tracker:observe(observations, now, snap); tracker:reconcile(snap, now);
    return tracker:drain_events();
end
-- The roll and Bust rows on someone, sorted.
local function rolls_on(now, who)
    local out = {};
    for _, row in ipairs(tracker:view(now, {}, snapshot()).rows) do
        if row.entity_id == who and row.effect >= 309 and row.effect <= 327 then out[#out + 1] = row.effect; end
    end
    table.sort(out);
    return table.concat(out, ',');
end

-- A COR main: the third roll takes Chaos Roll off, as it ends first.
tracker = require('core.tracker').new();
step(10, { roll(105, 3) });
step(60, { roll(108, 4) });
local events = step(120, { roll(110, 4) });
local gone;
for _, event in ipairs(events) do if event.kind == 'removed' and event.entity_id == FRIEND then gone = event; end end
assert(rolls_on(121, FRIEND) == '320,322' and rolls_on(121, COR) == '320,322',
    'A third roll takes the one that ends first off: ' .. rolls_on(121, FRIEND) .. ' | ' .. rolls_on(121, COR));
assert(gone and gone.effect == 317 and gone.reason == 'A new roll from the same Corsair took its place.', 'Its removal says why.');
-- A Double-Up renews its roll and takes nothing off.
step(130, { action(COR, 108, { { COR, 424, 9 }, { FRIEND, 421, 9 } }) });
assert(rolls_on(131, FRIEND) == '320,322', 'A Double-Up took nothing off: ' .. rolls_on(131, FRIEND));
-- Another Corsair's roll counts on its own.
step(140, { action(OTHER, 104, { { OTHER, 420, 5 }, { FRIEND, 421, 5 } }) });
assert(rolls_on(141, FRIEND) == '316,320,322', 'Another Corsair\'s roll is no third roll: ' .. rolls_on(141, FRIEND));

-- A COR sub keeps one.
slots[6].job = 1;
tracker = require('core.tracker').new();
step(10, { roll(105, 3) });
step(60, { roll(108, 4) });
assert(rolls_on(61, FRIEND) == '320' and rolls_on(61, COR) == '320', 'A COR sub keeps one: ' .. rolls_on(61, FRIEND));
-- With no job to read, the Corsair counts as a COR main.
slots[6] = { job = 1, zone2 = 5, updated = 1700000000 };
tracker = require('core.tracker').new();
step(10, { roll(105, 3) });
step(60, { roll(108, 4) });
assert(rolls_on(61, FRIEND) == '317,320', 'Unread counts as a COR main: ' .. rolls_on(61, FRIEND));
slots[6] = { job = 17, zone2 = 0, updated = 1700000000 };

-- On the Corsair their Bust takes one of the two places, and it never goes itself.
tracker = require('core.tracker').new();
step(10, { roll(105, 3) });
step(20, { action(COR, 105, { { COR, 426, 12 }, { FRIEND, 427, 12 } }) });
step(30, { roll(108, 4) });
assert(rolls_on(31, COR) == '309,320' and rolls_on(31, FRIEND) == '320', 'Fixture: a Bust and a roll: ' .. rolls_on(31, COR));
step(60, { roll(110, 4) });
assert(rolls_on(61, COR) == '309,322' and rolls_on(61, FRIEND) == '320,322',
    'The Bust counts on the Corsair alone: ' .. rolls_on(61, COR) .. ' | ' .. rolls_on(61, FRIEND));
return 'An alliance Corsair\'s rolls are capped as Phoenix caps them';
