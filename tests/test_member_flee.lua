-- Flee puts Flee (32) on its user for 30 seconds plus their gear's Flee duration, and its result is message 126, which
-- only Flee sends in Phoenix's era (globals/job_utils/thief.lua :274-284, sql/abilities.sql :62). Rogue's Poulaines give
-- +15 (sql/item_mods.sql :20215), so another player's counts 30 to 45. A party member's real 0x028 through
-- observer.read, then the tracker.
local observer = require('core.observer');
local SELF, BOB, MOB = 1001, 1002, 0x1000123;
local function snapshot()
    return { valid = true, id = SELF, name = 'Tester', zone = 102, job = 1, level = 75, self_known = true, self_effects = {},
        party = { { id = BOB, name = 'Bob', scope = 'party', valid = true, effects = {} } },
        entities = { [SELF] = { name = 'Tester' }, [BOB] = { name = 'Bob', kind = 'player' }, [MOB] = { name = 'Goblin', kind = 'monster' } } };
end
-- A job ability from actor with one result on target.
local function ability(actor, id, target, message, param)
    return MOCK.packet(0x028, MOCK.action_bytes(actor, 6, id, { { id = target, rows = { { message = message, param = param } } } }));
end

local events = observer.read(ability(BOB, 42, BOB, 126, 32), 1, snapshot());
local flee;
for _, event in ipairs(events) do if event.kind == 'apply' and event.entity_id == BOB and event.effect == 32 then flee = event; end end
assert(flee, 'A party member\'s Flee puts Flee on them.');
assert(flee.duration == 45 and flee.duration_min == 30 and flee.action_kind == 'abilities',
    'It counts 30 to 45 seconds: ' .. tostring(flee.duration_min) .. ' to ' .. tostring(flee.duration) .. ', ' .. tostring(flee.action_kind));

local tracker = require('core.tracker').new();
local snap = snapshot();
tracker:observe(events, 1, snap); tracker:reconcile(snap, 1);
local row;
for _, shown in ipairs(tracker:view(2, {}, snap).rows) do if shown.entity_id == BOB and shown.effect == 32 then row = shown; end end
assert(row and row.status == 'estimated' and row.remaining == 44 and row.source == BOB,
    'Bob\'s Flee counts down: ' .. tostring(row and row.status) .. ', ' .. tostring(row and row.remaining));
return 'A party member\'s Flee shows and counts down';
