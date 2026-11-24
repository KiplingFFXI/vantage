-- A duration override picked as "A job ability" reaches what the ability put on. Phoenix sends some job abilities in
-- action category 3, the weapon skills' (Shadowbind, Shield Bash, Weapon Bash, Angon, Tomahawk, Blade Bash:
-- sql/abilities.sql actionType 3), and Feint's Evasion Down is only taken from the next melee hit, so neither carries
-- the job ability category 6. The observer tells both apart all the same, and so do the overrides and learned times.
local durations = require('core.durations');
local observer = require('core.observer');
local SELF, MOB = 1001, 0x1000123;
local function snapshot(job)
    return { valid = true, id = SELF, name = 'Aster', zone = 102, job = job, level = 75, self_known = true, self_revision = 1,
        self_timer_revision = 1, self_effects = {}, party = {},
        entities = { [SELF] = { id = SELF, name = 'Aster', kind = 'player' }, [MOB] = { id = MOB, name = 'Goblin Smithy', kind = 'monster' } },
        target = { id = MOB, name = 'Goblin Smithy', kind = 'monster' } };
end;
local function action(actor, category, id, target, message, param)
    return MOCK.packet(0x028, MOCK.action_bytes(actor, category, id, { { id = target, rows = { { message = message, param = param } } } }));
end
local function copied(list)
    local out = {};
    for index, value in ipairs(list) do out[index] = value; end
    return out;
end
local function applied(observations, effect)
    for _, o in ipairs(observations) do if o.kind == 'apply' and o.effect == effect then return o; end end
end
local function rule(id, seconds)
    local value = durations.override();
    value.kind, value.id, value.mode, value.seconds = 'ability', id, 'fixed', seconds;
    return value;
end

-- Your Shadowbind lands: category 3, ability 57, message 277, Bind (11) (ranger.lua useShadowbind :265-266).
local settings = { durations = durations.tidy({}) };
settings.durations.overrides[1] = rule(57, 45);
local snap = snapshot(11);
local observations = copied(observer.read(action(SELF, 3, 57, MOB, 277, 11), 1, snap));
local bind = applied(observations, 11);
assert(bind and bind.action_category == 3 and bind.duration ~= 45, 'Fixture: the observer reads the Shadowbind Bind.');
durations.prepare(observations, settings, snap);
assert(bind.duration == 45 and bind.timing == 'override',
    'The Shadowbind override (A job ability, Shadowbind, 45 s) sets the Bind time: ' .. tostring(bind.duration));
-- Its learned times go under the ability, which the Timer durations page names, not under any Bind on that mob.
assert(durations.key(bind) == 'ability:57:11:goblin smithy', 'Shadowbind\'s Bind is learned as the ability\'s: ' .. tostring(durations.key(bind)));
-- A weapon skill in the same category still goes by its effect alone.
assert(durations.key({ action_category = 3, action_kind = 'skills', spell = 20, effect = 11, scope = 'enemy', entity_name = 'Goblin Smithy' })
    == 'effect:0:11:goblin smithy', 'A weapon skill\'s effect still keys by the effect.');

-- Feint: category 6, ability 156, message 100 on yourself. Your next melee hit for 50 takes Evasion Down (148) as
-- put on.
settings = { durations = durations.tidy({}) };
settings.durations.overrides[1] = rule(156, 45);
snap = snapshot(6);
observer.read(action(SELF, 6, 156, SELF, 100, 343), 2, snap);
observations = copied(observer.read(action(SELF, 1, 0, MOB, 1, 50), 3, snap));
local down = applied(observations, 148);
assert(down and down.action_category == 1 and down.duration ~= 45, 'Fixture: the hit after Feint takes Evasion Down as put on.');
durations.prepare(observations, settings, snap);
assert(down.duration == 45 and down.timing == 'override',
    'The Feint override (A job ability, Feint, 45 s) sets the Evasion Down time: ' .. tostring(down.duration));
return 'A job ability override reaches category 3 abilities and Feint';
