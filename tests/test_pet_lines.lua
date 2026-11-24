-- The pet display's optional lines (core/pet_lines.lua), each behind a tick on its Show tab that starts off: what your
-- pet fights and does, its distance and how long it has been out; an automaton's attachment recasts, its own
-- cooldowns, its build and its MP as a number; what an avatar costs; whether Healing Breath would fire; what Reward
-- would heal; the Sic mark; and the notices. The numbers are Phoenix's (data/pets.lua). The real addon takes the
-- packets here, over the pet fixture's game.
local fx = require('pet_fixture')();
local game, settings, pet = fx.game, fx.settings, require('core.pet');
local memory = AshitaCore.GetMemoryManager();
local player, party, entity = memory.GetPlayer(), memory.GetParty(), memory.GetEntity();
local config = settings.pet;
local function shown() return fx.app.state.view.pet; end
-- The line with this name, if the display has it.
local function line(name)
    local view = shown();
    for index = 1, view and view.line_count or 0 do
        if view.lines[index].name == name then return view.lines[index]; end
    end
end
local function count() return shown() and shown().line_count or 0; end

-- The names the game's resources give.
local spells, abilities, skills, items = { [1] = 'Cure', [4] = 'Cure IV', [58] = 'Paralyze', [144] = 'Fire' }, { [640] = 'Healing Breath' },
    { [1946] = 'Shock Absorber', [1945] = 'Provoke', [300] = 'Lamb Chop' }, { [0x2100 + 3] = 'Inhibitor' };
AshitaCore.GetResourceManager = function()
    return {
        GetSpellById = function(_, id) return spells[id] and { Name = { spells[id] } } or nil; end,
        GetAbilityById = function(_, id) return abilities[id - 512] and { Name = { abilities[id - 512] } } or nil; end,
        GetItemById = function(_, id) return items[id] and { Name = { items[id] } } or nil; end,
        GetString = function(_, list, id) return list == 'monsters.abilities' and skills[id + 256] or nil; end,
    };
end;

-- Every tick starts off, and a save holds only true or false for one.
local fresh = pet.make();
for _, key in ipairs(pet.extras) do
    assert(fresh[key] == false and config[key] == false, key .. ' starts off.');
    assert(pet.tidy({ [key] = 1 })[key] == false and pet.tidy({ [key] = true })[key] == true, key .. ' is true or false.');
end
assert(#pet.extras == 15 and fresh.alert_hp_percent == 25 and pet.tidy({ alert_hp_percent = 500 }).alert_hp_percent == 99
    and pet.tidy({ alert_hp_percent = 'low' }).alert_hp_percent == 25, 'The low HP line is 25% at first, from 1 to 99.');

-- A whole 0x044 PUP page: head, frame, attachments, name, HP, MP, skills and stats (0x044_extended_job_pup.h :40-81).
local function page(build)
    local bytes = MOCK.bytes(0xA0);
    MOCK.put(bytes, 4, 1, 18);
    MOCK.put(bytes, 8, 1, build.head); MOCK.put(bytes, 9, 1, build.frame);
    for slot, byte in ipairs(build.attachments or {}) do MOCK.put(bytes, 0x09 + slot, 1, byte); end
    for i = 1, #build.name do bytes[0x57 + i] = build.name:byte(i); end
    MOCK.put(bytes, 0x68, 2, build.hp or 800); MOCK.put(bytes, 0x6A, 2, build.max_hp or 1000);
    MOCK.put(bytes, 0x6C, 2, build.mp or 0); MOCK.put(bytes, 0x6E, 2, build.max_mp or 0);
    for index, pair in ipairs(build.skills or {}) do MOCK.put(bytes, 0x6C + index * 4, 2, pair[1]); MOCK.put(bytes, 0x6E + index * 4, 2, pair[2]); end
    for index, pair in ipairs(build.stats or {}) do MOCK.put(bytes, 0x7C + index * 4, 2, pair[1]); MOCK.put(bytes, 0x7E + index * 4, 2, pair[2]); end
    MOCK.fire('packet_in', MOCK.packet(0x044, bytes));
