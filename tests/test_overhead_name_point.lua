-- Above the name, each block sits on the game's own name point: the first frame with overhead icons on finds the
-- client patterns, and each unit's point is its actor's root plus point 2 of its skeleton times the actor's scale,
-- with the client's own lifts. The name hangs down from that point, so a block's bottom edge goes the gap (3 px at
-- 1080) over the name's top, over an icon in front of the name and, on the unit carrying it, over the target
-- cursor's box. Near and far, through the game's right-handed camera: a Mithra (point 2 at -2.0) and a Crawler
-- (-2.5). A unit whose point can't be read safely keeps the guessed placement, and says why.
local N = require('name_anchor_fixture');
local W = N.W;
local overhead = require('core.overhead');
local camera = require('core.camera');
local plan = overhead.plan;
local floor, ceil, huge = math.floor, math.ceil, math.huge;
local settings = W.settings();
local config = settings.overhead;
config.units.self = true;
local entities = AshitaCore:GetMemoryManager():GetEntity();

-- You, a Mithra, at the origin; a Crawler 3 yalms ahead and one 25 ahead; a Hume in the party between you and the
-- camera.
local NEAR, FAR, MEMBER = 0x100, 0x101, 0x401;
N.unit(W.self, 1001, 'player', 0, 0, { 0, -2.0, 0 }, { name = 'Tester', race = 7 });
N.unit(NEAR, 0x1000100, 'mob', 1.5, -3, { 0, -2.5, 0 }, { name = 'Crawler', hitbox = 0.5 });
N.unit(FAR, 0x1000101, 'mob', -3, -25, { 0, -2.5, 0 }, { name = 'Crawler', hitbox = 0.5 });
N.unit(MEMBER, 1002, 'player', -1.5, 4, { 0, -2.0, 0 }, { name = 'Member', race = 1 });
local members = { { id = 1002, index = MEMBER, scope = 'party' } };
local rows = { { entity_id = 0x1000100, kind = 'debuff', scope = 'enemy', source = 1001 },
    { entity_id = 0x1000101, kind = 'debuff', scope = 'enemy', source = 1001 },
    { entity_id = 1001, kind = 'buff', scope = 'self', source = 1001, mine = true },
    { entity_id = 1002, kind = 'buff', scope = 'party', source = 1001, mine = true } };
local snapshot, view = W.snapshot(members), W.view(rows);
local function frame() W.frame(view, settings, snapshot); end
local function placed(index)
    for i = 1, plan.count do if plan.units[i].index == index then return plan.units[i]; end end
    error('No block on ' .. index .. ': ' .. W.ids(plan) .. ' ' .. tostring(plan.hidden));
end

-- Where the camera puts a render-space point: display x and y, w and the NDC depth.
local function project(x, y, z)
    local m = camera._matrix;
    local w = x * m[4] + y * m[8] + z * m[12] + m[16];
    return ((x * m[1] + y * m[5] + z * m[9] + m[13]) / w + 1) * 960, (1 - (x * m[2] + y * m[6] + z * m[10] + m[14]) / w) * 540, w,
        (x * m[3] + y * m[7] + z * m[11] + m[15]) / w;
end
-- The block a unit's name point gives: the name's top half a pixel over the point, an icon rise font texels over
-- that, the cursor's box (32 menu px, 1 display px each here) over the cursor's whole-pixel point, or 10 px higher
-- for the subtarget's. lift raises the point (yalms, negative is up). Returns anchor x and y, and ay.
local function expected(index, rise, arrow, lift)
    local x, y, z = N.point(index);
    local ax, ay, _, depth = project(x, y + (lift or 0), z);
    local t = N.texel(depth);
    local top = ay - 0.5 - ceil((rise or 0) * t);
    if arrow == 'A' then top = math.min(top, N.trunc(ay) - 32 - 0.5); end
    if arrow == 'B' then top = math.min(top, N.trunc(ay) - 10 - 32 - 0.5); end
    return floor(ax + 0.5), floor(top - 3 + 0.5), ay, t;
