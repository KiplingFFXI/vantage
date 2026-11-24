-- Whose pet a unit is, from the game's entity list (core/client.lua pet_owner), and what that is for over heads: a
-- debuff a party member's pet put on a mob counts as the party's, as your own pet's does.
local W = require('overhead_fixture');
local client, overhead = require('core.client'), require('core.overhead');
local entities = AshitaCore:GetMemoryManager():GetEntity();
local JUG, CHARMED, WILD, STRAY = 0x1000801, 0x1000303, 0x1000802, 0x1000803;
W.unit(0x401, 1002, 'player', 1, -3, { name = 'Bob', pet = 0x701 });
W.unit(0x402, 1003, 'player', 2, -4, { name = 'Dave', pet = 0x303 });
W.unit(0x403, 1500, 'player', 3, -5, { name = 'Stranger', pet = 0x703 });
W.unit(0x701, JUG, 'pet', 1, -2, { name = 'CourierCarrie' });
W.unit(0x303, CHARMED, 'mob', 2, -6, { name = 'Hare' });
W.unit(0x702, WILD, 'mob', 4, -7, { name = 'Wild' });
W.unit(0x703, STRAY, 'pet', 3, -6, { name = 'Stray' });
local asked = 0;
local pet_index = entities.GetPetTargetIndex;
entities.GetPetTargetIndex = function(self, index) asked = asked + 1; return pet_index(self, index); end;

assert(client.pet_owner(JUG, 10) == 1002, 'A jug pet is its owner\'s: its place is 0x100 under what its id names.');
assert(client.pet_owner(CHARMED, 10) == 1003, 'A charmed monster keeps its place and is its charmer\'s.');
assert(client.pet_owner(STRAY, 10) == 1500, 'A stranger\'s pet is theirs.');
assert(client.pet_owner(WILD, 10) == nil, 'A monster nobody owns has no owner.');
assert(client.pet_owner(1002, 10) == nil and client.pet_owner(0, 10) == nil and client.pet_owner(nil, 10) == nil, 'A player, and no unit, have none.');
assert(client.pet_owner(0x1000FFF, 10) == nil and client.pet_owner(0x1000304, 10) == nil, 'A unit that isn\'t in the list has none.');
-- What was found is checked, not looked for again.
asked = 0;
assert(client.pet_owner(JUG, 11) == 1002 and asked <= 1, 'A known owner is checked with one look: ' .. asked);
-- A unit's update (0x00E) with its HP part, which marks a unit a player is master of (Phoenix
-- src/map/packets/entity_update.cpp :406-410), or not.
local function update(id, index, master)
    local bytes = MOCK.bytes(0x38);
    MOCK.put(bytes, 4, 4, id); MOCK.put(bytes, 8, 2, index); MOCK.put(bytes, 0x0A, 1, 0x07);
    MOCK.put(bytes, 0x27, 1, master and 0x08 or 0);
    return MOCK.packet(0x00E, bytes);
end
-- A unit found with no owner, such as a mob fighting a pet, isn't looked for again for half a minute. An update of it
-- that marks a player as its master, as the one a charm sends does, ends that, so one charmed since is found by its
-- next move.
asked = 0;
assert(client.pet_owner(WILD, 10.2) == nil and asked == 0, 'A unit with no owner isn\'t looked for again at once: ' .. asked);
assert(client.pet_owner(WILD, 15) == nil and asked == 0, 'Nor at its next move seconds later: ' .. asked);
client.accept(update(WILD, 0x702, false), 15.5);
assert(client.pet_owner(WILD, 16) == nil and asked == 0, 'An update with no master keeps that: ' .. asked);
W.entities[0x403].pet = 0x702;
client.accept(update(WILD, 0x702, true), 16.5);
assert(client.pet_owner(WILD, 17) == 1500, 'Charmed, its update ends that, and its next move finds its new owner.');
W.entities[0x403].pet = 0x703;
assert(client.pet_owner(WILD, 18) == nil, 'Fixture: let go again, it has none.');
asked = 0;
assert(client.pet_owner(WILD, 47.9) == nil and asked == 0, 'That holds for half a minute: ' .. asked);
assert(client.pet_owner(WILD, 48) == nil and asked > 100, 'Then it is looked for again: ' .. asked);
-- A pet let go has no owner. A pet that comes out with the same id has a new owner, found once its update says it has
-- one.
W.entities[0x401].pet = 0;
assert(client.pet_owner(JUG, 20) == nil, 'A pet its owner let go has none.');
W.entities[0x402].pet = 0x701;
client.accept(update(JUG, 0x701, true), 25);
assert(client.pet_owner(JUG, 26) == 1003, 'A new owner is found.');
W.entities[0x402].pet, W.entities[0x401].pet = 0x303, 0x701;

