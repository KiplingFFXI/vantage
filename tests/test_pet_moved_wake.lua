-- A pet asleep can't move: Phoenix holds a pet under Sleep, Sleep II, Lullaby, Petrification, Stun or Terror still
-- (src/map/ai/controllers/pet_controller.cpp :65-68, src/map/ai/states/inactive_state.cpp :75-83). So a pet the
-- client shows a yalm or more from where it was a second after the newest one landed is awake, though it did nothing,
-- and the icon goes. Through the whole addon: the client's place for the pet (core/client.lua read_pet) and the
-- tracker's check at each refresh.
local fx = require('pet_fixture')();
local game = fx.game;
local sheep, wyvern, index = 0x1000124, 0x1000801, 0x701;
game.pet = { index = index, id = wyvern, name = 'Wyvern', hpp = 100, x = 10, y = 20, z = 0 };
fx.step();
local pet = fx.app.state.snapshot.pet;
assert(pet.x == 10 and pet.y == 20 and pet.z == 0, 'The snapshot has the place the client gives the pet.');
-- Sheep Song, monster move 264, puts it to sleep.
fx.action(sheep, 11, 264, { { wyvern, 242, 2 } });
fx.step();
assert(fx.row(wyvern, 2), 'Fixture: asleep.');
-- The client finishes a step it was drawing, inside the first second. The place kept is where it ends up.
game.pet.x = 10.6;
fx.step(0.5);
fx.step(1);
game.pet.x = 11.2;
fx.step();
assert(fx.row(wyvern, 2), 'Under a yalm from where it was a second on is no wake.');
-- Out of view the client has no place for it, and the sleep stays.
game.pet.away = true;
fx.unit(wyvern, index, true);
fx.step();
assert(fx.app.state.snapshot.pet and fx.app.state.snapshot.pet.x == nil and fx.row(wyvern, 2),
    'A pet the game isn\'t showing has no place, and stays asleep.');
game.pet.away = nil;
fx.unit(wyvern, index);
fx.step();
assert(fx.app.state.snapshot.pet.x == 11.2 and fx.row(wyvern, 2), 'Back in view where it was, it is still asleep.');
-- The client can still list a pet after the despawn that marked it gone, at a spot that may be old. That's no place.
fx.unit(wyvern, index, true);
game.pet.x = 12;
fx.step();
pet = fx.app.state.snapshot.pet;
assert(pet.away and pet.x == nil and fx.row(wyvern, 2), 'A pet marked gone has no place, though the client lists it.');
-- Seen again a yalm or more from its place, it is awake.
fx.unit(wyvern, index);
fx.step();
assert(not fx.row(wyvern, 2), 'A yalm or more from its place, it is awake.');
return 'A pet seen to move is awake';
