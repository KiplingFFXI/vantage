-- A cooldown already running when Vantage loads or you log in is a quiet baseline: no start and no total. Through a
-- zone change or a pause in sampling over 2 s it stays that one cooldown, its instance kept, so the ready pulse still
-- knows the most it saw left and whether its early pulse played. It still has no start or total.
local zone, zoning, job, id = 230, false, 3, 1001;
local ends = {};
local t = 1000;
local manager = {
    GetSpellTimer = function(_, spell) local e = ends[spell]; return e and math.max(0, math.ceil((e - t) * 60)) or 0; end,
    GetAbilityTimerId = function() return 0; end, GetAbilityTimer = function() return 0; end };
local party = { GetMemberServerId = function() return id; end, GetMemberZone = function() return zone; end };
local player = { GetMainJob = function() return job; end, GetIsZoning = function() return zoning; end };
local memory = { GetRecast = function() return manager; end, GetInventory = function() return nil; end,
    GetParty = function() return party; end, GetPlayer = function() return player; end };
AshitaCore.GetMemoryManager = function() return memory; end;
-- Spells on data/actions.lua's list, as a spell off it you don't know isn't read.
local NAMES = { [201] = 'Spell A', [205] = 'Spell B', [206] = 'Spell C', [204] = 'Spell D' };
AshitaCore.GetResourceManager = function() return {
    GetSpellById = function(_, spell) return NAMES[spell] and { Name = { [1] = NAMES[spell] } } or nil; end,
    GetAbilityById = function() return nil; end, GetAbilityByTimerId = function() return nil; end }; end;
local recasts = require('core.recasts');
local ready_pulse = require('core.ready_pulse');

local model, watch, settings, snapshot, count;
local function row(spell)
    for _, value in ipairs(model:view(t).rows) do if value.recast_id == spell then return value; end end
end
-- One refresh as vantage.lua runs it: a sample, then the rows and events to the ready pulse.
local function step(seconds)
    t = t + seconds;
    model:update(snapshot, t);
    for _, entry in ipairs(watch:update(model:view(t).rows, model:drain_events(), settings, t)) do
        if entry.started == t then count[entry.recast_id] = (count[entry.recast_id] or 0) + 1; end
    end
end
-- A load or a login with this timer already running.
local function session(early, spell, left)
    t, zone, zoning, job, id = 1000, 230, false, 3, 1001;
    snapshot = { valid = true, id = id, zone = zone, job = job, name = 'Aster' };
    ends = { [spell] = t + left };
    model, watch, count = recasts.new(), ready_pulse.new(), {};
    settings = { ready_pulse = ready_pulse.tidy({ enabled = true, min_seconds = 60, early = early }) };
    step(0.1);
    assert(row(spell) and row(spell).total == nil and row(spell).start == nil, 'Fixture: a quiet baseline row at load.');
    return row(spell).instance;
end
local function until_left(spell, left) while ends[spell] - t > left do step(0.1); end end
local function until_ready(spell) while t < ends[spell] + 2 do step(0.1); end end
-- vantage.lua's clear_zone, about 6 s of zoning, then the new zone.
local function zone_change()
    model:reset();
    zoning = true;
    for _ = 1, 60 do step(0.1); end
    zoning, zone = false, zone + 1;
    snapshot = { valid = true, id = id, zone = zone, job = job, name = 'Aster' };
    step(0.1);
end

-- A zone change with 50 s left, under the 60 s minimum: the pulse still plays at ready, as with no zone change.
local before = session(0, 201, 300);
until_left(201, 50);
zone_change();
local after = row(201);
assert(after and after.instance == before and after.total == nil and after.start == nil,
    ('A quiet baseline is the same cooldown after a zone change: instance %s (was %s), total %s, start %s.'):format(
    tostring(after and after.instance), tostring(before), tostring(after and after.total), tostring(after and after.start)));
until_ready(201);
assert(count[201] == 1, 'Its pulse plays at ready: ' .. tostring(count[201]) .. ' pulses.');

-- Start early at 90 s, above the minimum: the early pulse, then a zone change at 80 s left, and nothing more at ready.
session(90, 205, 600);
until_left(205, 80);
assert(count[205] == 1, 'Fixture: the early pulse played.');
zone_change();
until_ready(205);
assert(count[205] == 1, 'An early pulse that played before the zone doesn\'t play again at ready: ' .. count[205] .. ' pulses.');

-- A pause in sampling over 2 s with 50 s left.
before = session(0, 206, 300);
until_left(206, 50);
t = t + 3;
step(0.1);
assert(row(206) and row(206).instance == before and row(206).total == nil, 'A quiet baseline is the same cooldown after a pause.');
until_ready(206);
assert(count[206] == 1, 'Its pulse plays at ready after the pause: ' .. tostring(count[206]) .. ' pulses.');

-- Another job has other cooldowns.
before = session(0, 204, 300);
until_left(204, 200);
job = 4;
zone_change();
assert(row(204) and row(204).instance ~= before, 'A quiet baseline doesn\'t come back to another job.');
return 'A quiet baseline keeps its instance through a zone change or a pause';
