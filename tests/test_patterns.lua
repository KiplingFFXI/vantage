-- core/patterns.lua: one finder for every client pattern, each owner's own rule, and what it finds kept for the game
-- session in the process environment, checked again before each use. Here a small module stands in for the client.
local patterns = require('core.patterns');
local BASE, SIZE = 0x10000000, 0x400;
local data, finds = {}, {};
for at = 0, SIZE - 1 do data[at] = 0x90; end
local function plant(at, pattern)
    for index = 0, #pattern / 2 - 1 do
        local pair = pattern:sub(index * 2 + 1, index * 2 + 2);
        data[at + index] = pair == '??' and 0x11 or tonumber(pair, 16);
    end
end
local function matches(pattern, at)
    for index = 0, #pattern / 2 - 1 do
        local pair = pattern:sub(index * 2 + 1, index * 2 + 2);
        if pair ~= '??' and data[at + index] ~= tonumber(pair, 16) then return false; end
    end
    return true;
end
-- As Ashita's FindPattern: the usage-th match from the start (overlapping ones too), plus offset, or 0.
ashita.memory.find = function(module, size, pattern, offset, usage)
    finds[#finds + 1] = { module = module, size = size, pattern = pattern, offset = offset, usage = usage };
    local count = 0;
    for at = 0, SIZE - #pattern / 2 do
        if matches(pattern, at) then
            if count == usage then return BASE + at + offset; end
            count = count + 1;
        end
    end
    return 0;
end
ashita.memory.read_uint8 = function(at) return data[at - BASE] or 0; end
ashita.memory.get_base = function(module) assert(module == 'FFXiMain.dll'); return BASE; end
ashita.memory.get_size = function(module) assert(module == 'FFXiMain.dll'); return SIZE; end
local page_checks = 0;
local function pages(at, size) page_checks = page_checks + 1; return at >= BASE and at + size <= BASE + SIZE; end
local stages = {};
local timing = {
    now = function() return MOCK.now * 1000; end,
    record = function(stage, started)
        assert(type(started) == 'number', 'A stage is timed from its start.');
        stages[stage] = (stages[stage] or 0) + 1;
        return true;
    end,
};
local function fresh(store)
    package.loaded['core.patterns'] = nil;
    patterns = require('core.patterns');
    patterns._set_pages(pages);
    patterns._set_performance(timing);
    if store then patterns._set_store(store); end
    finds, stages = {}, {};
end
local function positive(value) return type(value) == 'number' and value > 0 and value == math.floor(value); end

local A, TWICE, MISSING, D = 'AABBCC??DDEE', 'B1B2??B4', '010203', 'C1C2C3C4';
plant(0x10, A); plant(0x40, TWICE); plant(0x80, TWICE); plant(0x100, D);
local UNIQUE = { unique = true, within = true };

-- The rules. The tests keep nothing unless they set a store, and never touch the ffi for one.
local ffi_calls = 0;
local mocked = package.loaded.ffi;
local cdef = mocked.cdef;
mocked.cdef = function(...) ffi_calls = ffi_calls + 1; return cdef(...); end;
fresh();
local at, why = patterns.find('t', 'a', A, UNIQUE);
assert(at == BASE + 0x10 and why == nil, 'A pattern found once is found.');
assert(#finds == 2 and finds[1].usage == 0 and finds[2].usage == 1 and finds[1].module == 'FFXiMain.dll' and finds[1].size == 0
    and finds[1].offset == 0, 'The first match, then a second search over the whole module.');
assert(stages['patterns.first'] == 1 and stages['patterns.unique'] == 1 and stages['patterns.t'] == 1,
    'The first search, the second and the owner\'s whole find are timed apart.');
at = patterns.find('t', 'a', A, UNIQUE);
assert(at == BASE + 0x10 and #finds == 4, 'Without a store nothing is kept: each find searches again.');
assert(ffi_calls == 0, 'The tests reach no environment unless they set a store.');
mocked.cdef = cdef;

fresh();
at, why = patterns.find('t', 'b', TWICE, UNIQUE);
assert(at == nil and why == 'matches more than once' and #finds == 2);
at, why = patterns.find('t', 'c', MISSING, UNIQUE);
assert(at == nil and why == 'is missing' and #finds == 3 and finds[3].usage == 0, 'A missing pattern is not searched twice.');
ashita.memory.get_base = function() return BASE + 0x200; end
at, why = patterns.find('t', 'a', A, UNIQUE);
assert(at == nil and why == 'is outside the client' and #finds == 4, 'A match outside the module fails before a second search.');
at = patterns.find('t', 'a', A, { unique = true });
assert(at == BASE + 0x10, 'Without within, the module range is not checked.');
ashita.memory.get_base = function() return BASE; end
at, why = patterns.find('t', 'a', A, { unique = true, inside = function(value) return value ~= BASE + 0x10; end });
assert(at == nil and why == 'is outside the client', 'The owner\'s own range check.');
local function failing(pattern, offset, usage)
    if usage == 1 then error('scan failed'); end
    return ashita.memory.find('FFXiMain.dll', 0, pattern, offset, usage);
end
at, why = patterns.find('t', 'a', A, { unique = true, find = failing });
assert(at == nil and why == 'matches more than once', 'A second search that fails is no proof of one match.');
at = patterns.find('t', 'a', A, { unique = true, lenient = true, find = failing });
assert(at == BASE + 0x10, 'Unless the owner counts it as none, as the party list always has.');
at, why = patterns.find('t', 'b', TWICE, { unique = true, lenient = true });
assert(at == nil and why == 'matches more than once');
at, why = patterns.find('t', 'a', A, { unique = true, find = function() error('scan failed'); end });
assert(at == nil and why == 'is missing');
finds, stages = {}, {};
at = patterns.find('u', 'd', D, { offset = 16, accept = positive });
assert(at == BASE + 0x100 + 16 and #finds == 1 and finds[1].offset == 16 and finds[1].usage == 0,
    'A first-match rule searches once, with its offset.');
assert(stages['patterns.first'] == 1 and stages['patterns.unique'] == nil and stages['patterns.u'] == 1);
at, why = patterns.find('u', 'c', MISSING, { offset = 16, accept = positive });
assert(at == nil and why == 'is missing', 'The search adds no offset to no match.');
patterns.find('t', 'a', A, { unique = true, module = ':ffximain' });
assert(finds[#finds].module == ':ffximain', 'An owner keeps its own module name.');

-- Kept: the header names this process and module, and each good result is kept under owner, name and a hash of
-- the pattern and its rule.
local store = MOCK.pattern_store(nil, 0x4D2);
fresh(store);
assert(patterns.find('t', 'a', A, UNIQUE) == BASE + 0x10);
assert(patterns.find('u', 'd', D, { offset = 16, accept = positive }) == BASE + 0x110);
assert(patterns.find('t', 'b', TWICE, UNIQUE) == nil and patterns.find('t', 'c', MISSING, UNIQUE) == nil);
local header = '1;4d2;10000000;400';
assert(store.text:sub(1, #header + 1) == header .. ';', 'The header: version, process, module base and size.');
local keys = {};
for key, value in store.text:gmatch(';([^;=]+)=(%x+)') do keys[#keys + 1] = key; keys[key] = tonumber(value, 16); end
assert(#keys == 2 and keys[1]:match('^t%.a%.%x%x%x%x%x%x%x%x$') and keys[2]:match('^u%.d%.%x%x%x%x%x%x%x%x$')
    and keys[keys[1]] == BASE + 0x10 and keys[keys[2]] == BASE + 0x110,
    'Only results the rule accepted are kept, sorted by key, with the offset added as the search adds it.');
local A_KEY, good = keys[1], store.text;
assert(#finds == 6);
assert(patterns.find('t', 'a', A, UNIQUE) == BASE + 0x10 and #finds == 6, 'A kept address is used again.');
assert(patterns.find('t', 'a', A, { unique = true, lenient = true }) == BASE + 0x10 and #finds == 8,
    'Another rule for the same pattern is kept apart.');

-- A reload: a new module over the same environment searches nothing and gives the same addresses.
store.text = good;
fresh(store);
local writes = store.writes;
assert(patterns.find('t', 'a', A, UNIQUE) == BASE + 0x10 and patterns.find('u', 'd', D, { offset = 16, accept = positive }) == BASE + 0x110);
assert(#finds == 0 and store.reads == 2 and store.writes == writes, 'Reused: no search, and nothing to write.');
assert(stages['patterns.verify'] == 2 and stages['patterns.t'] == 1 and stages['patterns.first'] == nil);
-- A changed pattern text is searched again, alone.
assert(patterns.find('t', 'a', 'AABBCC??DD', UNIQUE) == BASE + 0x10 and #finds == 2, 'A changed pattern is searched again.');
assert(patterns.find('t', 'a', A, UNIQUE) == BASE + 0x10 and #finds == 2, 'The old text is still kept.');
-- A changed fixed byte is searched again; a changed wildcard byte is not.
store.text = good;
fresh(store);
data[0x13] = 0x77;
assert(patterns.find('t', 'a', A, UNIQUE) == BASE + 0x10 and #finds == 0, 'A wildcard byte is not compared.');
data[0x11] = 0x00; plant(0x200, A);
assert(patterns.find('t', 'a', A, UNIQUE) == BASE + 0x200 and #finds == 2, 'A fixed byte that changed is searched again.');
assert(store.text:find(A_KEY .. '=10000200', 1, true), 'The new address is kept in place of the old.');
plant(0x10, A);
for at = 0x200, 0x205 do data[at] = 0x90; end
-- An address on a page that can't be read is searched again, and a result that can't be checked is not kept.
store.text = good;
fresh(store);
patterns._set_pages(function() return false; end);
assert(patterns.find('t', 'a', A, UNIQUE) == BASE + 0x10 and #finds == 2);
assert(not store.text:find(A_KEY, 1, true));
patterns._set_pages(pages);
-- The owner's checks hold for a kept address as well.
store.text = good;
fresh(store);
at, why = patterns.find('t', 'a', A, { unique = true, within = true, inside = function(value) return value ~= BASE + 0x10; end });
assert(at == nil and why == 'is outside the client' and #finds == 1);

-- Anything else in the environment is ignored, and the next result writes a good header over it.
local entry = A_KEY .. '=10000010';
local garbage = {
    'garbage', '', 12345, true, header, header .. 'X;' .. entry, '1;4d3;10000000;400;' .. entry,
    '1;4d2;10001000;400;' .. entry, '1;4d2;10000000;800;' .. entry, '2;4d2;10000000;400;' .. entry,
    header .. ';t.a.zzzzzzzz=10000010', header .. ';' .. A_KEY .. '=110000010', header .. ';' .. A_KEY .. '=zz',
    header .. ';' .. A_KEY .. '=', header .. ';' .. A_KEY, header .. ';' .. A_KEY .. '=10000410',
    header .. ';' .. A_KEY .. '=fffff000', header .. ';' .. A_KEY .. '=10000011', header .. ';' .. A_KEY .. '=10000010=1',
};
for index, text in ipairs(garbage) do
    store.text = text;
    fresh(store);
    assert(patterns.find('t', 'a', A, UNIQUE) == BASE + 0x10 and #finds == 2, 'Ignored: entry ' .. index);
    assert(store.text:sub(1, #header + 1) == header .. ';', 'Rewritten: entry ' .. index);
end
-- A store that fails to read or write changes nothing found.
local broken = { read = function() error('read failed'); end, write = function() error('write failed'); end,
    process = function() return 0x4D2; end };
fresh(broken);
assert(patterns.find('t', 'a', A, UNIQUE) == BASE + 0x10 and #finds == 2);
fresh({ read = function() return good; end, write = function() return true; end, process = function() error('no id'); end });
assert(patterns.find('t', 'a', A, UNIQUE) == BASE + 0x10 and #finds == 2, 'Without a process id nothing is reused.');
ashita.memory.get_base = function() return 0; end
store.text = good;
fresh(store);
assert(patterns.find('t', 'a', A, { unique = true }) == BASE + 0x10 and #finds == 2 and store.text == good,
    'Without the module range nothing is reused or written.');
ashita.memory.get_base = function() return BASE; end

-- The environment store, as the game makes it: kernel32 only, under VANTAGE_PATTERNS.
local environment, calls = {}, {};
local fake = { os = 'Windows', C = {} };
fake.cdef = function(text) calls[#calls + 1] = text; end;
fake.new = function(kind, count) assert(kind == 'char[?]' and count == 32768); return { count = count }; end;
fake.string = function(buffer, length) return buffer.text:sub(1, length); end;
fake.C.GetEnvironmentVariableA = function(name, buffer, count)
    local value = environment[name];
    if not value then return 0; end
    if #value >= count then return #value + 1; end
    buffer.text = value;
    return #value;
end;
fake.C.SetEnvironmentVariableA = function(name, value) environment[name] = value; return 1; end;
fake.C.GetCurrentProcessId = function() return 4321; end;
local made = patterns._environment(fake);
assert(patterns._NAME == 'VANTAGE_PATTERNS' and #calls == 3);
for _, text in ipairs(calls) do assert(text:find('__stdcall', 1, true), 'Each kernel32 call is declared on its own.'); end
assert(made.read() == nil and made.process() == 4321);
assert(made.write('1;abc') and environment.VANTAGE_PATTERNS == '1;abc' and made.read() == '1;abc');
environment.VANTAGE_PATTERNS = string.rep('x', 40000);
assert(made.read() == nil, 'A value longer than the buffer is ignored.');
fake.os = 'Linux';
assert(patterns._environment(fake) == nil);
-- And over the real ffi, under a name of its own that is removed again.
package.loaded.ffi = nil;
local real = require('ffi');
package.loaded.ffi = mocked;
local NAME = 'VANTAGE_PATTERNS_SELF_TEST';
local live = patterns._environment(real, NAME);
local ok, problem = pcall(function()
    assert(live.read() == nil, 'The test name starts unset.');
    assert(live.write('1;4d2;10000000;400;t.a.00000000=10000010'));
    assert(live.read() == '1;4d2;10000000;400;t.a.00000000=10000010', 'The process environment keeps the text.');
    assert(type(live.process()) == 'number' and live.process() > 0);
end);
real.C.SetEnvironmentVariableA(NAME, nil);
assert(ok, problem);
assert(live.read() == nil, 'The test name is removed again.');

-- A warmup step runs its work once, timed under its name, and does nothing after that, even after an error.
fresh();
local done, runs = {}, 0;
local step = patterns.step('t.step', done, function() runs = runs + 1; end);
assert(step.name == 't.step' and type(step.run) == 'function');
step.run(); step.run();
assert(runs == 1 and done['t.step'] and stages['t.step'] == 1, 'Once, and timed once.');
local fails = patterns.step('t.fails', done, function() runs = runs + 1; error('step failed', 0); end);
local first, issue = pcall(fails.run);
assert(not first and issue == 'step failed' and stages['t.fails'] == 1);
assert(pcall(fails.run) and runs == 2 and stages['t.fails'] == 1, 'A failed step is reported once.');
patterns._set_performance(nil);
local quiet = patterns.step('t.quiet', {}, function() runs = runs + 1; end);
quiet.run();
assert(runs == 3 and stages['t.quiet'] == nil, 'Without timings a step still runs.');
return 'Client patterns: one finder, owner rules, kept for the game session';
