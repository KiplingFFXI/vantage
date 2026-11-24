-- vantage.lua samples your recasts ten times a second (core/recasts.lua update), and the client counts a running
-- timer down at every sample. A sample made a new reading for each running timer and new read counts, and once a second
-- it made again what the abilities you know give each timer: with twenty spells and four abilities running, about 6 KB
-- a sample. A sample now refills the readings and counts of two samples before, and keeps what the abilities you know
-- gave while the answers are the same, so it makes nothing while the same timers run. The last sample's readings and
-- counts stay as they were while a sample fills, as it compares with them.
local spells, slots = {}, {};
-- Twenty spells on data/actions.lua's list, as a spell off it you don't know isn't read.
local RUNNING = { 1, 2, 3, 4, 5, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 23 };
local manager = {
    GetSpellTimer = function(_, id) return spells[id] or 0; end,
    GetAbilityTimerId = function(_, slot) return slots[slot] and slots[slot].id or 0; end,
    GetAbilityTimer = function(_, slot) return slots[slot] and slots[slot].timer or 0; end,
};
-- You know every ability, unless known says otherwise. asked counts the questions. Of the spells off the list, you know
-- only spell 6, which isn't running but is read.
local known, asked = {}, 0;
local player = { HasAbilityData = function() return true; end, GetMainJob = function() return 4; end, GetSubJob = function() return 5; end,
    GetMainJobLevel = function() return 75; end, GetSubJobLevel = function() return 37; end,
    HasAbility = function(_, id) asked = asked + 1; return known[id] ~= false; end, HasPetCommand = function() return false; end,
    HasSpell = function(_, id) return id == 6; end };
local memory = { GetRecast = function() return manager; end, GetInventory = function() return nil; end, GetPlayer = function() return player; end };
local spell_names, ability_names = {}, {};
for id = 1, 40 do spell_names[id] = { Name = { 'Spell ' .. id }, ListIconNQ = id, ListIconHQ = id }; end;
for id = 1, 8 do ability_names[512 + id] = { Name = { 'Ability ' .. id }, RecastTimerId = id, ListIconId = id, Element = 1, Id = 512 + id }; end;
-- Timer 1 is shared by two abilities.
ability_names[521] = { Name = { 'Other 1' }, RecastTimerId = 1, ListIconId = 21, Element = 1, Id = 521 };
-- The client hands out the same managers each time, as the game does.
local resources = { GetSpellById = function(_, id) return spell_names[id]; end, GetAbilityById = function(_, id) return ability_names[id]; end,
    GetAbilityByTimerId = function() return nil; end };
AshitaCore.GetMemoryManager = function() return memory; end;
AshitaCore.GetResourceManager = function() return resources; end;
local model = require('core.recasts').new();
local snapshot = { valid = true, id = 1001, zone = 230, job = 4, name = 'Aster' };
local now = 100;
local options = { spells = true, abilities = true, items = false };
model:update(snapshot, now, options);
-- Twenty spells and four abilities start, and count down a tick each 1/60 s.
for _, id in ipairs(RUNNING) do spells[id] = 60 * 600; end;
for slot = 1, 4 do slots[slot] = { id = slot, timer = 60 * 900 }; end;
local function sample()
    now = now + 0.1;
    for _, id in ipairs(RUNNING) do spells[id] = spells[id] - 6; end;
    for slot = 1, 4 do slots[slot].timer = slots[slot].timer - 6; end;
    model:update(snapshot, now, options);