end
local function check(index, rise, arrow, lift, why)
    local unit = placed(index);
    local x, y, ay = expected(index, rise, arrow, lift);
    assert(unit.path == 'name point' and unit.anchor_x == x and unit.anchor_y == y,
        ('%s: the block at %s %s on %s (ay %.3f), %s expected'):format(why, tostring(unit.anchor_x), tostring(unit.anchor_y),
            tostring(unit.path), ay, y));
    return unit, ay;
end

-- The first frame finds the patterns, and every unit is placed from its name point.
frame();
assert(plan.valid and plan.count == 4, 'Four blocks: ' .. W.ids(plan) .. ' ' .. tostring(plan.hidden));
for i = 1, plan.count do
    assert(plan.units[i].path == 'name point', ('%s takes the name point, not %s (%s)'):format(plan.units[i].name,
        tostring(plan.units[i].path), tostring(plan.units[i].why)));
end
-- Untargeted, each block's bottom edge is exactly the gap over the name's top.
local _, mithra_y = check(W.self, 0, nil, nil, 'You, a Mithra');
local _, near_y = check(NEAR, 0, nil, nil, 'The near Crawler');
local _, far_y = check(FAR, 0, nil, nil, 'The far Crawler');
check(MEMBER, 0, nil, nil, 'The Hume');
-- Worked numbers, by hand from the camera: your name point (0, -2, 0) sits at y 477.414, 8.2 yalms deep; the near
-- Crawler's (1.5, -2.5, -3) at 401.217, 10.9 deep, and the far one's (-3, -2.5, -25) at 335.965, 31.6 deep. Each
-- name's top is half a pixel up and the block's edge 3 px over that, rounded.
assert(floor(mithra_y * 1000 + 0.5) == 477414 and floor(near_y * 1000 + 0.5) == 401217 and floor(far_y * 1000 + 0.5) == 335965,
    ('The name points on screen: %.3f %.3f %.3f'):format(mithra_y, near_y, far_y));
assert(placed(W.self).anchor_y == 474 and placed(NEAR).anchor_y == 398 and placed(FAR).anchor_y == 332,
    ('Their blocks: %d %d %d'):format(placed(W.self).anchor_y, placed(NEAR).anchor_y, placed(FAR).anchor_y));

-- The target carries the main cursor: its block goes the gap over the cursor's box, the far one's stays on its name.
W.target, N.window.ank_y = NEAR, N.trunc(near_y);
frame();
check(NEAR, 0, 'A', nil, 'The targeted Crawler');
check(FAR, 0, nil, nil, 'The far Crawler, untargeted');
assert(placed(NEAR).anchor_y == 366, 'The cursor box is 32 px over its whole-pixel point, 401: ' .. placed(NEAR).anchor_y);
-- The union of the cursor's frames: one frame taller by 4 moves it up 4, and it stays put while the cursor animates.
N.frames({ { -10, 10, -32, 0 }, { -10, 10, -36, 0 }, { -10, 10, -32, 0 } });
frame();
assert(placed(NEAR).anchor_y == 362, 'The tallest frame sets the room: ' .. placed(NEAR).anchor_y);
-- Frames that can't be read, or look wrong, leave the game's own box.
N.closed[0x7000200] = true;
frame();
assert(placed(NEAR).anchor_y == 366, 'An unreadable frame leaves the game box: ' .. placed(NEAR).anchor_y);
N.closed[0x7000200] = nil;
N.frames({ { -10, 10, 5, 9 } });
frame();
assert(placed(NEAR).anchor_y == 366, 'A box under the point leaves the game box: ' .. placed(NEAR).anchor_y);
N.frames();
-- The menu scale: a 1280x720 menu on the 1080 display makes each menu px 1.5 display px.
package.loaded['core.chat'] = { menu_size = function() return 1280, 720; end };
frame();
local window = require('core.name_anchor').status(N.targets).window;
assert(window.menu_width == 1280 and window.menu_height == 720 and window.ky == 1.5, 'The report has the menu size and its scale');
local top = (N.trunc(near_y / 1.5) - 32 - 0.5) * 1.5;
assert(placed(NEAR).anchor_y == floor(top - 3 + 0.5), ('Menu scale 1.5: %d, %s expected'):format(placed(NEAR).anchor_y, floor(top - 2.5)));
package.loaded['core.chat'] = nil;
-- A cursor that hangs from another point than the name's, or floats, is where the window keeps it.
N.memory[N.layouts[NEAR].actor + 0x8A6] = 3;
N.window.ank_y = 400;
frame();
assert(placed(NEAR).anchor_y == floor(400 - 32 - 0.5 - 3 + 0.5), 'The cursor on its own point: ' .. placed(NEAR).anchor_y);
N.memory[N.layouts[NEAR].actor + 0x8A6] = 2;
N.window.floating[0] = 1;
frame();
assert(placed(NEAR).anchor_y == 365, 'A floating cursor where the window keeps it: ' .. placed(NEAR).anchor_y);
N.window.floating[0], N.window.ank_y = 0, N.trunc(near_y);
-- A cursor that sits lower than the name leaves the name's room.
N.window.floating[0], N.window.ank_y = 1, 700;
frame();
check(NEAR, 0, nil, nil, 'A cursor below the name');
N.window.floating[0], N.window.ank_y = 0, N.trunc(near_y);
-- No cursor while the target is dead, or with no main cursor drawn.
N.window.dead = 1;
frame();
check(NEAR, 0, nil, nil, 'A dead target has no cursor');
N.window.dead, N.window.ank_x = 0, 0;
frame();
check(NEAR, 0, nil, nil, 'No main cursor drawn');
N.window.ank_x = 960;
-- Without the window getters, the cursor is on the target, at its name point, with the game's box.
N.window_getters(false);
frame();
check(NEAR, 0, 'A', nil, 'The target without the window getters');
N.window_getters(true);

