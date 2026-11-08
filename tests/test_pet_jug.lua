-- A jug pet's clock. It starts at your Call Beast, from the pet_list time of the pet that comes, by its name or by the
-- jug you had on. It ends with the pet. A zone keeps it only if the same jug comes back within 30 seconds, and /addon
-- reload keeps it and a charm in game memory, for the same character with a pet of that name. Loaded with a jug already
-- out, there is nothing to start from, so it shows no clock and nothing in place of one.
local fx = require('pet_fixture')();
local game = fx.game;
local pet = require('core.pet');
local self_id, mob, sheep, index = game.id, 0x1000AAA, 0x1000701, 0x701;
local CALL_BEAST, FAMILIAR, JUG = 85, 24, 17864;
game.job = 9;
local function out(id, name) game.pet = { index = index, id = id or sheep, name = name or 'SheepFamiliar', flags = 0x02, hpp = 100 }; end
-- Your Call Beast: the jug is gone from your ammo slot by the time its packet comes.
local function call_beast()
    game.items[3] = JUG;
    fx.step();
    game.items[3] = nil;
    fx.action(self_id, 6, CALL_BEAST, { { self_id, 100, 0 } });
end
local function shown() return fx.app.state.view.pet; end
local function clean(text)
    assert(not text:find('?', 1, true) and not text:lower():find('unknown', 1, true) and not text:find('+', 1, true), 'Nothing reads ?, unknown or +: ' .. text);
end
local function gone()
    game.pet = nil;
    fx.sync();
    fx.step();
    fx.step(3);
end

-- Call Beast, then the pet.
call_beast();
local at = MOCK.now;
out();
fx.step();
assert(shown().jug and shown().jug.deadline == at + 3600 and shown().jug.seconds == 3600, 'The clock runs from your Call Beast.');
local drawn = fx.draw();
assert(drawn:find('|Leaves in|', 1, true) and drawn:find('|59m|', 1, true), drawn);
clean(drawn);
fx.step(60);
assert(fx.draw():find('|58m|', 1, true), 'It counts down.');
-- Familiar leaves it alone.
fx.action(self_id, 6, FAMILIAR, { { sheep, 108, 0 } });
fx.step();
assert(shown().jug.deadline == at + 3600, 'Familiar doesn\'t lengthen a jug.');
-- It ends with the pet.
gone();
assert(not shown() and not fx.app.pet.jug, 'Leave or death ends it.');

-- The pet first, then the Call Beast, as packets can come.
out();
fx.step();
assert(not shown().jug, 'Fixture: no clock yet.');
fx.action(self_id, 6, CALL_BEAST, { { self_id, 100, 0 } });
at = MOCK.now;
fx.step();
assert(shown().jug and shown().jug.deadline == at + 3600, 'A Call Beast just after the pet came starts it too.');
-- A new pet ends it.
out(0x1000702, 'CrabFamiliar');
fx.step();
assert(not shown().jug, 'A new pet has no clock of the old one\'s.');
gone();

-- How long depends on which: the name is the pet_list one.
call_beast();
at = MOCK.now;
out(sheep, 'CrabFamiliar');
fx.step();
assert(shown().jug.deadline == at + 1800, 'Half an hour for a CrabFamiliar.');
gone();
-- The client may spell the name another way.
call_beast();
at = MOCK.now;
out(sheep, 'Sheep Familiar');
fx.step();
assert(shown().jug.deadline == at + 3600, 'A name in spaces is the same jug.');
gone();
-- With a name that is none of them, the jug you had on says which.
call_beast();
at = MOCK.now;
out(sheep, 'Lamb');
fx.step();
assert(shown().jug.deadline == at + 3600 and shown().jug.name == 'Lamb', 'The jug in your ammo slot says how long.');
drawn = fx.draw();
assert(drawn:find('|Leaves in|', 1, true), drawn);
gone();
-- With neither, nothing.
fx.step();
fx.action(self_id, 6, CALL_BEAST, { { self_id, 100, 0 } });
out(sheep, 'Lamb');
fx.step();
assert(not shown().jug, 'No name and no jug read: no clock.');
drawn = fx.draw();
assert(not drawn:find('Leaves in', 1, true), drawn);
clean(drawn);
gone();
-- A pet that comes long after a Call Beast isn't from it.
fx.action(self_id, 6, CALL_BEAST, { { self_id, 100, 0 } });
fx.step();
fx.step(11);
out();
fx.step();
assert(not shown().jug, 'Past the ten seconds a Call Beast takes.');
gone();
-- Its last minute, and the end of it: nothing is left on the title row, and a jug that ran out has no clock after.
call_beast();
out();
fx.step();
fx.step(3590);
drawn = fx.draw();
assert(drawn:find('|Leaves in|', 1, true) and drawn:find('s|', 1, true), drawn);
fx.step(11);
assert(not fx.app.pet.jug and not fx.draw():find('Leaves in', 1, true), 'Past its time the clock has gone.');
gone();

