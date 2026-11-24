local catalog = require('core.catalog');
local data = require('data.effects');
assert(#catalog.list() == 270, 'The pickers list Copy Image once, not its icons for 2, 3 and 4 or more shadows.');
assert(catalog.get(15).kind == 'debuff' and catalog.get(15).priority == 100);
assert(catalog.get(113).kind == 'buff', 'Reraise is a buff regardless of cancellation flags.');
assert(catalog.get(44).kind == 'buff' and catalog.get(299).kind == 'debuff');
assert(catalog.get(251).group == 'Food');
assert(catalog.get(999).unnamed and catalog.get(999).name == 'An effect with no name' and catalog.get(999).kind == 'other');
assert(#catalog.list() == 270, 'One nothing names joins no list.');
AshitaCore.GetResourceManager = function () return { GetString = function (_, table_name, id)
    assert(table_name == 'buffs.names'); return id == 999 and 'Custom Phoenix Status' or nil;
end }; end
assert(catalog.get(999).name == 'Custom Phoenix Status' and not catalog.get(999).unnamed);
-- The client spells many debuffs in lowercase. Each word of such a name gets a capital, and a name that has capitals
-- of its own is left as the client has it.
local client = { [4] = 'paralysis', [6] = 'silence', [13] = 'slow', [18] = 'gradual petrification', [136] = 'STR Down', [167] = 'Magic Def. Down',
    [997] = 'Seal of Might', [998] = 'Cait Sith\'s Favor' };
AshitaCore.GetResourceManager = function () return { GetString = function (_, _, id) return client[id]; end }; end
assert(catalog.get(4).name == 'Paralysis' and catalog.get(6).name == 'Silence' and catalog.get(13).name == 'Slow',
    'A debuff the client spells in lowercase starts with a capital: ' .. catalog.get(4).name .. ', ' .. catalog.get(6).name .. ', ' .. catalog.get(13).name);
assert(catalog.get(18).name == 'Gradual Petrification', 'Each of its words does: ' .. catalog.get(18).name);
assert(catalog.get(136).name == 'STR Down' and catalog.get(167).name == 'Magic Def. Down' and catalog.get(998).name == 'Cait Sith\'s Favor',
    'A name with capitals of its own is left alone: ' .. catalog.get(136).name .. ', ' .. catalog.get(167).name .. ', ' .. catalog.get(998).name);
assert(catalog.get(997).name == 'Seal of Might', 'So is a small word inside one: ' .. catalog.get(997).name);
local max, min, basis = catalog.duration('spells', 58, 4);
assert(max == 120 and min == 30 and basis:find('Duration range'));
-- Bindga binds for 13 to 60 seconds as Bind does, and Charm binds a monster it can't charm for 1 to 5.
max, min, basis = catalog.duration('spells', 362, 11);
assert(max == 60 and min == 13 and basis:find('Duration range'), 'Bindga binds for 13 to 60 seconds: ' .. min .. ' to ' .. max);
max, min, basis = catalog.duration('abilities', 52, 11);
assert(max == 5 and min == 1 and basis:find('Duration range'), 'Charm binds for 1 to 5 seconds: ' .. min .. ' to ' .. max);
-- A monster move whose length goes by the mob's TP runs from its time at 1000 TP to its time at 3000, and one that rolls
-- its length runs over the roll. Sticky Thread, Horror Cloud, Hypnosis and Feather Barrier go by TP, and so do a
-- charmed monster's Shockwave and a jug pet's Spoil from Sic. Spoil's pact row, the copy Ready would use
-- (sql/pet_skills.sql :232), gets the same times, though Phoenix never sends it (sql/abilities.sql :269,
-- src/map/ability.cpp :331-335, src/map/entities/pet_entity.cpp :423-428). Dream Flower rolls, and so does Leaf Dagger,
-- by Phoenix's own roll. Abominable Belch has a time for each of its effects. Animating Wail is a flat 90 seconds, as
-- it goes by the mob's TP after the move used it all (actions/mobskills/animating_wail.lua :19,
-- src/map/ai/states/mobskill_state.cpp :133, :179-180, globals/mobskills.lua :1724-1728). Cocoon stays a flat 180
-- seconds.
for _, move in ipairs({ { 'skills', 344, 13, 180, 540 }, { 'skills', 479, 13, 60, 300 }, { 'skills', 550, 2, 45, 135 },
    { 'skills', 402, 92, 180, 1020 }, { 'skills', 301, 2, 15, 60 }, { 'skills', 305, 3, 115, 180 }, { 'skills', 1978, 4, 30, 90 },
    { 'skills', 1978, 31, 15, 75 }, { 'charmed_skills', 52, 2, 60, 300 }, { 'pet_moves', 3879, 136, 180, 540 },
    { 'pacts', 711, 136, 180, 540 }, { 'skills', 1782, 33, 90, 90 }, { 'skills', 346, 93, 180, 180 } }) do
    max, min, basis = catalog.duration(move[1], move[2], move[3]);
    assert(min == move[4] and max == move[5] and basis:find(move[4] < move[5] and 'Duration range' or 'Phoenix base'),
        move[1] .. ' ' .. move[2] .. ' lasts ' .. move[4] .. ' to ' .. move[5] .. ' seconds: ' .. min .. ' to ' .. max .. ', ' .. basis);
end
max, min = catalog.duration('spells', 112, 156);
assert(max == 12 and min == 12, 'Flash is a flat 12 seconds.');
-- Hundred Fists, Counterstance, Formless Strikes and the blue magic buffs each last a set time.
for kind, lengths in pairs({ abilities = { [17] = { 46, 45 }, [40] = { 61, 300 }, [152] = { 341, 180 } },
    spells = { [517] = { 37, 300 }, [530] = { 33, 300 }, [632] = { 37, 300 }, [647] = { 36, 300 }, [547] = { 93, 90 },
        [574] = { 92, 30 }, [538] = { 190, 60 }, [655] = { 91, 60 } } }) do
    for id, length in pairs(lengths) do
        max, min = catalog.duration(kind, id, length[1]);
        assert(max == length[2] and min == length[2], kind .. ' ' .. id .. ' lasts ' .. length[2] .. ' seconds: ' .. tostring(max));
    end
end
max, min = catalog.duration('spells', 107, 116);
assert(max == 180 and min == 120, 'Phalanx II runs 120 to 180 seconds by merit.');
max, min = catalog.duration('spells', 107, 116, { merits = { [2310] = 2 }, level = 75 });
assert(max == 150 and min == 150, 'Your own Phalanx II goes by your merits.');
max, min = catalog.duration('spells', 136, 69);
assert(max == 300 and min == 30);
max, min = catalog.duration('spells', 57, 33);
assert(max == 180 and min == 180);
assert(catalog.duration('spells', 9999, 33) == nil, 'A known icon never supplies a generic timer.');
assert(catalog.duration('spells', 57, 40) == nil, 'An unrelated action cannot set the timer.');
assert(catalog.duration('procs', 1, 3, { complete = false, items = {} }) == nil, 'Incomplete weapon data cannot identify the proc timer.');
max, min = catalog.duration('spells', 25, 134);
assert(max > min, 'Unknown merit rank is a range.');
local rule = data.merits.dia_iii;
max, min = catalog.duration('spells', 25, 134, { items = {}, buffs = {}, merits = { [rule.id] = 3 }, level = 75 });
assert(max == rule.base + 3 * rule.per_rank and min == max);
max, min = catalog.roll_duration({ items = {}, merits = { [0x0C04] = 2 }, level = 75 });
assert(max == 340 and min == 340);
max, min = catalog.roll_duration(nil);
assert(max == 360 and min == 300, 'Phoenix era caps Winning Streak at three ranks.');
max, min = catalog.bust_duration({ merits = { [0x0588] = 5 }, level = 75 });
assert(max == 250 and min == 250);
local sample = { items = {}, buffs = { [419] = true }, merits = {}, level = 75, target_self = true, enhancing_skill = 230 };
max, min = catalog.duration('spells', 136, 69, sample);
assert(max == 900 and min == 90, 'Composure preserves the random range.');
max, min = catalog.duration('spells', 60, 100, sample);
assert(max == 570 and min == 570, 'Barspell uses sampled enhancing skill before Composure.');
sample.target_self = false;
max = catalog.duration('spells', 60, 100, sample);
assert(max == 190, 'Composure only extends self casts.');
assert(catalog.roll(98) == 310);
assert(catalog.source('spells', 259, 2) ~= nil, 'Sleep II can use the Sleep I icon.');
assert(catalog.drops(13)[1] == 33);
