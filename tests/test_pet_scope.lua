-- Your pet is a unit of its own in the tracker, whatever the client's flags say of it. It is never trimmed from a busy
-- fight, it keeps its effects while it is out of your view, and they go with it when it goes: all of them for a pet you
-- called, none for a mob you charmed, which goes back with what it has on. A hit wakes it as it wakes a mob, unless the
-- sleep is a mob's Nightmare, and takes Bind's countdown.
local fx = require('pet_fixture')();
local game, tracker = fx.game, fx.app.tracker;
local mob, crab, index = 0x1000AAA, 0x1000123, 0x123;
local PARALYZE, BIND, SLEEP, SLEEP_SPELL = 58, 11, 2, 253;

-- A charmed mob keeps the Monster flag, and is your pet all the same.
game.pet = { index = index, id = crab, name = 'Crab', flags = 0x10, hpp = 76 };
fx.step();
assert(fx.app.state.snapshot.pet.id == crab and fx.app.state.snapshot.entities[crab].kind == 'pet', 'The pet is in every snapshot.');
fx.action(mob, 4, PARALYZE, { { crab, 236, 4 } });
fx.step();
local row = fx.row(crab, 4);
assert(row and row.scope == 'pet', 'What lands on it is filed under your pet.');
assert(fx.app.state.view.pet.effects == fx.rows(crab), 'The display has its rows.');

-- Sixty-four mobs in a fight leave your pet's unit alone.
for i = 1, 80 do
    local id = 0x1002000 + i;
    fx.action(mob, 4, PARALYZE, { { id, 236, 4 } });
    fx.step(0.02);
end
fx.step();
assert(fx.row(crab, 4), 'A busy fight doesn\'t trim your pet.');
local kept = 0;
for id in pairs(tracker.entities) do if id > 0x1002000 then kept = kept + 1; end end
assert(kept < 80, 'Fixture: the fight was trimmed: ' .. kept);

-- Out of your view the client drops its unit. The effects stay, the display stays, and its HP is the server's word.
fx.unit(crab, index, true);
game.pet.away = true;
fx.sync(index, 50, 'Crab');
fx.step();
assert(fx.row(crab, 4), 'A pet out of view keeps its rows.');
assert(fx.app.state.view.pet and fx.app.state.view.pet.name == 'Crab' and fx.app.state.view.pet.hpp == 50, 'and stays on the display, with HP from its sync.');
-- Back in view.
game.pet.away = nil;
fx.unit(crab, index);
fx.step();
assert(fx.app.state.view.pet.hpp == 76 and fx.row(crab, 4), 'Back in view, the client says.');

-- With the client's pet index cleared too, it stays just the same, until 90 minutes pass with no word of it. A pet
-- parked out of view stays yours for as long as a long camp.
fx.unit(crab, index, true);
game.pet.away, game.pet.no_index = true, true;
fx.step(120);
assert(fx.app.state.view.pet and fx.row(crab, 4), 'With no index from the client it holds on.');
fx.sync(index, 40, 'Crab');
fx.step(250);
assert(fx.app.state.view.pet, 'A sync keeps it going.');
fx.step(301);
assert(fx.app.state.view.pet, 'Five minutes parked is nothing.');
fx.step(5401);
assert(not fx.app.state.snapshot.pet and not fx.app.state.view.pet, 'Ninety minutes with no word and it is taken as gone.');

-- A charmed mob you release keeps what it has on, as an enemy.
game.pet = { index = index, id = crab, name = 'Crab', flags = 0x10, hpp = 76 };
fx.step();
fx.action(mob, 4, PARALYZE, { { crab, 236, 4 } });
fx.step();
assert(fx.row(crab, 4).scope == 'pet', 'Fixture: on your pet.');
game.pet = nil;
game.units[index] = { id = crab, name = 'Crab', flags = 0x10 };
fx.sync();
fx.step();
assert(not fx.app.state.snapshot.pet and fx.row(crab, 4) and fx.row(crab, 4).scope == 'enemy', 'A released mob keeps its rows as an enemy.');
game.units[index] = nil;

