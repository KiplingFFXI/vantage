-- Phoenix sends a job ability that gives a buff as category 6 with the ability's own message (Berserk 115,
-- Warcry 116 on its user, 285 on a party member, the circles) or 'uses' (100) when it has none (Hasso),
-- or 0 for one with none that reaches everyone around its user, with the effect as param (CCharEntity::OnAbility).
-- The player's own then has its caster and total, and each of the player's own reports its use for the recast reader,
-- as do their avatar's pact going off and an action of theirs paralysis stopped.
local observer = require('core.observer');
local tracker = require('core.tracker').new();
local self_id, ally = 1001, 1002;
local snapshot = { valid = true, id = self_id, zone = 102, name = 'Tester', level = 75, job = 1, self_known = true,
    self_effects = {}, party = { { id = ally, name = 'Ally', scope = 'party', zone = 102 } },
    entities = { [self_id] = { name = 'Tester' }, [ally] = { name = 'Ally', kind = 'player' }, [0x1000001] = { name = 'Crab', kind = 'monster' } } };
-- One action, category 6 from the player unless given: each target with its message and param.
local function action(ability, targets, category, actor)
    local rows = {};
    for i, target in ipairs(targets) do rows[i] = { id = target[1], rows = { { message = target[2], param = target[3] } } }; end
    return MOCK.packet(0x028, MOCK.action_bytes(actor or self_id, category or 6, ability, rows));
end
local function applies(events, id, effect)
    for _, event in ipairs(events) do
        if event.kind == 'apply' and event.entity_id == id and event.effect == effect and event.source == self_id then return true; end
    end
    return false;
