-- At a zone-in Phoenix lists your abilities on cooldown (0x119) only after the rest of its answer to the client's first
-- packets, inventory and all, so the zone's list can come one sample after the first read or seconds later. A cooldown
-- Vantage was following still keeps its start, total and instance when the list comes, and a ready pulse that played
-- for it doesn't play again. The job special's slot reads 0 until the list comes, and the list doesn't make it a new
-- use. A pause or another reset before the list keeps them waiting. Another main job's cooldowns never come back, and
-- the kept rows wait a minute at most.
local slots, spells, zone, zoning, job, id, t = {}, {}, 230, false, 1, 1001, 100;
local manager = {
    GetSpellTimer = function(_, spell)
        local ends = spells[spell];
        return ends and math.max(0, math.ceil((ends - t) * 60)) or 0;
    end,
    GetAbilityTimerId = function(_, slot) return slots[slot] and slots[slot].id or 0; end,
    GetAbilityTimer = function(_, slot)
        local entry = slots[slot];
        return entry and math.max(0, math.ceil((entry.ends - t) * 60)) or 0;
    end,
};
local party = { GetMemberServerId = function() return id; end, GetMemberZone = function() return zone; end };
local player = { GetMainJob = function() return job; end, GetIsZoning = function() return zoning; end };
local memory = { GetRecast = function() return manager; end, GetInventory = function() return nil; end,
    GetParty = function() return party; end, GetPlayer = function() return player; end };
AshitaCore.GetMemoryManager = function() return memory; end;
-- Berserk is ability 16 (resource 528) on timer 1, and Mighty Strikes is the job special on timer 0.
local abilities = { [528] = { Name = { [1] = 'Berserk' }, RecastTimerId = 1, Id = 528, Type = 1 },
    [512] = { Name = { [1] = 'Mighty Strikes' }, RecastTimerId = 0, Id = 512, Type = 1 } };
local resources = { GetSpellById = function(_, spell) return spell == 57 and { Name = { [1] = 'Haste' } } or nil; end,
    GetAbilityById = function(_, ability) return abilities[ability]; end,
    GetAbilityByTimerId = function() return nil; end, GetItemById = function() return nil; end };
AshitaCore.GetResourceManager = function() return resources; end;

local recasts = require('core.recasts');
local ready_pulse = require('core.ready_pulse');
local model, snapshot, watch, settings, pulses, started;
local OPTIONS = { items = false };

local function row_of(timer)
    for _, row in ipairs(model:view(t).rows) do if row.kind == 'ability' and row.recast_id == timer then return row; end end
end
local function row_of_spell(spell)
    for _, row in ipairs(model:view(t).rows) do if row.kind == 'spell' and row.recast_id == spell then return row; end end
end
-- One refresh as vantage.lua runs it: a sample, then the rows and events to the ready pulse.
local function tick(dt, snap)
    t = t + dt;
    model:update(snap, t, OPTIONS);
    local view = model:view(t);
    local events = model:drain_events();
    for _, event in ipairs(events) do if event.kind == 'started' then started = started + 1; end end
    for _, entry in ipairs(watch:update(view.rows, events, settings, t)) do
        if entry.started == t and entry.recast_id == 1 then pulses = pulses + 1; end
    end
end
local function sample(dt) tick(dt or 1, snapshot); end

-- A fresh reader, then timer 1 or 0 used in front of it with its whole length read with the use.
local function start(timer, length, early)
    model, t, zone, zoning, job, id = recasts.new(), 100, 230, false, 1, 1001;
    snapshot = { valid = true, id = id, zone = zone, job = job, name = 'Aster' };
    settings = { ready_pulse = ready_pulse.tidy({ enabled = true, min_seconds = 60, early = early or 0 }) };
    watch, pulses, started, slots = ready_pulse.new(), 0, 0, {};
    sample(0.1); sample(0.1);
    if timer == 1 then model:used(16, t + 0.05); end
    slots[timer == 0 and 0 or 1] = { id = timer, ends = t + 0.1 + length };
    sample(0.1);
    local row = row_of(timer);
    assert(row and row.total and math.abs(row.total - length) < 0.1 and row.start and started == 1,
        'Fixture: the cooldown starts once with its whole length.');
    started = 0;
    return { total = row.total, start = row.start, instance = row.instance };
end

