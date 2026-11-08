-- Above the name, through the game's right-handed camera (the P11 and P22 of a Phoenix /vg report) on a level view 2
-- yalms up: a block's bottom edge sits the gap over the game's name, and over the target cursor on the target. The
-- name is 0.33 yalm tall in the world and at most 24 px, the cursor 0.4 yalm and at most 16 px. Up close (depth
-- 6.71, 101.4 px a yalm) both are at their largest; far off (depth 23, 29.6 px a yalm) both shrink with the
-- distance, and the room over the name shrinks with them. A mob's name is centered on its head, a player's half a
-- yalm over it. Its icons stand on that edge, and /vg report says where it went.
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

-- The camera: right-handed, as the game's is, 2 yalms up at your feet and looking level along -Y. Render space is
-- (X, Z, Y) with up negative, so a unit at Y = -d is d deep.
local P11, P22, zn, zf = 0.74774223566055, 1.2604166269302, 0.5, 500;
W.projection_matrix = { P11, 0, 0, 0, 0, P22, 0, 0, 0, 0, zf / (zn - zf), -1, 0, 0, zn * zf / (zn - zf), 0 };
-- View x is right, (-1, 0, 0) in render space, view y up, (0, -1, 0), and view z back along +Y.
local eye = 2;
W.view_matrix = { -1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, -eye, 0, 1 };

local settings = W.settings();
local config, layout = settings.overhead, settings.overhead.layout;
assert(layout.placement == 'above_name' and layout.name_height == 0.33 and layout.name_cap == 24 and layout.target_height == 0.4
    and layout.target_cap == 16 and layout.gap == 3, 'The default layout.');
assert(config.types.mob.name_lift == 0 and config.types.party.name_lift == 0.5, 'A mob\'s name on its head, a player\'s half a yalm over.');
-- The target, a Goblin (head 1.8 yalms from its hitbox), and Bob, an Elvaan F (1.95), side by side.
W.unit(0x100, 0x1000100, 'mob', 0, -6.71, { name = 'Goblin Mugger', hitbox = 1.2 });
W.unit(0x401, 1002, 'player', 1.5, -6.71, { name = 'Bob', race = 4 });
W.target = 0x100;
local snapshot = W.snapshot({ { id = 1002, index = 0x401, name = 'Bob', scope = 'party' } });
local dia = { entity_id = 0x1000100, effect = 134, kind = 'debuff', name = 'Dia', present = true, status = 'server', priority = 0,
    first_seen = 1, first_sequence = 1, key = 'dia', remaining = 50, scope = 'enemy', source = 1001, mine = true };
local poison = { entity_id = 1002, effect = 3, kind = 'debuff', name = 'Poison', present = true, status = 'server', priority = 0,
    first_seen = 2, first_sequence = 2, key = 'poison', remaining = 50, scope = 'party' };
local view = W.view({ dia, poison });
local subjects = { [0x1000100] = { effects = { dia } }, [1002] = { effects = { poison } } };
local entities = AshitaCore:GetMemoryManager():GetEntity();

local function unit_of(id) for i = 1, plan.count do if plan.units[i].id == id then return plan.units[i]; end end end
-- Places both at a depth and checks each block against the name the model predicts: its middle where the camera puts
-- the name point, its height and the cursor's from the px per yalm there. Returns each one's room over the name.
local function at(depth, label)
    W.entities[0x100].y, W.entities[0x401].y = -depth, -depth;
    W.frame(view, settings, snapshot, false, 0.2);
    assert(plan.valid and plan.ui == 1 and plan.k == 1, label .. ': the camera is used, at 1080: ' .. tostring(plan.hidden));
    local out = {};
    for _, case in ipairs({ { 0x1000100, 1.8, true, 'the target' }, { 1002, 1.95 + 0.5, false, 'Bob' } }) do
        local id, height, target, name = case[1], case[2], case[3], case[4];
        local unit = assert(unit_of(id), label .. ': ' .. name .. ' has a block.');
        local index = id == 1002 and 0x401 or 0x100;
        local sx, sy, w = camera.project(overhead.world_point(entities, index, height));
        local ppy = camera.pixels_per_yalm(w);
        assert(math.abs(w - depth) < 1e-6 and math.abs(unit.ppy - ppy) < 1e-9 and unit.target == target and unit.y == math.floor(sy + 0.5),
            ('%s: %s placed from the middle of its name, %s deep: %s %s'):format(label, name, depth, unit.y, sy));
        local name_px = math.min(24, 0.33 * ppy);
        local arrow_px = target and math.min(16, 0.4 * ppy) or 0;
        assert(math.abs(unit.name_px - name_px) < 1e-9 and math.abs(unit.arrow_px - arrow_px) < 1e-9,
            ('%s: %s leaves %.2f px for the name and %.2f for the cursor'):format(label, name, unit.name_px, unit.arrow_px));
        local name_top, arrow_top = sy - name_px / 2, sy - name_px / 2 - arrow_px;
        assert(unit.anchor_y == math.floor(arrow_top - 3 + 0.5), ('%s: %s anchor %d'):format(label, name, unit.anchor_y));
        -- The block's bottom is over the name's top, and over the cursor's on the target, by the gap.
        assert(unit.anchor_y < name_top and unit.anchor_y < arrow_top and arrow_top - unit.anchor_y >= 2.5 and arrow_top - unit.anchor_y <= 3.5,
            ('%s: %s block bottom %d, cursor top %.2f, name top %.2f'):format(label, name, unit.anchor_y, arrow_top, name_top));
        out[id] = { ppy = ppy, name_y = unit.y, name_px = unit.name_px, arrow_px = unit.arrow_px, anchor_y = unit.anchor_y,
            room = name_top - unit.anchor_y, unit = unit };
    end
    return out;
