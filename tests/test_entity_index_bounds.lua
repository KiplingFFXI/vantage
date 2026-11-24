-- The game's entity list has places 1 to 0x8FF. A mob's place is the low 12 bits of its id, or 0x100 under them, so
-- an id that isn't a real mob's, as /vg watch can be handed, can work out to a place past the list or to none.
-- Nothing asks the game about such a place: the unit is just not found.
local W = require('overhead_fixture');
local overhead, client = require('core.overhead'), require('core.client');
local entities = AshitaCore:GetMemoryManager():GetEntity();
local asked, lowest, highest = 0, math.huge, -math.huge;
for _, name in ipairs({ 'GetServerId', 'GetName', 'GetSpawnFlags', 'GetType', 'GetDistance', 'GetStatus', 'GetRace' }) do
    local real = entities[name];
    entities[name] = function(self, index, ...)
        asked, lowest, highest = asked + 1, math.min(lowest, index), math.max(highest, index);
        return real(self, index, ...);
    end;
end
local function reset() asked, lowest, highest = 0, math.huge, -math.huge; end
local function inside() return asked > 0 and lowest >= 1 and highest <= 0x8FF; end

-- Over heads: watched ids whose low bits are no place, past the list, or past it once 0x100 is taken off, beside a
-- real mob that still gets its block.
local settings = W.settings();
W.unit(0x100, 0x1000100, 'mob', 0, -5, { name = 'Real' });
W.unit(0x850, 0x1000950, 'mob', 0, -6, { name = 'Under' });
local snapshot = W.snapshot();
local ODD = { 0x1000000, 0x1000FFF, 0x1000900, 0x1000A00, 0x10009FF, 0x1FFFFFF, 4294967295, 0x1000950 };
settings.watch_ids = { 0x1000100 };
for index, id in ipairs(ODD) do settings.watch_ids[index + 1] = id; end
local rows = { 0x1000100 };
for index, id in ipairs(ODD) do rows[index + 1] = id; end
local view = W.view(rows);
reset();
for _ = 1, 3 do W.frame(view, settings, snapshot); end
assert(overhead.plan.valid, 'Fixture: the plan is placed: ' .. tostring(overhead.plan.hidden));
assert(inside(), 'Over heads asks the game about places 1 to 0x8FF only: ' .. lowest .. ' to ' .. highest);
assert(W.ids(overhead.plan) == '16777472 16779600', 'The real mob and the one 0x100 under its low bits still get blocks: ' .. W.ids(overhead.plan));

-- The same ids as debuffed mobs and as others, which are looked up the same way.
settings.watch_ids = {};
settings.overhead.units.other = true;
local debuffed = {};
for index, id in ipairs(ODD) do debuffed[index] = { entity_id = id, kind = 'debuff', scope = index % 2 == 0 and 'enemy' or 'other', source = 1001 }; end
reset();
for _ = 1, 3 do W.frame(W.view(debuffed), settings, snapshot); end
assert(inside(), 'So do debuffed and other units: ' .. lowest .. ' to ' .. highest);

-- The client's own lookup of a unit by id.
local probe = { GetServerId = function(_, index)
    asked, lowest, highest = asked + 1, math.min(lowest, index), math.max(highest, index);
    return index == 0x850 and 0x1000950 or 0;
end, GetSpawnFlags = function() return 0x10; end, GetName = function() return 'Under'; end };
for _, id in ipairs(ODD) do
    reset();
    local unit = client.resolve(id, nil, probe);
    assert(asked == 0 or inside(), ('Looking up %X asks about places 1 to 0x8FF only: %s to %s'):format(id, lowest, highest));
    assert(type(unit) == 'table' and unit.id == id, 'It still answers with a unit.');
    if id == 0x1000950 then assert(unit.index == 0x850 and unit.name == 'Under', 'A mob 0x100 under its low bits is still found.');
    else assert(unit.index == nil, ('%X is not found.'):format(id)); end
end
-- A place handed in from outside the list is not asked about either.
for _, index in ipairs({ 0x900, 0xFFF, 65535, 0, -1 }) do
    reset();
    local unit = client.resolve(0x1000100, index, probe);
    assert((asked == 0 or inside()) and unit.index == nil, 'A place of ' .. index .. ' is not asked about.');
end
-- A unit the client remembers with a place that is no place, as a party member in another zone is kept with 0, is
-- found again by its id and not by asking about that place.
local kept = client.resolve(0x1000950, 0x850, probe);
assert(kept.index == 0x850, 'Fixture: a remembered unit.');
for _, index in ipairs({ 0, 0x900, 65535, -3 }) do
    kept.index = index;
    reset();
    local unit = client.resolve(0x1000950, nil, probe);
    assert(asked == 0 or inside(), ('A remembered place of %d is not asked about: %s to %s'):format(index, lowest, highest));
    assert(unit.id == 0x1000950, 'It still answers with a unit.');
    kept = client.resolve(0x1000950, 0x850, probe);
end
return 'Entity lookups stay inside the game\'s entity list';
