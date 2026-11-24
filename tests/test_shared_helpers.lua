-- The small helpers many modules share: guarded reads (core/guard.lua), the settings tidy helpers (ui/numbers.lua),
-- plain deep copy and equal (core/tables.lua) and the job names and Copy Image fold (data/shared_ids.lua). Each gives
-- what the copies it replaced gave.
local guard = require('core.guard');

-- index_of and field.
assert(guard.index_of({ a = 5 }, 'a') == 5, 'index_of reads a key.');
assert(guard.field(nil, 'a') == nil and guard.field({ a = 5 }, 'a') == 5, 'field reads a key, and nil from nil.');
local throws = setmetatable({}, { __index = function() error('no'); end });
assert(guard.field(throws, 'a') == nil, 'field gives nil when the lookup fails.');
assert(guard.field(false, 'a') == nil and guard.field(7, 'a') == nil, 'field gives nil from a value with no keys.');

-- call.
local object = {
    one = function(self, ...) return select('#', ...), ...; end,
    fails = function() error('no'); end,
    none = function() end,
    many = function() return 1, 2, 3; end,
    plain = 5,
};
assert(guard.call(nil, 'one') == nil and guard.call(false, 'one') == nil, 'call gives nil from nil or false.');
assert(guard.call(object, 'missing') == nil and guard.call(object, 'plain') == nil, 'call gives nil for a key that is no function.');
assert(guard.call(throws, 'one') == nil, 'call gives nil when the lookup fails.');
assert(guard.call(object, 'fails') == nil and guard.call(object, 'none') == nil, 'call gives nil when the method fails or gives nothing.');
assert(select('#', guard.call(object, 'many')) == 1 and guard.call(object, 'many') == 1, 'call gives the first value only.');
assert(guard.call(object, 'one') == 0 and guard.call(object, 'one', 'a', 'b', 'c') == 3, 'call passes on every argument it gets.');
assert(select('#', guard.call(object, 'missing')) == 1, 'call gives one value, as the copies it replaced did.');

-- resource_name.
assert(guard.resource_name(nil, 60) == nil and guard.resource_name({}, 60) == nil, 'No resource, no name.');
assert(guard.resource_name({ Name = { '  Protect\r\n  ' } }, 60) == 'Protect','A name loses its control characters and spaces.');
assert(guard.resource_name({ Name = { ' . ' } }, 60) == nil and guard.resource_name({ Name = { '' } }, 60) == nil, 'A dot or nothing is no name.');
assert(guard.resource_name({ Name = { 5 } }, 60) == nil, 'A name must be text.');
local long = string.rep('a', 300);
assert(#guard.resource_name({ Name = { long } }, 60) == 60 and #guard.resource_name({ Name = { long } }, 250) == 250, 'most caps the length.');
assert(#guard.resource_name({ Name = { long } }) == 200, 'Without most, a name is cut at 200 characters, as the recasts read one.');
assert(guard.resource_name(throws, 60) == nil, 'A resource that fails to read has no name.');

-- The settings tidy helpers.
local numbers = require('ui.numbers');
assert(numbers.choice('b', { 'a', 'b' }, 'a') == 'b' and numbers.choice('c', { 'a', 'b' }, 'a') == 'a', 'choice keeps a listed value.');
local t = {};
assert(numbers.table_of(t) == t and type(numbers.table_of(5)) == 'table' and numbers.table_of(5) ~= numbers.table_of(5), 'table_of gives a new table for a non-table.');
local fallback = { 0.1, 0.2, 0.3, 0.4 };
local color = numbers.rgba({ 2, -1, 0.5 }, fallback);
assert(color[1] == 1 and color[2] == 0 and color[3] == 0.5 and color[4] == 0.4, 'rgba clamps each part and fills the missing ones.');
color = numbers.rgba({ ['1'] = 0.9, ['2'] = 0.8, 0.7 }, fallback);
assert(color[1] == 0.7 and color[2] == 0.2, 'rgba reads number keys only, unless asked.');
color = numbers.rgba({ ['1'] = 0.9, ['2'] = 0.8, 0.7 }, fallback, nil, true);
assert(color[1] == 0.7 and color[2] == 0.8 and color[3] == 0.3, 'Asked, rgba reads text keys where a number key is missing.');
local out = {};
assert(numbers.rgba('red', fallback, out) == out and out[1] == 0.1 and out[4] == 0.4, 'rgba fills out when given one.');
assert(numbers.rgba({ false, 0 / 0, math.huge }, fallback)[1] == 0.1, 'A part that is no finite number takes the fallback.');
local list = numbers.effect_list({ 5, 3, 5, '7', 0, 1024, 2.5, 445, [9] = true, [10] = 'yes' });
assert(table.concat(list, ',') == '3,5,7,9,445', 'effect_list sorts, drops repeats and keeps ids 1 to 1023: ' .. table.concat(list, ','));
list = numbers.effect_list({ 444, 66, 446 }, { [444] = 66, [446] = 66 });
assert(table.concat(list, ',') == '66', 'fold turns an id into the one it stands for.');
local many = {};
for id = 1, 400 do many[id] = id; end
assert(#numbers.effect_list(many) == 256 and #numbers.effect_list('none') == 0, 'At most 256 are kept.');

-- Plain deep copy and equal.
local tables = require('core.tables');
local source = { a = { b = { 1, 2 } }, c = 'd' };
local copied = tables.copy(source);
assert(copied ~= source and copied.a ~= source.a and copied.a.b ~= source.a.b and copied.a.b[2] == 2 and copied.c == 'd', 'copy copies every level.');
assert(tables.copy(5) == 5 and tables.copy(nil) == nil, 'copy hands back a value that is no table.');
assert(tables.same(copied, source) and not tables.same({ 1 }, { 1, 2 }) and not tables.same({ 1, 2 }, { 1 }), 'same compares every level both ways.');
assert(tables.same(5, 5) and not tables.same(5, '5') and not tables.same({ a = {} }, { a = 1 }), 'same compares types too.');

-- The job names and the Copy Image fold.
local ids = require('data.shared_ids');
assert(#ids.jobs == 18 and ids.jobs[1] == 'WAR' and ids.jobs[14] == 'DRG' and ids.jobs[18] == 'PUP', 'The 18 job names.');
local folded = 0;
for _ in pairs(ids.copy_image) do folded = folded + 1; end
assert(folded == 3 and ids.copy_image[444] == 66 and ids.copy_image[445] == 66 and ids.copy_image[446] == 66, 'Copy Image icons 444 to 446 read as 66.');
assert(require('core.conditions').jobs == ids.jobs, 'conditions.jobs is the shared list.');
local tidied = require('ui.overhead_defaults').tidy({ types = { mob = { include = { 445 }, exclude = { 444, 66 } } } }).types.mob;
assert(table.concat(tidied.include, ',') == '66' and table.concat(tidied.exclude, ',') == '66',
    'Overhead lists read Copy Image icons 444 to 446 as 66: ' .. table.concat(tidied.include, ',') .. ' / ' .. table.concat(tidied.exclude, ','));
-- The lit color is written once, in ui/defaults.lua.
local defaults = require('ui.defaults');
local lit = require('ui.overhead_defaults').make().dispel_color;
assert(lit ~= defaults.dispel_color and tables.same(lit, defaults.dispel_color), 'Overhead icons start with their own copy of the lit color.');
lit = require('ui.party_defaults').make().effects.dispel_color;
assert(lit ~= defaults.dispel_color and tables.same(lit, defaults.dispel_color), 'The party list starts with its own copy of the lit color.');