-- Over heads: a mob debuffed only by a member's pet gets its block, and one debuffed by a stranger's pet doesn't.
local settings = W.settings();
W.unit(0x100, 0x1000100, 'mob', 0, -5, { name = 'Crab' });
W.unit(0x101, 0x1000101, 'mob', 0, -8, { name = 'Goblin' });
local snapshot = W.snapshot({ { id = 1002, index = 0x401, scope = 'party' } });
local function debuff(mob, source) return { entity_id = mob, effect = 10, kind = 'debuff', scope = 'enemy', source = source }; end
W.frame(W.view({ debuff(0x1000100, JUG), debuff(0x1000101, STRAY) }), settings, snapshot);
assert(overhead.plan.valid and W.ids(overhead.plan):find(tostring(0x1000100), 1, true), 'A mob a party member\'s pet debuffed has its block: ' .. W.ids(overhead.plan));
assert(not W.ids(overhead.plan):find(tostring(0x1000101), 1, true), 'A stranger\'s pet\'s debuff is not the party\'s: ' .. W.ids(overhead.plan));
assert(overhead.keeps(settings.overhead.types.mob, debuff(0x1000100, JUG)), 'And its icon is kept.');
assert(not overhead.keeps(settings.overhead.types.mob, debuff(0x1000101, STRAY)), 'A stranger\'s pet\'s isn\'t, with only the party\'s debuffs shown.');
-- The pet goes while its debuff is still on the mob, as a released avatar's does: the debuff is still the party's.
-- Phoenix can send the owner's update with no pet (src/map/packets/char_update.cpp :444-447) a whole tick (400 ms,
-- src/map/map_constants.h :47-50) before the pet's own with its death animation (3) (src/map/zone_entities.cpp :2009,
-- :2039, src/map/entities/pet_entity.cpp :201-220). So for a moment the pet is still alive in the list, and its owner
-- no longer has it. Phoenix keeps the pet in that animation for 2.5 s, then it leaves the list
-- (src/map/entities/pet_entity.cpp :228-252, src/map/ai/states/death_state.cpp :57).
local jug = W.entities[0x701];
local function party_debuff()
    return W.ids(overhead.plan):find(tostring(0x1000100), 1, true) and overhead.keeps(settings.overhead.types.mob, debuff(0x1000100, JUG));
end
W.entities[0x401].pet = 0;
for _ = 1, 8 do W.frame(W.view({ debuff(0x1000100, JUG) }), settings, snapshot); end
assert(party_debuff(), 'A pet still alive for most of a second after its owner let it go keeps its debuffs with the party: ' .. W.ids(overhead.plan));
-- That second is unbroken: once its owner has it again, it starts over.
W.entities[0x401].pet = 0x701;
W.frame(W.view({ debuff(0x1000100, JUG) }), settings, snapshot);
W.entities[0x401].pet = 0;
for _ = 1, 8 do W.frame(W.view({ debuff(0x1000100, JUG) }), settings, snapshot); end
assert(party_debuff(), 'Once its owner has it again, the second starts over: ' .. W.ids(overhead.plan));
-- While the icons are hidden no list is made, so no survey sees the owner have the pet again. A wait seen before they
-- were hidden starts over once they show.
W.entities[0x401].pet = 0x701;
W.frame(W.view({ debuff(0x1000100, JUG) }), settings, snapshot);
W.entities[0x401].pet = 0;
W.frame(W.view({ debuff(0x1000100, JUG) }), settings, snapshot);
W.entities[0x401].pet = 0x701;
for _ = 1, 16 do W.frame(W.view({ debuff(0x1000100, JUG) }), settings, snapshot, true); end
W.entities[0x401].pet = 0;
W.frame(W.view({ debuff(0x1000100, JUG) }), settings, snapshot);
assert(party_debuff(), 'A wait seen before the icons were hidden starts over once they show again: ' .. W.ids(overhead.plan));
jug.status = 3;
W.frame(W.view({ debuff(0x1000100, JUG) }), settings, snapshot);
assert(W.ids(overhead.plan):find(tostring(0x1000100), 1, true), 'A pet in its death animation keeps its debuffs with the party: ' .. W.ids(overhead.plan));
W.entities[0x701] = nil;
W.frame(W.view({ debuff(0x1000100, JUG) }), settings, snapshot);
assert(W.ids(overhead.plan):find(tostring(0x1000100), 1, true), 'A pet that is gone keeps its debuffs with the party: ' .. W.ids(overhead.plan));
-- Its owner leaves the party: no longer the party's.
W.frame(W.view({ debuff(0x1000100, JUG) }), settings, W.snapshot());
assert(not W.ids(overhead.plan):find(tostring(0x1000100), 1, true), 'Once its owner has left the party it isn\'t: ' .. W.ids(overhead.plan));
-- Your own pet's, the same way.
W.entities[0x701], jug.status = jug, 0;
W.entities[W.self].pet = 0x701;
W.frame(W.view({ debuff(0x1000100, JUG) }), settings, W.snapshot());
assert(W.ids(overhead.plan):find(tostring(0x1000100), 1, true), 'Fixture: your own pet\'s debuff shows.');
W.entities[W.self].pet, W.entities[0x701] = 0, nil;
W.frame(W.view({ debuff(0x1000100, JUG) }), settings, W.snapshot());
assert(W.ids(overhead.plan):find(tostring(0x1000100), 1, true), 'Your own pet that is gone keeps its debuffs with you.');
-- A zone change forgets whose it was.
overhead.packet({ id = 0x00A });
-- The mobs are seen again in the new zone, as their updates come.
W.spawns();
W.frame(W.view({ debuff(0x1000100, JUG) }), settings, W.snapshot());
assert(not W.ids(overhead.plan):find(tostring(0x1000100), 1, true), 'A zone change forgets it.');

