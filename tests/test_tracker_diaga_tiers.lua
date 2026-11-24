-- A monster's Diaga II is tier 3 and its Diaga III tier 5, as Dia II and Dia III are (Phoenix
-- scripts/actions/spells/white/diaga_ii.lua :14, diaga_iii.lua :14). A Dia goes on only over a Dia of a lower tier
-- (data/status_effects.yaml :1302, src/map/status_effect_container.cpp :421-426) and over no Bio of the same or a higher
-- tier (diaga_ii.lua :17-26), and Bio the same way over Dia. An alliance member has no listing, so only the casts tell.
-- Real 0x028s through observer.read and the real tracker.
local observer = require('core.observer');
local SELF, ALLY, FRIEND, MOB = 1001, 1002, 1007, 0x1000123;
local slots = { [6] = { job = 5, zone2 = 0, updated = 1700000000 } };
local party = {
    GetMemberMainJob = function(_, slot) return slots[slot] and slots[slot].job; end,
    GetMemberZone2 = function(_, slot) return slots[slot] and slots[slot].zone2; end,
    GetMemberLastUpdatedTimestamp = function(_, slot) return slots[slot] and slots[slot].updated; end,
};
AshitaCore.GetMemoryManager = function() return { GetParty = function() return party; end }; end;
local function snapshot()
    return { valid = true, id = SELF, name = 'Tester', zone = 151, job = 6, level = 75, self_known = true, self_revision = 1,
        self_timer_revision = 1, self_effects = {},
        party = { { id = ALLY, name = 'Ally', scope = 'party', slot = 1, group = 1, zone = 151 },
            { id = FRIEND, name = 'Friend', scope = 'alliance', slot = 6, group = 2, zone = 151 } },
        entities = { [SELF] = { id = SELF, name = 'Tester', kind = 'player' }, [ALLY] = { id = ALLY, name = 'Ally', kind = 'player' },
            [FRIEND] = { id = FRIEND, name = 'Friend', kind = 'player' },
            [MOB] = { id = MOB, name = 'Yagudo Conquistador', kind = 'monster' } },
        target = { id = MOB, name = 'Yagudo Conquistador', kind = 'monster' } };
end;
local function action(actor, category, id, rows)
    local targets = {};
    for i, row in ipairs(rows) do targets[i] = { id = row[1], rows = { { message = row[2], param = row[3] } } }; end
    return MOCK.packet(0x028, MOCK.action_bytes(actor, category, id, targets));
end
local tracker;
-- The friend's Dia and Bio rows, each as its effect and the seconds it has left.
local function rows_of(now, packets)
    local snap, observations = snapshot(), {};
    for _, packet in ipairs(packets) do for _, o in ipairs(observer.read(packet, now, snap)) do observations[#observations + 1] = o; end end
    tracker:observe(observations, now, snap); tracker:reconcile(snap, now);
    local out = {};
    for _, row in ipairs(tracker:view(now, {}, snap).rows) do
        if row.entity_id == FRIEND then
            out[#out + 1] = ('%d(%s)'):format(row.effect, row.remaining and tostring(math.floor(row.remaining + 0.5)) or '-');
        end
    end
    table.sort(out);
    return table.concat(out, ',');
end;
-- The mob's spell hits the friend for 20 (message 2).
local function cast(spell) return action(MOB, 4, spell, { { FRIEND, 2, 20 } }); end
local cases = {
    -- The first spell, the second, the seconds between them, and what Phoenix leaves.
    { 'Dia II then Dia II', 24, 24, 30, '134(90)' },
    { 'Dia II then Diaga II', 24, 34, 30, '134(90)' },
    { 'Bio II then Diaga II', 231, 34, 10, '135(110)' },
    { 'Diaga II then Bio II', 34, 231, 10, '135(120)' },
    { 'Diaga II then Diaga II', 34, 34, 30, '134(90)' },
    { 'Diaga III then Diaga III', 35, 35, 30, '134(150)' },
    { 'Diaga II then Diaga III', 34, 35, 30, '134(180)' },
};
local log, bad = {}, 0;
for _, case in ipairs(cases) do
    tracker = require('core.tracker').new();
    rows_of(10, { cast(case[2]) });
    local got = rows_of(10 + case[4], { cast(case[3]) });
    if got ~= case[5] then bad = bad + 1; end
    log[#log + 1] = ('%s %d s on: %s, Phoenix %s'):format(case[1], case[4], got, case[5]);
end
assert(bad == 0, 'A Diaga goes on as Phoenix puts it on: ' .. table.concat(log, ' | '));
return 'Diaga II and III go on by their tiers';
