-- Frame and load timings for /vg report, in milliseconds since Vantage loaded. record keeps each stage's count,
-- last, longest and total, and the last 16 stages that took 5 ms or more. A zone window keeps the same from a
-- zone change until 2 seconds after the displays are ready again, or 30 seconds without that. Stages overlap:
-- frame.render holds the draws inside it. Loading this errors when there is no counter to read, and every
-- caller then times nothing.
local performance = {};
local SLOW, TIMEOUT, TAIL = 5, 30000, 2000;
local read, frequency;

do
    local ok, ffi = pcall(require, 'ffi');
    if ok and type(ffi) == 'table' and type(ffi.typeof) == 'function' then
        local made, cell = pcall(function()
            if not pcall(ffi.typeof, 'vg_counter') then ffi.cdef[[
                typedef struct { uint32_t low; uint32_t high; } vg_counter;
                int __stdcall QueryPerformanceCounter(vg_counter*);
                int __stdcall QueryPerformanceFrequency(vg_counter*);
            ]]; end
            local value = ffi.new('vg_counter');
            if ffi.C.QueryPerformanceFrequency(value) == 0 then return nil; end
            return value;
        end);
        if made and cell then
            frequency = cell.low + cell.high * 4294967296;
            -- One cell, read in place: the counter costs no allocation.
            read = function()
                if ffi.C.QueryPerformanceCounter(cell) == 0 then return nil; end
                return cell.low + cell.high * 4294967296;
            end;
        end
    end
    if not read and ashita and ashita.time and type(ashita.time.query_performance_counter) == 'function' then
        local got, value = pcall(ashita.time.query_performance_frequency);
        if got and type(value) == 'table' then
            frequency = tonumber(value.quad_part);
            read = function()
                local counted, counter = pcall(ashita.time.query_performance_counter);
                return counted and type(counter) == 'table' and tonumber(counter.quad_part) or nil;
            end;
        end
    end
end
if not read or type(frequency) ~= 'number' or frequency <= 0 then error('Timings are unavailable on this system.', 0); end
local origin = read();
if type(origin) ~= 'number' then error('Timings are unavailable on this system.', 0); end
-- When this module loaded, on the counter every Lua state in the game shares, in ms: a reload's next load compares
-- its own start with the times the unload kept (core/warmup.lua).
performance.origin_ms = origin * 1000 / frequency;

local function window()
    local slow = {};
    for index = 1, 16 do slow[index] = { at = 0, ms = 0 }; end
    return { stages = {}, slow = slow, slow_count = 0, slow_next = 1 };
end
local overall, zone = window(), window();
local zone_sequence, zone_active, zone_ready = 0, false, false;
local zone_begin_at, zone_ready_at, zone_until_at = 0, 0, 0;

local function finite(value) return type(value) == 'number' and value == value and value > -math.huge and value < math.huge; end

function performance.now()
    local counter = read();
    if not counter then return 0; end
    return (counter - origin) * 1000 / frequency;
end

local function accumulate(into, stage, finished, elapsed)
    local sample = into.stages[stage];
    if not sample then sample = { count = 0, last = 0, max = 0, total = 0, max_at = 0 }; into.stages[stage] = sample; end
    sample.count, sample.last, sample.total = sample.count + 1, elapsed, sample.total + elapsed;
    if sample.count == 1 or elapsed > sample.max then sample.max, sample.max_at = elapsed, finished; end
    if elapsed >= SLOW then
        local event = into.slow[into.slow_next];
        event.stage, event.at, event.ms = stage, finished, elapsed;
        into.slow_next = into.slow_next % 16 + 1;
        if into.slow_count < 16 then into.slow_count = into.slow_count + 1; end
    end
end

local function expire(at)
    if zone_active and at > (zone_ready and zone_until_at or zone_begin_at + TIMEOUT) then zone_active = false; end
end

-- Adds the time from started to now to stage. False for a stage that isn't a name or a start that isn't a time.
function performance.record(stage, started)
    local finished = performance.now();
    if type(stage) ~= 'string' or stage == '' or not finite(started) or started < 0 or finished < started then return false; end
    accumulate(overall, stage, finished, finished - started);
    expire(finished);
    if zone_active and finished >= zone_begin_at then accumulate(zone, stage, finished, finished - started); end
    return true;
end

-- Adds a time measured elsewhere, elapsed ms, to stage as if it ended now: the unload before a reload. False for a
-- stage that isn't a name or a time that isn't one.
function performance.add(stage, elapsed)
    if type(stage) ~= 'string' or stage == '' or not finite(elapsed) or elapsed < 0 then return false; end
    local finished = performance.now();
    accumulate(overall, stage, finished, elapsed);
    expire(finished);
    return true;
end

-- A zone change starts a new zone window, unless one is still waiting for the displays.
function performance.zone_begin()
    local at = performance.now();
    expire(at);
    if zone_active and not zone_ready then return false; end
    zone, zone_sequence, zone_active, zone_ready = window(), zone_sequence + 1, true, false;
    zone_begin_at, zone_ready_at, zone_until_at = at, 0, at + TIMEOUT;
    return true;
end

-- The displays are ready after a zone change; its window keeps the next 2 seconds.
function performance.zone_ready()
    local at = performance.now();
    if at < zone_begin_at then return false; end
    expire(at);
    if not zone_active or zone_ready then return false; end
    zone_ready, zone_ready_at, zone_until_at = true, at, at + TAIL;
    return true;
end

local function copy_window(from, out)
    out.stages = {};
    for stage, sample in pairs(from.stages) do
        out.stages[stage] = { count = sample.count, last = sample.last, max = sample.max, total = sample.total, max_at = sample.max_at };
    end
    out.slow_events = {};
    for index = 1, from.slow_count do
        local event = from.slow[(from.slow_next - from.slow_count + index - 2) % 16 + 1];
        out.slow_events[index] = { stage = event.stage, at = event.at, ms = event.ms };
    end
    return out;
end

function performance.snapshot()
    local at = performance.now();
    expire(at);
    local out = copy_window(overall, { unit = 'ms', overlapping = true, now = at, slow_threshold_ms = SLOW,
        clock = 'QueryPerformanceCounter' });
    out.zone = copy_window(zone, { sequence = zone_sequence, active = zone_active, ready = zone_ready, begin_at = zone_begin_at,
        ready_at = zone_ready_at, until_at = zone_until_at, timeout_ms = TIMEOUT, tail_ms = TAIL });
    return out;
end

return performance;
