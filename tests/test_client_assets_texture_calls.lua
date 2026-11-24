-- The two texture uploads in ui/client_assets.lua share one D3DX call: a picture is a smoothed square with the mip
-- levels asked for, a client texture is width by height with one level and no smoothing, and each says its own line
-- when it can't be made.
local state = { calls = {}, fail = false, device = 17, releases = 0 };
local saved_ffi, saved_d3d8 = package.loaded.ffi, package.loaded.d3d8;
package.loaded['ui.client_assets'], package.loaded.d3d8 = nil, nil;
package.loaded.ffi = {
    os = 'Test',
    new = function() return {}; end,
    cast = function(_, value) return value.id; end,
    C = {
        S_OK = 0, D3DFMT_A8R8G8B8 = 21, D3DPOOL_MANAGED = 1,
        D3DXCreateTextureFromFileInMemoryEx = function(...)
            local args = { ... };
            state.calls[#state.calls + 1] = args;
            if state.fail then return -1; end
            args[15][0] = { id = 500 + #state.calls, Release = function() state.releases = state.releases + 1; end };
            return 0;
        end,
    },
};
package.preload.d3d8 = function() return { get_device = function() return state.device; end }; end;
local assets = require('ui.client_assets');

-- The addon's own platform, as the game uses it, found through upload_picture.
local native;
for index = 1, 20 do
    local name, value = debug.getupvalue(assets.upload_picture, index);
    if name == nil then break; end
    if name == 'native' then native = value; end
end
assert(type(native) == 'function', 'upload_picture reaches the addon\'s own platform.');
local api = native();

local function shape(args)
    local out = {};
    for index = 3, 14 do out[#out + 1] = tostring(args[index]); end
    return table.concat(out, ' ');
end

local picture, why = api.upload_picture('PNGDATA', 64, 0, 'icon');
assert(picture and picture.id == 501 and why == nil, 'A picture is made into a texture.');
assert(state.calls[1][1] == 17 and state.calls[1][2] == 'PNGDATA', 'on the game\'s device, from its bytes,');
assert(shape(state.calls[1]) == '7 64 64 0 0 21 1 4 4 0 nil nil', 'as a smoothed square with the levels asked for: ' .. shape(state.calls[1]));
local texture = api.upload('DDSDATA!', 256, 128, 'font');
assert(texture and texture.id == 502, 'A client texture is made too.');
assert(shape(state.calls[2]) == '8 256 128 1 0 21 1 1 1 0 nil nil', 'width by height, one level, not smoothed: ' .. shape(state.calls[2]));
picture.release(); picture.release(); texture.release();
assert(state.releases == 2, 'Each texture is let go once.');

state.fail = true;
local _, picture_why = api.upload_picture('PNGDATA', 32, 1, 'icon');
local _, texture_why = api.upload('DDSDATA!', 256, 128, 'font');
assert(picture_why == 'The picture could not be made into a texture.', 'A picture says its own line: ' .. tostring(picture_why));
assert(texture_why == 'The client texture could not be uploaded.', 'and a client texture its own: ' .. tostring(texture_why));
state.fail, state.device = false, nil;
_, picture_why = api.upload_picture('PNGDATA', 32, 1, 'icon');
_, texture_why = api.upload('DDSDATA!', 256, 128, 'font');
assert(picture_why == 'The display device is not ready.' and texture_why == picture_why, 'Without a device both say so.');
assert(#state.calls == 4, 'and neither asks D3DX.');

package.loaded['ui.client_assets'], package.loaded.d3d8, package.preload.d3d8 = nil, saved_d3d8, nil;
package.loaded.ffi = saved_ffi;
