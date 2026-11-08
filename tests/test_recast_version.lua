-- The recast version (core/recasts.lua) moves only when a row comes, goes or takes another name, as the settings window
-- builds its list of recasts again each time it moves. A sample that only counts down leaves it as it is.
local spells, abilities, known, ready, unreadable = {}, {}, {}, false, false;
local manager = {
    GetSpellTimer = function(_, id) if unreadable then error('unreadable'); end; return spells[id] or 0; end,
    GetAbilityTimerId = function(_, slot) return abilities[slot] and abilities[slot].id or 0; end,
    GetAbilityTimer = function(_, slot) return abilities[slot] and abilities[slot].timer or 0; end,
};
local player = {
    GetMainJob = function() return 1; end, GetSubJob = function() return 2; end,
    GetMainJobLevel = function() return 75; end, GetSubJobLevel = function() return 37; end,
    HasAbilityData = function() return ready; end, HasAbility = function(_, id) return known[id] == true; end,
};
local memory = { GetRecast = function() return manager; end, GetPlayer = function() return player; end };
AshitaCore.GetMemoryManager = function() return memory; end;
local resources = {
    GetSpellById = function(_, id) return id == 57 and { Name = { [1] = 'Haste' } } or nil; end,
    GetAbilityById = function(_, id)
        if id == 547 then return { Name = { [1] = 'Provoke' }, RecastTimerId = 5, ListIconId = 22, Element = 0 }; end;
        if id == 600 then return { Name = { [1] = 'Alternate action' }, RecastTimerId = 5, ListIconId = 23, Element = 1 }; end;
    end,
    GetAbilityByTimerId = function() return nil; end,
};
AshitaCore.GetResourceManager = function() return resources; end;
local model = require('core.recasts').new();
local snapshot = { valid = true, id = 1001, zone = 230, job = 1, name = 'Aster' };
local now = 100;
-- One sample, a tenth of a second on, with each running timer that much lower.
local function sample()
    now = now + 0.1;
    if spells[57] and spells[57] > 0 then spells[57] = spells[57] - 6; end;
    if abilities[0] and abilities[0].timer > 0 then abilities[0].timer = abilities[0].timer - 6; end;
    model:update(snapshot, now, { items = false });
    model:drain_events();
    return model.version;
end;
local function row(kind, id)
    for _, value in ipairs(model:view(now).rows) do if value.kind == kind and value.recast_id == id then return value; end; end;
end;

spells[57], abilities[0] = 1200, { id = 5, timer = 1800 };
local version = model.version;
assert(sample() == version + 1 and row('spell', 57) and row('ability', 5), 'Rows that came move it once.');
version = model.version;
for _ = 1, 20 do sample(); end;
assert(model.version == version and row('spell', 57).remaining < 19, 'Samples that only count down leave it.');
-- The known-action data names the shared timer by the one action you have.
local name = row('ability', 5).name;
ready, known[547] = true, true;
assert(sample() == version + 1 and row('ability', 5).name ~= name, 'A row that took another name moves it.');
version = model.version;
assert(sample() == version, 'The same name again leaves it.');
spells[57] = 0;
assert(sample() == version + 1 and not row('spell', 57), 'A row that went at ready moves it.');
version = model.version;
spells[57] = 1200;
assert(sample() == version + 1 and row('spell', 57), 'A new cooldown moves it.');
version = model.version;
-- A timer that can't be read keeps its row a while, then lets it go.
unreadable = true;
for _ = 1, 100 do sample(); end;
assert(model.version == version and row('spell', 57) and row('spell', 57).status == 'unknown', 'An unreadable timer keeps its row a while.');
for _ = 1, 10 do sample(); end;
assert(model.version == version + 1 and not row('spell', 57), 'Its row going moves it.');
unreadable = false;
-- A reset moves it only when it drops rows.
version = model.version;
model:reset();
assert(model.version == version + 1, 'A reset that dropped rows moves it.');
model:reset();
assert(model.version == version + 1, 'A reset with no rows leaves it.');
return 'The recast version moves when a row comes, goes or takes another name';
