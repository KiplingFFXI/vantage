-- While overhead.update places its units, each memory region is page checked once, so the units whose blocks share a
-- region check it once a frame. After that loop, as for the preview's sample, every check is made again. A unit whose
-- name point was well off screen this tenth of a second isn't read again until the list is made again, while one on
-- screen is read every frame and one that comes on screen is read at once.
local N = require('name_anchor_fixture');
local W = N.W;
local overhead = require('core.overhead');
local anchor = require('core.name_anchor');
local plan = overhead.plan;
local settings = W.settings();
settings.overhead.units.self = true;
-- You, a Crawler ahead and one 12 yalms past the right edge of the screen. Their actors share one heap, their entities
-- another, and so do their skeleton nodes and their skeleton data.
local AHEAD, SIDE = 0x100, 0x101;
N.unit(W.self, 1001, 'player', 0, 0, { 0, -2.0, 0 }, { name = 'Tester', race = 7 });
N.unit(AHEAD, 0x1000100, 'mob', 1.5, -6, { 0, -2.5, 0 }, { name = 'Crawler', hitbox = 0.5 });
N.unit(SIDE, 0x1000101, 'mob', 20, 2, { 0, -2.5, 0 }, { name = 'Crawler', hitbox = 0.5 });
local rows = { { entity_id = 0x1000100, kind = 'debuff', scope = 'enemy', source = 1001 },
    { entity_id = 0x1000101, kind = 'debuff', scope = 'enemy', source = 1001 },
    { entity_id = 1001, kind = 'buff', scope = 'self', source = 1001, mine = true } };
local snapshot, view = W.snapshot(), W.view(rows);
local checks, heaps = 0, {};
anchor._set_pages(function(at, size)
    local start = at - at % 0x1000000;
    if start < 0x3000000 or start > 0x6000000 then return N.valid(at, size); end
    checks, heaps[start] = checks + 1, (heaps[start] or 0) + 1;
    return N.valid(at, size), start, start + 0x1000000;
end);
local side_actor, read_float, side_reads = N.layouts[SIDE].actor, ashita.memory.read_float, 0;
ashita.memory.read_float = function(at)
    if at >= side_actor and at < side_actor + 0x1000 then side_reads = side_reads + 1; end
    return read_float(at);
end;
local function frame(seconds)
    checks, side_reads = 0, 0;
    for start in pairs(heaps) do heaps[start] = nil; end
    W.frame(view, settings, snapshot, nil, seconds);
end
local function shows(id)
    for i = 1, plan.count do if plan.units[i].id == id then return true; end end
    return false;
end

-- The list made again: every unit's name point and skeleton is read, each heap checked once.
frame(0.125);
assert(shows(1001) and shows(0x1000100) and not shows(0x1000101), 'Fixture: you and the Crawler ahead get blocks: ' .. W.ids(plan));
assert(side_reads > 0, 'Fixture: the Crawler off screen is read as the list is made.');
assert(checks == 4 and heaps[0x3000000] == 1 and heaps[0x4000000] == 1 and heaps[0x5000000] == 1 and heaps[0x6000000] == 1,
    'Each heap is checked once as the list is made, not ' .. checks .. ' times in all.');
-- A frame later, the same list: the Crawler off screen isn't read, and the two read share their heaps' checks.
frame(0.01);
assert(shows(1001) and shows(0x1000100) and not shows(0x1000101), 'The same blocks a frame later: ' .. W.ids(plan));
assert(side_reads == 0, 'The Crawler well off screen isn\'t read again: ' .. side_reads .. ' reads.');
assert(checks == 2 and heaps[0x3000000] == 1 and heaps[0x4000000] == 1, 'Two units read check their two heaps once, not ' .. checks .. ' times.');
-- After the loop nothing is kept: your sample in the preview checks your actor's and entity's heaps again.
for start in pairs(heaps) do heaps[start] = nil; end
assert(overhead.sample({ size = 0 }, settings, snapshot, 'self') and heaps[0x3000000] == 1 and heaps[0x4000000] == 1,
    'The preview\'s sample checks its pages again.');
-- It walks on screen within the same tenth of a second, and is read at once.
N.move(SIDE, -1.5, -8);
frame(0.01);
assert(side_reads > 0 and shows(0x1000101), 'The Crawler that came on screen gets its block at once: ' .. W.ids(plan));
-- And back off it: read as the list is made again, then left alone.
N.move(SIDE, 20, 2);
frame(0.125);
assert(side_reads > 0 and not shows(0x1000101), 'The list made again reads it once more.');
frame(0.01);
assert(side_reads == 0, 'then leaves it alone: ' .. side_reads .. ' reads.');
