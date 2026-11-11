-- A mob's or a pet's Stoneskin goes at the first hit Vantage sees on it for more than 0 damage, and at spikes that hurt it
-- for more than 0. Phoenix takes Stoneskin's share out of a hit, and out of spike damage from a spell or a roll, before it
-- shows the damage, and a mob's own buff sends its wear-off to no one. Weapon Bash deals its damage straight to HP and an
-- absorbed skillchain heals, so neither says anything about it. Gear spikes show their number from before Stoneskin, so
-- spikes from you or a party member count only while the listing shows a spikes effect. An alliance member's Stoneskin
-- isn't read from hits. Real 0x028s through observer.read.
local observer = require('core.observer');
local catalog = require('core.catalog');
local SELF, ALLY, FRIEND, MOB, PET = 1001, 1002, 1007, 0x1000123, 0x1000124;
local party = { GetMemberMainJob = function() return 1; end, GetMemberZone2 = function() return 0; end,
    GetMemberLastUpdatedTimestamp = function() return 1700000000; end };
AshitaCore.GetMemoryManager = function() return { GetParty = function() return party; end }; end;
-- A listing of these effect ids, as the client reads one.
local function listing(ids)
    local out = {};
    for slot, effect in ipairs(ids or {}) do out[slot] = { effect = effect, slot = slot - 1 }; end
    return out;
end;
-- lists puts effects in your listing and the party member's: { self = { 34 }, ally = { 35 } }.
local function snapshot(lists)
    lists = lists or {};
    return { valid = true, id = SELF, name = 'Tester', zone = 107, job = 8, level = 20, self_known = true, self_revision = 1,
        self_timer_revision = 1, self_effects = listing(lists.self),
        party = { { id = ALLY, name = 'Ally', scope = 'party', group = 1, slot = 1, zone = 107, valid = true, revision = 1,
            effects = listing(lists.ally) },
            { id = FRIEND, name = 'Friend', scope = 'alliance', group = 2, slot = 6, zone = 107, valid = false, effects = {} } },
        entities = { [SELF] = { id = SELF, name = 'Tester', kind = 'player' }, [ALLY] = { id = ALLY, name = 'Ally', kind = 'player' },
            [FRIEND] = { id = FRIEND, name = 'Friend', kind = 'player' }, [MOB] = { id = MOB, name = 'Land Crab', kind = 'monster' },
            [PET] = { id = PET, name = 'Crab Familiar', kind = 'pet' } } };
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
-- Metallic Body, mob skill 448, on its user (message 186, it gains the effect).
local function metallic(who) return action(who, 11, 448, { { who, 186, 37 } }); end
local function hit(events, id)
    for _, event in ipairs(events) do if event.kind == 'damage' and (id == nil or event.entity_id == id) then return event; end end
end

-- The lengths, from Phoenix's data.
assert(catalog.duration('skills', 448, 37) == 300, 'Metallic Body lasts 300 seconds.');
assert(catalog.duration('spells', 54, 37) == 300, 'So does the Stoneskin spell.');

-- Every hit that wakes a mob went through Stoneskin first, at more than 0 (scripts/enum/msg.lua; Sange 77 and Barrage 157 in
-- src/map/enums/msg_basic.h).
for _, message in ipairs({ 1, 2, 67, 77, 110, 157, 163, 185, 187, 227, 229, 252, 264, 317, 352, 353, 379, 576, 577, 747 }) do
    local seen = hit(observer.read(action(ALLY, 1, 0, { { MOB, message, 25 } }), 1, snapshot()));
    assert(seen and seen.entity_id == MOB and seen.unsoaked, 'Message ' .. message .. ' for 25 got through Stoneskin.');
    assert(hit(observer.read(action(ALLY, 1, 0, { { MOB, message, 0 } }), 1, snapshot())) == nil, 'Message ' .. message .. ' for 0 is no hit.');
end;
-- Weapon Bash, ability 77, wakes a mob but deals its damage straight to HP. Jump, ability 66, goes through Stoneskin.
local bash = hit(observer.read(action(ALLY, 6, 77, { { MOB, 110, 21 } }), 1, snapshot()));
assert(bash and not bash.unsoaked, 'Weapon Bash says nothing about Stoneskin.');
local jump = hit(observer.read(action(ALLY, 6, 66, { { MOB, 110, 21 } }), 1, snapshot()));
assert(jump and jump.unsoaked, 'Jump went through it.');
-- Added damage and the drains went through it, after a swing it soaked whole.
for _, added in ipairs({ 161, 162, 163, 165, 229 }) do
    local seen = hit(observer.read(action(SELF, 1, 0, { { MOB, 1, 0, added, 12 } }), 1, snapshot()));
    assert(seen and seen.unsoaked, 'Added ' .. added .. ' for 12 got through.');