end

local near = at(6.71, 'Up close');
local mob, bob = near[0x1000100], near[1002];
assert(math.abs(mob.ppy - 101.4) < 0.05, ('Fixture: %.2f px a yalm up close'):format(mob.ppy));
assert(mob.name_px == 24 and mob.arrow_px == 16 and mob.name_y == 560 and mob.anchor_y == 529,
    ('Up close the name and cursor are at their largest: %s %s %s %s'):format(mob.name_y, mob.name_px, mob.arrow_px, mob.anchor_y));
assert(bob.name_px == 24 and bob.arrow_px == 0 and bob.name_y == 494 and bob.anchor_y == 479,
    ('Bob, not the target, leaves room for his name only: %s %s %s'):format(bob.name_y, bob.name_px, bob.anchor_y));
-- Drawn: the Dia icon stands on the target's edge, over its cursor and name.
calls = {};
assert(draw.draw(plan, subjects, settings, W.now) == 2, 'Both blocks draw their icon.');
local image;
for _, call in ipairs(calls) do if call[1] == 'AddImage' and call[2] == 5000 + 134 then image = call; end end
assert(image and image[4][2] <= mob.anchor_y and image[3][2] < image[4][2], ('The Dia icon ends at %s, on the edge'):format(image and image[4][2]));
-- /vg report gives the target's feet, the name's middle and the room left, rounded.
local row = overhead.report(settings, snapshot).target;
local _, feet = camera.project(overhead.world_point(entities, 0x100, 0));
assert(row.feet_y == math.floor(feet + 0.5) and row.name_y == 560 and row.name_px == 24 and row.arrow_px == 16 and row.anchor_y == 529,
    ('/vg report: %s %s %s %s %s'):format(row.feet_y, row.name_y, row.name_px, row.arrow_px, row.anchor_y));

local far = at(23, 'Far off');
local far_mob, far_bob = far[0x1000100], far[1002];
assert(math.abs(far_mob.ppy - 29.6) < 0.05, ('Fixture: %.2f px a yalm far off'):format(far_mob.ppy));
assert(far_mob.name_px < 24 and far_mob.arrow_px < 16 and far_mob.name_y == 546 and far_mob.anchor_y == 526,
    ('Far off both shrink: %s %.2f %.2f %s'):format(far_mob.name_y, far_mob.name_px, far_mob.arrow_px, far_mob.anchor_y));
assert(far_bob.name_px < 24 and far_bob.arrow_px == 0 and far_bob.name_y == 527 and far_bob.anchor_y == 519,
    ('Bob far off: %s %.2f %s'):format(far_bob.name_y, far_bob.name_px, far_bob.anchor_y));
row = overhead.report(settings, snapshot).target;
assert(row.name_y == 546 and row.name_px == 9.8 and row.arrow_px == 11.8 and row.anchor_y == 526,
    ('/vg report far off: %s %s %s %s'):format(row.name_y, row.name_px, row.arrow_px, row.anchor_y));

-- The room over the name is the cursor and the gap on the target, the gap alone on Bob; up close it is the caps',
-- far off 0.4 yalm's. It shrinks by the cursor's 16 - 0.4 * 29.6 = 4.2 px, within the rounding of the two edges.
assert(math.abs(mob.room - (16 + 3)) <= 0.5 and math.abs(far_mob.room - (0.4 * far_mob.ppy + 3)) <= 0.5,
    ('The room over the target\'s name: %.2f up close, %.2f far off'):format(mob.room, far_mob.room));
assert(math.abs((mob.room - far_mob.room) - (16 - 0.4 * far_mob.ppy)) <= 1, 'It shrinks as the cursor does.');
assert(math.abs(bob.room - 3) <= 0.5 and math.abs(far_bob.room - 3) <= 0.5, ('Over Bob\'s: %.2f and %.2f'):format(bob.room, far_bob.room));

-- Under the head: the gap under the head point, the name not counted.
layout.placement = 'below_name';
W.frame(view, settings, snapshot, false, 0.2);
local below = unit_of(0x1000100);
local _, head = camera.project(overhead.world_point(entities, 0x100, 1.8));
assert(not plan.above and below.y == math.floor(head + 0.5) and below.anchor_y == math.floor(head + 3 + 0.5) and below.name_px == 0,
    'Under the head: the gap under the head point.');
return true;
