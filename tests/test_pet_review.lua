-- A level restriction or Level Sync wipes a called pet's effects on the server and says nothing
-- (src/map/lua/lua_base_entity.cpp levelRestriction), so the rows go when your level changes with one of them. A charmed mob
-- keeps its own, and so does anything at an ordinary level up. A pet out of view shows the HP its last sync gave, and a
-- sample goes by the same ticks as a real pet.
local fx = require('pet_fixture')();
local game, settings = fx.game, fx.settings;
local mob, wyvern, called, charmed = 0x1000AAA, 0x1000700, 0x700, 0x123;
local crab, PARALYZE, RESTRICTED, SYNCED = 0x1000123, 58, 143, 269;

local function call_pet()
    game.buffs, game.level = {}, 75;
    game.pet = { index = called, id = wyvern, name = 'Wyvern', flags = 0x01, hpp = 100 };
    fx.step(10);
    fx.action(mob, 4, PARALYZE, { { wyvern, 236, 4 } });
    fx.step();
    assert(fx.row(wyvern, 4), 'Fixture: the pet has an effect.');
end;

-- Level restriction, and the same for Level Sync, on the way in and out.
for _, effect in ipairs({ RESTRICTED, SYNCED }) do
    call_pet();
    game.buffs, game.level = { { effect = effect } }, 30;
    fx.step();
    assert(not fx.row(wyvern, 4), 'The restriction took what was on the pet: ' .. effect);
    assert(fx.app.state.view.pet, 'The pet itself stays.');
    fx.action(mob, 4, PARALYZE, { { wyvern, 236, 4 } });
    fx.step();
    assert(fx.row(wyvern, 4), 'What lands after it shows.');
    fx.step(10);
    game.buffs, game.level = {}, 75;
    fx.step();
    assert(not fx.row(wyvern, 4), 'And its end takes that too: ' .. effect);
end;

-- A level up with no restriction takes nothing, and nor does a restriction that changes no level.
call_pet();
game.level = 74;
fx.step(10);
assert(fx.row(wyvern, 4), 'An ordinary level change keeps the rows.');
fx.step(10);
game.buffs = { { effect = RESTRICTED } };
fx.step(10);
assert(fx.row(wyvern, 4), 'A restriction with no change of level keeps them.');
fx.step(10);
game.level = 75;
fx.step();
assert(fx.row(wyvern, 4), 'The two far apart aren\'t one event.');

-- Half a restriction seen with one pet isn't matched with a level change the next pet sees, nor one seen before a zone
-- change with one after it.
game.pet, game.buffs, game.level = nil, {}, 75;
fx.step(10);
game.pet = { index = called, id = wyvern, name = 'Wyvern', flags = 0x01, hpp = 100 };
fx.step(10);
game.buffs = { { effect = RESTRICTED } };
fx.step();
game.pet = nil;
fx.step();
local next_pet = wyvern + 1;
game.pet = { index = called + 1, id = next_pet, name = 'Wyvern', flags = 0x01, hpp = 100 };
fx.step();
fx.action(mob, 4, PARALYZE, { { next_pet, 236, 4 } });
fx.step();
assert(fx.row(next_pet, 4), 'Fixture: the next pet has an effect.');
game.level = 74;
fx.step();
assert(fx.row(next_pet, 4), 'A restriction seen with the last pet isn\'t matched with the next one\'s level change.');
fx.step(10);
game.buffs = {};
fx.step();
game.zone = 103;
fx.step();
fx.action(mob, 4, PARALYZE, { { next_pet, 236, 4 } });
fx.step();
assert(fx.row(next_pet, 4), 'Fixture: the pet has an effect after the zone change.');
game.level = 75;
fx.step();
assert(fx.row(next_pet, 4), 'Nor is one seen before a zone change matched with a level change after it.');
game.zone = 102;

-- A charmed mob keeps what it has.
game.buffs, game.level = {}, 75;
game.pet = { index = charmed, id = crab, name = 'Crab', flags = 0x10, hpp = 76 };
fx.step(10);
fx.action(mob, 4, PARALYZE, { { crab, 236, 4 } });
fx.step();
assert(fx.row(crab, 4), 'Fixture: the charmed mob has an effect.');
game.buffs, game.level = { { effect = RESTRICTED } }, 30;
fx.step();
assert(fx.row(crab, 4), 'A charmed mob keeps its rows.');

-- Out of view the client has no unit to read, so the last sync's HP shows, not 0%.
game.buffs, game.level = {}, 75;
game.pet = { index = charmed, id = crab, name = 'Crab', flags = 0x10, hpp = 76 };
fx.step(10);
fx.unit(crab, charmed, true);
game.pet.away = true;
fx.sync(charmed, 40, 'Crab');
fx.step();
assert(fx.app.state.view.pet.hpp == 40, 'A pet out of view shows its last HP: ' .. tostring(fx.app.state.view.pet.hpp));

-- A sample goes by Show maneuvers and overload risk too.
game.pet, game.job = nil, 18;
fx.sync();
fx.step(10);
settings.pet.preview = true;
fx.step();
assert(fx.draw():find('Fire', 1, true), 'The automaton\'s sample shows its maneuvers.');
settings.pet.show_maneuvers = false;
assert(not fx.draw():find('Fire', 1, true), 'With the tick off it doesn\'t.');
return 'A level restriction wipes a called pet, a charmed mob stays, and the display keeps to what it can know';
