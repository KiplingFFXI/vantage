-- The overhead camera: known points through known matrices land where D3D puts them, mapped to ImGui's DisplaySize;
-- points behind the camera, on its near plane or past the far plane are rejected; each check on a bad matrix rejects
-- it, the last good camera is kept for hold_ms and then nothing is placed.
local camera = require('core.camera');
-- Read at present: no BeginScene comes before these frames.
local config = require('ui.overhead_defaults').make().camera;
config.capture = 'present';
local function near(a, b, tolerance) return math.abs(a - b) < (tolerance or 1e-6); end

-- A left-handed perspective, P22 1.7 at 16:9, near 0.5 and far 200, and a view from (10, 0, 5) looking along +x.
local xs, ys, q = 1.7 * 9 / 16, 1.7, 200 / 199.5;
local function projection() return { xs, 0, 0, 0, 0, ys, 0, 0, 0, 0, q, 1, 0, 0, -0.5 * q, 0 }; end
local function view() return { 0, 0, 1, 0, 0, 1, 0, 0, -1, 0, 0, 0, 5, 0, -10, 1 }; end
local V, P = view(), projection();
local reads = 0;
camera._set_reader(function(v, p)
    reads = reads + 1;
    for i = 1, 16 do v[i], p[i] = V[i], P[i]; end
    return true;
end);
local now = 10;
local function frame(width, height, x, y, z)
    now = now + 1 / 60;
    return camera.frame(now, config, width or 1920, height or 1080, x or 10, y or 0, z or 5);
end

assert(frame(), 'A good camera can be used.');
assert(reads == 1, 'Present mode reads once a frame.');
-- The camera the view puts at (10, 0, 5).
local ex, ey, ez = camera.eye();
assert(near(ex, 10) and near(ey, 0) and near(ez, 5), 'The camera position is -t times R transposed.');
-- Straight ahead lands in the middle of the 1920x1080 display; w is the view depth.
local sx, sy, w = camera.project(20, 0, 5);
assert(near(sx, 960) and near(sy, 540) and near(w, 10), ('ahead: %s %s %s'):format(sx, sy, w));
-- One yalm right (camera right is world -z here) and one up at depth 10.
sx, sy, w = camera.project(20, 1, 4);
assert(near(sx, (1 + xs / 10) * 960) and near(sy, (1 - ys / 10) * 540) and near(w, 10), ('right and up: %s %s'):format(sx, sy));
-- Pixels per yalm at the head: P22 * DisplayH / (2w).
assert(near(camera.pixels_per_yalm(10), 1.7 * 1080 / 20), 'px per yalm');
assert(near(camera.pixels_per_yalm(30), 1.7 * 1080 / 60), 'px per yalm falls with depth');

-- Behind the camera, on the near plane and past the far plane.
assert(camera.project(0, 0, 5) == nil, 'A point behind the camera is rejected.');
assert(camera.project(10.05, 0, 5) == nil, 'A point 0.05 yalms ahead is rejected (w <= 0.1).');
assert(camera.project(10, 0, 5) == nil, 'The camera point itself is rejected.');
assert(camera.project(10.3, 0, 5) == nil, 'A point in front of the near plane is rejected (NDC z < 0).');
assert(camera.project(220, 0, 5) == nil, 'A point past the far plane is rejected (NDC z > 1).');
assert(camera.project(math.huge, 0, 5) == nil, 'An infinitely far point is rejected (its NDC z is not a number).');
assert(camera.project(15, 0, 5) ~= nil, 'A point 5 yalms ahead is placed.');

-- DisplaySize, never the viewport: the same point on a 1920x1080 display with a 3840x2160 scene lands at the
-- display's middle. Another display size moves it with the display.
assert(frame(1920, 1080));
sx, sy = camera.project(20, 0, 5);
assert(near(sx, 960) and near(sy, 540), 'NDC maps to DisplaySize.');
assert(frame(1280, 720));
sx, sy = camera.project(20, 1, 4);
assert(near(sx, (1 + xs / 10) * 640) and near(sy, (1 - ys / 10) * 360), 'A resized display moves the points with it.');
assert(not frame(0, 1080), 'An empty display places nothing.');
assert(frame(), 'And a real one places again.');

