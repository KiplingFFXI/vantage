-- Raise, Raise II, Raise III and Arise finish with message 309 ('casts ... on') and give the raise level the
-- target accepts later (Phoenix raise*.lua, arise.lua: sendRaise). The observer reports who cast it.
local observer = require('core.observer');
local self_id, ally = 1001, 1002;
local snapshot = { valid = true, id = self_id, zone = 102, name = 'Tester', level = 75,
    self_effects = {}, party = { { id = ally, name = 'Ally' } }, entities = {
        [self_id] = { name = 'Tester' }, [ally] = { name = 'Ally' } } };
local function putbits(bytes, offset, length, value)
    for i = 0, length - 1 do
        local at = offset + i;
        if math.floor(value / 2 ^ i) % 2 == 1 then bytes[math.floor(at / 8)] = bytes[math.floor(at / 8)] + 2 ^ (at % 8); end
    end
end
local function action(id, target, actor, message, param)
    local bytes, at = MOCK.bytes(512), 150;
    putbits(bytes, 40, 32, actor); putbits(bytes, 72, 6, 1);
    putbits(bytes, 82, 4, 4); putbits(bytes, 86, 32, id);
    putbits(bytes, at, 32, target); putbits(bytes, at + 32, 4, 1); at = at + 36;
    putbits(bytes, at + 27, 17, param); putbits(bytes, at + 44, 10, message); at = at + 87;
    bytes.n = math.ceil(at / 8);
    return MOCK.packet(0x028, bytes);
end

for spell, level in pairs({ [12] = 1, [13] = 2, [140] = 3, [494] = 4 }) do
    local out = observer.read(action(spell, self_id, ally, 309, level), 1, snapshot);
    assert(#out == 1 and out[1].kind == 'raise' and out[1].entity_id == self_id and out[1].source == ally
        and out[1].source_name == 'Ally' and out[1].spell == spell and out[1].level == level, 'A raise cast is reported: ' .. spell);
end
local out = observer.read(action(264, self_id, ally, 309, 1), 1, snapshot);
assert(#out == 0, 'Tractor gives no raise.');
out = observer.read(action(12, ally, self_id, 309, 1), 1, snapshot);
assert(#out == 1 and out[1].entity_id == ally and out[1].source == self_id, 'A raise on someone else names them.');
