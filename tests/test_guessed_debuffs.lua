-- Debuffs the game never reports. When a player's weapon skill, a pet's move or a few abilities, spells, pacts and
-- items put a status on a monster, the server sends only the action's own result, with no word of the status. So the
-- status is taken as put on when the result fits what the data says of the action: it did damage (infer 'damage') or
-- its result has one of the action's messages (infer 'success'). A resist looks the same, so these are guesses. A
-- guess never renews or replaces what the monster already shows.
local observer, tracker, client = require('core.observer'), require('core.tracker'), require('core.client');
local ME, BOB, ALLY, STRANGER = 1001, 1002, 1010, 1500;
local MOB, CRAB = 0x1000301, 0x1000302;
-- A jug pet and an automaton sit in the game's list from 0x700, so their ids end 0x100 above their place. A charmed
-- monster keeps the id it had.
local MY_JUG, BOBS_PUPPET, CHARMED, WILD = 0x1000801, 0x1000802, 0x1000303, 0x1000803;
local snapshot = { valid = true, id = ME, zone = 102, name = 'Tester', level = 75, job = 1, self_known = true, self_effects = {},
    party = { { id = BOB, name = 'Bob', scope = 'party', zone = 102, slot = 1 }, { id = ALLY, name = 'Ally', scope = 'alliance', zone = 102, slot = 6 } },
    pet = { id = MY_JUG, index = 0x701, name = 'CourierCarrie', kind = 'pet' },
    entities = { [ME] = { id = ME, name = 'Tester', kind = 'player' }, [BOB] = { id = BOB, name = 'Bob', kind = 'player' },
        [ALLY] = { id = ALLY, name = 'Ally', kind = 'player' }, [STRANGER] = { id = STRANGER, name = 'Stranger', kind = 'player' },
        [MOB] = { id = MOB, name = 'Goblin', kind = 'monster' }, [CRAB] = { id = CRAB, name = 'Crab', kind = 'monster' },
        [MY_JUG] = { id = MY_JUG, name = 'CourierCarrie', kind = 'pet' }, [BOBS_PUPPET] = { id = BOBS_PUPPET, name = 'Ironsides', kind = 'pet' },
        [CHARMED] = { id = CHARMED, name = 'Hare', kind = 'monster' }, [WILD] = { id = WILD, name = 'Wild', kind = 'monster' } } };
-- Whose pet a unit is, as the client's entity list says.
local owners = { [MY_JUG] = ME, [BOBS_PUPPET] = BOB, [CHARMED] = ALLY };
client.pet_owner = function(id) return owners[id]; end;

-- One action: its actor, category and id, and each target as { id, message, param, reaction = { kind, message, param } }.
local function action(actor, category, id, targets)
    local rows = {};
    for i, target in ipairs(targets) do
        local reaction = target.reaction or {};
        rows[i] = { id = target[1], rows = { { message = target[2], param = target[3], reaction = reaction[2], reaction_param = reaction[3],
            reaction_kind = reaction[1] } } };
    end
    return MOCK.packet(0x028, MOCK.action_bytes(actor, category, id, rows));
