-- A support job change in the Mog House drops every ability cooldown but the job special, as a main job change does
-- (Phoenix src/map/packets/c2s/0x100_myroom_job.cpp:160, src/map/char_recast_container.cpp:137-145), and the new list
-- (0x119, 0x100_myroom_job.cpp:203) comes with the new job. The dropped rows go at once. The job special and the
-- spells keep counting, so they keep their start, total and instance. A support job that reads 0 for a while, as
-- under a battlefield's restriction, changes nothing.
local slots, spells = {}, {};
local t = 100;
local manager = {
    GetSpellTimer = function(_, spell) local e = spells[spell]; return e and math.max(0, math.ceil((e - t) * 60)) or 0; end,
    GetAbilityTimerId = function(_, slot) return slots[slot] and slots[slot].id or 0; end,
    GetAbilityTimer = function(_, slot) local e = slots[slot]; return e and math.max(0, math.ceil((e.ends - t) * 60)) or 0; end,
};
local party = { GetMemberServerId = function() return 1001; end, GetMemberZone = function() return 243; end };
local player = { GetMainJob = function() return 1; end, GetIsZoning = function() return false; end };
local memory = { GetRecast = function() return manager; end, GetInventory = function() return nil; end,
    GetParty = function() return party; end, GetPlayer = function() return player; end };
AshitaCore.GetMemoryManager = function() return memory; end;
-- Mighty Strikes is the job special on timer 0, Berserk ability 16 on timer 1 and Provoke ability 35 on timer 5.
local abilities = { [512] = { Name = { [1] = 'Mighty Strikes' }, RecastTimerId = 0, Id = 512, Type = 1 },
    [528] = { Name = { [1] = 'Berserk' }, RecastTimerId = 1, Id = 528, Type = 1 },
    [547] = { Name = { [1] = 'Provoke' }, RecastTimerId = 5, Id = 547, Type = 1 } };
AshitaCore.GetResourceManager = function() return {
    GetSpellById = function(_, spell) return spell == 57 and { Name = { [1] = 'Haste' } } or nil; end,
    GetAbilityById = function(_, ability) return abilities[ability]; end,
    GetAbilityByTimerId = function() return nil; end }; end;

local model = require('core.recasts').new();
-- WAR/NIN.
local snapshot = { valid = true, id = 1001, zone = 243, job = 1, sub_job = 13, name = 'Aster' };
local options = { items = false };
local function sample(dt) t = t + (dt or 0.1); model:update(snapshot, t, options); return model:view(t); end
local function row(kind, id)
    for _, value in ipairs(model:view(t).rows) do if value.kind == kind and value.recast_id == id then return value; end end
end
local function same(kind, id, was)
    local now = row(kind, id);
    return now ~= nil and now.total == was.total and now.start == was.start and now.instance == was.instance;
end

-- Mighty Strikes, Berserk, Provoke and Haste used while sampling, so each knows its whole length.
sample(); sample();
model:used(16, t + 0.05); model:used(35, t + 0.05);
slots[0], slots[1], slots[2] = { id = 0, ends = t + 0.1 + 900 }, { id = 1, ends = t + 0.1 + 300 }, { id = 5, ends = t + 0.1 + 30 };
spells[57] = t + 0.1 + 180;
sample();
assert(#model:drain_events() == 4 and row('ability', 0).total and row('ability', 1).total and row('ability', 5).total
    and row('spell', 57).total, 'Fixture: four cooldowns start, each with its whole length.');
for _ = 1, 20 do sample(); end
local special, haste = row('ability', 0), row('spell', 57);
special = { total = special.total, start = special.start, instance = special.instance };
haste = { total = haste.total, start = haste.start, instance = haste.instance };

-- NIN to SAM: the new list has only the job special.
snapshot = { valid = true, id = 1001, zone = 243, job = 1, sub_job = 12, name = 'Aster' };
slots[1], slots[2] = nil, nil;
sample();
assert(not row('ability', 1) and not row('ability', 5), 'After a support job change the abilities it dropped go at once.');
assert(#model:drain_events() == 0, 'The change says nothing.');
assert(same('ability', 0, special) and same('spell', 57, haste), 'The job special and the spells keep their start, total and instance.');

-- A battlefield's restriction reads the support job as 0, then it comes back: nothing changes, and a use just made
-- is still waited for.
snapshot = { valid = true, id = 1001, zone = 243, job = 1, sub_job = 0, name = 'Aster' };
model:used(16, t + 0.05);
sample();
snapshot = { valid = true, id = 1001, zone = 243, job = 1, sub_job = 12, name = 'Aster' };
sample();
assert(same('ability', 0, special) and same('spell', 57, haste) and model.uses[16] and #model:drain_events() == 0,
    'A support job read as 0 for a while, and back, changes nothing.');
return 'A support job change drops the abilities it drops, and keeps the rest';
