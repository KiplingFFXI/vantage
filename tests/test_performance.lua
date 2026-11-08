-- core.performance times stages in milliseconds from the Windows performance counter, read through ffi into
-- one cell, else through Ashita's own counter. Without either it fails to load, every caller times nothing,
-- and /vg report says timings are unavailable.
local function load(ffi)
    package.loaded['core.performance'] = nil;
    local saved = package.loaded.ffi;
    package.loaded.ffi = ffi;
    local ok, value = pcall(require, 'core.performance');
    package.loaded.ffi = saved;
    return ok, value;
end;

-- The counter through ffi: 1,000,000 ticks a second, read into the same cell every time.
local ticks, cells, reads = 5000000, {}, 0;
local fake = { declared = {}, C = {} };
fake.typeof = function(name) if not fake.declared[name] then error('not declared'); end; return name; end;
fake.cdef = function(source) for name in source:gmatch('}%s*([%w_]+)%s*;') do fake.declared[name] = true; end; end;
fake.new = function(kind) assert(kind == 'vg_counter'); local cell = { low = 0, high = 0 }; cells[#cells + 1] = cell; return cell; end;
fake.C.QueryPerformanceFrequency = function(cell) cell.low, cell.high = 1000000, 0; return 1; end;
fake.C.QueryPerformanceCounter = function(cell)
    reads = reads + 1;
    cell.low, cell.high = ticks % 4294967296, math.floor(ticks / 4294967296);
    return 1;
end;
local ok, performance = load(fake);
assert(ok and type(performance.now) == 'function' and type(performance.record) == 'function', tostring(performance));
assert(#cells == 1, 'One counter cell serves every read.');
assert(performance.now() == 0, 'Time counts from the load.');
ticks = ticks + 2500;
assert(performance.now() == 2.5 and #cells == 1, 'Milliseconds, read into the same cell.');
local started = performance.now();
ticks = ticks + 1000;
assert(performance.record('frame.render', started) and performance.record('frame.render', performance.now()));
ticks = ticks + 6000;
assert(performance.record('draw.hud', started), 'A 7 ms stage is recorded.');
assert(not performance.record('', started) and not performance.record('draw.hud', 0 / 0)
    and not performance.record('draw.hud', performance.now() + 1) and not performance.record(nil, started),
    'A stage that is not a name, or a start that is not a time, is refused.');
local snapshot = performance.snapshot();
local render, hud = snapshot.stages['frame.render'], snapshot.stages['draw.hud'];
assert(snapshot.unit == 'ms' and snapshot.clock == 'QueryPerformanceCounter' and snapshot.slow_threshold_ms == 5);
assert(render.count == 2 and render.max == 1 and render.last == 0 and render.total == 1);
assert(hud.count == 1 and hud.max == 7 and #snapshot.slow_events == 1 and snapshot.slow_events[1].stage == 'draw.hud'
    and snapshot.slow_events[1].ms == 7, 'Stages of 5 ms or more are kept as slow events.');
for _ = 1, 20 do ticks = ticks + 5000; performance.record('frame.refresh', performance.now() - 5); end;
snapshot = performance.snapshot();
assert(#snapshot.slow_events == 16 and snapshot.slow_events[16].stage == 'frame.refresh'
    and snapshot.slow_events[1].stage == 'frame.refresh', 'The last 16 slow events are kept.');

-- A zone window keeps the stages from a zone change until 2 seconds after the displays are ready.
assert(performance.zone_begin() and not performance.zone_begin(), 'A zone window waiting for the displays is not started again.');
started = performance.now(); ticks = ticks + 3000;
performance.record('frame.render', started);
assert(performance.snapshot().zone.stages['frame.render'].count == 1 and performance.snapshot().zone.active);
assert(performance.zone_ready() and not performance.zone_ready());
ticks = ticks + 2001000;
assert(not performance.snapshot().zone.active, 'The zone window ends 2 seconds after the displays are ready.');
assert(performance.zone_begin(), 'A new zone starts a new window.');
ticks = ticks + 30001000;
assert(not performance.snapshot().zone.active, 'A zone window waits 30 seconds at most.');

-- Ashita's own counter when ffi has none.
local qpc = 1000;
ashita.time.query_performance_frequency = function() return { quad_part = 1000 }; end;
ashita.time.query_performance_counter = function() return { quad_part = qpc }; end;
ok, performance = load({});
assert(ok, tostring(performance));
qpc = qpc + 3;
assert(performance.now() == 3, 'Ashita\'s counter gives the same milliseconds.');

-- Neither: the module fails to load, so callers time nothing, and /vg report says so.
ashita.time.query_performance_frequency, ashita.time.query_performance_counter = nil, nil;
ok, performance = load({});
assert(not ok and tostring(performance):find('Timings are unavailable', 1, true));
package.loaded['core.performance'] = nil;
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load');
app.refresh(1);
MOCK.frame();
assert(app.callbacks.export_report());
local report = require('core.store').read(MOCK_INSTALL_PATH .. '/config/addons/vantage/reports/latest.json');
assert(report.performance.available == false and report.performance.reason:find('Timings are unavailable', 1, true),
    '/vg report says timings are unavailable.');
return 'Lua timings for /vg report';
