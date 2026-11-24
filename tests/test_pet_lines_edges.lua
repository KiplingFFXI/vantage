-- The edges of the pet display's optional lines (core/pet_lines.lua), on the module itself: an automaton already out
-- when Vantage loads has recasts it can't know yet; a charm or a jug about to end raises its notice once; Healing
-- Breath goes by how far the wyvern is from the one it would heal; and the ticks travel with the display's settings.
local lines, pet = require('core.pet_lines'), require('core.pet');
local config = pet.make();
local function named(shown, name)
    for index = 1, shown.line_count do
        if shown.lines[index].name == name then return shown.lines[index]; end
    end
end

-- Already out at load: nothing says when each recast started, so each is unknown until its own length has passed or it
-- fires. One that comes out later starts them all.
local snapshot = { valid = true, id = 1001, job = 18, sub_job = 0, self_effects = {},
    pet = { id = 77, index = 5, name = 'Ironsides', automaton = { head = 2, frame = 0x21, attachments = { 97, 1 } } } };
config.show_attachments = true;
local watch, shown = lines.new(), {};
watch:track(100, snapshot);
watch:fill(shown, 100, config, snapshot);
assert(shown.line_count == 2 and named(shown, 'Strobe').value == 'Not known yet' and named(shown, 'Shock Absorber').value == 'Not known yet',
    'An automaton already out has recasts Vantage can\'t know yet.');
assert(named(shown, 'Strobe').details:find('loaded with the automaton out', 1, true), 'And its tooltip says why.');
watch:track(131, snapshot);
watch:fill(shown, 131, config, snapshot);
assert(named(shown, 'Strobe').value == 'Needs Fire' and named(shown, 'Shock Absorber').value == 'Not known yet',
    'Strobe\'s 30 seconds have passed, so it is known to be ready. Shock Absorber\'s 180 haven\'t.');
watch:observe({ kind = 'pet_action', entity_id = 77, category = 11, id = 1946 }, 140);
watch:fill(shown, 141, config, snapshot);
assert(named(shown, 'Shock Absorber').deadline == 320, 'Once it fires, its recast is known.');
watch:observe({ kind = 'pet_action', entity_id = 78, category = 11, id = 1945 }, 142);
watch:fill(shown, 143, config, snapshot);
assert(not named(shown, 'Strobe').deadline, 'What another pet does isn\'t taken for yours.');
watch:fill(shown, 500, config, snapshot);
assert(named(shown, 'Shock Absorber').value == 'Needs Earth', 'After its recast it waits for its maneuver.');
-- Gone and out again: a fresh one, with every recast started.
snapshot.pet = nil;
watch:track(510, snapshot);
snapshot.pet = { id = 79, index = 6, name = 'Ironsides', automaton = { head = 2, frame = 0x21, attachments = { 97, 1 } } };
watch:track(520, snapshot);
watch:fill(shown, 520, config, snapshot);
assert(named(shown, 'Strobe').deadline == 550 and named(shown, 'Shock Absorber').deadline == 700, 'One that comes out while Vantage watches starts them all.');
-- A pet that isn't an automaton has no attachment lines, and a pet with no page yet has none either.
snapshot.pet.automaton = nil;
watch:fill(shown, 521, config, snapshot);
assert(shown.line_count == 0, 'With no automaton status there is nothing to list.');
config.show_attachments = false;

