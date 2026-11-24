-- A bust and what the Corsair rolls after it (core/rolls.lua). The Bust effect lasts five minutes and Phantom Roll
-- is ready again in one, so the same roll can be rolled again while its bust is still on the Corsair. The bust keeps
-- its own line beside the new roll's. A Corsair main can hold two busts, and each one's line shows its own time.
local rolls, defaults = require('core.rolls'), require('ui.defaults');
local self_id, ally = 1001, 1002;
local snapshot = { valid = true, id = self_id, zone = 102, name = 'Tester', level = 75, job = 17, self_known = true, self_effects = {},
    party = { { id = ally, name = 'Ally', scope = 'party', zone = 102, slot = 1 } }, entities = {} };
local s = defaults.tidy(defaults.make());
s.rolls.enabled = true;
local slots = { [0] = { id = self_id, job = 17, level = 75, subjob = 13, sublevel = 37 }, [1] = { id = ally, job = 17, level = 75, subjob = 1, sublevel = 37 } };
local player = { GetMainJob = function() return 17; end, GetMainJobLevel = function() return 75; end,
    GetSubJob = function() return 13; end, GetSubJobLevel = function() return 37; end };
local party = { GetMemberServerId = function(_, slot) return slots[slot] and slots[slot].id or 0; end,
    GetMemberIsActive = function(_, slot) return slots[slot] and 1 or 0; end,
    GetMemberMainJob = function(_, slot) return slots[slot] and slots[slot].job; end, GetMemberMainJobLevel = function(_, slot) return slots[slot] and slots[slot].level; end,
    GetMemberSubJob = function(_, slot) return slots[slot] and slots[slot].subjob; end, GetMemberSubJobLevel = function(_, slot) return slots[slot] and slots[slot].sublevel; end };
local memory = { GetParty = function() return party; end, GetPlayer = function() return player; end };
AshitaCore.GetMemoryManager = function() return memory; end;

local watch = rolls.new();
local function roll(actor, ability, total, double_up, bust, at)
    watch:observe({ kind = 'roll', entity_id = actor, ability = ability, total = total, double_up = double_up, bust = bust,
        targets = { actor }, results = { bust and 'bust' or 'got' } }, at);
end
-- seen, when a case gives it, is when the tracker first listed the row (first_seen).
local function bust_row(id, deadline, seen) return { entity_id = id, effect = 309, deadline = deadline, present = true, first_seen = seen }; end
-- The shown entries as text, newest first: the roll, its total, and B with the bust's time for a bust.
local function lines(shown)
    local out = {};
    for index, entry in ipairs(shown) do
        out[index] = entry.ability .. ':' .. entry.total .. (entry.bust and ':B' .. tostring(entry.bust_deadline) or '');
    end
    return table.concat(out, ' ');
end

