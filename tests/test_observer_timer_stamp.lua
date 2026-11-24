-- Each self application carries the client's 0x063 count at its packet's arrival. Packets in one datagram
-- arrive in order, so an application read before a 0x063 counts that 0x063 as after it.
local observer = require('core.observer');
local client = require('core.client');
local self_id, mob, ally = 1001, 0x1000010, 1002;
local snapshot = { valid = true, id = self_id, zone = 102, name = 'Tester', level = 75,
    self_effects = {}, party = { { id = ally, name = 'Ally' } }, entities = {
        [self_id] = { name = 'Tester' }, [mob] = { name = 'Crab' }, [ally] = { name = 'Ally' } } };
local function action(id, targets, actor)
    local rows = {};
    for i, target in ipairs(targets) do rows[i] = { id = target.id, rows = { { message = target.message or 230, param = target.param } } }; end
    return MOCK.packet(0x028, MOCK.action_bytes(actor, 4, id, rows));
end
local function timer_update()
    local bytes = MOCK.bytes(200); MOCK.put(bytes, 4, 2, 9);
    return MOCK.packet(0x063, bytes);
end

local start = client.self_timer_revision();
local haste = observer.read(action(57, { { id = self_id, param = 33 }, { id = ally, param = 33 } }, ally), 1, snapshot);
assert(#haste == 2 and haste[1].entity_id == self_id and haste[1].timer_revision == start,
    'A self application carries the count at its arrival.');
assert(haste[2].entity_id == ally and haste[2].timer_revision == nil, 'Another entity\'s does not.');
assert(#observer.read(timer_update(), 1, snapshot) == 0 and client.self_timer_revision() == start + 1,
    'The 0x063 read after it moves the count, so it is after the application.');
local protect = observer.read(action(43, { { id = self_id, param = 40 } }, self_id), 1.1, snapshot);
assert(protect[1].timer_revision == start + 1, 'An application after that 0x063 carries the new count.');
local bytes = MOCK.bytes(28);
MOCK.put(bytes, 4, 4, mob); MOCK.put(bytes, 8, 4, self_id); MOCK.put(bytes, 12, 4, 116); MOCK.put(bytes, 24, 2, 205);
local gained = observer.read(MOCK.packet(0x029, bytes), 1.2, snapshot);
assert(gained[1].kind == 'apply' and gained[1].entity_id == self_id and gained[1].timer_revision == start + 1,
    'A status gained without an action carries it too.');
-- A removal carries the count too: Phoenix sends an always-overwrite recast's wear-off with no 0x063
-- before its application, and an expiry's wear-off with that tick's status packets.
local erased = observer.read(action(143, { { id = self_id, param = 4, message = 341 } }, ally), 1.3, snapshot);
assert(erased[1].kind == 'remove' and erased[1].entity_id == self_id and erased[1].timer_revision == start + 1,
    'A removal carries the count.');
bytes = MOCK.bytes(28);
MOCK.put(bytes, 4, 4, self_id); MOCK.put(bytes, 8, 4, self_id); MOCK.put(bytes, 12, 4, 43); MOCK.put(bytes, 24, 2, 206);
local worn = observer.read(MOCK.packet(0x029, bytes), 1.4, snapshot);
assert(worn[1].kind == 'remove' and worn[1].effect == 43 and worn[1].timer_revision == start + 1, 'So does a wear-off message.');
bytes = MOCK.bytes(28);
MOCK.put(bytes, 4, 4, ally); MOCK.put(bytes, 8, 4, ally); MOCK.put(bytes, 12, 4, 43); MOCK.put(bytes, 24, 2, 206);
local other = observer.read(MOCK.packet(0x029, bytes), 1.5, snapshot);
assert(other[1].entity_id == ally and other[1].timer_revision == nil, 'Another entity\'s wear-off does not.');
