-- ui.client_bitmap: the one loader that turns client item and status pictures into textures. Each icon module
-- keeps its own loader, so devices, retries and caches stay apart; item and status bitmaps keep their own limits.
local state;
local function fresh(options)
    options = options or {};
    state = { creates = 0, releases = 0, imports = 0, devices = 0 };
    package.loaded.d3d8 = nil;
    package.loaded.ffi = {
        NULL = 'NULL',
        new = function() return {}; end,
        cast = function(_, value) if options.cast_error then error('Unable to cast'); end; return value.id; end,
        C = {
            S_OK = 0, D3DFMT_A8R8G8B8 = 21, D3DPOOL_MANAGED = 1, D3DX_DEFAULT = -1,
            D3DXCreateTextureFromFileInMemoryEx = function(...)
                local args = { ... };
                state.creates, state.arguments = state.creates + 1, args;
                args[15][0] = { id = 1000 + state.creates, Release = function() state.releases = state.releases + 1; end };
                if options.create_error then error('Unable to upload'); end
                return options.create_failure and -1 or 0;
            end,
        },
    };
    package.preload.d3d8 = function()
        state.imports = state.imports + 1;
        if options.library_error then error('Library unavailable'); end
        return { get_device = function() state.devices = state.devices + 1; if not options.no_device then return 17; end; end };
    end;
end

local bitmap = require('ui.client_bitmap');
fresh();
local items, status = bitmap.loader(0x980), bitmap.loader(0x156A);
assert(items.prepare() and status.prepare() and state.imports == 1, 'Both loaders use the one d3d8 library.');
local id, release = items.load({ ImageSize = 0x980, Bitmap = string.rep('x', 0x980) });
assert(id == 1001 and type(release) == 'function' and state.arguments[1] == 17 and state.arguments[3] == 0x980
    and state.arguments[12] == 0xFF000000, 'An item picture of the largest size uploads.');
release(); release();
assert(state.releases == 1, 'A texture is released once.');
assert(items.load({ ImageSize = 0x981, Bitmap = string.rep('x', 0x981) }) == false and state.creates == 1,
    'An item bitmap over 0x980 bytes is refused before the upload.');
assert(status.load({ ImageSize = 0x156A, Bitmap = string.rep('x', 0x156A) }) == 1002, 'A status bitmap may hold 0x156A bytes.');
assert(status.load({ ImageSize = 0x156B, Bitmap = string.rep('x', 0x156B) }) == false and state.creates == 2);
for _, entry in ipairs({ { ImageSize = 0, Bitmap = 'x' }, { ImageSize = 1.5, Bitmap = 'xx' }, { ImageSize = 'big', Bitmap = 'x' },
    { ImageSize = 24 }, { ImageSize = 24, Bitmap = 'short' }, { ImageSize = 4, Bitmap = 'NULL' } }) do
    assert(items.load(entry) == false and status.load(entry) == false, 'A missing, short or NULL bitmap is refused.');
end
assert(items.load(nil) == false and state.creates == 2 and state.devices == 2, 'No device is asked for a refused bitmap.');

-- The device is kept per loader; a reset drops only that loader's device and library.
status.reset();
assert(status.prepare() and state.imports == 1);
assert(status.load({ ImageSize = 24, Bitmap = string.rep('x', 24) }) == 1003 and state.devices == 3,
    'A reset loader asks for the device again.');
assert(items.load({ ImageSize = 24, Bitmap = string.rep('x', 24) }) == 1004 and state.devices == 3,
    'Another loader keeps its device.');

fresh({ create_failure = true });
local failing = bitmap.loader(0x980);
assert(failing.prepare() and failing.load({ ImageSize = 24, Bitmap = string.rep('x', 24) }) == false and state.releases == 1,
    'A failed upload releases what it made.');
fresh({ create_error = true });
failing = bitmap.loader(0x980);
assert(failing.prepare() and failing.load({ ImageSize = 24, Bitmap = string.rep('x', 24) }) == false and state.releases == 1,
    'An upload that raises releases what it made.');
fresh({ cast_error = true });
failing = bitmap.loader(0x980);
assert(failing.prepare() and failing.load({ ImageSize = 24, Bitmap = string.rep('x', 24) }) == false and state.releases == 1);
fresh({ no_device = true });
failing = bitmap.loader(0x980);
assert(failing.prepare() and failing.load({ ImageSize = 24, Bitmap = string.rep('x', 24) }) == false and state.creates == 0);
fresh({ library_error = true });
failing = bitmap.loader(0x980);
-- Attempts are counted at require itself: once d3d8 fails to load, Lua answers a second require from its loaded
-- table without calling the loader, so the loader's own count can't tell a retry apart.
local attempts, real_require, real_clock = 0, require, os.clock;
require = function(name, ...) if name == 'd3d8' then attempts = attempts + 1; end; return real_require(name, ...); end;
local clock = real_clock();
os.clock = function() return clock; end;
assert(not failing.prepare() and not failing.prepare() and attempts == 1 and state.imports == 1,
    'A missing library is retried later, not each call.');
clock = clock + 31;
assert(not failing.prepare() and attempts == 2, 'It is tried again after 30 seconds.');
require, os.clock = real_require, real_clock;

-- The client status icons load through it with the status limit.
fresh();
package.loaded['ui.icons'] = nil;
local requested;
AshitaCore.GetResourceManager = function()
    return { GetStatusIconByIndex = function(_, index)
        requested = index;
        return { ImageSize = index == 33 and 0x156A or 0x156B, Bitmap = string.rep('x', 0x156B) };
    end };
end;
local icons = require('ui.icons');
assert(icons.status(33, 'Client') == 1001 and requested == 33, 'A status icon at the status limit loads.');
assert(icons.status(34, 'Client') == nil and requested == 34 and state.creates == 1, 'A larger status bitmap is refused.');
icons.clear();
assert(state.releases == 1);
