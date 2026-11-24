-- Diabolos's Nightmare. Where its sleep lands, Phoenix takes Dia and Bio off the mob with no word of it and puts on a
-- Bio of its own at tier 11, for the sleep's time. No Dia or Bio cast goes on over that Bio while it lasts, a hit that
-- wakes the mob leaves it on, and its ticks wake no one. Anyone's Diabolos does it, not only yours.
local fx = require('pet_fixture')();
local game, settings = fx.game, fx.settings;
local self_id, whm, blm, avatar, stranger = game.id, 1002, 1003, 0x1000702, 0x1000B05;
local NIGHTMARE, SLEEP, DIA, BIO, DIA_I, DIA_II, BIO_I, SLEEP_SPELL = 658, 2, 134, 135, 23, 24, 230, 253;
game.job, game.level, game.skill = 15, 75, 276;
game.members[1] = { id = whm, index = 0x401, name = 'Whm' };
game.members[2] = { id = blm, index = 0x402, name = 'Blm' };
game.pet = { index = 0x702, id = avatar, name = 'Diabolos', flags = 0x02, hpp = 100 };
-- The mobs, each with a name, as learning needs one.
for index = 0x101, 0x105 do game.units[index] = { id = 0x1000000 + index, name = 'Goblin', flags = 0x10 }; end
fx.step();
local function close(left, wanted) return left and math.abs(left - wanted) < 1; end
-- A Dia or Bio cast on a mob: its damage message, which Phoenix sends whether or not the effect went on.
local function cast(who, spell, mob) fx.action(who, 4, spell, { { mob, 2, 10 } }); fx.step(); end
local function nightmare(who, mob, message) fx.action(who, 13, NIGHTMARE, { { mob, message or 266, SLEEP } }); fx.step(); end

-- A White Mage's Dia, then your Diabolos's Nightmare.
local mob = 0x1000101;
cast(whm, DIA_I, mob);
assert(fx.row(mob, DIA), 'Fixture: the Dia is on.');
nightmare(avatar, mob);
local sleep, bio = fx.row(mob, SLEEP), fx.row(mob, BIO);
assert(sleep, 'The sleep is on.');
assert(not fx.row(mob, DIA), 'Nightmare took the Dia off.');
assert(bio and bio.source == avatar and bio.by_pet and bio.tier == 11, 'and put on its own Bio.');
assert(close(bio.remaining, 90) and close(bio.remaining, sleep.remaining), 'for the sleep\'s time: ' .. tostring(bio.remaining));
assert(fx.details(bio):find('Nightmare put it on with its sleep, for the same time.', 1, true), fx.details(bio));
-- A hit wakes the mob and leaves the Bio.
fx.action(whm, 1, 0, { { mob, 1, 30 } });
fx.step();
assert(not fx.row(mob, SLEEP) and fx.row(mob, BIO), 'A hit ends the sleep and not the Bio.');
-- While it lasts, no Dia or Bio goes on: the damage message comes all the same.
fx.step(20);
cast(whm, DIA_I, mob);
assert(not fx.row(mob, DIA), 'A Dia doesn\'t go on over it.');
cast(whm, DIA_II, mob);
assert(not fx.row(mob, DIA), 'Nor Dia II.');
cast(blm, BIO_I, mob);
bio = fx.row(mob, BIO);
assert(bio and bio.source == avatar and bio.tier == 11 and close(bio.remaining, 70), 'A Bio leaves Nightmare\'s as it was: ' .. tostring(bio and bio.remaining));
-- Once its time is up, a Dia goes on again.
fx.step(71);
cast(whm, DIA_I, mob);
assert(fx.row(mob, DIA) and fx.row(mob, DIA).source == whm, 'After it, the Dia goes on.');

-- A Bio from before is taken off the same way: the row is Nightmare's from then on.
mob = 0x1000102;
cast(blm, BIO_I, mob);
assert(fx.row(mob, BIO) and fx.row(mob, BIO).source == blm, 'Fixture: the Black Mage\'s Bio.');
nightmare(avatar, mob);
bio = fx.row(mob, BIO);
assert(bio and bio.source == avatar and bio.tier == 11 and close(bio.remaining, 90), 'The Bio is Nightmare\'s, with its time.');

-- A Nightmare that misses or takes no effect changes nothing.
mob = 0x1000103;
cast(whm, DIA_I, mob);
nightmare(avatar, mob, 324);
nightmare(avatar, mob, 323);
assert(fx.row(mob, DIA) and not fx.row(mob, BIO) and not fx.row(mob, SLEEP), 'A miss leaves the Dia.');

-- Another Summoner's Diabolos does the same.
mob = 0x1000104;
cast(whm, DIA_II, mob);
nightmare(stranger, mob);
bio = fx.row(mob, BIO);
assert(not fx.row(mob, DIA) and bio and bio.source == stranger and not bio.by_pet and bio.tier == 11, 'Anyone\'s Nightmare puts on its Bio.');
cast(whm, DIA_II, mob);
assert(not fx.row(mob, DIA), 'and keeps a Dia II off.');

-- Its ticks don't wake a sleeper, so your own sleep beside it still teaches its time.
settings.durations.learn = true;
mob = 0x1000105;
nightmare(avatar, mob);
fx.action(whm, 1, 0, { { mob, 1, 30 } });
fx.step();
fx.action(self_id, 4, SLEEP_SPELL, { { mob, 236, SLEEP } });
fx.step();
assert(fx.row(mob, SLEEP) and fx.row(mob, BIO), 'Fixture: your sleep beside Nightmare\'s Bio.');
fx.step(30);
fx.message(self_id, mob, SLEEP, 206);
fx.step();
fx.step(1.5);
assert(next(settings.durations.learned) ~= nil, 'Your sleep\'s wear-off is a sample.');
settings.durations.learn = false;
return 'Diabolos\'s Nightmare and its Bio';