-- Picking a subtarget: the main cursor stays on the target and the subtarget's, 10 px higher, goes on the other.
W.sub, W.sub_active = FAR, 1;
N.window.callback, N.window.sub, N.window.sub_x, N.window.sub_y = 1, 1, 900, N.trunc(far_y) - 10;
frame();
check(NEAR, 0, 'A', nil, 'The target while a subtarget is picked');
check(FAR, 0, 'B', nil, 'The subtarget');
-- The subtarget cursor isn't drawn when its point failed (0, -10), when no subtarget is shown, or with no command.
N.window.sub_x, N.window.sub_y = 0, -10;
frame();
check(FAR, 0, nil, nil, 'A subtarget cursor whose point failed');
N.window.sub_x, N.window.sub_y, N.window.sub = 900, N.trunc(far_y) - 10, 0;
frame();
check(FAR, 0, nil, nil, 'No subtarget cursor shown');
N.window.sub = 1;
N.window_getters(false);
frame();
check(FAR, 0, 'B', nil, 'The subtarget without the window getters');
N.window_getters(true);
N.window.callback, N.window.sub, W.sub, W.sub_active, W.target = 0, 0, 0, 0, 0;

-- An icon in front of a player's name: a linkshell's reaches 1.0625 font texels over it, 3 px at full size; far
-- away the name shrinks with depth and so does the room.
W.entities[MEMBER].flags1 = 0x08000000;
frame();
check(MEMBER, 1.0625, nil, nil, 'A linkshell member');
local _, _, _, t = expected(MEMBER, 1.0625);
assert(t == 2.53125 and ceil(1.0625 * t) == 3, 'Near, a texel is 2.53125 px: ' .. t);
N.move(MEMBER, -3, -24);
frame();
local _, _, _, far_t = expected(MEMBER, 1.0625);
check(MEMBER, 1.0625, nil, nil, 'A linkshell member far away');
assert(far_t < 1 and ceil(1.0625 * far_t) == 1, 'Far, the name and its room shrink: ' .. far_t);
N.move(MEMBER, -1.5, 4);
-- The second line of stars over a player's name reaches 18 texels, but only while the name is drawn.
W.entities[MEMBER].flags7 = 0x80;
frame();
check(MEMBER, 18, nil, nil, 'Stars over the name');
W.entities[MEMBER].flags4 = 0x80;
frame();
check(MEMBER, 1.0625, nil, nil, 'Stars over a hidden name');
W.entities[MEMBER].flags1, W.entities[MEMBER].flags4, W.entities[MEMBER].flags7 = 0, 0, 0;
-- A mob's own icon (the party request star on a monster's flags) is picked by the same rule.
W.entities[NEAR].flags8 = 0x8;
frame();
check(NEAR, 4, nil, nil, 'A mob with a party request star');
W.entities[NEAR].flags8 = 0;

