-- core.clock finds the client's game time functions by their own two patterns, each matched once inside the
-- client, and calls the one it found. Without one, self timers have no countdown and /vg report says why.
local clock = require('core.clock');
local base, size = 0x10000000, 0x800000;
local game_time, time_diff = base + 0x1000, base + 0x2000;
local matches = {};
local finds = {};
ashita.memory.get_base = function() return base; end;
ashita.memory.get_size = function() return size; end;
ashita.memory.find = function(module, _, pattern, offset, usage)
    assert(module == 'FFXiMain.dll' and offset == 0, 'The search covers the client module only.');
    finds[#finds + 1] = pattern;
    local list = matches[pattern] or {};
    return list[usage + 1] or 0;
end;
local declared, calls = nil, {};
local ffi = package.loaded.ffi;
ffi.typeof = function(name) if not declared then error('not declared'); end; return name; end;
ffi.cdef = function(source) declared = source; end;
ffi.cast = function(kind, at)
    assert(declared and declared:find(kind, 1, true), 'The function type is declared before the cast.');
    return function(value)
        calls[#calls + 1] = { kind = kind, at = at, value = value };
        return kind == 'vg_game_time_f' and 123456 or value + 60;
    end;
end;
local GAME, DIFF = 'E8????????0305????????C3', 'E8????????8BC88B4424043BC876??2BC1488BC8B8FFFFFF7F';

-- Both found once: the clock runs from the game time function.
matches[GAME], matches[DIFF] = { game_time }, { time_diff };
clock._reset_for_tests();
assert(clock.available() and clock.get_game_time_raw() == 123456, 'The game time function is called.');
assert(calls[1].kind == 'vg_game_time_f' and calls[1].at == game_time);
local status = clock.status();
assert(status.available and status.game_time == game_time and status.problem == nil);
assert(not status.reason:find('?', 1, true) and not status.reason:lower():find('unknown', 1, true));
local searched = #finds;
clock.load(); clock.get_game_time_raw();
assert(#finds == searched, 'The patterns are searched once.');
for _, pattern in ipairs(finds) do assert(pattern == GAME or pattern == DIFF, 'Only the two clock patterns are searched.'); end

-- A pattern that matches twice, or one outside the client, is not called.
for _, case in ipairs({ { game_time, base + 0x3000 }, { base - 0x1000 }, { base + size } }) do
    matches[GAME], matches[DIFF], calls = case, { time_diff }, {};
    clock._reset_for_tests();
    assert(not clock.available() and clock.get_game_time_raw() == nil and #calls == 0,
        'An ambiguous or outside match is never called.');
    status = clock.status();
    assert(not status.available and status.problem:find('game time function', 1, true)
        and status.reason:find('without a countdown', 1, true));
end

-- Missing: self timers show without a countdown and nothing else changes.
matches[GAME], matches[DIFF], calls = nil, nil, {};
clock._reset_for_tests();
assert(not clock.available() and clock.get_game_time_raw() == nil and #calls == 0);
status = clock.status();
assert(not status.available and status.reason == 'The game clock was not found on this client, so your own buffs and debuffs show without a countdown.');


-- Two warmup steps, one function each; the clock's own calls run whichever have not run.
matches[GAME], matches[DIFF], calls, finds = { game_time }, { time_diff }, {}, {};
clock._reset_for_tests();
local steps = clock.warmup_steps();
assert(#steps == 1 and steps[1].name == 'clock.game_time');
assert(not clock.loaded() and #finds == 0, 'Nothing is looked for before a step or a call.');
steps[1].run();
assert(#finds == 2 and finds[1] == GAME and finds[2] == GAME and clock.loaded() and clock.status().problem == nil, 'The step looks for the game time alone.');
assert(clock.get_game_time_raw() == 123456 and #finds == 2);
matches[GAME], finds = nil, {};
clock._reset_for_tests();
assert(not clock.available() and clock.loaded() and #finds == 1, 'A call with no step run looks for it.');
assert(clock.status().problem == 'The game time function is missing.');

-- The client reader uses this clock, never Ashita's time library.
matches[GAME], matches[DIFF] = { game_time }, { time_diff };
clock._reset_for_tests();
package.preload['ffxi.time'] = function() error('Ashita\'s time library is not used for self timers.'); end;
package.loaded['core.client'] = nil;
local client = require('core.client');
assert(client.capabilities().timers and client.clock_status().available);
assert(not package.loaded['ffxi.time']);
matches[GAME] = nil;
clock._reset_for_tests();
package.loaded['core.client'] = nil;
client = require('core.client');
assert(not client.capabilities().timers and not client.clock_status().available,
    'Without the game time function the client reader has no clock.');
return 'Game clock from two client patterns';
