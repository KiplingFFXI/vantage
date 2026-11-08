-- Your avatar's wards. A ward's length depends only on you, so your own copy from the same action, which the server
-- times, is everyone's; with no copy of yours it comes from the era formula and your summoning skill, and with no skill
-- to read there is no countdown. Those that give several effects report with messages of their own. /vg report keeps the
-- last few, so the formula can be checked against your own copy.
local fx = require('pet_fixture')();
local game = fx.game;
local self_id, ally, mob, avatar, index = game.id, 1002, 0x1000AAA, 0x1000702, 0x702;
local HASTEGA, GROWL, HOWL, SHROUD, ROLLING, SLOWGA, LUNAR_CRY, GLITTERING, EARTHEN = 595, 532, 533, 661, 626, 580, 530, 515, 564;
local HASTE, SLOW, BOOSTS = 33, 13, { 80, 81, 82, 83, 84, 85, 86 };
game.job, game.level, game.skill = 15, 75, 276;
game.members[1] = { id = ally, index = 0x401, name = 'Ally' };
game.pet = { index = index, id = avatar, name = 'Garuda', flags = 0x02, hpp = 100 };
fx.step();
local function close(left, wanted) return left and math.abs(left - wanted) < 1; end
local function clear()
    game.buffs = {};
    fx.status();
    for _, id in ipairs({ avatar, ally, mob }) do
        for _, row in ipairs(fx.rows(id)) do fx.message(row.source or mob, id, row.effect, 206); end
    end
    fx.step();
    fx.step(5);
end

-- It reached you: until your 0x063 the formula, then your copy's time, on the avatar and on the member.
fx.action(avatar, 13, HASTEGA, { { self_id, 319, HASTE }, { avatar, 319, HASTE }, { ally, 319, HASTE } });
fx.step();
local row = fx.row(avatar, HASTE);
assert(row and row.by_pet and row.exact and close(row.remaining, 111), 'The formula first: 90 + 3 x 7 at 276 skill.');
game.buffs[1] = { effect = HASTE, ends = MOCK.now + 150 };
fx.status();
fx.step();
row = fx.row(avatar, HASTE);
local member = fx.row(ally, HASTE);
local mine = fx.row(self_id, HASTE);
assert(mine and mine.status == 'server' and close(mine.remaining, 150), 'Fixture: your copy has its timer.');
assert(math.abs(row.deadline - mine.deadline) < 0.001 and math.abs(member.deadline - mine.deadline) < 0.001, 'The avatar\'s and the member\'s take your time.');
assert(fx.details(row):find('Ends when your own copy does.', 1, true), fx.details(row));
assert(fx.app.pet:report().wards[1].own_seconds and close(fx.app.pet:report().wards[1].own_seconds, 150), 'The report has your copy\'s length.');
local ward = fx.app.pet:report().wards[1];
assert(ward.name == 'Hastega' and ward.skill == 276 and ward.level == 75 and ward.seconds == 111, 'and what the formula made of it.');
assert(fx.draw():find('|2m|', 1, true), 'The display counts it.');
clear();

-- It took no effect on you: your older copy says nothing of this one, so the formula counts.
game.buffs[1] = { effect = HASTE, ends = MOCK.now + 20 };
fx.status();
fx.step();
fx.action(avatar, 13, HASTEGA, { { self_id, 323, 0 }, { avatar, 319, HASTE } });
fx.step();
row = fx.row(avatar, HASTE);
assert(close(row.remaining, 111) and row.exact and not row.follow, 'Your 323 leaves the formula.');
assert(fx.details(row):find('Phoenix\'s length for Hastega at your summoning skill. It ends sooner only if it\'s taken off.', 1, true), fx.details(row));
clear();

-- You weren't in it.
fx.action(avatar, 13, HASTEGA, { { avatar, 319, HASTE }, { ally, 319, HASTE } });
fx.step();
assert(close(fx.row(avatar, HASTE).remaining, 111) and close(fx.row(ally, HASTE).remaining, 111), 'Out of its reach, the formula for both.');
fx.step(111.5);
assert(not fx.row(avatar, HASTE), 'It leaves on time.');
clear();

-- The cap: 180 at most.
game.skill = 400;
fx.action(avatar, 13, HASTEGA, { { avatar, 319, HASTE } });
fx.step();
assert(close(fx.row(avatar, HASTE).remaining, 180), 'At most 180.');
clear();
game.skill = 100;
fx.action(avatar, 13, HASTEGA, { { avatar, 319, HASTE } });
fx.step();
assert(close(fx.row(avatar, HASTE).remaining, 90), 'And 90 at the cap or under it.');
clear();

-- With no skill to read there is no countdown, and nothing in place of one.
game.skill = nil;
fx.action(avatar, 13, HASTEGA, { { avatar, 319, HASTE } });
fx.step();
row = fx.row(avatar, HASTE);
assert(row and not row.remaining and not row.exact, 'No skill, no countdown.');
local drawn = fx.draw();
assert(not drawn:find('?', 1, true) and not drawn:lower():find('unknown', 1, true), drawn);
game.skill = 276;
clear();

