-- Each overhead block stays on its own unit's name. You and five party members walk up a slope, then up stairs, side
-- by side and never quite in step, so their blocks drift in and out of overlapping on screen. Every frame, each
-- block's edge next to the name keeps the same offset from that unit's name point, within the pixel that rounding to
-- whole pixels takes, and where two blocks overlap neither moves and the nearer one is drawn on top. The settings come
-- from a save, then from a profile export of them. Through the real core/overhead.lua update and
-- ui/overhead_icons.lua draw, on the decoded client image and the game's camera (name_anchor_fixture.lua), 64 frames a
-- second.
local N = require('name_anchor_fixture');
local W = N.W;
local overhead = require('core.overhead');
local camera = require('core.camera');
local draw = require('ui.overhead_icons');
local defaults, store, share, json = require('ui.defaults'), require('core.store'), require('core.share'), require('json');
local plan, slots = overhead.plan, draw._slots;
local floor, sin, pi, huge = math.floor, math.sin, math.pi, math.huge;
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);

-- A draw list that keeps the corners of each icon, in the order they are drawn.
local images = {};
local list = setmetatable({}, { __index = function(_, name)
    if name == 'AddImage' then
        return function(_, _, corner, far) images[#images + 1] = { corner[1], corner[2], far[1], far[2] }; end;
    end
    return function() end;
end });
local imgui = require('imgui');
rawset(imgui, 'GetBackgroundDrawList', function() return list; end);
rawset(imgui, 'CalcTextSize', function(text)
    local size = MOCK.font_stack[#MOCK.font_stack] or 18;
    return #tostring(text) * size * 0.5, size;
end);

-- A save as settings.json holds it: overhead icons on, you shown and other players not, 10 units at most. Read as a
-- save is read, then tidied.
local saved = json.decode(store.encode({ overhead = { enabled = true, max_units = 10,
    units = { self = true, other = false, other_pet = false }, camera = { capture = 'present' } } }));
local settings = defaults.tidy(saved);
local config = settings.overhead;
assert(config.enabled and config.units.self, 'The save loads and tidies.');

-- You, a Mithra, and the party, each with point 2 at their race's height, and five or six buffs with countdowns.
local people = {
    { index = W.self, id = 1001, name = 'Tester', race = 7, gen = -2.0 },
    { index = 0x401, id = 1002, name = 'Ayla', race = 1, gen = -2.0 },
    { index = 0x402, id = 1003, name = 'Bran', race = 3, gen = -2.4 },
    { index = 0x403, id = 1004, name = 'Cira', race = 5, gen = -1.3 },
    { index = 0x404, id = 1005, name = 'Dorn', race = 8, gen = -2.6 },
    { index = 0x405, id = 1006, name = 'Esme', race = 2, gen = -2.0 },
};
local BUFFS = { 33, 43, 42, 116, 36, 37 };
local rows, subjects, members, sequence = {}, {}, {}, 0;
for i, p in ipairs(people) do
    N.unit(p.index, p.id, 'player', 0, 0, { 0, p.gen, 0 }, { name = p.name, race = p.race });
    local effects = {};
    for k = 1, i == 1 and 6 or 5 do
        sequence = sequence + 1;
        local row = { entity_id = p.id, effect = BUFFS[k], kind = 'buff', name = 'Effect ' .. BUFFS[k], present = true,
            status = 'server', priority = 0, first_seen = sequence, first_sequence = sequence, key = p.id .. ':' .. k,
            remaining = 100 + sequence * 7, scope = i == 1 and 'self' or 'party', source = 1001, mine = true };
        effects[k], rows[#rows + 1] = row, row;
    end
    subjects[p.id] = { effects = effects };
    if i > 1 then members[#members + 1] = { id = p.id, index = p.index, scope = 'party' }; end
end
local snapshot, view = W.snapshot(members), W.view(rows);

-- The ground's height a distance ahead (render space, up is negative): a slope rising half a yalm each yalm, or
-- stairs a quarter yalm high every half yalm.
local grounds = {
    slope = function(ahead) return -0.5 * ahead; end,
    stairs = function(ahead) return -0.25 * floor(ahead / 0.5); end,
};
-- Where each one walks beside you, and how far ahead and to the side they drift and how fast: no one keeps in step.
local SIDE = { 0, -1.2, 1.2, -2.4, 2.4, -3.6 };
local DRIFT = { { 1, 0 }, { 3.1, 0.3 }, { 4.3, 1.9 }, { 5.7, 4.2 }, { 2.9, 2.6 }, { 3.7, 5.1 } };

-- The camera 8 yalms behind you and 4 up, looking at a point 1.2 over you, as it follows you.
local function unit_vector(x, y, z) local length = math.sqrt(x * x + y * y + z * z); return x / length, y / length, z / length; end
local function look(ex, ey, ez, tx, ty, tz)
    local zx, zy, zz = unit_vector(ex - tx, ey - ty, ez - tz);
    local xx, xy, xz = unit_vector(-zz, 0, zx);
    local yx, yy, yz = zy * xz - zz * xy, zz * xx - zx * xz, zx * xy - zy * xx;
    W.view_matrix = { xx, yx, zx, 0, xy, yy, zy, 0, xz, yz, zz, 0, -(xx * ex + xy * ey + xz * ez),
        -(yx * ex + yy * ey + yz * ez), -(zx * ex + zy * ey + zz * ez), 1 };
end
-- Where the camera puts a render-space point on the 1920x1080 display.
local function project(x, y, z)
    local m = camera._matrix;
    local w = x * m[4] + y * m[8] + z * m[12] + m[16];
    return ((x * m[1] + y * m[5] + z * m[9] + m[13]) / w + 1) * 960, (1 - (x * m[2] + y * m[6] + z * m[10] + m[14]) / w) * 540;
end

local function overlap(a, b) return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]; end

-- Walks everyone seconds long at 5 yalms a second on the ground named, from where the last walk stopped. Checks each
-- frame and returns how far each block's edge strayed from its name, across and up, and how many frames had blocks
-- overlapping.
local walked = 0;
local function walk(ground, seconds)
    local height = grounds[ground];
    local offsets, overlapping = {}, 0;
    for f = 1, seconds * 64 do
        walked = walked + 5 / 64;
        local t = walked / 5;
        for i, p in ipairs(people) do
            local drift = DRIFT[i];
            local side, ahead = SIDE[i], walked;
            if i > 1 then
                side = side + 0.15 * sin(2 * pi * t / (drift[1] * 1.3) + drift[2]);
                ahead = ahead + 0.5 * sin(2 * pi * t / drift[1] + drift[2]);
            end
            W.entities[p.index].z = height(ahead);
            N.move(p.index, side, -ahead);
        end
        local me = W.entities[W.self];
        look(me.x, me.z - 4, me.y + 8, me.x, me.z - 1.2, me.y);
        images = {};
        W.frame(view, settings, snapshot, nil, 1 / 64);
        draw.draw(plan, subjects, settings, W.now);
        assert(plan.valid and plan.count == #people, ('%s frame %d: a block for each of the six: %d %s'):format(ground, f, plan.count,
            tostring(plan.hidden)));
        -- The icons are drawn block by block in plan.order, far to near.
        local at, blocks = 0, {};
        for k = 1, plan.count do
            local index = plan.order[k];
            local unit, slot = plan.units[index], slots[index];
            assert(unit.path == 'name point' and slot.count > 0, ('%s frame %d: %s is placed from its name point (%s %s)'):format(ground, f,
                unit.name, tostring(unit.path), tostring(unit.why)));
            local px, py, pz = N.point(unit.index);
            local nx, ny = project(px, py, pz);
            local box = { huge, huge, -huge, -huge, depth = unit.depth, name = unit.name };
            for n = 1, slot.count do
                at = at + 1;
                local r = images[at];
                -- The block's anchor as drawn, from where this icon is and its place in the block; its edge next to the
                -- name against the name's top, half a pixel over the name point.
                local dx, dy = r[1] - slot.x[n] - nx, r[2] - slot.y[n] + slot.bottom - (ny - 0.5);
                local seen = offsets[unit.name];
                if not seen then seen = { huge, -huge, huge, -huge }; offsets[unit.name] = seen; end
                seen[1], seen[2] = math.min(seen[1], dx), math.max(seen[2], dx);
                seen[3], seen[4] = math.min(seen[3], dy), math.max(seen[4], dy);
                box[1], box[2], box[3], box[4] = math.min(box[1], r[1]), math.min(box[2], r[2]), math.max(box[3], r[3]),
                    math.max(box[4], r[4]);
            end
            blocks[k] = box;
        end
        assert(at == #images, 'Every icon drawn belongs to a block.');
        -- Where two overlap, the one drawn later, on top, is the nearer.
        local any = false;
        for a = 1, #blocks do
            for b = a + 1, #blocks do
                if overlap(blocks[a], blocks[b]) then
                    any = true;
                    assert(blocks[b].depth <= blocks[a].depth, ('%s frame %d: %s is nearer than %s and drawn on top'):format(ground, f,
                        blocks[b].name, blocks[a].name));
                end
            end
        end
        if any then overlapping = overlapping + 1; end
    end
    return offsets, overlapping;
end

-- Each block keeps one offset from its name, but for the pixel rounding takes, across and up.
local function steady(ground, offsets, overlapping, seconds)
    assert(overlapping > 0, ground .. ': blocks overlap on some frames, so the walk tests them.');
    for _, p in ipairs(people) do
        local seen = offsets[p.name];
        assert(seen and seen[2] - seen[1] < 1 and seen[4] - seen[3] < 1,
            ('%s: %s\'s block stays on its name, across %.2f to %.2f and up %.2f to %.2f px from it over %d frames, %d with blocks overlapping')
                :format(ground, p.name, seen and seen[1] or 0, seen and seen[2] or 0, seen and seen[3] or 0, seen and seen[4] or 0,
                    seconds * 64, overlapping));
    end
end

local offsets, overlapping = walk('slope', 4);
steady('Up a slope', offsets, overlapping, 4);
offsets, overlapping = walk('stairs', 4);
steady('Up stairs', offsets, overlapping, 4);

-- A profile export of these settings reads, and after the import the blocks still stay on their names.
settings = assert(share.candidate(settings, assert(share.read(assert(share.export(settings, 'profile', nil, 'Tester')))), 'replace'));
offsets, overlapping = walk('stairs', 2);
steady('Up stairs after the import', offsets, overlapping, 2);
return 'Overhead blocks stay on their names up slopes and stairs, overlapping or not, the nearer on top';
