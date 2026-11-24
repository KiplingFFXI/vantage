-- Reading the game's party windows makes nothing once running, in a party of 6 and in an alliance of 18. The host reads
-- them at each refresh, ten times a second and more, so a table made at each read adds up. The game's memory is laid
-- out as tests/test_native_geometry.lua lays it out. Measured as test_party_strip_allocation.lua does, with the
-- collector stopped and the compiler off.
local native = require('core.native_party_ui');
local mem = {};
local function put16(at, value) value = value % 65536; mem[at], mem[at + 1] = value % 256, math.floor(value / 256); end
local function row(group, index, x, y, w, h)
    local node, item = 0x60000 + group * 0x1000 + index * 0x40, 0x80000 + group * 0x1000 + index * 0x80;
    mem[node], mem[node + 0x10], mem[node + 0x14] = 0, item, 0;
    if index == 1 then mem[0x40000 + group * 0x100 + 0x14] = node;
    else mem[node - 0x40] = node; end
    put16(item, 1); put16(item + 0x3A, index);
    put16(item + 0x2A, x); put16(item + 0x2C, y); put16(item + 0x2E, w); put16(item + 0x30, h);
end
local function setup(count)
    mem = {};
    mem[0x10019], mem[0x11001], mem[0x11007] = 0x20100, 0x20200, 0x20300;
    local roster = { valid = true, id = 1001, members = {} };
    for group = 1, 3 do
        local container, ptr = 0x30000 + group * 0x100, 0x40000 + group * 0x100;
        mem[0x20000 + group * 0x100], mem[container], mem[container + 8] = container, 0x50000, ptr;
        mem[ptr + 0x0C], mem[ptr + 0x69], mem[ptr + 0x6A] = container, 1, 1;
        require('native_menu_fixture')(mem, container, ptr, group);
        for i = 1, 6 do
            row(group, i, 1100, 40 + (group - 1) * 160 + (i - 1) * 22, 116, 22);
            local slot = (group - 1) * 6 + i - 1;
            if slot < count then roster.members[#roster.members + 1] = { id = 1001 + slot, slot = slot, group = group }; end
        end
    end
    native._set_platform({
        valid = function(ptr, _, write) return not write and mem[ptr] ~= false; end,
        read32 = function(ptr) return mem[ptr]; end,
        read8 = function(ptr) return mem[ptr]; end,
        find = function(pattern, usage) return usage == 1 and 0 or pattern:sub(1, 2) == '6D' and 0x12000 or pattern:sub(1, 2) == '66' and 0x10000 or 0x11000; end,
    });
    return roster;
end
local menu = { width = 1280, height = 720 };
-- A full collection shrinks the Lua stack, and the next reads grow it back once, which is LuaJIT's and not a read's,
-- so a few reads run after the collection, with the collector stopped, before counting starts.
local function cost(count)
    local roster = setup(count);
    for _ = 1, 50 do native.geometry(roster, 1920, 1080, menu); end
    jit.off(); jit.flush();
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    for _ = 1, 6 do native.geometry(roster, 1920, 1080, menu); end
    local before = collectgarbage('count');
    for _ = 1, 200 do native.geometry(roster, 1920, 1080, menu); end
    local each = (collectgarbage('count') - before) / 200;
    collectgarbage('restart');
    jit.on();
    return each;
end
local alliance, party = cost(18), cost(6);
assert(alliance < 0.002 and party < 0.002,
    ('A read of the party windows makes %.3f KB with 18 members and %.3f KB with 6; nothing expected'):format(alliance, party));

-- What a read gives is still right when the alliance becomes a party and a member leaves: the groups that went have no
-- frame, and the member who left has no row.
local roster = setup(18);
local result = native.geometry(roster, 1920, 1080, menu);
assert(result.available and result.groups[1] and result.groups[2] and result.groups[3], 'Fixture: the alliance reads.');
for index = #roster.members, 7, -1 do roster.members[index] = nil; end
table.remove(roster.members, 3);
result = native.geometry(roster, 1920, 1080, menu);
local frame = result.groups[1];
assert(result.available and frame and not result.groups[2] and not result.groups[3], 'Only the party\'s group is left.');
assert(frame.rows[2] == nil and frame.rows[1].y == 93 and frame.rows[5].y == 225 and frame.rows[5].slot == 5,
    'The member who left has no row, and the others keep their own.');
local rows = 0;
for _ in pairs(frame.rows) do rows = rows + 1; end
assert(rows == 5 and frame.numbered_count == 6 and frame.pitch == 33, 'Five rows, six numbered items, the pitch from the rows.');
return 'Reading the game\'s party windows makes nothing once running';
