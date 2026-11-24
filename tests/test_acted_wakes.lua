-- A mob or a pet that finishes an action has nothing on it that stops a unit acting: Sleep, Sleep II, Lullaby,
-- Petrification, Stun and Terror (Phoenix HasPreventActionEffect, src/map/status_effect_container.cpp :2176-2186). The
-- game sends you no wear-off for an effect a monster put on your pet, so the pet's next swing, spell or move is the
-- sign it is over. Real 0x028s through observer.read and the tracker.
local observer, tracker = require('core.observer'), require('core.tracker');
local SELF, ALLY, MOB, PET, SHEEP = 1001, 1002, 0x1000123, 0x1000801, 0x1000124;
AshitaCore.GetResourceManager = function() return { GetString = function(_, kind, id)
    return kind == 'buffs.names' and ({ [19] = 'sleep', [193] = 'lullaby' })[id] or nil;
end }; end;
local snapshot = { valid = true, id = SELF, name = 'Tester', zone = 102, job = 14, level = 75, self_known = true, self_revision = 1,
    self_timer_revision = 1, self_effects = {}, party = { { id = ALLY, name = 'Ally', scope = 'party', effects = {} } },
    pet = { id = PET, index = 0x701, name = 'Wyvern', kind = 'pet' },
    entities = { [SELF] = { id = SELF, name = 'Tester', kind = 'player' }, [ALLY] = { id = ALLY, name = 'Ally', kind = 'player' },
        [MOB] = { id = MOB, name = 'Goblin', kind = 'monster' }, [SHEEP] = { id = SHEEP, name = 'Sheep', kind = 'monster' },
        [PET] = { id = PET, name = 'Wyvern', kind = 'pet' } } };
-- One action: its actor, category and id, and each target as { id, message, param }.
local function action(actor, category, id, rows)
    local targets = {};
    for i, row in ipairs(rows) do targets[i] = { id = row[1], rows = { { message = row[2], param = row[3] } } }; end
    return MOCK.packet(0x028, MOCK.action_bytes(actor, category, id, targets));
end
local settings = { tracking = { max_entities = 64, stale_seconds = 180 } };
local model = tracker.new();
model:reconcile(snapshot, 0);
local clock = 0;
local function feed(e)
    clock = clock + 1;
    local events = observer.read(e, clock, snapshot);
    model:observe(events, clock, snapshot);
    return events;
