-- The game party list is found by its two code patterns, each matched once, and the Treasure Pool by its menu
-- registry. Every read checks its page first, and nothing in the client is ever written.
local native = require('core.native_party_ui');
local memory, invalid, ambiguous = {}, {}, false;
local reads, scans, checked = 0, 0, nil;
local roots = { 0x20000, 0x20100, 0x20200 };
local pointers = { 0x40000, 0x40100, 0x40200 };
local function read(ptr)
    reads = reads + 1;
    assert(ptr == checked, 'Every read checks its page first.');
    assert(ptr ~= 0x10000 + 0x23, 'The target frame pointer is never read.');
    return memory[ptr];
end
local function setup()
    memory, invalid, ambiguous = {}, {}, false;
    reads, scans, checked = 0, 0, nil;
    memory[0x10000 + 0x19], memory[0x11000 + 1], memory[0x11000 + 7] = roots[1], roots[2], roots[3];
    memory[0x10000 + 0x23] = 0xDEAD00;
    for i = 1, 3 do
        memory[roots[i]], memory[0x30000 + i * 0x100 + 8] = 0x30000 + i * 0x100, pointers[i];
        memory[0x30000 + i * 0x100], memory[pointers[i] + 0x0C] = 0x50000, 0x30000 + i * 0x100;
        memory[pointers[i]], memory[pointers[i] + 0x69], memory[pointers[i] + 0x6A] = 0, 1, 1;
        require('native_menu_fixture')(memory, 0x30000 + i * 0x100, pointers[i], i);
    end
    native._set_platform({
        valid = function(ptr, _, write)
            assert(not write, 'The party list is only read.');
            checked = ptr;
            return not invalid[ptr];
        end,
        read32 = read, read8 = read,
        write8 = function() error('The party list is never written.'); end,
        find = function(pattern, occurrence)
            scans = scans + 1;
            if occurrence == 1 then return ambiguous and 0x12000 or 0; end
            return pattern:sub(1, 2) == '6D' and 0x12000 or pattern:sub(1, 2) == '66' and 0x10000 or 0x11000;
        end,
    });
end
local function open_treasure(index)
    local slot, container, ptr, header = 0x20F00 + index * 0x100, 0x70000, 0x71000, 0x72000;
    memory[slot], memory[container + 8], memory[ptr + 0x0C], memory[ptr + 4] = container, ptr, container, header;
    memory[header + 0x46], memory[header + 0x4A], memory[header + 0x4E] = 0x756E656D, 0x20202020, 0x746F6F6C;
    memory[header + 0x52] = index == 1 and 0x20202020 or 0x2065706F;
    memory[ptr + 0x69], memory[ptr + 0x6A] = 1, 1;
    return slot, container, ptr, header;
end

setup();
assert(native.load());
for index = 1, 2 do
    setup(); assert(native.treasure_open() == false, 'A closed Treasure Pool reads as closed.');
    local slot, container, ptr, header = open_treasure(index);
    assert(native.treasure_open() == true, 'Both the pool list and the lot/pass popup count as open.');
    memory[container + 8] = 0;
    assert(native.treasure_open() == false);
    memory[container + 8] = ptr;
    memory[ptr + 0x69], memory[ptr + 0x6A] = 0, 0;
    assert(native.treasure_open() == false, 'A fully hidden closing popup is not open.');
    memory[ptr + 0x6A] = 1;
    assert(native.treasure_open() == true, 'An active native callback counts as open even with hidden artwork.');
    memory[header + 0x52] = 0;
    assert(native.treasure_open() == nil, 'A reused or unrecognized primitive is not taken for a closed Treasure Pool.');
    memory[slot] = 0;
    assert(native.treasure_open() == false);
    invalid[slot] = true;
    assert(native.treasure_open() == nil, 'An unreadable Treasure Pool slot is not taken for a closed pool.');
end;
assert(reads > 0, 'Fixture: the pool was read.');
setup(); ambiguous = true;
assert(native.treasure_open() == nil, 'A registry pattern that matches twice finds no Treasure Pool.');

-- The party windows: a pattern that matches twice, or a slot that can't be read, finds nothing. The status lines
-- speak of the game's party list as it is: Vantage never hides or replaces it.
local function plain(text)
    for _, word in ipairs({ 'stay visible', 'replacement', 'overlay is off' }) do
        assert(not text:lower():find(word, 1, true), 'A party list status line says nothing of replacing windows: ' .. text);
    end;
end;
setup();
assert(native.status().reason == 'Waiting for the game party list.' and native.status().geometry.reason == native.status().reason,
    'Before the party list is read, the status waits for it.');
local roster = { valid = true, members = { { id = 1001, group = 1, slot = 0 } } };
local menu = { width = 1280, height = 720 };
setup(); ambiguous = true;
local found = native.geometry(roster, 1280, 720, menu);
assert(not found.available and found.reason:find('unique supported party-frame signatures', 1, true));
assert(native.status().available == false and native.status().reason == found.reason);
plain(found.reason);
setup(); invalid[roots[1]] = true;
found = native.geometry(roster, 1280, 720, menu);
assert(not found.available and found.reason:find('could not be validated', 1, true));
plain(found.reason);
native._set_platform(nil);
package.loaded.ffi.os = 'Linux';
assert(native.load() == false and native.status().reason == "Vantage could not read the game's party windows.",
    "A client that can't be read says so plainly.");
plain(native.status().reason);
package.loaded.ffi.os = 'Windows';
setup();
found = native.geometry(roster, 1280, 720, menu);
assert(native.status().available, 'Two unique patterns find the party window slots.');
assert(native.status().reason == "Found the game's party windows.", 'Once they are found, the status says so instead of waiting.');
plain(native.status().reason);
assert(native.status().geometry ~= found and native.live_status().geometry == found and native.live_status() == native.live_status()
    and native.live_status().reason == native.status().reason, 'The settings window reads the geometry itself, with no copy and no new table.');
local searches = scans;
native.geometry(roster, 1280, 720, menu);
assert(scans == searches, 'The slots are found once, then kept.');

-- Three warmup steps, one pattern each: the party list's two, the second with the window slots, then the Treasure
-- Pool's registry. After them, geometry and treasure_open search nothing.
setup();
local steps = native.warmup_steps();
assert(#steps == 3 and steps[1].name == 'party.list_1' and steps[2].name == 'party.list_2' and steps[3].name == 'party.treasure');
steps[1].run();
assert(scans == 2 and not native.status().available, 'The first step looks for the first pattern alone.');
steps[2].run();
assert(scans == 4 and native.status().available, 'The second finds the slots.');
steps[3].run(); steps[1].run(); steps[2].run();
assert(scans == 6, 'The treasure step looks for the registry, and each step runs once.');
open_treasure(1);
native.geometry(roster, 1280, 720, menu);
assert(native.treasure_open() == true and native.status().available and scans == 6);
setup(); ambiguous = true;
for _, step in ipairs(native.warmup_steps()) do step.run(); end
assert(scans == 4 and not native.status().available and native.treasure_open() == nil and scans == 4,
    'A first pattern found twice stops the second from being looked for.');
assert(#MOCK.commands == 0);
return 'Party list slots and the Treasure Pool, read only and page checked';
