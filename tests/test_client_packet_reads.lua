-- Each read of an Ashita event's data copies the packet, so the observer and the client copy a packet once and hand
-- the copy on. Your 0x037 says whether your status icons changed. An id no index answers is looked for once a refresh.
local client = require('core.client');
local observer = require('core.observer');
local snapshot = { valid = true, id = 1001, zone = 102, job = 1, party = {}, entities = {} };

-- A packet that counts the reads of its data.
local function counted(id, bytes)
    local characters = {};
    for i = 0, bytes.n - 1 do characters[#characters + 1] = string.char(bytes[i] or 0); end;
    local values = { id = id, size = bytes.n, data_raw = bytes, data = table.concat(characters), injected = false, blocked = false };
    local reads = 0;
    local event = newproxy(true);
    getmetatable(event).__index = function(_, key)
        if key == 'data' then reads = reads + 1; end;
        return values[key];
    end;
    return event, function() return reads; end;
end;

for _, id in ipairs({ 0x00E, 0x028, 0x029, 0x037, 0x063, 0x068, 0x076, 0x08C }) do
    local event, reads = counted(id, MOCK.bytes(256));
    observer.read(event, 1, snapshot);
    assert(reads() == 1, 'The observer copies a packet once: ' .. id .. ' was copied ' .. reads() .. ' times.');
    event, reads = counted(id, MOCK.bytes(256));
    local size, data = client.packet_size(event);
    observer.read(event, 1, snapshot, size, data);
    assert(size == 256 and reads() == 1, 'A copy handed to the observer is the only one: ' .. id);
end;
local quiet = MOCK.packet(0x063, MOCK.bytes(8));
local first, second = observer.read(quiet, 1, snapshot), observer.read(quiet, 1, snapshot);
assert(first == second and next(first) == nil, 'A packet with nothing to report hands back one shared empty list.');

-- Phoenix sends your 0x037 after any HP, MP or TP change too, so only its 32 icons say your effects changed.
local icons = MOCK.bytes(0x60);
client.reset(); client.icons_changed();
client.accept(MOCK.packet(0x037, icons), 1, snapshot);
assert(client.icons_changed() and not client.icons_changed(), 'The first status packet changes the icons, once.');
client.accept(MOCK.packet(0x037, icons), 2, snapshot);
assert(not client.icons_changed(), 'One with the same icons changes nothing.');
icons[0x30] = 7;
client.accept(MOCK.packet(0x037, icons), 3, snapshot);
assert(not client.icons_changed(), 'Its other fields changing is no icon change.');
icons[4 + 5] = 33;
client.accept(MOCK.packet(0x037, icons), 4, snapshot);
assert(client.icons_changed(), 'A new effect in a slot is a change.');
icons[0x4C + 1] = 4;
client.accept(MOCK.packet(0x037, icons), 5, snapshot);
assert(client.icons_changed(), 'A change in an effect\'s top two bits is a change.');
local zone_in = MOCK.bytes(52); MOCK.put(zone_in, 4, 4, 1001); MOCK.put(zone_in, 0x30, 2, 102);
client.accept(MOCK.packet(0x00A, zone_in), 6, snapshot);
client.accept(MOCK.packet(0x037, icons), 7, snapshot);
assert(client.icons_changed(), 'After a zone change the first status packet is a change again.');
client.reset();

-- A mob out of view is looked for at both of its indexes, and then not again until the next refresh.
local lookups, here = 0, nil;
local entities = {
    GetServerId = function(_, index) lookups = lookups + 1; return index == here and 0x1000123 or 0; end,
    GetSpawnFlags = function() return 0x10; end,
};
local MOB = 0x1000123;
local missed = client.resolve(MOB, nil, entities);
local count = lookups;
assert(missed.id == MOB and missed.kind == 'monster' and missed.name == nil and count == 2,
    'A mob out of view is looked for at both of its indexes: ' .. count);
assert(client.resolve(MOB, nil, entities) == missed and lookups == count, 'Until the next refresh it is not looked for again.');
client.read(2, {});
here = 0x123;
local found = client.resolve(MOB, nil, entities);
assert(found ~= missed and found.index == 0x123 and found.kind == 'monster', 'The next refresh looks again and finds it in view.');
here = nil; client.reset();
for i = 1, 300 do client.resolve(0x1000000 + i, nil, entities); end;
count = lookups;
client.resolve(0x1000000 + 300, nil, entities);
assert(count >= 300 and lookups == count, 'The misses kept are bounded and the newest stay.');
assert(#MOCK.commands == 0);
