-- The name points in /vg report, the preview sample, the guess settings and the frame's cost. The report names the
-- client patterns and offsets, the target window and its cursors, and for each unit with a block or a cursor every
-- value its point is made from, how its block was placed and where the guess would have put it, with the client's
-- own cameras (its copies and the device wrapper's cache) against Vantage's. The sample over your head takes your
-- own name point, as your block would, and keeps it fresh while show conditions hide the blocks. A save with the guess
-- settings changed loads: the name points leave those settings out and the guess uses them. Placing from name points
-- makes nothing per frame. A client without one of the patterns places every block on the guess and the report names
-- the pattern.
local N = require('name_anchor_fixture');
local W = N.W;
local overhead = require('core.overhead');
local camera = require('core.camera');
local plan = overhead.plan;
local floor = math.floor;
local entities = AshitaCore:GetMemoryManager():GetEntity();
local le32 = require('client_image_fixture').le32;

local NEAR, SUB = 0x100, 0x102;
N.unit(W.self, 1001, 'player', 0, 0, { 0, -2.0, 0 }, { name = 'Tester', race = 7 });
N.unit(NEAR, 0x1000100, 'mob', 1.5, -3, { 0, -2.5, 0 }, { name = 'Crawler', hitbox = 0.5 });
N.unit(SUB, 0x1000102, 'mob', -2, -6, { 0, -2.5, 0 }, { name = 'Bat', hitbox = 0.6 });
local rows = { { entity_id = 0x1000100, kind = 'debuff', scope = 'enemy', source = 1001 },
    { entity_id = 1001, kind = 'buff', scope = 'self', source = 1001, mine = true } };
local snapshot, view = W.snapshot(), W.view(rows);

local function make_settings()
    local settings = W.settings();
    settings.overhead.units.self, settings.overhead.units.subtarget = true, false;
    return settings;
end
local settings = make_settings();
local config = settings.overhead;
local function frame(scenes)
    -- The scene reads, for the report's copy of the client camera there.
    for _ = 1, scenes or 0 do camera.scene(true); end
    W.frame(view, settings, snapshot);
end
local function placed(index)
    for i = 1, plan.count do if plan.units[i].index == index then return plan.units[i]; end end
    error('No block on ' .. index .. ': ' .. W.ids(plan) .. ' ' .. tostring(plan.hidden));
end
local function project(x, y, z)
    local m = camera._matrix;
    local w = x * m[4] + y * m[8] + z * m[12] + m[16];
    return ((x * m[1] + y * m[5] + z * m[9] + m[13]) / w + 1) * 960, (1 - (x * m[2] + y * m[6] + z * m[10] + m[14]) / w) * 540, w,
        (x * m[3] + y * m[7] + z * m[11] + m[15]) / w;
end

-- The client's camera copies and its device wrapper, in the fake memory, holding the camera Vantage reads: the
-- client draws names into its 3840x2160 scene target with half a pixel off, and that target is shrunk onto the
-- 1920x1080 window, so each point lands a quarter of a pixel up and left of Vantage's.
local image = N.image;
local app, wrapper = 0x8000000, 0x8100000;
N.regions[#N.regions + 1] = { app, 0x400 };
N.regions[#N.regions + 1] = { wrapper, 0x1000 };
image:write(0x104568FC, le32(app));
image:write(0x1045666C, le32(wrapper));
for i = 1, 16 do
    N.memory[app + 0x94 + (i - 1) * 4], N.memory[app + 0x154 + (i - 1) * 4] = W.view_matrix[i], W.projection_matrix[i];
    N.memory[wrapper + 0x97C + (i - 1) * 4], N.memory[wrapper + 0x9BC + (i - 1) * 4] = W.view_matrix[i], W.projection_matrix[i];
end
N.memory[app + 0x10], N.memory[app + 0x12], N.memory[app + 0x18], N.memory[app + 0x1A] = 1920, 1080, 3840, 2160;
N.memory[wrapper + 0x158] = 1;
N.memory[wrapper + 0x98 + 0x18], N.memory[wrapper + 0x98 + 0x1C] = 0, 0;
N.memory[wrapper + 0x98 + 0x20], N.memory[wrapper + 0x98 + 0x24] = 1920, 1080;
N.memory[wrapper + 0x98 + 0x28], N.memory[wrapper + 0x98 + 0x2C] = 0, 1;

-- What only the report reads, set apart from the defaults on the Crawler: the name's size and hide bits, the four
-- model sizes, the attachment offset, point 2's rotation, a render flag and the model size Ashita gives.
local near = N.layouts[NEAR];
N.memory[near.actor + 0x88], N.memory[near.actor + 0x8C], N.memory[near.actor + 0xB2] = 0x600, 1.5, 3;
N.memory[near.actor + 0x754], N.memory[near.actor + 0x758], N.memory[near.actor + 0x75C], N.memory[near.actor + 0x760] = 1.25, 0.5, 0.75, 1.5;
N.memory[near.actor + 0x60C], N.memory[near.actor + 0x610], N.memory[near.actor + 0x614] = 0.25, -0.5, 0.125;
N.memory[near.entry + 2], N.memory[near.entry + 6], N.memory[near.entry + 0x0A] = 0.5, 0.25, -0.25;
W.entities[NEAR].flags7, W.entities[NEAR].model = 0x40, 0.75;

-- The Crawler is targeted and the Bat picked as subtarget; the Bat has no block of its own.
W.target, W.sub, W.sub_active = NEAR, SUB, 1;
N.window.callback, N.window.sub = 1, 1;
frame();
local _, near_y = project(N.point(NEAR));
local _, sub_y = project(N.point(SUB));
N.window.ank_y, N.window.sub_y = N.trunc(near_y), N.trunc(sub_y) - 10;
frame();
local report = overhead.report(settings, snapshot);
local points = report.name_point;
assert(type(points) == 'table' and points.usable == true and points.problem == nil, 'The report has the name points: '
    .. tostring(points and points.problem));
local count = 0;
for name, value in pairs(points.patterns) do
    count = count + 1;
    assert(type(value) == 'string' and value:match('^0x%x+$'), name .. ' found at ' .. tostring(value));
end
assert(count == 16 and points.offsets.root == '0x678' and points.offsets.node == '0x6B8' and points.offsets.lift == '0x8C0',
    'Every pattern and offset: ' .. count);
assert(points.display.width == 1920 and points.display.height == 1080 and points.placement == 'above_name');
local window = points.window;
assert(window.getters and window.arrow_a == NEAR and window.arrow_b == SUB and window.box == 'read' and window.box_low == -32
    and window.box_high == 0 and window.box_left == -10 and window.box_right == 10 and window.ky == 1, 'The cursors and their box');
assert(window.action_callback == true and window.death_flag == 0 and window.sub == 1 and window.ank_x == 960
    and window.ank_y == N.trunc(near_y) and window.sub_ank_y == N.trunc(sub_y) - 10 and #window.frames == 6, 'The target window');
assert(window.targets[1].slot == 0 and window.targets[1].index == SUB and window.targets[2].index == NEAR
    and window.targets[2].active == 1 and window.targets[2].arrow_active == 0, 'Targets 0 and 1');
assert(window.targets[1].actor == ('0x%08X'):format(N.layouts[SUB].actor) and window.targets[2].actor == ('0x%08X'):format(near.actor),
    'Their actors');
-- Each cursor frame's box as read, not only the union.
assert(window.frames[1].shape == '0x07000100' and window.frames[6].shape == '0x07000600' and window.frames[6].min_x == -10
    and window.frames[6].max_x == 10 and window.frames[6].min_y == -32 and window.frames[6].max_y == 0, 'Each frame and its box');
assert(points.cameras.usable and points.cameras.app and points.cameras.now and not points.cameras.scene, 'The client cameras');
assert(points.cameras.scene_target.width == 3840 and points.cameras.scene_target.height == 2160 and points.cameras.back == nil
    and points.cameras.window.width == 1920 and points.cameras.window.height == 1080 and points.cameras.viewport.slot == 1
    and points.cameras.viewport.width == 1920 and points.cameras.viewport.max_z == 1, 'The scene target, window and viewport');
assert(type(points.fixed_offsets) == 'string', 'The report says which reads are at fixed offsets');

local function row_of(index)
    for _, row in ipairs(points.units) do if row.index == index then return row; end end
    error('No report row for ' .. index);
end
local row = row_of(NEAR);
local unit = placed(NEAR);
local x, y, z = N.point(NEAR);
local ax, ay, _, depth = project(x, y, z);
local t, s = N.texel(depth);
assert(row.placed and row.path == 'name point' and row.reason == nil and row.arrow == 'A' and row.kind == 'mob' and row.name == 'Crawler');
assert(row.ax == ax and row.ay == ay and row.ndc_z == depth and row.zi == floor(depth * 4096) and row.s == floor(s * 1e4 + 0.5) / 1e4
    and row.t == floor(t * 1e4 + 0.5) / 1e4, ('ax %s ay %s, unrounded'):format(row.ax, row.ay));
assert(row.name_top == floor((ay - 0.5) * 100 + 0.5) / 100 and row.icon_top == row.name_top
    and row.arrow_top == N.trunc(ay) - 32.5 and row.anchor_y == unit.anchor_y and row.anchor_x == unit.anchor_x, 'The name, icon and cursor tops');
assert(row.root_x == 1.5 and row.root_y == 0 and row.root_z == -3 and row.entity_x == 1.5 and row.entity_y == 0 and row.entity_z == -3
    and row.scale_x == 1 and row.scale_y == 1 and row.scale_z == 1 and row.generator_y == -2.5 and row.generator_x == 0
    and row.bone == 0 and row.name_index == 2 and row.arrow_index == 2 and row.lift == 0 and row.m == 0
    and row.x == 1.5 and row.y == -2.5 and row.z == -3 and row.back_link == true and row.bones == 20 and row.generators == 6,
    'The values the point is made from');
assert(row.actor == ('0x%08X'):format(N.layouts[NEAR].actor) and row.node == ('0x%08X'):format(N.layouts[NEAR].node), 'Pointers in hex');
-- The actor's kind (0xA4, behind the chocobo, mount and chair gates) is the client's, apart from Vantage's own kind;
-- the status, race, Ashita's model size and the hitbox are the unit's.
assert(row.actor_kind == 0 and row.status == 0 and row.race == 0 and row.model_size == 0.75 and row.hitbox == 0.5,
    ('The kind and status: %s %s'):format(tostring(row.actor_kind), tostring(row.status)));
-- The flags its icon is picked from, raw.
assert(row.flags0 == '0x00000200' and row.flags1 == '0x00000000' and row.flags7 == '0x00000040' and row.flags8 == '0x00000000'
    and row.campaign == 0 and row.ballista == 0 and row.monstrosity == 0, 'The icon flags: ' .. tostring(row.flags7));
-- Point 2's rotation, and the reads at fixed offsets: the position copy and attachment offset the root is made from,
-- the four model sizes and the name's size and hide bits.
assert(row.rotation_x == 0.5 and row.rotation_y == 0.25 and row.rotation_z == -0.25, 'Point 2\'s rotation');
assert(row.base_x == 1.5 and row.base_y == 0 and row.base_z == -3 and row.offset_x == 0.25 and row.offset_y == -0.5 and row.offset_z == 0.125
    and row.actor_754 == 1.25 and row.actor_758 == 0.5 and row.actor_75c == 0.75 and row.actor_760 == 1.5 and row.actor_88 == '0x00000600'
    and row.actor_8c == 1.5 and row.actor_b2 == 3, 'The fixed reads');
-- The frame's clip w and NDC x and y, and on the target the display px per menu px its stored cursor point gives.
local _, _, w = project(x, y, z);
assert(row.w == floor(w * 1e4 + 0.5) / 1e4 and row.ndc_x == floor((ax / 960 - 1) * 1e6 + 0.5) / 1e6
    and row.ndc_y == floor((1 - ay / 540) * 1e6 + 0.5) / 1e6,
    ('w %s, NDC %s %s'):format(tostring(row.w), tostring(row.ndc_x), tostring(row.ndc_y)));
assert(row.ky_sample == floor(ay / N.trunc(ay) * 1e4 + 0.5) / 1e4, 'The cursor scale sample: ' .. tostring(row.ky_sample));
-- The guess: a mob's name centred on its hitbox head, the capped name and cursor over it.
local types = config.types.mob;
local head = overhead.head_height(false, 0, 0, 0.5, 'Crawler', config.head, 0);
local _, hy, hdepth = camera.project(overhead.world_point(entities, NEAR, head));
assert(row.guess_anchor_y == overhead.above_name(hy, camera.pixels_per_yalm(hdepth), true, config.layout, 1, 1, types.screen_y)
    and row.guess_anchor_y ~= row.anchor_y, 'The guess: ' .. tostring(row.guess_anchor_y));
-- The client's cameras put the point a quarter of a pixel up and left of Vantage's.
local game = row.check.game;
assert(game.vantage_y == floor(ay * 100 + 0.5) / 100 and game.app_dx == 0.25 and game.app_dy == 0.25 and game.now_dx == 0.25
    and game.now_dy == 0.25 and game.scene_dx == nil,
    ('Against the client camera: %s %s'):format(tostring(game.app_dx), tostring(game.app_dy)));
assert(row.check.guess.app_dy == 0.25 and row.check.root.app_dy == 0.25, 'The guess and the root too');
-- The subtarget's cursor is on the Bat, which has no block.
local bat = row_of(SUB);
assert(bat.placed == false and bat.arrow == 'B' and bat.path == nil and bat.x == -2 and bat.y == -2.5, 'The subtarget row');
-- Your own row.
assert(row_of(W.self).path == 'name point' and row_of(W.self).generator_y == -2, 'Your row');

-- With the camera read at the scene, the wrapper's cache there is copied for the next report.
config.camera.capture = 'scene';
frame(2);
frame(2);
report = overhead.report(settings, snapshot);
assert(report.name_point.cameras.scene == true and report.name_point.units[1].check.game.scene_dy == 0.25, 'The scene copy');
config.camera.capture = 'present';

-- On a chocobo the client raises your name point by 1.3 times your model size (the actor's 0x754 here, as neither
-- the entity's nor 0x75C is set), and the height at 0x8C0 is added last; the report keeps them apart as m, model
-- and lift.
local own = N.layouts[W.self];
W.entities[W.self].status, N.memory[own.actor + 0x8C0] = 5, -0.4;
frame();
report = overhead.report(settings, snapshot);
for _, r in ipairs(report.name_point.units) do
    if r.index == W.self then
        assert(r.m == -1.3 and r.model == 1 and r.lift == -0.4 and r.status == 5 and r.actor_kind == 0 and r.y == -3.7,
            ('On a chocobo: m %s, model %s, lift %s, y %s'):format(tostring(r.m), tostring(r.model), tostring(r.lift), tostring(r.y)));
    end
end
W.entities[W.self].status, N.memory[own.actor + 0x8C0] = 0, 0;

-- Point 2 at zero: the point is the root, and the report says so.
N.memory[N.layouts[W.self].node + 0x0C] = 0;
frame();
report = overhead.report(settings, snapshot);
for _, r in ipairs(report.name_point.units) do
    if r.index == W.self then assert(r.generator_zero == true and r.y == 0 and r.path == 'name point', 'Point 2 at zero is flagged'); end
end
N.memory[N.layouts[W.self].node + 0x0C] = N.layouts[W.self].handle;
-- A unit on the guess says why.
N.memory[N.layouts[NEAR].entity + 0x78] = 0x1000999;
frame();
points = overhead.report(settings, snapshot).name_point;
row = row_of(NEAR);
assert(row.path == 'guess' and row.reason == 'The actor is not this unit\'s.' and row.back_link == false
    and row.anchor_y == row.guess_anchor_y, 'The guess and why: ' .. tostring(row.reason));
N.memory[N.layouts[NEAR].entity + 0x78] = 0x1000100;
W.target, W.sub, W.sub_active, N.window.callback, N.window.sub = 0, 0, 0, 0, 0;

-- The preview's sample of a mob block sits over your own name point, as your block would, and takes the cursor's
-- room only when you carry it.
local sample = { kind = 'mob', target = false, subtarget = false, player = false, hitbox = 0, name = '', race = 0, size = 0, alpha = 1,
    x = 0, y = 0, anchor_x = 0, anchor_y = 0, depth = 0, distance = 0, ppy = 0, name_px = 0, arrow_px = 0 };
frame();
assert(overhead.sample(sample, settings, snapshot, 'mob'), 'The sample is placed');
local sx, sy = project(N.point(W.self));
assert(sample.anchor_y == floor(sy - 0.5 - 3 + 0.5) and sample.anchor_x == floor(sx + 0.5) and sample.anchor_y == placed(W.self).anchor_y,
    ('The sample over your name point: %d, your block %d'):format(sample.anchor_y, placed(W.self).anchor_y));
W.target, N.window.ank_y = W.self, N.trunc(sy);
frame();
overhead.sample(sample, settings, snapshot, 'mob');
assert(sample.anchor_y == N.trunc(sy) - 35, 'Targeting yourself, the sample leaves the cursor\'s room: ' .. sample.anchor_y);
W.target = 0;
frame();
-- While show conditions hide the blocks the sample still shows, and what its point is made from is read again ten
-- times a second all the same: an icon you gain then raises it, and a new menu size reaches the cursor's scale.
local function conditions_hidden(n)
    for _ = 1, n do
        W.now = W.now + 0.125;
        overhead.update(view, settings, snapshot, W.now, false, true);
    end
end
conditions_hidden(2);
assert(plan.hidden == 'Its When to show choices hide it here.' and overhead.sample(sample, settings, snapshot, 'mob')
    and sample.anchor_y == floor(sy - 0.5 - 3 + 0.5), 'The sample while show conditions hide the blocks: ' .. sample.anchor_y);
W.entities[W.self].flags1 = 0x08000000;
local chat = package.loaded['core.chat'];
package.loaded['core.chat'] = { menu_size = function() return 1280, 720; end };
conditions_hidden(2);
overhead.sample(sample, settings, snapshot, 'mob');
local _, _, _, own_depth = project(N.point(W.self));
local icon = math.ceil(1.0625 * N.texel(own_depth));
assert(icon > 0 and sample.anchor_y == floor(sy - 0.5 - icon - 3 + 0.5), ('A linkshell icon gained while hidden: %d, %d expected'):format(
    sample.anchor_y, floor(sy - 0.5 - icon - 3 + 0.5)));
assert(require('core.name_anchor').status(N.targets).window.ky == 1.5, 'The menu size read again while hidden');
package.loaded['core.chat'] = chat;
W.entities[W.self].flags1 = 0;
frame();

-- A save with every guess setting changed loads with them; the name points leave them out, the guess keeps them.
local defaults, store = require('ui.defaults'), require('core.store');
local changed = defaults.make();
local head_settings, layout = changed.overhead.head, changed.overhead.layout;
head_settings.race_heights[7], layout.name_height, layout.name_cap, layout.target_height, layout.target_cap = 2.6, 0.9, 40, 1, 30;
changed.overhead.types.mob.name_lift, changed.overhead.types.self.name_lift = 0.75, 1.25;
changed.overhead.enabled, changed.overhead.camera.capture, changed.overhead.units.self = true, 'present', true;
local path = MOCK_INSTALL_PATH .. '/guess-save.json';
assert(store.write(path, changed));
local loaded = defaults.tidy(assert(store.read(path)));
assert(loaded.overhead.head.race_heights[7] == 2.6 and loaded.overhead.layout.name_height == 0.9 and loaded.overhead.layout.target_cap == 30
    and loaded.overhead.types.mob.name_lift == 0.75 and loaded.overhead.types.self.name_lift == 1.25, 'The save loads as it was.');
local before_self, before_near = placed(W.self).anchor_y, placed(NEAR).anchor_y;
settings = loaded;
config = settings.overhead;
frame();
assert(placed(W.self).anchor_y == before_self and placed(NEAR).anchor_y == before_near, 'The name points leave the guess settings out.');
N.memory[N.layouts[NEAR].entity + 0x78] = 0x1000999;
frame();
local guess_head = overhead.head_height(false, 0, 0, 0.5, 'Crawler', config.head, 0) + 0.75;
local _, gy, gdepth = camera.project(overhead.world_point(entities, NEAR, guess_head));
assert(placed(NEAR).path == 'guess' and placed(NEAR).anchor_y == overhead.above_name(gy, camera.pixels_per_yalm(gdepth), false, config.layout,
    1, 1, 0), 'The guess uses them.');
N.memory[N.layouts[NEAR].entity + 0x78] = 0x1000100;
settings = make_settings();
config = settings.overhead;

-- Placing from name points makes nothing per frame, the ten-a-second list and skeleton reads included.
W.target, N.window.ank_y = NEAR, N.trunc(near_y);
local leak, made = false, nil;
local function frames(n)
    for i = 1, n do
        W.frame(view, settings, snapshot, false, 1 / 60);
        if leak and i % 6 == 0 then made = {}; end
    end
end
local function measure(n)
    jit.off(); jit.flush();
    frames(60);
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    local start = collectgarbage('count');
    frames(n);
    local each = (collectgarbage('count') - start) / n;
    collectgarbage('restart');
    jit.on();
    return each;
end
frames(600);
assert(placed(NEAR).path == 'name point' and placed(W.self).path == 'name point', 'Placing from name points');
local each = measure(600);
assert(each < 0.002, ('Placing from name points makes %.4f KB a frame; nothing expected'):format(each));
leak = true;
each = measure(600);
leak = false;
assert(each >= 0.002 and made, ('One table made ten times a second shows as %.4f KB a frame'):format(each));
-- The cursor's frames are read again ten times a second, once each time: the tenth of a second and the list made
-- in the same frame count once. Each read asks for the six frames and the empty slot after them.
local shape_getter, shape_calls = N.targets.GetWindowAnkShape, 0;
N.targets.GetWindowAnkShape = function(self, i) shape_calls = shape_calls + 1; return shape_getter(self, i); end;
frames(60);
N.targets.GetWindowAnkShape = shape_getter;
assert(shape_calls >= 8 * 7 and shape_calls <= 11 * 7, ('The cursor frames read %.1f times in a second'):format(shape_calls / 7));

-- A client without the root pattern: every block keeps the guess, and the report names the pattern.
local anchor = package.loaded['core.name_anchor'];
anchor._reset();
image:write(image:find(image.base, #image.data, anchor._patterns.root, 0), '\0');
frame();
for i = 1, plan.count do
    assert(plan.units[i].path == 'guess' and plan.units[i].why == 'The client pattern root is missing.',
        plan.units[i].name .. ' keeps the guess: ' .. tostring(plan.units[i].why));
end
points = overhead.report(settings, snapshot).name_point;
assert(points.usable == false and points.failed == 'root' and points.problem == 'The client pattern root is missing.'
    and points.patterns.root == 'not found', 'The report names the pattern.');
