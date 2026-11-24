-- An alliance member's Utsusemi shows how many shadows they have, counted as a mob's are, as the game lists buffs for your
-- own party only: Ichi 3, Ni 4 and San 5, Ni 3 for a main job the client shows isn't NIN, then one less for each shadow
-- seen taking a hit, and none once a hit gets through. Your party is still read from your listings, and other players
-- aren't followed. Real 0x028s through observer.read.
local observer = require('core.observer');
local SELF, ALLY, FRIEND, STRANGER, MOB = 1001, 1002, 1007, 1009, 0x1000123;
-- The client's party: Friend is in the alliance's second party, in slot 6, a NIN until a test changes it.
local slots = { [6] = { job = 13, zone2 = 0, updated = 1700000000 } };
local party = {
    GetMemberMainJob = function(_, slot) return slots[slot] and slots[slot].job; end,
    GetMemberZone2 = function(_, slot) return slots[slot] and slots[slot].zone2; end,
    GetMemberLastUpdatedTimestamp = function(_, slot) return slots[slot] and slots[slot].updated; end,
};
AshitaCore.GetMemoryManager = function() return { GetParty = function() return party; end }; end;
local function snapshot(zone)
    return { valid = true, id = SELF, name = 'Tester', zone = 151, job = 6, level = 75, self_known = true, self_revision = 1,
        self_timer_revision = 1, self_effects = {},
        party = { { id = ALLY, name = 'Ally', scope = 'party', slot = 1, group = 1, zone = 151 },
            { id = FRIEND, name = 'Friend', scope = 'alliance', slot = 6, group = 2, zone = zone or 151 } },
        entities = { [SELF] = { id = SELF, name = 'Tester', kind = 'player' }, [ALLY] = { id = ALLY, name = 'Ally', kind = 'player' },
            [FRIEND] = { id = FRIEND, name = 'Friend', kind = 'player' }, [STRANGER] = { id = STRANGER, name = 'Stranger', kind = 'player' },
            [MOB] = { id = MOB, name = 'Yagudo Conquistador', kind = 'monster' } } };
end;
-- One target row: { target, message, param, added, added_param, reaction, reaction_param }.
local function action(actor, category, id, rows)
    local targets = {};
    for i, row in ipairs(rows) do
        targets[i] = { id = row[1], rows = { { message = row[2], param = row[3], added = row[4], added_param = row[5],
            reaction = row[6], reaction_param = row[7] } } };
    end
    return MOCK.packet(0x028, MOCK.action_bytes(actor, category, id, targets));
end
local function utsusemi(who, spell) return action(who, 4, spell, { { who, 230, 66 } }); end
local function first(events, kind)
    for _, event in ipairs(events) do if event.kind == kind then return event; end end
end

-- The count each cast starts, and Ni's one less for a main job that isn't NIN.
for spell, count in pairs({ [338] = 3, [339] = 4, [340] = 5 }) do
    local cast = first(observer.read(utsusemi(FRIEND, spell), 1, snapshot()), 'apply');
    assert(cast and cast.effect == 66 and cast.shadows == count and cast.scope == 'alliance', 'Spell ' .. spell .. ' gives ' .. count .. '.');
end;
slots[6].job = 1;
assert(first(observer.read(utsusemi(FRIEND, 339), 1, snapshot()), 'apply').shadows == 3, 'Ni gives a WAR main one less.');
assert(first(observer.read(utsusemi(FRIEND, 340), 1, snapshot()), 'apply').shadows == 5, 'San has no such penalty.');
-- A job the client can't vouch for counts as a NIN, as core/roster.lua reads it: none yet, a slot it hasn't filled, someone
-- on their way between zones, or someone it lists in another zone.
for _, case in ipairs({ { job = 0 }, { updated = 0 }, { zone2 = 5 }, { zone = 152 } }) do
    slots[6] = { job = case.job or 1, zone2 = case.zone2 or 0, updated = case.updated or 1700000000 };
    assert(first(observer.read(utsusemi(FRIEND, 339), 1, snapshot(case.zone)), 'apply').shadows == 4, 'Unknown counts as a NIN.');
end;
slots[6] = { job = 13, zone2 = 0, updated = 1700000000 };
local yours = first(observer.read(utsusemi(ALLY, 339), 1, snapshot()), 'apply');
assert(yours and yours.scope == 'party' and yours.shadows == nil, 'A party member\'s count is their listing\'s.');
local theirs = first(observer.read(utsusemi(STRANGER, 339), 1, snapshot()), 'apply');
assert(theirs and theirs.scope == 'other' and theirs.shadows == nil, 'Other players aren\'t counted.');

-- What their shadows took: message 31 with how many, and a counter to their own attack (reaction 14).
local taken = first(observer.read(action(MOB, 1, 0, { { FRIEND, 31, 1 } }), 1, snapshot()), 'shadows');
assert(taken and taken.entity_id == FRIEND and taken.lost == 1 and taken.scope == 'alliance', 'A swing their shadow took.');
assert(first(observer.read(action(MOB, 11, 500, { { FRIEND, 31, 3 } }), 1, snapshot()), 'shadows').lost == 3, 'Three a skill took.');
local countered = first(observer.read(action(FRIEND, 1, 0, { { MOB, 0, 0, nil, nil, 14, 1 } }), 1, snapshot()), 'shadows');
assert(countered and countered.entity_id == FRIEND and countered.lost == 1, 'A counter their shadow took.');
for _, who in ipairs({ SELF, ALLY, STRANGER }) do
    assert(first(observer.read(action(MOB, 1, 0, { { who, 31, 1 } }), 1, snapshot()), 'shadows') == nil, 'Not counted for ' .. who .. '.');
