-- Each application the observer reads asks catalog.drops and catalog.duration (core/observer.lua). Neither makes a table
-- it throws away: an effect with no drops gets the same empty list each time, a duration with no sample of your gear
-- makes nothing, and with one it makes only the totals of the gear it reads. Measured as
-- test_catalog_unnamed_allocation.lua does, with the collector stopped and the compiler off.
local catalog = require('core.catalog');
local gear = require('data.gear');
-- The bytes each call of run makes.
local function garbage(run)
    jit.off(); jit.flush();
    for _ = 1, 60 do run(); end
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    local before = collectgarbage('count');
    for _ = 1, 1000 do run(); end
    local each = (collectgarbage('count') - before) * 1024 / 1000;
    collectgarbage('restart');
    jit.on();
    return each;
end

-- Protect (40) has no drops, so its list is empty, and the same one each time.
assert(#catalog.drops(40) == 0 and catalog.drops(40) == catalog.drops(40), 'An effect with no drops gets the same empty list each time.');
-- A member's Protectra (spell 125) has no sample, since only your own actions read your gear.
assert(catalog.duration('spells', 125, 40, nil) == 1800, 'Fixture: Protectra lasts 1800 s.');
-- Your own, with all 16 slots worn and none of them in data/gear.lua.
local sample = { items = {}, buffs = {}, merits = {}, level = 75, job = 3, complete = true };
for slot = 0, 15 do
    sample.items[slot] = 12000 + slot;
    assert(gear[12000 + slot] == nil, 'Fixture: no gear row for item ' .. (12000 + slot));
end
assert(catalog.duration('spells', 125, 40, sample) == 1800, 'Fixture: yours lasts 1800 s too.');

-- One empty table, which is all the totals of gear with no rows come to.
local one = garbage(function() local _ = {}; end);
local drops = garbage(function() catalog.drops(40); end);
local none = garbage(function() catalog.duration('spells', 125, 40, nil); end);
local own = garbage(function() catalog.duration('spells', 125, 40, sample); end);
local proc = garbage(function() catalog.duration('procs', 1, 4, sample); end);
local roll = garbage(function() catalog.roll_duration(nil); end);
assert(drops < 1, ('Drops for an effect with none make %.0f bytes; nothing expected'):format(drops));
assert(none < 1, ('A duration with no sample makes %.0f bytes; nothing expected'):format(none));
assert(own - one < 1, ('A duration with 16 slots worn makes %.0f bytes past its totals; nothing expected'):format(own - one));
assert(proc < 1, ('An additional effect\'s duration makes %.0f bytes; nothing expected'):format(proc));
assert(roll < 1, ('A roll\'s duration with no sample makes %.0f bytes; nothing expected'):format(roll));
return 'An application\'s drops and duration make no table they throw away';