-- SMN as a support job: the avatar's level is your support level.
game.job, game.sub, game.sub_level, game.skill = 1, 15, 37, 120;
fx.step();
fx.action(avatar, 13, HASTEGA, { { avatar, 319, HASTE } });
fx.step();
assert(close(fx.row(avatar, HASTE).remaining, 108), 'Over the cap at 37: 90 + 3 x 6.');
game.job, game.sub, game.sub_level, game.skill = 15, 0, 0, 276;
clear();

-- Ecliptic Growl: seven boosts for 180 s, from messages with no effect in them.
fx.action(avatar, 13, GROWL, { { avatar, 364, 0 }, { ally, 365, 0 } });
fx.step();
for _, effect in ipairs(BOOSTS) do
    row = fx.row(avatar, effect);
    assert(row and row.by_pet and close(row.remaining, 180) and fx.row(ally, effect), 'Ecliptic Growl gives ' .. effect .. '.');
end
assert(#fx.rows(avatar) == 7, 'Seven rows.');
clear();
-- Ecliptic Howl and Dream Shroud alike.
fx.action(avatar, 13, HOWL, { { avatar, 146, 0 }, { ally, 147, 0 } });
fx.step();
assert(close(fx.row(avatar, 90).remaining, 180) and close(fx.row(avatar, 92).remaining, 180) and #fx.rows(avatar) == 2, 'Ecliptic Howl gives two.');
clear();
fx.action(avatar, 13, SHROUD, { { avatar, 415, 0 }, { ally, 414, 0 } });
fx.step();
assert(close(fx.row(avatar, 190).remaining, 180) and close(fx.row(avatar, 191).remaining, 180) and #fx.rows(avatar) == 2, 'Dream Shroud gives two.');
clear();
-- Several effects on you too: each follows your copy of it.
fx.action(avatar, 13, GROWL, { { avatar, 364, 0 }, { self_id, 365, 0 } });
fx.step();
game.buffs = {};
for at, effect in ipairs(BOOSTS) do game.buffs[at] = { effect = effect, ends = MOCK.now + 170 }; end
fx.status();
fx.step();
for _, effect in ipairs(BOOSTS) do assert(close(fx.row(avatar, effect).remaining, 170), 'Your copy of ' .. effect .. '.'); end
clear();

-- Glittering Ruby: one stat boost, named in its param, on the formula.
fx.action(avatar, 13, GLITTERING, { { avatar, 319, 83 } });
fx.step();
assert(close(fx.row(avatar, 83).remaining, 111) and #fx.rows(avatar) == 1, 'One boost, with the formula\'s time.');
clear();

-- Earthen Ward's length is flat, whatever the skill.
game.skill = nil;
fx.action(avatar, 13, EARTHEN, { { avatar, 319, 37 } });
fx.step();
row = fx.row(avatar, 37);
assert(close(row.remaining, 900) and row.exact, 'A flat ward needs no skill.');
game.skill = 276;
clear();

-- Rolling Thunder reports a gain whether or not it took, so your copy of it says nothing and the formula counts.
game.buffs[1] = { effect = 94, ends = MOCK.now + 20 };
fx.status();
fx.step();
fx.action(avatar, 13, ROLLING, { { self_id, 320, 94 }, { avatar, 320, 94 } });
fx.step();
fx.status();
fx.step();
row = fx.row(avatar, 94);
assert(close(row.remaining, 74) and not row.follow, 'Rolling Thunder keeps to the formula: 60 + 2 x 7.');
clear();

-- Lunar Cry says nothing of what landed, so it makes nothing.
fx.action(avatar, 13, LUNAR_CRY, { { mob, 144, 0 } });
fx.step();
assert(#fx.rows(mob) == 0, 'Lunar Cry makes nothing.');

-- Slowga: 180 s plus your skill over 300, up to 200 more, as your pet's, and only an estimate of how long a mob keeps it.
for skill, seconds in pairs({ [276] = 180, [300] = 180, [350] = 230, [600] = 380 }) do
    game.skill = skill;
    fx.action(avatar, 13, SLOWGA, { { mob, 242, SLOW } });
    fx.step();
    row = fx.row(mob, SLOW);
    assert(row and row.by_pet and close(row.remaining, seconds) and not row.exact, 'Slowga at ' .. skill .. ' skill.');
    assert(fx.details(row):find('Phoenix\'s length at your summoning skill. A resist can shorten it.', 1, true), fx.details(row));
    clear();
end

-- The report keeps the last five.
game.skill = 276;
for _ = 1, 7 do fx.action(avatar, 13, HASTEGA, { { avatar, 319, HASTE } }); end
fx.step();
assert(#fx.app.pet:report().wards == 5, 'The last five wards.');
return 'Your avatar\'s wards';
