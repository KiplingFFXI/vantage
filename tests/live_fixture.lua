-- The game as vantage.lua meets it: each event Ashita hands a callback is userdata with only the fields Ashita gives
-- that kind of event. Reading any other field raises, and pairs, next, rawget or # on the event fail, as they do in
-- the game; blocked is the one field a callback sets. The events go to the handlers vantage.lua registers, by their
-- names, and the packets are built in the layouts Phoenix sends. The world is overhead_fixture.lua's: you (Tester,
-- 1001) in a party with Bob (1002) and Dave (1003) in La Theine Plateau (102).
local event_scan, interface_scan, focus_scan = 0x110000, 0x120000, 0x130000;
local interface, event_flag = 0x210000, 0x220000;
local memory = { [event_scan + 1] = event_flag, [interface_scan + 10] = interface, [focus_scan] = interface + 0x54,
    [interface + 0xB4] = 0, [event_flag] = 0, [interface + 0x54] = 0 };
ashita.memory.find = function(_, _, pattern)
    return pattern:sub(1, 2) == 'A0' and event_scan or pattern:sub(1, 8) == '8B442404' and interface_scan or focus_scan;
end;
local function read(address) return memory[address]; end
ashita.memory.read_uint8, ashita.memory.read_uint32 = read, read;
require('core.client')._set_pages(function() return true; end);

local L = { images = {} };
L.W = require('overhead_fixture');
local W = L.W;

-- The party: you in slot 0, Bob 2 yalms off to the right and Dave to the left, all here.
L.members = { [0] = { id = 1001, index = W.self, name = 'Tester' }, { id = 1002, index = 0x401, name = 'Bob' },
    { id = 1003, index = 0x402, name = 'Dave' } };
local party = AshitaCore:GetMemoryManager():GetParty();
local function member(slot, key) local m = L.members[slot]; return m and m[key]; end
party.GetMemberServerId = function(_, slot) return member(slot, 'id') or 0; end;
party.GetMemberTargetIndex = function(_, slot) return member(slot, 'index') or 0; end;
party.GetMemberName = function(_, slot) return member(slot, 'name') or ''; end;
party.GetMemberIsActive = function(_, slot) return L.members[slot] and 1 or 0; end;
party.GetMemberHPPercent = function(_, slot) return L.members[slot] and 100 or 0; end;
party.GetMemberMP = function() return 100; end;
W.unit(0x401, 1002, 'player', 2, -1, { name = 'Bob' });
W.unit(0x402, 1003, 'player', -2, -1, { name = 'Dave' });

-- The background draw list keeps each frame's icon textures; an icon's texture is 5000 plus its id.
local list = setmetatable({}, { __index = function(_, name)
    return function(_, texture) if name == 'AddImage' then L.images[#L.images + 1] = texture; end end;
end });
rawset(require('imgui'), 'GetBackgroundDrawList', function() return list; end);
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);

-- An event: fields is what it holds, exposed the names Ashita gives it.
function L.event(fields, exposed)
    local event = newproxy(true);
    local meta = getmetatable(event);
    meta.__index = function(_, key)
        if not exposed[key] then error('The event has no field ' .. tostring(key) .. '.', 2); end
        return fields[key];
    end;
    meta.__newindex = function(_, key, value)
        if key ~= 'blocked' then error('Only blocked is set on an event, not ' .. tostring(key) .. '.', 2); end
        fields.blocked = value;
    end;
    return event;
end
local PACKET = { id = true, size = true, data = true, data_raw = true, injected = true, blocked = true };
local COMMAND = { mode = true, command = true, injected = true, blocked = true };

local function handler(event, name)
    local found = MOCK.events[event] and MOCK.events[event][name];
    assert(type(found) == 'function', 'Fixture: vantage.lua registers ' .. name .. '.');
    return found;
end

-- An incoming packet of bytes (0-based, n long) as Ashita hands it to vantage.lua's packet_in handler.
function L.receive(id, bytes)
    local characters = {};
    for i = 0, bytes.n - 1 do characters[i + 1] = string.char(bytes[i] or 0); end
    local fields = { id = id, size = bytes.n, data = table.concat(characters), data_raw = bytes, injected = false, blocked = false };
    handler('packet_in', 'vantage_packet_in')(L.event(fields, PACKET));
    return fields;
end
function L.command(text)
    local fields = { mode = 1, command = text, injected = false, blocked = false };
    handler('command', 'vantage_command')(L.event(fields, COMMAND));
    return fields;
end
-- A frame: the scene's BeginScenes, then Present, which refreshes, places the blocks and draws their icons.
function L.frame(seconds)
    MOCK.now = MOCK.now + (seconds or 0.2);
    local scene = handler('d3d_beginscene', 'vantage_overhead_scene');
    scene(true); scene(true);
    for i = #L.images, 1, -1 do L.images[i] = nil; end
    handler('d3d_present', 'vantage_present')();
end

local function putbits(bytes, offset, length, value)
    for i = 0, length - 1 do
        local at = offset + i;
        if math.floor(value / 2 ^ i) % 2 == 1 then bytes[math.floor(at / 8)] = bytes[math.floor(at / 8)] + 2 ^ (at % 8); end
    end
