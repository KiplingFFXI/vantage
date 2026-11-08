-- The client keeps counting a cooldown through a zone change or a pause in sampling (no Present for over 2 s). The
-- row that comes back keeps its start and total when its timer still ends when it did, for the same character and
-- job, so its bar keeps its scale and percent rules can still fire, and its instance, so a ready pulse that played for it
-- doesn't play again. The first sample after stays quiet. Anything else starts without a total.
local spells, zone, zoning, job, id = {}, 230, false, 3, 1001;
local manager = { GetSpellTimer = function(_, spell) return spells[spell] or 0; end,
    GetAbilityTimerId = function() return 0; end, GetAbilityTimer = function() return 0; end };
local party = { GetMemberServerId = function() return id; end, GetMemberZone = function() return zone; end };
local player = { GetMainJob = function() return job; end, GetIsZoning = function() return zoning; end };
local memory = { GetRecast = function() return manager; end, GetInventory = function() return nil; end,
    GetParty = function() return party; end, GetPlayer = function() return player; end };
AshitaCore.GetMemoryManager = function() return memory; end;
AshitaCore.GetResourceManager = function() return { GetSpellById = function(_, spell) return spell == 57 and { Name = { [1] = 'Haste' } } or nil; end,
    GetAbilityById = function() return nil; end, GetAbilityByTimerId = function() return nil; end }; end;
local recasts = require('core.recasts');
local model, t, snapshot;
local function haste() for _, row in ipairs(model:view(t).rows) do if row.recast_id == 57 then return row; end; end; end;
local function sample(seconds)
    t = t + (seconds or 0.1);
    if spells[57] then spells[57] = math.max(0, spells[57] - math.floor((seconds or 0.1) * 60 + 0.5)); end;
    model:update(snapshot, t);
end;
-- Haste (a 20 s recast) cast while sampling, then 3 s of samples.
local function cast()
    model, t, zone, zoning, job, id = recasts.new(), 100, 230, false, 3, 1001;
    snapshot = { valid = true, id = id, zone = zone, job = job, name = 'Aster' };
    spells[57] = 0; model:update(snapshot, t);
    t = t + 0.1; spells[57] = 1200; model:update(snapshot, t);
    for _ = 1, 30 do sample(); end;
    assert(haste().total == 20 and #model:drain_events() == 1, 'Fixture: Haste starts once with its 20 s total.');
    return haste();
end;
local function zone_change()
    -- vantage.lua's clear_zone, about 6 s of zoning, then the new zone.
    model:reset();
    zoning = true;
    for _ = 1, 60 do sample(); end;
    zoning, zone = false, 231;
    snapshot = { valid = true, id = id, zone = zone, job = job, name = 'Aster' };
end;

local first = cast();
local start = first.start;
sample(2.5);
assert(haste().total == 20 and haste().start == start and haste().instance == first.instance and math.abs(haste().remaining - 14.5) < 0.01,
    'A 2.5 s pause keeps the running recast total: ' .. tostring(haste().total));
assert(#model:drain_events() == 0, 'The sample after a pause is quiet.');

first = cast();
start = first.start;
zone_change();
sample();
assert(haste().total == 20 and haste().start == start and haste().instance == first.instance and math.abs(haste().remaining - 10.9) < 0.01,
    'A zone change keeps the running recast total: ' .. tostring(haste().total));
assert(#model:drain_events() == 0, 'The sample after a zone change is quiet.');
for _ = 1, 200 do sample(); end;
local events = model:drain_events();
assert(#events == 1 and events[1].kind == 'ready', 'It still reports ready once at zero.');

-- Used again during the pause: a new cooldown that ends later, so its total is unknown.
cast();
spells[57] = 0; t = t + 2.5; spells[57] = 1200; model:update(snapshot, t);
assert(haste().total == nil and haste().start == nil, 'A recast that started during the pause has no total.');
-- Another job or another character has other cooldowns.
cast();
job = 4; zone_change(); sample();
assert(haste().total == nil, 'A job change drops the totals.');
cast();
id = 1002; zone_change(); sample();
assert(haste().total == nil, 'A character change drops the totals.');
-- A clock that went back makes the old end times meaningless, even one that happens to agree.
cast();
model:reset(); t = t - 5; spells[57] = spells[57] + 300; model:update(snapshot, t);
assert(haste().total == nil, 'Time that went back drops the totals.');

-- An early warning the ready pulse played before a zone change doesn't play again after it, nor at ready: the row that
-- comes back is the same cooldown.
local ready_pulse = require('core.ready_pulse');
local settings = { ready_pulse = ready_pulse.tidy({ enabled = true, min_seconds = 0, early = 15 }) };
local watch, pulses = ready_pulse.new(), 0;
local function watched()
    sample();
    for _, entry in ipairs(watch:update(model:view(t).rows, model:drain_events(), settings, t)) do
        if entry.started == t then pulses = pulses + 1; end;
    end;
end;
first = cast();
watch:update(model:view(t).rows, {}, settings, t);
for _ = 1, 25 do watched(); end;
assert(pulses == 1, 'The early warning plays at 15 s left.');
zone_change();
watched();
assert(haste().instance == first.instance and haste().total == 20 and haste().remaining < 15, 'The same cooldown came back.');
for _ = 1, 100 do watched(); end;
assert(not haste() and pulses == 1, 'Its early warning played once: not again after the zone change, nor at ready.');
