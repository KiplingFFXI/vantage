-- A geometry pass over the game's party list asks about each page region once, and the next pass asks again.
local native = require('core.native_party_ui');
local memory, freed, queries, reads = {}, {}, 0, 0;
local REGION = 0x1000;
local function read(ptr) reads = reads + 1; return memory[ptr]; end
native._set_platform({
    valid = function(ptr, size, write)
        assert(not write, 'The party list is only read.');
        queries = queries + 1;
        local first = ptr - ptr % REGION;
        if freed[first] then return false; end
        return ptr + size <= first + REGION, first, first + REGION;
    end,
    read32 = read, read8 = read,
    find = function(pattern, occurrence)
        if occurrence == 1 then return 0; end
        return pattern:sub(1, 2) == '6D' and 0x12000 or pattern:sub(1, 2) == '66' and 0x10000 or 0x11000;
    end,
});
local roots, pointers = { 0x20000, 0x20100, 0x20200 }, { 0x40000, 0x40100, 0x40200 };
memory[0x10000 + 0x19], memory[0x11000 + 1], memory[0x11000 + 7] = roots[1], roots[2], roots[3];
for i = 1, 3 do
    local container = 0x30000 + i * 0x100;
    memory[roots[i]], memory[container + 8] = container, pointers[i];
    memory[container], memory[pointers[i] + 0x0C] = 0x50000, container;
    memory[pointers[i]], memory[pointers[i] + 0x69], memory[pointers[i] + 0x6A] = 0, 1, 1;
    require('native_menu_fixture')(memory, container, pointers[i], i);
end
local roster, menu = { valid = true, members = { { id = 1001, group = 1, slot = 0 } } }, { width = 1280, height = 720 };
native.geometry(roster, 1280, 720, menu);
assert(native.status().available, 'Fixture: the windows are found.');
queries, reads = 0, 0;
native.geometry(roster, 1280, 720, menu);
assert(reads > 10 and queries < reads / 2, ('A pass asks once for each region: %d reads, %d queries.'):format(reads, queries));
local asked = queries;
queries, reads = 0, 0;
native.geometry(roster, 1280, 720, menu);
assert(queries == asked, 'The next pass asks again: nothing is kept from the last one.');
local readable = native.geometry(roster, 1280, 720, menu).reason;
freed[0x40000] = true;
local reason = native.geometry(roster, 1280, 720, menu).reason;
assert(reason ~= readable and reason:find('Group 1: primitive', 1, true), 'A window freed since the last pass reads as nothing: ' .. reason);
native._set_platform(nil);
return 'A geometry pass checks each page region once';