-- A pet you called goes with everything, and the empty sync is what says so, even with the client still naming it.
local wyvern, called = 0x1000701, 0x701;
game.pet = { index = called, id = wyvern, name = 'Rainbow', flags = 0x02, hpp = 100 };
fx.step();
fx.action(mob, 4, PARALYZE, { { wyvern, 236, 4 } });
fx.step();
assert(fx.row(wyvern, 4), 'Fixture: on your wyvern.');
fx.sync();
fx.step();
assert(not fx.app.state.snapshot.pet and not fx.row(wyvern, 4) and not tracker.entities[wyvern], 'The empty sync ends it at once, with nothing left.');
-- The client's own pet index can name it a moment longer; then it is simply gone.
fx.step(3);
game.pet = nil;
fx.step();
assert(not fx.app.state.snapshot.pet, 'Gone.');

-- A pet change forgets the old one.
game.pet = { index = called, id = wyvern, name = 'Rainbow', flags = 0x02, hpp = 100 };
fx.step();
fx.action(mob, 4, PARALYZE, { { wyvern, 236, 4 } });
fx.step();
local other = 0x1000702;
game.pet = { index = 0x702, id = other, name = 'Sheep', flags = 0x02, hpp = 100 };
fx.step();
assert(fx.app.state.snapshot.pet.id == other and not fx.row(wyvern, 4) and not tracker.entities[wyvern], 'A new pet, and the old one has gone with its rows.');

-- Its death takes them too.
fx.action(mob, 4, PARALYZE, { { other, 236, 4 } });
fx.step();
assert(fx.row(other, 4), 'Fixture: on the pet.');
fx.message(mob, other, 0, 6);
fx.step();
assert(not fx.row(other, 4), 'Its death clears it.');

-- A zone takes them too.
fx.action(mob, 4, PARALYZE, { { other, 236, 4 } });
fx.step();
assert(fx.row(other, 4), 'Fixture: on the pet again.');
fx.zone(103);
game.pet = nil;
fx.step();
fx.step();
assert(not fx.row(other, 4), 'A zone clears it.');
game.pet = { index = 0x702, id = other, name = 'Sheep', flags = 0x02, hpp = 100 };
fx.step();

-- A hit wakes it, as it wakes a mob.
fx.action(mob, 4, SLEEP_SPELL, { { other, 236, SLEEP } });
fx.action(mob, 4, 258, { { other, 236, BIND } });
fx.step();
assert(fx.row(other, SLEEP) and fx.row(other, BIND) and fx.row(other, BIND).remaining, 'Fixture: asleep and bound with a countdown.');
fx.action(mob, 1, 0, { { other, 1, 30 } });
fx.step();
assert(not fx.row(other, SLEEP), 'A hit wakes your pet.');
assert(fx.row(other, BIND) and not fx.row(other, BIND).remaining and fx.row(other, BIND).status == 'unknown', 'and Bind keeps its icon with no time.');
-- A hit for nothing doesn't.
fx.action(mob, 4, SLEEP_SPELL, { { other, 236, SLEEP } });
fx.step();
fx.action(mob, 1, 0, { { other, 1, 0 } });
fx.step();
assert(fx.row(other, SLEEP), 'A hit for 0 wakes nothing.');
fx.action(mob, 1, 0, { { other, 1, 12 } });
fx.step();
-- A mob's Nightmare isn't woken by a hit; your own pact's Nightmare on a mob is.
fx.action(mob, 11, 1908, { { other, 242, SLEEP } });
fx.step();
assert(fx.row(other, SLEEP) and fx.row(other, SLEEP).deep, 'Fixture: a mob\'s Nightmare on your pet.');
fx.action(mob, 1, 0, { { other, 1, 30 } });
fx.step();
assert(fx.row(other, SLEEP), 'A hit doesn\'t end a mob\'s Nightmare.');
return 'Your pet\'s unit in the tracker';