end
-- 0x028: the actor at bit 40, the target count at 72, the category at 82 and the action id at 86; from bit 150 each
-- target is its id and result count, and each result 85 bits with its param at +27 and message at +44, then the
-- added effect and reaction flags, both clear here.
function L.action(category, id, actor, targets)
    local bytes, at = MOCK.bytes(512), 150;
    putbits(bytes, 40, 32, actor); putbits(bytes, 72, 6, #targets);
    putbits(bytes, 82, 4, category); putbits(bytes, 86, 32, id);
    for _, target in ipairs(targets) do
        putbits(bytes, at, 32, target.id); putbits(bytes, at + 32, 4, #target.rows); at = at + 36;
        for _, row in ipairs(target.rows) do
            putbits(bytes, at + 27, 17, row.param or 0); putbits(bytes, at + 44, 10, row.message or 0);
            at = at + 85 + 1 + 1;
        end
    end
    bytes.n = math.ceil(at / 8);
    return L.receive(0x028, bytes);
end
-- 0x029: the actor and target ids, the param (an effect id here) and the message.
function L.message(actor, target, param, message)
    local bytes = MOCK.bytes(28);
    MOCK.put(bytes, 4, 4, actor); MOCK.put(bytes, 8, 4, target); MOCK.put(bytes, 12, 4, param); MOCK.put(bytes, 24, 2, message);
    return L.receive(0x029, bytes);
end
-- 0x00E: a mob's id and index with its status bit set, and who claimed it at 0x2C.
function L.entity(id, index, claimer)
    local bytes = MOCK.bytes(0x48);
    MOCK.put(bytes, 4, 4, id); MOCK.put(bytes, 8, 2, index); bytes[0x0A] = 0x02; MOCK.put(bytes, 0x2C, 4, claimer or 0);
    return L.receive(0x00E, bytes);
end
-- 0x076: a row of 48 bytes for each member listed ({ id, index, effects }), each effect a byte from 16 on.
function L.listing(rows)
    local bytes = MOCK.bytes(244);
    for r, row in ipairs(rows) do
        local start = 4 + (r - 1) * 48;
        MOCK.put(bytes, start, 4, row[1]); MOCK.put(bytes, start + 4, 2, row[2]);
        for i = 0, 31 do bytes[start + 16 + i] = 255; end
        for i, effect in ipairs(row[3]) do bytes[start + 16 + i - 1] = effect; end
    end
    return L.receive(0x076, bytes);
end
-- 0x063 type 9: your status icons and their timers, none here.
function L.self_timers()
    local bytes = MOCK.bytes(200);
    MOCK.put(bytes, 4, 2, 9); MOCK.put(bytes, 6, 2, 0xC4);
    for i = 0, 31 do MOCK.put(bytes, 8 + i * 2, 2, 255); end
    return L.receive(0x063, bytes);
end
-- 0x00A: the character's id at 4, the zone at 0x30, the login state at 0x80 (1 in a Mog House) and the name at 0x84.
function L.zone_in(zone, mog_house)
    local bytes = MOCK.bytes(0x100);
    MOCK.put(bytes, 4, 4, 1001); MOCK.put(bytes, 0x30, 2, zone); MOCK.put(bytes, 0x80, 4, mog_house and 1 or 2);
    for i = 1, #'Tester' do bytes[0x83 + i] = ('Tester'):byte(i); end
    return L.receive(0x00A, bytes);
end
-- 0x044: a job's set spells, each its id less 0x200, from 0x08; job at 0x04, 1 at 0x05 for a sub job's list.
function L.blue_set(job, sub, spells)
    local bytes = MOCK.bytes(0x9C);
    bytes[0x04], bytes[0x05] = job, sub;
    for index, spell in ipairs(spells) do bytes[0x07 + index] = spell; end
    return L.receive(0x044, bytes);
end

-- vantage.lua loaded and your settings read, then overhead icons turned on by command.
function L.start()
    L.app = dofile(ADDON_DIR .. '/vantage.lua');
    handler('load', 'vantage_load')();
    L.frame();
    local on = L.command('/vg overhead on');
    assert(on.blocked == true and L.app.state.settings.overhead.enabled == true, 'Fixture: /vg overhead on, through a userdata command.');
    L.frame(); L.frame();
    return L.app;
end

-- The tracker view's row for an entity's effect, or nil.
function L.row(entity_id, effect)
    for _, row in ipairs(L.app.state.view.rows or {}) do
        if row.entity_id == entity_id and row.effect == effect and row.domain ~= 'recast' then return row; end
    end
end
-- The overhead block placed for an entity this frame, or nil.
function L.unit(entity_id)
    local plan = require('core.overhead').plan;
    for i = 1, plan.count do if plan.units[i].id == entity_id then return plan.units[i]; end end
end
-- Whether this frame drew the icon for an effect id.
function L.drew(effect)
    for _, texture in ipairs(L.images) do if texture == 5000 + effect then return true; end end
    return false;
end

return L;
