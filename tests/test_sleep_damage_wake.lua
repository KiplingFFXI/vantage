-- Through vantage.lua's packet handler: a 0x028 that only hits a mob is queued for the next refresh and doesn't wake
-- one early, as a fight sends many; one action that hits a mob several times is one hit; an action that lands an
-- effect still wakes a refresh at once. At that refresh the hit takes the mob's Sleep off.
local SELF, MOB = 1001, 0x1000123;
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local function putbits(bytes, offset, length, value)
    for i = 0, length - 1 do
        local at = offset + i;
        if math.floor(value / 2 ^ i) % 2 == 1 then bytes[math.floor(at / 8)] = bytes[math.floor(at / 8)] + 2 ^ (at % 8); end
    end
end
-- One row for each { message, param } on the mob.
local function action(actor, category, id, rows)
    local bytes, at = MOCK.bytes(512), 150;
    putbits(bytes, 40, 32, actor); putbits(bytes, 72, 6, 1); putbits(bytes, 82, 4, category); putbits(bytes, 86, 32, id);
    putbits(bytes, at, 32, MOB); putbits(bytes, at + 32, 4, #rows); at = at + 36;
    for _, row in ipairs(rows) do
        putbits(bytes, at + 27, 17, row[2]); putbits(bytes, at + 44, 10, row[1]); at = at + 87;
    end
    bytes.n = math.ceil(at / 8);
    return MOCK.packet(0x028, bytes);
end
assert(app.state.snapshot.valid and app.state.snapshot.id == SELF, 'Fixture: the player is in the game.');
app.state.snapshot.entities = app.state.snapshot.entities or {};
app.state.snapshot.entities[MOB] = { id = MOB, name = 'Goblin', kind = 'monster' };
local function packet(e)
    app.state.wake, app.state.queue = false, {};
    MOCK.fire('packet_in', e);
end
-- Sleep lands: that wakes a refresh.
packet(action(SELF, 4, 253, { { 236, 2 } }));
assert(app.state.wake and #app.state.queue == 1 and app.state.queue[1].kind == 'apply', 'A landing wakes a refresh.');
app.refresh(10);
local function sleeping()
    for _, row in ipairs(app.state.view.rows) do if row.entity_id == MOB and row.effect == 2 then return true; end end
    return false;
end
assert(sleeping(), 'Fixture: the mob sleeps.');
-- A round of three hits on it: one queued hit, and no early refresh.
packet(action(1002, 1, 0, { { 1, 20 }, { 67, 45 }, { 1, 18 } }));
assert(not app.state.wake, 'A hit alone waits for the next refresh.');
assert(#app.state.queue == 1 and app.state.queue[1].kind == 'damage' and app.state.queue[1].entity_id == MOB, 'The round is one hit.');
assert(sleeping(), 'Until then the Sleep shows.');
app.refresh(10.1);
assert(not sleeping(), 'The next refresh takes it off.');
return 'A hit on a mob is queued for the next refresh, once for each action';
