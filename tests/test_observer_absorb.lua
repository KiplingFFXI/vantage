-- Absorb-STR to Absorb-CHR that land say so with their own message, 329 to 335, and name the Down they put on, 136 to
-- 142, which Phoenix's era keeps 90 seconds (globals/spells/absorb_spell.lua, modules/era/lua/actions/spells/
-- spell_adjustments.lua :113-150). A resist is 85 with nothing named, and one that took no effect 75. Real 0x028s through
-- observer.read and the tracker.
local observer = require('core.observer');
local tracker = require('core.tracker').new();
local SELF, ALLY, MOB = 1001, 1002, 0x1000123;
local snapshot = { valid = true, id = SELF, name = 'Tester', zone = 151, job = 8, level = 75, self_known = true, self_revision = 1,
    self_timer_revision = 1, self_effects = {}, party = { { id = ALLY, name = 'Ally', scope = 'party' } },
    entities = { [SELF] = { id = SELF, name = 'Tester', kind = 'player' }, [ALLY] = { id = ALLY, name = 'Ally', kind = 'player' },
        [MOB] = { id = MOB, name = 'Goblin Smithy', kind = 'monster' } },
    target = { id = MOB, name = 'Goblin Smithy', kind = 'monster' } };
-- One spell from actor on the mob, with its message and param.
local function cast(actor, spell, message, param)
    return MOCK.packet(0x028, MOCK.action_bytes(actor, 4, spell, { { id = MOB, rows = { { message = message, param = param } } } }));
end
local function applied(events)
    for _, event in ipairs(events) do if event.kind == 'apply' then return event; end end
end

for at = 0, 6 do
    local spell, message, effect = 266 + at, 329 + at, 136 + at;
    for _, actor in ipairs({ SELF, ALLY }) do
        local events = observer.read(cast(actor, spell, message, effect), 10, snapshot);
        local seen = applied(events);
        assert(seen and seen.entity_id == MOB and seen.effect == effect and seen.source == actor and seen.duration == 90
            and seen.scope == 'enemy', 'Spell ' .. spell .. ' by ' .. actor .. ' with ' .. message .. ' puts ' .. effect .. ' on the mob for 90 seconds: '
            .. (seen and (tostring(seen.effect) .. ' for ' .. tostring(seen.duration)) or 'nothing'));
    end
end
assert(applied(observer.read(cast(SELF, 266, 85, 0), 10, snapshot)) == nil, 'A resist puts nothing on.');
assert(applied(observer.read(cast(SELF, 266, 75, 136), 10, snapshot)) == nil, 'One that took no effect puts nothing on.');

-- The mob's row counts down from your cast.
tracker:observe(observer.read(cast(SELF, 266, 329, 136), 10, snapshot), 10, snapshot);
tracker:reconcile(snapshot, 10);
local row;
for _, value in ipairs(tracker:view(10, {}, snapshot).rows) do if value.entity_id == MOB and value.effect == 136 then row = value; end end
assert(row and row.mine == true and row.total == 90 and row.status == 'estimated', 'Your Absorb-STR shows STR Down on the mob for 90 seconds.');
return 'Absorb-STR to Absorb-CHR put their Down on the mob';