-- Each bad projection, then each bad view, is rejected; the last good camera stays in use for 250 ms.
local function rejected(change, what)
    local before = { camera.project(20, 1, 4) };
    V, P = view(), projection();
    change();
    now = now + 0.5;
    assert(not camera.frame(now, config, 1920, 1080, 10, 0, 5), what .. ' is rejected once the hold is over.');
    V, P = view(), projection();
    assert(frame(), 'A good camera after ' .. what .. ' is used again.');
    local after = { camera.project(20, 1, 4) };
    assert(near(before[1], after[1]) and near(before[2], after[2]));
end
rejected(function() P[12] = 0.5; end, 'P34 not 1');
rejected(function() P[16] = 1; end, 'P44 not 0 (an orthographic one)');
for _, slot in ipairs({ 2, 3, 4, 5, 7, 8, 13, 14 }) do rejected(function() P[slot] = 0.01; end, 'projection entry ' .. slot); end
rejected(function() P[1] = -xs; end, 'P11 below 0');
rejected(function() P[11] = -q; end, 'P33 below 0');
rejected(function() P[15] = 0.5; end, 'P43 above 0');
rejected(function() P[6] = 0.2; P[1] = 0.1; end, 'P22 below 0.3');
rejected(function() P[6] = 7; P[1] = 4; end, 'P22 above 6');
rejected(function() P[1] = 0.1; end, 'an aspect past 5');
rejected(function() P[1] = 1.7 * 1.6; end, 'an aspect under 0.67');
rejected(function() P[9] = 0 / 0; end, 'a NaN in the projection');
rejected(function() V[1] = 1.1; end, 'a view row longer than 1');
rejected(function() V[5], V[6] = 0.2, 0.98; end, 'view rows not at right angles');
rejected(function() V[4] = 0.01; end, 'V14 not 0');
rejected(function() V[16] = 2; end, 'V44 not 1');
rejected(function() V[13] = math.huge; end, 'an infinite view');
rejected(function() V[13], V[15] = 5 - 100, -10; end, 'a camera 100 yalms away (a menu preview)');

-- Held: a bad camera 0.1 s after a good one still places with the good one; at 0.3 s nothing is placed.
assert(frame());
local good = { camera.project(20, 1, 4) };
P[12] = 0.5;
now = now + 0.1;
assert(camera.frame(now, config, 1920, 1080, 10, 0, 5), 'The last good camera is held for 250 ms.');
local held = { camera.project(20, 1, 4) };
assert(near(good[1], held[1]) and near(good[2], held[2]), 'The held camera places as it did.');
now = now + 0.2;
assert(not camera.frame(now, config, 1920, 1080, 10, 0, 5), 'Past hold_ms the bad camera hides everything.');
local report = camera.report();
assert(report.valid == false and report.problem == 'The projection is not the world camera: it is not a perspective (P34 0.5 and '
    .. 'P44 0, where a perspective has 1 or -1 and 0).' and report.capture == 'present', tostring(report.problem));
P = projection();
-- A failed read counts as a rejection too.
local unreadable = true;
camera._set_reader(function() return not unreadable; end);
now = now + 1;
assert(not camera.frame(now, config, 1920, 1080, 10, 0, 5), 'A camera that can\'t be read is not used.');
unreadable = false;

-- The rejections and passes of the last second are counted for /vg report.
camera._reset();
camera._set_reader(function(v, p) for i = 1, 16 do v[i], p[i] = V[i], P[i]; end; return true; end);
-- The first frame starts the second; every third of the next 59 fails; a good one a second later ends it.
camera.frame(50, config, 1920, 1080, 10, 0, 5);
for i = 1, 59 do
    P[12] = i % 3 == 0 and 0.5 or 1;
    camera.frame(50 + i / 60, config, 1920, 1080, 10, 0, 5);
end
P[12] = 1;
camera.frame(51.001, config, 1920, 1080, 10, 0, 5);
report = camera.report();
assert(report.passes_per_second == 41 and report.rejects_per_second == 19, ('%s passes, %s rejects'):format(report.passes_per_second,
    report.rejects_per_second));
assert(near(report.p22, 1.7) and near(report.p34, 1) and near(report.p44, 0) and near(report.p11, xs), 'The report gives P11, P22, P34, P44.');
assert(report.display.width == 1920 and report.display.height == 1080, 'and DisplaySize.');
