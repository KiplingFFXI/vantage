local native = {};
local client_memory = require('core.memory');
local finder = require('core.patterns');
local platform, slots;
local reason, attempted = 'Waiting for the game party list.', false;
local treasure_slots, treasure_checked;
local treasure_pattern = '6D656E75202020206C6F6F7420202020' .. string.rep('?', 56)
    .. '6D656E75202020206C6E6F77696E2020' .. string.rep('?', 56) .. '6D656E75202020206C6F6F746F706520';
local treasure_names = { { 0x746F6F6C, 0x20202020 }, { 0x746F6F6C, 0x2065706F } };
local geometry_status = { available = false, reason = 'Waiting for the game party list.' };
local patterns = {
    '66C78182000000????C7818C000000????????C781900000',
    'A1????????8B0D????????89442424A1????????33DB89',
};

local address = client_memory.address;
-- Each pattern's first match, and no second one; a second search that fails counts as none.
local RULE = { unique = true, lenient = true, find = function(pattern, _, usage) return platform.find(pattern, usage); end };
-- Each party-frame pattern's match once looked for, or false.
local listed = {};
local done = {};

local function protected(method, ...)
    if not platform or type(platform[method]) ~= 'function' then return nil; end
    local ok, value = pcall(platform[method], ...);
    return ok and value or nil;
end

-- The page regions this pass has checked, as start and stop pairs. A pass runs inside one Present, with the client
-- waiting on it, and its reads land in a few regions, so each is queried once. None is kept past the pass: the client
-- frees memory between frames. A read outside a pass, as a warmup step's are, checks its own page.
local checked, checked_count, passing = {}, 0, false;

local function page_checked(ptr, size)
    for index = 1, checked_count, 2 do
        if ptr >= checked[index] and ptr + size <= checked[index + 1] then return true; end
    end
    if not platform or type(platform.valid) ~= 'function' then return false; end
    local ok, valid, first, stop = pcall(platform.valid, ptr, size, false);
    if not ok or not valid then return false; end
    if passing and first and stop then
        checked[checked_count + 1], checked[checked_count + 2] = first, stop;
        checked_count = checked_count + 2;
    end
    return true;
end

-- Every read is page checked first, so a window the client freed reads as nothing.
local function read(kind, ptr)
    local size = kind == 'read8' and 1 or 4;
    if not address(ptr) or not page_checked(ptr, size) then return nil; end
    return protected(kind, ptr);
end

local function word(ptr, signed)
    local low, high = read('read8', ptr), read('read8', ptr + 1);
    if low == nil or high == nil then return nil; end
    local value = low + high * 256;
    return signed and value >= 32768 and value - 65536 or value;
end

-- The full names are "menu    partywin", "menu    raid1   " and "menu    raid2   ".
local menu_names = {
    { 0x756E656D, 0x20202020, 0x74726170, 0x6E697779 },
    { 0x756E656D, 0x20202020, 0x64696172, 0x20202031 },
    { 0x756E656D, 0x20202020, 0x64696172, 0x20202032 },
};

local function menu_identity(entry, group)
    local header = read('read32', entry.ptr + 4);
    if header == nil then return nil; end
    if not address(header) then return false; end
    local expected = menu_names[group];
    for index = 1, 4 do
        local value = read('read32', header + 0x46 + (index - 1) * 4);
        if value == nil then return nil; end
        if value ~= expected[index] then return false; end
    end
    return true;
end

local function party_mode(entry, group)
    if not menu_identity(entry, group) then return false, 'The expected party menu is unavailable.'; end
    if group == 1 then
        -- Fishing and the character preview draw the party window their own way.
        local fish = word(entry.container + 0x3A, true);
        local alternate = read('read8', entry.container + 0x40);
        if fish == nil or alternate == nil then return false, 'The party window mode is unavailable.'; end
        if fish >= 0 then return false, 'The game\'s fishing display is active.'; end
        if alternate ~= 0 then return false, 'The game\'s character preview is active.'; end
    end
    return true;
end