-- A charm or a jug about to end: one notice as its last minute starts, and not again.
local said = {};
local function announce(key, message) said[#said + 1] = key .. ': ' .. message; end
config.alert_ending = true;
shown = { name = 'SheepFamiliar', jug = { deadline = 1000 } };
watch = lines.new();
snapshot = { valid = true, id = 1001, job = 9, sub_job = 0, self_effects = {}, pet = { id = 80, index = 7, name = 'SheepFamiliar' } };
watch:track(800, snapshot);
watch:fill(shown, 800, config, snapshot, announce);
assert(#said == 0, 'With minutes left, nothing.');
watch:fill(shown, 941, config, snapshot, announce);
assert(#said == 1 and said[1] == 'pet_ending: SheepFamiliar is about to leave', 'A jug\'s last minute raises a notice: ' .. tostring(said[1]));
watch:fill(shown, 950, config, snapshot, announce);
assert(#said == 1, 'Once.');
shown.jug, shown.charm = nil, { deadline = 2000 };
watch:fill(shown, 1000, config, snapshot, announce);
watch:fill(shown, 1945, config, snapshot, announce);
assert(#said == 2 and said[2] == 'pet_ending: Your charm is about to end', 'A charm\'s estimate does the same: ' .. tostring(said[2]));
shown.charm = { deadline = nil };
watch:fill(shown, 1950, config, snapshot, announce);
assert(#said == 2, 'A charm with no estimate has no last minute.');
-- A pet that comes out already under a line raises nothing until it has been over it.
config.alert_ending, config.alert_hp = false, true;
watch = lines.new();
watch:track(10, snapshot);
shown = { name = 'SheepFamiliar', hpp = 10 };
said = {};
watch:fill(shown, 10, config, snapshot, announce);
assert(#said == 0, 'A pet first seen under the line isn\'t news.');
shown.hpp = 60;
watch:fill(shown, 11, config, snapshot, announce);
shown.hpp = 25;
watch:fill(shown, 12, config, snapshot, announce);
assert(#said == 1 and said[1] == 'pet_hp: SheepFamiliar is at 25% HP', 'At the line itself it fires: ' .. tostring(said[1]));
shown.hpp = 60;
watch:fill(shown, 13, config, snapshot, announce);
shown.hpp = 0;
watch:fill(shown, 14, config, snapshot, announce);
assert(#said == 1, 'A dead pet isn\'t low on HP.');
-- Each notice goes by its own tick: with one on, crossing the other two lines raises nothing.
local function crossing(key)
    config.alert_hp, config.alert_tp, config.alert_ending = key == 'alert_hp', key == 'alert_tp', key == 'alert_ending';
    watch = lines.new();
    watch:track(10, snapshot);
    said = {};
    shown = { name = 'SheepFamiliar', hpp = 60, tp = 0, jug = { deadline = 1000 } };
    watch:fill(shown, 10, config, snapshot, announce);
    shown.hpp, shown.tp = 20, 1200;
    watch:fill(shown, 950, config, snapshot, announce);
    return table.concat(said, ', ');
end
assert(crossing('alert_hp') == 'pet_hp: SheepFamiliar is at 20% HP', 'Only the HP notice: ' .. table.concat(said, ', '));
assert(crossing('alert_tp') == 'pet_tp: SheepFamiliar has 1200 TP', 'Only the TP notice: ' .. table.concat(said, ', '));
assert(crossing('alert_ending') == 'pet_ending: SheepFamiliar is about to leave', 'Only the ending notice: ' .. table.concat(said, ', '));
-- A jug whose time has already passed isn't about to leave.
watch = lines.new();
watch:track(10, snapshot);
said = {};
shown = { name = 'SheepFamiliar', jug = { deadline = 1000 } };
watch:fill(shown, 10, config, snapshot, announce);
watch:fill(shown, 1010, config, snapshot, announce);
assert(#said == 0, 'Past its time, there is nothing left to warn of.');
config.alert_hp, config.alert_tp, config.alert_ending = false, false, false;

-- Healing Breath on a party member needs the wyvern within 14 yalms of them. The wyvern is at 0x709, a place the server
-- gives the pets it makes.
local hp, active, spot = { [0] = 100, [1] = 20, [2] = 20 }, { [1] = 1, [2] = 0 }, { [0x709] = { 0, 0, 0 }, [0x401] = { 15, 0, 0 }, [0x402] = { 1, 0, 0 } };
-- The game gives a distance as its square.
local squared, nameless = 25, false;
AshitaCore.GetMemoryManager = function()
    return {
        GetParty = function()
            return { GetMemberHPPercent = function(_, slot) return hp[slot] or 0; end, GetMemberIsActive = function(_, slot) return active[slot] or 0; end,
                GetMemberTargetIndex = function(_, slot) return 0x400 + slot; end,
                GetMemberName = function(_, slot) return not nameless and 'Member' .. slot or ''; end };
        end,
        GetEntity = function()
            return { GetDistance = function() return squared; end,
                GetLocalPositionX = function(_, index) return spot[index] and spot[index][1]; end,
                GetLocalPositionY = function(_, index) return spot[index] and spot[index][2]; end,
                GetLocalPositionZ = function(_, index) return spot[index] and spot[index][3]; end };
        end,
    };
end;
config.show_breath = true;
snapshot = { valid = true, id = 1001, job = 14, sub_job = 3, self_effects = {}, pet = { id = 0x1000809, index = 0x709, name = 'Wyvern' } };
watch = lines.new();
watch:track(10, snapshot);
shown = {};
watch:fill(shown, 10, config, snapshot);
assert(named(shown, 'Breath').value == 'At 33% HP', 'A member 15 yalms from the wyvern is too far, and one who isn\'t in the party doesn\'t count: '
    .. named(shown, 'Breath').value);
spot[0x401] = { 14, 0, 0 };
watch:fill(shown, 11, config, snapshot);
assert(named(shown, 'Breath').value == 'Ready for Member1', 'At 14 yalms it reaches.');
nameless = true;
watch:fill(shown, 11.5, config, snapshot);
assert(named(shown, 'Breath').value == 'Ready for a member', 'A member the game has no name for yet is still told: ' .. named(shown, 'Breath').value);
nameless = false;
hp[1] = 0;
watch:fill(shown, 12, config, snapshot);
assert(named(shown, 'Breath').value == 'At 33% HP', 'A member at 0 HP is past healing.');
hp[0] = 0;
watch:fill(shown, 12.2, config, snapshot);
assert(named(shown, 'Breath').value == 'At 33% HP', 'So are you at 0 HP.');
hp[0] = 33;
watch:fill(shown, 12.4, config, snapshot);
assert(named(shown, 'Breath').value == 'Ready for you', 'At a third of your HP it is ready for you.');
-- A wyvern the game no longer shows is out of reach, whatever distance the game still answers with.
snapshot.pet.away = true;
watch:fill(shown, 12.6, config, snapshot);
assert(named(shown, 'Breath').value == 'Too far' and named(shown, 'Breath').warn == true, 'Out of view, the wyvern can\'t reach you: '
    .. named(shown, 'Breath').value);
snapshot.pet.away = nil;
-- A member whose place the game only half answers for counts as near, and nothing fails.
hp[0], hp[1] = 100, 20;
spot[0x401] = { 30, nil, 0 };
watch:fill(shown, 12.8, config, snapshot);
assert(named(shown, 'Breath').value == 'Ready for Member1', 'A member with half a position still counts: ' .. named(shown, 'Breath').value);
spot[0x401] = { 14, 0, 0 };
hp[1] = 0;
hp[0] = 100;
snapshot.job = 13;
watch:fill(shown, 13, config, snapshot);
assert(shown.line_count == 0, 'Only a DRG main has the line.');
-- Only the wyvern uses Healing Breath (scripts/globals/pets/wyvern.lua :164-189), so another pet a DRG has out has no
-- Breath line: a /SMN's avatar, a /BST's jug pet or charmed mob, or a /PUP's automaton. A charmed mob keeps its own
-- place, under the 0x700 every pet the server makes is put at or past.
local function breath_for(sub, pet)
    local probe, seen = lines.new(), {};
    local state = { valid = true, id = 1001, job = 14, sub_job = sub, self_effects = {}, pet = pet };
    probe:track(14, state);
    probe:fill(seen, 14, config, state);
    return named(seen, 'Breath');
end
hp[0] = 33;
for _, other in ipairs({ { 15, { id = 0x1000809, index = 0x709, name = 'Carbuncle' } }, { 9, { id = 0x1000809, index = 0x709, name = 'SheepFamiliar' } },
    { 9, { id = 0x1000123, index = 0x123, name = 'Land Crab' } },
    { 18, { id = 0x1000809, index = 0x709, name = 'Ironsides', automaton = { head = 2, frame = 0x21, attachments = {} } } } }) do
    local found = breath_for(other[1], other[2]);
    assert(not found, other[2].name .. ' isn\'t a wyvern, so it has no Breath line: ' .. tostring(found and found.value));
end
hp[0] = 100;
config.show_breath = false;

-- The distance is in the warning color only past the reach of your job's command, and a pet the client can't show
-- says so.
config.show_distance = true;
snapshot = { valid = true, id = 1001, job = 9, sub_job = 0, self_effects = {}, pet = { id = 82, index = 9, name = 'SheepFamiliar', since = 20 } };
watch = lines.new();
watch:track(20, snapshot);
squared = 625;
watch:fill(shown, 20, config, snapshot);
assert(named(shown, 'Distance').value == '25.0' and named(shown, 'Distance').warn == false, 'At 25 yalms a BST\'s Fight still reaches.');
squared = 26 * 26;
watch:fill(shown, 21, config, snapshot);
assert(named(shown, 'Distance').value == '26.0' and named(shown, 'Distance').warn == true, 'Past it the line is in the warning color.');
snapshot.job = 5;
watch:fill(shown, 22, config, snapshot);
assert(named(shown, 'Distance').warn == false, 'A job with no such command has no reach to pass.');
snapshot.pet.away = true;
watch:fill(shown, 23, config, snapshot);
assert(named(shown, 'Distance').value == 'Out of view' and named(shown, 'Distance').warn == true, 'A pet the client can\'t show says so.');
snapshot.pet.away, snapshot.job = nil, 9;
-- Repair is for the automaton alone and Healing Breath comes from the wyvern alone (scripts/globals/job_utils/puppetmaster.lua
-- :209-210), so a PUP's or a DRG's other pet has no reach to pass, whatever the support job. Fight commands only a jug
-- pet or a charmed mob (sql/abilities.sql :89, src/map/utils/charutils.cpp :6393-6400), so a BST's avatar or automaton
-- has none either.
squared = 22 * 22;
local function reach(job, sub, pet)
    local probe, seen = lines.new(), {};
    local state = { valid = true, id = 1001, job = job, sub_job = sub, self_effects = {}, pet = pet };
    probe:track(30, state);
    probe:fill(seen, 30, config, state);
    return named(seen, 'Distance');
end
local crab, avatar, jug = { id = 0x1000123, index = 0x123, name = 'Land Crab' }, { id = 0x1000809, index = 0x709, name = 'Carbuncle' },
    { id = 0x1000809, index = 0x709, name = 'SheepFamiliar' };
local auto = { id = 0x1000809, index = 0x709, name = 'Ironsides', automaton = { head = 2, frame = 0x21, attachments = {} } };
for _, case in ipairs({ { 18, 9, crab }, { 18, 9, jug }, { 18, 15, avatar }, { 14, 15, avatar }, { 14, 9, crab }, { 14, 9, jug }, { 9, 15, avatar },
    { 9, 18, auto } }) do
    local found = reach(case[1], case[2], case[3]);
    assert(found.warn == false and not found.details:find('needs it', 1, true), case[3].name .. ' as job ' .. case[1] .. ' with support ' .. case[2]
        .. ' has no reach to pass: ' .. found.details);
end
local own = reach(18, 9, { id = 0x1000809, index = 0x709, name = 'Ironsides', automaton = { head = 2, frame = 0x21, attachments = {} } });
assert(own.warn == true and own.details:find('Repair needs it within about 20', 1, true), 'The automaton past 20 is too far for Repair: ' .. own.details);
own = reach(14, 3, { id = 0x1000809, index = 0x709, name = 'Wyvern' });
assert(own.warn == true and own.details:find('Healing Breath needs it within about 14', 1, true), 'The wyvern past 14 is too far for Healing Breath: ' .. own.details);
config.show_distance = false;

-- How long it has been out: minutes and seconds, then hours and minutes.
config.show_time_out = true;
watch:fill(shown, 20 + 59 * 60 + 59, config, snapshot);
assert(named(shown, 'Out for').value == '59:59', 'Under an hour: ' .. named(shown, 'Out for').value);
watch:fill(shown, 20 + 65 * 60, config, snapshot);
assert(named(shown, 'Out for').value == '1h 05m', 'From an hour: ' .. named(shown, 'Out for').value);
config.show_time_out = false;

-- What it is doing: a start with no word of its end gives way after 30 seconds, and a move that did no damage has no
-- number.
config.show_action = true;
watch:observe({ kind = 'pet_start', entity_id = 82, category = 7, id = 300 }, 100);
watch:fill(shown, 129, config, snapshot);
assert(shown.line_count == 1 and named(shown, 'Readies').value == 'a move', 'A readied move the client has no name for is still shown.');
watch:fill(shown, 131, config, snapshot);
assert(shown.line_count == 0, 'With no word of its end it gives way after 30 seconds.');
watch:observe({ kind = 'pet_action', entity_id = 82, category = 11, id = 300, amount = 0 }, 140);
watch:fill(shown, 141, config, snapshot);
assert(named(shown, 'Last move').value == 'A move', 'A move that did no damage has no number: ' .. named(shown, 'Last move').value);
watch:observe({ kind = 'pet_action', entity_id = 82, category = 11, id = 300, amount = 57 }, 150);
watch:fill(shown, 151, config, snapshot);
assert(named(shown, 'Last move').value == 'A move 57', 'One that did has it: ' .. named(shown, 'Last move').value);
config.show_action = false;

-- Reward is for a BST, main or support, and not for an automaton.
config.show_reward = true;
watch:fill(shown, 152, config, snapshot);
assert(named(shown, 'Reward').value == 'No pet food', 'A BST with nothing in the ammo slot is told so.');
snapshot.job, snapshot.sub_job = 5, 9;
watch:fill(shown, 153, config, snapshot);
assert(named(shown, 'Reward'), 'A /BST has the line too.');
snapshot.sub_job = 0;
watch:fill(shown, 154, config, snapshot);
assert(shown.line_count == 0, 'Another job has no Reward line.');
snapshot.job, snapshot.sub_job, snapshot.pet.automaton = 18, 9, { head = 2, frame = 0x21, attachments = {} };
watch:fill(shown, 155, config, snapshot);
assert(shown.line_count == 0, 'An automaton has none, as Reward is for a beast.');
config.show_reward = false;

-- What an avatar costs: the step your MP most often went down by in the last 45 seconds, for a SMN, main or support.
config.show_upkeep = true;
local function costs(job, sub)
    snapshot = { valid = true, id = 1001, job = job, sub_job = sub, self_effects = {}, mp = 500, pet = { id = 84, index = 9, name = 'Ifrit' } };
    watch = lines.new();
    watch:track(0, snapshot);
    return function(now, mp)
        snapshot.mp = mp;
        watch:fill(shown, now, config, snapshot);
        return named(shown, 'MP cost');
    end
end
local cost = costs(15, 0);
assert(cost(0, 500).value == 'Measuring', 'Before any step, it is measuring.');
assert(cost(3, 493).value == 'Measuring', 'One step down isn\'t enough to go by.');
assert(cost(6, 486).value == '7 a tick, 3:28 left' and cost(6, 486).warn == false, 'Two alike are: ' .. cost(6, 486).value);
-- A spell or a pact, at 30 MP or more, isn't the avatar's cost, and neither is MP coming back.
cost = costs(15, 0);
cost(0, 500); cost(3, 460);
assert(cost(6, 420).value == 'Measuring', 'Two casts of 40 MP aren\'t a cost a tick: ' .. cost(6, 420).value);
cost = costs(15, 0);
cost(0, 400); cost(3, 410);
assert(cost(6, 420).value == 'Measuring', 'MP coming back isn\'t one either: ' .. cost(6, 420).value);
-- Steps from more than 45 seconds ago don't count, so a cost that changed is read from the new steps.
cost = costs(15, 0);
cost(0, 500); cost(3, 493); cost(6, 486); cost(9, 479); cost(12, 472); cost(60, 467);
assert(cost(63, 462).value == '5 a tick, 4:37 left', 'Four old steps of 7 give way to two new ones of 5: ' .. cost(63, 462).value);
-- With under a minute of MP left, it wants attention.
cost = costs(5, 15);
cost(0, 114); cost(3, 107);
assert(cost(6, 100).value == '7 a tick, 0:42 left' and cost(6, 100).warn == true, 'A /SMN has the line, in the warning color for the last minute.');
cost = costs(5, 0);
cost(0, 500); cost(3, 493);
assert(cost(6, 486) == nil, 'Another job has no MP cost line.');
config.show_upkeep = false;

-- The automaton's cooldowns at their edges: two Damage Gauges take their 3 seconds off once, and maneuvers past three
-- count as three.
config.show_cooldowns = true;
local function automaton(build, effects)
    snapshot = { valid = true, id = 1001, job = 18, sub_job = 0, self_effects = {} };
    watch = lines.new();
    watch:track(1, snapshot);
    snapshot.pet = { id = 85, index = 9, name = 'Ironsides', automaton = build };
    for _, effect in ipairs(effects or {}) do snapshot.self_effects[#snapshot.self_effects + 1] = { effect = effect }; end
    watch:track(2, snapshot);
end
automaton({ head = 4, frame = 0x23, attachments = { 195, 207 } });
watch:observe({ kind = 'pet_start', entity_id = 85, category = 8, id = 1 }, 200);
watch:fill(shown, 201, config, snapshot);
assert(named(shown, 'Healing').deadline == 212 and named(shown, 'Healing').total == 12, 'A Stormwaker head\'s 15 seconds between cures, less 3 once.');
automaton({ head = 2, frame = 0x21, attachments = { 107 } }, { 303, 303, 303, 303 });
watch:observe({ kind = 'pet_action', entity_id = 85, category = 11, id = 1944 }, 300);
watch:fill(shown, 301, config, snapshot);
assert(named(shown, 'Shield Bash').deadline == 465 and named(shown, 'Shield Bash').total == 165, 'Four Earth maneuvers count as three: 180 less 15.');
config.show_cooldowns = false;
-- An Economizer starts with 60 seconds, so its first fill is of 60, and then of its 180.
config.show_attachments = true;
automaton({ head = 4, frame = 0x23, attachments = { 230 } });
watch:fill(shown, 2, config, snapshot);
assert(named(shown, 'Economizer').deadline == 62 and named(shown, 'Economizer').total == 60, 'At spawn its fill is of the 60 seconds it starts with.');
watch:observe({ kind = 'pet_action', entity_id = 85, category = 11, id = 2068 }, 100);
watch:fill(shown, 101, config, snapshot);
assert(named(shown, 'Economizer').deadline == 280 and named(shown, 'Economizer').total == 180, 'After a use it is of the full 180.');
config.show_attachments = false;

-- Sample displays show a line only for a tick that is on, and the MP number only on the automaton's sample.
local sample = {};
lines.samples(sample, 100, pet.make(), 18);
assert(sample.line_count == 0, 'With no tick on, the samples have no lines.');
local every = pet.make();
for _, key in ipairs(pet.extras) do every[key] = true; end
assert(pet.samples(100, 18, every).mp == 168 and pet.samples(100, 18, every).max_mp == 420, 'The automaton\'s sample has an MP number.');
assert(pet.samples(100, 9, every).mp == nil and pet.samples(100, 15, every).mp == nil, 'No other sample has one.');

-- The ticks are the display's own settings: /vg set reaches them, and an export of the display carries them.
local custom, share, defaults = require('core.customization'), require('core.share'), require('ui.defaults');
local settings = defaults.make();
local set = assert(custom.set(settings, 'pet.show_attachments', 'true'));
assert(set.pet.show_attachments == true and settings.pet.show_attachments == false, '/vg set turns one on.');
set = assert(custom.set(set, 'pet.alert_hp_percent', '40'));
local read = assert(share.read(assert(share.export(set, 'element', 'pet'))));
assert(read.data.show_attachments == true and read.data.alert_hp_percent == 40 and read.data.show_build == false, 'An export of the Pet display holds them.');
assert(lines.wanted(set.pet) == true and lines.wanted(settings.pet) == false, 'With none on, nothing is worked out.');
return 'The pet display\'s optional lines at their edges';
