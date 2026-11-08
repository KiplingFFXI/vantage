-- The camera part of /vg report says why a camera can't be used: which check failed, with the values read, for every
-- check of the projection (with either handedness) and of the view, the camera's distance from you included. It holds
-- all 16 values of the last view and projection read, to 6 places, with a value JSON can't hold put in words, so the
-- report is still saved. The cameras are the game's right-handed one (the P11 and P22 of a Phoenix /vg report, a
-- near plane of 0.5 and a far one of 500, a view 6 yalms behind you and 2.5 up) and its left-handed mirror.
local camera = require('core.camera');
local store = require('core.store');
-- Read at present: no BeginScene comes before these frames.
local config = require('ui.overhead_defaults').make().camera;
config.capture = 'present';

local P11, P22, zn, zf = 0.74774223566055, 1.2604166269302, 0.5, 500;
local function right_handed() return { P11, 0, 0, 0, 0, P22, 0, 0, 0, 0, zf / (zn - zf), -1, 0, 0, zn * zf / (zn - zf), 0 }; end
local function left_handed() return { P11, 0, 0, 0, 0, P22, 0, 0, 0, 0, zf / (zf - zn), 1, 0, 0, zn * zf / (zn - zf), 0 }; end
-- A right-handed look-at in render space (X, height with up negative, Y), up (0, -1, 0).
local function look_at(eye, at)
    local function unit(x, y, z) local length = math.sqrt(x * x + y * y + z * z); return x / length, y / length, z / length; end
    local zx, zy, zz = unit(eye[1] - at[1], eye[2] - at[2], eye[3] - at[3]);
    local xx, xy, xz = unit(-zz, 0, zx);
    local yx, yy, yz = zy * xz - zz * xy, zz * xx - zx * xz, zx * xy - zy * xx;
    return { xx, yx, zx, 0, xy, yy, zy, 0, xz, yz, zz, 0, -(xx * eye[1] + xy * eye[2] + xz * eye[3]),
        -(yx * eye[1] + yy * eye[2] + yz * eye[3]), -(zx * eye[1] + zy * eye[2] + zz * eye[3]), 1 };
end
local function view() return look_at({ 0, -2.5, 6 }, { 0, -1.5, 0 }); end
local V, P = view(), right_handed();
camera._set_reader(function(v, p)
    for i = 1, 16 do v[i], p[i] = V[i], P[i]; end
    return true;
end);
local now = 10;
local function frame()
    now = now + 1;
    return camera.frame(now, config, 1920, 1080, 0, 0, 0);
end
local function rounded(value) return math.floor(value * 1e6 + 0.5) / 1e6; end

assert(frame(), 'The right-handed camera is used: ' .. tostring(camera.report().problem));
local report = camera.report();
assert(report.valid and report.problem == nil, 'No problem while it is used.');
assert(type(report.view) == 'table' and type(report.projection) == 'table' and #report.view == 16 and #report.projection == 16,
    'The report holds all 16 values of the view and of the projection.');
for i = 1, 16 do
    assert(report.view[i] == rounded(V[i]) and report.projection[i] == rounded(P[i]), 'Value ' .. i .. ' to 6 places.');
end
assert(report.projection[1] == 0.747742 and report.projection[6] == 1.260417 and report.projection[11] == -1.001001
    and report.projection[12] == -1 and report.projection[15] == -0.500501 and report.projection[16] == 0, 'The projection as read.');
assert(report.view[6] == -0.986394 and report.view[14] == -1.479591 and report.view[15] == -6.329361 and report.view[16] == 1,
    'The view as read.');
assert(report.p11 == 0.747742 and report.p22 == 1.260417 and report.p34 == -1 and report.p44 == 0, 'P11, P22, P34 and P44.');
assert(type(store.encode(report)) == 'string', 'The report can be saved.');

-- Each check that fails says so, with what it read. The frames are a second apart, past the hold.
local function failing(base, change, expected)
    V, P = view(), base();
    change();
    assert(not frame(), 'Not used: ' .. expected);
    local problem = camera.report().problem;
    assert(problem == expected, ('\n%s\nnot\n%s'):format(tostring(problem), expected));
    assert(not problem:find('?', 1, true) and not problem:lower():find('unknown', 1, true), problem);
    V, P = view(), right_handed();
    assert(frame() and camera.report().problem == nil, 'Used again after: ' .. expected);
