-- Spirit Link: what it takes off your wyvern, and Empathy's copies of your effects. A copy has the time yours had left at
-- the link and never moves with yours after. With more flagged effects than ranks the server picks at random, so none is
-- shown; and the merit counts only for a DRG main at 75.
local fx = require('pet_fixture')();
local game = fx.game;
-- The client's names for the two it cures that the catalog leaves out.
AshitaCore.GetResourceManager = function() return { GetString = function(_, kind, id)
    return kind == 'buffs.names' and ({ [19] = 'sleep', [193] = 'lullaby' })[id] or nil;
end }; end;
local self_id, mob, wyvern, index = game.id, 0x1000AAA, 0x1000701, 0x701;
local LINK, EMPATHY = 80, 2884;
game.job = 14;
game.pet = { index = index, id = wyvern, name = 'Rainbow', flags = 0x02, hpp = 40 };
fx.step();
local function link() fx.action(self_id, 6, LINK, { { wyvern, 102, 200 } }); end
local function close(left, wanted) return left and math.abs(left - wanted) < 1; end
local function drop(id)
    for _, row in ipairs(fx.rows(id)) do fx.message(row.source or mob, id, row.effect, 206); end
    fx.step();
end

-- Its fourteen cures, and nothing else.
local cures = { 3, 135, 134, 192, 128, 129, 130, 131, 132, 133, 15, 2, 19, 193 };
for _, effect in ipairs(cures) do
    fx.action(mob, 4, 1, { { wyvern, 236, effect } });
    fx.action(mob, 4, 1, { { wyvern, 236, 4 } });
    fx.step();
    assert(fx.row(wyvern, effect) and fx.row(wyvern, 4), 'Fixture: ' .. effect .. ' on the wyvern.');
    link();
    fx.step();
    assert(not fx.row(wyvern, effect) and fx.row(wyvern, 4), 'Spirit Link takes off ' .. effect .. ', and not Paralysis.');
end
drop(wyvern);

-- Two ranks and two flagged effects: both copied, at the times yours have left. Weakness has no empathy flag.
fx.merits({ [EMPATHY] = 2 });
game.buffs = { { effect = 33, ends = MOCK.now + 100 }, { effect = 40, ends = MOCK.now + 300 }, { effect = 1, ends = MOCK.now + 50 } };
fx.status();
fx.step();
link();
fx.step();
local haste, protect = fx.row(wyvern, 33), fx.row(wyvern, 40);
assert(haste and protect and not fx.row(wyvern, 1), 'Each flagged effect of yours is copied, and only those.');
assert(close(haste.remaining, 100) and close(protect.remaining, 300), 'Each has the time yours had left.');
assert(haste.exact and protect.exact and haste.mine, 'They are known exactly, and yours.');
assert(fx.details(haste):find('Copied from you by Spirit Link', 1, true), fx.details(haste));
-- Yours is refreshed afterwards, and the copy doesn't move: nothing links them now.
local ended = haste.deadline;
game.buffs[1].ends = MOCK.now + 500;
fx.status();
fx.step();
assert(math.abs(fx.row(wyvern, 33).deadline - ended) < 0.001, 'A later refresh of yours doesn\'t move the copy.');
fx.step(99);
assert(fx.row(wyvern, 33), 'It stays to its end.');
fx.step(2);
assert(not fx.row(wyvern, 33) and fx.row(wyvern, 40), 'and leaves on time.');
drop(wyvern);

-- More flagged effects than ranks: the server picks at random, so none can be known.
game.buffs = { { effect = 33, ends = MOCK.now + 100 }, { effect = 40, ends = MOCK.now + 300 }, { effect = 41, ends = MOCK.now + 300 } };
fx.status();
fx.step();
link();
fx.step();
assert(#fx.rows(wyvern) == 0, 'Three effects with two ranks gives none.');

-- A merit needs DRG main at 75, as the server reads it.
game.buffs[3] = nil;
game.level = 74;
fx.status();
fx.step();
link();
fx.step();
assert(#fx.rows(wyvern) == 0, 'Below 75 the merit doesn\'t count.');
game.level, game.job, game.sub = 75, 1, 14;
fx.step();
link();
fx.step();
assert(#fx.rows(wyvern) == 0, 'Nor on the support job.');
game.job, game.sub = 14, 0;

-- No merit, no copies.
fx.merits({ [EMPATHY] = 0 });
fx.step();
link();
fx.step();
assert(#fx.rows(wyvern) == 0, 'No ranks, no copies.');

-- A link that didn't reach the wyvern puts nothing on it: the row has to name it.
fx.merits({ [EMPATHY] = 2 });
fx.step();
fx.action(self_id, 6, LINK, { { self_id, 100, 0 } });
fx.step();
assert(#fx.rows(wyvern) == 0, 'Aimed elsewhere it isn\'t yours to copy.');
return 'Spirit Link and Empathy';
