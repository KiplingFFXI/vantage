-- Phoenix sends a job ability that gives a buff as category 6 with the ability's own message (Berserk 115,
-- Warcry 116 on its user, 285 on a party member, the circles) or 'uses' (100) when it has none (Hasso),
-- with the effect as param (CCharEntity::OnAbility). The player's own then has its caster and total, and each of the
-- player's own reports its use for the recast reader, as do their avatar's pact going off and an action of theirs
-- paralysis stopped.
local observer = require('core.observer');
local tracker = require('core.tracker').new();
local self_id, ally = 1001, 1002;
local snapshot = { valid = true, id = self_id, zone = 102, name = 'Tester', level = 75, job = 1, self_known = true,
    self_effects = {}, party = { { id = ally, name = 'Ally', scope = 'party', zone = 102 } },
    entities = { [self_id] = { name = 'Tester' }, [ally] = { name = 'Ally', kind = 'player' }, [0x1000001] = { name = 'Crab', kind = 'monster' } } };
local function putbits(bytes, offset, length, value)
    for i = 0, length - 1 do
        local at = offset + i;
        if math.floor(value / 2 ^ i) % 2 == 1 then bytes[math.floor(at / 8)] = bytes[math.floor(at / 8)] + 2 ^ (at % 8); end
    end
end
-- One action, category 6 from the player unless given: each target with its message and param.
local function action(ability, targets, category, actor)
    local bytes, at = MOCK.bytes(2048), 150;
    putbits(bytes, 40, 32, actor or self_id); putbits(bytes, 72, 6, #targets); putbits(bytes, 82, 4, category or 6);
    putbits(bytes, 86, 32, ability);
    for _, target in ipairs(targets) do
        putbits(bytes, at, 32, target[1]); putbits(bytes, at + 32, 4, 1); at = at + 36;
        putbits(bytes, at + 27, 17, target[3]); putbits(bytes, at + 44, 10, target[2]); at = at + 87;
    end
    bytes.n = math.ceil(at / 8);
    return MOCK.packet(0x028, bytes);
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