end
local function projection_says(text) return 'The projection is not the world camera: ' .. text .. '.'; end
local function view_says(text) return 'The view is not the world camera near you: ' .. text .. '.'; end
failing(right_handed, function() P[12] = 0.5; end,
    projection_says('it is not a perspective (P34 0.5 and P44 0, where a perspective has 1 or -1 and 0)'));
-- An interface pass: D3DX's orthographic off-center projection of a 1920x1080 screen.
failing(right_handed, function() P = { 2 / 1920, 0, 0, 0, 0, -2 / 1080, 0, 0, 0, 0, 1, 0, -1, 1, 0, 1 }; end,
    projection_says('it is not a perspective (P34 0 and P44 1, where a perspective has 1 or -1 and 0)'));
failing(right_handed, function() P[2] = 0.01; end, projection_says('it is not a perspective (P12 is 0.01, where a perspective has 0)'));
failing(right_handed, function() P[14] = 0.5; end, projection_says('it is not a perspective (P42 is 0.5, where a perspective has 0)'));
-- The depth for each handedness: P33 of the other sign, or P43 above 0.
failing(right_handed, function() P[11] = -P[11]; end, projection_says('its depth does not fit a right-handed camera (P33 1.001 and P43 '
    .. '-0.500501 with P34 -1, where P33 takes the sign of P34 and P43 is below 0)'));
failing(right_handed, function() P[15] = 0.5; end, projection_says('its depth does not fit a right-handed camera (P33 -1.001 and P43 '
    .. '0.5 with P34 -1, where P33 takes the sign of P34 and P43 is below 0)'));
failing(left_handed, function() P[11] = -P[11]; end, projection_says('its depth does not fit a left-handed camera (P33 -1.001 and P43 '
    .. '-0.500501 with P34 1, where P33 takes the sign of P34 and P43 is below 0)'));
failing(right_handed, function() P[6] = 0.2; P[1] = 0.1; end, projection_says('its field of view is out of range (P22 0.2, not from 0.3 to 6)'));
failing(right_handed, function() P[6] = 7; P[1] = 4; end, projection_says('its field of view is out of range (P22 7, not from 0.3 to 6)'));
failing(right_handed, function() P[1] = 0.1; end, projection_says('its aspect is out of range (P11 0.1 with P22 1.26042, where P11 is '
    .. 'above 0 and from 0.2 to 1.5 times P22)'));
failing(right_handed, function() P[1] = -P11; end, projection_says('its aspect is out of range (P11 -0.747742 with P22 1.26042, where P11 '
    .. 'is above 0 and from 0.2 to 1.5 times P22)'));
-- Not a number: the report says it in words, and is still saved.
failing(right_handed, function() P[9] = 0 / 0; end, projection_says('one of its values is not a number or is ten million or more'));
V, P = view(), right_handed();
P[9], P[13] = 0 / 0, math.huge;
frame();
report = camera.report();
assert(report.projection[9] == 'not a number' and report.projection[13] == 'infinity' and type(store.encode(report)) == 'string',
    'A value JSON can\'t hold is put in words.');
V[14] = -math.huge;
P = right_handed();
frame();
report = camera.report();
assert(report.view[14] == '-infinity' and report.problem == view_says('one of its values is not a number or is ten million or more')
    and type(store.encode(report)) == 'string', tostring(report.problem));
-- The view: its last column, its rows, and how far the camera is from you.
failing(right_handed, function() V[4] = 0.01; end, view_says('its last column is not 0, 0, 0, 1 (0.01, 0, 0, 1)'));
failing(right_handed, function() V[16] = 2; end, view_says('its last column is not 0, 0, 0, 1 (0, 0, 0, 2)'));
failing(right_handed, function() V[1], V[2], V[3] = V[1] * 1.1, V[2] * 1.1, V[3] * 1.1; end,
    view_says('its rows are not of length 1 (row 1 is 1.1 long)'));
failing(right_handed, function() V[5] = 0.2; end, view_says('its rows are not at right angles (rows 1 and 2 have a dot product of -0.2)'));
failing(right_handed, function() V = look_at({ 0, -2.5, 106 }, { 0, -1.5, 100 }); end,
    view_says('the camera is 106.0 yalms from you, past 60'));
-- With the left-handed mirror the same checks hold, and its own camera is used.
V, P = view(), left_handed();
for _, i in ipairs({ 3, 7, 11, 15 }) do V[i] = -V[i]; end
assert(frame() and camera.report().problem == nil and camera.report().p34 == 1, 'The left-handed mirror is used.');