local function primitive(slot)
    local container = read('read32', slot);
    if container == 0 then return false; end
    if not address(container) then return nil, { stage = 'container' }; end
    local vtable = read('read32', container);
    if not address(vtable) or not page_checked(vtable, 4) then
        return nil, { stage = 'container_vtable' };
    end
    local ptr = read('read32', container + 8);
    if ptr == 0 then return false; end
    if not address(ptr) then return nil, { stage = 'primitive' }; end
    -- The primitive has no vtable; its owner points back to this container.
    if read('read32', ptr + 0x0C) ~= container then return nil, { stage = 'primitive_owner' }; end
    local first, second = read('read8', ptr + 0x69), read('read8', ptr + 0x6A);
    if (first ~= 0 and first ~= 1) or (second ~= 0 and second ~= 1) then
        return nil, { stage = 'visibility_flags', first = first, second = second };
    end
    return { slot = slot, container = container, ptr = ptr, vtable = vtable, first = first, second = second };
end

local function same(a, b)
    return a and b and a.container == b.container and a.ptr == b.ptr and a.vtable == b.vtable;
end

function native.load()
    if platform then return true; end
    local ok, result = pcall(function()
        local ffi = require('ffi');
        if ffi.os ~= 'Windows' or not ashita or not ashita.memory then return nil; end
        return {
            valid = client_memory.pages().valid,
            find = function(pattern, usage) return ashita.memory.find(':ffximain', 0, pattern, 0, usage); end,
            read32 = ashita.memory.read_uint32, read8 = ashita.memory.read_uint8,
        };
    end);
    platform = ok and result or nil;
    if not platform then reason = 'Vantage could not read the game\'s party windows.'; return false, reason; end
    return true;
end

-- The Treasure Pool's two window slots, from its menu registry, once.
local function find_treasure()
    if treasure_checked or not native.load() then return; end
    treasure_checked = true;
    local registry = finder.find('party', 'treasure', treasure_pattern, RULE);
    if registry then
        local first, second = read('read32', registry + 0x20), read('read32', registry + 0x78);
        if address(first) and address(second) and first ~= second then treasure_slots = { first, second }; end
    end
end

local function treasure_state()
    if not treasure_checked then
        if not native.load() then return nil; end
        find_treasure();
    end
    if not treasure_slots then return nil; end
    local unknown = false;
    for index, slot in ipairs(treasure_slots) do
        local container = read('read32', slot);
        if container ~= 0 then
            local ptr = address(container) and read('read32', container + 8) or nil;
            if ptr ~= 0 then
                local header = address(ptr) and read('read32', ptr + 4) or nil;
                local expected = treasure_names[index];
                if not address(header) or read('read32', ptr + 0x0C) ~= container
                    or read('read32', header + 0x46) ~= 0x756E656D or read('read32', header + 0x4A) ~= 0x20202020
                    or read('read32', header + 0x4E) ~= expected[1] or read('read32', header + 0x52) ~= expected[2] then
                    unknown = true;
                else
                    local art, callback = read('read8', ptr + 0x69), read('read8', ptr + 0x6A);
                    if art == 1 or callback == 1 then return true; end
                    if art ~= 0 or callback ~= 0 then unknown = true; end
                end
            end
        end
    end
    if unknown then return nil; end
    return false;
end

-- The client draws each member's lot/pass result inside the party windows.
function native.treasure_open()
    checked_count, passing = 0, true;
    local open = treasure_state();
    checked_count, passing = 0, false;
    return open;
end

-- One party-frame pattern's match, looked for once; the second isn't looked for when the first failed.
local function list(index)
    if listed[index] == nil and (index == 1 or listed[1]) and native.load() then
        listed[index] = finder.find('party', 'list_' .. index, patterns[index], RULE) or false;
    end
    return listed[index];
end

local function locate()
    if slots then return true; end
    if attempted then return false; end
    attempted = true;
    if not native.load() then return false; end
    local first = list(1);
    local second = first and list(2);
    if not first or not second then
        reason = 'This client does not have unique supported party-frame signatures.';
        return false;
    end
    local found = { read('read32', first + 0x19), read('read32', second + 1), read('read32', second + 7) };
    for i = 1, 3 do
        if not address(found[i]) or not protected('valid', found[i], 4, false) then
            reason = 'A party-frame pointer could not be validated.'; return false;
        end
        for j = 1, i - 1 do if found[j] == found[i] then reason = 'Party-frame pointers overlap.'; return false; end end
    end
    slots = found;
    return true;
end

