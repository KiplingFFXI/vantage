-- What your own job abilities put on your pet and take off it, from the packets through to the pet display: Reward and
-- Repair's Regen and cures, Deep Breathing, Overdrive and an overload. Each has a length Vantage knows, so each leaves on
-- time and counts as yours, and teaches the learned times nothing.
local fx = require('pet_fixture')();
local game = fx.game;
-- The client's names for the two sleeps the catalog leaves out.
AshitaCore.GetResourceManager = function() return { GetString = function(_, kind, id)
    return kind == 'buffs.names' and ({ [19] = 'sleep', [193] = 'lullaby' })[id] or nil;
end }; end;
local self_id, mob, pet_id, index = game.id, 0x1000AAA, 0x1000701, 0x701;
local REWARD, REPAIR, DEEP_BREATHING, OVERDRIVE, FIRE_MANEUVER = 78, 137, 169, 135, 141;
local REGEN, BOOST, OVERDRIVEN, OVERLOAD = 42, 190, 166, 299;
game.pet = { index = index, id = pet_id, name = 'SheepFamiliar', flags = 0x02, hpp = 90 };
fx.step();
local function on_pet(effect) fx.action(mob, 4, 1, { { pet_id, 236, effect } }); end
local function reward() fx.action(self_id, 6, REWARD, { { pet_id, 102, 100 } }); end
local function close(left, wanted) return left and math.abs(left - wanted) < 1; end

-- Reward: Regen from you for 180 s, drawn with its time and the words that say what it is.
reward();
fx.step();
local row = fx.row(pet_id, REGEN);
assert(row and row.mine and not row.by_pet and row.exact and close(row.remaining, 180) and row.status == 'estimated', 'Reward gives the pet 180 s of Regen.');
assert(fx.draw():find('|3m|', 1, true), 'The display counts it.');
assert(fx.details(row):find('Phoenix\'s fixed length for your Reward. It ends sooner only if the pet loses it.', 1, true), fx.details(row));
-- It wakes the pet, and a Jackcoat cures its list.
for _, sleep in ipairs({ 2, 19, 193 }) do
    on_pet(sleep);
    fx.step();
    assert(fx.row(pet_id, sleep), 'Fixture: asleep with ' .. sleep .. '.');
    reward();
    fx.step();
    assert(not fx.row(pet_id, sleep), 'Reward wakes it: ' .. sleep);
end;
local coats = { [12646] = { 4, 3, 5 }, [14481] = { 4, 3, 5, 12, 13, 6 }, [15095] = { 12, 13, 6 }, [14508] = { 4, 3, 5, 12, 13, 6 } };
local all = { 4, 3, 5, 12, 13, 6 };
for coat, list in pairs(coats) do
    game.items[5] = coat;
    for _, effect in ipairs(all) do on_pet(effect); end
    fx.step();
    reward();
    fx.step();
    local cured = {};
    for _, effect in ipairs(list) do cured[effect] = true; end
    for _, effect in ipairs(all) do
        assert((fx.row(pet_id, effect) == nil) == (cured[effect] == true), 'Jackcoat ' .. coat .. ' and effect ' .. effect .. '.');
    end
    for _, effect in ipairs(all) do fx.message(mob, pet_id, effect, 206); end
    game.items[5] = nil;
    fx.step();
end

-- Your wear-off ends it, and only then or at its end.
reward();
fx.step();
fx.step(60);
assert(close(fx.row(pet_id, REGEN).remaining, 120), 'It counts down.');
fx.message(self_id, pet_id, REGEN, 206);
fx.step();
assert(not fx.row(pet_id, REGEN), 'Your wear-off takes it off.');
reward();
fx.step();
fx.step(179);
assert(fx.row(pet_id, REGEN), 'It stays to its end.');
fx.step(1.5);
assert(not fx.row(pet_id, REGEN), 'It leaves on time with nothing to say so.');

-- A new Reward takes the old Regen off with a message: it can come either side of the action.
reward();
fx.step();
fx.step(5);
fx.message(self_id, pet_id, REGEN, 206);
reward();
fx.step();
assert(close(fx.row(pet_id, REGEN).remaining, 180), 'A wear-off just before the action leaves the new one.');
fx.step(5);
reward();
fx.message(self_id, pet_id, REGEN, 206);
fx.step();
assert(close(fx.row(pet_id, REGEN).remaining, 180), 'and one just after in the same packets.');
fx.step(5);
reward();
fx.step();
fx.step(0.3);
fx.message(self_id, pet_id, REGEN, 206);
fx.step();
assert(close(fx.row(pet_id, REGEN).remaining, 180), 'and one a moment after.');
fx.step(1);
fx.message(self_id, pet_id, REGEN, 206);
fx.step();
assert(not fx.row(pet_id, REGEN), 'Later than that a wear-off means it.');

