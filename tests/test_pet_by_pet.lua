-- What your pet does counts as yours wherever a display asks for what's yours: Only effects I applied, the debuffs Watched
-- enemies lists, the overhead blocks. It stays out of mine, as learned times are from your own casts alone.
local fx = require('pet_fixture')();
local game, hud, overhead = fx.game, require('ui.hud'), require('core.overhead');
local self_id, ally, mob, avatar, index = game.id, 1002, 0x1000AAA, 0x1000702, 0x702;
local SLOWGA, HASTEGA, SLOW, HASTE = 580, 595, 13, 33;
game.job, game.level, game.skill = 15, 75, 276;
game.members[1] = { id = ally, index = 0x401, name = 'Ally' };
game.units[0x123] = { id = mob, name = 'Crab', flags = 0x10 };
game.pet = { index = index, id = avatar, name = 'Garuda', flags = 0x02, hpp = 100 };
fx.step();
local settings = fx.settings;

-- A debuff from your avatar on a mob.
fx.action(avatar, 13, SLOWGA, { { mob, 242, SLOW } });
fx.step();
local row = fx.row(mob, SLOW);
assert(row and row.by_pet and not row.mine and row.source == avatar, 'It is by your pet, and not yours as such.');
assert(fx.details(row):find('From Garuda (your pet)', 1, true), fx.details(row));
-- A panel set to Only effects I applied keeps it, and leaves someone else's.
fx.action(ally, 4, 56, { { mob, 236, 4 } });
fx.step();
local panel = settings.panels.watch;
local view = fx.app.state.view;
settings.watch_ids = { mob };
local function shown()
    local out = {};
    for _, kept in ipairs(hud.filter_rows(view, panel, 'watch', settings)) do out[kept.effect] = true; end
    return out;
end
assert(shown()[SLOW] and shown()[4], 'Fixture: both on the watched mob.');
panel.mine_only = true;
assert(shown()[SLOW] and not shown()[4], 'Only effects I applied keeps what your pet did, and not a member\'s.');
panel.mine_only = false;
-- Watched enemies lists the mobs you debuffed, and that is by your pet too.
settings.watch_ids = {};
panel.list_debuffed = true;
assert(shown()[SLOW] and not shown()[4], 'Debuffs from your pet list a mob as yours do.');
panel.list_debuffed = false;

-- The overhead filters keep it, and the pet block's usual filter of buffs you cast shows a ward.
local pet_block = settings.overhead.types.pet;
assert(pet_block.buffs_mine_only == true, 'Fixture: the pet block\'s default is buffs you cast.');
fx.action(avatar, 13, HASTEGA, { { avatar, 319, HASTE } });
fx.step();
local haste = fx.row(avatar, HASTE);
assert(haste and overhead.keeps(pet_block, haste), 'The pet block shows a ward by default.');
assert(not overhead.keeps(pet_block, { effect = HASTE, kind = 'buff', source = 0x1000BBB, present = true }), 'and not a buff someone else\'s pet gave.');
local strict = { kinds = 'all', mine_only = true, exclude = {}, include = {} };
assert(overhead.keeps(strict, row) and not overhead.keeps(strict, fx.row(mob, 4)), 'Only mine on a block keeps it too.');

-- An alert on Watched enemies counts a mob your pet debuffed, with the panel's Also list enemies I debuff on.
local function alert(by_pet)
    local notices = require('core.alerts').new();
    local rule = { id = 'slow', enabled = true, event = 'remaining', effect = SLOW, scope = 'watch', thresholds = { 30 }, unit = 'seconds', cooldown = 0,
        visual = true, duration = 4 };
    local debuff = { key = 'slow', instance = 1, effect = SLOW, name = 'Slow', scope = 'enemy', entity_id = mob, kind = 'debuff', by_pet = by_pet, status = 'estimated',
        remaining = 40, total = 180, present = true };
    local rows = { valid = true, rows = { debuff }, subjects = {}, context = { id = self_id, zone = 102, job = 15 } };
    notices:update(rows, {}, { rule }, 0, { list_debuffed = true, watch_ids = {} });
    debuff.remaining = 5;
    notices:update(rows, {}, { rule }, 1, { list_debuffed = true, watch_ids = {} });
    return #notices:drain(1);
end
assert(alert(true) == 1 and alert(nil) == 0, 'An alert on watched enemies counts your pet\'s debuffs, and not a stranger\'s.');

-- Learned times come from your own casts alone: with learning on, your pet's effect wearing off teaches nothing.
settings.durations.learn = true;
fx.action(avatar, 13, SLOWGA, { { mob, 242, SLOW } });
fx.step();
fx.step(100);
fx.message(avatar, mob, SLOW, 204);
fx.step();
fx.step(1);
assert(next(settings.durations.learned) == nil, 'A pet\'s effect is no sample.');
-- and so does a job ability Vantage already knows the length of.
fx.action(self_id, 6, 78, { { avatar, 102, 100 } });
fx.step();
fx.step(60);
fx.message(self_id, avatar, 42, 206);
fx.step();
fx.step(1);
assert(next(settings.durations.learned) == nil, 'An exact length is no sample.');
settings.durations.learn = false;
return 'Your pet\'s effects count as yours';
