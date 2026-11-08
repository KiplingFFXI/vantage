-- The game clock is looked for by its own warmup steps, not by a client read: a read before them searches only
-- the reader's three flags and gives self timers no deadline, a read after them gives the deadline. client.load still
-- looks for both, and client.capabilities finishes looking for the clock first, so a caller that keeps its table
-- (core/overhead.lua) never keeps a guess.
local base, size = 0x10000000, 0x800000;
local GAME, DIFF = 'E8????????0305????????C3', 'E8????????8BC88B4424043BC876??2BC1488BC8B8FFFFFF7F';
local matches = { [GAME] = { base + 0x1000 }, [DIFF] = { base + 0x2000 } };
local finds = {};
ashita.memory.get_base = function() return base; end;
ashita.memory.get_size = function() return size; end;
ashita.memory.find = function(_, _, pattern, offset, usage)
    finds[#finds + 1] = pattern;
    local list = matches[pattern];
    if list then return list[usage + 1] or 0; end
    return 0;
end;
local raw = 1000;
local ffi = package.loaded.ffi;
ffi.typeof = function(name) if not ffi.declared then error('not declared'); end; return name; end;
ffi.cdef = function(source) ffi.declared = source; end;
ffi.cast = function(kind) return kind == 'vg_game_time_f' and function() return raw; end or function(value) return value; end; end;
local mm = AshitaCore:GetMemoryManager();
local stats = mm:GetPlayer();
local icons, timers = {}, {};
for slot = 0, 31 do icons[slot], timers[slot] = 255, 0; end
icons[0], timers[0] = 33, (raw + 100) * 60;
stats.GetStatusIcons = function() return icons; end;
stats.GetStatusTimers = function() return timers; end;
stats.GetBuffs = function() return icons; end;
AshitaCore.GetMemoryManager = function() return mm; end;

local function fresh()
    package.loaded['core.clock'], package.loaded['core.client'] = nil, nil;
    finds = {};
    return require('core.clock'), require('core.client');
end
local function searched(pattern)
    for _, value in ipairs(finds) do if value == pattern then return true; end end
    return false;
end

local clock, client = fresh();
assert(#client.warmup_steps() == 1 and client.warmup_steps()[1].name == 'client.pointers');
local steps = clock.warmup_steps();
assert(#steps == 1 and steps[1].name == 'clock.game_time');
local s = client.read(10);
assert(s.valid and #s.self_effects == 1 and s.self_effects[1].deadline == nil and s.self_diagnostics.clock_available == false,
    'Before the clock steps, self timers have no deadline.');
assert(#finds == 3 and not searched(GAME) and not searched(DIFF), 'A read searches only the reader\'s three flags.');
assert(not clock.loaded());
steps[1].run();
assert(#finds == 5 and searched(GAME) and clock.loaded());
s = client.read(12);
assert(s.self_effects[1].deadline == 112 and s.self_diagnostics.clock_available == true, 'After them, the deadline shows.');
assert(client.capabilities().timers and #finds == 5);

-- client.load finds the flags and the clock, each searched once.
clock, client = fresh();
client.load();
assert(#finds == 5 and searched(GAME) and clock.loaded(), 'client.load finds the flags and the clock.');
client.load();
assert(client.read(14).self_effects[1].deadline == 114 and #finds == 5, 'Nothing is searched twice.');

-- capabilities asked first finishes the look, so the table a caller keeps holds the final answer.
clock, client = fresh();
local kept = client.capabilities();
assert(kept.timers == true and clock.loaded() and searched(GAME));
assert(client.clock_status().available);
matches[GAME] = nil;
clock, client = fresh();
kept = client.capabilities();
assert(kept.timers == false and clock.loaded(), 'Without the game time function, timers is false, and final.');
steps = clock.warmup_steps();
local count = #finds;
for _, step in ipairs(steps) do step.run(); end
assert(#finds == count and client.capabilities().timers == false and not client.clock_status().available);
assert(client.read(13).self_effects[1].deadline == nil);
return 'Game clock looked for by its own steps';
