-- A client for the name point tests. The decoded client image (FFXiMain.dll 04288488) is where the first frame with
-- overhead icons on finds the client patterns; each unit's actor, entity and skeleton live in a fake memory beside
-- it, with page checks over just the blocks made here. The camera is the game's: right-handed, the P11 and P22 of a
-- Phoenix /vg report and the client's own near and far planes (0.1 and 65535), 8 yalms behind you and 4 up, looking
-- ahead along -Y down to a point 1.2 over you. The display is 1920x1080, so a name's font texel is 2.53125 px at full
-- size.
local W = require('overhead_fixture');
local image = require('client_image_fixture').load('new'):install();
local N = { W = W, memory = {}, regions = {}, image = image, layouts = {} };
local memory, regions = N.memory, N.regions;
local base, finish = image.base, image.base + #image.data;
local u8, u16, u32 = ashita.memory.read_uint8, ashita.memory.read_uint16, ashita.memory.read_uint32;
local function from(read) return function(at) if at >= base and at < finish then return read(at); end return memory[at]; end; end
ashita.memory.read_uint8, ashita.memory.read_uint16, ashita.memory.read_uint32 = from(u8), from(u16), from(u32);
ashita.memory.read_float = function(at) return memory[at]; end;
ashita.memory.read_int32 = function(at) return memory[at]; end;
-- Page checks over the client module and the blocks made here, by start and size; N.closed[start] makes one
-- unreadable.
N.closed = {};
regions[1] = { base, #image.data };
local function valid(at, size)
    for i = 1, #regions do
        local start, length = regions[i][1], regions[i][2];
        if at >= start and at + size <= start + length then return not N.closed[start]; end
    end
    return false;
end
N.valid = valid;
require('core.memory').pages = function() return { valid = valid, readable = valid }; end;
require('core.client')._set_pages(function() return true; end);

-- The game's camera.
local P11, P22, zn, zf = 0.74774223566055, 1.2604166269302, 0.1, 65535;
W.projection_matrix = { P11, 0, 0, 0, 0, P22, 0, 0, 0, 0, zf / (zn - zf), -1, 0, 0, zn * zf / (zn - zf), 0 };
local function unit_vector(x, y, z) local length = math.sqrt(x * x + y * y + z * z); return x / length, y / length, z / length; end
local eye, at = { 0, -4, 8 }, { 0, -1.2, 0 };
local zx, zy, zz = unit_vector(eye[1] - at[1], eye[2] - at[2], eye[3] - at[3]);
local xx, xy, xz = unit_vector(-zz, 0, zx);
local yx, yy, yz = zy * xz - zz * xy, zz * xx - zx * xz, zx * xy - zy * xx;
W.view_matrix = { xx, yx, zx, 0, xy, yy, zy, 0, xz, yz, zz, 0, -(xx * eye[1] + xy * eye[2] + xz * eye[3]),
    -(yx * eye[1] + yy * eye[2] + yz * eye[3]), -(zx * eye[1] + zy * eye[2] + zz * eye[3]), 1 };

local function region(start, size) regions[#regions + 1] = { start, size }; end

-- A unit with its actor, entity and skeleton. gen is point 2's offset in yalms (up is negative, as in render space),
-- scale the actor's x, y and z. The root sits on the entity's position.
function N.unit(index, id, kind, x, y, gen, fields)
    local e = W.unit(index, id, kind, x, y, fields);
    local actor, entity, node, data = 0x3000000 + index * 0x1000, 0x4000000 + index * 0x400, 0x5000000 + index * 0x100,
        0x6000000 + index * 0x1000;
    local handle, bones = node + 0x80, 20;
    local table_at = data + 0x34 + bones * 0x1E;
    local entry = table_at + 4 + 2 * 0x1A;
    e.actor = actor;
    local layout = { actor = actor, entity = entity, node = node, handle = handle, data = data, table_at = table_at, entry = entry };
    N.layouts[index] = layout;
    -- The node, its handle, the bone list and the generator table each in a block of its own, so a test can close one.
    region(actor, 0x1000); region(entity, 0x400); region(node, 0x80); region(handle, 0x80); region(data, table_at - data);
    region(table_at, data + 0x1000 - table_at);
    memory[actor + 0x70], memory[actor + 0xA4], memory[actor + 0x6B8] = entity, 0, node;
    memory[actor + 0x698], memory[actor + 0x6A0], memory[actor + 0x69C] = 1, 1, 1;
    memory[actor + 0x754], memory[actor + 0x75C], memory[actor + 0x8C0] = 1, -1, 0;
    memory[actor + 0x8A6], memory[actor + 0x8A7] = 2, 2;
    -- What only the report reads: the name's size and hide bits, the other two model sizes and the attachment
    -- offset (the position copy moves with the unit).
    memory[actor + 0x88], memory[actor + 0x8C], memory[actor + 0xB2], memory[actor + 0x758], memory[actor + 0x760] = 0, 0, 0, 1, 1;
    memory[actor + 0x60C], memory[actor + 0x610], memory[actor + 0x614] = 0, 0, 0;
    memory[entity + 0x78], memory[entity + 0xA0], memory[entity + 0x204] = id, actor, -1;
    memory[node + 0x0C], memory[handle], memory[data + 0x32] = handle, data, bones;
    memory[table_at], memory[entry] = 6, 0;
    memory[entry + 2], memory[entry + 6], memory[entry + 0x0A] = 0, 0, 0;
    memory[entry + 0x0E], memory[entry + 0x12], memory[entry + 0x16] = gen[1], gen[2], gen[3];
    N.move(index, x, y);
    return e, layout;
end

-- Moves a unit, its root and the actor's copy of its position with it.
function N.move(index, x, y)
    local e, actor = W.entities[index], N.layouts[index].actor;
    e.x, e.y = x, y;
    memory[actor + 0x678], memory[actor + 0x67C], memory[actor + 0x680] = e.x, e.z, e.y;
    memory[actor + 0x5FC], memory[actor + 0x600], memory[actor + 0x604] = e.x, e.z, e.y;
end

-- The game's name point of a unit, as the client works it out with no lift: root plus point 2 times the scale.
function N.point(index)
    local actor = N.layouts[index].actor;
    local entry = N.layouts[index].entry;
    return memory[actor + 0x678] + memory[entry + 0x0E] * memory[actor + 0x698],
        memory[actor + 0x67C] + memory[entry + 0x12] * memory[actor + 0x6A0] + memory[actor + 0x8C0],
        memory[actor + 0x680] + memory[entry + 0x16] * memory[actor + 0x69C];
end

-- The target window, with the getters Ashita has: the action callback (a command picking its target), the death
-- flag, the main cursor's and the subtarget cursor's stored points in menu pixels, which entries are active or float,
-- and the cursor's frames.
N.window = { callback = 0, dead = 0, ank_x = 960, ank_y = 0, sub = 0, sub_x = 0, sub_y = -10, active = { [0] = 1, [1] = 1 },
    floating = { [0] = 0, [1] = 0 }, shapes = {} };
local targets = AshitaCore:GetMemoryManager():GetTarget();
N.targets = targets;
local window = N.window;
local getters = {
    GetActionCallback = function() return window.callback; end,
    GetWindowDeathFlag = function() return window.dead; end,
    GetWindowAnkX = function() return window.ank_x; end,
    GetWindowAnkY = function() return window.ank_y; end,
    GetWindowSub = function() return window.sub; end,
    GetWindowSubAnkX = function() return window.sub_x; end,
    GetWindowSubAnkY = function() return window.sub_y; end,
    GetWindowAnkNum = function() return 0; end,
    GetIsActive = function(_, slot) return window.active[slot] or 0; end,
    GetIsArrowActive = function(_, slot) return window.floating[slot] or 0; end,
    GetWindowAnkShape = function(_, i) return window.shapes[i + 1] or 0; end,
    GetActorPointer = function(self, slot) local e = W.entities[self:GetTargetIndex(slot)]; return e and e.actor or 0; end,
};
-- The window getters on or off (an Ashita without them).
function N.window_getters(on) for name, fn in pairs(getters) do targets[name] = on and fn or nil; end end
N.window_getters(true);

-- The game's own cursor frames: six, each -10 to 10 across and -32 to 0 over the point, or the boxes given.
local function s16(value) return value < 0 and value + 0x10000 or value; end
function N.frames(boxes)
    for i = #window.shapes, 1, -1 do window.shapes[i] = nil; end
    for i = 1, boxes and #boxes or 6 do
        local box = boxes and boxes[i] or { -10, 10, -32, 0 };
        local shape = 0x7000000 + i * 0x100;
        region(shape, 0x40);
        memory[shape + 0x20], memory[shape + 0x22], memory[shape + 0x24], memory[shape + 0x26] = s16(box[1]), s16(box[2]), s16(box[3]),
            s16(box[4]);
        window.shapes[i] = shape;
    end
end
N.frames();

function N.trunc(value) return value >= 0 and math.floor(value) or math.ceil(value); end

-- The name's texel on this display at NDC depth z: 1080 * 0.00234375, times the client's shrink past 4020 / 4096.
function N.texel(z)
    local zi = math.floor(z * 4096);
    local s = zi < 4020 and 1 or math.max(0, math.min(1, (4100 - zi) / 80));
    return 1080 * 0.00234375 * s, s;
end

return N;