-- A mob a party member charmed and let go keeps its id, so a stranger can charm it later. What it does then is the
-- stranger's, once a second has gone by.
local daves = W.snapshot({ { id = 1003, index = 0x402, scope = 'party' } });
W.frame(W.view({ debuff(0x1000101, CHARMED) }), settings, daves);
assert(W.ids(overhead.plan):find(tostring(0x1000101), 1, true), 'Fixture: a member\'s charmed mob\'s debuff is the party\'s: ' .. W.ids(overhead.plan));
W.entities[0x402].pet, W.entities[0x403].pet = 0, 0x303;
W.frame(W.view({ debuff(0x1000101, CHARMED) }), settings, daves);
W.frame(W.view({ debuff(0x1000101, CHARMED) }), settings, daves, nil, 1);
assert(not W.ids(overhead.plan):find(tostring(0x1000101), 1, true), 'Once a stranger has charmed it, its debuff isn\'t the party\'s: ' .. W.ids(overhead.plan));
assert(not overhead.keeps(settings.overhead.types.mob, debuff(0x1000101, CHARMED)), 'And its icon isn\'t kept.');
-- A party pet's place in the list, and so its id, can come back on a stranger's new pet once the zone has handed out
-- the rest. That pet's debuffs are the stranger's too.
local bobs = W.snapshot({ { id = 1002, index = 0x401, scope = 'party' } });
W.unit(0x701, JUG, 'pet', 1, -2, { name = 'CourierCarrie' });
W.entities[0x401].pet = 0x701;
W.frame(W.view({ debuff(0x1000100, JUG) }), settings, bobs);
assert(W.ids(overhead.plan):find(tostring(0x1000100), 1, true), 'Fixture: a member\'s jug pet\'s debuff is the party\'s: ' .. W.ids(overhead.plan));
W.entities[0x401].pet, W.entities[0x701] = 0, nil;
W.frame(W.view({ debuff(0x1000100, JUG) }), settings, bobs);
assert(W.ids(overhead.plan):find(tostring(0x1000100), 1, true), 'Fixture: and still is once the pet is gone: ' .. W.ids(overhead.plan));
W.unit(0x701, JUG, 'pet', 3, -6, { name = 'Stray' });
W.entities[0x403].pet = 0x701;
W.frame(W.view({ debuff(0x1000100, JUG) }), settings, bobs);
W.frame(W.view({ debuff(0x1000100, JUG) }), settings, bobs, nil, 1);
assert(not W.ids(overhead.plan):find(tostring(0x1000100), 1, true), 'A stranger\'s pet with the id a party pet had isn\'t the party\'s: ' .. W.ids(overhead.plan));
assert(not overhead.keeps(settings.overhead.types.mob, debuff(0x1000100, JUG)), 'And its icon isn\'t kept.');
return 'A pet\'s owner is found, and a member\'s pet counts as the party';
