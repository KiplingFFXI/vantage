-- A pass over the game's party list asks about each page region once, and keeps none of them for the next pass or for a
-- read outside one: the client frees memory between frames.
local native = require('core.native_party_ui');
local memory, freed = {}, {};
local queries, reads = 0, 0;
local REGION = 0x1000;
local function read(ptr) reads = reads + 1; return memory[ptr]; end
local function setup(regions)
    memory, freed, queries, reads = {}, {}, 0, 0;
    native._set_platform({
        valid = function(ptr, size, write)
            assert(not write, 'The party list is only read.');
            queries = queries + 1;
            local first = ptr - ptr % REGION;
            if freed[first] then return false; end
            if not regions then return true; end
            return ptr + size <= first + REGION, first, first + REGION;
        end,
        read32 = read, read8 = read,
        find = function(pattern, occurrence)
            if occurrence == 1 then return 0; end
            return pattern:sub(1, 2) == '6D' and 0x12000 or pattern:sub(1, 2) == '66' and 0x10000 or 0x11000;
        end,
    });
end
-- The Treasure Pool's lot window, open: its slot, container, primitive and header each in a region of its own.
local slot, container, ptr, header = 0x21000, 0x70000, 0x71000, 0x72000;
local function open_treasure()
    memory[0x12000 + 0x20], memory[0x12000 + 0x78] = slot, 0x22000;
    memory[slot], memory[0x22000] = container, 0;
    memory[container + 8], memory[ptr + 0x0C], memory[ptr + 4] = ptr, container, header;
    memory[header + 0x46], memory[header + 0x4A], memory[header + 0x4E], memory[header + 0x52] = 0x756E656D, 0x20202020, 0x746F6F6C, 0x20202020;
    memory[ptr + 0x69], memory[ptr + 0x6A] = 1, 1;
end

-- Once the registry is found, a pass reads 10 values in 4 regions.
setup(true);
open_treasure();
assert(native.treasure_open() == true, 'Fixture: the pool reads as open.');
queries, reads = 0, 0;
assert(native.treasure_open() == true, 'The pool still reads as open.');
assert(reads == 10 and queries == 4, ('A pass asks once for each region: %d reads, %d queries.'):format(reads, queries));

-- A platform that doesn't say where a region stops checks each read, as these reads always did.
setup(false);
open_treasure();
native.treasure_open();
queries, reads = 0, 0;
assert(native.treasure_open() == true, 'Fixture: the pool reads as open without regions.');
assert(queries == reads, 'Each read is checked when no region is known.');

-- The next pass asks again, so a region freed since the last one reads as nothing.
setup(true);
open_treasure();
assert(native.treasure_open() == true, 'Fixture: the pool reads as open before the free.');
freed[ptr] = true;
assert(native.treasure_open() == nil, 'A region freed between passes is not read.');
freed[ptr] = nil;
assert(native.treasure_open() == true, 'A region mapped again is read again.');

-- A read past a region's end is asked about on its own.
setup(true);
open_treasure();
native.treasure_open();
memory[slot], memory[container + REGION + 8] = container + REGION, ptr;
memory[container + REGION + 8], memory[ptr + 0x0C] = ptr, container + REGION;
assert(native.treasure_open() == true, 'A container in the next region is read.');
freed[container + REGION] = true;
assert(native.treasure_open() == nil, 'One region having been checked says nothing about the next.');

-- A warmup step's reads are outside any pass: each checks its own page, and nothing stays for the next one.
setup(true);
open_treasure();
local steps = native.warmup_steps();
steps[1].run(); steps[2].run();
queries, reads = 0, 0;
steps[3].run();
assert(reads == 2 and queries == 2, 'A warmup step checks each of its reads.');
queries, reads = 0, 0;
assert(native.treasure_open() == true, 'The pool reads as open after the warmup.');
assert(queries == 4, 'A pass after the warmup finds no region kept from it.');
native._set_platform(nil);