-- Read the same numbered menu items the client uses to draw each member.
local function row_rects(entry)
    local head = read('read32', entry.ptr + 0x14);
    local node, seen, rows = head, {}, {};
    for _ = 1, 128 do
        if node == 0 then
            if read('read32', entry.ptr + 0x14) ~= head then return nil, 'The game\'s row list changed.'; end
            return rows;
        end
        if not address(node) or seen[node] then return nil, 'The game\'s row list can\'t be read.'; end
        seen[node] = true;
        local removed = read('read8', node + 0x14);
        if removed ~= 0 and removed ~= 1 then return nil, 'The game\'s row list can\'t be read.'; end
        if removed == 0 then
            local item = read('read32', node + 0x10);
            if not address(item) then return nil, 'A row of the game\'s list can\'t be read.'; end
            local kind = word(item);
            if kind == 1 then
                local index = word(item + 0x3A);
                if index and index >= 1 and index <= 6 then
                    local x, y = word(item + 0x2A, true), word(item + 0x2C, true);
                    local w, h = word(item + 0x2E, true), word(item + 0x30, true);
                    if not x or not y or not w or not h or w <= 0 or h <= 0 or w > 1200 or h > 240 or rows[index] then
                        return nil, 'A member\'s row in the game\'s list is an unexpected size.';
                    end
                    rows[index] = { x = x, y = y, width = w, height = h };
                end
            end
        end
        node = read('read32', node);
    end
    return nil, 'The game\'s row list is longer than it should be.';
end

-- The pitch each group's rows had earlier this session, with the row height it was read at, so a group down to one
-- member can still use it while its rows keep that height.
local seen_pitch = { {}, {}, {} };

-- Whether a numbered item lines up with the member's row: the same place across, the same size, and on the screen.
local function lined_up(item, member, dimensions)
    return item.x == member.x and item.width == member.width and item.height == member.height and item.y >= 0
        and item.y + item.height <= dimensions.height;
end