-- Chaos Roll, a Double-Up that busts, then Chaos Roll again a minute on, with the bust still on you.
roll(self_id, 105, 6, false, false, 100);
roll(self_id, 105, 12, true, true, 105);
local shown = watch:refresh(106, s, snapshot, { bust_row(self_id, 405) });
assert(lines(shown) == '105:12:B405', 'Fixture: the bust shows with its time: ' .. lines(shown));
roll(self_id, 105, 3, false, false, 166);
shown = watch:refresh(167, s, snapshot, { bust_row(self_id, 405) });
assert(lines(shown) == '105:3 105:12:B405', 'The same roll rolled again keeps the bust\'s line beside it: ' .. lines(shown));
assert(shown[1].window_deadline == 211 and shown[2].window_deadline == nil, 'The new roll has its Double-Up window and the bust has none.');
-- A Double-Up goes to the new roll, and the bust's line is as it was.
roll(self_id, 105, 8, true, false, 170);
shown = watch:refresh(171, s, snapshot, { bust_row(self_id, 405) });
assert(lines(shown) == '105:8 105:12:B405', 'A Double-Up lands on the new roll: ' .. lines(shown));
-- The new roll busts too: two busts, each with its own time. The older bust ends first.
roll(self_id, 105, 12, true, true, 175);
shown = watch:refresh(176, s, snapshot, { bust_row(self_id, 405), bust_row(self_id, 475) });
assert(lines(shown) == '105:12:B475 105:12:B405', 'Two busts of one roll each show their own time: ' .. lines(shown));
-- The rows come in any order.
shown = watch:refresh(177, s, snapshot, { bust_row(self_id, 475), bust_row(self_id, 405) });
assert(lines(shown) == '105:12:B475 105:12:B405', 'Whatever order the buff list has them in: ' .. lines(shown));
-- The older bust wears off: its line leaves, and the newer keeps its own time.
shown = watch:refresh(406, s, snapshot, { bust_row(self_id, 475) });
assert(lines(shown) == '105:12:B475', 'When the older bust wears off its line leaves: ' .. lines(shown));
shown = watch:refresh(476, s, snapshot, {});
assert(#shown == 0, 'And the newer leaves with its own.');

-- Two busts of different rolls, the same way.
watch = rolls.new();
roll(self_id, 105, 5, false, false, 500);
roll(self_id, 105, 12, true, true, 503);
roll(self_id, 108, 5, false, false, 565);
roll(self_id, 108, 12, true, true, 570);
shown = watch:refresh(571, s, snapshot, { bust_row(self_id, 870), bust_row(self_id, 803) });
assert(lines(shown) == '108:12:B870 105:12:B803', 'Busts of two rolls each show their own time: ' .. lines(shown));
-- Each of your Bust rows has the game's time, so each bust keeps the row it took. When the older bust's row goes and
-- the newer's is still listed, the older bust is off you, and its line leaves with its row.
shown = watch:refresh(572, s, snapshot, { bust_row(self_id, 870) });
assert(lines(shown) == '108:12:B870', 'When its row goes, the older bust leaves at once: ' .. lines(shown));
shown = watch:refresh(871, s, snapshot, {});
assert(#shown == 0, 'And the newer leaves with its row.');
-- Chaos Roll busts at 101 and its row is listed. Hunter's Roll busts at 162. Right after, before the buff list shows
-- the second Bust, the only row is the first bust's: both lines stay, and the first keeps its own time.
local function two_busts(first, second)
    watch = rolls.new();
    roll(self_id, 105, 6, false, false, 100);
    roll(self_id, 105, 12, true, true, 101);
    shown = watch:refresh(102, s, snapshot, { bust_row(self_id, first) });
    assert(lines(shown) == '105:12:B' .. first, 'Fixture: the first bust has its row: ' .. lines(shown));
    roll(self_id, 108, 5, false, false, 160);
    roll(self_id, 108, 12, true, true, 162);
    shown = watch:refresh(162.5, s, snapshot, { bust_row(self_id, first) });
    assert(lines(shown) == '108:12:Bnil 105:12:B' .. first, 'Before the second Bust is listed both lines stay: ' .. lines(shown));
    shown = watch:refresh(163, s, snapshot, { bust_row(self_id, first), bust_row(self_id, second) });
    assert(lines(shown) == '108:12:B' .. second .. ' 105:12:B' .. first, 'Then each has its own time: ' .. lines(shown));
end
-- Fold at 170 takes the older Bust off and leaves the 462 row.
two_busts(401, 462);
shown = watch:refresh(171, s, snapshot, { bust_row(self_id, 462) });
assert(lines(shown) == '108:12:B462', 'After Fold only the bust still on you shows: ' .. lines(shown));
-- Five ranks of Bust Duration merits make each bust 250 s, so the older wears off at 351, before its five minutes.
two_busts(351, 412);
shown = watch:refresh(352, s, snapshot, { bust_row(self_id, 412) });
assert(lines(shown) == '108:12:B412', 'A bust that merits made shorter leaves when it wears off: ' .. lines(shown));
-- A buff list that came without its timers can't say which Bust went, so the tracker holds a row back (present false)
-- until the timers come. That row still counts, so neither line leaves before the timers say which bust went.
two_busts(401, 462);
local held = bust_row(self_id, 462);
held.present = false;
shown = watch:refresh(171, s, snapshot, { bust_row(self_id, 401), held });
assert(lines(shown) == '108:12:B462 105:12:B401', 'A row held back ends no line: ' .. lines(shown));
shown = watch:refresh(172, s, snapshot, { bust_row(self_id, 462) });
assert(lines(shown) == '108:12:B462', 'Once the timers say the older bust went, only its line leaves: ' .. lines(shown));
-- A buff list Vantage couldn't read whole leaves rows with no time. Such a row could be either bust's, so both lines
-- stay with no time to show. Each finds its own row again when the times are back, though a time worked out again can
-- be a second off.
two_busts(401, 462);
shown = watch:refresh(171, s, snapshot, { { entity_id = self_id, effect = 309 }, { entity_id = self_id, effect = 309 } });
assert(lines(shown) == '108:12:Bnil 105:12:Bnil', 'Rows with no time end no line: ' .. lines(shown));
shown = watch:refresh(172, s, snapshot, { bust_row(self_id, 402), bust_row(self_id, 461) });
assert(lines(shown) == '108:12:B461 105:12:B402', 'Each bust finds its own row again: ' .. lines(shown));
-- A bust from before the display was on has a row but no line. Right after a new bust it can be the only Bust row for
-- a moment. It ends too soon to be the new bust's, so the new bust doesn't keep it, and takes its own once it is listed.
watch = rolls.new();
roll(self_id, 108, 5, false, false, 175);
roll(self_id, 108, 12, true, true, 180);
watch:refresh(180.5, s, snapshot, { bust_row(self_id, 300) });
shown = watch:refresh(181, s, snapshot, { bust_row(self_id, 300), bust_row(self_id, 478) });
assert(lines(shown) == '108:12:B478', 'The new bust takes its own row: ' .. lines(shown));
shown = watch:refresh(301, s, snapshot, { bust_row(self_id, 478) });
assert(lines(shown) == '108:12:B478', 'and stays when the older bust wears off: ' .. lines(shown));
-- That older bust can also be just 30 s before the new one: one late in a roll's Double-Up window, the new one early in
-- the next roll. Its row then ends 270 s after the new bust, as long as a bust with three ranks of Bust Duration merits
-- lasts, so its length can't tell. The tracker listed it before the new bust, though, so the new bust doesn't keep it
-- either.
watch = rolls.new();
roll(self_id, 108, 5, false, false, 175);
roll(self_id, 108, 12, true, true, 180);
watch:refresh(180.5, s, snapshot, { bust_row(self_id, 450, 150.5) });
shown = watch:refresh(181, s, snapshot, { bust_row(self_id, 450, 150.5), bust_row(self_id, 480, 181) });
assert(lines(shown) == '108:12:B480', 'A bust 30 s older isn\'t kept either: ' .. lines(shown));
shown = watch:refresh(451, s, snapshot, { bust_row(self_id, 480, 181) });
assert(lines(shown) == '108:12:B480', 'and the new bust stays when the older bust wears off: ' .. lines(shown));
-- A bust's action and the status packets that list its Bust usually come in one frame, so the refresh that first lists
-- the bust's own row can read the same time Vantage saw the bust at. That row is still the bust's own, so each bust
-- keeps it, and after Fold only the bust still on you shows.
watch = rolls.new();
roll(self_id, 105, 6, false, false, 100);
roll(self_id, 105, 12, true, true, 101);
watch:refresh(101, s, snapshot, { bust_row(self_id, 401, 101) });
roll(self_id, 108, 5, false, false, 160);
roll(self_id, 108, 12, true, true, 162);
shown = watch:refresh(162, s, snapshot, { bust_row(self_id, 401, 101), bust_row(self_id, 462, 162) });
assert(lines(shown) == '108:12:B462 105:12:B401', 'Fixture: each bust has the row listed at its own time: ' .. lines(shown));
shown = watch:refresh(171, s, snapshot, { bust_row(self_id, 462, 162) });
assert(lines(shown) == '108:12:B462', 'A row listed at the bust\'s own time is its own, so Fold ends the older line: ' .. lines(shown));
-- No Bust left on the Corsair at all: every bust that had a row leaves at once.
watch = rolls.new();
roll(self_id, 105, 12, true, true, 900);
roll(self_id, 108, 12, true, true, 960);
shown = watch:refresh(961, s, snapshot, { bust_row(self_id, 1200), bust_row(self_id, 1260) });
assert(#shown == 2, 'Fixture: two busts with their rows.');
shown = watch:refresh(970, s, snapshot, {});
assert(#shown == 0, 'With no Bust left on the Corsair both lines leave: ' .. lines(shown));

-- A party member's Bust rows have times the tracker estimated, and their two Busts can come through as one row, so
-- their busts take the rows by age: the newest bust takes the row that ends last.
watch = rolls.new();
roll(ally, 105, 5, false, false, 600);
roll(ally, 105, 12, true, true, 604);
roll(ally, 105, 2, false, false, 665);
shown = watch:refresh(666, s, snapshot, { bust_row(ally, 904) });
assert(lines(shown) == '105:2 105:12:B904', 'A member\'s roll after their bust keeps the bust\'s line: ' .. lines(shown));
-- The member busts again, and their two Busts are still listed as one row: both lines stay.
roll(ally, 105, 12, true, true, 670);
shown = watch:refresh(671, s, snapshot, { bust_row(ally, 970) });
assert(lines(shown) == '105:12:B970 105:12:Bnil', 'A second bust listed as one row keeps both lines: ' .. lines(shown));
shown = watch:refresh(905, s, snapshot, { bust_row(ally, 970) });
assert(lines(shown) == '105:12:B970', 'The first leaves five minutes after it busted: ' .. lines(shown));
-- A member's busts of two rolls. With fewer Bust rows listed than busts held, the row is the newest bust's. The older
-- bust keeps its line, with no time to show, and takes its own row once one is listed.
watch = rolls.new();
roll(ally, 105, 5, false, false, 500);
roll(ally, 105, 12, true, true, 503);
roll(ally, 108, 5, false, false, 565);
roll(ally, 108, 12, true, true, 570);
shown = watch:refresh(571, s, snapshot, { bust_row(ally, 870), bust_row(ally, 803) });
assert(lines(shown) == '108:12:B870 105:12:B803', 'A member\'s busts of two rolls each show their own time: ' .. lines(shown));
shown = watch:refresh(572, s, snapshot, { bust_row(ally, 870) });
assert(#shown == 2 and shown[1].ability == 108 and shown[1].bust_deadline == 870, 'One row for two busts is the newer one: ' .. lines(shown));
assert(shown[2].ability == 105 and shown[2].bust and shown[2].bust_deadline == nil, 'The older bust keeps its line and never takes the newer time: ' .. lines(shown));
shown = watch:refresh(573, s, snapshot, { bust_row(ally, 803), bust_row(ally, 870) });
assert(lines(shown) == '108:12:B870 105:12:B803', 'Listed again, the older bust has its own time back: ' .. lines(shown));
-- With one row left, the older bust leaves five minutes after it happened, and the newer when its row goes.
shown = watch:refresh(802, s, snapshot, { bust_row(ally, 870) });
assert(#shown == 2, 'Inside its five minutes the older bust still shows: ' .. lines(shown));
shown = watch:refresh(804, s, snapshot, { bust_row(ally, 870) });
assert(lines(shown) == '108:12:B870', 'Five minutes after it busted, the older bust leaves: ' .. lines(shown));
shown = watch:refresh(871, s, snapshot, {});
assert(#shown == 0, 'And the newer leaves with its row.');
-- A bust Vantage never saw a row for still stays its five minutes, beside the new roll.
watch = rolls.new();
roll(ally, 105, 5, false, false, 700);
roll(ally, 105, 12, true, true, 704);
roll(ally, 105, 2, false, false, 765);
shown = watch:refresh(766, s, snapshot, {});
assert(lines(shown) == '105:2 105:12:Bnil', 'With no bust row seen the bust still shows: ' .. lines(shown));
shown = watch:refresh(1005, s, snapshot, {});
assert(#shown == 0, 'And leaves five minutes after it.');
return 'A bust keeps its own line and its own time';
