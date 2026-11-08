-- Every client pattern owner (core/clock.lua, client.lua, chat.lua, native_party_ui.lua and name_anchor.lua) on the
-- decoded 04288488 client: its warmup steps, one search each, find what its one-shot load finds, and an
-- /addon reload in the same game process searches nothing and gets the same addresses. A changed pattern, or one
-- whose bytes changed, is searched again alone, and the clock never calls an address that failed its check.
local fixture = require('client_image_fixture');
local image = fixture.load('new'):install();
local store = MOCK.pattern_store();
local ffi = package.loaded.ffi;
local casts = {};
ffi.typeof = function(name) if not ffi.declared then error('not declared'); end; return name; end;
ffi.cdef = function(source) ffi.declared = source; end;
ffi.cast = function(kind, at) casts[#casts + 1] = { kind = kind, at = at }; return function() return 1000; end; end;
package.preload['core.chat'] = nil;
local OWNERS = { 'core.patterns', 'core.clock', 'core.client', 'core.chat', 'core.native_party_ui', 'core.name_anchor' };
local patterns, clock, client, chat, native, anchor;
local stages = {};
local timing = { now = function() return MOCK.now * 1000; end,
    record = function(stage) stages[stage] = (stages[stage] or 0) + 1; return true; end };

-- A new load of every owner, as /addon reload makes, over the image now installed and the same environment.
local function fresh(memory_image)
    for _, name in ipairs(OWNERS) do package.loaded[name] = nil; end
    patterns = require('core.patterns');
    patterns._set_store(store);
    patterns._set_performance(timing);
    local function contains(at, size) return memory_image:contains(at, size); end
    patterns._set_pages(contains);
    clock, client, chat = require('core.clock'), require('core.client'), require('core.chat');
    native, anchor = require('core.native_party_ui'), require('core.name_anchor');
    client._set_pages(function(at, size) return contains(at, size); end);
    anchor._set_pages(contains);
    chat._set_backend({
        range = function() return memory_image.base, #memory_image.data; end,
        find = function(pattern, usage) return ashita.memory.find('FFXiMain.dll', 0, pattern, 0, usage); end,
        read = function(at, size) return memory_image:bytes(at, size); end,
    });
    native._set_platform({
        valid = function(at, size) return contains(at, size); end,
        find = function(pattern, usage) return ashita.memory.find(':ffximain', 0, pattern, 0, usage); end,
        read32 = ashita.memory.read_uint32, read8 = ashita.memory.read_uint8,
    });
    stages, casts = {}, {};
    memory_image.finds = 0;
end

local function steps()
    local list = {};
    for _, owner in ipairs({ clock, client, chat, native, anchor }) do
        for _, step in ipairs(owner.warmup_steps()) do list[#list + 1] = step; end
    end
    return list;
end

local function snapshot()
    local status, out = anchor.status(), {};
    for name, value in pairs(status.patterns) do out[name] = value; end
    local timers = clock.status();
    out.game_time = timers.game_time;
    for name, value in pairs(anchor._offsets) do out['offset ' .. name] = value; end
    return out;
end

-- The steps, in order, each one search of its own.
fresh(image);
local names, expected = {}, { 'clock.game_time', 'client.pointers', 'chat.table', 'chat.scale',
    'party.list_1', 'party.list_2', 'party.treasure' };
local sorted = {};
for name in pairs(anchor._patterns) do sorted[#sorted + 1] = name; end
table.sort(sorted);
for _, name in ipairs(sorted) do expected[#expected + 1] = 'name_anchor.' .. name; end
expected[#expected + 1] = 'name_anchor.operands';
local per_step = {};
for _, step in ipairs(steps()) do
    names[#names + 1] = step.name;
    local before = image.finds;
    assert(not anchor.usable(), 'No name point before the last step.');
    step.run();
    per_step[step.name] = image.finds - before;
end
assert(table.concat(names, ' ') == table.concat(expected, ' '), 'The warmup steps, in order: ' .. table.concat(names, ' '));
for name, count in pairs(per_step) do
    local want = name == 'client.pointers' and 3 or name == 'name_anchor.operands' and 0 or 2;
    assert(count == want, ('%s searches %d times, not %d'):format(name, count, want));
end
assert(image.finds == 47, 'A cold load searches 47 times: ' .. image.finds);
assert(anchor.usable() and clock.available() and client.capabilities().timers and chat.status().loaded,
    'Everything the image has is found.');
for _, name in ipairs(expected) do assert(stages[name] == 1, 'Each step is timed once: ' .. name); end
for _, owner in ipairs({ 'clock', 'client', 'chat', 'party', 'name_anchor' }) do
    assert(stages['patterns.' .. owner], 'Each owner\'s finds are timed: ' .. owner);
end
assert(stages['patterns.first'] == 25 and stages['patterns.unique'] == 22, 'First searches and second searches are timed apart.');
local cold, capabilities = snapshot(), client.capabilities();
assert(cold.game_time and casts[1].at == cold.game_time);
local finds = image.finds;
for _, step in ipairs(steps()) do step.run(); end
assert(clock.load() == nil and client.load() == nil and chat.load() and anchor.load() and image.finds == finds,
    'A step that ran does nothing again, and neither do the one-shot loads.');
assert(stages['clock.game_time'] == 1, 'Nor is it timed again.');
local cameras = anchor.cameras();
assert(cameras.usable and image.finds == finds + 14, 'The camera check finds its seven at the first report.');
local text = store.text;
assert(text and select(2, text:gsub('=', '')) == 32, 'All 32 addresses are kept.');

-- A reload: no search at all, the same addresses, nothing written.
fresh(image);
local writes = store.writes;
for _, step in ipairs(steps()) do step.run(); end
assert(anchor.cameras().usable);
assert(image.finds == 0, 'A reload in the same game process searches nothing: ' .. image.finds);
local again = snapshot();
for key, value in pairs(cold) do assert(again[key] == value, 'The same ' .. key); end
assert(casts[1].at == cold.game_time, 'The clock calls the same function.');
assert(store.writes == writes and store.text == text);
assert(stages['patterns.first'] == nil and stages['patterns.verify'] == 32 and stages['name_anchor.lift'] == 1);
for key, value in pairs(capabilities) do assert(client.capabilities()[key] == value, 'The same flags: ' .. key); end
assert(chat.status().loaded);

-- The one-shot loads reuse them the same way.
fresh(image);
assert(clock.available() and anchor.load() and chat.load() and client.capabilities().timers and image.finds == 0);
assert(native.treasure_open() ~= true and image.finds == 0);

-- A changed pattern is searched again, alone.
fresh(image);
anchor._patterns.lift = 'FF93B4000000??FF0000008BCE50FF93C4010000D986????????';
for _, step in ipairs(steps()) do step.run(); end
assert(image.finds == 2 and anchor.usable() and snapshot().lift == cold.lift, 'Only the changed pattern is searched: ' .. image.finds);
assert(store.writes == writes + 1);

-- The game time function's bytes changed in place: it is searched again, and nothing is called.
local changed = image:copy();
changed:install();
changed:write(cold.game_time, '\0');
fresh(changed);
for _, step in ipairs(steps()) do step.run(); end
assert(changed.finds == 1, 'Only the game time function is searched again: ' .. changed.finds);
assert(not clock.available() and clock.status().problem == 'The game time function is missing.');
for _, cast in ipairs(casts) do assert(cast.kind ~= 'vg_game_time_f', 'An address that failed its check is never called.'); end
assert(not client.capabilities().timers and anchor.usable());
image:install();

-- Garbage in the environment: everything is searched again, as on a cold load.
store.text = 'not a pattern list';
fresh(image);
for _, step in ipairs(steps()) do step.run(); end
assert(image.finds == 47 and anchor.usable() and clock.available());
return 'Client patterns kept for the game session and found again on reload';