end
-- Your own job ability also reports its use, last, for the recast reader.
local function used(events, ability)
    local last = events[#events];
    return last ~= nil and last.kind == 'used' and last.ability == ability;
end
local events = observer.read(action(31, { { self_id, 115, 56 } }), 1, snapshot);
assert(#events == 2 and applies(events, self_id, 56) and events[1].spell == 31 and used(events, 31),
    'Berserk (115) is the player\'s own application.');
events = observer.read(action(173, { { self_id, 100, 353 } }), 1, snapshot);
assert(#events == 2 and applies(events, self_id, 353) and used(events, 173), 'Hasso, sent as \'uses\' (100), is the player\'s own application.');
events = observer.read(action(32, { { self_id, 116, 68 }, { ally, 285, 68 } }), 1, snapshot);
assert(#events == 3 and applies(events, self_id, 68) and applies(events, ally, 68) and events[2].scope == 'party' and used(events, 32),
    'Warcry is credited on its user and on the party member.');
events = observer.read(action(47, { { self_id, 131, 74 }, { ally, 286, 74 } }), 1, snapshot);
assert(#events == 3 and applies(events, self_id, 74) and applies(events, ally, 74) and used(events, 47),
    'Holy Circle is credited on everyone it reaches.');
-- 'uses' with something else in the param: Wild Card's roll, Scavenge's item, a target other than its user.
local function only_used(packet, ability)
    local seen = observer.read(packet, 1, snapshot);
    return #seen == 1 and used(seen, ability);
end
assert(only_used(action(96, { { self_id, 100, 3 } }), 96), 'A param that is no buff is no application.');
assert(only_used(action(56, { { self_id, 100, 17298 } }), 56), 'An item ID is no application.');
assert(only_used(action(46, { { 0x1000001, 100, 56 } }), 46), '\'uses\' on another target is no application.');
assert(only_used(action(35, { { 0x1000001, 119, 56 } }), 35), 'Provoke gives no buff.');
-- Jump finishes as category 3, as a weapon skill does. Someone else's ability, and your spell, are no use of yours.
assert(used(observer.read(action(66, { { 0x1000001, 110, 120 } }, 3), 1, snapshot), 66), 'Jump is your use.');
local others = observer.read(action(35, { { 0x1000001, 119, 0 } }, 6, ally), 1, snapshot);
assert(#others == 1 and others[1].kind == 'cooldown', 'Someone else\'s Provoke is no use of yours, only their cooldown.');
for _, seen in ipairs(observer.read(action(144, { { 0x1000001, 2, 100 } }, 4), 1, snapshot)) do
    assert(seen.kind ~= 'used', 'A spell is no ability use.');
end
-- A Double-Up comes with the id of the roll it doubles (Phoenix modules/era/lua/globals/job_utils/corsair.lua :349), and
-- only a Double-Up gives your own row 424, or 426 on a bust. Its cooldown is Double-Up's own, timer 194
-- (src/map/entities/char_entity.cpp :2130, sql/abilities.sql :143), so it is a use of Double-Up, ability 123. A roll is
-- a use of the roll, and a party member's Double-Up is no use of yours.
assert(used(observer.read(action(98, { { self_id, 424, 9 }, { ally, 421, 9 } }), 1, snapshot), 123),
    'Your Double-Up on Fighter\'s Roll is a use of Double-Up.');
assert(used(observer.read(action(98, { { self_id, 426, 12 }, { ally, 427, 12 } }), 1, snapshot), 123), 'So is one that busts.');
assert(used(observer.read(action(98, { { self_id, 420, 4 }, { ally, 421, 4 } }), 1, snapshot), 98), 'Fighter\'s Roll is a use of itself.');
for _, seen in ipairs(observer.read(action(98, { { ally, 424, 9 }, { self_id, 421, 9 } }, 6, ally), 1, snapshot)) do
    assert(seen.kind ~= 'used', 'A party member\'s Double-Up is no use of yours.');
end
-- Your avatar's pact going off is a use of it too. Phoenix starts the pact's cooldown then (summoner.lua
-- onUseBloodPact), and the avatar's move has the pact's own id (pet_entity.cpp OnPetSkillFinished). Someone else's
-- avatar, and a jug pet's move (category 11), are no use of yours.
local pet_id = 0x1000700;
local summoner = {};
for key, value in pairs(snapshot) do summoner[key] = value; end;
summoner.pet = { id = pet_id };
assert(used(observer.read(action(544, { { 0x1000001, 317, 120 } }, 13, pet_id), 1, summoner), 544), 'Your avatar\'s Punch is your use of it.');
for _, packet in ipairs({ action(544, { { 0x1000001, 317, 120 } }, 13, pet_id + 1), action(257, { { 0x1000001, 185, 120 } }, 11, pet_id) }) do
    for _, seen in ipairs(observer.read(packet, 1, summoner)) do
        assert(seen.kind ~= 'used', 'Another avatar\'s pact, and a jug pet\'s move, are no use of yours.');
    end
end
-- Paralysis stopping your job ability or ranged attack is category 4 with no action id, and message 84 (AbilityParalyzed).
-- A paralyzed spell has its id, and someone else's paralysis is theirs.
local function paralyzed(packet)
    for _, seen in ipairs(observer.read(packet, 1, snapshot)) do if seen.kind == 'paralyzed' then return true; end end
    return false;
end
assert(paralyzed(action(0, { { 0x1000001, 84, 0 } }, 4)), 'Your paralyzed ability says so.');
assert(not paralyzed(action(144, { { 0x1000001, 84, 0 } }, 4)), 'A paralyzed spell is no paralyzed ability.');
assert(not paralyzed(action(0, { { 0x1000001, 84, 0 } }, 4, ally)), 'Someone else\'s paralysis is not yours.');

-- The player's Berserk, then the listing that shows it.
tracker:reconcile(snapshot, 10);
tracker:observe(observer.read(action(31, { { self_id, 115, 56 } }), 10, snapshot), 10, snapshot);
local listed = {};
for key, value in pairs(snapshot) do listed[key] = value; end;
listed.self_effects = { { effect = 56, slot = 0, raw_timer = 6000, deadline = 190 } };
listed.self_revision, listed.self_timer_revision = 2, 2;
tracker:reconcile(listed, 10.2);
local row;
for _, value in ipairs(tracker:view(10.2, nil, listed).rows) do if value.effect == 56 then row = value; end; end;
assert(row and row.source == self_id and row.mine == true and row.spell == 31 and row.total == 180,
    'The player\'s Berserk has its caster, its ability and its total.');

-- A party member's Hundred Fists, sent as 'uses' (100) on its user, lasts a set 45 seconds, so it counts down.
local fists;
for _, seen in ipairs(observer.read(action(17, { { ally, 100, 46 } }, 6, ally), 1, snapshot)) do
    if seen.kind == 'apply' then fists = seen; end
end
assert(fists and fists.entity_id == ally and fists.effect == 46 and fists.duration == 45,
    'A party member\'s Hundred Fists counts down 45 seconds: ' .. tostring(fists and fists.duration));
-- Your Charm on a monster it can't charm binds it instead (127), for 1 to 5 seconds, so it counts down that range.
local bound;
for _, seen in ipairs(observer.read(action(52, { { 0x1000001, 127, 11 } }), 1, snapshot)) do
    if seen.kind == 'apply' then bound = seen; end
end
assert(bound and bound.entity_id == 0x1000001 and bound.effect == 11 and bound.duration == 5 and bound.duration_min == 1,
    'Charm\'s Bind counts down 1 to 5 seconds: ' .. tostring(bound and bound.duration_min) .. ' to ' .. tostring(bound and bound.duration));

-- An ability that reaches everyone around its user keeps its own message on every row, and one with none keeps 0, as
-- only a single target's 0 becomes 'uses' (char_entity.cpp :2038-2075, :2099-2101). Killer Instinct is 0 on every row
-- and puts itself on each of them, Diffusion is 0 on its user alone, and Mantra is 441 on its user and 421 on the others
-- (sql/abilities.sql :170, :181, :195, messageutils.h :67).
local function lands(events, id, effect)
    for _, event in ipairs(events) do
        if event.kind == 'apply' and event.entity_id == id and event.effect == effect then return event; end
    end
end
local function said(event) return event and (tostring(event.duration) .. ' s by ' .. tostring(event.source) .. ' as ' .. tostring(event.action_kind)) or 'nothing'; end
local instinct = observer.read(action(162, { { ally, 0, 349 }, { self_id, 0, 349 } }, 6, ally), 1, snapshot);
local on_user, on_you = lands(instinct, ally, 349), lands(instinct, self_id, 349);
assert(on_user and on_you and on_user.duration == 60 and on_you.duration == 60 and on_user.source == ally and on_you.action_kind == 'abilities',
    'A party member\'s Killer Instinct counts 60 seconds on them and on you: ' .. said(on_user) .. ', ' .. said(on_you));
instinct = observer.read(action(162, { { self_id, 0, 349 }, { ally, 0, 349 } }), 1, snapshot);
assert(applies(instinct, self_id, 349) and applies(instinct, ally, 349) and used(instinct, 162),
    'Your Killer Instinct is yours on you and on the party member.');
local mantra = observer.read(action(151, { { self_id, 441, 88 }, { ally, 421, 88 } }), 1, snapshot);
assert(applies(mantra, self_id, 88) and applies(mantra, ally, 88) and lands(mantra, ally, 88).duration == 180 and used(mantra, 151),
    'Your Mantra is yours on you and on the party member, for 180 seconds (globals/job_utils/monk.lua :215): ' .. said(lands(mantra, ally, 88)));
local diffusion = observer.read(action(176, { { ally, 0, 356 } }, 6, ally), 1, snapshot);
assert(lands(diffusion, ally, 356) and lands(diffusion, ally, 356).duration == 60,
    'A party member\'s Diffusion counts 60 seconds on them: ' .. said(lands(diffusion, ally, 356)));
diffusion = observer.read(action(176, { { ally, 0, 356 }, { self_id, 0, 356 } }, 6, ally), 1, snapshot);
assert(lands(diffusion, ally, 356) and not lands(diffusion, self_id, 356), 'Diffusion goes on its user alone, whatever else its rows say.');
-- Random Deal is 441 and 421 too, with no buff in the param.
assert(only_used(action(133, { { self_id, 441, 0 }, { ally, 421, 0 } }), 133), 'Random Deal puts no buff on.');