-- Repair, with what the oil in your ammo slot gives, read before the last of them is used up.
game.job = 18;
for oil, seconds in pairs({ [18731] = 30, [18732] = 60, [18733] = 90, [19185] = 120 }) do
    game.items[3] = oil;
    fx.step();
    game.items[3] = nil;
    fx.action(self_id, 6, REPAIR, { { pet_id, 100, 0 } });
    fx.step();
    row = fx.row(pet_id, REGEN);
    assert(row and row.exact and row.mine and close(row.remaining, seconds), 'Oil ' .. oil .. ' gives ' .. seconds .. ' s.');
    assert(fx.details(row):find('your Repair', 1, true), fx.details(row));
    fx.message(self_id, pet_id, REGEN, 206);
    fx.step();
end
-- It wakes the pet. With REPAIR_EFFECT gear it also takes the first it finds of its list.
game.items[3] = 18731;
fx.step();
on_pet(2);
on_pet(3);
on_pet(4);
fx.step();
fx.action(self_id, 6, REPAIR, { { pet_id, 100, 0 } });
fx.step();
assert(not fx.row(pet_id, 2) and fx.row(pet_id, 3) and fx.row(pet_id, 4), 'Repair wakes it and cures nothing with no gear for it.');
game.items[8] = 15686;
fx.action(self_id, 6, REPAIR, { { pet_id, 100, 0 } });
fx.step();
assert(fx.row(pet_id, 3) and not fx.row(pet_id, 4), 'REPAIR_EFFECT 1 takes Paralysis, which comes before Poison on the list.');
game.items[8] = nil;
fx.message(self_id, pet_id, 3, 206);
fx.message(self_id, pet_id, REGEN, 206);
fx.step();

-- Overdrive: yours has the server's time, and the automaton's ends with it, with nothing left behind.
fx.action(self_id, 6, OVERDRIVE, { { pet_id, 100, OVERDRIVEN } });
fx.step();
row = fx.row(pet_id, OVERDRIVEN);
assert(row and row.exact and row.mine and not row.remaining, 'Until your 0x063 it has no time.');
assert(not fx.draw():find('?', 1, true), 'and nothing in its place.');
local ends = MOCK.now + 60;
game.buffs[1] = { effect = OVERDRIVEN, ends = ends };
fx.status();
fx.step();
row = fx.row(pet_id, OVERDRIVEN);
assert(close(row.remaining, 60) and math.abs(row.deadline - fx.row(self_id, OVERDRIVEN).deadline) < 0.001, 'Then it has yours.');
assert(fx.details(row):find('Ends when your own copy does.', 1, true), fx.details(row));
fx.step(30);
assert(close(fx.row(pet_id, OVERDRIVEN).remaining, 30), 'It counts down with yours.');
fx.step(29);
assert(fx.row(pet_id, OVERDRIVEN), 'It stays to its end.');
game.buffs[1] = nil;
fx.status();
fx.step(1.5);
assert(not fx.row(pet_id, OVERDRIVEN), 'It leaves at its end.');
fx.step(200);
assert(not fx.row(pet_id, OVERDRIVEN), 'and no icon is left to wait for.');

-- An overload: the number reported, less 5, then your own copy's time.
fx.action(self_id, 6, FIRE_MANEUVER, { { self_id, 799, 45 } });
fx.step();
row = fx.row(pet_id, OVERLOAD);
assert(row and row.exact and close(row.remaining, 40), 'Overload reports 45, which is 40 s.');
game.buffs[1] = { effect = OVERLOAD, ends = MOCK.now + 38 };
fx.status();
fx.step();
assert(close(fx.row(pet_id, OVERLOAD).remaining, 38), 'Your 0x063 has the last word.');
fx.step(37);
assert(fx.row(pet_id, OVERLOAD), 'It stays to its end.');
game.buffs[1] = nil;
fx.status();
fx.step(1.5);
assert(not fx.row(pet_id, OVERLOAD), 'It leaves on time too.');

-- Deep Breathing is reported on you and put on the wyvern; the breath that uses it wears it off.
game.job = 14;
game.pet.name = 'Rainbow';
fx.step();
fx.action(self_id, 6, DEEP_BREATHING, { { self_id, 100, 0 } });
fx.step();
row = fx.row(pet_id, BOOST);
assert(row and row.mine and row.exact and close(row.remaining, 180) and not fx.row(self_id, BOOST), 'Magic Atk. Boost on the wyvern for 180 s.');
assert(fx.details(row):find('your Deep Breathing', 1, true), fx.details(row));
fx.step(20);
fx.message(self_id, pet_id, BOOST, 206);
fx.step();
assert(not fx.row(pet_id, BOOST), 'The breath wears it off.');

-- With no pet out nothing is put on anything.
game.pet = nil;
fx.sync();
fx.step();
fx.action(self_id, 6, DEEP_BREATHING, { { self_id, 100, 0 } });
fx.step();
assert(not fx.row(self_id, BOOST) and #fx.rows(pet_id) == 0, 'No pet, nothing.');
return 'Your job abilities on your pet';