-- Point 2 of the skeleton at 0, 0, 0, or a skeleton not loaded yet: the client puts the name at the root, and so
-- does the block.
local far_layout = N.layouts[FAR];
N.memory[far_layout.node + 0x0C] = 0;
frame();
local fx, fy, fz = N.memory[far_layout.actor + 0x678], N.memory[far_layout.actor + 0x67C], N.memory[far_layout.actor + 0x680];
local ax, ay = project(fx, fy, fz);
assert(placed(FAR).path == 'name point' and placed(FAR).anchor_y == floor(ay - 0.5 - 3 + 0.5) and placed(FAR).anchor_x == floor(ax + 0.5),
    'Without a skeleton the block sits on the root: ' .. placed(FAR).anchor_y);
N.memory[far_layout.node + 0x0C] = far_layout.handle;
N.memory[far_layout.entry + 0x12] = 0;
frame();
assert(placed(FAR).anchor_y == floor(ay - 0.5 - 3 + 0.5), 'Point 2 at 0 is the root too: ' .. placed(FAR).anchor_y);
N.memory[far_layout.entry + 0x12] = -2.5;

-- The actor's scale: a Crawler 1.25 times as tall has its point 1.25 times as high.
local near_layout = N.layouts[NEAR];
N.memory[near_layout.actor + 0x6A0] = 1.25;
frame();
check(NEAR, 0, nil, nil, 'A Crawler scaled 1.25');
assert(placed(NEAR).anchor_y < 398 - 10, 'Scaled up, its point is higher: ' .. placed(NEAR).anchor_y);
N.memory[near_layout.actor + 0x6A0] = 1;

-- Lifts: on a chocobo (5) and mounted (85) 1.3 times the model size, in a chair (63 to 83) 0.5 times, the size the
-- entity's own when set, else the actor's two. The actor of the chocobo, mount or chair itself (kind 1 to 4, 0x54,
-- 0x3D to 0x51) gets none, nor does a point that hangs from a bone.
local member_layout, member = N.layouts[MEMBER], W.entities[MEMBER];
N.memory[member_layout.actor + 0x754] = 1.1;
for _, case in ipairs({ { 5, 0, -1.3 * 1.1, 'On a chocobo' }, { 5, 2, 0, 'The chocobo itself' }, { 85, 0, -1.3 * 1.1, 'Mounted' },
    { 85, 0x54, 0, 'The mount itself' }, { 70, 0, -0.5 * 1.1, 'In a chair' }, { 63, 0, -0.55, 'In the first chair' },
    { 83, 0, -0.55, 'In the last chair' }, { 84, 0, 0, 'Past the chairs' }, { 70, 0x45, 0, 'The chair itself' }, { 33, 0, 0, 'Resting' } }) do
    member.status = case[1];
    N.memory[member_layout.actor + 0xA4] = case[2];
    frame();
    check(MEMBER, 0, nil, case[3], case[4]);
end
member.status = 5;
N.memory[member_layout.actor + 0xA4] = 0;
N.memory[member_layout.actor + 0x75C] = 0.95;
frame();
check(MEMBER, 0, nil, -1.3 * 0.95, 'On a chocobo, the actor\'s first size');
N.memory[member_layout.entity + 0x204] = 0.8;
frame();
check(MEMBER, 0, nil, -1.3 * 0.8, 'On a chocobo, the entity\'s model size');
N.memory[member_layout.entry] = 7;
frame();
check(MEMBER, 0, nil, 0, 'A point on a bone');
N.memory[member_layout.entry], N.memory[member_layout.entity + 0x204], N.memory[member_layout.actor + 0x75C] = 0, -1, -1;
member.status = 0;
-- The height the client adds last, actor+0x8C0.
N.memory[member_layout.actor + 0x8C0] = -0.4;
frame();
check(MEMBER, 0, nil, nil, 'The client\'s last height');
N.memory[member_layout.actor + 0x8C0] = 0;

