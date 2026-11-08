-- Through the game's right-handed camera (the P11 and P22 of a Phoenix /vg report, a near plane of 0.5 and a far one
-- of 500, a view 6 yalms behind you and 2.5 up looking ahead), the target in front of you gets a block over its head,
-- above its name with the default layout, and its icons are drawn there; a debuffed mob behind the camera gets none;
-- calibrate says the camera is in use and the head sits above the feet.
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

local W = require('overhead_fixture');
local overhead = require('core.overhead');
local camera = require('core.camera');
local draw = require('ui.overhead_icons');
local plan = overhead.plan;
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);
local calls = {};
local list = setmetatable({}, { __index = function(_, name)
    return function(_, ...) calls[#calls + 1] = MOCK.copy_arguments(name, ...); end;
end });
rawset(require('imgui'), 'GetBackgroundDrawList', function() return list; end);

-- The camera: right-handed, as the game's is. Render space is (X, Z, Y) with up negative and you at the origin.
local P11, P22, zn, zf = 0.74774223566055, 1.2604166269302, 0.5, 500;
W.projection_matrix = { P11, 0, 0, 0, 0, P22, 0, 0, 0, 0, zf / (zn - zf), -1, 0, 0, zn * zf / (zn - zf), 0 };
local function unit(x, y, z) local length = math.sqrt(x * x + y * y + z * z); return x / length, y / length, z / length; end
local eye, at = { 0, -2.5, 6 }, { 0, -1.5, 0 };
local zx, zy, zz = unit(eye[1] - at[1], eye[2] - at[2], eye[3] - at[3]);
-- Right is up (0, -1, 0) crossed with view z, and view y is z crossed with right.
local xx, xy, xz = unit(-zz, 0, zx);
local yx, yy, yz = zy * xz - zz * xy, zz * xx - zx * xz, zx * xy - zy * xx;
W.view_matrix = { xx, yx, zx, 0, xy, yy, zy, 0, xz, yz, zz, 0, -(xx * eye[1] + xy * eye[2] + xz * eye[3]),
    -(yx * eye[1] + yy * eye[2] + yz * eye[3]), -(zx * eye[1] + zy * eye[2] + zz * eye[3]), 1 };

local settings = W.settings();
assert(settings.overhead.layout.placement == 'above_name', 'The default layout puts blocks above the name.');
-- The target, a Goblin 5 yalms ahead and 2 to the side, and a mob your party debuffed 12 yalms behind you.
W.unit(0x100, 0x1000100, 'mob', 2, -5, { name = 'Goblin Mugger', hitbox = 1.2 });
W.unit(0x101, 0x1000101, 'mob', 0, 12, { name = 'Behind', hitbox = 1.2 });
W.target = 0x100;
local snapshot = W.snapshot();
local row = { entity_id = 0x1000100, effect = 134, kind = 'debuff', name = 'Dia', present = true, status = 'server', priority = 0,
    first_seen = 1, first_sequence = 1, key = 'dia', remaining = 50, scope = 'enemy', source = 1001, mine = true };
local behind = { entity_id = 0x1000101, effect = 13, kind = 'debuff', name = 'Slow', present = true, status = 'server', priority = 0,
    first_seen = 2, first_sequence = 2, key = 'slow', remaining = 50, scope = 'enemy', source = 1001, mine = true };
local view = W.view({ row, behind });
local subjects = { [0x1000100] = { effects = { row } }, [0x1000101] = { effects = { behind } } };

W.frame(view, settings, snapshot);
assert(plan.valid and plan.hidden == nil, 'The camera can be used: ' .. tostring(plan.hidden) .. ' ' .. tostring(camera.report().problem));
assert(plan.considered == 2, 'Both mobs are candidates: ' .. plan.considered);
assert(W.ids(plan) == tostring(0x1000100), 'Only the target in front gets a block, not the mob behind: ' .. W.ids(plan));
local target = plan.units[1];
-- Its head point is where the camera puts (X, Z - 1.8, Y), and its feet are below it.
local entities = AshitaCore:GetMemoryManager():GetEntity();
local hx, hy, depth = camera.project(overhead.world_point(entities, 0x100, target.head));
local _, fy = camera.project(overhead.world_point(entities, 0x100, 0));
assert(math.abs(target.head - 1.8) < 1e-9 and target.x == math.floor(hx + 0.5) and target.y == math.floor(hy + 0.5),
    ('At its head: %s %d %d %s %s'):format(target.head, target.x, target.y, hx, hy));
assert(target.x == 829 and target.y == 471 and fy > hy + 100, ('Over its head, its feet below: %d %d %s'):format(target.x, target.y, fy));
assert(math.abs(target.depth - 10.965) < 1e-3 and target.depth == depth and target.size == 23, ('Depth %s, %d px'):format(target.depth,
    target.size));
-- Above the name: a mob's name is centered on its head. At this depth the name is 0.33 yalm tall, under its 24 px
-- cap, and the target cursor over it 0.4 yalm, held at its 16 px; the block's bottom edge sits the top half of the
-- name, the cursor and the 3 px gap over the head.
local ui, layout = plan.ui, settings.overhead.layout;
assert(ui == 1, 'At 1080 the interface scale is 1.');
local ppy = camera.pixels_per_yalm(depth);
local name, arrow = math.min(layout.name_cap, layout.name_height * ppy), math.min(layout.target_cap, layout.target_height * ppy);
assert(name < layout.name_cap and arrow == layout.target_cap, ('Fixture: name %s px, cursor %s px'):format(name, arrow));
local bottom = math.floor(hy - name / 2 - arrow - layout.gap * ui + 0.5);
assert(target.anchor_x == target.x and target.anchor_y == bottom and bottom == 441, ('Its anchor: %d %d'):format(target.anchor_x,
    target.anchor_y));

-- Drawn: the Dia icon stands on that edge, under the head and over the name, centered on the head.
local drawn = draw.draw(plan, subjects, settings, W.now);
assert(drawn == 1, 'One icon drawn: ' .. drawn);
-- Each AddImage call: the texture, its top left corner and its bottom right one.
local images = {};
for _, call in ipairs(calls) do if call[1] == 'AddImage' then images[#images + 1] = call; end end
assert(#images == 1 and images[1][2] == 5000 + 134, 'The Dia icon.');
local corner, far = images[1][3], images[1][4];
assert(corner[1] == 829 - 11 and far[1] == 829 + 12, ('Centered on the head: %s %s'):format(corner[1], far[1]));
assert(far[2] <= bottom and far[2] < hy - name / 2 - arrow and corner[2] == far[2] - 23,
    ('Above the name: %s to %s'):format(corner[2], far[2]));

-- Calibrate on the target: the camera is in use, and the head sits above the feet.
overhead.calibrate(settings);
local lines = W.frame(view, settings, snapshot);
assert(lines and lines[2]:find('Camera read at present: in use. It sits 6.5 yalms from you as X,Z,Y', 1, true), tostring(lines and lines[2]));
assert(lines[2]:find('The head is 109 px above the feet, icons 23 px at depth 11.0.', 1, true), lines[2]);