end
local function shown(unit)
    local out = {};
    for _, row in ipairs(model:view(clock, settings, snapshot).rows) do
        if row.entity_id == unit then out[#out + 1] = row.effect; end
    end
    table.sort(out);
    return table.concat(out, ' ');
end
local function acted(events)
    local count = 0;
    for _, event in ipairs(events) do if event.kind == 'acted' then count = count + 1; end end
    return count;
end

-- Only a unit seen to take such an effect is read for this, so a fight with none of them costs nothing more.
assert(acted(feed(action(PET, 1, 0, { { SHEEP, 1, 30 } }))) == 0 and acted(feed(action(SHEEP, 1, 0, { { PET, 1, 30 } }))) == 0,
    'A swing from a unit with nothing of the kind on it says nothing.');
-- A sheep's Sheep Song, monster move 264, puts your pet to sleep for 45 seconds at most.
feed(action(SHEEP, 11, 264, { { PET, 242, 2 } }));
assert(shown(PET) == '2', 'Fixture: the pet is asleep: ' .. shown(PET));
-- Its estimate runs out with no word of the wear-off, which only the sheep gets. The row stays, with no countdown.
clock = clock + 60;
assert(shown(PET) == '2', 'Fixture: past its estimate the sleep still shows.');
-- The pet swings: it is awake.
local events = feed(action(PET, 1, 0, { { SHEEP, 1, 30 } }));
assert(acted(events) == 1 and events[1].kind == 'acted' and events[1].entity_id == PET and events[1].scope == 'pet', 'A pet\'s swing says it acted, first of all.');
assert(shown(PET) == '', 'A pet that swings isn\'t asleep: ' .. shown(PET));
assert(acted(feed(action(PET, 1, 0, { { SHEEP, 1, 30 } }))) == 0, 'Its next swing says nothing more.');
-- A swing that misses is a swing too, and so are a spell, a move, an ability and a blood pact.
for _, finish in ipairs({ { 1, 15 }, { 2, 352 }, { 3, 185 }, { 4, 2 }, { 6, 100 }, { 11, 185 }, { 13, 317 } }) do
    feed(action(SHEEP, 11, 264, { { PET, 242, 2 } }));
    assert(shown(PET) == '2', 'Fixture: asleep again.');
    feed(action(PET, finish[1], 30, { { SHEEP, finish[2], 20 } }));
    assert(shown(PET) == '', 'A pet that finishes an action of category ' .. finish[1] .. ' isn\'t asleep: ' .. shown(PET));
end
-- The start of your pet's spell or move is no finished action: one that falls asleep in the middle sends the same
-- packet as it is cut short.
feed(action(SHEEP, 11, 264, { { PET, 242, 2 } }));
-- Readies a move (43), starts casting (327), a cast cut short, and a ranged attack begun.
for _, start in ipairs({ { 7, 43, 24931 }, { 8, 327, 24931 }, { 8, 0, 28787 }, { 12, 0, 24931 } }) do
    assert(acted(feed(action(PET, start[1], 30, { { SHEEP, start[2], start[3] } }))) == 0,
        'A start of category ' .. start[1] .. ' with message ' .. start[2] .. ' is no action finished.');
end
assert(shown(PET) == '2', 'The pet is still asleep after a start: ' .. shown(PET));
-- Three packets a unit can send while it still can't act. A cast it started before it fell asleep ends in "is
-- paralyzed" (84) or "is intimidated" (106) when that roll comes first (Phoenix src/map/ai/states/magic_state.cpp
-- :264-293), and a mob's script sends its own packets, with no message, whatever state the mob is in
-- (CLuaBaseEntity::injectActionPacket, as Promyvion's Wailers do every 30 seconds).
for _, still in ipairs({ { 4, 84 }, { 4, 106 }, { 11, 0 } }) do
    assert(acted(feed(action(PET, still[1], 30, { { SHEEP, still[2], 0 } }))) == 0,
        'A packet of category ' .. still[1] .. ' with message ' .. still[2] .. ' is no action finished.');
end
assert(shown(PET) == '2', 'The pet is still asleep after those: ' .. shown(PET));
feed(action(PET, 1, 0, { { SHEEP, 1, 30 } }));
assert(shown(PET) == '', 'And its next real swing still wakes it.');

-- Every effect that stops a unit acting goes, on a mob as on a pet, and nothing else does.
for _, effect in ipairs({ 2, 19, 193, 7, 10, 28 }) do
    feed(action(ALLY, 4, 253, { { MOB, 237, effect } }));
    feed(action(ALLY, 4, 58, { { MOB, 237, 4 } }));
    feed(action(ALLY, 4, 258, { { MOB, 237, 11 } }));
    assert(shown(MOB):find('%f[%d]' .. effect .. '%f[%D]'), 'Fixture: effect ' .. effect .. ' is on the mob: ' .. shown(MOB));
    feed(action(MOB, 1, 0, { { ALLY, 1, 40 } }));
    assert(shown(MOB) == '4 11', 'A mob that swings has no effect ' .. effect .. ', and keeps its Paralysis and Bind: ' .. shown(MOB));
end
-- Another unit's action changes nothing, and a player's says nothing of this: their listings are read.
feed(action(ALLY, 4, 253, { { MOB, 237, 2 } }));
feed(action(SHEEP, 1, 0, { { ALLY, 1, 40 } }));
assert(shown(MOB) == '2 4 11', 'Another mob\'s swing leaves this one asleep: ' .. shown(MOB));
assert(acted(feed(action(ALLY, 1, 0, { { SHEEP, 1, 40 } }))) == 0, 'A party member\'s swing is not read for this.');
assert(acted(feed(action(SELF, 1, 0, { { SHEEP, 1, 40 } }))) == 0, 'Nor is yours.');
-- What an action puts on its own user comes after the action, so it stays: a mob asleep that wakes and uses a move
-- that puts Terror on itself has the Terror and no Sleep.
feed(action(MOB, 11, 500, { { MOB, 242, 28 } }));
assert(shown(MOB) == '4 11 28', 'An effect from the unit\'s own action stays: ' .. shown(MOB));
-- A wake seen this way teaches no time, not even for a Sleep of your own: nothing says when the effect ended.
feed(action(SELF, 4, 253, { { SHEEP, 237, 2 } }));
assert(shown(SHEEP) == '2', 'Fixture: your own Sleep on a mob.');
clock = clock + 20;
feed(action(SHEEP, 1, 0, { { ALLY, 1, 40 } }));
assert(shown(SHEEP) == '', 'The mob swung, so your Sleep was over.');
assert(#model:samples(clock + 5) == 0, 'Nothing is learned from it.');
-- Players aren't kept for this, however many are put to sleep: 70 of them leave the pet's own sleep to end at its swing.
feed(action(SHEEP, 11, 264, { { PET, 242, 2 } }));
for player = 2000, 2069 do feed(action(SHEEP, 4, 253, { { player, 237, 2 } })); end
assert(acted(feed(action(PET, 1, 0, { { SHEEP, 1, 30 } }))) == 1 and shown(PET) == '', 'Players asleep crowd no mob or pet out.');
-- A unit that dies or leaves view is forgotten, so the next one with its id says nothing.
local function died(unit)
    local bytes = MOCK.bytes(28);
    MOCK.put(bytes, 4, 4, SELF); MOCK.put(bytes, 8, 4, unit); MOCK.put(bytes, 24, 2, 6);
    return MOCK.packet(0x029, bytes);
end
local function left(unit)
    local bytes = MOCK.bytes(16);
    MOCK.put(bytes, 4, 4, unit); MOCK.put(bytes, 10, 1, 0x20);
    return MOCK.packet(0x00E, bytes);
end
feed(action(ALLY, 4, 253, { { SHEEP, 237, 2 } }));
feed(died(SHEEP));
assert(acted(feed(action(SHEEP, 1, 0, { { ALLY, 1, 40 } }))) == 0, 'A unit that died asleep is forgotten.');
feed(action(ALLY, 4, 253, { { SHEEP, 237, 2 } }));
feed(left(SHEEP));
assert(acted(feed(action(SHEEP, 1, 0, { { ALLY, 1, 40 } }))) == 0, 'So is one that left view.');
-- A zone change forgets who was seen to take one.
feed(action(SHEEP, 11, 264, { { PET, 242, 2 } }));
observer.read(MOCK.packet(0x00A, MOCK.bytes(64)), clock, snapshot);
assert(acted(observer.read(action(PET, 1, 0, { { SHEEP, 1, 30 } }), clock, snapshot)) == 0, 'After a zone change a swing says nothing.');
-- A pet under one of them can't move either: Phoenix holds it still (src/map/ai/controllers/pet_controller.cpp
-- :65-68, src/map/ai/states/inactive_state.cpp :75-83). A second after the newest one lands, the pet's place is kept,
-- and a pet then a yalm or more from there is awake, though it did nothing. The place the snapshot gives is the
-- client's (core/client.lua read_pet).
local pet = snapshot.pet;
local function at(time, x, y, z)
    clock = time;
    pet.x, pet.y, pet.z = x, y, z;
    model:reconcile(snapshot, clock);
end
pet.x, pet.y, pet.z = 10, 20, 0;
feed(action(SHEEP, 11, 264, { { PET, 242, 2 } }));
local slept = clock;
at(slept + 0.5, 10.8, 20, 0);
assert(shown(PET) == '2', 'Fixture: asleep.');
at(slept + 1, 10, 20, 0);
at(slept + 2, 10.5, 20.5, 0.5);
assert(shown(PET) == '2', 'A step the client was still drawing, and under a yalm from its place, is no wake: ' .. shown(PET));
at(slept + 3, nil, nil, nil);
at(slept + 30, 10, 20, 0);
assert(shown(PET) == '2', 'A pet the game stops showing keeps its place, and is asleep where it was.');
at(slept + 31, 11, 20, 0);
assert(shown(PET) == '', 'A pet a yalm from its place is awake: ' .. shown(PET));
-- Another sleep after it acted, somewhere else, keeps its own place: the pet isn't read against the old one, though
-- that one was kept and nothing was read between.
feed(action(SHEEP, 11, 264, { { PET, 242, 2 } }));
at(clock + 1, 11, 20, 0);
feed(action(PET, 1, 0, { { SHEEP, 1, 30 } }));
pet.x = 40;
feed(action(SHEEP, 11, 264, { { PET, 242, 2 } }));
slept = clock;
at(slept + 0.2, 40, 20, 0);
at(slept + 1, 40, 20, 0);
at(slept + 5, 40.5, 20, 0);
assert(shown(PET) == '2', 'A new sleep keeps the place it landed at: ' .. shown(PET));
-- Moving takes off only what stops a pet acting.
feed(action(ALLY, 4, 58, { { PET, 237, 4 } }));
at(clock + 1, 42, 20, 0);
assert(shown(PET) == '4', 'A pet that moved keeps its Paralysis: ' .. shown(PET));
-- Moving takes off every one of them, not only Sleep.
for _, effect in ipairs({ 19, 193, 7, 10, 28 }) do
    feed(action(SHEEP, 11, 264, { { PET, 242, effect } }));
    slept = clock;
    at(slept + 1, 42, 20, 0);
    assert(shown(PET) == '4 ' .. effect, 'Fixture: effect ' .. effect .. ' is on the pet: ' .. shown(PET));
    at(slept + 2, 43, 20, 0);
    assert(shown(PET) == '4', 'A pet that moved has no effect ' .. effect .. ': ' .. shown(PET));
end
return 'A mob or a pet that acts has nothing on it that stops it acting';