-- vantage.lua's clear_zone, about 6 s of zoning, then the new zone, whose list comes gap seconds after the first read
-- there. A gap of 0 has the list in place at the first read. A stall has the game pause that long before the list.
local function zone_change(gap, new_job, stall)
    model:reset();
    zoning = true;
    for _ = 1, 30 do tick(0.2, { valid = false }); end
    zoning, zone, job = false, zone + 1, new_job or job;
    snapshot = { valid = true, id = id, zone = zone, job = job, name = 'Aster' };
    local listed = slots;
    if gap > 0 then slots = {}; end
    sample(0.1);
    local waited = 0;
    while waited < gap do sample(0.1); waited = waited + 0.1; end
    slots = listed;
    sample(stall or 0.1);
end

local function until_ready(timer)
    local guard = 0;
    while row_of(timer) and guard < 8000 do sample(1); guard = guard + 1; end
    assert(not row_of(timer), 'Fixture: the cooldown is ready.');
end

local function kept(before, timer)
    local row = row_of(timer);
    return row ~= nil and row.total == before.total and row.start == before.start and row.instance == before.instance,
        ('total %s (was %s), start %s (was %s), instance %s (was %s)'):format(tostring(row and row.total), tostring(before.total),
        tostring(row and row.start), tostring(before.start), tostring(row and row.instance), tostring(before.instance));
end

-- Berserk (300 s), a zone change with about 50 s left, the list at the first read (control), one sample later, and
-- 1.6 s and 6.5 s later as Phoenix sends it with a few bags or full ones.
for _, gap in ipairs({ 0, 0.1, 1.6, 6.5 }) do
    local before = start(1, 300);
    for _ = 1, 250 do sample(1); end
    zone_change(gap);
    local same, what = kept(before, 1);
    assert(same and started == 0, ('Berserk is the same cooldown after a zone whose list came %.1f s after the first read: %s, %d started.'):format(
        gap, what, started));
    until_ready(1);
    assert(pulses == 1, ('Its pulse plays once at ready after a zone whose list came %.1f s late: %d pulses.'):format(gap, pulses));
end

-- Start early at 90 s: the early pulse plays, then the zone with its list a sample late, and nothing more at ready.
start(1, 300, 90);
for _ = 1, 212 do sample(1); end
assert(pulses == 1, 'Fixture: the early pulse played.');
zone_change(0.1);
until_ready(1);
assert(pulses == 1, 'An early pulse that played before the zone doesn\'t play again at ready: ' .. pulses .. ' pulses.');

-- The job special: its slot reads 0 until the list comes, and the list doesn't make it a new use.
local special = start(0, 7200);
for _ = 1, 100 do sample(1); end
zone_change(1.6);
local same, what = kept(special, 0);
assert(same and started == 0, 'The job special after a zone whose list came late is the same cooldown, not a new use: ' .. what
    .. ', ' .. started .. ' started.');

-- Another main job has other cooldowns: what was kept never comes back to it, even with the same end.
local before = start(1, 300);
for _ = 1, 100 do sample(1); end
zone_change(1.6, 2);
local row = row_of(1);
assert(row and row.total == nil and row.start == nil and row.instance ~= before.instance,
    'A cooldown kept for one main job doesn\'t come back to another.');

-- Haste comes back at the zone's first read, then a pause of over 2 s before the list resets the reader again. Berserk
-- still waits for the list, and Haste stays the same cooldown too.
before = start(1, 300);
spells[57] = t + 400;
sample(0.1);
row = row_of_spell(57);
local haste = row and { instance = row.instance, total = row.total };
assert(haste and haste.total, 'Fixture: Haste starts.');
for _ = 1, 100 do sample(1); end
started = 0;
zone_change(0.1, nil, 3);
same, what = kept(before, 1);
row = row_of_spell(57);
assert(same and started == 0 and row and row.instance == haste.instance and row.total == haste.total,
    'Berserk and Haste are the same cooldowns after a 3 s pause between the zone\'s first read and its list: ' .. what .. ', '
    .. started .. ' started.');
spells[57] = nil;

-- The kept rows wait a minute at most for their list.
before = start(1, 300);
for _ = 1, 100 do sample(1); end
zone_change(70);
row = row_of(1);
assert(row and row.total == nil and row.instance ~= before.instance, 'A list over a minute late brings a cooldown back without its total.');
return 'A zone\'s late ability list brings back the cooldowns Vantage was following';
