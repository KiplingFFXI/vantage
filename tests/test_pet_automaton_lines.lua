-- The pet display's optional lines for an automaton, an avatar and a wyvern (core/pet_lines.lua), each behind a tick
-- that starts off. An automaton's attachments fire on recasts Phoenix sets at each use, and all start when it comes
-- out (scripts/globals/pets/automaton.lua :682-694); its own spells, shots and Shield Bash have cooldowns by head and
-- frame, as era plays them; the 0x044 gives its build and its MP. An avatar's cost is measured from your MP, and
-- Healing Breath goes by your HP, your sub job and your helm. The real addon takes the packets here.
local fx = require('pet_fixture')();
local game, settings, pet = fx.game, fx.settings, require('core.pet');
local memory = AshitaCore.GetMemoryManager();
local player, party = memory.GetPlayer(), memory.GetParty();
local config = settings.pet;
local function shown() return fx.app.state.view.pet; end
local function line(name)
    local view = shown();
    for index = 1, view and view.line_count or 0 do
        if view.lines[index].name == name then return view.lines[index]; end
    end
end
local function count() return shown() and shown().line_count or 0; end
local function left(name) local found = line(name); return found and found.deadline and math.floor(found.deadline - MOCK.now + 0.5) or nil; end
AshitaCore.GetResourceManager = function()
    return { GetItemById = function(_, id) return id == 0x2100 + 3 and { Name = { 'Inhibitor' } } or nil; end,
        GetSpellById = function() return nil; end, GetAbilityById = function() return nil; end, GetString = function() return nil; end };