end;

-- A hit for damage that got through: a swing, a critical hit, and a counter. A spell can go past shadows.
local function hit(events)
    local event = first(events, 'damage');
    return event and event.entity_id == FRIEND and event;
end;
local landed = hit(observer.read(action(MOB, 1, 0, { { FRIEND, 1, 40 } }), 1, snapshot()));
assert(landed and landed.scope == 'alliance' and landed.through and landed.melee, 'A swing that landed got through.');
assert(hit(observer.read(action(MOB, 1, 0, { { FRIEND, 67, 90 } }), 1, snapshot())).through, 'So did a critical hit.');
assert(hit(observer.read(action(FRIEND, 1, 0, { { MOB, 0, 0, nil, nil, 33, 20 } }), 1, snapshot())).through, 'A counter that hit them.');
local spell = hit(observer.read(action(MOB, 4, 144, { { FRIEND, 2, 300 } }), 1, snapshot()));
assert(spell and not spell.through and not spell.melee, 'A spell can go past shadows.');
for _, who in ipairs({ SELF, ALLY, STRANGER }) do
    assert(first(observer.read(action(MOB, 1, 0, { { who, 1, 40 } }), 1, snapshot()), 'damage') == nil, 'No hit is followed on ' .. who .. '.');
end;

-- The tracker: Copy Image, with the icon of the count, down to the last shadow or a hit that got through.
local tracker = require('core.tracker').new();
local function step(now, packets)
    local snap, observations = snapshot(), {};
    for _, packet in ipairs(packets) do for _, o in ipairs(observer.read(packet, now, snap)) do observations[#observations + 1] = o; end end
    tracker:observe(observations, now, snap); tracker:reconcile(snap, now);
    local rows = {};
    for _, row in ipairs(tracker:view(now, {}, snap).rows) do if row.entity_id == FRIEND then rows[#rows + 1] = row; end end
    return rows[1], #rows;
end;
local row, count = step(10, { utsusemi(FRIEND, 339) });
assert(count == 1 and row.effect == 66 and row.icon == 446 and row.shadows == 4 and row.scope == 'alliance', 'Ni shows four.');
for at, wanted in ipairs({ 445, 444, 66 }) do
    row = step(10 + at, { action(MOB, 1, 0, { { FRIEND, 31, 1 } }) });
    assert(row.effect == 66 and (row.icon or row.effect) == wanted and row.shadows == 4 - at, 'A shadow goes: ' .. wanted .. '.');
end;
row, count = step(20, { action(MOB, 1, 0, { { FRIEND, 31, 1 } }) });
assert(count == 0, 'The last one goes with the icon.');
row = step(30, { utsusemi(FRIEND, 338) });
assert(row.effect == 66 and row.icon == 445 and row.shadows == 3, 'Ichi starts three.');
row = step(31, { action(MOB, 4, 144, { { FRIEND, 2, 300 } }) });
assert(row and row.shadows == 3, 'A spell that went past them leaves the count.');
row, count = step(32, { action(MOB, 1, 0, { { FRIEND, 1, 52 } }) });
assert(count == 0, 'A hit got through, so none were left.');
-- Their Blink gives 2, which go as a mob's do, and keeps its own icon. A hit that gets past it leaves it.
row = step(40, { action(FRIEND, 4, 53, { { FRIEND, 230, 36 } }) });
assert(row and row.effect == 36 and row.shadows == 2 and (row.icon or row.effect) == 36, 'Blink starts two: ' .. tostring(row and row.shadows));
row = step(41, { action(MOB, 1, 0, { { FRIEND, 1, 52 } }) });
assert(row and row.effect == 36 and row.shadows == 2, 'A hit that got past it leaves it.');
row = step(42, { action(MOB, 1, 0, { { FRIEND, 31, 1 } }) });
assert(row and row.effect == 36 and row.shadows == 1 and (row.icon or row.effect) == 36, 'One left.');
row, count = step(43, { action(MOB, 1, 0, { { FRIEND, 31, 1 } }) });
assert(count == 0, 'Its last shadow took Blink with it.');
-- A blue mage's Zephyr Mantle puts on Blink with 4.
row = step(50, { action(FRIEND, 4, 647, { { FRIEND, 230, 36 } }) });
assert(row and row.effect == 36 and row.shadows == 4 and (row.icon or row.effect) == 36,
    'Zephyr Mantle starts four: ' .. tostring(row and row.shadows));
row = step(51, { action(MOB, 1, 0, { { FRIEND, 31, 3 } }) });
assert(row and row.effect == 36 and row.shadows == 1, 'Three went.');
row, count = step(52, { action(MOB, 1, 0, { { FRIEND, 31, 1 } }) });
assert(count == 0, 'Its last shadow took Zephyr Mantle\'s Blink with it.');
return 'An alliance member\'s shadows are counted as a mob\'s, and Ni goes by the job the client shows';
