-- Most action packets in a busy zone are about strangers and tell Vantage nothing. Reading one makes nothing past its
-- decode: no closure for its results, and the list it hands back is the one it handed back before. Measured as
-- test_party_strip_allocation.lua does, with the collector stopped and the compiler off.
local observer, client = require('core.observer'), require('core.client');
local ME, STRANGER, MOB = 1001, 1500, 0x1000301;
local snapshot = { valid = true, id = ME, zone = 102, name = 'Aster', level = 75, job = 1, self_known = true, self_effects = {},
    party = {}, entities = { [ME] = { id = ME, name = 'Aster', kind = 'player' },
        [STRANGER] = { id = STRANGER, name = 'Stranger', kind = 'player' }, [MOB] = { id = MOB, name = 'Goblin', kind = 'monster' } } };
-- A 0x028 from actor on one target, a result for each { message, param } with no added effect or reaction.
local function action(actor, category, id, target, rows)
    local results = {};
    for i, row in ipairs(rows) do results[i] = { message = row[1], param = row[2] }; end
    return MOCK.packet(0x028, MOCK.action_bytes(actor, category, id, { { id = target, rows = results } }));
end
-- The bytes each call of run makes. A full collection shrinks the Lua stack and the next calls grow it back once, so a
-- few run after it, with the collector stopped, before counting starts.
local function garbage(run)
    for _ = 1, 50 do run(); end
    jit.off(); jit.flush();
    for _ = 1, 50 do run(); end
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    for _ = 1, 5 do run(); end
    local before = collectgarbage('count');
    for _ = 1, 1000 do run(); end
    local each = (collectgarbage('count') - before) * 1024 / 1000;
    collectgarbage('restart');
    jit.on();
    return each;
end

-- A stranger swings at a mob and misses twice (15), then hits it twice for 40 (1).
local miss, hits = action(STRANGER, 1, 0, MOB, { { 15, 0 }, { 15, 0 } }), action(STRANGER, 1, 0, MOB, { { 1, 40 }, { 1, 40 } });
local miss_size, miss_data = client.packet_size(miss);
local hits_size, hits_data = client.packet_size(hits);
assert(observer.decode(miss, miss_size) and #observer.decode(miss, miss_size).rows == 2, 'Fixture: the round decodes, two results.');
assert(#observer.read(miss, 1, snapshot, miss_size, miss_data) == 0, 'Fixture: two misses tell nothing.');
local struck = observer.read(hits, 1, snapshot, hits_size, hits_data);
assert(#struck == 1 and struck[1].kind == 'damage' and struck[1].entity_id == MOB, 'Fixture: two hits are one hit on the mob.');

local decoded = garbage(function() observer.decode(miss, miss_size); end);
local read = garbage(function() observer.read(miss, 1, snapshot, miss_size, miss_data); end);
assert(read - decoded < 48, ('A round that tells nothing makes %.0f bytes, %.0f past its decode; none expected'):format(read, read - decoded));
-- The count sees what a round makes: the two hits make their hit on the mob.
local hit = garbage(function() observer.read(hits, 1, snapshot, hits_size, hits_data); end);
assert(hit - read > 64, ('Two hits make %.0f bytes, two misses %.0f: the hit on the mob shows'):format(hit, read));
-- The list a round hands back is emptied for the next one, so what it found is read before the next packet.
local first = observer.read(hits, 1, snapshot, hits_size, hits_data);
assert(#first == 1 and first[1].kind == 'damage', 'Fixture: the hits read again.');
local second = observer.read(miss, 1, snapshot, miss_size, miss_data);
assert(second == first and #second == 0, 'The next round hands back the same list with only its own in it: ' .. #second);
return 'An action that tells nothing makes nothing past its decode';
