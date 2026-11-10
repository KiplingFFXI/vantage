local assets = {}
local MAX_FILE, MAX_CHUNKS, MAX_TEXTURE = 16 * 1024 * 1024, 4096, 4 * 1024 * 1024
local aliases = { newtex = 'menu    newtex  ', hfr1 = 'menu    hfr1    ', corner = 'menu    corner  ',
    vfr1 = 'menu    vfr1    ', moji = 'font    moji    ',
    gauge = 'menu    gauge   ', acre = 'menu    acre    ' }
local kinds = { 'window', 'window2', 'window3', 'window4', 'window5', 'window6', 'window7', 'window8',
    'original_font', 'xiview_font' }
-- The sizes of the stock window frames' square pieces, which the skin's fixed source rectangles are made for
-- (ui/client_skin.lua).
local WINDOW_SIZES = { newtex = 128, hfr1 = 32, corner = 32, vfr1 = 32 }
local state, platform, native_platform, generation = {}, nil, nil, 0
local ready, retry_at = false, 0
-- Each kind's file and textures once the paths are known (setup), and the file readers of the stock font and of
-- XI View's art, let go once they are done.
local plan, stock_reader, view_reader
-- The game's folder and XI View's font file with where it was found, worked out once for the art, the status icons
-- and the action icons (art_roots).
local roots
-- The window frame the settings draw with, which its warmup step loads (want_window). Any other loads at its first use.
local wanted_window = 'window'
local icon_sources
local action_sources
local action_dds
-- Status records are this long, and ids run from 0 to 1023.
local ICON_STRIDE, ICON_RECORDS = 0x1800, 1024
-- The bitmap face draws only moji's first two rows of 16-pixel glyphs, so the device gets a 64-row texture (moji_upload).
local MOJI_ROWS = 64

-- Window choices are one-based in the addon. Invalid or omitted choices use type 1.
local function window_key(value)
    if type(value) ~= 'number' or value < 1 or value > 8 or value ~= math.floor(value) then value = 1 end
    return value == 1 and 'window' or 'window' .. value
end

local load_deferred

local function asset_group(kind, window_type)
    if kind == 'window' then kind = window_key(window_type) end
    local held = state[kind]
    if held and held.deferred then load_deferred() end
    return held
end

local function u16(data, at)
    local a, b = data:byte(at, at + 1)
    if not b then return nil end
    return a + b * 256
end

local function u32(data, at)
    local lo, hi = u16(data, at), u16(data, at + 2)
    return hi and lo + hi * 65536 or nil
end

local function le32(value)
    return string.char(value % 256, math.floor(value / 256) % 256, math.floor(value / 65536) % 256,
        math.floor(value / 16777216) % 256)
end

-- Every status icon reaches the device as a 32 px A8R8G8B8 DDS, so its header is made once.
local ICON_HEADER = 'DDS ' .. le32(124) .. le32(0x100F) .. le32(32) .. le32(32) .. le32(128)
    .. le32(0) .. le32(1) .. string.rep('\0', 44) .. le32(32) .. le32(65) .. le32(0) .. le32(32)
    .. le32(0x00FF0000) .. le32(0x0000FF00) .. le32(0x000000FF) .. le32(0xFF000000)
    .. le32(0x1000) .. string.rep('\0', 16)

local function name_set(names)
    local result = {}
    for _, name in ipairs(names or {}) do result[aliases[name] or name] = true end
    return result
end

-- A texture's last word, such as moji, for timing stage names.
local function short(name)
    return type(name) == 'string' and name:match('(%S+)%s*$') or 'texture'
end

-- What of moji goes to the device: block rows 0-8 (rows 0-35) as they are, so a glyph's bottom edge filters against
-- row 32 just as it does in the whole texture, rows 36-59 blank, and the texture's own last block row as rows 60-63, so
-- a top glyph's top edge reads the same texel whether the sampler wraps (row 2047 of the whole texture, row 63 of this
-- one) or clamps. The pixels Lua keeps stay whole for the faces and the countdown atlas.
local function moji_upload(raw)
    local row = raw.width / 4 * 16
    if raw.format ~= 'DXT3' or raw.height <= MOJI_ROWS or raw.width % 4 ~= 0 or raw.height % 4 ~= 0
        or type(raw.dds) ~= 'string' or #raw.dds ~= 128 + row * raw.height / 4 then
        return raw.dds, raw.height
    end
    local header = raw.dds:sub(1, 12) .. le32(MOJI_ROWS) .. raw.dds:sub(17, 20) .. le32(row * MOJI_ROWS / 4)
        .. raw.dds:sub(25, 128)
    return header .. raw.dds:sub(129, 128 + row * 9) .. string.rep('\0', row * 6) .. raw.dds:sub(-row), MOJI_ROWS
end

local function make_dds(payload)
    if #payload < 69 or payload:byte(1) ~= 0xA1 or u32(payload, 18) ~= 40 then return nil, 'Unsupported texture header.' end
    local width, height = u32(payload, 22), u32(payload, 26)
    if not width or not height or width < 1 or height < 1 or width > 2048 or height > 2048 then
        return nil, 'Texture dimensions are outside the supported range.'
    end
    local offset, fourcc
    for _, at in ipairs({ 58, 62 }) do
        local tag = payload:sub(at, at + 3)
        if tag == '1TXD' or tag == '3TXD' or tag == '5TXD' then offset, fourcc = at, tag:reverse(); break end
    end
    if not offset then return nil, 'Unsupported texture compression.' end
    local bytes = u32(payload, offset + 4)
    local expected = math.ceil(width / 4) * math.ceil(height / 4) * (fourcc == 'DXT1' and 8 or 16)
    if not bytes or bytes ~= expected or bytes > MAX_TEXTURE or offset + 11 + bytes > #payload then
        return nil, 'The compressed texture is incomplete or has an invalid size.'
    end
    local dds = 'DDS ' .. le32(124) .. le32(0x81007) .. le32(height) .. le32(width) .. le32(bytes)
        .. le32(0) .. le32(1) .. string.rep('\0', 44) .. le32(32) .. le32(4) .. fourcc
        .. string.rep('\0', 20) .. le32(0x1000) .. string.rep('\0', 16)
    return { width = width, height = height, format = fourcc,
        dds = dds .. payload:sub(offset + 12, offset + 11 + bytes) }
end

-- Only selected texture and layout payloads leave the bounded container parser. A selected texture that can't be
-- used, or is in the file twice, is left out with its reason in errors, so one odd texture never costs the others;
-- whoever asked decides whether it was needed.
function assets.parse(data, texture_names, layout_names)
    if type(data) ~= 'string' or #data < 16 or #data > MAX_FILE then return nil, 'Invalid or oversized DAT file.' end
    local wanted, wanted_layouts = texture_names == true and true or name_set(texture_names), name_set(layout_names)
    local result, at, count, seen = { textures = {}, layouts = {}, errors = {} }, 1, 0, {}
    while at <= #data do
        count = count + 1
        if count > MAX_CHUNKS or at + 15 > #data then return nil, 'Invalid DAT chunk count or header.' end
        local packed = u32(data, at + 4)
        local kind, size = packed % 128, math.floor(packed / 128) % 524288 * 16
        if size < 16 or at + size - 1 > #data then return nil, 'A DAT chunk extends beyond the file.' end
        if kind == 0x20 and size >= 33 then
            local name = data:sub(at + 17, at + 32)
            if wanted == true or wanted[name] then
                if seen[name] then
                    result.textures[name], result.errors[name] = nil, 'Duplicate selected texture in the DAT file.'
                else
                    seen[name] = true
                    local texture, why = make_dds(data:sub(at + 16, at + size - 1))
                    if texture then
                        texture.name = name
                        result.textures[name] = texture
                    else
                        result.errors[name] = why
                    end
                end
            end
        elseif kind == 0x31 and size >= 32 then
            local name = data:sub(at + 16, at + 31)
            if wanted_layouts[name] then
                if result.layouts[name] then return nil, 'Duplicate selected layout in the DAT file.' end
                result.layouts[name] = data:sub(at + 16, at + size - 1)
            end
        end
        at = at + size
    end
    return result
end

-- pcall(index_of, object, key) guards a lookup without making a closure for it.
local function index_of(object, key) return object[key] end

local function call(object, method, ...)
    if not object then return nil end
    local ok, fn = pcall(index_of, object, method)
    if not ok or type(fn) ~= 'function' then return nil end
    local success, value = pcall(fn, object, ...)
    if success then return value end
end

local function path(value)
    if type(value) ~= 'string' or value == '' or #value > 4096 or value:find('\0', 1, true) then return nil end
    return value:gsub('\\', '/'):gsub('/+$', '')
end

local function join(root, relative)
    root = path(root)
    return root and root .. '/' .. relative or nil
end

local function absolute(value)
    return value and (value:match('^%a:[/\\]') or value:match('^[/\\][/\\]') or value:sub(1, 1) == '/')
end

-- An upload this slow also gets a stage of its own, named for its texture.
local SLOW_UPLOAD = 5

