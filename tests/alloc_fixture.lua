-- The KB each run makes, as the allocation tests count it: the compiler off, 60 runs, two full collections, the
-- collector stopped, 6 runs for the Lua stack to grow back, then count runs. run(n) does n runs.
local A = {};
function A.measure(run, count)
    jit.off(); jit.flush();
    run(60);
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    run(6);
    local before = collectgarbage('count');
    run(count);
    local each = (collectgarbage('count') - before) / count;
    collectgarbage('restart');
    jit.on();
    return each;
end
return A;