-- A zone keeps it only if the same jug comes back.
call_beast();
at = MOCK.now;
out();
fx.step();
game.pet = nil;
fx.zone(103);
fx.step();
fx.step(5);
assert(not shown(), 'Fixture: no pet yet after the zone.');
out(0x1000710, 'SheepFamiliar');
fx.step();
assert(shown().jug and shown().jug.deadline == at + 3600, 'The same jug back keeps its clock, with a new id.');
-- Each zone starts its wait over, from when you arrive.
game.pet = nil;
fx.zone(104);
fx.step();
fx.step(25);
fx.zone(105);
fx.step();
fx.step(25);
out(0x1000711, 'SheepFamiliar');
fx.step();
assert(shown().jug and shown().jug.deadline == at + 3600, 'Two zones in a row.');
-- A different pet in the new zone isn't the same jug, and past the wait nothing is held.
game.pet = nil;
fx.zone(106);
fx.step();
out(0x1000712, 'CrabFamiliar');
fx.step();
assert(not shown().jug, 'A different pet doesn\'t take the clock.');
game.pet = nil;
fx.sync();
fx.step();
fx.step(31);
out(0x1000713, 'SheepFamiliar');
fx.step();
assert(not shown().jug, 'Thirty seconds on it isn\'t held.');
gone();
call_beast();
out();
fx.step();
game.pet = nil;
fx.zone(107);
fx.step();
fx.step(31);
out(0x1000714, 'SheepFamiliar');
fx.step();
assert(not shown().jug, 'Back too late, it has no clock.');
gone();
-- A Call Beast in the new zone starts over.
call_beast();
out();
fx.step();
game.pet = nil;
fx.zone(108);
fx.step();
fx.step(5);
call_beast();
at = MOCK.now;
out(0x1000715, 'SheepFamiliar');
fx.step();
assert(shown().jug.deadline == at + 3600, 'A new call is a new clock.');
gone();

-- A charmed pet and a jug are not the same thing: a charm's estimate stays on the title row.
fx.action(self_id, 6, 52, { { mob, 136, 0 } });
out(mob, 'Crab');
game.pet.index = 0x123;
fx.step();
assert(shown().charm and not shown().jug and not fx.draw():find('Leaves in', 1, true), 'A charm has no jug clock.');
gone();

-- /addon reload. The store stands for the process environment, and os.time for the wall clock it counts by.
local wall = os.time;
local clock = 1000000;
os.time = function() return clock; end;
local written, writes = nil, 0;
local store = { read = function() return written; end, write = function(text) written, writes = text, writes + 1; end };
local settings = { pet = pet.tidy({ enabled = true }) };
local entity = { GetHPPercent = function() return 90; end };
local player = { GetPetMPPercent = function() return 0; end, GetPetTP = function() return 0; end, GetStat = function() return 60; end, GetStatModifier = function() return 10; end };
local memory = { GetEntity = function() return entity; end, GetPlayer = function() return player; end };
AshitaCore.GetMemoryManager = function() return memory; end;
local function snapshot(id, name, owner)
    return { valid = true, id = owner or self_id, zone = 102, level = 75, job = 9, self_effects = {}, entities = {},
        pet = id and { id = id, index = index, name = name, kind = 'pet' } or nil };
end
local watch = pet.new(store);
watch:refresh(100, settings, snapshot());
watch:observe({ kind = 'call_beast', entity_id = self_id, item = JUG }, 100, snapshot());
local view = watch:refresh(101, settings, snapshot(sheep, 'SheepFamiliar'));
assert(view.jug and view.jug.deadline == 3700 and writes > 0 and type(written) == 'string', 'A clock is written when it starts.');
-- It is written when it changes, and not each refresh.
local count = writes;
for t = 102, 150 do watch:refresh(t, settings, snapshot(sheep, 'SheepFamiliar')); end
assert(writes == count, 'Nothing is written while nothing changes.');
-- A reload, 200 s on: the wall clock says how much of it is left, whatever the new load's own clock reads.
clock = clock + 200;
local kept = written;
watch = pet.new(store);
view = watch:refresh(5, settings, snapshot(sheep, 'SheepFamiliar'));
assert(view.jug and math.abs(view.jug.deadline - (5 + 3600 - 1 - 200)) <= 1 and view.jug.seconds == 3600, 'The clock comes back: ' .. tostring(view.jug and view.jug.deadline));
-- With no pet of that name it is left: a record for another pet or another character isn't this one's.
for _, case in ipairs({ { sheep, 'CrabFamiliar' }, { sheep, 'SheepFamiliar', 1002 } }) do
    written = kept;
    watch = pet.new(store);
    view = watch:refresh(5, settings, snapshot(case[1], case[2], case[3]));
    assert(view and not view.jug, 'Another pet or another character has no clock: ' .. case[2]);