-- The type's world_offset raises the point in yalms, and screen_x and screen_y move the block.
config.types.mob.world_offset, config.types.mob.screen_x, config.types.mob.screen_y = 0.5, 4, -2;
frame();
local x, y, z = N.point(NEAR);
local nx, ny = project(x, y, z);
local rx, ry = project(x, y - 0.5, z);
assert(placed(NEAR).anchor_x == floor(rx + 4 + 0.5) and placed(NEAR).anchor_y == floor(ny - 0.5 + (ry - ny) - 3 - 2 + 0.5),
    ('The nudges: %d %d'):format(placed(NEAR).anchor_x, placed(NEAR).anchor_y));
config.types.mob.world_offset, config.types.mob.screen_x, config.types.mob.screen_y = 0, 0, 0;

-- Anything that can't be read safely keeps the guess: the head height and name lift, unchanged.
local function guessed(index, target)
    local e = W.entities[index];
    local kind = e.spawn == 0x10 and 'mob' or index == W.self and 'self' or 'party';
    local types = config.types[kind];
    local head = overhead.head_height(e.id < 0x1000000, e.race, e.status, e.hitbox, e.name, config.head, types.world_offset)
        + types.name_lift;
    local _, hy, depth = camera.project(overhead.world_point(entities, index, head));
    return (overhead.above_name(hy, camera.pixels_per_yalm(depth), target, config.layout, 1, 1, types.screen_y));
end
local cases = {
    { 'The actor is not this unit\'s.', function() N.memory[near_layout.entity + 0x78] = 0x1000999; end,
        function() N.memory[near_layout.entity + 0x78] = 0x1000100; end },
    { 'The actor is not this unit\'s.', function() N.memory[near_layout.entity + 0xA0] = 0x3999000; end,
        function() N.memory[near_layout.entity + 0xA0] = near_layout.actor; end },
    { 'The actor can\'t be read.', function() N.closed[near_layout.actor] = true; end, function() N.closed[near_layout.actor] = nil; end },
    { 'The unit has no actor.', function() W.entities[NEAR].actor = 0x100; end, function() W.entities[NEAR].actor = near_layout.actor; end },
    { 'The name uses another point.', function() N.memory[near_layout.actor + 0x8A7] = 3; end,
        function() N.memory[near_layout.actor + 0x8A7] = 2; end },
    { 'Its values are out of range.', function() N.memory[near_layout.actor + 0x8C0] = 12; end,
        function() N.memory[near_layout.actor + 0x8C0] = 0; end },
    { 'Its values are out of range.', function() N.memory[near_layout.actor + 0x67C] = 0 / 0; end, function() N.move(NEAR, 1.5, -3); end },
    { 'Its scale is out of range.', function() N.memory[near_layout.actor + 0x698] = 0; end,
        function() N.memory[near_layout.actor + 0x698] = 1; end },
    { 'The root is far from the unit.', function() N.memory[near_layout.actor + 0x678] = 15; end, function() N.move(NEAR, 1.5, -3); end },
    { 'The skeleton can\'t be read.', function() N.closed[near_layout.node] = true; end, function() N.closed[near_layout.node] = nil; end },
    { 'The skeleton can\'t be read.', function() N.closed[near_layout.handle] = true; end,
        function() N.closed[near_layout.handle] = nil; end },
    { 'The skeleton can\'t be read.', function() N.closed[near_layout.data] = true; end, function() N.closed[near_layout.data] = nil; end },
    { 'The skeleton can\'t be read.', function() N.closed[near_layout.table_at] = true; end,
        function() N.closed[near_layout.table_at] = nil; end },
    -- On a chocobo with no model size that is a number anywhere.
    { 'Its values are out of range.', function()
        W.entities[NEAR].status = 5;
        N.memory[near_layout.entity + 0x204], N.memory[near_layout.actor + 0x75C] = 0 / 0, 0 / 0;
        N.memory[near_layout.actor + 0x754] = 0 / 0;
    end, function()
        W.entities[NEAR].status = 0;
        N.memory[near_layout.entity + 0x204], N.memory[near_layout.actor + 0x75C], N.memory[near_layout.actor + 0x754] = -1, -1, 1;
    end },
    { 'The skeleton is out of range.', function() N.memory[near_layout.data + 0x32] = 600; end,
        function() N.memory[near_layout.data + 0x32] = 20; end },
    { 'The skeleton is out of range.', function() N.memory[near_layout.table_at] = 2; end, function() N.memory[near_layout.table_at] = 6; end },
    { 'Point 2 of the skeleton is out of range.', function() N.memory[near_layout.entry + 0x12] = 3; end,
        function() N.memory[near_layout.entry + 0x12] = -2.5; end },
};
W.target = NEAR;
for _, case in ipairs(cases) do
    case[2]();
    frame();
    local unit = placed(NEAR);
    assert(unit.path == 'guess' and unit.why == case[1] and unit.anchor_y == guessed(NEAR, true),
        ('%s: %s %s at %s, the guess at %s'):format(case[1], tostring(unit.path), tostring(unit.why), unit.anchor_y, guessed(NEAR, true)));
    assert(placed(FAR).path == 'name point', 'Only that unit takes the guess: ' .. case[1]);
    case[3]();
    frame();
    check(NEAR, 0, 'A', nil, 'Back on its name point after ' .. case[1]);
