-- A hit for more than 0 that Vantage sees takes a mob's Sleep, Sleep II and Lullaby off, as every Phoenix damage
-- path does, skillchains and counters included. Bind stays but loses its time, since Phoenix breaks it at 95 hits in
-- 100. Spikes are no hit, so they leave both. Nothing else changes, and only a mob's or a pet's effects: the player and
-- the party are read from their listings. Real 0x028s through observer.read.
local observer = require('core.observer');
local hud = require('ui.hud');
local SELF, ALLY, MOB, PET = 1001, 1002, 0x1000123, 0x1000124;
-- The client's names for the two the catalog leaves out.
AshitaCore.GetResourceManager = function() return { GetString = function(_, kind, id)
    return kind == 'buffs.names' and ({ [19] = 'sleep', [193] = 'lullaby' })[id] or nil;
end }; end;
-- The party member's listing, when a test gives one.
local function snapshot(listed)
    return { valid = true, id = SELF, name = 'Tester', zone = 102, job = 4, level = 75, self_known = true, self_revision = 1,
        self_timer_revision = 1, self_effects = {}, party = { { id = ALLY, name = 'Ally', scope = 'party', effects = listed } },
        entities = { [SELF] = { id = SELF, name = 'Tester', kind = 'player' }, [ALLY] = { id = ALLY, name = 'Ally', kind = 'player' },
            [MOB] = { id = MOB, name = 'Goblin', kind = 'monster' }, [PET] = { id = PET, name = 'Carbuncle', kind = 'pet' } },
        target = { id = MOB, name = 'Goblin', kind = 'monster' } };
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
local function wearoff(actor, target, icon)
    local bytes = MOCK.bytes(28);
    MOCK.put(bytes, 4, 4, actor); MOCK.put(bytes, 8, 4, target); MOCK.put(bytes, 12, 4, icon); MOCK.put(bytes, 24, 2, 204);
    return MOCK.packet(0x029, bytes);
end
local function hits(events)
    local count = 0;
    for _, event in ipairs(events) do if event.kind == 'damage' then count = count + 1; end end
    return count;
end

