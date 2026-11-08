-- The overhead camera reads the game's Direct3D device through Ashita's libs/d3d8: GetTransform for the view (2) and
-- projection (3) through the device's own vtable into buffers it made once, checked by its result; the device is cast
-- again only when the game's device changes; present or scene mode reads at its own point; the report gives the back
-- buffer and viewport beside DisplaySize. The device here is the real d3d8 types over Lua callbacks.
local ffi = package.preload.ffi('ffi');
local mock_ffi = package.loaded.ffi;
package.loaded.ffi = ffi;
local d3d8 = require('d3d8');
local camera = require('core.camera');
local config = require('ui.overhead_defaults').make().camera;

local xs, ys, q = 1.7 * 9 / 16, 1.7, 200 / 199.5;
local matrices = { [2] = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }, [3] = { xs, 0, 0, 0, 0, ys, 0, 0, 0, 0, q, 1, 0, 0, -0.5 * q, 0 } };
local calls, failing, released = {}, {}, 0;
local function device(name)
    local vtable = ffi.new('IDirect3DDevice8Vtbl');
    vtable.GetTransform = ffi.cast('HRESULT (__stdcall *)(IDirect3DDevice8*, D3DTRANSFORMSTATETYPE, D3DMATRIX*)', function(_, state, out)
        state = tonumber(state);
        calls[#calls + 1] = name .. ':' .. state;
        if failing[state] then return -2147467259; end
        local floats, source = ffi.cast('float*', out), matrices[state];
        for i = 0, 15 do floats[i] = source and source[i + 1] or 0; end
        return 0;
    end);
    vtable.GetViewport = ffi.cast('HRESULT (__stdcall *)(IDirect3DDevice8*, D3DVIEWPORT8*)', function(_, port)
        port.X, port.Y, port.Width, port.Height, port.MinZ, port.MaxZ = 0, 0, 3840, 2160, 0, 1;
        return 0;
    end);
    local surface_table = ffi.new('IDirect3DSurface8Vtbl');
    surface_table.GetDesc = ffi.cast('HRESULT (__stdcall *)(IDirect3DSurface8*, D3DSURFACE_DESC*)', function(_, desc)
        desc.Width, desc.Height = 3840, 2160;
        return 0;
    end);
    surface_table.Release = ffi.cast('ULONG (__stdcall *)(IDirect3DSurface8*)', function() released = released + 1; return 0; end);
    local surface = ffi.new('IDirect3DSurface8[1]');
    surface[0].lpVtbl = surface_table;
    vtable.GetBackBuffer = ffi.cast('HRESULT (__stdcall *)(IDirect3DDevice8*, UINT, D3DBACKBUFFER_TYPE, IDirect3DSurface8**)',
        function(_, _, _, out) out[0] = surface; return 0; end);
    local cell = ffi.new('IDirect3DDevice8[1]');
    cell[0].lpVtbl = vtable;
    return { cell = cell, vtable = vtable, surface = surface, surface_table = surface_table,
        address = tonumber(ffi.cast('uintptr_t', cell)) };
end
local first, second = device('first'), device('second');
local current = first;
AshitaCore.GetDirect3DDevice = function() return current.address; end;

local now = 10;
local function frame(mode)
    now = now + 1 / 60;
    config.capture = mode or 'present';
    return camera.frame(now, config, 1920, 1080, 0, 0, 0);
end
assert(frame(), 'The device\'s camera is used.');
assert(table.concat(calls, ' ') == 'first:2 first:3', 'View then projection through GetTransform: ' .. table.concat(calls, ' '));
-- The middle of a 3840x2160 scene is the middle of the 1920x1080 display.
local sx, sy, w = camera.project(0, 0, 10);
assert(math.abs(sx - 960) < 1e-6 and math.abs(sy - 540) < 1e-6 and math.abs(w - 10) < 1e-6, 'DisplaySize, not the viewport.');
sx, sy = camera.project(1, 1, 10);
assert(math.abs(sx - (1 + xs / 10) * 960) < 1e-4 and math.abs(sy - (1 - ys / 10) * 540) < 1e-4,
    'A point off the middle keeps its place on the display, not twice its offset.');
local report = camera.report();
assert(report.capture == 'present' and report.valid and report.viewport.width == 3840 and report.viewport.height == 2160
    and report.backbuffer.width == 3840 and report.backbuffer.height == 2160 and report.display.width == 1920
    and report.display.height == 1080, 'The report has DisplaySize, the viewport and the back buffer.');
assert(released == 1, 'The back buffer is released after its size is read.');
-- A GetDesc that throws still releases the back buffer, and the report goes out without its size.
local new = ffi.new;
ffi.new = function(ct, ...)
    if ct == 'D3DSURFACE_DESC[1]' then error('No surface description.'); end
    return new(ct, ...);
end;
report = camera.report();
ffi.new = new;
assert(released == 2 and report.backbuffer == nil and report.display.width == 1920,
    'The back buffer is released when reading its size fails.');
assert(math.abs(report.p22 - 1.7) < 1e-6 and math.abs(report.p34 - 1) < 1e-6 and report.p44 == 0);

-- A failed GetTransform rejects the frame; the camera is held, then not used.
calls, failing[3] = {}, true;
assert(frame(), 'Held after a failed read.');
assert(camera.report().problem == 'The graphics device gave no camera.');
now = now + 1;
assert(not frame(), 'A camera that can\'t be read is not used past the hold.');
failing[3] = nil;
assert(frame());

-- The same device is cast once; a new device is cast again and read from then on.
calls = {};
for _ = 1, 3 do frame(); end
assert(table.concat(calls, ' ') == 'first:2 first:3 first:2 first:3 first:2 first:3');
current, calls = second, {};
assert(frame() and table.concat(calls, ' ') == 'second:2 second:3', 'A new device is read: ' .. table.concat(calls, ' '));
-- No device: not used, and says why.
current = { address = 0 };
now = now + 1;
assert(not frame() and camera.report().problem == 'The graphics device is not available.');
current = second;

-- Scene mode reads at the second BeginScene of the frame, not at present; the report counts the scenes and marks the
-- ones drawn to the back buffer.
assert(frame());
-- The mode takes at the next present; that frame has no scene read yet, so it holds the last camera.
assert(frame('scene'), 'Held while the mode changes.');
calls = {};
camera.scene(false);
assert(#calls == 0, 'Not at the first BeginScene.');
camera.scene(true);
assert(table.concat(calls, ' ') == 'second:2 second:3', 'At the second.');
camera.scene(true);
assert(#calls == 2, 'Only once a frame.');
assert(frame('scene') and #calls == 2, 'Present reads nothing in scene mode.');
report = camera.report();
assert(report.capture == 'scene' and report.scenes == 3 and report.scene_backbuffer == 6, 'Three scenes, the 2nd and 3rd to the back buffer.');
-- A frame whose second scene never came holds the last camera, then hides.
camera.scene(true);
assert(frame('scene'), 'Held.');
now = now + 1;
camera.scene(true);
assert(not frame('scene'), 'One scene a frame never reads in scene mode with scene_index 2.');
assert(camera.report().problem == 'The frame had too few scenes to read the camera.', tostring(camera.report().problem));
config.scene_index = 1;
frame('scene');
camera.scene(true);
assert(frame('scene'), 'With scene_index 1 the first one reads.');
-- Idle: overhead icons off count and read nothing.
camera.idle();
calls = {};
camera.scene(true); camera.scene(true);
assert(#calls == 0, 'No reads while idle.');
-- Woken for a calibrate, the next frame's scenes count and read again in the woken mode.
camera.wake({ capture = 'scene', scene_index = 2 });
camera.scene(false); camera.scene(true);
assert(table.concat(calls, ' ') == 'second:2 second:3', 'Woken, the second scene reads: ' .. table.concat(calls, ' '));
camera.idle();
assert(camera.capture_point({ capture = 'scene' }) == 'scene' and camera.capture_point({ capture = 'other' }) == 'present'
    and camera.capture_point(nil) == 'present', 'The capture point is chosen in one place.');
package.loaded.ffi = mock_ffi;
