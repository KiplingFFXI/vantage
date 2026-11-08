-- The world camera for the overhead icons: the game's view and projection matrices, read from the Direct3D device
-- into buffers made once, checked every frame, and used to put world points on the ImGui screen. It only reads the
-- device; nothing is set or drawn.
local camera = {};
local abs, floor, sqrt = math.abs, math.floor, math.sqrt;
-- D3DTS_VIEW and D3DTS_PROJECTION (Ashita's libs/d3d8/d3d8types.lua).
local VIEW, PROJECTION = 2, 3;
-- A point this close to the camera, or behind it, isn't placed: its icons would blow up as the camera passes
-- through a model.
local NEAR = 0.1;

-- The last matrices read, 16 Lua numbers each in D3D's row order (_11, _12, ... _44), and view times projection
-- of the last good pair, which places the points.
local view, projection, matrix = {}, {}, {};
for i = 1, 16 do view[i], projection[i], matrix[i] = 0, 0, 0; end
-- What the last frame used, for /vg report and calibrate. failed names the check the last read failed, which the
-- report spells out from the matrices; distance and reach are the camera's distance from you and the limit, when
-- that was the check.
local status = { capture = 'present', valid = false, problem = 'Not read yet.', passes = 0, rejects = 0,
    good_p22 = 0, width = 0, height = 0, scenes = 0, scene_flags = 0, read = false, failed = nil, distance = 0, reach = 0 };
local good_at, second_at, passes, rejects = nil, nil, 0, 0;
local active, scene_index, scene_count, scene_flags, scene_read = false, 2, 0, 0, false;
-- The device and the buffers GetTransform writes into, made once. The device pointer is cast again only when the
-- game's device changes.
local binding = { address = nil };
local reader;
-- Called at the scene read, after the matrices are read: core/name_anchor.lua copies the client's own camera there
-- for /vg report.
local scene_hook;

-- Where the matrices are read, the one place the choice is made: at the scene_index-th BeginScene of the frame (the
-- default, as icons placed from present-time matrices shake in game), or at present, the one to try when scene reads
-- no camera. Settings always name one; anything else is present, which needs no BeginScene.
function camera.capture_point(config)
    return config and config.capture == 'scene' and 'scene' or 'present';
end

local function device_address() return AshitaCore:GetDirect3DDevice(); end

-- Binds Ashita's libs/d3d8 to the game's device. Returns whether it can be read; status.problem says why not.
local function bind()
    local ok, address = pcall(device_address);
    if not ok or type(address) ~= 'number' or address == 0 then
        binding.address, binding.device = nil, nil;
        status.problem = 'The graphics device is not available.';
        return false;
    end
    if address == binding.address then return binding.device ~= nil; end
    binding.address, binding.device = address, nil;
    local made, why = pcall(function()
        if not binding.view_cell then
            local ffi, d3d8 = require('ffi'), require('d3d8');
            binding.view_cell, binding.projection_cell = ffi.new('D3DMATRIX[1]'), ffi.new('D3DMATRIX[1]');
            binding.view_floats = ffi.cast('float*', binding.view_cell);
            binding.projection_floats = ffi.cast('float*', binding.projection_cell);
            -- X, Y, Width, Height as DWORDs, read as numbers without a struct reference each frame.
            binding.viewport = ffi.new('D3DVIEWPORT8[1]');
            binding.viewport_words = ffi.cast('uint32_t*', binding.viewport);
            binding.d3d8 = d3d8;
        end
        local device = binding.d3d8.get_device();
        if device == nil then error('The graphics device is not available.', 0); end
        binding.get_transform, binding.get_viewport = device.lpVtbl.GetTransform, device.lpVtbl.GetViewport;
        binding.device = device;
    end);
    if not made then status.problem = 'The graphics device could not be read. ' .. tostring(why); end
    return made;
end

-- Both matrices through the device's own GetTransform, checked by its result.
local function read_device(into_view, into_projection)
    if not bind() then return false; end
    local device, get = binding.device, binding.get_transform;
    if get(device, VIEW, binding.view_cell) ~= 0 or get(device, PROJECTION, binding.projection_cell) ~= 0 then
        status.problem = 'The graphics device gave no camera.';
        return false;
    end
    local v, p = binding.view_floats, binding.projection_floats;
    for i = 0, 15 do into_view[i + 1], into_projection[i + 1] = v[i], p[i]; end
    get = binding.get_viewport;
    if get(device, binding.viewport) == 0 then
        status.viewport_width, status.viewport_height = binding.viewport_words[2], binding.viewport_words[3];
    end
    return true;
end

local function read(into_view, into_projection)
    if reader then return reader(into_view, into_projection) == true; end
    local ok, result = pcall(read_device, into_view, into_projection);
    if not ok then status.problem = 'The graphics device could not be read. ' .. tostring(result); end
    return ok and result;
end

local function small(value) return abs(value) < 1e-3; end

local function finite(m)
    for i = 1, 16 do local value = m[i]; if not (value == value and abs(value) < 1e7) then return false; end end
    return true;
end

-- The entries off the diagonal a perspective has at 0: P12, P13, P14, P21, P23, P24, P41 and P42.
local ZEROS = { 2, 3, 4, 5, 7, 8, 13, 14 };

-- Which check a projection fails as the game's world camera, or nil when it passes: a perspective (P34 1 or -1 and
-- P44 0, the rest off the diagonal 0) of either handedness, its depth running 0 to 1 from the near plane to the far
-- one (P33 of P34's sign and P43 below 0, so w is the view depth in front of the camera), a vertical field of view
-- of about 19 to 146 degrees and an aspect from about 0.67 to 5. The game's camera is right-handed: P34 -1.
local function projection_check(p)
    if not finite(p) then return 'finite'; end
    if not (abs(abs(p[12]) - 1) < 1e-3 and small(p[16])) then return 'shape'; end
    for i = 1, #ZEROS do if not small(p[ZEROS[i]]) then return 'zeros'; end end
    if not (p[11] * p[12] > 0 and p[15] < 0) then return 'depth'; end
    if not (p[6] >= 0.3 and p[6] <= 6) then return 'field'; end
    if not (p[1] > 0 and p[1] >= 0.2 * p[6] and p[1] <= 1.5 * p[6]) then return 'aspect'; end
end

-- Where the view puts the camera, in render space: c = -t * R^T, t the bottom row and R the rotation.
local function eye(v)
    local x, y, z = v[13], v[14], v[15];
    return -(x * v[1] + y * v[2] + z * v[3]), -(x * v[5] + y * v[6] + z * v[7]), -(x * v[9] + y * v[10] + z * v[11]);
end

local function row_length(v, a) return v[a] * v[a] + v[a + 1] * v[a + 1] + v[a + 2] * v[a + 2]; end
local function row_dot(v, a, b) return v[a] * v[b] + v[a + 1] * v[b + 1] + v[a + 2] * v[b + 2]; end

-- Which check a view fails, or nil when it passes: a rigid view, finite, rows of length 1 at right angles (either
-- handedness), no projection part, and the camera within max_distance yalms of you. That last one catches a menu's
-- own preview camera, and keeps how far it was.
local function view_check(v, max_distance, ox, oy, oz)
    if not finite(v) then return 'finite'; end
    if not (small(v[4]) and small(v[8]) and small(v[12]) and abs(v[16] - 1) < 1e-3) then return 'column'; end
    for a = 1, 9, 4 do
        local length = row_length(v, a);
        if length < 0.9604 or length > 1.0404 then return 'length'; end
    end
    if abs(row_dot(v, 1, 5)) >= 0.02 or abs(row_dot(v, 1, 9)) >= 0.02 or abs(row_dot(v, 5, 9)) >= 0.02 then return 'angle'; end
    local x, y, z = eye(v);
    x, y, z = x - ox, y - oy, z - oz;
    local squared = x * x + y * y + z * z;
    if squared > max_distance * max_distance then
        status.distance, status.reach = sqrt(squared), max_distance;
        return 'distance';
    end
end

local function multiply()
    for row = 0, 12, 4 do
        local a, b, c, d = view[row + 1], view[row + 2], view[row + 3], view[row + 4];
        for column = 1, 4 do
            matrix[row + column] = a * projection[column] + b * projection[column + 4] + c * projection[column + 8]
                + d * projection[column + 12];
        end
    end
end

-- Counts BeginScene calls between presents. In scene mode the scene_index-th one reads the matrices.
function camera.scene(backbuffer)
    if not active then return; end
    scene_count = scene_count + 1;
    if backbuffer and scene_count <= 8 then scene_flags = scene_flags + 2 ^ (scene_count - 1); end
    if status.capture == 'scene' and scene_count == scene_index then
        scene_read = read(view, projection);
        if scene_hook then scene_hook(); end
    end
end

function camera.set_scene_hook(fn) scene_hook = fn; end

-- This frame's camera, read at present or taken from the scene read before it, checked. One that fails leaves the
-- last good one in use for hold_ms, then nothing is placed until a good one comes back. screen_w and screen_h are
-- ImGui's DisplaySize, which every point maps to; ox, oy, oz is your own point in render space. Returns whether a
-- camera can be used.
function camera.frame(now, config, screen_w, screen_h, ox, oy, oz)
    active = true;
    status.capture, scene_index = camera.capture_point(config), config.scene_index or 2;
    status.width, status.height = screen_w, screen_h;
    local got;
    if status.capture == 'scene' then
        got = scene_read;
        if scene_count < scene_index then status.problem = 'The frame had too few scenes to read the camera.'; end
    else got = read(view, projection); end
    status.scenes, status.scene_flags = scene_count, scene_flags;
    scene_count, scene_flags, scene_read = 0, 0, false;
    status.read, status.failed = got, nil;
    if got then
        status.failed = projection_check(projection);
        if status.failed then got, status.problem = false, 'The projection is not the world camera.'; end
    end
    if got then
        status.failed = view_check(view, config.max_distance or 60, ox, oy, oz);
        if status.failed then got, status.problem = false, 'The view is not the world camera near you.'; end
    end
    if got then
        multiply();
        status.good_p22, good_at, status.problem = projection[6], now, nil;
        passes = passes + 1;
    else rejects = rejects + 1; end
    if not second_at or now - second_at >= 1 or now < second_at then
        status.passes, status.rejects, passes, rejects, second_at = passes, rejects, 0, 0, now;
    end
    status.valid = good_at ~= nil and now >= good_at and now - good_at <= (config.hold_ms or 250) / 1000
        and screen_w > 0 and screen_h > 0;
    return status.valid;
end

-- Overhead icons are off, so no BeginScene is counted.
function camera.idle() active = false; scene_count, scene_flags, scene_read = 0, 0, false; end

-- A frame whose blocks are hidden reads no camera. Its BeginScenes are dropped all the same, so the first frame
-- shown again reads its own camera, not the one from the start of the hidden stretch.
function camera.skip() scene_count, scene_flags, scene_read = 0, 0, false; end

-- Counts the next frame's BeginScenes though overhead icons are off, so a calibrate in scene mode reads the camera.
function camera.wake(config)
    if active then return; end
    active, scene_count, scene_flags, scene_read = true, 0, 0, false;
    status.capture, scene_index = camera.capture_point(config), config.scene_index or 2;
end

-- A render-space point on the ImGui screen: x, y, the clip-space w and the NDC depth (0 at the near plane, 1 at the
-- far one), or nothing when the point is behind the camera, too close to it, past the far plane or infinitely far
-- away (its depth is then not a number). w is the view depth in front of the camera with either handedness (view z
-- for a left-handed camera, minus view z for a right-handed one). NDC maps to DisplaySize, never to the viewport.
function camera.project(x, y, z)
    local m = matrix;
    local w = x * m[4] + y * m[8] + z * m[12] + m[16];
    if not (w > NEAR) then return nil; end
    local depth = (x * m[3] + y * m[7] + z * m[11] + m[15]) / w;
    if not (depth >= 0 and depth <= 1) then return nil; end
    return ((x * m[1] + y * m[5] + z * m[9] + m[13]) / w + 1) * 0.5 * status.width,
        (1 - (x * m[2] + y * m[6] + z * m[10] + m[14]) / w) * 0.5 * status.height, w, depth;
end

-- Screen pixels per yalm at view depth w.
function camera.pixels_per_yalm(w) return status.good_p22 * status.height * 0.5 / w; end

-- The camera the last read view puts in render space, checked or not, for calibrate.
function camera.eye() return eye(view); end

function camera.valid() return status.valid == true; end

-- A matrix value for the report, to 6 places, or in words when it isn't a number JSON can hold, so the report is
-- still saved.
local function plain(value)
    if value ~= value then return 'not a number'; end
    if value == math.huge then return 'infinity'; end
    if value == -math.huge then return '-infinity'; end
    if abs(value) >= 1e9 then return value; end
    return floor(value * 1e6 + 0.5) / 1e6;
end

local function number(value) return ('%.6g'):format(value); end

-- The check status.failed names, in words, with the values of the last read that failed it.
local function detail(failed)
    local p, v = projection, view;
    if failed == 'finite' then return 'one of its values is not a number or is ten million or more'; end
    if failed == 'shape' then
        return ('it is not a perspective (P34 %s and P44 %s, where a perspective has 1 or -1 and 0)')
            :format(number(p[12]), number(p[16]));
    end
    if failed == 'zeros' then
        for i = 1, #ZEROS do
            local slot = ZEROS[i];
            if not small(p[slot]) then
                return ('it is not a perspective (P%d%d is %s, where a perspective has 0)')
                    :format(floor((slot - 1) / 4) + 1, (slot - 1) % 4 + 1, number(p[slot]));
            end
        end
    end
    if failed == 'depth' then
        return ('its depth does not fit a %s camera (P33 %s and P43 %s with P34 %s, where P33 takes the sign of P34 and P43 is'
            .. ' below 0)'):format(p[12] > 0 and 'left-handed' or 'right-handed', number(p[11]), number(p[15]), number(p[12]));
    end
    if failed == 'field' then return ('its field of view is out of range (P22 %s, not from 0.3 to 6)'):format(number(p[6])); end
    if failed == 'aspect' then
        return ('its aspect is out of range (P11 %s with P22 %s, where P11 is above 0 and from 0.2 to 1.5 times P22)')
            :format(number(p[1]), number(p[6]));
    end
    if failed == 'column' then
        return ('its last column is not 0, 0, 0, 1 (%s, %s, %s, %s)'):format(number(v[4]), number(v[8]), number(v[12]),
            number(v[16]));
    end
    if failed == 'length' then
        for row = 1, 3 do
            local length = row_length(v, row * 4 - 3);
            if length < 0.9604 or length > 1.0404 then
                return ('its rows are not of length 1 (row %d is %s long)'):format(row, number(sqrt(length)));
            end
        end
    end
    if failed == 'angle' then
        for first = 1, 2 do
            for second = first + 1, 3 do
                local dot = row_dot(v, first * 4 - 3, second * 4 - 3);
                if abs(dot) >= 0.02 then
                    return ('its rows are not at right angles (rows %d and %d have a dot product of %s)')
                        :format(first, second, number(dot));
                end
            end
        end
    end
    if failed == 'distance' then return ('the camera is %.1f yalms from you, past %g'):format(status.distance, status.reach); end
end

-- What the camera did, for /vg report: the capture point, whether the last frame's camera could be used and if not
-- why, with the check it failed, the checks passed and failed in the last second, all 16 values of the last view
-- and projection read (row by row, _11 first) and the projection's P11, P22, P34 and P44 again, DisplaySize, the
-- viewport at the read and the BeginScene calls of the last frame (bit n set when call n drew to the back buffer).
-- While no frame reads the camera (overhead icons off, or none yet), the capture point is the one config names.
function camera.report(config)
    local problem, why = status.problem, status.failed and status.problem and detail(status.failed);
    if why then problem = problem:gsub('%.$', '') .. ': ' .. why .. '.'; end
    local capture = (active or not config) and status.capture or camera.capture_point(config);
    local out = { capture = capture, valid = status.valid, read = status.read, problem = problem,
        passes_per_second = status.passes, rejects_per_second = status.rejects, view = {}, projection = {},
        p11 = plain(projection[1]), p22 = plain(projection[6]), p34 = plain(projection[12]), p44 = plain(projection[16]),
        display = { width = status.width, height = status.height },
        viewport = status.viewport_width and { width = status.viewport_width, height = status.viewport_height } or nil,
        scenes = status.scenes, scene_backbuffer = status.scene_flags };
    for i = 1, 16 do out.view[i], out.projection[i] = plain(view[i]), plain(projection[i]); end
    if binding.device ~= nil and not reader then
        -- The back buffer the scene is drawn to, which can be larger than the display. It is released even when
        -- reading its size fails.
        local surface;
        local ok, width, height = pcall(function()
            local result;
            result, surface = binding.device:GetBackBuffer(0, 0);
            if result ~= 0 or surface == nil then return nil; end
            local described, desc = surface:GetDesc();
            if described ~= 0 or desc == nil then return nil; end
            return desc.Width, desc.Height;
        end);
        if surface ~= nil then pcall(function() surface:Release(); end); end
        if ok and width then out.backbuffer = { width = width, height = height }; end
    end
    return out;
end

if VANTAGE_TEST_MODE then
    -- reader(view, projection) fills both tables and returns true, in place of the device.
    function camera._set_reader(fn) reader = fn; end
    function camera._reset()
        good_at, second_at, passes, rejects, reader = nil, nil, 0, 0, nil;
        binding = { address = nil };
        active, scene_count, scene_flags, scene_read = false, 0, 0, false;
        status.valid, status.problem, status.good_p22, status.failed = false, 'Not read yet.', 0, nil;
    end
    camera._matrix = matrix;
end

return camera;