end
-- A 0x068 with the pet's HP, MP, TP and what it attacks.
local function sync(index, name, hpp, mpp, tp, target)
    local bytes = MOCK.bytes(0x2C);
    MOCK.put(bytes, 8, 4, game.id); MOCK.put(bytes, 0x0C, 2, index); MOCK.put(bytes, 0x0E, 1, hpp or 100); MOCK.put(bytes, 0x0F, 1, mpp or 0);
    MOCK.put(bytes, 0x10, 2, tp or 0); MOCK.put(bytes, 0x14, 4, target or 0);
    for i = 1, #name do bytes[0x17 + i] = name:byte(i); end
    MOCK.fire('packet_in', MOCK.packet(0x068, bytes));
end
local function maneuvers(list)
    game.buffs = {};
    for _, effect in ipairs(list) do game.buffs[#game.buffs + 1] = { effect = effect, ends = MOCK.now + 60 }; end
    fx.status();
    fx.step();
end

-- With every tick off the display has no lines, whatever the pet does.
local CRAB, crab_index, PET, pet_index = 0x1000301, 0x301, 0x1000700, 0x700;
game.units[crab_index] = { id = CRAB, index = crab_index, name = 'Land Crab', flags = 0x10, hpp = 63 };
game.job = 9;
fx.step();
game.pet = { index = pet_index, id = PET, name = 'SheepFamiliar', flags = 0x02, hpp = 80 };
sync(pet_index, 'SheepFamiliar', 80, 0, 300, CRAB);
fx.step();
assert(shown() and count() == 0 and not shown().sic_mark, 'With no tick on there are no lines.');
fx.action(PET, 11, 300, { { CRAB, 185, 212 } });
fx.step();
assert(count() == 0, 'Nor after the pet uses a move.');

-- A move being readied or a spell being cast is read only from your own pet. Anyone else's start gives nothing at
-- all, whatever its rows hold. The action id of a start is a four letter code (src/map/enums/four_cc.h): "cate" as a
-- move begins and "spte" as it is stopped, "cawh" and "spwh" for white magic. A stopped move names the pet itself
-- and no move (src/map/action/interrupts.cpp :151-170).
local MOVE, MOVE_STOPPED, WHITE = 0x65746163, 0x65747073, 0x68776163;
local observer = require('core.observer');
local read, seen = observer.read, nil;
observer.read = function(...) seen = read(...); return seen; end;
fx.action(CRAB, 7, MOVE, { { PET, 1, 50 } });
assert(#seen == 0, 'A mob\'s readied move isn\'t read: ' .. #seen);
fx.action(PET, 7, MOVE, { { CRAB, 43, 300 } });
assert(#seen == 1 and seen[1].kind == 'pet_start' and seen[1].id == 300 and not seen[1].stopped, 'Your pet\'s is, as one start.');
fx.action(PET, 7, MOVE_STOPPED, { { PET, 0, 0 } });
assert(#seen == 1 and seen[1].kind == 'pet_start' and seen[1].stopped == true, 'And one that was stopped says so.');
observer.read = read;

-- What it fights: the mob the 0x068 names while it attacks, with its HP, marked when it isn't your target.
config.show_target = true;
fx.step();
local fighting = assert(line('Fighting'), 'The pet\'s target has a line.');
assert(fighting.value == 'Land Crab 63%' and fighting.warn == true, 'It names the mob and its HP, and says it isn\'t your target: ' .. tostring(fighting.value));
memory.GetTarget().GetTargetIndex = function() return crab_index; end;
fx.step();
assert(line('Fighting').warn == false, 'With the same target it isn\'t marked.');
assert(fx.draw():find('|Fighting|', 1, true) and fx.draw():find('|Land Crab 63%|', 1, true), 'The display draws the line: ' .. fx.draw());
sync(pet_index, 'SheepFamiliar', 80, 0, 300, 0);
fx.step();
assert(not line('Fighting') and count() == 0, 'A pet that isn\'t attacking has no such line.');
config.show_target = false;

-- What it does: the last move with its damage, then a move being readied, which goes when it ends or is stopped.
config.show_action = true;
fx.step();
assert(line('Last move') and line('Last move').value == 'Lamb Chop 212', 'The last move and its damage: ' .. tostring(line('Last move') and line('Last move').value));
fx.action(PET, 7, MOVE, { { CRAB, 0, 300 } });
fx.step();
assert(line('Readies') and line('Readies').value == 'Lamb Chop' and not line('Last move'), 'A move it readies takes the line.');
fx.action(PET, 7, MOVE_STOPPED, { { PET, 0, 0 } });
fx.step();
assert(not line('Readies') and line('Last move'), 'Stopped, the last move is back.');
fx.action(PET, 8, WHITE, { { PET, 0, 4 } });
fx.step();
assert(line('Casting') and line('Casting').value == 'Cure IV', 'A spell it casts is named.');
fx.action(PET, 4, 4, { { PET, 7, 180 } });
fx.step();
assert(line('Last move').value == 'Cure IV', 'A finished spell that did no damage shows by name alone: ' .. line('Last move').value);
-- What failed isn't something the pet finished: a swing Paralysis or Intimidate stopped (84, 106), a pact whose target
-- got out of reach (328), a move whose target was out of range (78) or that had none in its area (76), and a spell
-- Paralysis or Intimidate stopped at its end. Each comes as category 4 with no action id, or with the spell's id and
-- 84 or 106 (Phoenix src/map/action/interrupts.cpp :39-128, :193-233, :299-422). It still ends what the pet was
-- readying, as a move that failed for range sends no stop of its own (src/map/ai/states/mobskill_state.cpp :244-256).
local function last() return line('Last move') and line('Last move').value; end
fx.action(PET, 11, 300, { { CRAB, 185, 212 } });
fx.step();
assert(last() == 'Lamb Chop 212', 'A move that went off: ' .. tostring(last()));
for _, message in ipairs({ 84, 106 }) do
    fx.action(PET, 4, 0, { { CRAB, message } });
    fx.step();
    assert(last() == 'Lamb Chop 212', 'A swing stopped with message ' .. message .. ' isn\'t a move: ' .. tostring(last()));
end
fx.action(PET, 7, MOVE, { { CRAB, 0, 300 } });
fx.action(PET, 4, 0, { { CRAB, 328, 300 } });
fx.action(PET, 7, MOVE_STOPPED, { { PET, 0, 0 } });
fx.step();
assert(not line('Readies') and last() == 'Lamb Chop 212', 'Nor a pact whose target got out of reach: ' .. tostring(last()));
for _, row in ipairs({ { CRAB, 78 }, { PET, 76 } }) do
    fx.action(PET, 7, MOVE, { { CRAB, 43, 300 } });
    fx.step();
    assert(line('Readies'), 'The pet readies a move.');
    fx.action(PET, 4, 0, { row });
    fx.step();
    assert(not line('Readies') and last() == 'Lamb Chop 212', 'A move that failed with message ' .. row[2] .. ' ends the readying and isn\'t a move: '
        .. tostring(line('Readies') and line('Readies').value) .. ', ' .. tostring(last()));
end
local WHITE_STOPPED = 0x68777073;
for _, message in ipairs({ 84, 106 }) do
    fx.action(PET, 8, WHITE, { { PET, 0, 4 } });
    fx.action(PET, 4, 4, { { CRAB, message } });
    fx.action(PET, 8, WHITE_STOPPED, { { PET, 0, 4 } });
    fx.step();
    assert(not line('Casting') and last() == 'Lamb Chop 212', 'A spell stopped with message ' .. message .. ' didn\'t go off: ' .. tostring(last()));
end
-- The observer gives a failure as a stop, never as a finish.
observer.read = function(...) seen = read(...); return seen; end;
fx.action(PET, 4, 0, { { CRAB, 84 } });
assert(#seen == 1 and seen[1].kind == 'pet_start' and seen[1].stopped == true and seen[1].category == 4,
    'A failure reads as a stop: ' .. tostring(seen[1] and seen[1].kind));
observer.read = read;
fx.step(61);
assert(not line('Last move') and count() == 0, 'A minute on, the line goes.');
-- Someone else's pet, or the mob, says nothing here.
fx.action(CRAB, 11, 300, { { PET, 185, 90 } });
fx.step();
assert(count() == 0, 'Only your own pet\'s moves count.');
config.show_action = false;

-- Distance, in yalms, marked when the pet is too far for the command your job has.
config.show_distance = true;
entity.GetDistance = function() return 100; end;
fx.step();
assert(line('Distance').value == '10.0' and line('Distance').warn == false, 'Ten yalms: ' .. line('Distance').value);
entity.GetDistance = function() return 26 * 26; end;
fx.step();
assert(line('Distance').value == '26.0' and line('Distance').warn == true, 'Past 25 a BST\'s pet is too far for Fight.');
game.job = 5;
fx.step();
assert(line('Distance').warn == false, 'A job with no such command marks nothing.');
game.job = 9;
config.show_distance = false;

-- How long it has been out.
config.show_time_out = true;
fx.step();
local out = line('Out for').value;
fx.step(75);
assert(out:match('^%d+:%d%d$') and line('Out for').value ~= out, 'It counts up: ' .. out .. ' then ' .. line('Out for').value);
config.show_time_out = false;

-- The Sic mark is for a BST, main or support.
config.sic_mark = true;
fx.step();
assert(shown().sic_mark == true, 'A BST has the mark.');
game.job, game.sub = 5, 9;
fx.step();
assert(shown().sic_mark == true, 'So does a /BST.');
game.sub = 0;
fx.step();
assert(shown().sic_mark == false, 'Another job has none.');
config.sic_mark = false;
game.job = 9;

-- What Reward would heal: least + per * (MND - from) by the pet food on, then the percent your gear adds.
config.show_reward = true;
player.GetStat = function(_, index) return index == 5 and 50 or index == 6 and game.chr or 0; end;
player.GetStatModifier = function(_, index) return index == 5 and 10 or index == 6 and game.chr_bonus or 0; end;
fx.step();
assert(line('Reward').value == 'No pet food' and line('Reward').warn, 'With no pet food on, it says so.');
game.items[3] = 17021;
fx.step();
assert(line('Reward').value == 'Heals 395', 'Zeta at 60 MND: 350 + 3 * 15 = ' .. line('Reward').value);
game.items[3] = 17016;
fx.step();
assert(line('Reward').value == 'Heals 125', 'Alpha at 60 MND: 25 + 2 * 50 = ' .. line('Reward').value);
game.items[3], game.items[6], game.items[8] = 17021, 13706, 15140;
fx.step();
assert(line('Reward').value == 'Heals 513', 'Ogre Gloves and Monster Gaiters add 30%: 395 + 118 = ' .. line('Reward').value);
-- Reward heals only a jug pet or a charmed mob (scripts/globals/job_utils/beastmaster.lua :279-288). An avatar, a
-- wyvern or an automaton has no line, whatever your jobs, and no warning with no pet food either. An automaton has
-- none even before the status the server sends a PUP has named it. Every pet the server makes is at 0x700 or past it.
local function reward_for(job, sub, name, index, id)
    game.job, game.sub = job, sub;
    game.pet = { index = index, id = id, name = name, flags = 0x02, hpp = 80 };
    sync(index, name, 80, 0, 0);
    fx.step();
    return line('Reward') and line('Reward').value;
end
game.items = { [3] = 17016 };
for _, case in ipairs({ { 15, 9, 'Carbuncle' }, { 9, 15, 'Garuda' }, { 14, 9, 'Azure' }, { 9, 18, 'Ironsides' }, { 18, 9, 'Ironsides' } }) do
    local value = reward_for(case[1], case[2], case[3], 0x702, 0x1000802);
    assert(value == nil, case[3] .. ' as job ' .. case[1] .. ' with support ' .. case[2] .. ' takes no Reward: ' .. tostring(value));
end
game.items = {};
assert(reward_for(15, 9, 'Carbuncle', 0x702, 0x1000802) == nil, 'Nor is an avatar\'s missing pet food a warning.');
game.items = { [3] = 17016 };
for _, case in ipairs({ { 15, 9, 'SheepFamiliar', 0x702, 0x1000802 }, { 14, 9, 'SheepFamiliar', 0x702, 0x1000802 }, { 18, 9, 'SheepFamiliar', 0x702, 0x1000802 },
    { 9, 0, 'Land Crab', crab_index, CRAB }, { 14, 9, 'Land Crab', crab_index, CRAB }, { 18, 9, 'Land Crab', crab_index, CRAB } }) do
    local value = reward_for(case[1], case[2], case[3], case[4], case[5]);
    assert(value == 'Heals 125', case[3] .. ' as job ' .. case[1] .. ' with support ' .. case[2] .. ' takes Reward: ' .. tostring(value));
end
-- Sic commands only a jug pet or a charmed mob too (modules/era/sql/wotg/job_adjustments.sql :25,
-- src/map/utils/charutils.cpp :6393-6400), so the Sic mark goes by the same pets.
config.sic_mark = true;
for _, case in ipairs({ { 15, 9, 'Carbuncle' }, { 9, 15, 'Garuda' }, { 14, 9, 'Azure' }, { 9, 18, 'Ironsides' }, { 18, 9, 'Ironsides' } }) do
    reward_for(case[1], case[2], case[3], 0x702, 0x1000802);
    assert(shown().sic_mark == false, case[3] .. ' as job ' .. case[1] .. ' with support ' .. case[2] .. ' has no Sic mark.');
end
-- A pet whose kind can't be named yet, such as a jug before its name comes, keeps the mark.
for _, case in ipairs({ { 15, 9, 'SheepFamiliar', 0x702, 0x1000802 }, { 9, 0, 'Land Crab', crab_index, CRAB }, { 18, 9, 'Land Crab', crab_index, CRAB },
    { 9, 0, 'Unknown', 0x702, 0x1000802 } }) do
    reward_for(case[1], case[2], case[3], case[4], case[5]);
    assert(shown().sic_mark == true, case[3] .. ' as job ' .. case[1] .. ' with support ' .. case[2] .. ' has the Sic mark.');
end
config.sic_mark = false;
game.job, game.sub = 9, 0;
game.pet = { index = pet_index, id = PET, name = 'SheepFamiliar', flags = 0x02, hpp = 80 };
sync(pet_index, 'SheepFamiliar', 80, 0, 300);
fx.step();
game.items = {};
config.show_reward = false;

-- The notices: one each time a line is crossed, through the alert notices, which need Alerts on.
local function notices()
    local out = {};
    for _, notice in ipairs(fx.app.state.view.notices or {}) do out[#out + 1] = notice.message; end
    return table.concat(out, '|');
end
config.alert_hp, config.alert_tp = true, true;
settings.alerts.enabled, settings.alerts.muted = true, false;
player.GetPetTP = function() return 300; end;
fx.step();
assert(notices() == '', 'Above the line, nothing.');
game.pet.hpp = 24;
fx.step();
assert(notices():find('SheepFamiliar is at 24% HP', 1, true), 'HP falling to the line raises a notice: ' .. notices());
fx.step(11);
game.pet.hpp = 20;
fx.step();
assert(not notices():find('20%%'), 'It says so once, not at every HP after.');
game.pet.hpp = 90;
fx.step();
game.pet.hpp = 10;
fx.step();
assert(notices():find('SheepFamiliar is at 10% HP', 1, true), 'Back over the line and under again, it says so again: ' .. notices());
player.GetPetTP = function() return 1010; end;
fx.step();
assert(notices():find('SheepFamiliar has 1010 TP', 1, true), 'TP reaching 1000 raises one: ' .. notices());
-- With Alerts off or muted, nothing is raised at all.
local alerts = fx.app.alerts;
local raise, raised = alerts.announce, 0;
alerts.announce = function(self, ...) raised = raised + 1; return raise(self, ...); end;
local function tp_crosses()
    player.GetPetTP = function() return 0; end;
    fx.step(11);
    player.GetPetTP = function() return 1200; end;
    fx.step();
    return raised;
end
settings.alerts.enabled = false;
assert(tp_crosses() == 0, 'With Alerts off there is no notice.');
settings.alerts.enabled, settings.alerts.muted = true, true;
assert(tp_crosses() == 0, 'Nor while Alerts are muted.');
settings.alerts.muted = false;
assert(tp_crosses() == 1, 'With Alerts on again, the next crossing raises one.');
alerts.announce = nil;
-- The same notice within 10 seconds is raised once.
local held = #alerts.notices;
assert(alerts:announce('pet_test', 'Once', MOCK.now) == true and alerts:announce('pet_test', 'Once', MOCK.now + 9) == false
    and #alerts.notices == held + 1, 'The same notice within 10 seconds isn\'t raised twice.');
assert(alerts:announce('pet_test', 'Once', MOCK.now + 10) == true, 'After 10 seconds it is.');
config.alert_hp, config.alert_tp = false, false;
return 'The pet display\'s optional lines for any pet and a BST';
