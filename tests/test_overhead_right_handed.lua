-- The game's own camera is right-handed: P34 -1, with P33 and P43 below 0, so a point in front has a negative view z
-- and w is minus view z. With the P11 and P22 of a Phoenix /vg report on a 1920x1080 display, a near plane of 0.5
-- and a far one of 500, and a view 6 yalms behind you and 2.5 up looking ahead, the camera can be used, a point
-- ahead lands where D3D puts it with a positive depth, sensible pixels per yalm and a sensible icon size, a point
-- behind the camera, too near it or past the far plane is dropped, and the same scene through the left-handed
-- mirror of that camera lands on the same pixels.
local camera = require('core.camera');
local overhead = require('core.overhead');
local defaults = require('ui.overhead_defaults').make();
-- Read at present: no BeginScene comes before these frames.
local config = defaults.camera;
config.capture = 'present';
local function near(a, b, tolerance) return math.abs(a - b) < (tolerance or 1e-6); end

local P11, P22, zn, zf = 0.74774223566055, 1.2604166269302, 0.5, 500;
local function projection()
    return { P11, 0, 0, 0, 0, P22, 0, 0, 0, 0, zf / (zn - zf), -1, 0, 0, zn * zf / (zn - zf), 0 };
end
-- A right-handed look-at in render space (X, height with up negative, Y): view z points from what it looks at back
-- to the camera, so ahead is minus view z.
local function look_at(eye, at, up)
    local function unit(x, y, z) local length = math.sqrt(x * x + y * y + z * z); return x / length, y / length, z / length; end
    local zx, zy, zz = unit(eye[1] - at[1], eye[2] - at[2], eye[3] - at[3]);
    local xx, xy, xz = unit(up[2] * zz - up[3] * zy, up[3] * zx - up[1] * zz, up[1] * zy - up[2] * zx);
    local yx, yy, yz = zy * xz - zz * xy, zz * xx - zx * xz, zx * xy - zy * xx;
    return { xx, yx, zx, 0, xy, yy, zy, 0, xz, yz, zz, 0, -(xx * eye[1] + xy * eye[2] + xz * eye[3]),
        -(yx * eye[1] + yy * eye[2] + yz * eye[3]), -(zx * eye[1] + zy * eye[2] + zz * eye[3]), 1 };
end
local EYE = { 0, -2.5, 6 };
local function view() return look_at(EYE, { 0, -1.5, 0 }, { 0, -1, 0 }); end
local V, P = view(), projection();
camera._set_reader(function(v, p)
    for i = 1, 16 do v[i], p[i] = V[i], P[i]; end
    return true;
end);
local now = 10;
-- You stand at the render-space origin.
local function frame()
    now = now + 1 / 60;
    return camera.frame(now, config, 1920, 1080, 0, 0, 0);
end
-- Where D3D puts a render-space point through V and P, worked out in view space: NDC x is P11 times view x over w,
-- NDC y is P22 times view y over w, and w is P34 times view z.
local function expected(x, y, z)
    local vx = x * V[1] + y * V[5] + z * V[9] + V[13];
    local vy = x * V[2] + y * V[6] + z * V[10] + V[14];
    local vz = x * V[3] + y * V[7] + z * V[11] + V[15];
    local w = vz * P[12];
    return (P[1] * vx / w + 1) * 960, (1 - P[6] * vy / w) * 540, w;
end

assert(frame(), 'The game\'s right-handed camera can be used: ' .. tostring(camera.report().problem));
local ex, ey, ez = camera.eye();
assert(near(ex, 0) and near(ey, -2.5) and near(ez, 6), ('The camera is where the view puts it: %s %s %s'):format(ex, ey, ez));

-- A Goblin's head (1.8 yalms up) 5 yalms ahead of you and 2 to the side, as (X, Z - 1.8, Y).
local sx, sy, w = camera.project(2, -1.8, -5);
assert(sx, 'A head in front of the camera is placed.');
local wx, wy, ww = expected(2, -1.8, -5);
assert(near(sx, wx, 1e-6) and near(sy, wy, 1e-6) and near(w, ww, 1e-9), ('Where D3D puts it: %s %s %s'):format(sx, sy, w));
assert(near(sx, 829.073, 1e-3) and near(sy, 470.611, 1e-3) and near(w, 10.965, 1e-3), ('Head point: %s %s %s'):format(sx, sy, w));
assert(w > 0, 'Its depth is positive.');
-- Its feet sit below the head on screen, by about its 1.8 yalms at that depth.
local fx, fy, fw = camera.project(2, 0, -5);
assert(fx and fy > sy and fw > 0 and near(fy - sy, 109.134, 1e-3), ('The head sits above the feet: %s'):format(fy - sy));
local ppy = camera.pixels_per_yalm(w);
assert(near(ppy, P22 * 1080 / 2 / w, 1e-9) and ppy > 50 and ppy < 75, 'Pixels per yalm: ' .. ppy);
-- The Goblin as the target: 22 px at 10 yalms, times the square root of 10 over its depth, its hitbox class and 1.2.
local size = overhead.icon_size(false, 0, 1.2, 'Goblin', w, true, defaults, 1, 1);
assert(near(size, 22 * math.sqrt(10 / w) * math.sqrt(1.2 / 1.5) * 1.2, 1e-9) and math.floor(size + 0.5) == 23,
    'Its icons are 23 px: ' .. size);

-- Dropped: behind the camera, nearer than its near plane, and past its far plane.
assert(camera.project(0, -1, 12) == nil, 'A point behind the camera is dropped.');
assert(camera.project(EYE[1], EYE[2], EYE[3]) == nil, 'The camera point itself is dropped.');
local ahead_x, ahead_y, ahead_z = -V[3], -V[7], -V[11];
assert(camera.project(EYE[1] + 0.3 * ahead_x, EYE[2] + 0.3 * ahead_y, EYE[3] + 0.3 * ahead_z) == nil,
    'A point 0.3 yalms ahead, inside the near plane, is dropped.');
assert(camera.project(EYE[1] + 2 * ahead_x, EYE[2] + 2 * ahead_y, EYE[3] + 2 * ahead_z) ~= nil, 'A point 2 yalms ahead is placed.');
assert(camera.project(0, -1.5, -600) == nil, 'A point past the far plane is dropped.');

-- The left-handed mirror of the same camera: the view's third column and the projection's third row negated. Its
-- view times projection is the same, so every point lands on the same pixels, and it is used too.
local mirror_view, mirror_projection = view(), projection();
for _, i in ipairs({ 3, 7, 11, 15 }) do mirror_view[i] = -mirror_view[i]; end
for i = 9, 12 do mirror_projection[i] = -mirror_projection[i]; end
assert(mirror_projection[12] == 1 and mirror_projection[11] > 0 and mirror_projection[15] < 0, 'The mirror is left-handed.');
V, P = mirror_view, mirror_projection;
assert(frame(), 'The left-handed mirror can be used too: ' .. tostring(camera.report().problem));
local lx, ly, lw = camera.project(2, -1.8, -5);
assert(near(lx, sx, 1e-6) and near(ly, sy, 1e-6) and near(lw, w, 1e-9), ('The same pixels: %s %s %s'):format(lx, ly, lw));
assert(camera.project(0, -1, 12) == nil, 'And the point behind it is dropped.');
ex, ey, ez = camera.eye();
assert(near(ex, 0) and near(ey, -2.5) and near(ez, 6), 'The mirror puts the camera in the same place.');
-- And back: frames can switch between the two.
V, P = view(), projection();
assert(frame() and near((camera.project(2, -1.8, -5)), sx, 1e-6), 'The right-handed camera again.');