end
-- A clock that ran out while the addon was away is gone with it.
written = kept;
clock = clock + 4000;
watch = pet.new(store);
assert(not watch:refresh(5, settings, snapshot(sheep, 'SheepFamiliar')).jug, 'A deadline that passed is gone.');
-- A bad record reads as none.
for _, text in ipairs({ 'nothing', '2;1001;SheepFamiliar;1;1;0;;;;;;0;', '', 12 }) do
    written = text;
    watch = pet.new(store);
    assert(not watch:refresh(5, settings, snapshot(sheep, 'SheepFamiliar')).jug, 'A record that can\'t be read is none.');
end
-- Loaded with a jug out and nothing kept: no clock, and nothing in place of one.
written = nil;
watch = pet.new(store);
view = watch:refresh(5, settings, snapshot(sheep, 'SheepFamiliar'));
assert(view and not view.jug, 'Nothing to start from.');
-- What waits for its pet gives up after 30 seconds, and writes nothing over itself until then.
written, count = kept, writes;
clock = 1000000 + 200;
watch = pet.new(store);
watch:refresh(5, settings, snapshot());
watch:refresh(20, settings, snapshot());
assert(written == kept and writes == count, 'It waits.');
watch:refresh(36, settings, snapshot());
assert(writes > count and written == nil, 'and gives up.');
-- With no store at all a reload simply has nothing.
watch = pet.new();
watch:observe({ kind = 'call_beast', entity_id = self_id, item = JUG }, 100, snapshot());
assert(watch:refresh(101, settings, snapshot(sheep, 'SheepFamiliar')).jug, 'No store, and the clock still runs.');

-- A charm comes back too, with Familiar used.
written = nil;
clock = 2000000;
watch = pet.new(store);
watch:refresh(100, settings, snapshot());
watch:observe({ kind = 'check', entity_id = mob, level = 70 }, 100, snapshot());
watch:observe({ kind = 'charm', entity_id = mob, items = {} }, 101, snapshot());
view = watch:refresh(102, settings, snapshot(mob, 'Crab'));
assert(view.charm and view.charm.deadline == 812, 'Fixture: a charm with its estimate.');
watch:observe({ kind = 'familiar', entity_id = mob, items = {} }, 103, snapshot(mob, 'Crab'));
view = watch:refresh(104, settings, snapshot(mob, 'Crab'));
assert(view.charm.deadline == 812 + 1500, 'Fixture: Familiar counted.');
clock = clock + 10;
watch = pet.new(store);
view = watch:refresh(7, settings, snapshot(mob, 'Crab'));
assert(view.charm and view.charm.familiar and math.abs(view.charm.deadline - (7 + 812 + 1500 - 104 - 10)) <= 1, 'The charm comes back: ' .. tostring(view.charm and view.charm.deadline));
assert(pet.charm_details(view.charm, 7):find('Familiar added', 1, true), 'Familiar still counts, and its tooltip says so.');
watch:observe({ kind = 'familiar', entity_id = mob, items = {} }, 8, snapshot(mob, 'Crab'));
assert(math.abs(watch:refresh(9, settings, snapshot(mob, 'Crab')).charm.deadline - (7 + 812 + 1500 - 104 - 10)) <= 1, 'and it isn\'t counted twice.');
-- A charm with no /check before it comes back with no estimate.
written = nil;
watch = pet.new(store);
watch:refresh(100, settings, snapshot());
watch:observe({ kind = 'charm', entity_id = mob, items = {} }, 101, snapshot());
watch:refresh(102, settings, snapshot(mob, 'Crab'));
watch = pet.new(store);
view = watch:refresh(7, settings, snapshot(mob, 'Crab'));
assert(view.charm and view.charm.deadline == nil, 'Charmed, with no estimate, after a reload too.');
os.time = wall;
return 'A jug\'s clock, and what a reload keeps';