end
jit.off(); jit.flush();
for _ = 1, 50 do sample(); end;
assert(#model:view(now).rows == 24 and #model:drain_events() == 20, 'Fixture: 24 recasts run, the 20 spells started once each.');
collectgarbage('collect'); collectgarbage('collect');
collectgarbage('stop');
local before = collectgarbage('count');
for _ = 1, 100 do sample(); end;
local each = (collectgarbage('count') - before) / 100;
collectgarbage('restart');
jit.on();
assert(each < 0.05, ('A recast sample with 24 running timers makes %.2f KB, nothing expected'):format(each));
assert(#model:drain_events() == 0, 'Ten seconds of countdown start nothing.');
-- Every five seconds the spells off the list you know are asked about again, and the list a sample reads is refilled
-- then, not made again.
local spell_ids = model.spell_ids;
for _ = 1, 60 do sample(); end;
assert(spell_ids and model.spell_ids == spell_ids, 'Asked again, the spells to read are refilled in place.');

-- Each sample has counts of its own: the last sample's stay as they were, and each counts only its own reads.
local last = model.capabilities;
local spell_reads = last.reads.GetSpellTimer;
sample();
local current = model.capabilities;
assert(current ~= last and current.reads ~= last.reads, 'Each sample has its own counts.');
assert(last.reads.GetSpellTimer == spell_reads and current.reads.GetSpellTimer == 30 and current.reads.GetAbilityTimer == 31,
    'Each sample counts its own reads: ' .. tostring(current.reads.GetSpellTimer));
-- What one sample read and another didn't isn't left over when its table comes back.
assert(current.ability_complete == true, 'Fixture: abilities are read.');
options.abilities = false;
sample();
assert(model.capabilities == last and model.capabilities.ability_complete == nil and model.capabilities.reads.GetAbilityTimer == nil
    and model.capabilities.reads.GetSpellTimer == 30, 'A sample that reads no abilities says nothing of them.');
options.abilities = true;
sample(); sample();
assert(model.capabilities.ability_complete == true and model.capabilities.reads.GetAbilityTimer == 31, 'Abilities are read again.');

-- A spell cast again rises from the last sample's reading, and a recast that ends falls to zero from it: each sample
-- compares with the last one's readings.
local function row(id) for _, value in ipairs(model:view(now).rows) do if value.recast_id == id and value.kind == 'spell' then return value; end; end; end;
local instance = row(1).instance;
spells[1] = 60 * 600;
sample();
local events = model:drain_events();
assert(#events == 1 and events[1].kind == 'started' and events[1].recast_id == 1 and row(1).instance ~= instance,
    'A spell cast again starts over: ' .. #events .. ' events.');
spells[2] = 6;
sample();
events = model:drain_events();
assert(#events == 1 and events[1].kind == 'ready' and events[1].recast_id == 2 and not row(2), 'A recast that ends is ready.');
spells[2] = 60 * 30;
sample(); sample();
events = model:drain_events();
assert(#events == 1 and events[1].kind == 'started' and events[1].recast_id == 2 and row(2).total > 29.8,
    'Cast again, it starts once: ' .. #events .. ' events.');
for _ = 1, 20 do sample(); end;
assert(#model:drain_events() == 0 and math.abs(row(2).remaining - (row(2).deadline - now)) < 1e-9, 'Then it counts down.');

-- Once a second the abilities you know are asked again. The same answers keep what they made, so a row keeps its
-- icons. A changed answer changes the row at the next asking.
local function ability(id) for _, value in ipairs(model:view(now).rows) do if value.recast_id == id and value.kind == 'ability' then return value; end; end; end;
local icons, questions = ability(1).action_icons, asked;
assert(ability(1).icon_source == 'known_abilities' and #ability(1).ability_ids == 2 and ability(1).name == 'Ability 1 / Other 1 (shared)',
    'Fixture: you know both abilities of timer 1: ' .. ability(1).name);
for _ = 1, 12 do sample(); end;
assert(asked >= questions + 5, 'They are asked again: ' .. (asked - questions) .. ' questions.');
assert(ability(1).action_icons == icons and #ability(1).ability_ids == 2, 'The same answers keep what they made.');
known[521] = false;
for _ = 1, 12 do sample(); end;
assert(ability(1).ability_id == 513 and #ability(1).action_icons == 1 and ability(1).name == 'Ability 1 (shared)',
    'An ability you no longer know leaves the row: ' .. ability(1).name);
known[513] = false;
for _ = 1, 12 do sample(); end;
assert(ability(1).icon_source == 'resource_aliases' and ability(1).ability_id == nil, 'With neither known, the row has the timer\'s own.');
known[513], known[521] = nil, nil;
for _ = 1, 12 do sample(); end;
assert(ability(1).icon_source == 'known_abilities' and #ability(1).ability_ids == 2, 'Known again, they are back.');
assert(#model:drain_events() == 0, 'None of it starts a recast.');

-- With recasts off, or no character to read, a sample resets once and then makes nothing. Read again, the rows come
-- back as they were.
local function idle(count, step)
    jit.off(); jit.flush();
    step();
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    local start = collectgarbage('count');
    for _ = 1, count do step(); end;
    local made = (collectgarbage('count') - start) / count;
    collectgarbage('restart');
    jit.on();
    return made;
end
-- The client counts the timers down all the while.
local function countdown()
    now = now + 0.1;
    for _, id in ipairs(RUNNING) do spells[id] = math.max(0, spells[id] - 6); end;
    for slot = 1, 4 do slots[slot].timer = math.max(0, slots[slot].timer - 6); end;
end
local off = { enabled = false };
each = idle(100, function() countdown(); model:update(snapshot, now, off); end);
assert(each < 0.002, ('A sample with recasts off makes %.4f KB, nothing expected'):format(each));
assert(model.valid == false and #model:view(now).rows == 0 and next(model.capabilities) == nil, 'Off, there are no rows.');
local away = { valid = false };
each = idle(100, function() countdown(); model:update(away, now, options); end);
assert(each < 0.002, ('A sample with no character makes %.4f KB, nothing expected'):format(each));
sample();
assert(model.valid == true and #model:view(now).rows == 24 and ability(1) and row(1).total and row(2).total,
    'Read again, the 24 recasts are back, the spells with their totals: ' .. #model:view(now).rows);

-- An equipped enchanted item with charges is read at each sample too, into a kept reading as the timers are. The item
-- data library stands in with one table, so only Vantage's part is counted. A drain with nothing new makes nothing.
local item_resource = { Name = { 'Enchanted ring' }, Type = 5, MaxCharges = 10, CastDelay = 30, RecastDelay = 1800 };
local ring = { Id = 15793, Index = 2050, Extra = string.char(1) .. string.rep('\0', 11) };
local worn, unworn, info = { Index = 2050 }, { Index = 0 }, { use_delay = 30, remaining_charges = 7 };
local inventory = { GetEquippedItem = function(_, slot) return slot == 13 and worn or unworn; end,
    GetContainerItem = function(_, container, index) return container * 256 + index == ring.Index and ring or nil; end };
memory.GetInventory = function() return inventory; end;
resources.GetItemById = function(_, id) return id == ring.Id and item_resource or nil; end;
package.preload['ffxi.itemdata'] = function() return { parse_timer_info = function() return info; end }; end;
options.items = true;
for _, id in ipairs(RUNNING) do spells[id] = 60 * 600; end;
for slot = 1, 4 do slots[slot].timer = 60 * 900; end;
local function steady(count, step)
    jit.off(); jit.flush();
    for _ = 1, 50 do step(); end;
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    for _ = 1, 6 do step(); end;
    local start = collectgarbage('count');
    for _ = 1, count do step(); end;
    local made = (collectgarbage('count') - start) / count;
    collectgarbage('restart');
    jit.on();
    return made;
end
each = steady(100, sample);
local function item() for _, value in ipairs(model:view(now).rows) do if value.kind == 'item' then return value; end; end; end;
assert(item() and item().charges == 7 and item().inventory_index == 2050, 'Fixture: the ring is read.');
assert(each < 0.05, ('A recast sample with 24 running timers and a ring makes %.2f KB, nothing expected'):format(each));
model:drain_events();
each = steady(100, function() model:drain_events(); end);
assert(each < 0.002, ('A drain with nothing new makes %.4f KB, nothing expected'):format(each));
-- The kept reading takes what each sample reads.
info.use_delay, info.remaining_charges = 60, 6;
sample();
events = model:drain_events();
assert(#events == 1 and events[1].kind == 'started' and item().charges == 6 and math.abs(item().remaining - 60) < 1e-9,
    'The ring used again starts over with its charges: ' .. #events .. ' events.');
-- Moved to another place in the bag, its key changes, and the reading kept for the old one goes.
ring.Index, worn.Index = 2051, 2051;
sample(); sample();
assert(model.rows['item:15793:2051'] and model.rows['item:15793:2051'].inventory_index == 2051, 'Fixture: the ring is read at its new place.');
assert(model.spare_pool['item:15793:2050'] == nil and model.previous_pool['item:15793:2050'] == nil,
    'Neither sample keeps a reading for the ring\'s old place.');
return 'A recast sample refills its readings and counts';
