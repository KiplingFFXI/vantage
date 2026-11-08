-- The client's own game clock, which its status timers count against. Self timers need only its game time
-- function, so Vantage finds that itself: Ashita's time library looks for thirteen and stops at the first one it
-- misses. If it is missing or matched twice self timers show without a countdown, and nothing else changes. A
-- warmup step looks for it after load (clock.warmup_steps); core/patterns.lua finds it and keeps it for the game
-- session.
local clock = {};
local finder = require('core.patterns');
local patterns = {
    game_time = 'E8????????0305????????C3',
};
-- The one match inside the client module.
local RULE = { unique = true, within = true };
local found, done, problem = nil, {}, nil;
local get_time;

-- Looks for the function and makes it callable. Only an address the finder gave by the rule above is cast: a kept one
-- that fails its check is searched again first.
local function look()
    local ok, why = pcall(function()
        if not ashita or not ashita.memory or type(ashita.memory.find) ~= 'function' then error('client memory access is unavailable', 0); end
        local at, reason = finder.find('clock', 'game_time', patterns.game_time, RULE);
        found = at;
        if not at then problem = 'The game time function ' .. reason .. '.'; return; end
        local ffi = require('ffi');
        if not pcall(ffi.typeof, 'vg_game_time_f') then
            ffi.cdef[[
                typedef uint32_t (__stdcall *vg_game_time_f)(void);
            ]];
        end
        get_time = ffi.cast('vg_game_time_f', at);
    end);
    if not ok then problem = tostring(why); end
end

local STEP = finder.step('clock.game_time', done, look);

-- The clock's warmup step, as { name, run }. clock.load runs it.
function clock.warmup_steps() return { STEP }; end

function clock.load()
    if not done['clock.game_time'] then STEP.run(); end
end

-- Whether the search for the function has run. Asking never starts one.
function clock.loaded() return done['clock.game_time'] == true; end

-- Whether self timers can count down.
function clock.available()
    clock.load();
    return get_time ~= nil;
end

-- The client's raw game time, or nil without the function.
function clock.get_game_time_raw()
    clock.load();
    if not get_time then return nil; end
    return get_time();
end

-- For /vg report: whether the clock was found, and a plain line saying what that means.
function clock.status()
    clock.load();
    local status = { available = get_time ~= nil, game_time = found, problem = problem };
    status.reason = get_time and 'Your own buffs and debuffs count down with the game clock.'
        or 'The game clock was not found on this client, so your own buffs and debuffs show without a countdown.';
    return status;
end

if VANTAGE_TEST_MODE then
    function clock._reset_for_tests()
        found, problem, get_time = nil, nil, nil;
        for key in pairs(done) do done[key] = nil; end
    end
end

return clock;
