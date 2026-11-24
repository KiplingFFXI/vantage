-- Seconds for the waits that time a message, a cache or a retry: the frame timings' counter (core/performance.lua),
-- else os.clock. The game's os.clock stops counting after about 24.86 days with the game open, so a wait timed on it
-- would never end.
local ok, performance = pcall(require, 'core.performance');
if ok and type(performance) == 'table' and type(performance.now) == 'function' then
    local now = performance.now;
    return function() return now() / 1000; end;
end
return function() return os.clock(); end;