end;
-- A skillchain went through it when it dealt damage, and not when it dealt 0 or the mob absorbed it, though both wake.
for _, added in ipairs({ 288, 294, 303 }) do
    local seen = hit(observer.read(action(SELF, 3, 0, { { MOB, 185, 0, added, 40 } }), 1, snapshot()));
    assert(seen and seen.unsoaked, 'Skillchain ' .. added .. ' for 40 got through.');
    seen = hit(observer.read(action(SELF, 3, 0, { { MOB, 185, 0, added, 0 } }), 1, snapshot()));
    assert(seen and not seen.unsoaked, 'Skillchain ' .. added .. ' for 0 did not.');
end;
for _, added in ipairs({ 385, 392, 400 }) do
    local seen = hit(observer.read(action(SELF, 3, 0, { { MOB, 185, 0, added, 40 } }), 1, snapshot()));
    assert(seen and not seen.unsoaked, 'Absorbed skillchain ' .. added .. ' did not.');
end;
-- A counter for more than 0 went through it, and so did a hit on a pet.
local countered = hit(observer.read(action(MOB, 1, 0, { { ALLY, 15, 0, nil, nil, 33, 20 } }), 1, snapshot()));
assert(countered and countered.entity_id == MOB and countered.unsoaked, 'A counter got through.');
local bitten = hit(observer.read(action(MOB, 1, 0, { { PET, 1, 40 } }), 1, snapshot()));
assert(bitten and bitten.scope == 'pet' and bitten.unsoaked, 'So did a hit on a pet.');
-- Spikes for more than 0 went through the attacker's Stoneskin, and they're all that hurt it: spikes on you or a party
-- member with Blaze, Ice or Shock Spikes, Dread Spikes or Gallant's Roll listed, and spikes on a mob or a pet, which have
-- no gear.
local function spikes(target, reaction, param) return action(MOB, 1, 0, { { target, 1, 30, nil, nil, reaction, param } }); end
for _, effect in ipairs({ 34, 35, 38, 173, 316 }) do
    local seen = hit(observer.read(spikes(SELF, 44, 12), 1, snapshot({ self = { 40, effect } })));
    assert(seen and seen.entity_id == MOB and seen.unsoaked and seen.spikes_only, 'Spikes with ' .. effect .. ' on you got through.');
    seen = hit(observer.read(spikes(ALLY, 44, 12), 1, snapshot({ ally = { effect } })));
    assert(seen and seen.entity_id == MOB and seen.unsoaked and seen.spikes_only, 'And with ' .. effect .. ' on a party member.');
end;
local drained = hit(observer.read(spikes(SELF, 132, 9), 1, snapshot({ self = { 173 } })));
assert(drained and drained.entity_id == MOB and drained.unsoaked and drained.spikes_only, 'Dread Spikes draining 9 got through.');
local round = observer.read(action(PET, 1, 0, { { MOB, 1, 30, nil, nil, 44, 15 } }), 1, snapshot());
local pet_spiked, mob_hit = hit(round, PET), hit(round, MOB);
assert(pet_spiked and pet_spiked.scope == 'pet' and pet_spiked.unsoaked and pet_spiked.spikes_only, 'A mob\'s spikes got through your pet\'s.');
assert(mob_hit and mob_hit.unsoaked and not mob_hit.spikes_only, 'Your pet\'s swing on the mob is a hit.');
local mob_spiked = hit(observer.read(spikes(PET, 44, 15), 1, snapshot()), MOB);
assert(mob_spiked and mob_spiked.unsoaked and mob_spiked.spikes_only, 'Your pet\'s spikes got through a mob\'s.');
-- A counter beside spikes in one round is a hit, in either order.
local both = hit(observer.read(action(MOB, 1, 0, { { SELF, 1, 30, nil, nil, 44, 12 }, { SELF, 15, 0, nil, nil, 33, 20 } }), 1,
    snapshot({ self = { 34 } })));
