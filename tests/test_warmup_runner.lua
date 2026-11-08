-- core/warmup.lua on its own, over a clock the test moves: the steps run in their listed order from the second
-- Present after the load, at least one a Present and new ones only while the Present has spent under 8 ms of them.
-- A deferred group waits until something wants it, and only the groups the displays wait for hold the displays back.
-- The displays first draw in the Present after the one their last step ran in, and that Present runs no step. An
-- early ask lets them draw until the first refresh that reads the settings asks for more. A step that fails is said
-- once in plain words and skipped; the report keeps its name and why. Nothing runs a step inside another. A restart
-- runs a group again and the displays wait for it again. Without a clock every wanted step runs at once. A reload's
-- unload times reach the next load through the store once, and only while fresh.
local clock, records, added = 0, {}, {};
local timing = {
    origin_ms = 1000000,
    now = function() return clock; end,
    record = function(stage, started)
        assert(type(started) == 'number' and started <= clock, 'A stage ends after it starts: ' .. tostring(stage));
        records[#records + 1] = { stage = stage, ms = clock - started };
        return true;
    end,
    add = function(stage, ms) added[stage] = ms; return true; end,
};
package.loaded['core.performance'] = timing;
package.loaded['core.warmup'] = nil;
local warmup = require('core.warmup');
local BUDGET = warmup._BUDGET;
assert(BUDGET == 8, 'The budget is 8 ms a Present.');

local ran, said = {}, {};
local function say(line) said[#said + 1] = line; end
local function step(name, cost, work)
    return { name = name, run = function() ran[#ran + 1] = name; clock = clock + cost; if work then work(); end end };
end
local function recorded(stage)
    local count = 0;
    for _, entry in ipairs(records) do if entry.stage == stage then count = count + 1; end end
    return count;
end
-- One Present: its steps and what they cost, then 16 ms to the next.
local function present()
    local before, began = #ran, clock;
    warmup.frame(began);
    local names = {};
    for index = before + 1, #ran do names[#names + 1] = ran[index]; end
    local spent = clock - began;
    warmup.frame_end();
    clock = clock + 16;
    return names, spent;
end
-- Every string in a table, nested.
local function strings(value, out)
    out = out or {};
    if type(value) == 'string' then out[#out + 1] = value;
    elseif type(value) == 'table' then for key, child in pairs(value) do strings(key, out); strings(child, out); end end
    return out;
end

-- The order, the first Present, at least one step a Present and the budget.
warmup.start({
    { group = 'start', steps = { step('a1', 3), step('a2', 3) } },
    { group = 'assets', steps = { step('b1', 2), step('b2', 12), step('b3', 1), step('b4', 1) } },
    { group = 'later', deferred = true, steps = { step('c1', 1) }, note = 'Runs once a look wants it.' },
    { group = 'names', deferred = true, displays = false, steps = { step('n1', 5), step('n2', 5), step('n3', 1) } },
}, say);
assert(#ran == 0 and not warmup.ready(), 'With a clock the load runs no step, and the displays wait.');
local first = present();
assert(#first == 0 and recorded('load.first_present') == 1, 'The first Present runs no step: it is still the load\'s.');
-- Its refresh asks for what the settings draw with.
warmup.asked();
local largest, frames = 12, {};
while warmup.pending('start') or warmup.pending('assets') do
    local names, spent = present();
    frames[#frames + 1] = table.concat(names, ' ');
    assert(#names >= 1, 'Every Present runs at least one step while some are left.');
    assert(spent < BUDGET + largest, ('A Present spends under the budget and the largest step: %s ms'):format(spent));
end
assert(table.concat(frames, ', ') == 'a1 a2 b1, b2, b3 b4', 'In order, 8 ms a Present: ' .. table.concat(frames, ', '));
assert(not warmup.ready(), 'The displays don\'t draw in the Present their last step ran in.');
assert(recorded('warmup.frame') == 3 and recorded('warmup.total') == 1, 'Each Present\'s steps and the whole warmup are timed.');
local names = present();
assert(#names == 0 and warmup.ready(), 'The displays draw from the next Present, once every group they wait for has run.');
names = present();
assert(#names == 0, 'A deferred group runs nothing until it is wanted.');
local report = warmup.report();
assert(report.spread and report.ready and #report.steps == 6 and report.steps[1].name == 'a1' and report.steps[1].present == 2,
    'The report lists each step, what it cost and the Present it ran in.');
assert(#report.later == 2 and report.later[1].group == 'later' and report.later[1].note == 'Runs once a look wants it.'
    and report.later[2].group == 'names' and report.later[2].steps == 3, 'The report says what is still to run, and when.');
assert(report.displays_ready_present == 5 and report.displays_ready_ms and report.finished_ms,
    'The report says when the displays could draw.');

-- Wanting a group runs nothing now; the next Presents do. A wanted group the displays wait for after they opened
-- holds nothing back: what needs it asks for it itself.
warmup.want('later');
assert(#ran == 6 and warmup.pending('later') and warmup.ready(), 'Wanting runs nothing in the caller, and the displays stay open.');
assert(warmup.need('names') == true and #ran == 6, 'Needing with a clock runs nothing in the caller and says it waits.');
assert(table.concat(present(), ' ') == 'c1 n1 n2', 'The wanted groups run on the next Present, in order.');
assert(warmup.need('names') == true and table.concat(present(), ' ') == 'n3' and warmup.need('names') == false,
    'A group needed is done once its last step ran.');
local ended = clock - 16;
assert(#present() == 0 and #warmup.report().later == 0, 'Nothing is left.');
-- The warmup's end moves to the end of its last work, a group asked for later included; a Present with nothing to run
-- leaves it.
assert(warmup.report().finished_ms == ended and ended > report.finished_ms and recorded('warmup.total') == 2,
    'The warmup ends with the last group\'s last step, timed again: ' .. tostring(warmup.report().finished_ms));
-- A group run at once on its own (the zone-in packet's XI View) moves it too, once nothing else is left.
ran = {};
local loaded = clock;
warmup.start({ { group = 'assets', steps = { step('p', 1) } }, { group = 'later', deferred = true, steps = { step('q', 3) } } }, say);
warmup.asked();
present(); present(); present();
local before = warmup.report().finished_ms;
warmup.want('later');
assert(warmup.drain('later') and table.concat(ran, ' ') == 'p q' and warmup.report().finished_ms == clock - loaded
    and warmup.report().finished_ms > before and recorded('warmup.total') == 4, 'A group drained on its own ends the warmup again.');

-- The Present that runs the displays' last step goes on to its budget with steps they don't wait for; the next, the
-- one they first draw in, runs none; the one after goes on.
ran = {};
warmup.start({
    { group = 'assets', steps = { step('x', 3), step('y', 3) } },
    { group = 'names', displays = false, steps = { step('n1', 1), step('n2', 1), step('n3', 1) } },
}, say);
present();
warmup.asked();
assert(table.concat(present(), ' ') == 'x y n1 n2' and not warmup.ready(), 'The displays\' last step\'s Present goes on to its budget.');
assert(#present() == 0 and warmup.ready(), 'The Present they first draw in runs no step.');
assert(table.concat(present(), ' ') == 'n3', 'The next one goes on.');

-- Until the first refresh has asked for what the settings draw with, the displays wait even with every wanted step
-- run, as a drain before it does; Presents still run what is wanted. Once asked, what it asked for is waited for too.
ran = {};
warmup.start({ { group = 'assets', steps = { step('p', 1) } }, { group = 'later', deferred = true, steps = { step('q', 1) } } }, say);
assert(warmup.drain() and table.concat(ran, ' ') == 'p' and not warmup.ready(), 'A drain before it lets nothing draw.');
present();
assert(not warmup.ready(), 'Nor does the first Present.');
warmup.want('later');
warmup.asked();
assert(not warmup.ready(), 'Once asked, what it asked for is waited for.');
assert(table.concat(present(), ' ') == 'q' and not warmup.ready(), 'Its step runs, and the displays wait for the next Present.');
assert(#present() == 0 and warmup.ready(), 'Then they draw.');
ran = {};
warmup.start({ { group = 'assets', steps = { step('p', 1) } } }, say);
present(); present();
assert(table.concat(ran, ' ') == 'p' and not warmup.ready(), 'A Present before it runs the steps, and nothing draws.');
warmup.asked();
assert(#present() == 0 and warmup.ready(), 'The Present after it draws, and runs no step.');

-- A command at the title screen asks early, before any settings can be read: the displays draw once every wanted
-- step has run. The first refresh that reads the settings asks for what those need, and the displays wait again for
-- its steps; nothing asked after that holds them back.
ran = {};
warmup.start({ { group = 'assets', steps = { step('p', 1) } }, { group = 'later', deferred = true, steps = { step('q', 1) } } }, say);
present();
assert(warmup.asked(true) == false and warmup.drain() and warmup.ready(), 'An early ask lets the displays draw.');
warmup.want('later');
assert(warmup.asked() == true and not warmup.ready(), 'The first refresh that reads the settings makes them wait again.');
assert(table.concat(present(), ' ') == 'q' and not warmup.ready(), 'Its step runs, and the displays wait for the next Present.');
assert(#present() == 0 and warmup.ready(), 'Then they draw again.');
assert(warmup.asked() == false and warmup.asked(true) == false and warmup.ready(), 'Later asks hold nothing back.');
ran = {};
warmup.start({ { group = 'assets', steps = { step('p', 1) } } }, say);
present();
warmup.asked(true);
warmup.drain();
assert(warmup.ready() and warmup.asked() == false and warmup.ready(), 'With nothing more to wait for they go on drawing.');

-- A step that fails is said once, skipped, and the displays still open; again after a restart, it isn't said again.
-- Chat gets what failed in plain words; the report keeps the step's name and why.
ran, said, records = {}, {}, {};
warmup.start({
    { group = 'assets', what = 'the client art', steps = { step('ok1', 1),
        { name = 'broken', run = function() error('The file could not be read.', 0); end }, step('ok2', 1) } },
}, say);
warmup.asked();
present(); present();
assert(table.concat(ran, ' ') == 'ok1 ok2' and not warmup.ready() and #present() == 0 and warmup.ready(),
    'The other steps run and the displays open.');
assert(#said == 1 and said[1] == 'Part of Vantage could not load (the client art), so it goes on without it. /vg report has the reason.',
    'The failure is said once in plain words: ' .. tostring(said[1]));
assert(warmup.restart('assets') and not warmup.ready(), 'A restart makes the displays wait again.');
present(); present();
assert(#said == 1 and warmup.ready() and table.concat(ran, ' ') == 'ok1 ok2 ok1 ok2', 'It runs again and is not said again.');
report = warmup.report();
assert(#report.failed == 2 and report.failed[1].name == 'broken' and report.failed[1].problem == 'The file could not be read.'
    and report.restarts == 1, 'The report lists each failure with its step and why.');
assert(not warmup.restart('nothing'), 'A group not listed has nothing to restart.');
-- A part the load event made itself is said the same way, once; a step listed without words says no name at all.
warmup.fail('load.fonts', 'the fonts', 'attempt to index field \'?\' (a nil value)');
warmup.fail('load.fonts', 'the fonts', 'again');
assert(#said == 2 and said[2] == 'Part of Vantage could not load (the fonts), so it goes on without it. /vg report has the reason.',
    'A load part\'s failure is said once in plain words: ' .. tostring(said[2]));
warmup.start({ { group = 'start', steps = { { name = 'plain', run = function() error('boom', 0); end } } } }, say);
present(); present();
assert(#said == 3 and said[3] == 'Part of Vantage could not load, so it goes on without it. /vg report has the reason.',
    'Without words for it, no step name is said: ' .. tostring(said[3]));
assert(warmup.report().failed[1].name == 'plain' and warmup.report().failed[1].problem == 'boom', 'The report still has both.');
-- Two steps of one part that fail say it once; the report keeps each step and why.
said = {};
warmup.start({ { group = 'assets', what = 'the client art', steps = {
    { name = 'broken1', run = function() error('one', 0); end }, { name = 'broken2', run = function() error('two', 0); end } } } }, say);
warmup.asked();
present(); present();
assert(#said == 1 and said[1] == 'Part of Vantage could not load (the client art), so it goes on without it. /vg report has the reason.',
    'Two failures of one part are said once: ' .. table.concat(said, ' | '));
local failures = warmup.report().failed;
assert(#failures == 2 and failures[1].name == 'broken1' and failures[1].problem == 'one' and failures[2].name == 'broken2'
    and failures[2].problem == 'two', 'The report keeps both steps and why.');

-- Nothing runs inside a step: a drain or a Present from one does nothing, and a drain afterwards does the rest.
ran, said = {}, {};
local inner;
warmup.start({
    { group = 'start', steps = {
        step('outer', 1, function() inner = { warmup.drain(), #ran }; warmup.frame(clock); end),
        step('next', 1), step('last', 1) } },
}, say);
present(); present();
assert(inner[1] == false and inner[2] == 1, 'A drain inside a step runs nothing.');
assert(table.concat(ran, ' ') == 'outer next last', 'Each step runs once, in order.');
ran = {};
warmup.start({ { group = 'start', steps = { step('one', 6), step('two', 6), step('three', 6) } } }, say);
warmup.asked();
present(); present();
assert(#ran == 2 and warmup.drain() and table.concat(ran, ' ') == 'one two three' and warmup.ready(),
    'A drain runs what is left at once.');
assert(recorded('warmup.drain') >= 1 and warmup.report().drains == 1, 'A drain that ran something is timed and counted.');
assert(warmup.drain() and warmup.report().drains == 1, 'A drain with nothing left counts nothing.');

-- An unload: nothing runs after it and the displays are not held back.
ran = {};
warmup.start({ { group = 'start', steps = { step('one', 1), step('two', 1) } } }, say);
warmup.reset();
present(); present();
assert(#ran == 0 and warmup.ready() and warmup.drain() and #ran == 0, 'Nothing runs after an unload.');

-- The report: 32 Presents at most, and no question mark or unknown anywhere.
ran = {};
local many = {};
for index = 1, 40 do many[index] = step('s' .. index, 9); end
warmup.start({ { group = 'start', steps = many }, { group = 'later', deferred = true, steps = { step('x', 1) } } }, say);
for _ = 1, 45 do present(); end
report = warmup.report();
assert(#report.presents == 32 and #report.steps == 40 and report.presents[2].steps == 1 and report.presents[2].steps_ms == 9
    and report.presents[2].gap_ms == 16 and report.presents[2].handler_ms == 9,
    'The report keeps the first 32 Presents: the gap before each, its handler and its steps.');
for _, text in ipairs(strings(report)) do
    assert(not text:find('?', 1, true) and not text:lower():find('unknown', 1, true), 'The report never guesses: ' .. text);
end
assert(report.later[1].note == 'Not needed yet.', 'A group without a note of its own says it isn\'t needed yet.');

-- Without a clock nothing can be spread: the load runs every wanted step, a need runs its group in place, a want waits
-- for the next Present and a restart runs its group at once.
package.loaded['core.performance'] = nil;
package.preload['core.performance'] = function() error('No counter here.'); end;
ran = {};
warmup.start({
    { group = 'start', steps = { step('a', 20), step('b', 20) } },
    { group = 'later', deferred = true, steps = { step('c', 1) } },
    { group = 'names', deferred = true, displays = false, steps = { step('n', 1) } },
}, say);
assert(table.concat(ran, ' ') == 'a b' and warmup.ready(), 'Without a clock the load runs every wanted step.');
warmup.asked(true);
warmup.want('later');
assert(warmup.asked() == false and warmup.ready(), 'Without a clock an early ask makes nothing wait later.');
assert(warmup.need('later') == false and table.concat(ran, ' ') == 'a b c', 'A need runs its group where it is asked.');
warmup.want('names');
assert(#ran == 3, 'A want runs nothing in the caller.');
warmup.frame();
assert(table.concat(ran, ' ') == 'a b c n', 'The next Present runs it, before anything draws.');
assert(warmup.restart('start') and table.concat(ran, ' ') == 'a b c n a b' and warmup.ready(), 'A restart runs at once.');
report = warmup.report();
assert(not report.spread and report.note:find('no timing clock', 1, true) and #report.presents == 0,
    'The report says why every step ran at once.');
package.preload['core.performance'] = nil;
package.loaded['core.performance'] = timing;

-- A reload: the unload keeps its start and end, and the next load in the same game reads them once if fresh.
local store = MOCK.pattern_store(nil, 1234);
warmup._set_store(store);
clock = 100;
warmup.unloading();
clock = 112;
warmup.unloaded();
assert(store.text == '1;4d2;1000100.000;1000112.000', 'The unload keeps when it began and ended: ' .. tostring(store.text));
local function load_after(gap, text)
    store.text = text or store.text;
    timing.origin_ms = 1000112 + gap;
    added = {};
    warmup.start({}, say);
    warmup.reloaded();
    return warmup.report().reload;
end
local reload = load_after(250);
assert(reload and reload.unload_ms == 12 and reload.gap_ms == 250 and added['reload.unload'] == 12 and added['reload.gap'] == 250,
    'A load 250 ms after the unload times the unload and the gap.');
assert(store.text == nil, 'The kept times are taken away once read.');
assert(load_after(250) == nil and next(added) == nil, 'They are read once.');
local kept = '1;4d2;1000100.000;1000112.000';
for _, case in ipairs({
    { 6000, kept, 'older than 5 seconds' }, { 250, '1;4d3;1000100.000;1000112.000', 'from another game process' },
    { 250, 'not a time', 'garbage' }, { -50, kept, 'from after this load started' },
    { 250, '1;4d2;1000112.000;1000100.000', 'ending before it began' },
}) do
    assert(load_after(case[1], case[2]) == nil and next(added) == nil and store.text == nil, 'Times are ignored: ' .. case[3]);
end
warmup._set_store(nil);
assert(load_after(250, kept) == nil, 'Without the environment nothing is kept.');

-- core/performance.lua: when it loaded on the counter every Lua state shares, and a time measured elsewhere added.
local ticks = 5000000;
local fake = { declared = {}, C = {} };
fake.typeof = function(name) if not fake.declared[name] then error('not declared'); end; return name; end;
fake.cdef = function(source) for name in source:gmatch('}%s*([%w_]+)%s*;') do fake.declared[name] = true; end; end;
fake.new = function() return { low = 0, high = 0 }; end;
fake.C.QueryPerformanceFrequency = function(cell) cell.low, cell.high = 1000000, 0; return 1; end;
fake.C.QueryPerformanceCounter = function(cell) cell.low, cell.high = ticks % 4294967296, math.floor(ticks / 4294967296); return 1; end;
package.loaded['core.performance'] = nil;
local saved = package.loaded.ffi;
package.loaded.ffi = fake;
local performance = require('core.performance');
package.loaded.ffi = saved;
assert(performance.origin_ms == 5000, 'The module\'s load time on the shared counter, in ms: ' .. tostring(performance.origin_ms));
assert(performance.add('reload.gap', 250) and performance.add('reload.gap', 150), 'A measured time is added.');
assert(not performance.add('', 1) and not performance.add('reload.gap', -1) and not performance.add('reload.gap', 0 / 0),
    'A stage that isn\'t a name or a time that isn\'t one is refused.');
local gap = performance.snapshot().stages['reload.gap'];
assert(gap.count == 2 and gap.max == 250 and gap.last == 150 and gap.total == 400, 'It is kept as a recorded stage is.');
package.loaded['core.performance'] = nil;
return 'The warmup runs its steps in order within its budget';
