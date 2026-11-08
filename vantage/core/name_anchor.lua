-- The point the game hangs each name and its target cursor from, read from the client, so an overhead block can sit
-- a few pixels over the game's own name. The struct offsets are read out of the client's own code, found by byte
-- patterns through core/patterns.lua: one warmup step for each pattern and one for the offsets
-- (anchor.warmup_steps), or all at once the first time overhead icons are on. A pattern that is missing, found twice
-- or gives an offset out of range turns this off for every unit, and the blocks keep the guessed heights. Every range
-- is page checked before it is read, nothing is written and a frame makes nothing. docs/OVERHEAD.md.
local anchor = {};
local bit = require('bit');
local memory = require('core.memory');
local finder = require('core.patterns');
local band, rshift = bit.band, bit.rshift;
local floor, ceil, abs, huge = math.floor, math.ceil, math.abs, math.huge;

-- The client code the name point is read from (FFXiMain.dll 04288488 and f2245d1c alike): the caller that adds the
-- last height to the point, the name's and the cursor's point index getters, the point function that copies the
-- root, takes the skeleton and its scale and asks for point 2 of the first node, the node's generator handle and
-- data, the bone and generator tables, the entity back pointer with its model size, the model size pick for the
-- mounted and seated lifts and the three actor kind gates that skip them.
local patterns = {
    lift = 'FF93B400000025FF0000008BCE50FF93C4010000D986????????',
    name_index = '8A81A7080000C3',
    arrow_index = '8A81A6080000C3',
    root = '83EC58538B5C246455568BF1578DBE????????',
    skeleton = '8DAE????????51578B7C24745253576A00568BCDE8',
    scale = '8B086A02E8????????D946??D95C241CD946??D95C2420D946??',
    node = '83FF028BF10F85????????E8????????8B0885C9',
    handle = '8B41??568D71??85C0740B8BCEE8????????84C07504',
    generator_offset = '8D4E??50E8????????85C05E74118B4C244883C0??',
    bones = '668B48??8D0C498D0C898D4448??C3',
    generators = '8B4C24048D14498D0C918D4448??',
    entity = '8B41??85C07407D980????????C3',
    model_pick = 'D986????????D81D????????DFE0F6C4057A2B8B068BCEFF90????????D81D????????DFE0F6C4057A08D986????????EB1E8B168BCEFF92????????EB12D986????????EB0A8B068BCEFF90????????D84C24??8B4424??5F5E5DD84004D95804',
    gate_mount = '8B81????????83F8547C087F06',
    gate_chocobo = '8B81????????83F8017C0B83F8047F06',
    gate_chair = '8B81????????83F83D7C0B83F8517F06',
};
-- For /vg report only: the client's own camera copies, the device wrapper's cached transforms and viewport, and the
-- sizes of the window and of the scene target the names are drawn into, to check the camera Vantage reads against
-- the one the names are drawn with. Missing ones only leave that check out.
local check_patterns = {
    app_view = 'A1????????0594000000C3',
    app_projection = 'A1????????0554010000C3',
    wrapper_transforms = '8B4424045683E8025774??4874??2DFD00000075??8B7C24108DB1????????B910000000F3A55F5EC208008B7C24108DB1????????B910000000F3A55F5EC208008B7C24108DB1????????',
    wrapper = '83EC088B0D????????E8????????8B480C8B5008',
    wrapper_again = 'E8????????E8????????8B0D????????506A03E8????????5F5EE9',
    viewport = '33C08A81????????8D04408D84C1????????C3',
    sizes = '33D233C9668B56??668B4E??33C089542430668B46??33D2668B56??',
};
local NAMES, CHECK_NAMES = {}, {};
for name in pairs(patterns) do NAMES[#NAMES + 1] = name; end
for name in pairs(check_patterns) do CHECK_NAMES[#CHECK_NAMES + 1] = name; end
table.sort(NAMES);
table.sort(CHECK_NAMES);

-- The entity fields the back-link reads (Ashita's entity_t): its server id and its actor pointer.
local SERVER_ID, ACTOR = 0x78, 0xA0;
-- The point index both patterns pin, and the size of a bone and of a generator entry, fixed by the code's own
-- arithmetic.
local POINT, BONE_SIZE, GENERATOR_SIZE = 2, 0x1E, 0x1A;
-- Status lifts: chocobo 5 and mount 85 raise by 1.3 times the model size, chairs 63 to 83 by 0.5. A mount's own
-- lift comes from its race tables; the highest, 1.3, is used for all, so a mounted name is never under the block.
local MOUNT, CHOCOBO, CHAIR_LOW, CHAIR_HIGH = 85, 5, 63, 83;
local RIDING, SEATED = -1.3, -0.5;
-- What /vg report reads at offsets fixed for this client rather than found by a pattern.
local FIXED = 'Fixed for client 04288488, not found by a pattern: rotation_x to _z (point 2 + 2, + 6, + 0xA), base_x to _z '
    .. '(actor + 0x5FC), offset_x to _z (actor + 0x60C), actor_88, actor_8c, actor_b2 and actor_754 to actor_760.';

local found, check_found, off = {}, {}, {};
local state = { loaded = false, usable = false, problem = 'Overhead icons have not been on yet.', failed = nil };
local check = { loaded = false, usable = false, problem = nil };
local pages;
-- The arrows this frame: the unit each sits on (0 for none), whether its stored screen point is used, and that
-- point in the game's menu pixels. box_low is the highest row of the cursor's frames over its point, in menu
-- pixels, and ky the display pixels per menu pixel.
local arrows = { a = 0, a_stored = false, a_y = 0, b = 0, b_stored = false, b_y = 0, box_low = -32, box = 'fallback',
    ky = 1, full = false, generation = -1 };
-- The wrapper's view and projection as the scene read took them, for /vg report.
local scene_copy, scene_taken, scene_calls = {}, false, 0;
for i = 1, 32 do scene_copy[i] = 0; end

local address = memory.address;
local function finite(value) return value == value and value > -1e6 and value < 1e6; end

-- Page checks through core/memory.lua, made once.
local function readable(at, size)
    if pages == nil then
        local ok, value = pcall(memory.pages);
        pages = ok and type(value) == 'table' and value.valid or false;
    end
    return pages ~= false and address(at) and pages(at, size, false) == true;
end

-- The one match inside the client module, as core/clock.lua finds its own.
local RULE = { unique = true, within = true };

local function module_range()
    if type(ashita.memory.get_base) ~= 'function' then return nil, nil; end
    local ok, base, size = pcall(function() return ashita.memory.get_base('FFXiMain.dll'), ashita.memory.get_size('FFXiMain.dll'); end);
    if ok then return base, size; end
end

-- The camera check's patterns in order, until one fails: its name and why.
local function find_all(names, list, into)
    for _, name in ipairs(names) do
        local at, why = finder.find('camera_check', name, list[name], RULE);
        into[name] = at;
        if not at then return name, why; end
    end
end

-- A byte or a 32-bit word of the client's code, inside the module when its range is known.
local function code(at, width, base, size)
    if address(base) and type(size) == 'number' and (at < base or at + width > base + size) then return nil; end
    local ok, value = pcall(width == 1 and ashita.memory.read_uint8 or ashita.memory.read_uint32, at);
    return ok and type(value) == 'number' and value or nil;
end

local function fits(value, low, high, step) return type(value) == 'number' and value >= low and value <= high and value % step == 0; end

-- The offsets out of the matches, each held to what the code around it allows. Returns the name of the first
-- pattern whose operands don't fit, or nil.
local function operands(base, size)
    local function byte(name, at) return code(found[name] + at, 1, base, size); end
    local function word(name, at) return code(found[name] + at, 4, base, size); end
    off.lift = word('lift', 22);
    if not fits(off.lift, 0x100, 0x1000, 4) then return 'lift'; end
    off.name_index = word('name_index', 2);
    if not fits(off.name_index, 0x100, 0x1000, 1) then return 'name_index'; end
    off.arrow_index = word('arrow_index', 2);
    if not fits(off.arrow_index, 0x100, 0x1000, 1) then return 'arrow_index'; end
    off.root = word('root', 15);
    if not fits(off.root, 0x100, 0x1000, 4) then return 'root'; end
    local skeleton = word('skeleton', 2);
    if not fits(skeleton, 0x100, 0x1000, 4) then return 'skeleton'; end
    -- The scale's x, y and z, in that order in the code but not in memory.
    local sx, sy, sz = byte('scale', 11), byte('scale', 18), byte('scale', 25);
    if not (fits(sx, 4, 0x7C, 4) and fits(sy, 4, 0x7C, 4) and fits(sz, 4, 0x7C, 4)) or sx == sy or sy == sz or sx == sz then
        return 'scale';
    end
    off.scale_x, off.scale_y, off.scale_z = skeleton + sx, skeleton + sy, skeleton + sz;
    -- The node list: the call at +11 goes to a getter that returns the list's address in the skeleton
    -- (lea eax, [ecx + list]; ret).
    local relative = word('node', 12);
    if not relative then return 'node'; end
    local target = found.node + 16 + (relative >= 0x80000000 and relative - 0x100000000 or relative);
    if code(target, 1, base, size) ~= 0x8D or code(target + 1, 1, base, size) ~= 0x41 or code(target + 3, 1, base, size) ~= 0xC3 then
        return 'node';
    end
    local list = code(target + 2, 1, base, size);
    if not fits(list, 4, 0x7C, 4) then return 'node'; end
    off.node = skeleton + list;
    -- The node's handle holder, the handle's slot in it (read twice by the code) and the generator's offset. The point's
    -- three floats have to end inside its generator entry, the span skeleton checks before it reads them.
    local slot, again = byte('handle', 2), byte('handle', 6);
    if slot ~= again or not fits(slot, 4, 0x7C, 4) then return 'handle'; end
    local holder, point = byte('generator_offset', 2), byte('generator_offset', 20);
    if not fits(holder, 4, 0x7C, 4) or not fits(point, 2, GENERATOR_SIZE - 12, 2) then return 'generator_offset'; end
    off.handle, off.point = holder + slot, point;
    local count, start = byte('bones', 3), byte('bones', 13);
    if not fits(count, 2, 0x7E, 2) or not fits(start, 2, 0x7E, 2) or start <= count then return 'bones'; end
    off.bone_count, off.bones = count, start;
    off.generators = byte('generators', 13);
    if not fits(off.generators, 2, 0x20, 2) then return 'generators'; end
    off.entity, off.model_size = byte('entity', 2), word('entity', 9);
    if not fits(off.entity, 4, 0x7C, 4) or not fits(off.model_size, 0x100, 0x1000, 4) then return 'entity'; end
    off.model_first, off.model_last = word('model_pick', 2), word('model_pick', 44);
    if word('model_pick', 64) ~= off.model_first or not fits(off.model_first, 0x100, 0x1000, 4) or not fits(off.model_last, 0x100, 0x1000, 4) then
        return 'model_pick';
    end
    off.kind = word('gate_mount', 2);
    if not fits(off.kind, 4, 0x1000, 4) then return 'gate_mount'; end
    if word('gate_chocobo', 2) ~= off.kind then return 'gate_chocobo'; end
    if word('gate_chair', 2) ~= off.kind then return 'gate_chair'; end
    -- One page check covers every actor field read.
    local low, high = huge, 0;
    for _, at in ipairs({ off.entity, off.kind, off.root, off.root + 8, off.scale_x, off.scale_y, off.scale_z, off.node, off.model_first,
        off.model_last, off.lift, off.name_index, off.arrow_index }) do
        if at < low then low = at; end
        if at + 4 > high then high = at + 4; end
    end
    off.low, off.span = low, high - low;
    off.entity_span = math.max(ACTOR, off.model_size) + 4 - SERVER_ID;
end

-- One pattern, in the order of NAMES. After one fails, or without the client's memory, the rest are not looked for.
local looked = { failed = nil, why = nil, unavailable = false };
local function find_pattern(name)
    if looked.failed or looked.unavailable then return; end
    if not ashita or not ashita.memory or type(ashita.memory.find) ~= 'function' then looked.unavailable = true; return; end
    local at, why = finder.find('name_anchor', name, patterns[name], RULE);
    found[name] = at;
    if not at then looked.failed, looked.why = name, why; end
end

-- Reads the offsets out of the matches, once the patterns are looked for, and settles whether the name point can be
-- used.
local function settle()
    state.loaded = true;
    local ok, why = pcall(function()
        if looked.unavailable then error('Client memory access is unavailable.', 0); end
        if looked.failed then state.failed = looked.failed; error(('The client pattern %s %s.'):format(looked.failed, looked.why), 0); end
        local base, size = module_range();
        local name = operands(base, size);
        if name then state.failed = name; error(('The client pattern %s gives an offset out of range.'):format(name), 0); end
    end);
    state.usable, state.problem = ok, not ok and tostring(why) or nil;
end

local done, STEPS = {}, {};
for _, name in ipairs(NAMES) do
    STEPS[#STEPS + 1] = finder.step('name_anchor.' .. name, done, function() find_pattern(name); end);
end
STEPS[#STEPS + 1] = finder.step('name_anchor.operands', done, function()
    for index = 1, #NAMES do STEPS[index].run(); end
    settle();
end);

-- The name point's warmup steps, in order, as { name, run }: one search for each pattern, in sorted name order, then
-- the offsets. Until the last has run, no unit gets a name point.
function anchor.warmup_steps()
    local list = {};
    for index, step in ipairs(STEPS) do list[index] = step; end
    return list;
end

-- Finds the patterns and reads the offsets, once, running whichever steps have not run. Returns whether the name
-- point can be used.
function anchor.load()
    if state.loaded then return state.usable; end
    for _, step in ipairs(STEPS) do step.run(); end
    return state.usable;
end

function anchor.usable() return state.usable; end
-- Why the name points are off, or nil.
function anchor.problem() return state.problem; end

-- Turns the name points off after a read raised an error, with why, for /vg report.
function anchor.fail(why)
    state.usable, state.problem = false, 'Reading a name point failed. ' .. tostring(why);
end

local function signed16(value) return value >= 0x8000 and value - 0x10000 or value; end

-- Point 2 of the unit's first skeleton node: the bone it hangs from and its offset, as the client keeps them. A
-- node, handle or data of 0 is a point the client puts at the root, as it does while the model loads. Fills cache
-- and returns nil, or why it can't be read. detail, a table, takes the raw values for /vg report.
local function skeleton(cache, node, detail)
    local mem = ashita.memory;
    cache.np_gx, cache.np_gy, cache.np_gz, cache.np_bone, cache.np_count = 0, 0, 0, 0, 0;
    if node == 0 then return nil; end
    if not readable(node + off.handle, 4) then return 'The skeleton can\'t be read.'; end
    local handle = mem.read_uint32(node + off.handle);
    if detail then detail.handle = handle; end
    if handle == 0 then return nil; end
    if not readable(handle, 4) then return 'The skeleton can\'t be read.'; end
    local data = mem.read_uint32(handle);
    if detail then detail.data = data; end
    if data == 0 then return nil; end
    if not readable(data + off.bone_count, 2) then return 'The skeleton can\'t be read.'; end
    local bones = mem.read_uint16(data + off.bone_count);
    if detail then detail.bones = bones; end
    if bones < 1 or bones > 512 then return 'The skeleton is out of range.'; end
    local table_at = data + off.bones + bones * BONE_SIZE;
    local entry = table_at + off.generators + POINT * GENERATOR_SIZE;
    if not readable(table_at, entry + GENERATOR_SIZE - table_at) then return 'The skeleton can\'t be read.'; end
    local count = mem.read_uint16(table_at);
    local bone = signed16(mem.read_uint16(entry));
    local gx, gy, gz = mem.read_float(entry + off.point), mem.read_float(entry + off.point + 4), mem.read_float(entry + off.point + 8);
    if detail then
        detail.generators, detail.bone = count, bone;
        detail.rotation_x, detail.rotation_y, detail.rotation_z = mem.read_float(entry + 2), mem.read_float(entry + 6),
            mem.read_float(entry + 0x0A);
    end
    if count < POINT + 1 or count > 0x80 then return 'The skeleton is out of range.'; end
    if not (finite(gx) and finite(gy) and finite(gz)) or abs(gx) > 4 or abs(gz) > 4 or gy > 0 or gy < -16 then
        return 'Point 2 of the skeleton is out of range.';
    end
    cache.np_gx, cache.np_gy, cache.np_gz, cache.np_bone, cache.np_count = gx, gy, gz, bone, count;
end

-- How far, in font texels, the first icon in front of a name reaches over the name's top: the client's own choice
-- of icon (FFXiMain.dll 10097500, 10097730 and 100977A0) and each icon's height in its font. 0 with none.
local RISE = {};
for glyph = 0x8E, 0x91 do RISE[glyph] = 2; end
RISE[0x92], RISE[0x93] = 1.0625, 1.0625;
for glyph = 0x94, 0x99 do RISE[glyph] = 2; end
for glyph = 0x9D, 0xA9 do RISE[glyph] = 2; end
RISE[0x9C], RISE[0xAB], RISE[0xAC] = 0, 2, 4;
for glyph = 0xAE, 0xB1 do RISE[glyph] = 4; end
-- Ballista and campaign icons pick from the unit's Ballista data, which isn't read here; each of them reaches 2.
local BALLISTA = 0x9E;

function anchor.rise(entities, index, id)
    local f0, f1, f2, f3 = entities:GetRenderFlags0(index), entities:GetRenderFlags1(index), entities:GetRenderFlags2(index),
        entities:GetRenderFlags3(index);
    local f4, f7, f8 = entities:GetRenderFlags4(index), entities:GetRenderFlags7(index), entities:GetRenderFlags8(index);
    local camp, ballista, monster = entities:GetCampaignNameFlag(index), entities:GetBallistaFlags(index), entities:GetMonstrosityFlag(index);
    local pc, high = band(id, 0xFF000000) == 0, rshift(id, 24) == 1;
    local ranked = ballista >= 2 and ballista <= 0x27 or ballista >= 0x2C and ballista <= 0x63;
    local default = pc and band(f1, 0x08000000) ~= 0 and 0x92 or 0;
    local first, second = 0, 0;
    if band(f1, 0x04000000) ~= 0 then first = 0x8E;
    elseif band(f1, 0x10000000) ~= 0 then first = 0x8F;
    elseif monster ~= 0 then first = 0xAB;
    elseif ranked then first = BALLISTA;
    elseif band(f1, 0x400000) ~= 0 then
        local job = band(rshift(f1, 1), 7);
        first = not high and 0x90 or job == 5 and 0xAE or job == 6 and 0xAF or job == 7 and 0xB0 or default;
    elseif band(f3, 0x40000) == 0 and band(rshift(f2, 11), 7) ~= 0 then
        local mark = band(rshift(f2, 11), 7);
        first = mark <= 2 and 0x93 or 0x92 + mark;
    elseif camp ~= 0 then first = 0x94;
    elseif band(f8, 0x8) ~= 0 then first = 0xAC;
    elseif band(f1, 0x200000) ~= 0 then first = 0x9D;
    elseif band(f1, 0x100000) ~= 0 then first = 0x91;
    elseif band(f4, 0x800000) ~= 0 then first = 0xA8;
    elseif band(f4, 0x4000) ~= 0 then first = 0x93;
    elseif band(f4, 0x1000) ~= 0 then first = pc and 0xA2 or 0xB1;
    elseif band(f4, 0x2000) ~= 0 then first = 0xA1;
    elseif band(f2, 0x200) ~= 0 then first = 0x9C;
    else first = default; end
    local lead = 0;
    if ballista == 8 or ballista == 9 then
        local j = monster ~= 0 and band(rshift(f7, 4), 3) or band(rshift(f7, 2), 3);
        if j < 3 then lead = 0xA9; end
    end
    if lead ~= 0 and first ~= 0xAB then first = 0; end
    if first ~= 0 and (ranked or camp ~= 0) then
        second = band(f8, 0x8) ~= 0 and 0xAC or band(f1, 0x200000) ~= 0 and 0x9D or band(f1, 0x100000) ~= 0 and 0x91
            or band(f4, 0x800000) ~= 0 and 0xA8 or 0;
    end
    local rise = RISE[lead ~= 0 and lead or first] or 0;
    if second == 0xAC then rise = 4; end
    if lead ~= 0 and first == 0xAB and rise < 2 then rise = 2; end
    -- The second line of stars over a player's name, drawn only with the name.
    local named = band(f0, 0x200) ~= 0 and band(f0, 0xC000) == 0 and band(f2, 0x8) == 0 and band(f4, 0x80) == 0;
    if pc and band(f7, 0x80) ~= 0 and named then rise = 18; end
    return rise, first, lead, second;
end

-- The game's name point for one unit, in render space as camera.project takes it: x, y, z, or nil and why not.
-- cache (a unit) keeps the skeleton's point and the icon rise between list rebuilds; they are read again when
-- generation changes or the skeleton moves, and cache.np_ai takes the cursor's point index each frame. detail, a
-- table, takes every value read, for /vg report.
local function point(cache, entities, index, id, actor, generation, detail)
    if not state.usable then return nil, 'The client patterns were not found.'; end
    if not address(actor) then return nil, 'The unit has no actor.'; end
    if not readable(actor + off.low, off.span) then return nil, 'The actor can\'t be read.'; end
    local mem = ashita.memory;
    local read32, readf = mem.read_uint32, mem.read_float;
    -- The actor's kind, which the chocobo, mount and chair gates test.
    if detail then detail.actor_kind = mem.read_int32(actor + off.kind); end
    local entity = read32(actor + off.entity);
    local owned = address(entity) and readable(entity + SERVER_ID, off.entity_span) and read32(entity + SERVER_ID) == id
        and read32(entity + ACTOR) == actor;
    if detail then detail.actor, detail.entity, detail.back_link = actor, entity, owned; end
    if not owned then return nil, 'The actor is not this unit\'s.'; end
    local ni, ai = mem.read_uint8(actor + off.name_index), mem.read_uint8(actor + off.arrow_index);
    cache.np_ai = ai;
    if detail then detail.name_index, detail.arrow_index = ni, ai; end
    if ni ~= POINT then return nil, 'The name uses another point.'; end
    local rx, ry, rz = readf(actor + off.root), readf(actor + off.root + 4), readf(actor + off.root + 8);
    local sx, sy, sz = readf(actor + off.scale_x), readf(actor + off.scale_y), readf(actor + off.scale_z);
    local raise = readf(actor + off.lift);
    local node = read32(actor + off.node);
    if detail then
        detail.root_x, detail.root_y, detail.root_z, detail.scale_x, detail.scale_y, detail.scale_z = rx, ry, rz, sx, sy, sz;
        detail.lift, detail.node = raise, node;
    end
    if not (finite(rx) and finite(ry) and finite(rz) and finite(raise)) or abs(raise) >= 10 then return nil, 'Its values are out of range.'; end
    if not (sx > 0 and sx <= 20 and sy > 0 and sy <= 20 and sz > 0 and sz <= 20) then return nil, 'Its scale is out of range.'; end
    -- The unit's (X, Z, Y) is where the root should be, up to the model's own sway.
    local ex, ey, ez = entities:GetLocalPositionX(index), entities:GetLocalPositionZ(index), entities:GetLocalPositionY(index);
    if detail then detail.entity_x, detail.entity_y, detail.entity_z = ex, ey, ez; end
    if (rx - ex) ^ 2 + (ry - ey) ^ 2 + (rz - ez) ^ 2 > 100 then return nil, 'The root is far from the unit.'; end
    if node ~= cache.np_node or generation ~= cache.np_gen or detail then
        cache.np_node, cache.np_gen = node, generation;
        cache.np_bad = skeleton(cache, node, detail) or false;
        cache.np_rise = cache.np_bad == false and anchor.rise(entities, index, id) or 0;
    end
    if cache.np_bad then return nil, cache.np_bad; end
    local x, y, z = rx + cache.np_gx * sx, ry + cache.np_gy * sy, rz + cache.np_gz * sz;
    -- Mounted, on a chocobo or in a chair, the client raises the name by the model's size, unless the point hangs
    -- from a bone or the actor is the mount or chair itself.
    local m = 0;
    if cache.np_bone == 0 then
        local status = entities:GetStatus(index);
        local kind = mem.read_int32(actor + off.kind);
        if status == MOUNT and kind ~= 0x54 or status == CHOCOBO and not (kind >= 1 and kind <= 4) then m = RIDING;
        elseif status >= CHAIR_LOW and status <= CHAIR_HIGH and not (kind >= 0x3D and kind <= 0x51) then m = SEATED; end
    end
    if m ~= 0 then
        local h = readf(entity + off.model_size);
        if not (h >= 0) then
            h = readf(actor + off.model_first);
            if not (h >= 0) then h = readf(actor + off.model_last); end
        end
        if not finite(h) then return nil, 'Its values are out of range.'; end
        y = y + m * h;
        if detail then detail.model = h; end
    end
    if detail then detail.m = m; end
    return x, y + raise, z;
end

-- For /vg report, the reads at fixed offsets (FIXED): the actor's copy of the unit's position and its attachment
-- offset, whose sum the client makes the root, the four model sizes, and the name's size and hide bits.
local function fixed(actor, detail)
    if not address(actor) or not readable(actor + 0x88, 0x764 - 0x88) then return; end
    local mem = ashita.memory;
    local readf = mem.read_float;
    detail.base_x, detail.base_y, detail.base_z = readf(actor + 0x5FC), readf(actor + 0x600), readf(actor + 0x604);
    detail.offset_x, detail.offset_y, detail.offset_z = readf(actor + 0x60C), readf(actor + 0x610), readf(actor + 0x614);
    detail.actor_754, detail.actor_758, detail.actor_75c, detail.actor_760 = readf(actor + 0x754), readf(actor + 0x758),
        readf(actor + 0x75C), readf(actor + 0x760);
    detail.actor_88, detail.actor_8c, detail.actor_b2 = mem.read_uint32(actor + 0x88), readf(actor + 0x8C), mem.read_uint16(actor + 0xB2);
end

function anchor.point(cache, entities, index, id, actor, generation)
    return point(cache, entities, index, id, actor, generation, nil);
end

-- Everything point reads for one unit, fresh, for /vg report: a table, with x, y, z when it gives a point and
-- reason when not, the flags its icon is picked from and, with the patterns found, the reads at fixed offsets.
function anchor.detail(entities, index, id, actor)
    local detail, cache = {}, { np_gen = -1 };
    local x, y, z = point(cache, entities, index, id, actor, -1, detail);
    if x then detail.x, detail.y, detail.z = x, y, z; else detail.reason = y; end
    detail.generator_x, detail.generator_y, detail.generator_z = cache.np_gx, cache.np_gy, cache.np_gz;
    detail.generator_zero = cache.np_gx == 0 and cache.np_gy == 0 and cache.np_gz == 0 and cache.np_bad == false or nil;
    if cache.np_bad == false then
        local rise, first, lead, second = anchor.rise(entities, index, id);
        detail.rise, detail.icon, detail.lead, detail.second_icon = rise, first, lead, second;
    end
    detail.flags0, detail.flags1, detail.flags2, detail.flags3 = entities:GetRenderFlags0(index), entities:GetRenderFlags1(index),
        entities:GetRenderFlags2(index), entities:GetRenderFlags3(index);
    detail.flags4, detail.flags7, detail.flags8 = entities:GetRenderFlags4(index), entities:GetRenderFlags7(index),
        entities:GetRenderFlags8(index);
    detail.campaign, detail.ballista, detail.monstrosity = entities:GetCampaignNameFlag(index), entities:GetBallistaFlags(index),
        entities:GetMonstrosityFlag(index);
    if state.usable then fixed(actor, detail); end
    return detail;
end

local function call(target, name, ...)
    local method = target[name];
    if not method then return nil; end
    return method(target, ...);
end

-- The cursor's frames, read again with each list rebuild: the union of their boxes over the cursor's point, in the
-- game's menu pixels. Every frame of the game's own cursor has -10 to 10 and -32 to 0; that is used when the
-- frames can't be read.
local function cursor_box(targets)
    local low, high, left, right = huge, -huge, huge, -huge;
    local mem = ashita.memory;
    for i = 0, 15 do
        local shape = call(targets, 'GetWindowAnkShape', i);
        if not shape or shape == 0 then break; end
        if not readable(shape + 0x20, 8) then low = huge; break; end
        local x0, x1 = signed16(mem.read_uint16(shape + 0x20)), signed16(mem.read_uint16(shape + 0x22));
        local y0, y1 = signed16(mem.read_uint16(shape + 0x24)), signed16(mem.read_uint16(shape + 0x26));
        if x0 < left then left = x0; end
        if x1 > right then right = x1; end
        if y0 < low then low = y0; end
        if y1 > high then high = y1; end
    end
    if left < right and low < high and low > -128 and low < 0 and high >= 0 and high <= 64 then
        arrows.box_low, arrows.box, arrows.box_left, arrows.box_right, arrows.box_high = low, 'read', left, right, high;
    else arrows.box_low, arrows.box, arrows.box_left, arrows.box_right, arrows.box_high = -32, 'fallback', -10, 10, 0; end
end

-- Where the target cursors are this frame, from the game's target window. Arrow A is the main one, on the target;
-- arrow B the subtarget's while a command picks one. Without those getters, A sits on main and B on sub with the
-- game's own cursor box. display_h is DisplaySize.y; the box and the menu scale are read again when generation
-- changes.
function anchor.arrows(targets, display_h, generation, main, sub)
    if generation ~= arrows.generation then
        arrows.generation = generation;
        arrows.full = targets ~= nil and targets.GetActionCallback ~= nil and targets.GetWindowAnkY ~= nil and targets.GetIsArrowActive ~= nil;
        if arrows.full then cursor_box(targets); else arrows.box_low, arrows.box = -32, 'fallback'; end
        local chat = package.loaded['core.chat'];
        local width, height;
        if chat and chat.menu_size then width, height = chat.menu_size(); end
        arrows.menu_width, arrows.menu_height = width, height;
        arrows.ky = type(height) == 'number' and height > 0 and display_h > 0 and display_h / height or 1;
    end
    if not arrows.full then
        arrows.a, arrows.a_stored, arrows.b, arrows.b_stored = main or 0, false, sub or 0, false;
        return;
    end
    local callback = (targets:GetActionCallback() or 0) ~= 0;
    local dead = (targets:GetWindowDeathFlag() or 0) ~= 0;
    local a = callback and 1 or 0;
    arrows.a, arrows.b = 0, 0;
    if not dead and targets:GetWindowAnkX() ~= 0 and targets:GetIsActive(a) ~= 0 then
        arrows.a, arrows.a_y, arrows.a_stored = targets:GetTargetIndex(a), targets:GetWindowAnkY(), targets:GetIsArrowActive(a) ~= 0;
    end
    if callback and not dead and targets:GetWindowSub() ~= 0 and targets:GetIsActive(0) ~= 0 then
        local x, y = targets:GetWindowSubAnkX(), targets:GetWindowSubAnkY();
        if not (x == 0 and y == -10) then arrows.b, arrows.b_y, arrows.b_stored = targets:GetTargetIndex(0), y, targets:GetIsArrowActive(0) ~= 0; end
    end
end

local function trunc(value) return value >= 0 and floor(value) or ceil(value); end

-- The top of the target cursor over the unit at index, in display pixels, and which arrow set it ('A', 'B'), or
-- huge and nil when no cursor is on it. ay is the name point on screen; the client keeps the cursor's point in
-- whole menu pixels and draws its box half a pixel up. When the cursor hangs from another point (ai, its point
-- index, is not 2) or floats, its stored point is used.
function anchor.arrow_top(index, ay, ai)
    local top, which, ky = huge, nil, arrows.ky;
    local own = trunc(ay / ky);
    if arrows.a == index and index > 0 then
        local y = (arrows.a_stored or ai ~= POINT and arrows.full) and arrows.a_y or own;
        top, which = (y + arrows.box_low - 0.5) * ky, 'A';
    end
    if arrows.b == index and index > 0 then
        local y = (arrows.b_stored or ai ~= POINT and arrows.full) and arrows.b_y or own - 10;
        local b = (y + arrows.box_low - 0.5) * ky;
        if b < top then top, which = b, 'B'; end
    end
    return top, which;
end

function anchor.arrow_units() return arrows.a, arrows.b; end

-- The report's view of the arrows and the target window.
local function window_report(targets)
    local out = { arrow_a = arrows.a, arrow_b = arrows.b, a_stored = arrows.a_stored, b_stored = arrows.b_stored,
        box = arrows.box, box_low = arrows.box_low, box_high = arrows.box_high, box_left = arrows.box_left, box_right = arrows.box_right,
        ky = arrows.ky, menu_width = arrows.menu_width, menu_height = arrows.menu_height, getters = arrows.full };
    if not targets or not arrows.full then return out; end
    local ok = pcall(function()
        out.action_callback = targets:GetActionCallback() ~= 0;
        out.death_flag, out.sub, out.frame = targets:GetWindowDeathFlag(), targets:GetWindowSub(), call(targets, 'GetWindowAnkNum');
        out.ank_x, out.ank_y = targets:GetWindowAnkX(), targets:GetWindowAnkY();
        out.sub_ank_x, out.sub_ank_y = targets:GetWindowSubAnkX(), targets:GetWindowSubAnkY();
        out.sub_target_active = call(targets, 'GetIsSubTargetActive');
        out.targets = {};
        for slot = 0, 1 do
            local actor = call(targets, 'GetActorPointer', slot);
            out.targets[slot + 1] = { slot = slot, index = targets:GetTargetIndex(slot), active = targets:GetIsActive(slot),
                arrow_active = targets:GetIsArrowActive(slot), actor = type(actor) == 'number' and ('0x%08X'):format(actor) or nil };
        end
        -- Each cursor frame and its box over the cursor's point, as read.
        out.frames = {};
        local mem = ashita.memory;
        for i = 0, 15 do
            local shape = targets:GetWindowAnkShape(i);
            if not shape or shape == 0 then break; end
            local frame = { shape = ('0x%08X'):format(shape) };
            if readable(shape + 0x20, 8) then
                frame.min_x, frame.max_x = signed16(mem.read_uint16(shape + 0x20)), signed16(mem.read_uint16(shape + 0x22));
                frame.min_y, frame.max_y = signed16(mem.read_uint16(shape + 0x24)), signed16(mem.read_uint16(shape + 0x26));
            end
            out.frames[#out.frames + 1] = frame;
        end
    end);
    if not ok then out.problem = 'The target window could not be read.'; end
    return out;
end

-- Pattern status for /vg report.
function anchor.status(targets)
    local out = { usable = state.usable, problem = state.problem, failed = state.failed, patterns = {}, offsets = {},
        window = window_report(targets), fixed_offsets = FIXED };
    for _, name in ipairs(NAMES) do out.patterns[name] = found[name] and ('0x%08X'):format(found[name]) or 'not found'; end
    if state.usable then for name, value in pairs(off) do out.offsets[name] = ('0x%X'):format(value); end end
    return out;
end

-- The camera check's patterns and their addresses, once, at the first /vg report.
local function load_check()
    if check.loaded then return check.usable; end
    check.loaded = true;
    local ok, why = pcall(function()
        local base, size = module_range();
        local name, reason = find_all(CHECK_NAMES, check_patterns, check_found);
        if name then error(('The client pattern %s %s.'):format(name, reason), 0); end
        local function byte(key, at) return code(check_found[key] + at, 1, base, size); end
        local function word(key, at) return code(check_found[key] + at, 4, base, size); end
        check.app, check.view, check.projection = word('app_view', 1), word('app_view', 6), word('app_projection', 6);
        check.wrapper = word('wrapper', 5);
        if not (check.app and word('app_projection', 1) == check.app and check.wrapper and word('wrapper_again', 12) == check.wrapper) then
            error('The client camera patterns do not agree.', 0);
        end
        check.world, check.wrapper_projection, check.wrapper_view = word('wrapper_transforms', 0x1B), word('wrapper_transforms', 0x31),
            word('wrapper_transforms', 0x47);
        check.viewport_index, check.viewports = word('viewport', 4), word('viewport', 14);
        check.window_w, check.scene_w, check.window_h, check.scene_h = byte('sizes', 7), byte('sizes', 11), byte('sizes', 21), byte('sizes', 27);
        for _, key in ipairs({ 'view', 'projection', 'world', 'wrapper_projection', 'wrapper_view', 'viewport_index', 'viewports' }) do
            if not fits(check[key], 4, 0x2000, 1) then error('The client camera offsets are out of range.', 0); end
        end
        for _, key in ipairs({ 'window_w', 'scene_w', 'window_h', 'scene_h' }) do
            if not fits(check[key], 2, 0x7E, 2) then error('The client size offsets are out of range.', 0); end
        end
    end);
    check.usable, check.problem = ok, not ok and tostring(why) or nil;
    return check.usable;
end

local function floats(at, count, into, start)
    if not readable(at, count * 4) then return false; end
    local readf = ashita.memory.read_float;
    for i = 0, count - 1 do into[start + i] = readf(at + i * 4); end
    return true;
end

-- At the scene read (core/camera.lua), every eighth one: the wrapper's view and projection as they are then.
function anchor.scene()
    if not check.usable then return; end
    scene_calls = scene_calls + 1;
    if scene_calls % 8 ~= 1 then return; end
    local wrapper = address(check.wrapper) and readable(check.wrapper, 4) and ashita.memory.read_uint32(check.wrapper);
    scene_taken = address(wrapper) and floats(wrapper + check.wrapper_view, 16, scene_copy, 1)
        and floats(wrapper + check.wrapper_projection, 16, scene_copy, 17) or false;
end

-- v times p (16 each, row order) into out.
local function multiply(v, vs, p, ps, out)
    for row = 0, 12, 4 do
        for column = 0, 3 do
            out[row + column + 1] = v[vs + row] * p[ps + column] + v[vs + row + 1] * p[ps + column + 4]
                + v[vs + row + 2] * p[ps + column + 8] + v[vs + row + 3] * p[ps + column + 12];
        end
    end
    return out;
end

-- The client's own cameras now, for /vg report: its copies (app), the wrapper's cache at the last scene read
-- (scene) and now (now), with the window's size, the size of the scene target the names are drawn into (app + 0x18
-- and + 0x1A, the client's own size for the name's font, then stretched onto the window) and the current viewport.
-- Each camera is 16 numbers, view times projection.
function anchor.cameras()
    local out = { usable = load_check(), problem = check.problem };
    if not out.usable then return out; end
    local mem = ashita.memory;
    local app = readable(check.app, 4) and mem.read_uint32(check.app);
    local wrapper = readable(check.wrapper, 4) and mem.read_uint32(check.wrapper);
    local raw = {};
    if address(app) and floats(app + check.view, 16, raw, 1) and floats(app + check.projection, 16, raw, 17) then
        out.app = multiply(raw, 1, raw, 17, {});
    end
    if address(app) and readable(app + check.window_w, 0x10) then
        out.window = { width = mem.read_uint16(app + check.window_w), height = mem.read_uint16(app + check.window_h) };
        out.scene_target = { width = mem.read_uint16(app + check.scene_w), height = mem.read_uint16(app + check.scene_h) };
    end
    if address(wrapper) and floats(wrapper + check.wrapper_view, 16, raw, 1) and floats(wrapper + check.wrapper_projection, 16, raw, 17) then
        out.now = multiply(raw, 1, raw, 17, {});
    end
    if scene_taken then out.scene = multiply(scene_copy, 1, scene_copy, 17, {}); end
    if address(wrapper) and readable(wrapper + check.viewport_index, 1) then
        local slot = mem.read_uint8(wrapper + check.viewport_index);
        local at = wrapper + check.viewports + slot * 0x18;
        if readable(at, 0x18) then
            out.viewport = { slot = slot, x = mem.read_uint32(at), y = mem.read_uint32(at + 4), width = mem.read_uint32(at + 8),
                height = mem.read_uint32(at + 12), min_z = mem.read_float(at + 16), max_z = mem.read_float(at + 20) };
        end
    end
    return out;
end

-- Where a camera from anchor.cameras puts a render-space point in display pixels, the way the client maps it: to
-- the scene target with half a pixel off, then stretched to the display. nil behind the camera.
function anchor.game_point(m, target, x, y, z, display_w, display_h)
    if not m or not target or target.width <= 0 or target.height <= 0 then return nil; end
    local w = x * m[4] + y * m[8] + z * m[12] + m[16];
    if not (w > 0) then return nil; end
    local nx = (x * m[1] + y * m[5] + z * m[9] + m[13]) / w;
    local ny = (x * m[2] + y * m[6] + z * m[10] + m[14]) / w;
    local gx = (nx + 1) * floor(target.width / 2) - 0.5;
    local gy = (1 - ny) * floor(target.height / 2) - 0.5;
    return gx * display_w / target.width, gy * display_h / target.height;
end

if VANTAGE_TEST_MODE then
    -- valid(ptr, length) in place of VirtualQuery.
    function anchor._set_pages(valid) pages = valid or nil; end
    function anchor._reset()
        for key in pairs(found) do found[key] = nil; end
        for key in pairs(check_found) do check_found[key] = nil; end
        for key in pairs(off) do off[key] = nil; end
        state.loaded, state.usable, state.problem, state.failed = false, false, 'Overhead icons have not been on yet.', nil;
        looked.failed, looked.why, looked.unavailable = nil, nil, false;
        for key in pairs(done) do done[key] = nil; end
        check.loaded, check.usable, check.problem = false, false, nil;
        arrows.generation, arrows.full, arrows.a, arrows.b = -1, false, 0, 0;
        scene_taken, scene_calls = false, 0;
    end
    anchor._patterns, anchor._check_patterns, anchor._offsets, anchor._check = patterns, check_patterns, off, check;
end

return anchor;
