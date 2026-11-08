-- The name point's client patterns, on both decoded clients and on the new one loaded at another base: each is
-- found exactly once, and the offsets read out of them are the ones the client's code uses (actor root 0x678, scale
-- 0x698 / 0x6A0 / 0x69C, first node 0x6B8, point 2's offset 0x0E into its generator, the entity back pointer 0x70
-- with its model size 0x204, and so on). So are the /vg report camera check's. A pattern that is missing, found twice
-- or gives an offset its code doesn't allow turns the name points off, and the status names it.
local fixture = require('client_image_fixture');
local anchor = require('core.name_anchor');
local expected = { lift = 0x8C0, name_index = 0x8A7, arrow_index = 0x8A6, root = 0x678, scale_x = 0x698, scale_y = 0x6A0,
    scale_z = 0x69C, node = 0x6B8, handle = 0x0C, point = 0x0E, bone_count = 0x32, bones = 0x34, generators = 4, entity = 0x70,
    model_size = 0x204, model_first = 0x75C, model_last = 0x754, kind = 0xA4, low = 0x70, span = 0x8C4 - 0x70,
    entity_span = 0x208 - 0x78 };
local camera_offsets = { view = 0x94, projection = 0x154, world = 0x93C, wrapper_projection = 0x9BC, wrapper_view = 0x97C,
    viewport_index = 0x158, viewports = 0x98, window_w = 0x10, window_h = 0x12, scene_w = 0x18, scene_h = 0x1A };
local count = 0;
for _ in pairs(anchor._patterns) do count = count + 1; end
assert(count == 16, 'Sixteen name point patterns: ' .. count);

local function loaded(image)
    anchor._reset();
    image:install();
    anchor._set_pages(function(at, size) return image:contains(at, size); end);
    return anchor.load();
end

for _, case in ipairs({ { 'new', 0x10000000 }, { 'old', 0x10000000 }, { 'new', 0x0F300000 } }) do
    local image = fixture.load(case[1], case[2]);
    local where = ('%s at 0x%08X'):format(case[1], case[2]);
    assert(loaded(image), where .. ': ' .. tostring(anchor.status().problem));
    for name, pattern in pairs(anchor._patterns) do
        local first = image:find(image.base, #image.data, pattern, 0);
        assert(first ~= 0 and image:find(image.base, #image.data, pattern, 1) == 0, where .. ': ' .. name .. ' once');
    end
    for key, value in pairs(expected) do
        assert(anchor._offsets[key] == value, ('%s: %s is 0x%X, not 0x%X'):format(where, key, anchor._offsets[key] or -1, value));
    end
    local status = anchor.status();
    assert(status.usable and status.problem == nil and status.patterns.root:match('^0x%x+$') and status.offsets.root == '0x678', where);
    -- The camera check's own patterns, found at the first report.
    local cameras = anchor.cameras();
    assert(cameras.usable, where .. ': ' .. tostring(cameras.problem));
    for name, pattern in pairs(anchor._check_patterns) do
        assert(image:find(image.base, #image.data, pattern, 1) == 0 and image:find(image.base, #image.data, pattern, 0) ~= 0, name);
    end
    local check, delta = anchor._check, case[2] - 0x10000000;
    for key, value in pairs(camera_offsets) do
        assert(check[key] == value, ('%s: %s is 0x%X, not 0x%X'):format(where, key, check[key] or -1, value));
    end
    -- The client's camera and its device wrapper are globals, moved with the module.
    assert(check.app == 0x104568FC + delta and check.wrapper == 0x1045666C + delta, ('%s: app 0x%X, wrapper 0x%X'):format(where,
        check.app, check.wrapper));
end

-- Broken clients: the new one with one change each.
local new = fixture.load('new');
local patterns = anchor._patterns;
local function at(image, name) return image:find(image.base, #image.data, patterns[name], 0); end
local function broken(name, change, problem)
    local image = new:copy();
    change(image);
    assert(not loaded(image), name .. ' breaks the name points');
    local status = anchor.status();
    assert(status.usable == false and status.failed == name and status.problem == problem,
        ('%s: %s %s'):format(name, tostring(status.failed), tostring(status.problem)));
    assert(anchor.point({}, nil, 1, 1, 0x3000000, 1) == nil, name .. ': no unit gets a name point');
end
broken('lift', function(image) image:write(at(image, 'lift'), '\0'); end, 'The client pattern lift is missing.');
broken('name_index', function(image) image:write(image.base + #image.data - 16, '\138\129\167\8\0\0\195'); end,
    'The client pattern name_index matches more than once.');
broken('lift', function(image) image:write(at(image, 'lift') + 22, fixture.le32(0x3000)); end,
    'The client pattern lift gives an offset out of range.');
broken('scale', function(image) local found = at(image, 'scale'); image:write(found + 18, '\36'); end,
    'The client pattern scale gives an offset out of range.');
broken('node', function(image)
    -- The getter the node pattern calls: lea eax, [ecx + 0x44]; ret.
    local found = at(image, 'node');
    local relative = image:read32(found + 12);
    if relative >= 0x80000000 then relative = relative - 0x100000000; end
    image:write(found + 16 + relative + 3, '\144');
end, 'The client pattern node gives an offset out of range.');
broken('model_pick', function(image) image:write(at(image, 'model_pick') + 64, fixture.le32(0x760)); end,
    'The client pattern model_pick gives an offset out of range.');
broken('gate_chair', function(image) image:write(at(image, 'gate_chair') + 2, fixture.le32(0xA8)); end,
    'The client pattern gate_chair gives an offset out of range.');
broken('handle', function(image) image:write(at(image, 'handle') + 6, '\8'); end,
    'The client pattern handle gives an offset out of range.');
-- Point 2's offset past 0x0E would put the end of its three floats outside the generator entry the read checks.
broken('generator_offset', function(image) image:write(at(image, 'generator_offset') + 20, '\16'); end,
    'The client pattern generator_offset gives an offset out of range.');

-- Seventeen warmup steps: one search for each pattern, in sorted name order, then the offsets. No unit gets a name
-- point before the last, and after a pattern fails the rest are not looked for.
local function stepped(image)
    anchor._reset();
    image:install();
    anchor._set_pages(function(at, size) return image:contains(at, size); end);
    image.finds = 0;
    return anchor.warmup_steps();
end
local names = {};
for name in pairs(patterns) do names[#names + 1] = name; end
table.sort(names);
local image = new:copy();
local steps = stepped(image);
assert(#steps == 17 and steps[17].name == 'name_anchor.operands');
for index, name in ipairs(names) do
    assert(steps[index].name == 'name_anchor.' .. name, 'Step ' .. index .. ' is ' .. steps[index].name);
    steps[index].run();
    assert(image.finds == index * 2 and not anchor.usable(), name .. ': one pattern a step');
end
steps[17].run(); steps[1].run();
assert(anchor.usable() and anchor._offsets.root == 0x678 and anchor._offsets.lift == 0x8C0 and anchor.load() and image.finds == 32,
    'The last step reads the offsets, and nothing is searched again.');
image = new:copy();
image:write(at(image, 'entity'), '\0');
steps = stepped(image);
for _, step in ipairs(steps) do step.run(); end
local status = anchor.status();
assert(image.finds == 5 and not anchor.usable() and status.failed == 'entity' and status.problem == 'The client pattern entity is missing.',
    'After entity fails, the patterns after it are not looked for.');
anchor._reset();
new:install();
assert(anchor.load() and anchor.usable(), 'anchor.load alone still runs every step.');
