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
local function putbits(bytes, offset, length, value)
    for i = 0, length - 1 do
        local at = offset + i;
        if math.floor(value / 2 ^ i) % 2 == 1 then bytes[math.floor(at / 8)] = bytes[math.floor(at / 8)] + 2 ^ (at % 8); end
    end
end
-- One target row: { target, message, param, added, added_param, reaction, reaction_param }.
local function action(actor, category, id, rows)
    local bytes, at = MOCK.bytes(2048), 150;
    putbits(bytes, 40, 32, actor); putbits(bytes, 72, 6, #rows); putbits(bytes, 82, 4, category); putbits(bytes, 86, 32, id);
    for _, row in ipairs(rows) do
        putbits(bytes, at, 32, row[1]); putbits(bytes, at + 32, 4, 1); at = at + 36;
        putbits(bytes, at + 27, 17, row[3] or 0); putbits(bytes, at + 44, 10, row[2] or 0); at = at + 85;
        putbits(bytes, at, 1, row[4] and 1 or 0); at = at + 1;
        if row[4] then putbits(bytes, at + 10, 17, row[5] or 0); putbits(bytes, at + 27, 10, row[4]); at = at + 37; end
        putbits(bytes, at, 1, row[6] and 1 or 0); at = at + 1;
        if row[6] then putbits(bytes, at + 10, 14, row[7] or 0); putbits(bytes, at + 24, 10, row[6]); at = at + 34; end
    end
    bytes.n = math.ceil(at / 8);
    return MOCK.packet(0x028, bytes);
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
return 'An alliance member\'s shadows are counted as a mob\'s, and Ni goes by the job the client shows';