assert(both and both.through and both.unsoaked and not both.spikes_only, 'A counter after spikes is a hit.');
both = hit(observer.read(action(MOB, 1, 0, { { SELF, 15, 0, nil, nil, 33, 20 }, { SELF, 1, 30, nil, nil, 44, 12 } }), 1,
    snapshot({ self = { 34 } })));
assert(both and both.through and not both.spikes_only, 'So is one before them.');
-- Spikes for 0, spikes that healed (383) or gave a status (374), gear spikes with no spikes effect listed, and an alliance
-- member's spikes, whose listing the game doesn't send, say nothing.
for _, case in ipairs({
    { 'Spikes for 0', spikes(SELF, 44, 0), { self = { 34 } } },
    { 'Spikes that healed', spikes(SELF, 383, 12), { self = { 34 } } },
    { 'Status spikes', spikes(SELF, 374, 4), { self = { 34 } } },
    { 'Gear spikes on you', spikes(SELF, 44, 12), { self = { 40 }, ally = { 34 } } },
    { 'Gear spikes on a party member', spikes(ALLY, 44, 12), { self = { 34 } } },
    { 'An alliance member\'s spikes', spikes(FRIEND, 44, 12), { self = { 34 }, ally = { 34 } } },
}) do
    assert(hit(observer.read(case[2], 1, snapshot(case[3])), MOB) == nil, case[1] .. ' say nothing.');
end;

