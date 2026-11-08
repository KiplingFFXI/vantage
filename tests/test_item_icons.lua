local function setup(options)
    options = options or {}
    local state = { reads = {}, creates = 0, releases = 0, imports = 0, devices = 0 }
    MOCK.now = 0
    package.loaded['ui.item_icons'], package.loaded.d3d8 = nil, nil
    package.loaded.ffi = {
        new = function() return {} end,
        cast = function(_, value)
            if options.cast_error then error('Unable to cast') end
            return options.texture_id or value.id
        end,
        C = {
            S_OK = 0, D3DFMT_A8R8G8B8 = 21, D3DPOOL_MANAGED = 1, D3DX_DEFAULT = -1,
            D3DXCreateTextureFromFileInMemoryEx = function(...)
                local args = { ... }
                state.creates, state.arguments = state.creates + 1, args
                if not options.null_texture then
                    args[15][0] = { id = 1000 + state.creates, Release = function()
                        state.releases = state.releases + 1
                        if options.release_error then error('Unable to release') end
                    end }
                end
                if options.create_error then error('Unable to upload') end
                return options.create_failure and -1 or 0
            end,
        },
    }
    package.preload.d3d8 = function()
        state.imports = state.imports + 1
        if options.library_error then error('Library unavailable') end
        return { get_device = function()
            state.devices = state.devices + 1
            if not options.no_device then return 17 end
        end }
    end
    AshitaCore.GetResourceManager = function()
        if options.no_resources then return nil end
        return { GetItemById = function(_, id)
            state.reads[#state.reads + 1] = id
            if options.resource_error then error('Resource unavailable') end
            if options.missing then return nil end
            return { Bitmap = not options.no_bitmap and string.rep('x', options.short_bitmap and 1 or 0x980) or nil,
                ImageSize = options.image_size or 24 }
        end }
    end
    return require('ui.item_icons'), state
end

local icons, state = setup()
assert(icons.prepare() and icons.prepare() and state.imports == 1 and #state.reads == 0)
assert(icons.texture(16041) == 1001 and state.reads[1] == 16041, 'Recast items use their actual client item identity.')
local cached = true
for _ = 1, 1000 do cached = icons.texture(16041) == 1001 and cached end
assert(cached and #state.reads == 1 and state.creates == 1 and state.devices == 1,
    'Ready textures never repeat resource reads or uploads while drawing.')
assert(state.arguments[1] == 17 and state.arguments[3] == 24 and state.arguments[6] == 1
    and state.arguments[9] == 1 and state.arguments[12] == 0xFF000000,
    'Item pictures use managed single-mip textures and the native black color key.')
assert(icons.texture(65534) == 1002 and state.reads[2] == 65534)
for _, item in ipairs({ -1, 0, 65535, 16041.5, '16041', false, math.huge, -math.huge, 0 / 0 }) do
    assert(icons.texture(item) == nil)
end
assert(icons.texture(nil) == nil and #state.reads == 2, 'Invalid identities never reach client resources.')
icons.clear(); icons.clear()
assert(state.releases == 2, 'Repeated cleanup releases each texture once.')
assert(icons.texture(16041) == 1003 and state.devices == 2)
icons.clear()

for _, size in ipairs({ 0, -1, 1.5, 'invalid', math.huge, 0 / 0, 0x981 }) do
    icons, state = setup({ image_size = size })
    assert(icons.texture(16041) == nil and state.creates == 0 and state.devices == 0,
        'Malformed bitmap lengths never reach Direct3D.')
    icons.clear()
end
icons, state = setup({ image_size = 0x980 })
assert(icons.texture(16041) == 1001 and state.arguments[3] == 0x980)
icons.clear()

for _, options in ipairs({
    { resource_error = true }, { no_resources = true }, { missing = true }, { no_bitmap = true },
    { short_bitmap = true }, { no_device = true }, { null_texture = true },
    { create_error = true }, { create_failure = true }, { cast_error = true },
    { texture_id = 0 }, { texture_id = -1 }, { texture_id = 1.5 }, { texture_id = 0 / 0 },
    { texture_id = math.huge },
}) do
    icons, state = setup(options)
    assert(icons.texture(16041) == nil)
    local reads, creates, devices, releases = #state.reads, state.creates, state.devices, state.releases
    assert(releases == (options.null_texture and 0 or creates), 'Failed uploads release partial textures immediately.')
    local unavailable = true
    for frame = 1, 120 do
        MOCK.now = frame / 60
        unavailable = icons.texture(16041) == nil and unavailable
    end
    assert(unavailable and #state.reads == reads and state.creates == creates and state.devices == devices,
        'Unavailable images are not retried every frame.')
    MOCK.now = 29.999; assert(icons.texture(16041) == nil and state.creates == creates)
    for key in pairs(options) do options[key] = nil end
    MOCK.now = 30
    assert(icons.texture(16041) == 1000 + creates + 1, 'Transient errors recover after30 seconds.')
    icons.clear(); icons.clear()
    assert(state.releases == releases + 1, 'Recovered textures have one cleanup.')
end

local options = { library_error = true }
icons, state = setup(options)
assert(not icons.prepare() and icons.texture(16041) == nil and icons.texture(16042) == nil and state.imports == 1)
options.library_error, package.loaded.d3d8 = false, nil
MOCK.now = 30
assert(icons.texture(16041) == 1001 and state.imports == 2)
icons.clear()

icons, state = setup({ release_error = true })
icons.texture(16041); icons.texture(16042)
icons.clear(); icons.clear()
assert(state.releases == 2, 'A cleanup failure cannot skip other textures or release one twice.')

icons, state = setup()
local loads, released = {}, {}
icons._set_loader_for_tests(function(item)
    loads[item] = (loads[item] or 0) + 1
    return item + 100000, function() released[item] = (released[item] or 0) + 1 end
end)
for item = 1, 64 do assert(icons.texture(item) == item + 100000) end
assert(icons.texture(1) == 100001 and loads[1] == 1)
assert(icons.texture(65) == 100065 and released[2] == 1 and not released[1], 'Eviction keeps recently used item pictures.')
assert(icons.texture(2) == 100002 and loads[2] == 2 and released[3] == 1, 'The texture cache is bounded at64 items.')
assert(#state.reads == 0 and state.creates == 0, 'The offline loader never reaches game resources.')
icons.clear(); icons.clear()
local total = 0
for _, value in pairs(released) do total = total + value end
assert(total == 66, 'Evicted and retained textures are each released once.')

icons, state = setup()
local failed_loads, failed_releases = 0, 0
icons._set_loader_for_tests(function()
    failed_loads = failed_loads + 1
    return false, function() failed_releases = failed_releases + 1 end
end)
for item = 1, 65 do assert(icons.texture(item) == nil) end
assert(failed_loads == 65 and failed_releases == 65, 'Invalid loader results still release their resource handles.')
icons.texture(65)
assert(failed_loads == 65, 'A retained failure obeys its retry delay.')
icons.texture(1)
assert(failed_loads == 66, 'Failure entries obey the same cache bound as successful images.')
icons.clear(); icons.clear()
assert(failed_releases == 66, 'Failure cleanup is not repeated during clear.')
