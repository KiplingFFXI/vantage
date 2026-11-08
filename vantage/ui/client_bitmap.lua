-- Textures made from the pictures the client keeps in its resources (item and status icons). Each user makes its
-- own loader, so its caches, device and retry stay its own; limit is the most bytes that resource's bitmap owns.
local bitmap = {};

function bitmap.loader(limit)
    local loader = {};
    local library, device, retry_at;

    function loader.prepare()
        if library == nil or library == false and os.clock() >= (retry_at or 0) then
            local ok, value = pcall(require, 'd3d8');
            library = ok and value or false;
            retry_at = not library and os.clock() + 30 or nil;
        end
        return library and true or false;
    end

    -- The texture id and a function that releases it, for a resource entry with ImageSize and Bitmap; false
    -- when there is none. Call prepare() first.
    function loader.load(entry)
        local size = entry and tonumber(entry.ImageSize);
        if not entry or not size or size ~= math.floor(size) or size <= 0 or size > limit then return false; end
        local picture = entry.Bitmap;
        if picture == nil or type(picture) == 'string' and #picture < size then return false; end
        local ffi = require('ffi');
        if picture == ffi.NULL then return false; end
        device = device or library.get_device();
        if not device or device == ffi.NULL then device = nil; return false; end
        local out = ffi.new('IDirect3DTexture8*[1]');
        local ok, result = pcall(ffi.C.D3DXCreateTextureFromFileInMemoryEx, device, picture, size,
            0xFFFFFFFF, 0xFFFFFFFF, 1, 0, ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED,
            ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT, 0xFF000000, nil, nil, out);
        local texture = out[0];
        if not ok or result ~= ffi.C.S_OK or texture == nil or texture == ffi.NULL then
            if texture ~= nil and texture ~= ffi.NULL then pcall(function() texture:Release(); end); end
            return false;
        end
        local function release()
            local retained = texture;
            texture = nil;
            if retained ~= nil then retained:Release(); end
        end
        local converted, value = pcall(function() return tonumber(ffi.cast('uintptr_t', texture)); end);
        if not converted then pcall(release); return false; end
        return value, release;
    end

    -- Whether prepare() has run since the last reset.
    function loader.ready()
        return library ~= nil;
    end

    function loader.reset()
        library, device, retry_at = nil, nil, nil;
    end

    return loader;
end

return bitmap;