end;

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
local function maneuvers(list)
    game.buffs = {};
    for _, effect in ipairs(list) do game.buffs[#game.buffs + 1] = { effect = effect, ends = MOCK.now + 600 }; end
    fx.status();
    fx.step();
end
local FIRE, ICE, WIND, EARTH, WATER, LIGHT, DARK, OVERDRIVE = 300, 301, 302, 303, 305, 306, 307, 166;
local PUPPET, index, CRAB = 0x1000703, 0x703, 0x1000301;
game.job = 18;
fx.step();

-- A Valoredge automaton with Strobe, Shock Absorber, Flashbulb, Economizer, Inhibitor and two Barrier Modules.
local build = { name = 'Ironsides', head = 2, frame = 0x21, attachments = { 1, 97, 194, 230, 3, 107, 104 }, hp = 780, max_hp = 1000, mp = 0, max_mp = 0,
    skills = { { 245, 269 }, { 0, 0 }, { 120, 203 } }, stats = { { 60, 5 }, { 55, 0 }, { 58, 2 }, { 50, 0 }, { 30, 0 }, { 28, 0 }, { 25, 0 } } };
page(build);
game.pet = { index = index, id = PUPPET, name = 'Ironsides', flags = 0x02, hpp = 78 };
fx.sync(index, 78, 'Ironsides');
fx.step();
assert(count() == 0, 'With no tick on there are no lines.');
local automaton = fx.app.state.snapshot.pet.automaton;
assert(automaton and automaton.head == 2 and automaton.frame == 0x21 and automaton.attachments[2] == 97 and automaton.attachments[8] == 0
    and automaton.skills[1][2] == 269 and automaton.stats[1][1] == 60 and automaton.stats[7][1] == 25, 'The whole page is read.');

-- Attachment timers: every recast starts when the automaton comes out, by what it has on.
config.show_attachments = true;
fx.step();
assert(left('Strobe') == 30 and left('Shock Absorber') == 180 and left('Flashbulb') == 45 and left('Economizer') == 60,
    'Each starts its recast at spawn: ' .. tostring(left('Strobe')) .. ' ' .. tostring(left('Shock Absorber')) .. ' ' .. tostring(left('Economizer')));
assert(count() == 4 and not line('Inhibitor') and not line('Replicator'), 'Only the attachments that fire, and only the ones on, have a line.');
fx.step(31);
assert(line('Strobe').value == 'Needs Fire' and line('Strobe').warn == true and not line('Strobe').deadline, 'Ready with no maneuver, it says which it needs.');
maneuvers({ FIRE });
assert(line('Strobe').value == 'Ready' and line('Strobe').warn == false, 'With the maneuver up, it is ready.');
-- It fires: the recast is the one set at its use, counted from then.
fx.action(PUPPET, 11, 1945, { { CRAB, 0, 0 } });
fx.step();
assert(left('Strobe') == 30 and line('Strobe').total == 30, 'Its use starts its recast again.');
fx.step(150);
maneuvers({ EARTH });
assert(line('Shock Absorber').value == 'Ready', 'Three minutes after it came out, Shock Absorber is ready.');
fx.action(PUPPET, 11, 1946, { { PUPPET, 0, 0 } });
fx.step();
assert(left('Shock Absorber') == 180, 'And three minutes more after it fires.');
-- Economizer starts at 60 but takes 180 after a use.
fx.action(PUPPET, 11, 2068, { { PUPPET, 0, 0 } });
fx.step();
assert(left('Economizer') == 180, 'Economizer\'s recast at use is longer than at spawn.');
-- Two of one kind share a recast and a line.
build.attachments = { 1, 9, 97, 105 };
page(build);
fx.step();
assert(count() == 2 and line('Strobe') and line('Shock Absorber') and not line('Strobe II'), 'Strobe and Strobe II fire one skill, so they share a line.');
-- A zone change makes the automaton anew, so every recast starts over.
fx.zone(103);
fx.step();
page(build);
fx.sync(index, 78, 'Ironsides');
fx.step();
assert(left('Strobe') == 30 and left('Shock Absorber') == 180, 'After a zone change they start over: ' .. tostring(left('Strobe')));
build.attachments = { 1, 97, 194, 230, 3, 107, 104 };
page(build);
config.show_attachments = false;

-- Its own cooldowns. A Valoredge frame uses Shield Bash every 3 minutes, less 5 seconds for each Earth maneuver for
-- each Barrier Module.
config.show_cooldowns = true;
maneuvers({});
assert(line('Shield Bash').value == 'Not seen yet' and count() == 1, 'A Valoredge frame has Shield Bash alone, and no time until it is seen.');
fx.action(PUPPET, 11, 1944, { { CRAB, 0, 0 } });
fx.step();
assert(left('Shield Bash') == 180, 'Three minutes from the bash.');
maneuvers({ EARTH, EARTH });
assert(left('Shield Bash') == 160, 'Two Earth maneuvers take 10 seconds off for each Barrier Module: ' .. tostring(left('Shield Bash')));
-- A Sharpshot frame shoots: 20 seconds with a Sharpshot head, 36 with another, less a Drum Magazine's seconds.
build.head, build.frame, build.attachments = 3, 0x22, { 69 };
page(build);
maneuvers({});
fx.action(PUPPET, 11, 1949, { { CRAB, 185, 150 } });
fx.step();
assert(left('Ranged attack') == 18 and count() == 1, 'A Sharpshot head and a Drum Magazine with no maneuver: 20 less 2 = ' .. tostring(left('Ranged attack')));
maneuvers({ WIND, WIND, WIND });
assert(left('Ranged attack') == 12, 'Three Wind maneuvers take 8 off.');
build.head = 2;
page(build);
maneuvers({});
assert(left('Ranged attack') == 34, 'Another head shoots every 36 seconds: ' .. tostring(left('Ranged attack')));
-- A Stormwaker frame casts by its head's era cooldowns: 25 seconds between any two spells with a Soulsoother head,
-- 15 between cures and 15 between status removals.
build.head, build.frame, build.attachments = 5, 0x23, { 33, 195 };
page(build);
fx.step();
assert(line('Next spell').value == 'Not seen yet' and line('Healing') and line('Enfeebling') and line('Status removal') and not line('Elemental'),
    'A Soulsoother head has its kinds of spell, and no elemental one.');
-- A spell's start carries a four letter code for its kind of magic: "cawh" for white, "cabk" for black, and "spwh"
-- when a white one is stopped, which names the automaton itself with the spell (src/map/enums/four_cc.h,
-- src/map/action/interrupts.cpp :278-297).
local WHITE, WHITE_STOPPED, BLACK = 0x68776163, 0x68777073, 0x6B626163;
fx.action(PUPPET, 8, WHITE, { { game.id, 0, 3 } });
fx.step();
assert(left('Next spell') == 23 and left('Healing') == 12, 'Mana Booster takes 2 off the wait between spells and a Damage Gauge 3 off cures: '
    .. tostring(left('Next spell')) .. ' ' .. tostring(left('Healing')));
assert(line('Enfeebling').value == 'Not seen yet', 'A cure doesn\'t start the enfeebling wait.');
maneuvers({ ICE, ICE, ICE });
assert(left('Next spell') == 17, 'Three Ice maneuvers make Mana Booster take 8 off.');
maneuvers({ ICE, OVERDRIVE });
assert(left('Next spell') == 17, 'Under Overdrive one maneuver counts as three.');
-- A spell stopped part way through: its wait counts from when it started, as the server's does.
config.show_action = true;
fx.action(PUPPET, 8, WHITE, { { CRAB, 0, 58 } });
fx.step(3);
assert(line('Casting'), 'A spell under way shows as Casting.');
fx.action(PUPPET, 8, WHITE_STOPPED, { { PUPPET, 0, 58 } });
fx.step();
assert(left('Enfeebling') == 27, 'A spell that was stopped counts its wait from its start, not from when it stopped: ' .. tostring(left('Enfeebling')));
assert(not line('Casting'), 'And it stops showing as Casting.');
config.show_action = false;
-- A head with no row for a kind doesn't cast it, and a frame that doesn't cast has no spell lines.
build.head, build.frame, build.attachments = 6, 0x20, {};
page(build);
maneuvers({});
assert(line('Elemental') and line('Enfeebling') and not line('Healing') and not line('Status removal'), 'A Spiritreaver head doesn\'t cure.');
-- Drain and Aspir start the enfeebling wait: Phoenix casts them from the same check as the enfeebling spells
-- (src/map/ai/controllers/automaton_controller.cpp :406-411, :905-916).
fx.action(PUPPET, 8, BLACK, { { CRAB, 0, 245 } });
fx.step();
assert(left('Enfeebling') == 45 and line('Elemental').value == 'Not seen yet', 'Drain starts the 45 second enfeebling wait, not the elemental one: '
    .. tostring(left('Enfeebling')) .. ' ' .. tostring(line('Elemental').value));
config.show_cooldowns = false;

-- Its build, as the page gave it.
build.head, build.frame, build.attachments = 2, 0x21, { 1, 97, 3 };
page(build);
config.show_build = true;
fx.step();
assert(line('Build').value == 'Valoredge / Valoredge', 'Head and frame by name.');
assert(line('Melee skill').value == '245 / 269' and line('Magic skill').value == '120 / 203' and not line('Ranged skill'), 'Each skill it has, with its cap.');
assert(line('STR 65  DEX 55  VIT 60  AGI 50') and line('INT 30  MND 28  CHR 25'), 'Its stats, with what the attachments add.');
assert(line('Strobe') and line('Strobe').value == 'Shock Absorber' and line('Inhibitor'), 'Its attachments, two to a line, named from the game when not one that fires.');
-- A stat bonus is a signed number the server writes into two bytes (Phoenix
-- src/map/packets/s2c/0x044_extended_job_pup.cpp :98-111, getMod), so one under zero arrives as 65536 less it and
-- comes off the stat.
local plain_stats = build.stats;
build.stats = { { 60, 65531 }, { 55, 0 }, { 58, 2 }, { 50, 65506 }, { 30, 65535 }, { 28, 3 }, { 25, 65521 } };
page(build);
fx.step();
local read_stats = fx.app.state.snapshot.pet.automaton.stats;
assert(read_stats[1][2] == -5 and read_stats[4][2] == -30 and read_stats[5][2] == -1 and read_stats[7][2] == -15 and read_stats[3][2] == 2,
    'A bonus under zero is read with its sign: ' .. tostring(read_stats[1][2]));
assert(line('STR 55  DEX 55  VIT 60  AGI 20') and line('INT 29  MND 31  CHR 10'), 'And it comes off the stat.');
build.stats = plain_stats;
page(build);
fx.step();
config.show_build = false;

-- MP as a number, while it agrees with the percent.
build.mp, build.max_mp = 168, 420;
page(build);
player.GetPetMPPercent = function() return 40; end;
fx.step();
config.exact_mp = true;
assert(shown().mp == 168 and shown().max_mp == 420 and fx.draw():find('|MP 168/420|', 1, true), 'The MP bar shows the number: ' .. fx.draw());
config.exact_mp = false;
assert(fx.draw():find('|MP 40%|', 1, true), 'With the tick off, the percent.');
config.exact_mp = true;
player.GetPetMPPercent = function() return 70; end;
fx.step();
assert(not shown().mp and fx.draw():find('|MP 70%|', 1, true), 'A number that doesn\'t agree with the percent isn\'t shown.');
config.exact_mp = false;

-- An avatar's cost: the step your MP most often goes down by, and how long your MP lasts at 3 seconds a step.
local mp = 400;
party.GetMemberMP = function() return mp; end;
game.job = 15;
game.pet = { index = 0x710, id = 0x1000710, name = 'Garuda', flags = 0x02, hpp = 100 };
fx.sync(0x710, 100, 'Garuda');
config.show_upkeep = true;
fx.step();
assert(line('MP cost').value == 'Measuring', 'At first it is measuring.');
for _ = 1, 3 do mp = mp - 7; fx.step(3); end
assert(line('MP cost').value == '7 a tick, 2:42 left', '379 MP at 7 every 3 seconds: ' .. line('MP cost').value);
mp = mp - 68;
fx.step();
mp = mp - 7;
fx.step(3);
assert(line('MP cost').value:find('^7 a tick'), 'A pact\'s MP isn\'t taken for the cost: ' .. line('MP cost').value);
fx.step(60);
assert(line('MP cost').value == 'None', 'With no step down for a while, it costs nothing.');
config.show_upkeep = false;
game.job = 18;
fx.step();
assert(not line('MP cost'), 'Only a SMN has the line.');

-- Healing Breath: at a third of your HP with a casting sub job, a half with a Drachen Armet, a quarter with a sub job
-- that heals only you, and never with one that makes the wyvern fight.
local hp = { [0] = 100, [1] = 100 };
party.GetMemberHPPercent = function(_, slot) return hp[slot] or 100; end;
game.job, game.sub = 14, 3;
game.pet = { index = 0x720, id = 0x1000720, name = 'Wyvern', flags = 0x02, hpp = 100 };
fx.sync(0x720, 100, 'Wyvern');
config.show_breath = true;
fx.step();
assert(line('Breath').value == 'At 33% HP', 'A /WHM\'s wyvern waits for a third of your HP: ' .. line('Breath').value);
hp[0] = 33;
fx.step();
assert(line('Breath').value == 'Ready for you', 'At a third it would fire on you.');
hp[0] = 45;
fx.step();
assert(line('Breath').value == 'At 33% HP');
game.items[4] = 12519;
fx.step();
assert(line('Breath').value == 'Ready for you', 'A Drachen Armet makes it a half.');
game.items = {};
hp[0] = 100;
game.members[1] = { id = 1002, index = 0x401, name = 'Healer' };
hp[1] = 20;
fx.step();
assert(line('Breath').value == 'Ready for Healer', 'A party member under the line gets it from a /WHM\'s wyvern.');
game.sub = 7;
fx.step();
assert(line('Breath').value == 'At 25% HP', 'A /PLD\'s wyvern heals only you, at a quarter.');
game.sub = 1;
fx.step();
assert(line('Breath').value == 'Not with this sub job', 'A /WAR\'s wyvern never uses it.');
-- You must be within 14 yalms of the wyvern, as a member must (scripts/globals/pets/wyvern.lua :61-68). Past that it
-- says so, and a member it can reach is next.
local entity = memory.GetEntity();
local near = entity.GetDistance;
game.sub, hp[0], hp[1] = 3, 20, 100;
entity.GetDistance = function() return 15 * 15; end;
fx.step();
assert(line('Breath').value == 'Too far' and line('Breath').warn == true, 'Low enough but 15 yalms from the wyvern is too far: '
    .. line('Breath').value);
hp[1] = 20;
fx.step();
assert(line('Breath').value == 'Ready for Healer', 'With you out of reach a member in reach gets it.');
hp[1] = 100;
entity.GetDistance = function() return 14 * 14; end;
fx.step();
assert(line('Breath').value == 'Ready for you', 'At 14 yalms it reaches you.');
entity.GetDistance = near;
-- Phoenix goes by your HP against a third of your max HP rounded down, not by the percent: with 1000 max HP that is
-- 333, so 339 isn't low enough though the game shows 33%.
local own_hp = 339;
party.GetMemberHP = function(_, slot) return slot == 0 and own_hp or 0; end;
player.GetHPMax = function() return 1000; end;
hp[0] = 33;
fx.step();
assert(line('Breath').value == 'At 33% HP', 'At 339 of 1000 HP it wouldn\'t fire: ' .. line('Breath').value);
own_hp = 333;
fx.step();
assert(line('Breath').value == 'Ready for you', 'At 333 of 1000 HP it would.');
own_hp = 0;
fx.step();
assert(line('Breath').value == 'At 33% HP', 'At 0 HP you are past healing.');
party.GetMemberHP, player.GetHPMax = nil, nil;
hp[0] = 100;
config.show_breath = false;
game.job = 18;
fx.step();
assert(count() == 0, 'With the ticks off again there are no lines.');

-- Sample displays show each ticked line for the job, with made-up values.
config.show_attachments, config.show_target, config.preview = true, true, true;
fx.step();
local text = fx.draw();
assert(text:find('|Fighting|', 1, true) and text:find('|Strobe|', 1, true) and text:find('|Needs Earth|', 1, true), 'The samples have the ticked lines: ' .. text);
-- A support job's pet is sampled when your main job has none: WAR/PUP gets the automaton with its lines. A support
-- DRG has no wyvern, so WAR/DRG gets the plain sample.
local support = pet.samples(MOCK.now, 1, config, 18);
assert(support.name == 'Sample automaton' and support.line_count > 0 and support.lines[1].name ~= nil, 'WAR/PUP samples the automaton: ' .. support.name);
local none = pet.samples(MOCK.now, 1, config, 14);
assert(none.name == 'Sample pet', 'WAR/DRG samples a plain pet: ' .. none.name);
assert(pet.samples(MOCK.now, 15, config, 18).name == 'Sample avatar', 'A main job with a pet of its own comes first.');
game.job, game.sub = 1, 18;
fx.step();
assert(fx.draw():find('|Strobe|', 1, true), 'The display samples a support job\'s pet: ' .. fx.draw());
game.job, game.sub = 18, 0;
fx.step();
config.show_attachments, config.show_target = false, false;
assert(not fx.draw():find('|Strobe|', 1, true), 'And none that aren\'t ticked.');
config.preview = false;
return 'The pet display\'s optional lines for an automaton, an avatar and a wyvern';