local function measure_native(api)
    local ok, performance = pcall(require, 'core.performance')
    if not ok or type(performance) ~= 'table' or type(performance.now) ~= 'function'
        or type(performance.record) ~= 'function' then return api end
    local function finish(started, stage, label, success, ...)
        performance.record(stage, started)
        if type(label) == 'string' and performance.now() - started >= SLOW_UPLOAD then
            performance.record(stage .. '.' .. label, started)
        end
        if not success then error((...), 0) end
        return ...
    end
    -- An upload's fourth argument names its texture.
    local function wrap(stage, callback, named)
        return function(...)
            local started = performance.now()
            return finish(started, stage, named and select(4, ...) or nil, pcall(callback, ...))
        end
    end
    api.read = wrap('assets.read', api.read)
    api.upload = wrap('assets.upload', api.upload, true)
    return api
end

local function native()
    if native_platform then return native_platform end
    local api = {}
    native_platform = api
    local ok, ffi = pcall(require, 'ffi')
    local kernel
    if ok and ffi.os == 'Windows' then
        for _, declaration in ipairs({
            'void* __stdcall GetModuleHandleW(const unsigned short*);',
            'unsigned long __stdcall GetModuleFileNameW(void*, unsigned short*, unsigned long);',
            'int __stdcall MultiByteToWideChar(unsigned int, unsigned long, const char*, int, unsigned short*, int);',
            'int __stdcall WideCharToMultiByte(unsigned int, unsigned long, const unsigned short*, int, char*, int, const char*, int*);',
            'void* __stdcall CreateFileW(const unsigned short*, unsigned long, unsigned long, void*, unsigned long, unsigned long, void*);',
            'int __stdcall GetFileSizeEx(void*, int64_t*);',
            'int __stdcall GetFileTime(void*, void*, void*, void*);',
            'int __stdcall ReadFile(void*, void*, unsigned long, unsigned long*, void*);',
            'int __stdcall CloseHandle(void*);',
        }) do pcall(ffi.cdef, declaration) end
        local loaded, value = pcall(ffi.load, 'kernel32')
        if loaded then kernel = value end
    end
    -- A path is UTF-8 when it is valid UTF-8, else in the system's ANSI code page, as a folder name with letters
    -- outside ASCII can reach here either way.
    local function wide(text)
        if not kernel or not path(text) then return nil end
        for _, page in ipairs({ 65001, 0 }) do
            local flags = page == 65001 and 8 or 0
            local count = kernel.MultiByteToWideChar(page, flags, text, #text, nil, 0)
            if count > 0 and count <= 4096 then
                local out = ffi.new('unsigned short[?]', count + 1)
                if kernel.MultiByteToWideChar(page, flags, text, #text, out, count) == count then return out end
            end
        end
    end
    local function module_root()
        if not kernel then return nil end
        local module = kernel.GetModuleHandleW(wide('FFXiMain.dll'))
        if module == nil or module == ffi.NULL then return nil end
        local buffer = ffi.new('unsigned short[4096]')
        local count = kernel.GetModuleFileNameW(module, buffer, 4096)
        if count == 0 or count >= 4096 then return nil end
        local length = kernel.WideCharToMultiByte(65001, 0, buffer, count, nil, 0, nil, nil)
        if length <= 0 or length > 16384 then return nil end
        local utf8 = ffi.new('char[?]', length)
        if kernel.WideCharToMultiByte(65001, 0, buffer, count, utf8, length, nil, nil) ~= length then return nil end
        local filename = path(ffi.string(utf8, length))
        return filename and filename:match('^(.*)/[^/]+$') or nil
    end
    api.game_root = function()
        local success, root = pcall(module_root)
        if success and root then return root end
        local resources = call(AshitaCore, 'GetResourceManager')
        local dat = path(call(resources, 'GetFilePath', 14))
        if dat then
            local ending = dat:lower():match('()/rom/%d+/%d+%.dat$')
            if ending then return dat:sub(1, ending - 1) end
        end
        local configuration = call(AshitaCore, 'GetConfigurationManager')
        local lang = tonumber(call(configuration, 'GetInt32', 'boot', 'ashita.language', 'playonline', 2)) or 2
        if lang > 4 or lang < 0 then lang = 2 elseif lang == 4 then lang = 3 end
        local lookup = ashita and ashita.fs and (ashita.fs.get_install_dir or ashita.fs.get_install_directory)
        if type(lookup) == 'function' then
            local found, value = pcall(lookup, lang, 1)
            if found then return path(value) end
        end
    end
    api.ashita_root = function() return path(call(AshitaCore, 'GetInstallPath')) end
    -- With an overlay on, CreateFileA and fopen_s are redirected. CreateFileW isn't, so this opens the exact path given.
    local function open(name)
        local handle = kernel.CreateFileW(name, 0x80000000, 7, nil, 3, 0x80, nil)
        if handle == nil or handle == ffi.NULL or tonumber(ffi.cast('intptr_t', handle)) == -1 then return nil end
        return handle
    end
    -- A file's size and last write time, from the same kind of handle a read opens.
    api.stat = function(filename)
        local name = kernel and wide(filename)
        local handle = name and open(name)
        if not handle then return nil end
        local success, size, written = pcall(function()
            local length, stamp = ffi.new('int64_t[1]'), ffi.new('unsigned long[2]')
            if kernel.GetFileSizeEx(handle, length) == 0 then return nil end
            if kernel.GetFileTime(handle, nil, nil, stamp) == 0 then return nil end
            return tonumber(length[0]), ('%08x%08x'):format(tonumber(stamp[1]), tonumber(stamp[0]))
        end)
        kernel.CloseHandle(handle)
        if success then return size, written end
    end
    api.read = function(filename, limit)
        if not kernel then return nil, 'Direct Windows file reads are unavailable.' end
        local name = wide(filename)
        if not name then return nil, 'The asset path is unavailable or could not be converted.' end
        local handle = open(name)
        if not handle then return nil, 'The asset file could not be opened.' end
        local success, bytes, why = pcall(function()
            local length = ffi.new('int64_t[1]')
            if kernel.GetFileSizeEx(handle, length) == 0 then return nil, 'The asset size could not be read.' end
            local size = tonumber(length[0])
            if size < 1 or size > limit then return nil, 'The asset file is empty or exceeds the size limit.' end
            local buffer, actual = ffi.new('uint8_t[?]', size), ffi.new('unsigned long[1]')
            if kernel.ReadFile(handle, buffer, size, actual, nil) == 0 or tonumber(actual[0]) ~= size then
                return nil, 'The asset file could not be read completely.'
            end
            return ffi.string(buffer, size)
        end)
        kernel.CloseHandle(handle)
        if not success then return nil, 'The asset read failed.' end
        return bytes, why
    end
    api.upload = function(dds, width, height)
        if not ok then return nil, 'The texture interface is unavailable.' end
        local loaded, d3d = pcall(require, 'd3d8')
        if not loaded then return nil, 'The texture interface is unavailable.' end
        local device = d3d.get_device()
        if device == nil or device == ffi.NULL then return nil, 'The display device is not ready.' end
        local out = ffi.new('IDirect3DTexture8*[1]')
        local result = ffi.C.D3DXCreateTextureFromFileInMemoryEx(device, dds, #dds, width, height, 1, 0,
            ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED, 1, 1, 0, nil, nil, out)
        if result ~= ffi.C.S_OK or out[0] == ffi.NULL then
            if out[0] ~= ffi.NULL then out[0]:Release() end
            return nil, 'The client texture could not be uploaded.'
        end
        local texture = out[0]
        return { id = tonumber(ffi.cast('uintptr_t', texture)), release = function()
            if texture ~= nil then texture:Release(); texture = nil end
        end }
    end
    return measure_native(api)
end

local function read(api, filename, limit)
    if not filename then return nil, 'The asset path is unavailable.' end
    local ok, bytes, why = pcall(api.read, filename, limit)
    if not ok then return nil, 'The asset file could not be read.' end
    if type(bytes) ~= 'string' or #bytes > limit then return nil, why or 'Invalid or oversized asset data.' end
    return bytes
end

local function overlay_configuration(api)
    local configuration = call(AshitaCore, 'GetConfigurationManager')
    local root = path(call(configuration, 'GetString', 'pivot', 'settings', 'root_path'))
    local sections = call(configuration, 'GetSections', 'pivot')
    local runtime = type(sections) == 'string' and sections ~= ''
    local overlays = {}
    for index = 0, 63 do
        local name = call(configuration, 'GetString', 'pivot', 'overlays', tostring(index))
        if type(name) == 'string' and name ~= '' then overlays[#overlays + 1] = { index = index, name = name } end
    end
    local ashita_root = api.ashita_root and api.ashita_root() or nil
    if #overlays == 0 and not runtime then
        local contents = read(api, join(ashita_root, 'config/pivot/pivot.ini'), 65536)
        local section
        for line in (contents or ''):gmatch('[^\r\n]+') do
            line = line:gsub('^\239\187\191', ''):match('^%s*(.-)%s*$')
            if line:sub(1, 1) ~= ';' and line:sub(1, 1) ~= '#' then
                local heading = line:match('^%[([^%]]+)%]$')
                if heading then section = heading:lower() else
                    local key, value = line:match('^([^=]+)=(.*)$')
                    if key then
                        key, value = key:match('^%s*(.-)%s*$'):lower(), value:match('^%s*(.-)%s*$')
                        value = value:match('^"(.*)"$') or value
                        if section == 'settings' and key == 'root_path' then root = path(value) end
                        local index = section == 'overlays' and tonumber(key) or nil
                        if index and index >= 0 and index < 64 and index == math.floor(index) then
                            overlays[#overlays + 1] = { index = index, name = value }
                        end
                    end
                end
            end
        end
    end
    root = root or join(ashita_root, 'polplugins/DATs')
    if root and not absolute(root) then root = join(ashita_root, root) end
    table.sort(overlays, function(a, b) return a.index < b.index end)
    local valid = {}
    for _, overlay in ipairs(overlays) do
        local name = path(overlay.name)
        if name and not absolute(name)
            and not ('/' .. name .. '/'):find('/../', 1, true) then
            valid[#valid + 1] = { name = name, root = join(root, name) }
        end
    end
    return valid
end

local function config_path(api, overlays)
    if api.xiview_path then
        local ok, filename = pcall(api.xiview_path)
        if ok and path(filename) then return path(filename), 'XI View fixture' end
    end
    for _, overlay in ipairs(overlays or overlay_configuration(api)) do
        if overlay.name:lower():gsub('[%s%p]', ''):match('^xiview') then
            return join(overlay.root, 'ROM/119/51.DAT'), 'Configured XI View: ' .. overlay.name
        end
    end
    return nil, 'No configured XI View overlay was found.'
end

local function source_reader(api)
    local files = {}
    return function(filename, limit)
        if not filename then return nil, 'The asset path is unavailable.' end
        local key = filename:lower()
        local cached = files[key]
        if not cached then
            local bytes, why = read(api, filename, limit)
            cached = { bytes = bytes, reason = why }; files[key] = cached
        end
        return cached.bytes, cached.reason
    end
end

-- Where the art is, worked out once: the game's folder, and XI View's font file with where it was found (the overlay
-- settings can come from its config file). Reads no DAT.
local function art_roots()
    if roots then return roots end
    local api = platform or native()
    local ok, game = pcall(api.game_root)
    local config_ok, overlays = pcall(overlay_configuration, api)
    overlays = config_ok and overlays or {}
    local view_ok, view_path, view_source = pcall(config_path, api, overlays)
    if not view_ok then view_path, view_source = nil, 'The XI View configuration could not be read.' end
    roots = { game = ok and path(game) or nil, view = view_path, view_source = view_source }
    return roots
end

-- XI View art is read the first time something asks for it, or by its warmup steps. Its menu font is made at load
-- from pixels read for that alone (assets.font_pixels), unless the menu-font cache already holds it.
local deferred = { xiview_font = true }

local function load_kind(kind, held, read_source)
    local definition = held.definition
    local bytes, why = read_source(definition.path, MAX_FILE)
    if bytes then held.data, why = assets.parse(bytes, definition.textures) end
    local data = held.data
    if data and definition.shared then
        -- The action icons' shared texture is in this file too. It waits here for them (load_action), so the file is
        -- read once.
        local name = aliases[definition.shared]
        held.shared = { texture = data.textures[name], reason = data.errors[name] }
        data.textures[name], data.errors[name] = nil, nil
    end
    if data then
        local required = definition.window_type and definition.textures or { 'moji' }
        for _, name in ipairs(required) do
            local texture, size = data.textures[aliases[name]], definition.window_type and WINDOW_SIZES[name]
            if not texture then
                held.data, why = nil, data.errors[aliases[name]] or 'A required client texture is missing.'; break
            end
            if size and (texture.width ~= size or texture.height ~= size) then
                held.data, why = nil, 'This window frame\'s textures are not the sizes the client draws them at.'; break
            end
        end
    end
    held.reason = (deferred[kind] and not definition.path and definition.source)
        or why or 'The client textures have not been uploaded.'
end

local function new_held(definition)
    return { available = false, path = definition.path, source = definition.source,
        window_type = definition.window_type, textures = {}, releases = {}, definition = definition }
end

-- Whether any kind is uploaded, and when the next failed one may try again (nil when none waits).
local function settle()
    local any, next_retry = false, nil
    for _, kind in ipairs(kinds) do
        local held = state[kind]
        if held then
            any = any or held.available
            if held.data and not held.available then
                next_retry = math.min(next_retry or math.huge, held.retry_at or 0)
            end
        end
    end
    ready, retry_at = any, next_retry
end

-- A 565 end color's red, green and blue, widened to 8 bits.
local function widen(value)
    local r, g, b = math.floor(value / 2048), math.floor(value / 32) % 64, value % 32
    return r * 8 + math.floor(r / 4), g * 4 + math.floor(g / 16), b * 8 + math.floor(b / 4)
end

-- weight parts in parts of the second end color, the rest of the first, packed as one number.
local function blend(first, second, weight, parts)
    local r0, g0, b0 = widen(first)
    local r1, g1, b1 = widen(second)
    local keep = parts - weight
    local r = math.floor((keep * r0 + weight * r1) / parts + 0.5)
    local g = math.floor((keep * g0 + weight * g1) / parts + 0.5)
    local b = math.floor((keep * b0 + weight * b1) / parts + 0.5)
    return (r * 256 + g) * 256 + b
end

-- Every texel of a DXT1, DXT3 or DXT5 texture as one number, its color and alpha packed, row by row from the top, as
-- the formats define their blocks. nil for data too short.
local function texels(raw)
    local width, height, dds, format = raw.width, raw.height, raw.dds, raw.format
    local size, wide = format == 'DXT1' and 8 or 16, math.ceil(width / 4)
    if type(dds) ~= 'string' or #dds < 128 + wide * math.ceil(height / 4) * size then return nil end
    local out, colors, alphas = {}, {}, {}
    for block = 0, wide * math.ceil(height / 4) - 1 do
        local at = 129 + block * size
        local color_at = format == 'DXT1' and at or at + 8
        local c0, c1 = u16(dds, color_at), u16(dds, color_at + 2)
        -- A DXT1 block whose first end color isn't the greater has three colors, and its fourth index is see-through.
        local three_colors = format == 'DXT1' and c0 <= c1
        colors[1], colors[2] = blend(c0, c1, 0, 1), blend(c0, c1, 1, 1)
        if three_colors then colors[3], colors[4] = blend(c0, c1, 1, 2), 0
        else colors[3], colors[4] = blend(c0, c1, 1, 3), blend(c0, c1, 2, 3) end
        if format == 'DXT5' then
            local a0, a1 = dds:byte(at, at + 1)
            alphas[0], alphas[1] = a0, a1
            local steps = a0 > a1 and 7 or 5
            for i = 1, steps - 1 do alphas[i + 1] = math.floor(((steps - i) * a0 + i * a1) / steps + 0.5) end
            if steps == 5 then alphas[6], alphas[7] = 0, 255 end
        end
        for texel = 0, 15 do
            local x, y = block % wide * 4 + texel % 4, math.floor(block / wide) * 4 + math.floor(texel / 4)
            local index = math.floor(dds:byte(color_at + 4 + math.floor(texel / 4)) / 4 ^ (texel % 4)) % 4
            local alpha = 255
            if three_colors and index == 3 then alpha = 0
            elseif format == 'DXT3' then
                alpha = math.floor(u16(dds, at + math.floor(texel / 4) * 2) / 16 ^ (texel % 4)) % 16 * 17
            elseif format == 'DXT5' then
                local half = texel < 8 and at + 2 or at + 5
                local bits = dds:byte(half) + dds:byte(half + 1) * 256 + dds:byte(half + 2) * 65536
                alpha = alphas[math.floor(bits / 8 ^ (texel % 8)) % 8]
            end
            if x < width and y < height then out[y * width + x + 1] = colors[index + 1] * 256 + alpha end
        end
    end
    return out
end

-- Whether each row of a texture is one color all the way across, and each column one color all the way down. The skin
-- draws a frame edge whose art is the same along its length as one stretched piece, which draws what its tiles would.
local function evenness(raw)
    local values = texels(raw)
    if not values then return false, false end
    local width, across, down = raw.width, true, true
    for i = 1, #values do
        local x, y = (i - 1) % width, math.floor((i - 1) / width)
        across = across and values[i] == values[y * width + 1]
        down = down and values[i] == values[x + 1]
    end
    return across, down
end

-- Uploads one read kind, whole or not at all, unless it waits for its retry time.
local function upload_kind(kind, held, now)
    if not held.data or held.available or now < (held.retry_at or 0) then return end
    local api, textures, releases, problem = platform or native(), {}, {}, nil
    for name, raw in pairs(held.data.textures) do
        local dds, height = raw.dds, raw.height
        if name == aliases.moji then dds, height = moji_upload(raw) end
        local ok, uploaded, why = pcall(api.upload, dds, raw.width, height, kind .. '.' .. short(name))
        if not ok or type(uploaded) ~= 'table' or type(uploaded.id) ~= 'number' or uploaded.id <= 0
            or uploaded.id ~= uploaded.id or uploaded.id == math.huge then
            if type(uploaded) == 'table' and type(uploaded.release) == 'function' then pcall(uploaded.release) end
            problem = why or 'The client texture could not be uploaded.'; break
        end
        if type(uploaded.release) == 'function' then releases[#releases + 1] = uploaded.release end
        local across, down
        if name == aliases.hfr1 or name == aliases.vfr1 then across, down = evenness(raw) end
        textures[name] = { id = uploaded.id, width = raw.width, height = height, format = raw.format,
            name = name, path = held.path, source = held.source, window_type = held.window_type,
            across = across, down = down }
    end
    if problem then
        for _, release in ipairs(releases) do if type(release) == 'function' then pcall(release) end end
        held.reason, held.retry_at = problem, now + 5
    else
        held.textures, held.releases, held.available, held.reason = textures, releases, true, nil
        generation = generation + 1
        -- Nothing reads uploaded pixels again but a bitmap face, which lets its font's go
        -- (release_pixels). A device change reads the files again.
        for name, raw in pairs(held.data.textures) do
            if name ~= aliases.moji then raw.dds = nil end
        end
    end
end

local function upload_pending(now)
    for _, kind in ipairs(kinds) do
        local held = state[kind]
        if held then upload_kind(kind, held, now) end
    end
    settle()
end

-- Reads XI View's art if it is still waiting, and uploads it.
load_deferred = function()
    view_reader = view_reader or source_reader(platform or native())
    for _, kind in ipairs(kinds) do
        local held = state[kind]
        if held and held.deferred then
            held.deferred = nil
            load_kind(kind, held, view_reader)
        end
    end
    view_reader = nil
    upload_pending(os.clock())
end

-- Where each kind's file is and what it holds, without reading any DAT. XI View's art waits here until it is used.
local function setup()
    if plan then return plan end
    local found = art_roots()
    local game = found.game
    local definitions = {
        original_font = { path = join(game, 'ROM/119/51.DAT'), source = 'Base client files',
            textures = { 'moji', 'gauge', 'acre' }, shared = 'acre' },
        xiview_font = { path = found.view, source = found.view_source, textures = { 'moji', 'gauge', 'acre' }, shared = 'acre' },
    }
    for window_type = 1, 8 do
        definitions[window_key(window_type)] = { path = join(game, ('ROM/0/%d.DAT'):format(13 + window_type)),
            source = 'Base client files', textures = { 'newtex', 'hfr1', 'corner', 'vfr1' }, window_type = window_type }
    end
    plan = definitions
    for kind in pairs(deferred) do
        local held = new_held(definitions[kind])
        held.deferred, held.reason = true, 'The client textures have not been uploaded.'
        state[kind] = held
    end
    settle()
    return plan
end

-- One stock kind: its file read and the kind uploaded. Nothing once it is. The font file may have been read already
-- for its menu font (font_pixels); that read is used here, then let go.
local function load_stock(kind)
    local definitions = setup()
    if state[kind] then return end
    local held = new_held(definitions[kind])
    state[kind] = held
    load_kind(kind, held, kind == 'original_font' and stock_reader or source_reader(platform or native()))
    if kind == 'original_font' then stock_reader = nil end
    upload_kind(kind, held, os.clock())
    settle()
end

-- A window frame the warmup didn't load is read and uploaded the first time it is drawn or asked about.
local function load_window(kind, window_type)
    if kind == 'window' then load_stock(window_key(window_type)) end
end

-- XI View's art the same way. Its first use (load_deferred) reads it if it is still waiting.
local function load_view(kind)
    setup()
    local held = state[kind]
    if not held or not held.deferred then return end
    held.deferred = nil
    view_reader = view_reader or source_reader(platform or native())
    load_kind(kind, held, view_reader)
    upload_kind(kind, held, os.clock())
    settle()
    for other in pairs(deferred) do
        if state[other] and state[other].deferred then return end
    end
    view_reader = nil
end

-- A warmup step: run does work and times it as stage, unless done says there is nothing to do. A failing work is
-- timed, then its error raised again.
function assets.step(stage, done, work)
    return { name = stage, run = function()
        if done() then return end
        local ok, performance = pcall(require, 'core.performance')
        if not ok or type(performance) ~= 'table' or type(performance.now) ~= 'function'
            or type(performance.record) ~= 'function' then performance = nil end
        local started = performance and performance.now()
        local success, why = pcall(work)
        if performance then performance.record(stage, started) end
        if not success then error(why, 0) end
    end }
end

-- The stock art as warmup steps: the window frame the settings draw with, then the font. prepare() runs whichever
-- are left.
function assets.warmup_steps()
    return {
        assets.step('assets.window', function() return state[wanted_window] ~= nil end,
            function() load_stock(wanted_window) end),
        assets.step('assets.original_font', function() return state.original_font ~= nil end,
            function() load_stock('original_font') end),
    }
end

-- The window frame the settings draw with, 1 to 8, for its warmup step. Loads nothing itself.
function assets.want_window(window_type)
    wanted_window = window_key(window_type)
end

-- XI View's art as warmup steps.
function assets.xiview_steps()
    local steps = {}
    for _, kind in ipairs(kinds) do
        if deferred[kind] then
            steps[#steps + 1] = assets.step('assets.' .. kind,
                function() return state[kind] ~= nil and not state[kind].deferred end, function() load_view(kind) end)
        end
    end
    return steps
end

-- Every stock step still to run, then any failed upload whose time has come.
function assets.prepare()
    if not state[wanted_window] or not state.original_font then
        load_stock(wanted_window)
        load_stock('original_font')
    end
    if retry_at == nil then return ready end
    local now = os.clock()
    if now < retry_at then return ready end
    upload_pending(now)
    return ready
end

function assets.retry_pending()
    return plan ~= nil and retry_at ~= nil
end

-- Draw-time recovery only retries the uploads of kinds already read; discovery and file reads stay in prepare()
-- and the warmup steps.
function assets.retry()
    if not plan then return false end
    if retry_at == nil then return ready end
    local now = os.clock()
    if now < retry_at then return ready end
    upload_pending(now)
    return ready
end

function assets.cached_texture(kind, name, window_type)
    local held = asset_group(kind, window_type)
    return held and held.textures[aliases[name] or name] or nil
end

function assets.texture(kind, name, window_type)
    assets.prepare()
    load_window(kind, window_type)
    return assets.cached_texture(kind, name, window_type)
end

-- The font renderer can inspect already validated compressed pixels without another upload. Font pixels
-- not kept (XI View before its first use, or let go) are read again for this call only.
function assets.raw(kind, name, window_type)
    if kind == 'window' then kind = window_key(window_type) end
    local held = state[kind]
    local key = aliases[name] or name
    local raw = held and held.data and held.data.textures[key]
    if not held or key ~= aliases.moji or raw and raw.dds or not raw and not held.deferred then return raw or nil end
    local bytes = read(platform or native(), held.definition.path, MAX_FILE)
    local data = bytes and assets.parse(bytes, { key })
    return data and data.textures[key] or nil
end

-- The moji pixels a menu font is made from, whether or not its kind is loaded yet: kept pixels when there are any,
-- else read for this call. The stock file read here is kept for its warmup step, which follows at once; nothing is
-- loaded or uploaded. Without pixels, why, and whether the file itself was read.
function assets.font_pixels(kind)
    if kind ~= 'original_font' and kind ~= 'xiview_font' then return nil, 'No client font has that name.', false end
    local definition = setup()[kind]
    local held = state[kind]
    if held and not held.deferred then return assets.raw(kind, 'moji') end
    local bytes, why
    if held then bytes, why = read(platform or native(), definition.path, MAX_FILE)
    else
        stock_reader = stock_reader or source_reader(platform or native())
        bytes, why = stock_reader(definition.path, MAX_FILE)
    end
    if not bytes then return nil, why or 'The client font file could not be read.', false end
    local data, problem = assets.parse(bytes, { aliases.moji })
    local raw = data and data.textures[aliases.moji]
    if raw then return raw end
    return nil, data and data.errors[aliases.moji] or problem or 'The client font file has no font texture.', true
end

-- The file kind's art is read from, with its size and last write time, for a cache keyed by its source; nil when
-- that file cannot be looked at. Reads no file.
function assets.source_identity(kind)
    local definition = setup()[kind]
    local api = platform or native()
    if not definition or not definition.path or type(api.stat) ~= 'function' then return nil end
    local ok, size, written = pcall(api.stat, definition.path)
    if not ok or type(size) ~= 'number' or type(written) ~= 'string' then return nil end
    return definition.path:lower() .. '|' .. size .. '|' .. written
end

-- A face made from a font's pixels lets them go once they are uploaded; width and height stay.
function assets.release_pixels(kind, name)
    local held = state[kind]
    local raw = held and held.available and held.data and held.data.textures[aliases[name] or name]
    if raw then raw.dds = nil end
end

-- What a made countdown atlas keeps of its bytes to tell them again: their length and two running sums, so the bytes
-- themselves can go once it is uploaded.
local function checksum(bytes)
    local low, high = 1, 0
    for at = 1, #bytes, 4 do
        local a, b, c, d = bytes:byte(at, at + 3)
        low = (low + a + (b or 0) * 256 + (c or 0) * 65536 + (d or 0) * 16777216) % 4294967291
        high = (high + low) % 4294967291
    end
    return #bytes .. ':' .. low .. ':' .. high
end

-- Countdown glyphs derive one small atlas from each already loaded client font.
function assets.derived_texture(kind, name, dds, width, height)
    if (kind ~= 'original_font' and kind ~= 'xiview_font') or name ~= 'countdown_foreground'
        or type(dds) ~= 'string' or type(width) ~= 'number' or type(height) ~= 'number'
        or width < 1 or height < 1 or width > 256 or height > 256 or width ~= math.floor(width) or height ~= math.floor(height)
        or #dds ~= 128 + width * height * 4 or dds:sub(1,4) ~= 'DDS ' or u32(dds,5) ~= 124
        or u32(dds,13) ~= height or u32(dds,17) ~= width or u32(dds,21) ~= width*4
        or u32(dds,77) ~= 32 or u32(dds,81) ~= 0x41 or u32(dds,85) ~= 0 or u32(dds,89) ~= 32
        or u32(dds,93) ~= 0xFF0000 or u32(dds,97) ~= 0xFF00 or u32(dds,101) ~= 0xFF or u32(dds,105) ~= 0xFF000000 then
        return nil, 'Invalid countdown font atlas.'
    end
    local held = state[kind]
    if not held or not held.available then return nil, 'The client font is not loaded.' end
    held.derived = held.derived or {}
    local cached = held.derived[name]
    if cached then
        if cached.dds and cached.dds ~= dds or not cached.dds and cached.sum ~= checksum(dds) then
            return nil, 'The countdown font source changed without a texture refresh.'
        end
        if cached.texture then return cached.texture end
        if os.clock() < cached.retry_at then return nil, cached.reason end
    else cached = { dds=dds }; held.derived[name] = cached end
    local ok, uploaded, why = pcall((platform or native()).upload, dds, width, height, kind .. '.countdown')
    if not ok or type(uploaded) ~= 'table' or type(uploaded.id) ~= 'number' or uploaded.id <= 0
        or uploaded.id ~= uploaded.id or uploaded.id == math.huge then
        if type(uploaded) == 'table' and type(uploaded.release) == 'function' then pcall(uploaded.release) end
        cached.reason, cached.retry_at = why or 'The countdown font atlas could not be uploaded.', os.clock() + 5
        return nil, cached.reason
    end
    local texture = { id=uploaded.id, width=width, height=height, format='A8R8G8B8' }
    cached.texture, cached.sum, cached.dds = texture, checksum(dds), nil
    if type(uploaded.release) == 'function' then held.releases[#held.releases+1] = uploaded.release end
    return texture
end

local function icon_id(id)
    return type(id) == 'number' and id == math.floor(id) and id >= 0 and id <= 1023
end

-- The bit count of the status record at base (0-based) in data, when its bitmap header is one this reads.
local function icon_bits(data, base)
    local bytes = u32(data, base + 0x281)
    if data:byte(base + 0x285) ~= 0x91 or u32(data, base + 0x296) ~= 40
        or u32(data, base + 0x29A) ~= 32 or u32(data, base + 0x29E) ~= 32
        or u16(data, base + 0x2A2) ~= 1 or u32(data, base + 0x2A6) ~= 0 then
        return nil, 'Unsupported status icon bitmap header.'
    end
    -- The planes and bit-count fields are adjacent 16-bit values in BITMAPINFOHEADER.
    local bits = u16(data, base + 0x2A4)
    if bits ~= 32 and bits ~= 8 or bytes ~= 57 + (bits == 32 and 4096 or 2048) then
        return nil, 'Unsupported status icon bitmap size or pixel format.'
    end
    return bits
end

-- The status record at base in data as a 32 px DDS, its header already checked (icon_bits).
local function icon_record(data, base, bits, buffer, pixel_ffi)
    -- Stock bitmaps use 0..128 alpha, so it is doubled. A few XI View ones peak at 136 (Berserk, Defender and others)
    -- and are doubled too, so the limit is 160. Full-range replacement images retain their own alpha.
    local pixels
    if buffer then
        local source, at = pixel_ffi.cast('const uint8_t*', data) + base, 0
        for y = 31, 0, -1 do
            if bits == 32 then
                pixel_ffi.copy(buffer + at, source + 0x2BD + y * 128, 128)
                at = at + 128
            else
                for x = 0, 31 do
                    pixel_ffi.copy(buffer + at, source + 0x2BD + source[0x6BD + y * 32 + x] * 4, 4)
                    at = at + 4
                end
            end
        end
        local maximum = 0
        for index = 3, 4095, 4 do maximum = math.max(maximum, buffer[index]) end
        if maximum > 0 and maximum <= 160 then
            for index = 3, 4095, 4 do buffer[index] = math.min(255, buffer[index] * 2) end
        end
        pixels = pixel_ffi.string(buffer, 4096)
    else
        local maximum
        pixels, maximum = {}, 0
        for y = 31, 0, -1 do
            for x = 0, 31 do
                local at = base + 0x2BE + (y * 32 + x) * 4
                if bits == 8 then at = base + 0x2BE + data:byte(base + 0x6BE + y * 32 + x) * 4 end
                local pixel = data:sub(at, at + 3)
                maximum = math.max(maximum, pixel:byte(4))
                pixels[#pixels + 1] = pixel
            end
        end
        pixels = table.concat(pixels)
        if maximum > 0 and maximum <= 160 then
            pixels = pixels:gsub('(...)(.)', function(color, alpha) return color .. string.char(math.min(255, alpha:byte() * 2)) end)
        end
    end
    return { dds = ICON_HEADER .. pixels, width = 32, height = 32, format = 'A8R8G8B8' }
end

-- Status records use their file index, matching GetStatusIconByIndex rather than the internal Id. Every record's
-- header is checked here, and bits holds the valid ones'; a record's pixels are made the first time records[id] is
-- read, so a pack costs only the icons drawn from it. Whole records count: a part record at the end is left out, and
-- so is any record past the 1024th.
function assets.parse_icons(data)
    if type(data) ~= 'string' or #data < ICON_STRIDE or #data > MAX_FILE then
        return nil, 'Invalid or oversized status icon DAT file.'
    end
    local count = math.min(ICON_RECORDS, math.floor(#data / ICON_STRIDE))
    if #data > count * ICON_STRIDE then data = data:sub(1, count * ICON_STRIDE) end
    local result = { errors = {}, bits = {}, count = count, valid = 0 }
    for id = 0, count - 1 do
        local bits, why = icon_bits(data, id * ICON_STRIDE)
        result.bits[id], result.errors[id] = bits, why
        if bits then result.valid = result.valid + 1 end
    end
    local ok, pixel_ffi = pcall(require, 'ffi')
    if not ok or type(pixel_ffi.new) ~= 'function' or type(pixel_ffi.copy) ~= 'function' or type(pixel_ffi.cast) ~= 'function'
        or type(pixel_ffi.string) ~= 'function' then pixel_ffi = nil end
    local buffer
    result.records = setmetatable({}, { __index = function(records, id)
        local bits = result.bits[id]
        if not bits then return nil end
        -- One scratch buffer for the whole pack, made with its first record.
        buffer = buffer or pixel_ffi and pixel_ffi.new('uint8_t[4096]')
        local raw = icon_record(data, id * ICON_STRIDE, bits, buffer, pixel_ffi)
        rawset(records, id, raw)
        return raw
    end })
    return result
end

local function icon_base(font_path)
    local value = path(font_path)
    local start = value and value:lower():match('()/rom/119/51%.dat$')
    return start and value:sub(1, start - 1) or nil
end

-- Where each artwork's status icons are, and the files read so far by name (one read serves both).
local icon_roots, icon_files

local function load_icons(definition)
    local read_source = source_reader(platform or native())
    local held = { source = definition[3], textures = {}, releases = {}, failures = {}, available = false }
    icon_sources[definition[1]] = held
    local problem = definition[1] == 'xiview' and not definition[2] and (definition[3] or 'No configured XI View overlay was found.')
    for _, relative in ipairs({ 'ROM/119/57.DAT', 'ROM/0/12.DAT' }) do
        if definition[2] then
            local filename, source = join(definition[2], relative), definition[3]
            local prior = filename and icon_files[filename:lower()]
            local data, why
            if prior then data, why = prior.data, prior.reason
            else
                local bytes
                bytes, why = read_source(filename, MAX_FILE)
                if bytes then data, why = assets.parse_icons(bytes) end
            end
            if data and data.valid > 0 then
                if prior then held = prior; icon_sources[definition[1]] = held
                else held.data, held.path, held.available, held.source = data, filename, true, source end
                icon_files[filename:lower()] = held
                break
            end
            problem = why or 'The status icon file contains no supported images.'
        end
    end
    held.reason = not held.available and (problem or 'The status icon path is unavailable.')
        or held.data.valid < held.data.count and 'Some status images in this artwork are unsupported and use a fallback.' or nil
end

-- XI View's icons are read the first time something draws with them.
function assets.prepare_icons()
    if icon_sources then return end
    icon_sources, icon_files = {}, {}
    local found = art_roots()
    icon_roots = { original = { 'original', found.game, 'Base client files' },
        xiview = { 'xiview', icon_base(found.view), found.view_source } }
    load_icons(icon_roots.original)
end

local function icon_source(kind)
    if icon_sources and icon_sources[kind] == nil and icon_roots[kind] then load_icons(icon_roots[kind]) end
    return icon_sources and icon_sources[kind]
end

-- Whether the stock status icons have been read, and whether kind's have.
function assets.icons_prepared() return icon_sources ~= nil end
function assets.icons_loaded(kind) return icon_sources ~= nil and icon_sources[kind] ~= nil end

-- New icon textures made while drawing, 32 px status icons and action icons: up to 8 in a Present. An upload of a
-- small texture took about 0.16 to 0.25 ms in the game, so a list that shows many new icons at once makes them over
-- the next few Presents instead of stalling one, and draws each once it is made. icon_frame starts each Present's
-- count; before the first Present nothing is counted.
local UPLOADS_PER_PRESENT = 8
local present_uploads

-- Whether one more new icon texture may be made in this Present, counting it if so.
function assets.spend_upload()
    if present_uploads == nil then return true end
    if present_uploads >= UPLOADS_PER_PRESENT then return false end
    present_uploads = present_uploads + 1
    return true
end

-- A status icon's 32 px texture, or nil and why. While this Present's new textures are spent, nil, nil and true: it
-- is made in a later Present, and nothing else is drawn for it meanwhile.
function assets.icon_texture(kind, id)
    if not icon_id(id) then return nil, 'Invalid status icon index.' end
    local held = icon_source(kind)
    if not held or not held.available then return nil, held and held.reason or 'Status icon artwork has not been prepared.' end
    if held.textures[id] then return held.textures[id] end
    if not held.data.bits[id] then return nil, held.data.errors[id] or 'This status index is not present in the selected artwork.' end
    local failed = held.failures[id]
    if failed and os.clock() < failed.retry_at then return nil, failed.reason end
    if not assets.spend_upload() then return nil, nil, true end
    local raw = held.data.records[id]
    local api = platform or native()
    local ok, uploaded, why = pcall(api.upload, raw.dds, raw.width, raw.height, kind .. '.status')
    if not ok or type(uploaded) ~= 'table' or type(uploaded.id) ~= 'number' or uploaded.id <= 0
        or uploaded.id ~= uploaded.id or uploaded.id == math.huge then
        if type(uploaded) == 'table' and type(uploaded.release) == 'function' then pcall(uploaded.release) end
        why = why or 'The status icon texture could not be uploaded.'
        held.failures[id] = { retry_at = os.clock() + 5, reason = why }
        return nil, why
    end
    held.textures[id] = { id = uploaded.id, width = 32, height = 32, path = held.path, source = held.source }
    held.releases[id], held.failures[id] = uploaded.release, nil
    return held.textures[id]
end

-- out, when given, is emptied and filled in place of a new table, for a caller that asks every frame.
function assets.icon_status(kind, id, out)
    if out then require('table.clear')(out) else out = {} end
    local held = icon_source(kind)
    if not held then out.available, out.reason = false, 'Status icon artwork has not been prepared.'; return out end
    local available, reason = held.available, held.reason
    if id ~= nil and available then
        local failed = held.failures[id]
        available = icon_id(id) and held.data.bits[id] ~= nil and not failed
        reason = not available and (failed and failed.reason or held.data.errors[id]
            or 'This status index is not present in the selected artwork.') or nil
    elseif available then
        local _, failure = next(held.failures)
        if failure then reason = failure.reason .. ' Some status images are using fallback artwork.' end
    end
    out.available, out.reason, out.path, out.source = available, reason, held.path, held.source
    out.count, out.valid = held.data and held.data.count or 0, held.data and held.data.valid or 0
    return out
end

-- Party icons drawn at a size other than 32 get a texture made at that size (icon_texture_at), so they draw 1:1 instead
-- of being stretched by the card. Up to 4 are made in a Present, a size is made only once it has been asked for 0.25 s
-- in a row, and each art keeps 4 sizes at most. A size let go of is released at the start of a later Present, after
-- the frame that may still draw it. The report counts what was made.
local SIZED_BUILDS, SIZED_KEPT, SIZED_WAIT, SIZED_RETRY = 4, 4, 0.25, 5
local sized_present, sized_builds, sized_asked, sized_released = 0, 0, 0, {}
local sized_counts, sized_timer = { made = 0, builds = 0, fallbacks = 0, slowest_ms = 0 }, nil

-- For a side of size px, each pixel's first source texel and how much of it and the ones after it the pixel covers.
-- On one line a source texel is size long and a pixel 32, so each pixel's parts add up to 32.
local sized_spans = {}
local function span_for(size)
    local span = sized_spans[size]
    if span then return span end
    span = { first = {}, parts = {} }
    for pixel = 0, size - 1 do
        local from, to = 32 * pixel, 32 * pixel + 32
        local texel, parts = math.floor(from / size), {}
        span.first[pixel] = texel
        while texel < 32 and size * texel < to do
            parts[#parts + 1] = math.min(size * texel + size, to) - math.max(size * texel, from)
            texel = texel + 1
        end
        span.parts[pixel] = parts
    end
    sized_spans[size] = span
    return span
end

-- The pixels of a status record's 32 px DDS made at size px, in the top left of a side px square that is transparent
-- elsewhere. Each pixel is the average of what it covers: alpha by area, colour by area and alpha, so a transparent
-- texel never darkens an edge, each rounded to the nearest byte. Rows go across first, then down.
local function sized_pixels(dds, size, side)
    local span = span_for(size)
    local first, parts = span.first, span.parts
    local alpha, blue, green, red = {}, {}, {}, {}
    for y = 0, 31 do
        local row = 128 + y * 128
        for x = 0, size - 1 do
            local texel, weights = first[x], parts[x]
            local a, b, g, r = 0, 0, 0, 0
            for part = 1, #weights do
                local at = row + (texel + part - 1) * 4
                local pb, pg, pr, pa = dds:byte(at + 1, at + 4)
                local weight = weights[part] * pa
                a, b, g, r = a + weight, b + weight * pb, g + weight * pg, r + weight * pr
            end
            local at = y * size + x
            alpha[at], blue[at], green[at], red[at] = a, b, g, r
        end
    end
    local rows, bytes = {}, {}
    for y = 0, size - 1 do
        local texel, weights = first[y], parts[y]
        for x = 0, size - 1 do
            local a, b, g, r = 0, 0, 0, 0
            for part = 1, #weights do
                local at, weight = (texel + part - 1) * size + x, weights[part]
                a, b, g, r = a + weight * alpha[at], b + weight * blue[at], g + weight * green[at], r + weight * red[at]
            end
            local at = x * 4
            if a > 0 then
                bytes[at + 1], bytes[at + 2] = math.floor((2 * b + a) / (2 * a)), math.floor((2 * g + a) / (2 * a))
                bytes[at + 3], bytes[at + 4] = math.floor((2 * r + a) / (2 * a)), math.floor((a + 512) / 1024)
            else
                bytes[at + 1], bytes[at + 2], bytes[at + 3], bytes[at + 4] = 0, 0, 0, 0
            end
        end
        for at = size * 4 + 1, side * 4 do bytes[at] = 0 end
        rows[y + 1] = string.char(unpack(bytes, 1, side * 4))
    end
    local blank = string.rep('\0', side * 4)
    for y = size, side - 1 do rows[y + 1] = blank end
    return table.concat(rows)
end

-- Milliseconds for the report's slowest build, from the frame timings' counter when it loads.
local function sized_now()
    if sized_timer == nil then
        local ok, performance = pcall(require, 'core.performance')
        sized_timer = ok and type(performance) == 'table' and performance.now or false
    end
    return sized_timer and sized_timer() or os.clock() * 1000
end

-- Status icon id of kind made at size px, and the corner of its texture to draw (UV1), or nil until it is made, and
-- the caller draws the 32 px texture until then. 32 itself and sizes past 128 always use that one.
function assets.icon_texture_at(kind, id, size)
    if not icon_id(id) or type(size) ~= 'number' or size ~= math.floor(size) or size < 1 or size > 128 or size == 32 then
        return nil
    end
    local held = icon_source(kind)
    local raw = held and held.available and held.data.bits[id] and held.data.records[id]
    if not raw then return nil end
    local sizes, now = held.sized, os.clock()
    if not sizes then sizes = {}; held.sized = sizes end
    local entry = sizes[size]
    if not entry then
        -- A size past the 4 kept lets go of the one asked for least recently, never one asked for in this Present.
        local count, oldest = 0, nil
        for _, other in pairs(sizes) do
            count = count + 1
            if other.present ~= sized_present and (not oldest or other.asked < oldest.asked) then oldest = other end
        end
        if count >= SIZED_KEPT then
            if not oldest then return nil end
            for _, release in pairs(oldest.releases) do sized_released[#sized_released + 1] = release end
            sizes[oldest.size] = nil
        end
        local side = size <= 32 and 32 or size <= 64 and 64 or 128
        entry = { size = size, side = side, uv = { size / side, size / side }, textures = {}, releases = {}, failures = {},
            since = now, present = sized_present, asked = 0 }
        sizes[size] = entry
    elseif entry.present < sized_present - 1 then
        -- Not asked for in the Present before: the wait starts again.
        entry.since = now
    end
    sized_asked = sized_asked + 1
    entry.present, entry.asked = sized_present, sized_asked
    local texture = entry.textures[id]
    if texture then return texture, entry.uv end
    if now - entry.since < SIZED_WAIT or sized_builds >= SIZED_BUILDS then return nil end
    local failed = entry.failures[id]
    if failed and now < failed.retry_at then return nil end
    sized_builds, sized_counts.builds = sized_builds + 1, sized_counts.builds + 1
    local started, side = sized_now(), entry.side
    local made, pixels = pcall(sized_pixels, raw.dds, size, side)
    local ok, uploaded, why = false, nil, nil
    if made then
        local dds = 'DDS ' .. le32(124) .. le32(0x100F) .. le32(side) .. le32(side) .. le32(side * 4)
            .. le32(0) .. le32(1) .. string.rep('\0', 44) .. le32(32) .. le32(65) .. le32(0) .. le32(32)
            .. le32(0x00FF0000) .. le32(0x0000FF00) .. le32(0x000000FF) .. le32(0xFF000000)
            .. le32(0x1000) .. string.rep('\0', 16) .. pixels
        ok, uploaded, why = pcall((platform or native()).upload, dds, side, side, kind .. '.status')
    end
    sized_counts.slowest_ms = math.max(sized_counts.slowest_ms, sized_now() - started)
    if not ok or type(uploaded) ~= 'table' or type(uploaded.id) ~= 'number' or uploaded.id <= 0
        or uploaded.id ~= uploaded.id or uploaded.id == math.huge then
        if type(uploaded) == 'table' and type(uploaded.release) == 'function' then pcall(uploaded.release) end
        entry.failures[id] = { retry_at = now + SIZED_RETRY, reason = why or 'The status icon texture could not be made at this size.' }
        sized_counts.fallbacks = sized_counts.fallbacks + 1
        return nil
    end
    texture = { id = uploaded.id, width = side, height = side, size = size }
    entry.textures[id], entry.failures[id] = texture, nil
    if type(uploaded.release) == 'function' then entry.releases[id] = uploaded.release end
    sized_counts.made = sized_counts.made + 1
    return texture, entry.uv
end

-- At the start of each Present: a new budget of builds and of new icon textures, and the sizes let go of in an
-- earlier Present released.
function assets.icon_frame()
    sized_present, sized_builds, present_uploads = sized_present + 1, 0, 0
    for index = #sized_released, 1, -1 do
        pcall(sized_released[index])
        sized_released[index] = nil
    end
end

-- What icon_texture_at made, for /vg report: each art's sizes and how many icons each holds, then the textures made,
-- the builds tried, the ones that failed and drew the 32 px texture instead, and the slowest build in ms.
function assets.icon_sizes_report()
    local kinds = {}
    for kind, held in pairs(icon_sources or {}) do
        local sizes = {}
        for size, entry in pairs(held.sized or {}) do
            local count = 0
            for _ in pairs(entry.textures) do count = count + 1 end
            sizes[#sizes + 1] = { size = size, icons = count }
        end
        table.sort(sizes, function(a, b) return a.size < b.size end)
        kinds[kind] = sizes
    end
    return { sizes = kinds, made = sized_counts.made, builds = sized_counts.builds, fallbacks = sized_counts.fallbacks,
        slowest_ms = sized_counts.slowest_ms }
end

function assets.clear_icons()
    local seen = {}
    for _, held in pairs(icon_sources or {}) do
        if not seen[held] then
            seen[held] = true
            for _, release in pairs(held.releases) do if type(release) == 'function' then pcall(release) end end
            for _, entry in pairs(held.sized or {}) do
                for _, release in pairs(entry.releases) do pcall(release) end
            end
        end
    end
    for index = #sized_released, 1, -1 do
        pcall(sized_released[index])
        sized_released[index] = nil
    end
    icon_sources, icon_files = nil, nil
end

-- Where each pack's files are, and the files read so far by name (one read serves both packs).
local action_roots, action_files
local action_definitions = {
    main = { 'ROM/280/15.DAT', 'menu    magiconw' },
    secondary = { 'ROM/324/95.DAT', 'menu    magico2w' },
    common = { 'ROM/119/51.DAT' },
}
-- The files a part's texture is looked for in, in order.
local main_keys, secondary_keys = { 'main', 'common' }, { 'secondary', 'common' }

-- The common file is a font kind's file too. Once that kind has read it, its texture is what that read kept
-- (load_kind), so the file isn't read again.
local function font_read(filename)
    for _, kind in ipairs({ 'original_font', 'xiview_font' }) do
        local held = state[kind]
        if held and held.shared and held.path and held.path:lower() == filename:lower() then return held.shared end
    end
end

-- One file of a pack, unless it is read already. Each file is its own read; a pack without its own files shares
-- the stock pack's, read once.
local function load_action(kind, key)
    local pack = action_sources[kind]
    if not pack then pack = {}; action_sources[kind] = pack end
    if pack[key] ~= nil then return end
    local definition = action_definitions[key]
    local filename = join(action_roots[kind], definition[1])
    local prior = filename and action_files[filename:lower()]
    if prior then pack[key] = prior; return end
    local shared = key == 'common' and filename and font_read(filename)
    local parsed, why
    if shared then
        parsed, why = { textures = { [aliases.acre] = shared.texture }, layouts = {}, errors = {} }, shared.reason
    else
        local bytes
        bytes, why = read(platform or native(), filename, MAX_FILE)
        if bytes then parsed, why = assets.parse(bytes, key == 'common' and { aliases.acre } or true,
            definition[2] and { definition[2] } or {}) end
    end
    if parsed and definition[2] and not parsed.layouts[definition[2]] then
        parsed, why = nil, 'The native action icon layout is missing.'
    end
    pack[key] = { data = parsed, path = filename, reason = why, textures = {}, failures = {}, releases = {} }
    if filename then action_files[filename:lower()] = pack[key] end
end

local function load_actions(kind)
    for key in pairs(action_definitions) do load_action(kind, key) end
end

-- Where each pack's files are. Reads no DAT.
local function action_setup()
    if action_sources then return end
    action_sources, action_files = {}, {}
    local found = art_roots()
    action_roots = { original = found.game, xiview = icon_base(found.view) }
end

-- Action shapes and their source textures are read once; only used textures reach the GPU. The XI View
-- pack is read the first time something draws with it, or by its warmup steps.
function assets.prepare_actions()
    action_setup()
    load_actions('original')
end

-- One file of a pack read now, for a warmup step, and whether it is read.
function assets.load_action(kind, key)
    if not action_definitions[key] then return end
    action_setup()
    load_action(kind == 'xiview' and kind or 'original', key)
end
function assets.action_loaded(kind, key)
    local pack = action_sources and action_sources[kind == 'xiview' and kind or 'original']
    return pack ~= nil and pack[key] ~= nil
end

-- A pack's first use reads whichever of its files are not read yet.
local function action_source(kind, key)
    if not action_sources then return nil end
    kind = kind == 'xiview' and kind or 'original'
    local pack = action_sources[kind]
    if not pack or pack[key] == nil then load_actions(kind) end
    local held = action_sources[kind][key]
    if held and held.data then return held, kind end
    if action_sources.original == nil or action_sources.original[key] == nil then load_actions('original') end
    return action_sources.original[key], 'original'
end

function assets.action_layout(kind, secondary)
    local held, using = action_source(kind, secondary and 'secondary' or 'main')
    return held and held.data and held.data.layouts[secondary and 'menu    magico2w' or 'menu    magiconw'],
        held and held.reason or 'Action icon artwork has not been prepared.', using
end

action_dds = function(raw, alpha)
    if type(raw) ~= 'table' or raw.format ~= 'DXT3' or type(raw.width) ~= 'number' or type(raw.height) ~= 'number'
        or raw.width < 1 or raw.height < 1 or raw.width > 2048 or raw.height > 2048
        or raw.width ~= math.floor(raw.width) or raw.height ~= math.floor(raw.height)
        or raw.width*raw.height > 1024*1024 or type(raw.dds) ~= 'string'
        or #raw.dds ~= 128+math.ceil(raw.width/4)*math.ceil(raw.height/4)*16
        or type(alpha) ~= 'number' or alpha ~= math.floor(alpha) or alpha < 0 or alpha > 255 then
        return nil,'Unsupported native action pixel format.'
    end
    local ok, pixel_ffi = pcall(require, 'ffi')
    local buffer = ok and type(pixel_ffi.new) == 'function' and type(pixel_ffi.string) == 'function'
        and type(pixel_ffi.abi) == 'function' and pixel_ffi.abi('le')
        and pixel_ffi.new('uint32_t[?]', raw.width*raw.height) or nil
    local rows, colors = {}, {}
    if not buffer then for y=1,raw.height do rows[y] = {} end end
    local bits = require('bit')
    local at = 129
    local function rgb(value)
        local r,g,b = math.floor(value/2048),math.floor(value/32)%64,value%32
        return r*8+math.floor(r/4),g*4+math.floor(g/16),b*8+math.floor(b/4)
    end
    for by=0,math.ceil(raw.height/4)-1 do for bx=0,math.ceil(raw.width/4)-1 do
        local r0,g0,b0 = rgb(u16(raw.dds,at+8))
        local r1,g1,b1 = rgb(u16(raw.dds,at+10))
        colors[1],colors[2] = b0+g0*256+r0*65536,b1+g1*256+r1*65536
        colors[3] = math.floor((2*b0+b1)/3)+math.floor((2*g0+g1)/3)*256+math.floor((2*r0+r1)/3)*65536
        colors[4] = math.floor((b0+2*b1)/3)+math.floor((g0+2*g1)/3)*256+math.floor((r0+2*r1)/3)*65536
        local indices = u32(raw.dds,at+12)
        for pixel=0,15 do
            local x,y = bx*4+pixel%4,by*4+math.floor(pixel/4)
            if x<raw.width and y<raw.height then
                local color = colors[bits.band(bits.rshift(indices,pixel*2),3)+1]
                local packed = raw.dds:byte(at+math.floor(pixel/2))
                local source_alpha = bits.band(bits.rshift(packed,pixel%2*4),15)*17
                local effective = math.min(255,math.floor(source_alpha*alpha*2/255+0.5))
                if buffer then buffer[y*raw.width+x] = color+effective*16777216
                else rows[y+1][x+1] = string.char(color%256,math.floor(color/256)%256,math.floor(color/65536),effective) end
            end
        end
        at = at+16
    end end
    local data
    if buffer then data = pixel_ffi.string(buffer,raw.width*raw.height*4)
    else
        for y=1,#rows do rows[y] = table.concat(rows[y]) end
        data = table.concat(rows)
    end
    return 'DDS '..le32(124)..le32(0x100F)..le32(raw.height)..le32(raw.width)..le32(raw.width*4)
        ..le32(0)..le32(1)..string.rep('\0',44)..le32(32)..le32(0x41)..le32(0)..le32(32)
        ..le32(0xFF0000)..le32(0xFF00)..le32(0xFF)..le32(0xFF000000)..le32(0x1000)
        ..string.rep('\0',16)..data
end

-- A part's texture at its alpha, or nil and why. It is converted and uploaded the first time it is drawn, within this
-- Present's budget of new icon textures (spend_upload); while that is spent, nil, nil and true, and it is made in a
-- later Present.
function assets.action_texture(kind, secondary, name, alpha)
    if type(name) ~= 'string' or #name ~= 16 then return nil, 'Invalid action texture name.' end
    if type(alpha) ~= 'number' or alpha ~= math.floor(alpha) or alpha < 0 or alpha > 255 then return nil,'Invalid native action alpha.' end
    name = name:lower()
    local held, raw
    for _, key in ipairs(secondary and secondary_keys or main_keys) do
        local source = action_source(kind, key)
        if source and source.data and source.data.textures[name] then held, raw = source, source.data.textures[name]; break end
        source = action_source('original', key)
        if source and source.data and source.data.textures[name] then held, raw = source, source.data.textures[name]; break end
    end
    if not raw then return nil, 'The selected client action texture is unavailable.' end
    local key = name..':'..alpha
    if held.textures[key] then return held.textures[key] end
    local failed = held.failures[key]
    if failed and os.clock() < failed.retry_at then return nil, failed.reason end
    if not assets.spend_upload() then return nil, nil, true end
    raw.action_dds = raw.action_dds or {}
    local converted,problem = raw.action_dds[alpha]
    if not converted then converted,problem = action_dds(raw,alpha);raw.action_dds[alpha] = converted end
    if not converted then
        -- Pixels this can't convert never will, so it isn't tried again.
        held.failures[key] = { retry_at = math.huge, reason = problem }
        return nil,problem
    end
    local ok, uploaded, why = pcall((platform or native()).upload, converted, raw.width, raw.height,
        'actions.' .. short(name))
    if not ok or type(uploaded) ~= 'table' or type(uploaded.id) ~= 'number' or uploaded.id <= 0
        or uploaded.id ~= uploaded.id or uploaded.id == math.huge then
        if type(uploaded) == 'table' and type(uploaded.release) == 'function' then pcall(uploaded.release) end
        why = why or 'The native action texture could not be uploaded.'
        held.failures[key] = { retry_at = os.clock() + 30, reason = why }
        return nil, why
    end
    -- The converted pixels are kept only for a retry. A device change reads the files again.
    raw.action_dds[alpha] = nil
    local texture = { id = uploaded.id, width = raw.width, height = raw.height, path = held.path }
    held.textures[key], held.releases[key], held.failures[key] = texture, uploaded.release, nil
    return texture
end

function assets.clear_actions()
    local seen = {}
    for _, pack in pairs(action_sources or {}) do
        for _, held in pairs(pack) do
            if not seen[held] then
                seen[held] = true
                for _, release in pairs(held.releases) do if type(release) == 'function' then pcall(release) end end
            end
        end
    end
    action_sources, action_files = nil, nil
end

-- out, when given, is emptied and filled in place of a new table, for a caller that asks every frame.
function assets.status(kind, window_type, out)
    assets.prepare()
    load_window(kind, window_type)
    if out then require('table.clear')(out) else out = {} end
    local held = asset_group(kind, window_type)
    if not held then out.available, out.reason = false, 'No client asset group has that name.'; return out end
    out.available, out.reason, out.path, out.source = held.available, held.reason, held.path, held.source
    out.window_type = held.window_type
    return out
end

-- Fonts can refresh cached glyph references when uploads recover, without reading files here.
function assets.generation()
    return generation
end

-- The textures a parse left out, by short name, with why; nil when it left none out.
local function skipped(data)
    local out
    for name, why in pairs(data and data.errors or {}) do
        out = out or {}
        out[short(name)] = why
    end
    return out
end

local function tally(values)
    local total = 0
    for _ in pairs(values or {}) do total = total + 1 end
    return total
end

local NOT_YET = 'Not needed yet.'

-- What the art loaded from and why any part of it isn't in use, for /vg report: each kind, the status icons of each
-- artwork and each action pack's files. It reads and uploads nothing, so a part not needed yet says so.
function assets.report()
    local out = { window = wanted_window, kinds = {}, icons = {}, actions = {} }
    for _, kind in ipairs(kinds) do
        local held = state[kind]
        if held and not held.deferred then
            out.kinds[kind] = { available = held.available, reason = held.reason, path = held.path, source = held.source,
                skipped = skipped(held.data) }
        else
            out.kinds[kind] = { available = false, reason = NOT_YET, path = held and held.path, source = held and held.source }
        end
    end
    for _, kind in ipairs({ 'original', 'xiview' }) do
        local held = icon_sources and icon_sources[kind]
        out.icons[kind] = held and { available = held.available, reason = held.reason, path = held.path,
            source = held.source, count = held.data and held.data.count or 0, valid = held.data and held.data.valid or 0,
            made = tally(held.textures), failed = tally(held.failures) } or { available = false, reason = NOT_YET }
        local pack = action_sources and action_sources[kind]
        local files = {}
        for key in pairs(action_definitions) do
            local file = pack and pack[key]
            files[key] = file and { read = file.data ~= nil, reason = file.reason, path = file.path,
                skipped = skipped(file.data), made = tally(file.textures), failed = tally(file.failures) }
                or { read = false, reason = NOT_YET }
        end
        out.actions[kind] = files
    end
    return out
end

-- Call after the last draw that uses these textures, such as addon unload.
function assets.clear()
    assets.clear_icons()
    assets.clear_actions()
    local seen = {}
    for _, held in pairs(state) do
        if not seen[held] then
            seen[held] = true
            for _, release in ipairs(held.releases) do if type(release) == 'function' then pcall(release) end end
        end
    end
    state = {}
    plan, stock_reader, view_reader, roots = nil, nil, nil, nil
    ready, retry_at = false, 0
    generation = generation + 1
end

if VANTAGE_TEST_MODE then
    assets._action_dds_for_tests = action_dds
    function assets._set_platform_for_tests(value)
        assets.clear()
        platform = value
    end
end

return assets