-- The smallest step from one row to the next among rows keyed by slot or item number, or nil. Two rows with numbers
-- between them share their distance over the gap. With member (the game's numbered items, in menu pixels), only items
-- in line with its row count, and never a step past twice its height.
local function smallest_step(rows, member, dimensions)
    local best;
    for upper_key, upper in pairs(rows) do
        for lower_key, lower in pairs(rows) do
            if lower_key > upper_key and (not member or lined_up(upper, member, dimensions) and lined_up(lower, member, dimensions)) then
                local step = math.abs(lower.y - upper.y) / (lower_key - upper_key);
                if step > 0 and (not member or step <= member.height * 2) and (not best or step < best) then best = step; end;
            end;
        end;
    end;
    return best;
end

-- Where a group's pitch comes from: its members' rows, else the items the game keeps for empty slots, else the pitch
-- seen this session at the same row height. measured_by says which, or 'none'.
local function measure_pitch(frame, group, items, member, dimensions, sy)
    local pitch, measured_by = smallest_step(frame.rows), 'rows';
    if not pitch then
        local step = member and smallest_step(items, member, dimensions);
        pitch, measured_by = step and step * sy, 'empty_slots';
    end;
    local seen = seen_pitch[group];
    if pitch then
        seen.height, seen.pitch = frame.row_height, pitch;
    elseif seen.height == frame.row_height and seen.pitch then
        pitch, measured_by = seen.pitch, 'session';
    else measured_by = 'none'; end;
    frame.pitch, frame.measured_by = pitch, measured_by;
end

-- The game menu's size from the chat log's last read. The host reads the chat log at least once a second, and again
-- for another screen size, so this reads nothing more of the client. Before its first read it is read here.
local menu = {};
local function geometry(roster, width, height, dimensions)
    local out = { available = false, groups = {}, reason = 'Waiting for the game party windows.' };
    if not roster or not roster.valid or roster.hidden or roster.map or roster.in_event then return out; end
    if not locate() then out.reason = reason; return out; end
    if not dimensions then
        local chat = require('core.chat');
        menu.width, menu.height = chat.menu_size();
        dimensions = menu.width and menu or chat.menu_dimensions();
    end
    local function dimension(value)
        return type(value) == 'number' and value == math.floor(value) and value > 0 and value <= 16384;
    end
    if not dimensions or not dimension(dimensions.width) or not dimension(dimensions.height)
        or not dimension(width) or not dimension(height) then
        out.reason = 'The game menu size is unavailable.'; return out;
    end
    local sx, sy = width / dimensions.width, height / dimensions.height;
    local function readable(entry)
        return entry and entry.first == 1 and entry.second == 1;
    end;
    local issues = {};
    for group = 1, 3 do
        local members = {};
        for _, member in ipairs(roster.members or {}) do if member.group == group then members[#members + 1] = member; end end
        if #members > 0 then
            local entry, detail = primitive(slots[group]);
            if readable(entry) then
                local allowed, issue = party_mode(entry, group);
                local rows;
                if allowed then rows, issue = row_rects(entry); end
                local current = primitive(slots[group]);
                if rows and same(entry, current) and readable(current) and party_mode(current, group) then
                    local frame = { rows = {}, row_height = 0 };
                    local l, t, r, b = dimensions.width, dimensions.height, 0, 0;
                    -- A member whose row isn't in the game's list (yet) gets none here, and the others keep their own
                    -- rows. The game's empty slots are lined up with the first row found to measure the pitch.
                    local found;
                    for _, member in ipairs(members) do
                        local row = rows[member.slot % 6 + 1];
                        if row and row.x >= 0 and row.y >= 0 and row.x + row.width <= dimensions.width and row.y + row.height <= dimensions.height then
                            -- These are the final item bounds, after the client's menu scaling.
                            l, t = math.min(l, row.x), math.min(t, row.y);
                            r, b = math.max(r, row.x + row.width), math.max(b, row.y + row.height);
                            frame.rows[member.slot] = { x = row.x * sx, y = row.y * sy, width = row.width * sx,
                                height = row.height * sy, slot = member.slot };
                            frame.row_height = math.max(frame.row_height, row.height * sy);
                            found = found or row;
                        else issue = 'A member\'s row in the game\'s list isn\'t there.'; end
                    end
                    if found then
                        frame.x, frame.y, frame.width, frame.height = l * sx, t * sy, (r - l) * sx, (b - t) * sy;
                        -- For /vg report: every numbered row item the game has in this window, members' or not, by
                        -- number and in menu pixels, and how many there are.
                        local count = 0;
                        for _ in pairs(rows) do count = count + 1; end;
                        frame.numbered_rows, frame.numbered_count = rows, count;
                        measure_pitch(frame, group, rows, found, dimensions, sy);
                        out.groups[group], out.available = frame, true;
                    end
                else issue = issue or 'The game\'s party window changed or can\'t be read.'; end
                if issue then issues[#issues + 1] = 'Group ' .. group .. ': ' .. issue; end
            elseif entry == nil then issues[#issues + 1] = 'Group ' .. group .. ': ' .. (detail and detail.stage or 'unreadable'); end
        end
    end
    out.reason = #issues > 0 and table.concat(issues, ' ') or out.available and 'Following the game party windows.' or out.reason;
    return out;
end

function native.geometry(roster, width, height, dimensions)
    checked_count, passing = 0, true;
    geometry_status = geometry(roster, width, height, dimensions);
    checked_count, passing = 0, false;
    return geometry_status;
end;

function native.status()
    return { available = slots ~= nil, reason = reason, geometry = require('core.store').copy(geometry_status) };
end

-- The party list's warmup steps, in order, as { name, run }: the first party-frame pattern, the second with the
-- window slots they give, then the Treasure Pool's registry. Without them, the first geometry and treasure_open
-- calls do the search themselves.
local STEPS = {
    finder.step('party.list_1', done, function() list(1); end),
    finder.step('party.list_2', done, function() locate(); end),
    finder.step('party.treasure', done, find_treasure),
};
function native.warmup_steps() return { STEPS[1], STEPS[2], STEPS[3] }; end

if VANTAGE_TEST_MODE then
    function native._set_platform(value)
        platform, slots, attempted = value, nil, false;
        treasure_slots, treasure_checked = nil, false;
        for key in pairs(listed) do listed[key] = nil; end
        for key in pairs(done) do done[key] = nil; end
        geometry_status = { available = false, reason = 'Waiting for the game party list.' };
        reason = 'Waiting for the game party list.';
        seen_pitch = { {}, {}, {} };
    end
end

return native;
