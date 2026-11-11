-- An effect the client doesn't name is asked about again each time, in case the client names it later. Asking makes
-- nothing new, and the row that stands in for it is the same one each time.
local catalog = require('core.catalog');
local asked, later = 0, nil;
local strings = { GetString = function (_, table_name, id)
    assert(table_name == 'buffs.names');
    asked = asked + 1;
    return id == 998 and later or nil;
end };
AshitaCore.GetResourceManager = function () return strings; end;

local row = catalog.get(998);
assert(row.unnamed and row.name == 'An effect with no name', 'Fixture: nothing names 998.');
assert(catalog.get(998) == row, 'An effect with no name gets the same row each time.');

local function run(count)
    for _ = 1, count do assert(catalog.get(998) == row); end;
end;
jit.off(); jit.flush();
run(60);
collectgarbage('collect'); collectgarbage('collect');
collectgarbage('stop');
asked = 0;
local before = collectgarbage('count');
run(2000);
local each = (collectgarbage('count') - before) / 2000;
collectgarbage('restart');
jit.on();
assert(asked == 2000, 'The client is still asked each time: ' .. asked);
assert(each < 0.0005, ('Looking up an effect with no name makes %.4f KB each time, nothing expected'):format(each));

later = 'Named Later';
assert(catalog.get(998).name == 'Named Later' and not catalog.get(998).unnamed, 'Once the client names it, its name is used.');
return 'An effect with no name is looked up without making anything';
