-- A crowded fight sends tens of 0x028 a second. Each decode fills the same action, its list of results and the same
-- result rows again, as observer.read reads them within the packet's callback and keeps nothing of them. A row read
-- before has nothing left of it: an added effect, a reaction or a spell's recast that this packet doesn't send reads as
-- none. So a decode makes nothing. Measured as test_party_strip_allocation.lua does, with the collector stopped and the
-- compiler off.
local observer, client = require('core.observer'), require('core.client');
local STRANGER, MOB = 1500, 0x1000301;
-- A 0x028 from actor on one target, a result for each { message, param, added, added param, reaction, reaction param,
-- reaction kind }, with its added effect and reaction when it has them. A spell gives its recast.
local function action(actor, category, id, target, rows, recast)
    local results = {};
    for i, row in ipairs(rows) do
        results[i] = { message = row[1], param = row[2], added = row[3], added_param = row[4], reaction = row[5], reaction_param = row[6],
            reaction_kind = row[7] };
    end
    return MOCK.packet(0x028, MOCK.action_bytes(actor, category, id, { { id = target, rows = results } }, recast));
end
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

-- A stranger hits a mob twice for 40 (1), the first with an added effect of Paralysis (160, 4) and a counter (33) for 12.
local rich = action(STRANGER, 1, 0, MOB, { { 1, 40, 160, 4, 33, 12, 1 }, { 1, 40 } });
local plain = action(STRANGER, 1, 0, MOB, { { 1, 40 }, { 1, 40 } });
-- A spell with its recast, then a melee round with none.
local spell = action(STRANGER, 4, 144, MOB, { { 2, 120 } }, 9);
local rich_size, plain_size, spell_size = client.packet_size(rich), client.packet_size(plain), client.packet_size(spell);

local decoded = garbage(function() observer.decode(plain, plain_size); observer.decode(rich, rich_size); end);
assert(decoded < 16, ('Two decodes make %.0f bytes; none expected'):format(decoded));

local first = observer.decode(rich, rich_size);
assert(first and first.actor == STRANGER and first.category == 1 and #first.rows == 2, 'Fixture: the round decodes, two results.');
local row = first.rows[1];
assert(row.target == MOB and row.param == 40 and row.message == 1 and row.added == 160 and row.added_param == 4
    and row.reaction == 33 and row.reaction_param == 12 and row.reaction_kind == 1, 'Fixture: the first result has it all.');
local second = observer.decode(plain, plain_size);
assert(second == first, 'The next decode fills the same action.');
row = second.rows[1];
assert(#second.rows == 2 and row.param == 40 and row.added == nil and row.added_param == nil and row.reaction == nil
    and row.reaction_param == nil and row.reaction_kind == nil, 'A result read before has nothing left of the last packet.');
local cast = observer.decode(spell, spell_size);
assert(cast.category == 4 and cast.id == 144 and cast.recast == 9 and #cast.rows == 1 and cast.rows[1].message == 2,
    'Fixture: a spell with its recast.');
assert(observer.decode(plain, plain_size).recast == nil and #observer.decode(plain, plain_size).rows == 2,
    'A round after a spell has no recast.');
-- A packet cut short gives nothing, and the next one reads whole.
local short = action(STRANGER, 1, 0, MOB, { { 1, 40 }, { 1, 40 } });
assert(observer.decode(short, 25) == nil, 'A packet cut short gives nothing.');
local after = observer.decode(rich, rich_size);
assert(after and #after.rows == 2 and after.rows[1].added == 160 and after.rows[2].added == nil, 'The next packet reads whole.');
