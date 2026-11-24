-- Item recasts with Ashita's own item data library (libs/ffxi/itemdata.lua and bitreader.lua, as installed). Its answer
-- for a worn item comes from the item's extra bytes and the client's game time, which its game_time_diff reads in whole
-- seconds through the client's game time function, the one core/clock.lua finds. Both stand in here with one whole
-- second. Each reading must match the library's own answer at every sample, through an equip, a use, a bag move, a swap
-- to another of the same item and the charges running out. A ready item doesn't ask the library at all, a counting one
-- once a second, so neither makes the library's garbage at every sample.
package.loaded.common, package.preload.common = nil, nil;
require('common');
local second = 800000000;
package.preload['ffxi.time'] = function()
    return { game_time_diff = function(value) if value > second then return math.min(value - second - 1, 0x7FFFFFFF); end return 0; end };
end;
package.loaded['core.clock'] = { available = function() return true; end, get_game_time_raw = function() return second; end };
local itemdata = require('ffxi.itemdata');
local real_parse = itemdata.parse_timer_info;
local parses = 0;
itemdata.parse_timer_info = function(...) parses = parses + 1; return real_parse(...); end;

local function u32(value) return string.char(value % 256, math.floor(value / 256) % 256, math.floor(value / 65536) % 256, math.floor(value / 16777216) % 256); end
-- Enchanted (1), the charges left, flags, then when it can next be used and when its equip delay ends.
local function extra(charges, next_use, equip_end) return string.char(1, charges, 0, 0) .. u32(next_use) .. u32(equip_end) .. string.rep('\0', 16); end
local resource = { Name = { 'Enchanted ring' }, Type = 5, MaxCharges = 10, CastDelay = 5, RecastDelay = 1800, CastTime = 0 };
local ring = { Id = 15793, Index = 2050, Extra = extra(7, second - 4000, 0) };
local other = { Id = 15793, Index = 2052, Extra = extra(3, second - 4000, second - 4000) };
local bag = { [2050] = ring, [2052] = other };
local worn = { Index = 0 };
local unworn = { Index = 0 };
local inventory = { GetEquippedItem = function(_, slot) return slot == 13 and worn or unworn; end,
    GetContainerItem = function(_, container, index) return bag[container * 256 + index]; end };
local manager = { GetSpellTimer = function() return 0; end, GetAbilityTimerId = function() return 0; end, GetAbilityTimer = function() return 0; end };
local player = { GetMainJob = function() return 4; end };
local memory = { GetRecast = function() return manager; end, GetInventory = function() return inventory; end, GetPlayer = function() return player; end };
local resources = { GetSpellById = function() return nil; end, GetAbilityById = function() return nil; end,
    GetAbilityByTimerId = function() return nil; end, GetItemById = function(_, id) return id == ring.Id and resource or nil; end };
AshitaCore.GetMemoryManager = function() return memory; end;
AshitaCore.GetResourceManager = function() return resources; end;

local model = require('core.recasts').new();
local snapshot = { valid = true, id = 1001, zone = 230, job = 4, name = 'Aster' };
local options = { spells = false, abilities = false, items = true };
local now, samples = 100, 0;
-- A sample each 0.1 s. The game second turns at its own moment, every tenth sample.
local function sample()
    now, samples = now + 0.1, samples + 1;
    if samples % 10 == 3 then second = second + 1; end
    model:update(snapshot, now, options);
    model:drain_events();
end

-- What the library says for the worn item right now, as the reader keeps it: seconds and charges, or nothing.
local function wanted()
    local item = bag[worn.Index];
    if not item then return nil; end
    local info = real_parse(item, resource, true);
    local seconds, charges = info.use_delay, info.remaining_charges;
    if type(seconds) == 'number' and seconds == seconds and type(charges) == 'number' and charges >= 1 and charges <= 255 then
        return math.max(0, seconds), charges, 'item:' .. item.Id .. ':' .. item.Index;
    end
end
local compared, readings = 0, {};
local function run(count)
    for _ = 1, count do
        sample();
        local seconds, charges, key = wanted();
        local held;
        for name, input in pairs(model.previous) do
            if input.kind == 'item' then
                assert(name == key and not held, ('Sample %d: the reader has %s, the library %s.'):format(samples, name, tostring(key)));
                held = input;
            end
        end
        assert((held == nil) == (seconds == nil) and (not held or held.seconds == seconds and held.charges == charges),
            ('Sample %d: the reader has %s s with %s charges, the library %s s with %s.'):format(samples, tostring(held and held.seconds),
            tostring(held and held.charges), tostring(seconds), tostring(charges)));
        if held then readings[held.seconds] = true; end
        compared = compared + 1;
    end
end

run(10);
-- Equipped: Phoenix sends the item's bytes again, its equip delay ending 5 s on (src/map/utils/charutils.cpp:3111-3119).
worn.Index, ring.Extra = 2050, extra(7, second - 4000, second + 6);
run(80);
-- Used: one charge less, the next use 30 s on, and the equip delay again (src/map/packets/s2c/0x020_item_attr.cpp:97-109).
ring.Extra = extra(6, second + 31, second + 6);
run(350);
ring.Extra = extra(5, second + 31, second + 6);
run(100);
-- Moved in the bag: its key changes, its bytes don't.
bag[2050], bag[2051], ring.Index, worn.Index = nil, ring, 2051, 2051;
run(20);
-- Swapped for another of the same ring, and back.
worn.Index = 2052;
run(20);
worn.Index = 2051;
run(20);
-- Its last charge used: no charges left, so no reading.
ring.Extra = extra(0, second + 1801, second + 6);
run(30);
worn.Index = 0;
run(20);
assert(readings[30] and readings[0] and readings[5] and compared == 650, 'Fixture: the ring counted down, went ready and was compared at each sample.');
assert(next(model.item_answers) == nil, 'Nothing is kept for an item no longer worn.');

-- What a sample costs, and how often the library runs, while the ring counts down and while it's ready.
local function measure(count, step)
    jit.off(); jit.flush();
    for _ = 1, 50 do step(); end
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    local start = collectgarbage('count');
    for _ = 1, count do step(); end
    local made = (collectgarbage('count') - start) / count;
    collectgarbage('restart');
    jit.on();
    return made;
end
ring.Extra, worn.Index = extra(5, second + 1801, second + 6), 2051;
local per_parse = measure(100, function() real_parse(ring, resource, true); end);
local running = measure(100, sample);
parses = 0;
for _ = 1, 100 do sample(); end
local running_parses = parses;
ring.Extra = extra(5, second - 10, second - 5);
local ready = measure(100, sample);
parses = 0;
for _ = 1, 100 do sample(); end
local ready_parses = parses;
assert(running_parses <= 11 and ready_parses == 0 and running < per_parse * 0.2 and ready < 0.01,
    ('In 100 samples (10 s) a counting ring asks the library %d times and a ready one %d times. A sample makes %.3f KB counting'
    .. ' and %.3f KB ready, and the library makes %.3f KB each time it runs.'):format(running_parses, ready_parses, running, ready, per_parse));
return 'Each worn item asks the library only when its bytes or the game second moved';
