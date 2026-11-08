local native = require('core.native_party_ui');
local mem, writes = {}, 0;
local function put16(at, value) value = value % 65536; mem[at], mem[at + 1] = value % 256, math.floor(value / 256); end
local function row(group, index, x, y, w, h)
    local node, item = 0x60000 + group * 0x1000 + index * 0x40, 0x80000 + group * 0x1000 + index * 0x80;
    mem[node], mem[node + 0x10], mem[node + 0x14] = 0, item, 0;
    if index == 1 then mem[0x40000 + group * 0x100 + 0x14] = node;
    else mem[node - 0x40] = node; end
    put16(item, 1); put16(item + 0x3A, index);
    put16(item + 0x2A, x); put16(item + 0x2C, y); put16(item + 0x2E, w); put16(item + 0x30, h);
    return node, item;
end
local function setup(count)
    mem, writes = {}, 0;
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
            if slot < (count or 18) then roster.members[#roster.members + 1] = { id = 1001 + slot, slot = slot, group = group }; end
        end
    end
    native._set_platform({
        valid = function(ptr, _, write) return not write and mem[ptr] ~= false; end,
        read32 = function(ptr) assert(ptr ~= 0x10023, 'Never read target frame.'); return mem[ptr]; end,
        read8 = function(ptr) return mem[ptr]; end,
        write8 = function() writes = writes + 1; error('Geometry is read only.'); end,
        find = function(pattern, usage) return usage == 1 and 0 or pattern:sub(1, 2) == '6D' and 0x12000 or pattern:sub(1, 2) == '66' and 0x10000 or 0x11000; end,
    });
    return roster;
end
local function geometry(roster, w, h, menu)
    return native.geometry(roster, w or 1280, h or 720, menu or { width = 1280, height = 720 });
end
local r = setup();
local result = geometry(r);
assert(result.available and result.groups[1] and result.groups[2] and result.groups[3]);
for group = 1, 3 do for index = 1, 6 do
    local slot = (group - 1) * 6 + index - 1;
    local rect = result.groups[group].rows[slot];
    assert(rect.slot == slot and rect.y == 40 + (group - 1) * 160 + (index - 1) * 22);
end end
assert(writes == 0, 'Geometry does not need writable memory or change visibility.');
result = geometry(r, 1920, 1080);
assert(result.groups[1].x == 1650 and result.groups[2].rows[7].height == 33);
assert(result.groups[3].width == 174, 'Menu coordinates project to the display once.');
local status = native.status(); status.geometry.groups[1].x = 1;
assert(native.status().geometry.groups[1].x == 1650, 'Reports cannot mutate cached geometry.');
table.remove(r.members, 8);
result = geometry(r);
assert(result.groups[2].rows[7] == nil and result.groups[2].rows[8].y == 244, 'Holes retain native row numbers.');
-- A member whose row isn't in the game's list yet gets none, and the others keep their own rows: the group still
-- draws, and the reason names what's missing.
put16(0x81000 + 3 * 0x80, 2);
result = geometry(r);
local partial = result.groups[1];
assert(result.available and partial and partial.rows[2] == nil and partial.rows[1].y == 62 and partial.rows[3].y == 106
    and partial.rows[5].y == 150 and partial.y == 40 and partial.height == 132 and partial.pitch == 22,
    'A missing row leaves out only its member.');
assert(result.reason:find('Group 1: A member\'s row in the game\'s list isn\'t there.', 1, true), result.reason);
put16(0x81000 + 3 * 0x80, 1);
r = setup(1); result = geometry(r);
assert(result.groups[1].height == 22 and not result.groups[2], 'Solo uses its own row and no guessed party spacing.');
for _, key in ipairs({ 'hidden', 'map', 'in_event' }) do
    r[key] = true; assert(not geometry(r).available); r[key] = false;
end
for _, v in ipairs({ 0, -1, 0/0, math.huge, 16385 }) do
    assert(not geometry(r, v).available);
    assert(not geometry(r, 1280, 720, { width = v, height = 720 }).available);
end
mem[0x40169] = 0; assert(not geometry(r).available); mem[0x40169] = 1;
mem[0x4010C] = 0x30200; assert(not geometry(r).available); mem[0x4010C] = 0x30100;
local node, item = row(1, 1, 1100, 40, 116, 22);
mem[node] = node; assert(not geometry(r).available, 'Cyclic lists fail closed.'); mem[node] = 0;
mem[node + 0x14] = 1; assert(not geometry(r).available, 'Removed items are not anchors.'); mem[node + 0x14] = 0;
put16(item + 0x2A, -1); assert(not geometry(r).available); put16(item + 0x2A, 1100);
put16(item + 0x2E, 0); assert(not geometry(r).available); put16(item + 0x2E, 116);
put16(item + 0x30, 241); assert(not geometry(r).available); put16(item + 0x30, 22);
put16(item + 0x3A, 7); assert(not geometry(r).available); put16(item + 0x3A, 1);
mem[item + 0x2A] = false; assert(not geometry(r).available, 'Unreadable bounds fail closed.');
r = setup(); mem[0x40269] = 0;
result = geometry(r);
assert(result.groups[1] and not result.groups[2] and result.groups[3], 'Hidden groups do not disable readable groups.');
mem[0x40269] = 1; mem[0x62040] = 0x62080;
put16(0x82000 + 2 * 0x80 + 0x3A, 1);
assert(not geometry(r).groups[2], 'Duplicate row identifiers fail closed.');
assert(writes == 0);
r = setup();
for _, hp in ipairs({ 0, 100 }) do
    put16(0x3013A, hp); result = geometry(r);
    assert(not result.groups[1] and result.groups[2] and result.groups[3], 'Fishing is never used as a native buff anchor');
    assert(result.reason:find('fishing', 1, true));
end
put16(0x3013A, -1); assert(geometry(r).groups[1]);
mem[0x30140] = 1; assert(not geometry(r).groups[1], 'Character preview rows are not party anchors');
mem[0x30140] = 0; mem[0x90152] = 0;
assert(not geometry(r).groups[1], 'Unrelated menus cannot supply native anchors');
mem[0x40204] = 0x90300;
assert(not geometry(r).groups[2], 'Alliance menu identities cannot be interchanged');
assert(writes == 0, 'Protected menu geometry checks remain read only');

-- Each group's pitch, for the room up to the next row: the smallest step between its members' rows, in screen pixels.
-- /vg report also lists every numbered row item the game has in each window, in menu pixels.
r = setup(); result = geometry(r);
for group = 1, 3 do
    local frame = result.groups[group];
    assert(frame.pitch == 22 and frame.measured_by == 'rows' and frame.row_height == 22, 'Members\' rows give the pitch.');
    assert(frame.numbered_count == 6, 'The report counts every numbered row item.');
    for index = 1, 6 do assert(frame.numbered_rows[index].y == 40 + (group - 1) * 160 + (index - 1) * 22); end;
end;
result = geometry(r, 1920, 1080);
assert(result.groups[1].pitch == 33 and result.groups[1].row_height == 33 and result.groups[1].numbered_rows[2].y == 62,
    'The pitch follows the menu scale; the item list keeps menu pixels.');
local reported = native.status().geometry.groups[2];
assert(reported.numbered_count == 6 and reported.numbered_rows[6].y == 310 and reported.pitch == 33 and reported.measured_by == 'rows');
assert(require('core.json').decode(require('core.store').encode(native.status())).geometry.groups[1].numbered_count == 6,
    'The report writes the item list.');
r.members = { r.members[1], r.members[3] }; result = geometry(r);
assert(result.groups[1].pitch == 22 and result.groups[1].measured_by == 'rows', 'A gap between two members shares their distance.');
-- With the first member's row missing, the empty slots line up with the next member's.
r = setup(2); put16(0x81000 + 1 * 0x80, 2); result = geometry(r);
assert(result.groups[1].rows[0] == nil and result.groups[1].rows[1].y == 62 and result.groups[1].pitch == 22
    and result.groups[1].measured_by == 'empty_slots', 'The pitch is measured from the first row found.');
-- One member: the items the game keeps for empty slots give the pitch where they line up with the member's row.
r = setup(1); result = geometry(r);
assert(result.groups[1].pitch == 22 and result.groups[1].measured_by == 'empty_slots' and result.groups[1].numbered_count == 6,
    'Solo reads the empty slots\' rows.');
-- Out of line, they don't count; the pitch seen this session at the same row height does.
for index = 2, 6 do put16(0x81000 + index * 0x80 + 0x2A, 600); end;
result = geometry(r);
assert(result.groups[1].pitch == 22 and result.groups[1].measured_by == 'session', 'Solo remembers the pitch seen this session.');
-- A row height never seen has none: the room is the row.
for index = 1, 6 do put16(0x81000 + index * 0x80 + 0x30, 20); end;
result = geometry(r);
assert(result.groups[1].pitch == nil and result.groups[1].measured_by == 'none' and result.groups[1].row_height == 20);
-- Empty slots spread past twice the row's height are not a pitch.
r = setup(1);
for index = 2, 6 do put16(0x81000 + index * 0x80 + 0x2C, 40 + (index - 1) * 50); end;
result = geometry(r);
assert(result.groups[1].pitch == nil and result.groups[1].measured_by == 'none', 'Spread items are not rows.');
assert(writes == 0);
return 'Native row geometry, solo and alliance slots, scaling, pitch, empty slots and guarded failure';