end
-- A despawned unit's actor reused by another: the back-link no longer names it.
N.memory[near_layout.entity + 0x78] = 0x1000777;
frame();
assert(placed(NEAR).path == 'guess', 'A reused actor isn\'t read as this unit\'s.');
N.memory[near_layout.entity + 0x78] = 0x1000100;

-- Below the head, blocks keep the head point: their top edge the gap under it.
config.layout.placement = 'below_name';
frame();
local _, hy = camera.project(overhead.world_point(entities, NEAR, placed(NEAR).head));
assert(placed(NEAR).path == 'guess' and placed(NEAR).anchor_y == floor(hy + 3 + 0.5), 'Below the head: ' .. placed(NEAR).anchor_y);
config.layout.placement = 'above_name';

-- A read that raises turns the name points off for every unit, and every block keeps the guess. The unit whose read
-- raised (placed first here) says so, and each unit placed after it gives why name points are off.
local anchor = require('core.name_anchor');
N.memory[near_layout.actor + 0x6A0] = nil;
frame();
local problem = anchor.problem();
assert(type(problem) == 'string' and problem:find('Reading a name point failed. ', 1, true) == 1, 'Why they are off: ' .. tostring(problem));
for i = 1, plan.count do
    local unit = plan.units[i];
    assert(unit.path == 'guess', unit.name .. ' keeps the guess once reading failed');
    local why = unit.index == NEAR and 'Reading the name point failed.' or problem;
    assert(unit.why == why, ('%s says %s, %s expected'):format(unit.name, tostring(unit.why), why));
end
assert(placed(NEAR).anchor_y == guessed(NEAR, true) and placed(MEMBER).anchor_y == guessed(MEMBER, false), 'The guesses are today\'s.');
N.memory[near_layout.actor + 0x6A0] = 1;
frame();
assert(placed(NEAR).path == 'guess', 'Name points stay off until the addon loads again.');
for i = 1, plan.count do assert(plan.units[i].why == problem, plan.units[i].name .. ' says why name points are off'); end

-- Loaded again, a read that raises on the far Crawler: a unit placed before it that frame keeps its name point, the
-- Crawler and each unit after it take the guess, and from the next frame every unit does.
anchor._reset();
frame();
check(NEAR, 0, 'A', nil, 'Loaded again');
N.memory[far_layout.actor + 0x6A0] = nil;
frame();
problem = anchor.problem();
for i = 1, plan.count do
    local unit = plan.units[i];
    if unit.index == FAR then
        assert(unit.path == 'guess' and unit.why == 'Reading the name point failed.',
            'The far Crawler says its read failed: ' .. tostring(unit.why));
    else
        assert(unit.path == 'name point' or unit.path == 'guess' and unit.why == problem,
            ('%s: %s %s'):format(unit.name, unit.path, tostring(unit.why)));
    end
end
N.memory[far_layout.actor + 0x6A0] = 1;
frame();
for i = 1, plan.count do
    assert(plan.units[i].path == 'guess' and plan.units[i].why == problem,
        plan.units[i].name .. ' keeps the guess after the far read failed');
end