end
-- The effects an action put on, as 'effect@target' in order, with each apply by that name.
local function applies(e, at)
    local out, by = {}, {};
    for _, seen in ipairs(observer.read(e, at or 1, snapshot)) do
        if seen.kind == 'apply' then
            local name = seen.effect .. '@' .. seen.entity_id;
            out[#out + 1], by[name] = name, seen;
        end
    end
    table.sort(out);
    return table.concat(out, ' '), by;
end
local EVASION_DOWN, DEFENSE_DOWN, ATTACK_DOWN, ACCURACY_DOWN, STUN, POISON, BIND, SLOW, PARALYSIS = 148, 149, 147, 146, 10, 3, 11, 13, 4;
local on_mob = '@' .. MOB;

-- Shield Break, weapon skill 80, for 300 damage: Evasion Down on the monster, from whoever used it.
local said, by = applies(action(ME, 3, 80, { { MOB, 185, 300 } }));
assert(said == EVASION_DOWN .. on_mob, 'Your Shield Break that hits puts Evasion Down on the monster: ' .. said);
local seen = by[EVASION_DOWN .. on_mob];
assert(seen.source == ME and seen.guessed == true and seen.action_kind == 'weaponskills' and seen.spell == 80, 'It is yours, and a guess.');
assert(seen.duration == 180, 'It counts down its three minutes: ' .. tostring(seen.duration));
assert(seen.category == 'debuff', 'It is a debuff.');
for _, who in ipairs({ BOB, ALLY, STRANGER }) do
    said, by = applies(action(who, 3, 80, { { MOB, 185, 300 } }));
    assert(said == EVASION_DOWN .. on_mob and by[said].source == who, 'Anyone\'s Shield Break does the same, as theirs: ' .. said);
end
-- A miss, no damage and a blink put nothing on.
assert(applies(action(ME, 3, 80, { { MOB, 188, 0 } })) == '', 'A miss puts nothing on.');
assert(applies(action(ME, 3, 80, { { MOB, 185, 0 } })) == '', 'A hit for nothing puts nothing on.');
assert(applies(action(ME, 3, 80, { { MOB, 31, 1 } })) == '', 'A shadow taken puts nothing on.');
-- Only monsters: nothing is guessed on a player.
assert(applies(action(MOB, 3, 80, { { ME, 185, 300 } })) == '', 'A monster\'s use on you is not a player\'s weapon skill.');
assert(applies(action(STRANGER, 3, 80, { { BOB, 185, 300 } })) == '', 'Nothing is guessed on a player.');
said = applies(action(STRANGER, 3, 80, { { MOB, 185, 300 }, { BOB, 185, 300 } }));
assert(said == EVASION_DOWN .. on_mob, 'Nor on a player hit beside a monster: ' .. said);
-- Each monster it hits takes it, and each of Full Break's four.
said = applies(action(ME, 3, 80, { { MOB, 185, 300 }, { CRAB, 264, 120 } }));
assert(said == EVASION_DOWN .. '@' .. MOB .. ' ' .. EVASION_DOWN .. '@' .. CRAB, 'Every monster hit takes it: ' .. said);
-- A drain is damage too, in each form its result takes: 187 on the first monster and 281 on the others, and a
-- spell's 227, which a magic burst turns into 274.
said = applies(action(ME, 3, 80, { { MOB, 187, 300 }, { CRAB, 281, 120 } }));
assert(said == EVASION_DOWN .. '@' .. MOB .. ' ' .. EVASION_DOWN .. '@' .. CRAB, 'A drain counts as damage on every monster it reaches: ' .. said);
assert(applies(action(ME, 3, 80, { { MOB, 187, 300 }, { CRAB, 281, 0 } })) == EVASION_DOWN .. on_mob, 'One that drained nothing puts nothing on.');
for _, message in ipairs({ 2, 227, 252, 274 }) do
    said = applies(action(ME, 4, 623, { { MOB, message, 80 } }));
    assert(said == STUN .. on_mob, 'A spell whose result ' .. message .. ' says it did damage puts its status on: ' .. said);
end
assert(applies(action(ME, 4, 623, { { MOB, 274, 0 } })) == '', 'A burst that drained nothing puts nothing on.');
assert(applies(action(ME, 4, 623, { { MOB, 85, 0 } })) == '', 'A resisted spell puts nothing on.');
-- That spell is Head Butt, whose stun is 2 to 7 seconds on Phoenix: a time from 2 up to 8 with the part of a second
-- dropped.
said, by = applies(action(ME, 4, 623, { { MOB, 2, 80 } }));
assert(said == STUN .. on_mob and by[said].duration == 7 and by[said].duration_min == 2,
    'Head Butt stuns for 2 to 7 seconds: ' .. tostring(by[said] and by[said].duration_min) .. ' to ' .. tostring(by[said] and by[said].duration));
said = applies(action(ME, 3, 87, { { MOB, 185, 500 } }));
assert(said == table.concat({ ACCURACY_DOWN .. on_mob, ATTACK_DOWN .. on_mob, EVASION_DOWN .. on_mob, DEFENSE_DOWN .. on_mob }, ' '),
    'Full Break puts on all four: ' .. said);
-- A stun is one too, with its few seconds, and a weapon skill with no known time has none.
said, by = applies(action(ME, 3, 2, { { MOB, 185, 90 } }));
assert(said == STUN .. on_mob and by[said].duration == 4, 'Shoulder Tackle stuns for 4 seconds: ' .. said);
said, by = applies(action(ME, 3, 16, { { MOB, 185, 90 } }));
assert(said == POISON .. on_mob and by[said].duration == nil, 'Wasp Sting poisons, with no time to count: ' .. said);
-- A weapon skill with no status puts nothing on, and so does a job ability that finishes like one.
assert(applies(action(ME, 3, 1, { { MOB, 185, 90 } })) == '', 'A weapon skill with no status puts nothing on.');

-- Weapon Bash, ability 77, finishes as a weapon skill does, and its message 110 is the hit that stuns. Its id is a
-- weapon skill's too, which has no status.
said, by = applies(action(ME, 3, 77, { { MOB, 110, 12 } }));
assert(said == STUN .. on_mob and by[said].guessed and by[said].action_kind == 'abilities', 'Weapon Bash stuns: ' .. said);
assert(by[said].duration == 8 and by[said].duration_min == 2, 'For 2 to 8 seconds: ' .. tostring(by[said].duration_min) .. ' to ' .. tostring(by[said].duration));
assert(applies(action(ME, 3, 77, { { MOB, 158, 0 } })) == '', 'A Weapon Bash that misses doesn\'t.');
-- Shield Bash, ability 46, the same way. Its stun is 4.2 to 6.2 seconds on Phoenix, so it counts down 4 to 6, in whole
-- seconds.
said, by = applies(action(ME, 3, 46, { { MOB, 110, 12 } }));
assert(said == STUN .. on_mob and by[said].guessed and by[said].duration == 6 and by[said].duration_min == 4,
    'Shield Bash stuns for 4 to 6 seconds: ' .. tostring(by[said] and by[said].duration_min) .. ' to ' .. tostring(by[said] and by[said].duration));
assert(applies(action(ME, 3, 77, { { MOB, 185, 90 } })) == '', 'The weapon skill with that id puts nothing on.');
-- An action aimed at no monster asks nothing about who owns its user.
local lookups = 0;
local owner_of = client.pet_owner;
client.pet_owner = function(...) lookups = lookups + 1; return owner_of(...); end;
applies(action(CRAB, 11, 2, { { ME, 185, 40 }, { BOB, 185, 40 } }));
assert(lookups == 0, 'A monster\'s move on players looks up no owner: ' .. lookups);
applies(action(CRAB, 11, 2, { { ME, 185, 40 }, { MOB, 185, 40 } }));
assert(lookups == 1, 'One that reaches a monster does, once: ' .. lookups);
client.pet_owner = owner_of;
-- Angon's own message names its Defense Down, so it is put on once, as reported.
said, by = applies(action(ME, 6, 170, { { MOB, 127, DEFENSE_DOWN } }));
assert(said == DEFENSE_DOWN .. on_mob and not by[said].guessed, 'An effect the result names is not guessed again: ' .. said);
-- Chi Blast, ability 82, inhibits TP only with Penance merits, which only your own can be checked for.
local ranks;
client.merit = function(id) return id == 0x0846 and ranks or nil; end;
snapshot.job, ranks = 2, 0;
assert(applies(action(ME, 6, 82, { { MOB, 110, 200 } })) == '', 'Your Chi Blast with no Penance merits puts nothing on.');
assert(applies(action(BOB, 6, 82, { { MOB, 158, 0 } })) == '', 'A Chi Blast whose result is not its own message puts nothing on.');
ranks = 3;
said = applies(action(ME, 6, 82, { { MOB, 110, 200 } }));
assert(said == '168' .. on_mob, 'With Penance merits it inhibits TP: ' .. said);
-- Its time is 20 seconds a rank, which your own ranks give.
local sampled = client.sample_modifiers;
for rank, seconds in pairs({ [1] = 20, [2] = 40, [3] = 60 }) do
    client.sample_modifiers = function() return { items = {}, buffs = {}, merits = { [2118] = rank }, level = 75, job = 2, complete = true }; end;
    said, by = applies(action(ME, 6, 82, { { MOB, 110, 200 } }));
    assert(by[said].duration == seconds and by[said].duration_min == seconds, 'Rank ' .. rank .. ' of Penance is ' .. seconds .. ' seconds: ' .. tostring(by[said].duration));
end
client.sample_modifiers = sampled;
ranks = nil;
assert(applies(action(ME, 6, 82, { { MOB, 110, 200 } })) == '168' .. on_mob, 'With your merits not yet read, it counts.');
-- Merits do nothing under level 75, so a Monk under it puts nothing on whatever ranks they hold.
ranks, snapshot.level = 3, 74;
assert(applies(action(ME, 6, 82, { { MOB, 110, 200 } })) == '', 'Under level 75 your Penance merits do nothing.');
assert(applies(action(BOB, 6, 82, { { MOB, 110, 200 } })) == '168' .. on_mob, 'Someone else\'s level isn\'t yours.');
-- With your job or level not read, nothing says the merit is out of reach, so it counts.
snapshot.level = nil;
assert(applies(action(ME, 6, 82, { { MOB, 110, 200 } })) == '168' .. on_mob, 'With your level not read, it counts.');
snapshot.level, snapshot.job = 75, nil;
assert(applies(action(ME, 6, 82, { { MOB, 110, 200 } })) == '168' .. on_mob, 'With your job not read, it counts.');
snapshot.job, ranks = 0, 0;
assert(applies(action(ME, 6, 82, { { MOB, 110, 200 } })) == '168' .. on_mob, 'With no job read, your ranks aren\'t asked.');
ranks = nil;
snapshot.job = 1;
assert(applies(action(ME, 6, 82, { { MOB, 110, 200 } })) == '', 'On a job that can\'t have the merit, it doesn\'t.');
assert(applies(action(BOB, 6, 82, { { MOB, 110, 200 } })) == '168' .. on_mob, 'Someone else\'s merits can\'t be read, so theirs counts.');
-- Tomahawk, ability 150, puts on an effect the game has no name or picture for, 805. It finishes as a weapon skill
-- does, and its result says only that it was used (message 100), which no weapon skill's does. Its id is Tachi:
-- Yukikaze's too. It lasts 15 seconds and 15 more a merit rank, which your own ranks give.
said, by = applies(action(ME, 3, 150, { { MOB, 185, 300 } }));
assert(said == '5' .. on_mob and by[said].action_kind == 'weaponskills', 'Tachi: Yukikaze, with that id, still blinds: ' .. said);
said, by = applies(action(BOB, 3, 150, { { MOB, 100, 0 } }));
assert(by[said] and by[said].action_kind == 'abilities', 'Tomahawk is read as the ability it is.');
assert(said == '805' .. on_mob and by[said].guessed and by[said].source == BOB and by[said].category == 'debuff', 'Tomahawk puts its effect on, as a debuff: ' .. said);
assert(by[said].duration == 60 and by[said].duration_min == 30, 'Someone else\'s lasts 30 to 60 seconds, by ranks nobody can read: '
    .. tostring(by[said].duration_min) .. ' to ' .. tostring(by[said].duration));
for rank, seconds in pairs({ [1] = 30, [2] = 45, [3] = 60 }) do
    client.sample_modifiers = function() return { items = {}, buffs = {}, merits = { [2050] = rank }, level = 75, job = 1, complete = true }; end;
    said, by = applies(action(ME, 3, 150, { { MOB, 100, 0 } }));
    assert(said == '805' .. on_mob and by[said].duration == seconds and by[said].duration_min == seconds,
        'Rank ' .. rank .. ' of Tomahawk is ' .. seconds .. ' seconds: ' .. tostring(by[said] and by[said].duration));
end
client.sample_modifiers = sampled;
assert(applies(action(BOB, 3, 150, { { MOB, 158, 0 } })) == '', 'A Tomahawk whose result is not its own message puts nothing on.');
assert(applies(action(MOB, 3, 150, { { ME, 100, 0 } })) == '', 'Nor one on a player.');
-- Feral Howl, ability 161, says only that it was used (message 100) with Terror (28) as its param, whether or not the
-- Terror took (modules/era/lua/globals/job_utils/beastmaster.lua :28-55), so its Terror is a guess. It lasts 10
-- seconds times the resist rate, which is 10, 5 or 2.5, counted in whole seconds.
said, by = applies(action(BOB, 6, 161, { { MOB, 100, 28 } }));
assert(said == '28' .. on_mob and by[said].guessed and by[said].source == BOB and by[said].action_kind == 'abilities',
    'Feral Howl terrorizes: ' .. said);
assert(by[said].duration == 10 and by[said].duration_min == 2, 'For 2 to 10 seconds: ' .. tostring(by[said].duration_min)
    .. ' to ' .. tostring(by[said].duration));
said = applies(action(ME, 6, 161, { { MOB, 100, 28 } }));
assert(said == '28' .. on_mob, 'Your own Feral Howl does too: ' .. said);
-- A Bottle of Hysteroanima, item 5262, puts on the other such effect, 804, for 25 to 32 seconds. A Bottle of
-- Psychoanima, 5261, puts on Intimidate for as long.
said, by = applies(action(BOB, 5, 5262, { { MOB, 0, 0 } }));
assert(said == '804' .. on_mob and by[said].guessed and by[said].category == 'debuff' and by[said].duration == 32 and by[said].duration_min == 25,
    'Hysteroanima puts its effect on for 25 to 32 seconds: ' .. said .. ', ' .. tostring(by[said] and by[said].duration_min));
said, by = applies(action(BOB, 5, 5261, { { MOB, 0, 0 } }));
assert(said == '22' .. on_mob and by[said].guessed and by[said].duration == 32 and by[said].duration_min == 25,
    'Psychoanima intimidates for 25 to 32 seconds: ' .. said .. ', ' .. tostring(by[said] and by[said].duration_min));
-- Jump finishes as a weapon skill does, with an ability's damage message, and its id is Gale Axe's too. It puts
-- Defense Down on only under Spirit Surge, effect 126.
assert(applies(action(ME, 3, 66, { { MOB, 317, 90 } })) == '', 'Your Jump with no Spirit Surge puts nothing on.');
snapshot.self_effects = { { effect = 126, slot = 0 } };
said, by = applies(action(ME, 3, 66, { { MOB, 317, 90 } }));
assert(said == DEFENSE_DOWN .. on_mob and by[said].action_kind == 'abilities', 'With Spirit Surge it puts Defense Down on: ' .. said);
snapshot.self_effects = {};
said, by = applies(action(ME, 3, 66, { { MOB, 185, 90 } }));
assert(said == '130' .. on_mob and by[said].action_kind == 'weaponskills', 'The weapon skill with that id is Gale Axe, which chokes: ' .. said);
-- With your own effects not read yet, what a guess needs of them is taken as there.
snapshot.self_known = false;
assert(applies(action(ME, 3, 66, { { MOB, 317, 90 } })) == DEFENSE_DOWN .. on_mob, 'With no listing of your effects yet, your Jump counts.');
snapshot.self_known = true;
-- A party member's Jump goes by their own listing, as core/client.lua gives it once it has read one (valid): Defense
-- Down only under their Spirit Surge, whatever yours shows.
local bob = snapshot.party[1];
bob.valid, bob.effects = true, {};
assert(applies(action(BOB, 3, 66, { { MOB, 317, 90 } })) == '', 'A member\'s Jump with no Spirit Surge on their listing puts nothing on.');
snapshot.self_effects = { { effect = 126, slot = 0 } };
said = applies(action(BOB, 3, 66, { { MOB, 317, 90 } }));
snapshot.self_effects = {};
assert(said == '', 'Your own Spirit Surge does nothing for theirs: ' .. said);
bob.effects = { { effect = 126, slot = 3 } };
said, by = applies(action(BOB, 3, 66, { { MOB, 317, 90 } }));
assert(said == DEFENSE_DOWN .. on_mob and by[said].source == BOB and by[said].guessed and by[said].action_kind == 'abilities' and by[said].duration == 60,
    'Under their own Spirit Surge it puts Defense Down on, as theirs, for 60 seconds: ' .. said);
-- With no listing of theirs to read, it is taken as there: a member's the client hasn't read yet, an alliance member's
-- and a stranger's.
bob.valid, bob.effects = false, {};
for _, who in ipairs({ BOB, ALLY, STRANGER }) do
    said, by = applies(action(who, 3, 66, { { MOB, 317, 90 } }));
    assert(said == DEFENSE_DOWN .. on_mob and by[said].source == who, 'With no listing of theirs to read, their Jump counts: ' .. said);
end
bob.valid, bob.effects = nil, nil;
-- A guess is no time to learn from, and a reported effect of yours still is.
local durations = require('core.durations');
local learning = { durations = { learn = true, overrides = {}, learned = {} } };
local cast = observer.read(action(ME, 4, 58, { { MOB, 236, PARALYSIS } }), 1, snapshot);
durations.prepare(cast, learning, snapshot);
assert(cast[1].kind == 'apply' and type(cast[1].learn_key) == 'string', 'Fixture: a reported cast of yours is marked for learning.');
local swing = observer.read(action(ME, 3, 80, { { MOB, 185, 300 } }), 1, snapshot);
durations.prepare(swing, learning, snapshot);
for _, made in ipairs(swing) do
    if made.kind == 'apply' then assert(made.guessed and made.learn_key == nil, 'A guessed effect is not marked for learning.'); end
end
-- Nor does a guess take a learned time. Viper Bite's Poison has the key a Poison proc of yours learns into, and the
-- proc's 30 seconds aren't the weapon skill's. With no time of its own, it stays without a countdown.
local function landed(observations, effect)
    for _, made in ipairs(observations) do
        if made.kind == 'apply' and made.effect == effect then return made; end
    end
end
learning.durations.learned = { ['effect:0:' .. POISON .. ':goblin'] = { samples = { 30, 30.2, 30.4 }, unit = 'Goblin', at = 1 },
    ['effect:0:' .. EVASION_DOWN .. ':goblin'] = { samples = { 60, 60, 60 }, unit = 'Goblin', at = 1 } };
local bite = observer.read(action(ME, 3, 17, { { MOB, 185, 300 } }), 1, snapshot);
durations.prepare(bite, learning, snapshot);
local poisoned = landed(bite, POISON);
local proc = { kind = 'apply', entity_id = MOB, entity_name = 'Goblin', scope = 'enemy', effect = POISON, source = ME,
    action_category = 1, spell = 1 };
durations.prepare({ proc }, learning, snapshot);
assert(poisoned and poisoned.guessed and durations.key(poisoned) == durations.key(proc) and proc.learn_key == durations.key(proc)
    and proc.duration == 30 and proc.timing == 'learned', 'Fixture: a Poison proc of yours learns into the same key, and takes the learned time.');
assert(poisoned.duration == nil and poisoned.timing == nil and poisoned.basis:find('Taken from', 1, true) == 1,
    'A guessed Poison takes no learned time: ' .. tostring(poisoned.duration) .. ', ' .. tostring(poisoned.timing));
-- One with a time of its own keeps it: Shield Break's three minutes, not an Evasion Down proc's minute.
swing = observer.read(action(ME, 3, 80, { { MOB, 185, 300 } }), 1, snapshot);
durations.prepare(swing, learning, snapshot);
local broken = landed(swing, EVASION_DOWN);
assert(broken and broken.duration == 180 and broken.timing == nil, 'A guess keeps its own time: ' .. tostring(broken and broken.duration));
-- An override still sets a guess's time.
learning.durations.overrides = { { enabled = true, kind = 'effect', id = POISON, name = '', mode = 'fixed', seconds = 120, offset = 0, percent = 100 } };
bite = observer.read(action(ME, 3, 17, { { MOB, 185, 300 } }), 1, snapshot);
durations.prepare(bite, learning, snapshot);
poisoned = landed(bite, POISON);
assert(poisoned and poisoned.duration == 120 and poisoned.timing == 'override', 'An override sets a guess\'s time: ' .. tostring(poisoned and poisoned.duration));
learning.durations.overrides, learning.durations.learned = {}, {};
-- Ice Break, blue magic 531, for damage: Bind.
said, by = applies(action(ME, 4, 531, { { MOB, 2, 210 } }));
assert(said == BIND .. on_mob and by[said].guessed and by[said].duration == 30, 'Ice Break binds: ' .. said);
assert(applies(action(ME, 4, 531, { { MOB, 85, 0 } })) == '', 'Resisted outright, it doesn\'t.');
-- Light of Penance, blue magic 634, puts Blindness and Bind on before Phoenix checks that you and the monster face each
-- other (blue/light_of_penance.lua :41-45). Facing, its result names one of them (236) and the other is a guess. Not
-- facing, its result says it had no effect (75, :58), though both are on.
local BLINDNESS = 5;
said, by = applies(action(ME, 4, 634, { { MOB, 75, 0 } }));
assert(said == BIND .. on_mob .. ' ' .. BLINDNESS .. on_mob and by[BIND .. on_mob].guessed and by[BLINDNESS .. on_mob].guessed,
    'Light of Penance with no effect still blinds and binds: ' .. said);
assert(by[BIND .. on_mob].duration == 30 and by[BLINDNESS .. on_mob].duration == 30, 'Each for its 30 seconds.');
said, by = applies(action(ME, 4, 634, { { MOB, 236, BLINDNESS } }));
assert(said == BIND .. on_mob .. ' ' .. BLINDNESS .. on_mob and not by[BLINDNESS .. on_mob].guessed and by[BIND .. on_mob].guessed,
    'Facing, its Blindness is reported and its Bind is a guess: ' .. said);
assert(applies(action(ME, 4, 634, { { MOB, 85, 0 } })) == '', 'Resisted, it puts nothing on.');
assert(applies(action(ME, 4, 634, { { MOB, 431, BLINDNESS } })) == '', 'Facing with neither taking, it puts nothing on.');
-- Enervation, blue magic 633, puts Defense Down and Magic Def. Down on each monster around its target, and its result
-- names one of them, so the other is a guess. The first target's result is 236 and each one after it gets 277, the
-- area form of 236 (src/map/entities/battle_entity.cpp :2511-2518, src/map/utils/messageutils.h :37).
local MAGIC_DEF_DOWN, on_crab = 167, '@' .. CRAB;
said, by = applies(action(ME, 4, 633, { { MOB, 236, DEFENSE_DOWN }, { CRAB, 277, DEFENSE_DOWN } }));
assert(by[DEFENSE_DOWN .. on_crab] and not by[DEFENSE_DOWN .. on_crab].guessed and by[MAGIC_DEF_DOWN .. on_mob]
    and by[MAGIC_DEF_DOWN .. on_mob].guessed and by[MAGIC_DEF_DOWN .. on_crab] and by[MAGIC_DEF_DOWN .. on_crab].guessed,
    'Enervation lowers both on every monster it reaches: ' .. said);
said, by = applies(action(ME, 4, 633, { { MOB, 85, 0 }, { CRAB, 277, MAGIC_DEF_DOWN } }));
assert(said == DEFENSE_DOWN .. on_crab .. ' ' .. MAGIC_DEF_DOWN .. on_crab and by[DEFENSE_DOWN .. on_crab].guessed
    and not by[MAGIC_DEF_DOWN .. on_crab].guessed, 'Resisted by the first, it still lowers both on one after it: ' .. said);
assert(applies(action(ME, 4, 633, { { MOB, 85, 0 }, { CRAB, 284, 0 } })) == '', 'Resisted by both, it puts nothing on.');
-- Dia is still read its own way, once.
said, by = applies(action(ME, 4, 23, { { MOB, 2, 10 } }));
assert(said == '134' .. on_mob and by[said].inferred and not by[said].guessed, 'Dia is read as before: ' .. said);

-- Your jug pet's Wild Oats, and a party member's automaton's Shield Bash.
said, by = applies(action(MY_JUG, 11, 3845, { { MOB, 185, 80 } }));
assert(said == '138' .. on_mob and by[said].guessed and by[said].by_pet == true and by[said].action_kind == 'pet_moves', 'Your pet\'s Wild Oats: ' .. said);
-- Its Slow needs a Hammermill on the automaton, which can be checked only on your own, and the owner's Earth Maneuver,
-- which is checked only for yours too, so another's has both. It lasts 30, 50 or 70 seconds by the owner's Earth
-- Maneuvers, which are counted only for yours, so another's lasts 30 to 70 seconds.
said, by = applies(action(BOBS_PUPPET, 11, 1944, { { MOB, 185, 60 } }));
assert(said == STUN .. on_mob .. ' ' .. SLOW .. on_mob and by[STUN .. on_mob].source == BOBS_PUPPET and by[STUN .. on_mob].by_pet == nil,
    'A member\'s automaton stuns and may slow with Shield Bash: ' .. said);
local slowed = by[SLOW .. on_mob];
assert(slowed.duration == 70 and slowed.duration_min == 30, 'Another\'s Slow lasts 30 to 70 seconds: '
    .. tostring(slowed.duration_min) .. ' to ' .. tostring(slowed.duration));
-- Your own Earth Maneuvers and your automaton's attachments aren't another's: with two up and no Hammermill on yours,
-- theirs still slows for 30 to 70 seconds.
snapshot.self_effects = { { effect = 303, slot = 0 }, { effect = 303, slot = 1 } };
snapshot.pet.automaton = { name = 'CourierCarrie', attachments = { 97, 104, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } };
said, by = applies(action(BOBS_PUPPET, 11, 1944, { { MOB, 185, 60 } }));
slowed = by[SLOW .. on_mob];
assert(said == STUN .. on_mob .. ' ' .. SLOW .. on_mob and slowed.duration == 70 and slowed.duration_min == 30, 'Nothing of yours changes another\'s Slow: '
    .. said .. ', ' .. tostring(slowed and slowed.duration_min) .. ' to ' .. tostring(slowed and slowed.duration));
snapshot.self_effects, snapshot.pet.automaton = {}, nil;
owners[MY_JUG], owners[BOBS_PUPPET] = nil, nil;
owners[MY_JUG] = ME;
snapshot.self_effects = {};
said = applies(action(MY_JUG, 11, 1944, { { MOB, 185, 60 } }));
assert(said == STUN .. on_mob, 'Your automaton\'s Shield Bash with no Earth Maneuver only stuns: ' .. said);
-- With an Earth Maneuver up it slows too, for 30, 50 or 70 seconds by your Earth Maneuvers. Under Overdrive one counts as
-- three.
local EARTH, OVERDRIVE = 303, 166;
for count, seconds in ipairs({ 30, 50, 70 }) do
    snapshot.self_effects = {};
    for slot = 1, count do snapshot.self_effects[slot] = { effect = EARTH, slot = slot - 1 }; end
    said, by = applies(action(MY_JUG, 11, 1944, { { MOB, 185, 60 } }));
    slowed = by[SLOW .. on_mob];
    assert(said == STUN .. on_mob .. ' ' .. SLOW .. on_mob and slowed.duration == seconds and slowed.duration_min == seconds,
        'With ' .. count .. ' Earth Maneuvers up it slows for ' .. seconds .. ' seconds: ' .. said .. ', ' .. tostring(slowed and slowed.duration));
end
snapshot.self_effects = { { effect = EARTH, slot = 0 }, { effect = OVERDRIVE, slot = 1 } };
said, by = applies(action(MY_JUG, 11, 1944, { { MOB, 185, 60 } }));
slowed = by[SLOW .. on_mob];
assert(slowed and slowed.duration == 70 and slowed.duration_min == 70, 'Under Overdrive one Earth Maneuver slows for 70 seconds: ' .. said);
-- Once the game sends your automaton's attachments, they say whether a Hammermill (attachment 103) is on. Before that
-- it is taken as there, as above.
snapshot.self_effects = { { effect = EARTH, slot = 0 } };
snapshot.pet.automaton = { name = 'CourierCarrie', attachments = { 97, 104, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } };
said = applies(action(MY_JUG, 11, 1944, { { MOB, 185, 60 } }));
assert(said == STUN .. on_mob, 'With no Hammermill on, your automaton\'s Shield Bash only stuns: ' .. said);
snapshot.pet.automaton.attachments[3] = 103;
said, by = applies(action(MY_JUG, 11, 1944, { { MOB, 185, 60 } }));
assert(said == STUN .. on_mob .. ' ' .. SLOW .. on_mob and by[SLOW .. on_mob].duration == 30, 'With a Hammermill on, it slows: ' .. said);
snapshot.pet.automaton = nil;
-- With your own effects not read yet, your maneuvers can't be counted, so your automaton's Slow has the same range.
snapshot.self_known = false;
said, by = applies(action(MY_JUG, 11, 1944, { { MOB, 185, 60 } }));
slowed = by[SLOW .. on_mob];
assert(slowed and slowed.duration == 70 and slowed.duration_min == 30, 'With no listing of yours yet, the Slow lasts 30 to 70 seconds: ' .. said);
snapshot.self_known = true;
snapshot.self_effects = {};
owners[BOBS_PUPPET] = BOB;
-- A charmed monster's own move, and the same move from a monster nobody owns.
said, by = applies(action(CHARMED, 11, 2, { { MOB, 185, 40 } }));
assert(said == STUN .. on_mob and by[said].action_kind == 'charmed_skills', 'A charmed monster\'s Shoulder Tackle stuns its target: ' .. said);
-- It has a monster's own Shield Bash, which stuns for 7 seconds, not an automaton's.
said, by = applies(action(CHARMED, 11, 1944, { { MOB, 185, 40 } }));
assert(said == STUN .. on_mob and by[said].duration == 7 and by[said].action_kind == 'charmed_skills', 'A charmed monster\'s move is a monster\'s: ' .. said);
assert(applies(action(WILD, 11, 3845, { { MOB, 185, 40 } })) == '', 'A monster nobody owns is no pet.');
assert(applies(action(CRAB, 11, 2, { { MOB, 185, 40 } })) == '', 'Nor is a wild monster using its own move.');
-- Your avatar's Poison Nails, pact 513, with its message.
said, by = applies(action(MY_JUG, 13, 513, { { MOB, 317, 70 } }));
assert(said == POISON .. on_mob and by[said].guessed and by[said].action_kind == 'pacts', 'Poison Nails poisons: ' .. said);
-- An item used on a monster.
said, by = applies(action(ME, 5, 5268, { { MOB, 0, 0 } }));
assert(said == '16' .. on_mob and by[said].guessed and by[said].action_kind == 'items', 'A polymer pump: ' .. said);

-- Ice Spikes: a monster that hits someone with them up may be paralyzed, by the one it hit.
said, by = applies(action(MOB, 1, 0, { { ME, 1, 30, reaction = { 2, 44, 12 } } }));
assert(said == PARALYSIS .. on_mob and by[said].source == ME and by[said].guessed and by[said].duration == 30, 'Ice Spikes may paralyze the attacker: ' .. said);
assert(applies(action(MOB, 1, 0, { { ME, 1, 30, reaction = { 1, 44, 12 } } })) == '', 'Blaze Spikes put nothing on.');
assert(applies(action(MOB, 1, 0, { { ME, 1, 30 } })) == '', 'No spikes, nothing.');

-- Feint, ability 156: the next melee hit of whoever used it puts Evasion Down on what it hits, once.
assert(applies(action(BOB, 1, 0, { { MOB, 1, 40 } }), 10) == '', 'A plain hit puts nothing on.');
assert(applies(action(BOB, 6, 156, { { BOB, 100, 0 } }), 11) == '', 'Feint itself puts nothing on a monster.');
assert(applies(action(BOB, 1, 0, { { MOB, 15, 0 } }), 12) == '', 'A miss keeps it armed.');
assert(applies(action(BOB, 1, 0, { { MOB, 31, 1 } }), 12.2) == '', 'So does a swing that takes a shadow.');
assert(applies(action(BOB, 1, 0, { { MOB, 1, 0 } }), 12.5) == '', 'So does a swing the monster deflects, which reads as a hit for nothing.');
said, by = applies(action(BOB, 1, 0, { { MOB, 1, 40 } }), 13);
assert(said == EVASION_DOWN .. on_mob and by[said].source == BOB and by[said].duration == 30, 'The hit after Feint: ' .. said);
assert(applies(action(BOB, 1, 0, { { MOB, 1, 40 } }), 14) == '', 'And only that one.');
applies(action(BOB, 6, 156, { { BOB, 100, 0 } }), 20);
assert(applies(action(BOB, 1, 0, { { MOB, 1, 40 } }), 81) == '', 'A Feint left unused for a minute is gone.');
-- Phoenix takes Feint off at a KO with no word of it, so the first hit after a raise puts nothing on: a party member's
-- or yours, defeated by a monster (97) or with no attacker (20). A zone change keeps it.
local function defeated(who, by, message)
    local bytes = MOCK.bytes(28);
    MOCK.put(bytes, 4, 4, by); MOCK.put(bytes, 8, 4, who); MOCK.put(bytes, 24, 2, message);
    return MOCK.packet(0x029, bytes);
end
for _, case in ipairs({ { BOB, MOB, 97 }, { BOB, BOB, 20 }, { ME, MOB, 97 } }) do
    local who, by, message = case[1], case[2], case[3];
    applies(action(who, 6, 156, { { who, 100, 0 } }), 85);
    observer.read(defeated(who, by, message), 87, snapshot);
    said = applies(action(who, 1, 0, { { MOB, 1, 40 } }), 100);
    assert(said == '', 'Feint goes with its user\'s KO, message ' .. message .. ': ' .. said);
end
applies(action(BOB, 6, 156, { { BOB, 100, 0 } }), 110);
observer.read(MOCK.packet(0x00A, MOCK.bytes(64)), 111, snapshot);
said = applies(action(BOB, 1, 0, { { MOB, 1, 40 } }), 112);
assert(said == EVASION_DOWN .. on_mob, 'A zone change keeps Feint armed: ' .. said);

-- In the tracker: a guess makes a row, and never renews or replaces what is there.
local model = tracker.new();
local settings = { tracking = { max_entities = 64, stale_seconds = 180 } };
model:reconcile(snapshot, 0);
local function feed(e, at) model:observe(observer.read(e, at, snapshot), at, snapshot); end
local function row(effect)
    for _, held in ipairs(model:view(model.clock or 0, settings, snapshot).rows) do
        if held.entity_id == MOB and held.effect == effect then return held; end
    end
end
local function at(time) model.clock = time; end
at(100);
feed(action(ME, 3, 80, { { MOB, 185, 300 } }), 100);
local made = row(EVASION_DOWN);
assert(made and made.deadline == 280 and made.mine == true and made.kind == 'debuff', 'The guess is a row on the monster with its time: ' .. tostring(made and made.deadline));
-- A second Shield Break while it is on changes nothing: the server adds none over one.
at(150);
feed(action(BOB, 3, 80, { { MOB, 185, 300 } }), 150);
made = row(EVASION_DOWN);
assert(made.deadline == 280 and made.source == ME, 'A second one while it is on is not a new one: ' .. tostring(made.deadline));
-- When its time is up a guess goes, with no wear-off to wait for: nothing ever said it was on.
at(279);
assert(row(EVASION_DOWN) ~= nil, 'Fixture: it is there until its time is up.');
at(280);
assert(row(EVASION_DOWN) == nil, 'A guess goes when its time is up.');
-- Past its time, another hit starts it again.
at(300);
feed(action(BOB, 3, 80, { { MOB, 185, 300 } }), 300);
made = row(EVASION_DOWN);
assert(made and made.deadline == 480 and made.source == BOB, 'After its time, the next one counts: ' .. tostring(made and made.deadline));
-- The same from a job ability: Chi Blast from one monk, then from another after the first one's time is up.
snapshot.job = 1;
feed(action(BOB, 6, 82, { { MOB, 110, 200 } }), 500);
at(501);
local inhibit = row(168);
assert(inhibit and inhibit.source == BOB and inhibit.deadline == 560, 'Fixture: a member\'s Chi Blast is a row.');
feed(action(ALLY, 6, 82, { { MOB, 110, 200 } }), 600);
at(601);
inhibit = row(168);
assert(inhibit and inhibit.source == ALLY and inhibit.deadline == 660, 'After its time, another monk\'s is theirs, with its time: '
    .. tostring(inhibit and inhibit.source) .. ', ' .. tostring(inhibit and inhibit.deadline));
-- A guess doesn't spoil a time being learned: your reported Paralysis wears off, and a guess of Paralysis follows.
local fresh = tracker.new();
fresh:reconcile(snapshot, 0);
local cast = observer.read(action(ME, 4, 58, { { CRAB, 236, PARALYSIS } }), 700, snapshot);
for _, made in ipairs(cast) do if made.kind == 'apply' then made.learn_key = 'spells:58:4:'; end end
fresh:observe(cast, 700, snapshot);
fresh:observe({ { kind = 'remove', entity_id = CRAB, effect = PARALYSIS, reason = tracker.WEAR_OFF } }, 760, snapshot);
fresh:observe(observer.read(action(CRAB, 1, 0, { { ME, 1, 30, reaction = { 2, 44, 12 } } }), 760.5, snapshot), 760.5, snapshot);
assert(#fresh:samples(762) == 1, 'A guess after your wear-off leaves its time to be learned: ' .. #fresh:samples(762));
-- A real Paralysis the game reported is not touched by a guess of it from Ice Spikes.
feed(action(STRANGER, 4, 58, { { MOB, 236, PARALYSIS } }), 310);
at(311);
local real = row(PARALYSIS);
assert(real and real.source == STRANGER, 'Fixture: a reported Paralysis.');
local ends = real.deadline;
feed(action(MOB, 1, 0, { { ME, 1, 30, reaction = { 2, 44, 12 } } }), 320);
at(321);
real = row(PARALYSIS);
assert(real.source == STRANGER and real.deadline == ends, 'A guess leaves a reported effect as it is.');
-- Your own wear-off ends a guess that did land.
model:observe({ { kind = 'remove', entity_id = MOB, effect = EVASION_DOWN, reason = tracker.WEAR_OFF } }, 330, snapshot);
at(331);
assert(row(EVASION_DOWN) == nil, 'A wear-off takes it off.');
-- A guess gives no time to learn from.
at(400);
feed(action(ME, 3, 80, { { MOB, 185, 300 } }), 400);
model:observe({ { kind = 'remove', entity_id = MOB, effect = EVASION_DOWN, reason = tracker.WEAR_OFF } }, 520, snapshot);
assert(#model:samples(530) == 0, 'A guessed effect is not a time to learn.');
-- A guess with no time to count goes once it is as old as anything is kept with no word of it.
at(600);
feed(action(BOB, 3, 16, { { MOB, 185, 90 } }), 600);
at(779);
assert(row(POISON) ~= nil and row(POISON).deadline == nil, 'A guess with no time stays, with no countdown.');
at(781);
assert(row(POISON) == nil, 'And goes once it is too old.');
-- An effect the game then reports over a guess is no guess: past its estimate it stays as any estimate does, with no
-- countdown, until it is too old.
feed(action(BOB, 3, 87, { { MOB, 185, 500 } }), 800);
at(801);
assert(row(DEFENSE_DOWN) ~= nil, 'Fixture: Full Break\'s guessed Defense Down.');
feed(action(BOB, 6, 170, { { MOB, 127, DEFENSE_DOWN } }), 810);
at(811);
local reported = row(DEFENSE_DOWN);
assert(reported and reported.deadline and reported.deadline > 811, 'Fixture: a reported Defense Down over it, with its time.');
local over = reported.deadline;
at(over + 1);
reported = row(DEFENSE_DOWN);
assert(reported ~= nil and reported.deadline == nil, 'A reported effect over a guess stays past its estimate.');
at(over + 181);
assert(row(DEFENSE_DOWN) == nil, 'Fixture: and goes once it is too old.');
-- A job ability's result from someone else over a guess: the effect is now a reported one, theirs, with its time.
local t = over + 200;
feed(action(BOB, 3, 87, { { MOB, 185, 500 } }), t);
at(t + 1);
assert(row(DEFENSE_DOWN) and row(DEFENSE_DOWN).source == BOB, 'Fixture: a member\'s guessed Defense Down.');
feed(action(ALLY, 6, 170, { { MOB, 127, DEFENSE_DOWN } }), t + 10);
at(t + 11);
reported = row(DEFENSE_DOWN);
assert(reported and reported.source == ALLY and reported.deadline and reported.deadline < t + 180,
    'Another player\'s reported ability takes a guess over, with its own time: ' .. tostring(reported and reported.source) .. ', ' .. tostring(reported and reported.deadline));
over = reported.deadline;
at(over + 1);
assert(row(DEFENSE_DOWN) ~= nil and row(DEFENSE_DOWN).deadline == nil, 'And it stays past its estimate, as a reported one does.');
-- A guessed Bind that takes a hit loses its countdown, as any Bind does, and still goes at its time.
t = over + 400;
feed(action(ME, 4, 648, { { MOB, 2, 80 } }), t);
at(t + 1);
assert(row(BIND) and row(BIND).deadline == t + 30, 'Fixture: a guessed Bind of 30 seconds: ' .. tostring(row(BIND) and row(BIND).deadline));
feed(action(BOB, 1, 0, { { MOB, 1, 30 } }), t + 5);
at(t + 29);
assert(row(BIND) ~= nil and row(BIND).deadline == nil, 'A hit takes its countdown off.');
at(t + 30);
assert(row(BIND) == nil, 'It still goes when its time is up.');
-- A guessed Dia doesn't keep a real one off: a charmed monster's move leaves the guess, then a member casts Dia II.
t = t + 100;
feed(action(CHARMED, 11, 1258, { { MOB, 185, 40 } }), t);
at(t + 1);
local dia = row(134);
assert(dia and dia.source == CHARMED and dia.deadline == t + 30, 'Fixture: a guessed Dia from a charmed monster\'s move.');
feed(action(BOB, 4, 24, { { MOB, 2, 12 } }), t + 5);
at(t + 6);
dia = row(134);
assert(dia and dia.source == BOB and dia.deadline == t + 125, 'A cast Dia II lands over a guessed Dia: ' .. tostring(dia and dia.source) .. ', ' .. tostring(dia and dia.deadline));
-- A real Dia II still keeps a weaker one off.
feed(action(ALLY, 4, 23, { { MOB, 2, 4 } }), t + 10);
at(t + 11);
dia = row(134);
assert(dia.source == BOB and dia.deadline == t + 125, 'Fixture: a weaker Dia changes nothing over a real Dia II.');
-- Hysteria lasts 25 to 32 seconds, so its row counts down that range.
local hud = require('ui.hud');
t = t + 100;
feed(action(BOB, 5, 5262, { { MOB, 0, 0 } }), t);
at(t + 1);
local hysteria = row(804);
assert(hysteria and hysteria.duration_min == 25 and hysteria.total == 32 and hud.timer_text(hysteria, t + 1) == '24s - 31s',
    'Hysteria counts down its range: ' .. tostring(hysteria and hud.timer_text(hysteria, t + 1)));
-- A member's Jump with no Spirit Surge on their listing leaves no Defense Down, so a Full Break after it shows its own.
t = t + 100;
bob.valid, bob.effects = true, {};
feed(action(BOB, 3, 66, { { MOB, 317, 90 } }), t);
bob.valid, bob.effects = nil, nil;
feed(action(ALLY, 3, 87, { { MOB, 185, 500 } }), t + 10);
at(t + 11);
local broke = row(DEFENSE_DOWN);
assert(broke and broke.source == ALLY and broke.deadline == t + 190, 'A member\'s Jump with no Spirit Surge keeps no Break off: '
    .. tostring(broke and broke.source) .. ', ' .. tostring(broke and broke.deadline));
-- Your automaton's Slow goes at the end of its 30 seconds with one Earth Maneuver, not once it is too old.
t = t + 300;
snapshot.self_effects = { { effect = EARTH, slot = 0 } };
feed(action(MY_JUG, 11, 1944, { { MOB, 185, 60 } }), t);
snapshot.self_effects = {};
at(t + 29);
assert(row(SLOW) ~= nil and row(SLOW).deadline == t + 30, 'Fixture: your automaton\'s Slow counts down its 30 seconds: ' .. tostring(row(SLOW) and row(SLOW).deadline));
at(t + 30);
assert(row(SLOW) == nil, 'Your automaton\'s Slow goes when its time is up.');
return 'Debuffs the game never reports are taken from what the action did';
