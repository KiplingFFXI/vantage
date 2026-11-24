-- A 0x00D, a player's update, comes many times a second in a town, overhead icons on or off. The icons take only its
-- server id, index and flags from it, so those are read where the packet is: each read of an event's data copies the
-- whole packet. A 0x00E reads its data, as it has more to give.
local overhead = require('core.overhead');

-- An update for unit at index, with update flags at 0x0A and a claimer at 0x2C, that counts the reads of its data.
-- size, when given, is the size the event says it has.
local function counted(id, unit, index, flags, claimer, size)
    local bytes = MOCK.bytes(0x48);
    MOCK.put(bytes, 4, 4, unit); MOCK.put(bytes, 8, 2, index); bytes[0x0A] = flags; MOCK.put(bytes, 0x2C, 4, claimer or 0);
    local characters = {};
    for i = 0, bytes.n - 1 do characters[#characters + 1] = string.char(bytes[i]); end
    local values = { id = id, size = size or bytes.n, data_raw = bytes, data = table.concat(characters), injected = false, blocked = false };
    local reads = 0;
    local event = newproxy(true);
    getmetatable(event).__index = function(_, key)
        if key == 'data' then reads = reads + 1; end
        return values[key];
    end;
    return event, function() return reads; end;
end

local MOB = 0x1000102;
local claim, reads = counted(0x00E, MOB, 0x102, 0x02, 1001);
overhead.packet(claim);
assert(overhead._claimer(MOB) == 1001 and reads() == 1, 'An 0x00E reads its data once, and its claim bit names the claimer.');
-- A 0x00D too short to hold its flags is left alone.
local short;
short, reads = counted(0x00D, MOB, 0x102, 0x20, 0, 0x0A);
overhead.packet(short);
assert(overhead._claimer(MOB) == 1001 and reads() == 0, 'A 0x00D too short for its flags changes nothing and copies nothing.');
-- The despawn bit of a 0x00D forgets the unit, read from the packet where it is.
local gone;
gone, reads = counted(0x00D, MOB, 0x102, 0x20);
overhead.packet(gone);
assert(overhead._claimer(MOB) == nil, 'A 0x00D with its despawn bit forgets the unit.');
assert(reads() == 0, 'A 0x00D is read without copying it: its data was read ' .. reads() .. ' times.');
-- With the data read already, as for a packet the observer takes too, that copy is what is read.
overhead.packet(claim);
local handed;
handed, reads = counted(0x00D, MOB, 0x102, 0x20);
local size, data = require('core.client').packet_size(handed);
overhead.packet(handed, size, data);
assert(overhead._claimer(MOB) == nil and reads() == 1, 'A copy handed in is the only one.');
return 'A player update is read without copying it';