-- The tracker.
local tracker = require('core.tracker').new();
local function step(now, packets, lists)
    local snap, observations = snapshot(lists), {};
    for _, packet in ipairs(packets) do for _, o in ipairs(observer.read(packet, now, snap)) do observations[#observations + 1] = o; end end
    tracker:observe(observations, now, snap); tracker:reconcile(snap, now);
    return tracker:view(now, {}, snap).rows, tracker:drain_events();
end;
local function find(rows, id, effect)
    for _, row in ipairs(rows) do if row.entity_id == id and row.effect == effect then return row; end end
end;
local function removed(events, id, effect)
    for _, event in ipairs(events) do
        if event.kind == 'removed' and event.entity_id == id and event.effect == effect then return event; end
    end
end;
local USED_UP = 'Damage got through, so its Stoneskin was used up.';
-- A mob's Metallic Body counts down its 300 seconds. A miss, a hit for 0, Weapon Bash, a skillchain for 0 and one it
-- absorbed leave it.
local rows, events = step(10, { metallic(MOB) });
local row = find(rows, MOB, 37);
assert(row and row.total == 300 and row.remaining == 300 and row.scope == 'enemy', 'Metallic Body counts down 300 seconds.');
rows, events = step(11, { action(ALLY, 1, 0, { { MOB, 15, 0 } }), action(ALLY, 1, 0, { { MOB, 1, 0 } }), action(ALLY, 6, 77, { { MOB, 110, 21 } }),
    action(SELF, 3, 0, { { MOB, 185, 0, 288, 0 } }), action(SELF, 3, 0, { { MOB, 185, 0, 390, 60 } }) });
assert(find(rows, MOB, 37) and not removed(events, MOB, 37), 'A miss, a hit for 0, Weapon Bash and those skillchains leave it.');
-- The first hit for more than 0 takes it off, and the mob's other effects stay.
tracker:observe({ { kind = 'apply', entity_id = MOB, effect = 40, source = MOB, scope = 'enemy', duration = 600 } }, 12, snapshot());
rows, events = step(13, { action(ALLY, 1, 0, { { MOB, 1, 0 }, { MOB, 1, 15 } }) });
local gone = removed(events, MOB, 37);
assert(not find(rows, MOB, 37) and gone and gone.reason == USED_UP, 'The first hit for more than 0 takes it off.');
assert(find(rows, MOB, 40), 'Protect stays.');
-- A counter, added damage, a spell, a skillchain that dealt damage and Jump each take it off too.
local takers = {
    { 'A counter', action(MOB, 1, 0, { { ALLY, 15, 0, nil, nil, 33, 20 } }) },
    { 'Added damage', action(SELF, 1, 0, { { MOB, 1, 0, 163, 12 } }) },
    { 'A spell', action(ALLY, 4, 144, { { MOB, 2, 80 } }) },
    { 'A skillchain', action(SELF, 3, 0, { { MOB, 185, 0, 288, 40 } }) },
    { 'Jump', action(ALLY, 6, 66, { { MOB, 110, 30 } }) },
};
for i, taker in ipairs(takers) do
    local at = 20 + i * 2;
    assert(find(step(at, { metallic(MOB) }), MOB, 37), 'Fixture: Metallic Body again.');
    rows, events = step(at + 1, { taker[2] });
    gone = removed(events, MOB, 37);
    assert(not find(rows, MOB, 37) and gone and gone.reason == USED_UP, taker[1] .. ' takes it off.');
end;
-- Stoneskin a mob casts on itself goes the same way.
rows = step(40, { action(MOB, 4, 54, { { MOB, 230, 37 } }) });
assert(find(rows, MOB, 37) and find(rows, MOB, 37).total == 300, 'A mob\'s Stoneskin spell counts down 300 seconds.');
rows, events = step(41, { action(ALLY, 2, 0, { { MOB, 352, 18 } }) });
assert(not find(rows, MOB, 37) and removed(events, MOB, 37), 'A ranged hit takes it off.');
-- One whose estimate ran out shows with no countdown, and a hit still takes it off.
step(50, { metallic(MOB) });
rows = step(360, {});
row = find(rows, MOB, 37);
assert(row and row.status == 'unknown', 'Its estimate ran out, and it shows with no countdown.');
rows, events = step(361, { action(ALLY, 1, 0, { { MOB, 1, 15 } }) });
assert(not find(rows, MOB, 37) and removed(events, MOB, 37), 'A hit takes it off.');

-- A pet's goes at a hit on it too.
rows = step(400, { metallic(PET) });
row = find(rows, PET, 37);
assert(row and row.total == 300 and row.scope == 'pet', 'A pet\'s Metallic Body.');
rows = step(401, { action(MOB, 1, 0, { { PET, 1, 0 } }) });
assert(find(rows, PET, 37), 'A hit for 0 on it leaves it.');
rows, events = step(402, { action(MOB, 1, 0, { { PET, 1, 40 } }) });
gone = removed(events, PET, 37);
assert(not find(rows, PET, 37) and gone and gone.reason == USED_UP, 'A hit for 40 takes it off.');

-- Spikes take a mob's off: yours, a party member's, and a mob's own spikes take your pet's. Spikes for 0, gear spikes and an
-- alliance member's leave it.
assert(find(step(410, { metallic(MOB) }), MOB, 37), 'Fixture: Metallic Body again.');
rows, events = step(411, { spikes(SELF, 44, 0), spikes(ALLY, 44, 12), spikes(FRIEND, 44, 12) }, { self = { 34 } });
assert(find(rows, MOB, 37) and not removed(events, MOB, 37), 'Spikes for 0, gear spikes and an alliance member\'s leave it.');
rows, events = step(412, { spikes(SELF, 44, 12) }, { self = { 34 } });
gone = removed(events, MOB, 37);
assert(not find(rows, MOB, 37) and gone and gone.reason == USED_UP, 'Your Blaze Spikes for 12 take it off.');
assert(find(step(413, { metallic(MOB) }), MOB, 37), 'Fixture: Metallic Body again.');
rows, events = step(414, { spikes(ALLY, 132, 9) }, { ally = { 173 } });
assert(not find(rows, MOB, 37) and removed(events, MOB, 37), 'A party member\'s Dread Spikes draining 9 take it off.');
assert(find(step(415, { metallic(PET) }), PET, 37), 'Fixture: your pet\'s Metallic Body.');
rows, events = step(416, { action(PET, 1, 0, { { MOB, 1, 0, nil, nil, 44, 15 } }) });
gone = removed(events, PET, 37);
assert(not find(rows, PET, 37) and gone and gone.reason == USED_UP, 'A mob\'s spikes for 15 take your pet\'s off.');

-- An alliance member's own Stoneskin isn't read from hits, so it keeps its time.
rows = step(500, { action(FRIEND, 4, 54, { { FRIEND, 230, 37 } }) });
row = find(rows, FRIEND, 37);
assert(row and row.scope == 'alliance', 'An alliance member\'s Stoneskin.');
rows, events = step(501, { action(MOB, 1, 0, { { FRIEND, 1, 40 } }) });
assert(find(rows, FRIEND, 37) and not removed(events, FRIEND, 37), 'A hit on them leaves it.');
return 'A mob\'s or a pet\'s Stoneskin goes at the first hit or spikes Vantage sees for more than 0, but not at Weapon Bash, an absorbed skillchain or gear spikes';
