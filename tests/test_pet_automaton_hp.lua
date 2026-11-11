-- Show automaton HP as a number, on the pet display. A PUP, main or support, gets its automaton's name, HP and max HP
-- from the server in the job extra 0x044, sent whenever the automaton changes. With the tick on, the HP bar shows them
-- for the pet of that name while they agree with the HP percent the game shows, and the percent otherwise. The tick
-- starts off, and off the bar shows the percent, as it always did.
local fx = require('pet_fixture')();
local game, settings, display, pet = fx.game, fx.settings, require('ui.pet_display'), require('core.pet');
local automaton, index = 0x1000703, 0x703;
local function shown() return fx.app.state.view.pet; end

assert(pet.make().exact_hp == false and settings.pet.exact_hp == false, 'It starts off.');
assert(pet.tidy({ exact_hp = 1 }).exact_hp == false and pet.tidy({ exact_hp = true }).exact_hp == true, 'Only true or false is kept.');

game.job = 18;
game.pet = { index = index, id = automaton, name = 'Ironsides', flags = 0x02, hpp = 78 };
fx.sync(index, 78, 'Ironsides');
fx.step();
settings.pet.exact_hp = true;
assert(shown() and not shown().hp and fx.draw():find('|HP 78%|', 1, true), 'Before the server sends a number, the percent.');
-- The same packet's BLU page is no automaton's.
fx.automaton('Ironsides', 812, 1040, 16);
fx.step();
assert(not shown().hp, 'A BLU page gives no number.');
fx.automaton('Ironsides', 812, 1040);
fx.step();
assert(shown().hp == 812 and shown().max_hp == 1040, 'The number the server sent.');
local text = fx.draw();
assert(text:find('|HP 812/1040|', 1, true) and not text:find('HP 78%', 1, true), 'The bar shows it: ' .. text);
settings.pet.exact_hp = false;
assert(fx.draw():find('|HP 78%|', 1, true), 'With the tick off, the percent.');
settings.pet.exact_hp = true;

-- Hovering the number says where it comes from, with Hover details on. The percent has no tooltip, as before.
local function hover()
    fx.moving.hover, fx.moving.mx = true, settings.pet.x + 40;
    for y = settings.pet.y, settings.pet.y + 120 do
        fx.moving.my = y;
        fx.draw();
        if fx.spot and fx.spot.kind == 'hp' then return fx.spot; end
    end
end
local found = hover();
assert(found and display.details(found, MOCK.now):find('percent', 1, true), 'The bar\'s tooltip says where the number comes from.');
settings.pet.exact_hp = false;
assert(not hover(), 'With the percent showing, the bar has no tooltip.');
settings.pet.exact_hp = true;
fx.moving.hover, fx.moving.mx, fx.moving.my = false, -1, -1;

-- The server works the percent out from the same HP, so a number it disagrees with isn't shown.
game.pet.hpp = 50;
fx.step();
assert(not shown().hp and fx.draw():find('|HP 50%|', 1, true), 'A number the percent disagrees with gives the percent.');
-- At 0 HP the server sends the max HP as the HP.
game.pet.hpp = 0;
fx.automaton('Ironsides', 1040, 1040);
fx.step();
assert(not shown().hp and fx.draw():find('|HP 0%|', 1, true), 'At 0 HP, the percent.');
fx.automaton('Ironsides', 5, 1040);
fx.step();
assert(not shown().hp, 'The percent is never 0 above 0 HP, so a number above 0 against it is left out.');
-- It rounds the percent down in single precision, so the percent can be 1 under what the number gives.
game.pet.hpp = 28;
fx.automaton('Ironsides', 29, 100);
fx.step();
assert(shown().hp == 29 and fx.draw():find('|HP 29/100|', 1, true), 'A percent 1 off by rounding still agrees.');
game.pet.hpp = 100;
fx.automaton('Ironsides', 1040, 1040);
fx.step();
assert(fx.draw():find('|HP 1040/1040|', 1, true), 'Full.');
fx.automaton('Ironsides', 1045, 1040);
fx.step();
assert(not shown().hp, 'An HP over the max HP is left out.');

-- The packet tells of your automaton even while your pet is something else, as with a jug on BST with PUP support.
game.job, game.sub = 9, 18;
game.pet = { index = 0x704, id = 0x1000704, name = 'SheepFamiliar', flags = 0x02, hpp = 100 };
fx.sync(0x704, 100, 'SheepFamiliar');
fx.automaton('Ironsides', 1040, 1040);
fx.step();
assert(shown().name == 'SheepFamiliar' and not shown().hp and fx.draw():find('|HP 100%|', 1, true), 'Another pet keeps the percent.');

-- A zone change forgets the number until the server sends it again.
game.job, game.sub = 18, 0;
game.pet = { index = index, id = automaton, name = 'Ironsides', flags = 0x02, hpp = 78 };
fx.sync(index, 78, 'Ironsides');
fx.automaton('Ironsides', 812, 1040);
fx.step();
assert(shown().hp == 812, 'Fixture: the automaton is back with its number.');
fx.zone(103);
fx.sync(index, 78, 'Ironsides');
fx.step();
assert(shown() and not shown().hp, 'After a zone change, the percent.');
fx.automaton('Ironsides', 812, 1040);
fx.step();
assert(shown().hp == 812, 'and the number once the server sends it.');

-- The automaton's sample shows a number with the tick on, and the other samples their percent.
settings.pet.preview = true;
assert(fx.draw():find('|HP 798/1050|', 1, true), 'The automaton\'s sample shows a number.');
settings.pet.exact_hp = false;
assert(fx.draw():find('|HP 76%|', 1, true), 'With the tick off, its percent.');
settings.pet.exact_hp = true;
game.job = 9;
fx.step();
assert(fx.draw():find('|HP 76%|', 1, true), 'A jug\'s sample keeps the percent.');
settings.pet.preview = false;
return 'Automaton HP as a number';
