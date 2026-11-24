-- A recast sample reads the timer of each spell on data/actions.lua's list the client names, here all of them, about
-- ten times a second. With everything ready it reuses the table it read into two samples before instead of building a
-- new one: a few KB a sample, not about 50.
-- Each sample still publishes read counts of its own.
local manager = { GetSpellTimer = function() return 0; end, GetAbilityTimerId = function() return 0; end,
    GetAbilityTimer = function() return 0; end };
local memory = { GetRecast = function() return manager; end, GetInventory = function() return nil; end };
AshitaCore.GetMemoryManager = function() return memory; end;
local named = { Name = { 'A spell' } };
AshitaCore.GetResourceManager = function() return { GetSpellById = function() return named; end,
    GetAbilityById = function() return nil; end, GetAbilityByTimerId = function() return nil; end }; end;
local model = require('core.recasts').new();
local snapshot = { valid = true, id = 1001, zone = 230, job = 3, name = 'Aster' };
local now = 100;
local function sample() now = now + 0.1; model:update(snapshot, now, { spells = true, abilities = true, items = false }); end;
for _ = 1, 4 do sample(); end;
local reads = model.capabilities.reads;
sample();
assert(model.capabilities.reads ~= reads and model.capabilities.reads.GetSpellTimer == #require('data.actions').spells,
    'Each sample publishes its own read counts.');
collectgarbage('collect'); collectgarbage('collect');
collectgarbage('stop');
local before = collectgarbage('count');
for _ = 1, 20 do sample(); end;
local each = (collectgarbage('count') - before) / 20;
collectgarbage('restart');
assert(each < 8, ('An idle recast sample makes %.1f KB of garbage, at most 8 expected'):format(each));