-- Every damage path's message wakes, at more than 0 damage only (scripts/enum/msg.lua; Sange 77 and Barrage 157 in
-- src/map/enums/msg_basic.h).
for _, message in ipairs({ 1, 2, 67, 77, 110, 157, 163, 185, 187, 227, 229, 252, 264, 317, 352, 353, 379, 576, 577, 747 }) do
    local events = observer.read(action(ALLY, 1, 0, { { MOB, message, 25 } }), 1, snapshot());
    assert(hits(events) == 1, 'Message ' .. message .. ' for 25 is a hit.');
    local event = events[#events];
    assert(event.kind == 'damage' and event.entity_id == MOB and event.source == ALLY and event.scope == 'enemy');
    assert(hits(observer.read(action(ALLY, 1, 0, { { MOB, message, 0 } }), 1, snapshot())) == 0, 'Message ' .. message .. ' for 0 is no hit.');
end;
-- Barrage and Sange shots finish as a ranged attack, each row with the ability's message and its damage
-- (src/map/entities/battle_entity.cpp :3393-3398, :3485-3490).
for _, message in ipairs({ 77, 157 }) do
    assert(hits(observer.read(action(ALLY, 2, 0, { { MOB, message, 120 } }), 1, snapshot())) == 1, 'A shot with message ' .. message .. ' is a hit.');
end;
-- A miss, shadows taking it, a ranged miss, an MP drain spell and a resist hit nothing.
for _, message in ipairs({ 15, 31, 354, 228, 85 }) do
    assert(hits(observer.read(action(ALLY, 1, 0, { { MOB, message, 25 } }), 1, snapshot())) == 0, 'Message ' .. message .. ' is no hit.');
end;
-- Added damage and the drains hit at more than 0; a skillchain hits whatever it deals, absorbed too.
for _, added in ipairs({ 161, 162, 163, 165, 229 }) do
    assert(hits(observer.read(action(SELF, 1, 0, { { MOB, 15, 0, added, 12 } }), 1, snapshot())) == 1, 'Added ' .. added .. ' hits.');
    assert(hits(observer.read(action(SELF, 1, 0, { { MOB, 15, 0, added, 0 } }), 1, snapshot())) == 0, 'Added ' .. added .. ' for 0 does not.');
end;
for _, added in ipairs({ 288, 294, 301, 385, 398 }) do
    assert(hits(observer.read(action(SELF, 3, 0, { { MOB, 185, 0, added, 0 } }), 1, snapshot())) == 1, 'Skillchain ' .. added .. ' hits.');
end;
assert(hits(observer.read(action(SELF, 1, 0, { { MOB, 1, 30, 163, 12 } }), 1, snapshot())) == 1, 'A row with two kinds of damage is one hit.');
assert(hits(observer.read(action(SELF, 1, 0, { { MOB, 1, 30 }, { MOB, 67, 50 } }), 1, snapshot())) == 1, 'An action that hits a mob twice is one hit.');
assert(hits(observer.read(action(SELF, 1, 0, { { MOB, 15, 0, 160, 4 } }), 1, snapshot())) == 0, 'An added effect that lands is no hit.');
-- Only mobs and pets: a hit on you or a party member is left to their own listings. A pet has none, so its hit counts.
for _, target in ipairs({ SELF, ALLY }) do
    assert(hits(observer.read(action(MOB, 1, 0, { { target, 1, 40 } }), 1, snapshot())) == 0, 'A hit on ' .. target .. ' is not counted.');
end;
local bitten = observer.read(action(MOB, 1, 0, { { PET, 1, 40 } }), 1, snapshot());
assert(hits(bitten) == 1 and bitten[1].entity_id == PET and bitten[1].scope == 'pet', 'A hit on a pet is counted.');
assert(hits(observer.read(action(MOB, 1, 0, { { PET, 1, 0 } }), 1, snapshot())) == 0, 'A hit on a pet for 0 is not.');
-- A counter hits the mob that attacked (message 33 in the reaction slot, battle_entity.cpp :3781-3783), at more than
-- 0. Spikes (44) deal their damage without waking or breaking Bind (CBattleEntity::takeDamage), so the mob's damage from a
-- party member's Blaze Spikes comes marked as spikes only, and a mob's counter on you is left to your listing.
local countered = observer.read(action(MOB, 1, 0, { { ALLY, 15, 0, nil, nil, 33, 20 } }), 1, snapshot());
assert(hits(countered) == 1 and countered[1].entity_id == MOB and countered[1].source == ALLY, 'A counter is a hit on the mob.');
assert(hits(observer.read(action(MOB, 1, 0, { { ALLY, 15, 0, nil, nil, 33, 0 } }), 1, snapshot())) == 0, 'A counter for 0 is no hit.');
local BLAZE = { { effect = 34, slot = 0 } };
local spiked = observer.read(action(MOB, 1, 0, { { ALLY, 1, 30, nil, nil, 44, 20 } }), 1, snapshot(BLAZE));
assert(hits(spiked) == 1 and spiked[1].entity_id == MOB and spiked[1].spikes_only, 'Spikes are no hit.');
assert(hits(observer.read(action(SELF, 1, 0, { { MOB, 15, 0, nil, nil, 33, 20 } }), 1, snapshot())) == 0, "A mob's counter on you is not counted.");

-- The tracker: your Sleep II, Paralyze and Bind on the mob, then the hits.
local tracker = require('core.tracker').new();
local function step(now, packets, listed)
    local snap, observations = snapshot(listed), {};
    for _, packet in ipairs(packets) do for _, o in ipairs(observer.read(packet, now, snap)) do observations[#observations + 1] = o; end end
    tracker:observe(observations, now, snap); tracker:reconcile(snap, now);
    local rows = {};
    local view = tracker:view(now, {}, snap);
    for _, row in ipairs(view.rows) do if row.entity_id == MOB then rows[row.effect] = row; end end
    return rows, tracker:drain_events();
end;
local function removed(events, effect)
    for _, event in ipairs(events) do if event.kind == 'removed' and event.effect == effect then return event; end end
end;
local rows = step(10, { action(SELF, 4, 259, { { MOB, 236, 2 } }), action(SELF, 4, 58, { { MOB, 236, 4 } }),
    action(SELF, 4, 258, { { MOB, 236, 11 } }) });
assert(rows[2] and rows[4] and rows[11] and rows[11].deadline and rows[4].deadline, 'Fixture: Sleep, Paralysis and Bind are on the mob.');
local events;
rows, events = step(11, { action(ALLY, 1, 0, { { MOB, 1, 0 } }), action(ALLY, 1, 0, { { MOB, 15, 0 } }) });
assert(rows[2] and rows[11].deadline and #events == 0, 'A hit for 0 and a miss change nothing.');
rows, events = step(12, { action(ALLY, 1, 0, { { MOB, 1, 31 } }) });
assert(rows[2] == nil, 'The first hit for more than 0 takes Sleep off.');
local gone = removed(events, 2);
assert(gone and gone.reason == 'Damage was observed.', 'Its removal says what took it.');
assert(rows[4] and rows[4].deadline and rows[4].status == 'estimated', 'Paralysis keeps its time: it has no damage flag.');
assert(rows[11] and rows[11].deadline == nil and rows[11].status == 'unknown', 'Bind stays, with no time.');
assert(hud.timer_text(rows[11], 12) == '', 'Bind shows no countdown.');
assert(rows[11].reason:find('Bind can break at any hit', 1, true), 'Its details say why.');
for _, word in ipairs({ 'unknown', 'Unknown', '?' }) do assert(not rows[11].reason:find(word, 1, true), 'No ' .. word .. ' in its details.'); end;
rows, events = step(13, { action(ALLY, 1, 0, { { MOB, 1, 31 } }) });
assert(rows[11] and rows[4].deadline and #events == 0, 'Later hits change nothing more.');
-- A new Bind, then the mob's attack is countered: the counter is a hit on it.
rows = step(14, { action(SELF, 4, 258, { { MOB, 236, 11 } }) });
assert(rows[11] and rows[11].deadline, 'Fixture: Bind again, with a time.');
rows = step(15, { action(MOB, 1, 0, { { ALLY, 15, 0, nil, nil, 33, 20 } }) });
assert(rows[11] and rows[11].deadline == nil, 'Bind loses its time at a counter.');
-- A new Sleep and Bind keep their time when the mob's only damage is from a party member's Blaze Spikes.
rows = step(16, { action(SELF, 4, 253, { { MOB, 236, 2 } }), action(SELF, 4, 258, { { MOB, 236, 11 } }) });
assert(rows[2] and rows[11] and rows[11].deadline, 'Fixture: Sleep and Bind again, with a time.');
rows, events = step(17, { action(MOB, 1, 0, { { ALLY, 1, 30, nil, nil, 44, 20 } }) }, BLAZE);
assert(rows[2] and rows[11] and rows[11].deadline and not removed(events, 2), 'Spikes leave both.');
-- A hit, then a new Sleep in the same row as an added effect: Phoenix deals the damage first, so the new Sleep stays.
rows = step(20, { action(SELF, 4, 253, { { MOB, 236, 2 } }) });
assert(rows[2], 'Fixture: Sleep again.');
rows, events = step(21, { action(SELF, 1, 0, { { MOB, 1, 40, 160, 2 } }) });
assert(removed(events, 2) and rows[2] and rows[2].first_seen == 21, 'The hit takes the old Sleep off and the added effect puts a new one on.');
-- Sleep II and Lullaby leave too; an effect with no damage flag stays.
local flagged = { 19, 193 };
local observations = {};
for _, effect in ipairs(flagged) do observations[#observations + 1] = { kind = 'apply', entity_id = MOB, effect = effect, source = SELF, scope = 'enemy', duration = 60 }; end;
observations[#observations + 1] = { kind = 'apply', entity_id = MOB, effect = 40, source = MOB, scope = 'enemy', duration = 600 };
tracker:observe(observations, 30, snapshot());
rows, events = step(31, { action(ALLY, 2, 0, { { MOB, 352, 18 } }) });
for _, effect in ipairs(flagged) do assert(rows[effect] == nil and removed(events, effect), 'A hit takes off ' .. effect .. '.'); end;
assert(rows[40] and rows[40].deadline, 'Protect, with no damage flag, stays.');
-- A wear-off before the hit (Phoenix sends the caster's at once) leaves one removal.
rows = step(40, { action(SELF, 4, 253, { { MOB, 236, 2 } }) });
rows, events = step(41, { wearoff(SELF, MOB, 2), action(ALLY, 1, 0, { { MOB, 1, 31 } }) });
local count = 0;
for _, event in ipairs(events) do if event.kind == 'removed' and event.effect == 2 then count = count + 1; end end;
assert(rows[2] == nil and count == 1, 'One removal: the wear-off took it, and the hit found nothing.');

-- A party member's Sleep is read from their listing: a damage observation for them changes nothing.
local party = require('core.tracker').new();
party:observe({ { kind = 'apply', entity_id = ALLY, effect = 2, source = MOB, scope = 'party', duration = 30 } }, 1, snapshot());
party:observe({ { kind = 'damage', entity_id = ALLY, source = MOB, scope = 'party' } }, 2, snapshot());
local kept = false;
for _, row in ipairs(party:view(2, {}, snapshot()).rows) do kept = kept or row.entity_id == ALLY and row.effect == 2; end;
assert(kept, 'Only a mob\'s effects leave at a hit.');
return 'Sleep and the other damage-marked effects leave a mob at the first hit Vantage sees; Bind loses its time';
