local assets = require('ui.client_assets')
local function le32(n)
    return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256,
        math.floor(n / 16777216) % 256)
end
local function get32(s, at)
    local a, b, c, d = s:byte(at, at + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end
local function chunk(kind, payload)
    local length = math.ceil((16 + #payload) / 16) * 16
    return 'TEST' .. le32(length / 16 * 128 + kind) .. string.rep('\0', 8)
        .. payload .. string.rep('\0', length - 16 - #payload)
end
local names = { newtex = 'menu    newtex  ', hfr1 = 'menu    hfr1    ', corner = 'menu    corner  ',
    vfr1 = 'menu    vfr1    ', font = 'font    font    ', moji = 'font    moji    ',
    gauge = 'menu    gauge   ', fontshp = 'font    fontshp ', anc = 'anc     anc     ' }
local function texture(name, format, extra, width, height, count)
    format, width, height = format or 'DXT1', width or 4, height or 4
    count = count or math.ceil(width / 4) * math.ceil(height / 4) * (format == 'DXT1' and 8 or 16)
    return chunk(0x20, string.char(0xA1) .. names[name] .. le32(40) .. le32(width) .. le32(height)
        .. string.rep('\0', 28 + (extra or 0)) .. format:reverse() .. le32(count) .. le32(0)
        .. string.rep('\0', count))
end
local layout = names.fontshp .. '\1' .. names.font .. '\146\0' .. string.rep('\0', 24)
local font = texture('font', 'DXT3', 4) .. texture('moji', 'DXT3') .. texture('gauge') .. chunk(0x31, layout)
-- A window frame's pieces at the sizes the client draws them at: 128 px for the background, 32 px for the rest.
local function frame(sizes)
    sizes = sizes or {}
    local out = {}
    for _, name in ipairs({ 'newtex', 'hfr1', 'corner', 'vfr1' }) do
        local size = sizes[name] or (name == 'newtex' and 128 or 32)
        out[#out + 1] = texture(name, nil, nil, size, size)
    end
    return table.concat(out)
end
local window = frame()
local parsed, why = assets.parse(window .. font, { names.font, 'newtex' }, { names.fontshp })
assert(parsed and not why and parsed.textures[names.font] and parsed.textures[names.newtex])
assert(not parsed.textures[names.hfr1] and not parsed.textures[names.gauge], 'Only requested textures are retained.')
local dds = parsed.textures[names.font].dds
assert(#dds == 144 and dds:sub(1, 4) == 'DDS ' and get32(dds, 5) == 124)
assert(get32(dds, 13) == 4 and get32(dds, 17) == 4 and dds:sub(85, 88) == 'DXT3',
    'DDS output preserves dimensions and compression in the standard header.')
assert(parsed.layouts[names.fontshp]:sub(1, #layout) == layout, 'The layout stays intact for the independent font parser.')
assert(assets.parse(texture('font', 'DXT5'), { names.font }).textures[names.font].format == 'DXT5')
assert(not assets.parse(window:sub(1, -2), { 'newtex' }), 'Truncated containers must be rejected even after selected textures.')
-- A selected texture that can't be used is left out with why, and the file's other textures still come through.
local function left_out(odd, reason, label)
    local result = assets.parse(odd .. texture('moji', 'DXT3'), { names.font, names.moji })
    assert(result and not result.textures[names.font] and result.errors[names.font] == reason, label)
    assert(result.textures[names.moji] and result.errors[names.moji] == nil, label .. ' The other textures stay.')
end
left_out(texture('font', 'DXT3', 0, 4, 4, 8), 'The compressed texture is incomplete or has an invalid size.',
    'A DXT block size mismatch cannot reach upload.')
left_out(texture('font', 'BAD!'), 'Unsupported texture compression.', 'Unknown compression cannot reach upload.')
left_out(texture('font', 'DXT1', 0, 2049, 4, 8), 'Texture dimensions are outside the supported range.',
    'Oversized dimensions are rejected.')
left_out(texture('font') .. texture('font'), 'Duplicate selected texture in the DAT file.',
    'Duplicate selected textures are ambiguous.')
left_out(texture('font') .. texture('font') .. texture('font'), 'Duplicate selected texture in the DAT file.',
    'A third copy does not bring a duplicate back.')
assert(not assets.parse(chunk(0x31, layout) .. chunk(0x31, layout), {}, { names.fontshp }))
assert(not assets.parse(string.rep('\0', 16), { names.font }), 'Zero-sized chunks cannot loop forever.')
assert(not assets.parse(string.rep(chunk(0, ''), 4097), {}), 'The parser has a finite chunk budget.')
assert(not assets.parse(string.rep('x', 16 * 1024 * 1024 + 1), {}), 'File bounds apply before parsing.')
assert(not assets.parse({}, {}))

local files, reads, uploads, releases = {}, {}, 0, 0
local game, ashita_root = 'C:/Client Root', 'C:/Ashita Root'
for window_type = 1, 8 do files[game .. ('/ROM/0/%d.DAT'):format(13 + window_type)] = window end
files[game .. '/ROM/119/51.DAT'] = font
files[ashita_root .. '/config/pivot/pivot.ini'] = '\239\187\191[settings]\r\nroot_path=polplugins/DATs\r\n'
    .. '[overlays]\r\n0=EraDATs\r\n1="XiView-Standard"\r\n2=XiView-Alternate\r\n'
local viewpath = ashita_root .. '/polplugins/DATs/XiView-Standard/ROM/119/51.DAT'
files[viewpath] = font
local sent = {}
local function upload(data, width, height)
    assert(data:sub(1, 4) == 'DDS ' and get32(data, 13) == height and get32(data, 17) == width,
        'An upload is the size its header says.')
    uploads = uploads + 1
    sent[100 + uploads] = data
    return { id = 100 + uploads, release = function() releases = releases + 1 end }
end
local api = {
    game_root = function() return game end,
    ashita_root = function() return ashita_root end,
    read = function(filename, limit)
        reads[#reads + 1] = filename
        assert(limit <= 16 * 1024 * 1024)
        return files[filename], 'Fixture file missing.'
    end,
    upload = upload,
}
assets._set_platform_for_tests(api)
local generation = assets.generation()
assert(not assets.retry() and assets.raw('original_font', 'moji') == nil
    and assets.cached_texture('original_font', 'moji') == nil and #reads == 0,
    'Draw-time retry and cache inspection never initialize the loader.')
assert(assets.prepare() and uploads == 6 and #reads == 3,
    'Load reads and uploads the window frame in use and the stock font; XI View is not read or uploaded.')
assert(reads[2] == game .. '/ROM/0/14.DAT' and reads[3] == game .. '/ROM/119/51.DAT', 'The frame in use is type 1 unless set.')
assert(assets.generation() > generation, 'Successful uploads advance the read-only generation.')
local stock = assets.texture('original_font', 'moji')
local view = assets.texture('xiview_font', 'moji')
assert(uploads == 8 and #reads == 4, 'Its first use reads its file once and uploads it.')
assert(stock.id ~= view.id and stock.path == game .. '/ROM/119/51.DAT' and view.path == viewpath,
    'Stock and configured XI View fonts retain distinct source paths and GPU resources.')
assert(assets.status('xiview_font').source == 'Configured XI View: XiView-Standard')
assert(assets.raw('original_font', 'moji').dds:sub(85, 88) == 'DXT3')
assert(assets.texture('window', 'hfr1') and not assets.texture('window', 'font'))
local first = assets.texture('window', 'newtex')
local seen = {}
for window_type = 1, 8 do
    local image, status = assets.texture('window', 'newtex', window_type), assets.status('window', window_type)
    assert(image and image.window_type == window_type and not seen[image.id], 'Each client window type owns its selected texture.')
    seen[image.id] = true
    assert(status.available and status.window_type == window_type and status.path == game .. ('/ROM/0/%d.DAT'):format(13 + window_type))
    local raw = assets.raw('window', 'hfr1', window_type)
    assert(assets.texture('window', 'hfr1', window_type).format == 'DXT1' and raw.dds == nil and raw.width == 32,
        'An uploaded skin keeps its size and lets its pixels go.')
    assert(sent[assets.texture('window', 'hfr1', window_type).id]:sub(85, 88) == 'DXT1',
        'The skin reaches the device with its DXT1 header.')
end
assert(uploads == 36 and #reads == 11, 'Each other window frame is read and uploaded the first time it is asked for.')
for _, invalid in ipairs({ 0, 9, -1, 1.5, '2', false, math.huge, 0 / 0 }) do
    assert(assets.texture('window', 'newtex', invalid) == first and assets.status('window', invalid).window_type == 1,
        'Invalid window choices consistently use type 1.')
end
assert(not assets.status('unknown').available)
for _ = 1, 5 do
    assets.prepare()
    for window_type = 1, 8 do assets.texture('window', 'newtex', window_type); assets.status('window', window_type) end
    assets.status('original_font')
end
assert(uploads == 36 and #reads == 11, 'Switching cached window types and status reads never reread files or recreate textures.')
-- /vg report's art section: plain values only, what each kind loaded from, and a part not needed yet said so. Making
-- it reads and uploads nothing.
local function plain(value)
    if type(value) ~= 'table' then return type(value) == 'string' or type(value) == 'number' or type(value) == 'boolean' end
    for key, child in pairs(value) do if not plain(key) or not plain(child) then return false end end
    return true
end
local art = assets.report()
assert(plain(art) and pcall(require('core.store').encode, art), 'The report is plain values that encode.')
assert(art.window == 'window' and art.kinds.window8.available and art.kinds.window8.path == game .. '/ROM/0/21.DAT'
    and art.kinds.xiview_font.available and art.kinds.xiview_font.path == viewpath
    and art.kinds.xiview_font.source == 'Configured XI View: XiView-Standard' and art.kinds.original_font.skipped == nil,
    'Each kind says where it loaded from.')
assert(art.icons.original.reason == 'Not needed yet.' and art.icons.xiview.available == false
    and art.actions.original.main.reason == 'Not needed yet.' and art.actions.xiview.common.read == false,
    'Icons and actions not used yet say so.')
assert(uploads == 36 and #reads == 11, 'The report reads and uploads nothing.')
assets.release_pixels('original_font', 'moji')
assert(assets.raw('original_font', 'moji').dds:sub(85, 88) == 'DXT3' and #reads == 12,
    'Font pixels a face let go are read again for a later caller.')
assets.clear()
assert(releases == 36 and assets.generation() > generation, 'Unload releases every window type and font texture.')
assets.clear()
assert(releases == 36, 'Repeated cleanup must not double-release textures.')

-- One broken skin cannot disable other choices; source changes require an explicit reload.
files[game .. '/ROM/0/17.DAT'] = nil
files[game .. '/ROM/0/18.DAT'] = window:sub(1, -2)
files[game .. '/ROM/0/19.DAT'] = texture('newtex', nil, nil, 128, 128)
-- Pieces at sizes the skin's fixed rectangles aren't made for, as an upscaled frame has, and a piece that can't be used.
files[game .. '/ROM/0/20.DAT'] = frame({ hfr1 = 64 })
files[game .. '/ROM/0/21.DAT'] = frame({ newtex = 64 })
files[game .. '/ROM/0/16.DAT'] = texture('newtex', nil, nil, 128, 128) .. texture('hfr1', 'BAD!', nil, 32, 32)
    .. texture('corner', nil, nil, 32, 32) .. texture('vfr1', nil, nil, 32, 32)
assets.prepare()
assert(not assets.status('window', 4).available and assets.status('window', 4).reason == 'Fixture file missing.')
assert(not assets.status('window', 5).available and assets.status('window', 5).reason:find('beyond', 1, true))
assert(not assets.status('window', 6).available and assets.status('window', 6).reason == 'A required client texture is missing.')
for _, window_type in ipairs({ 7, 8 }) do
    assert(not assets.status('window', window_type).available and not assets.texture('window', 'corner', window_type)
        and assets.status('window', window_type).reason == 'This window frame\'s textures are not the sizes the client draws them at.',
        'A frame whose pieces are not the client\'s sizes falls back and says why.')
end
assert(not assets.status('window', 3).available and assets.status('window', 3).reason == 'Unsupported texture compression.',
    'A frame missing a piece it can\'t use says that piece\'s reason.')
for _, window_type in ipairs({ 1, 2 }) do assert(assets.status('window', window_type).available) end
assert(assets.status('original_font').available and assets.status('xiview_font').available)
local stable_reads = #reads
for window_type = 3, 8 do files[game .. ('/ROM/0/%d.DAT'):format(13 + window_type)] = window end
assets.retry()
assert(not assets.status('window', 4).available and #reads == stable_reads, 'Drawing does not retry failed file reads.')
assets.clear()

-- Broken upload transactions release only their own successful work, and retry cached data later.
local attempts, returned, failed_releases = 0, 0, 0
api.upload = function()
    attempts = attempts + 1
    if attempts == 2 then return nil, 'Device temporarily unavailable.' end
    returned = returned + 1
    return { id = returned, release = function() failed_releases = failed_releases + 1 end }
end
assets._set_platform_for_tests(api)
assets.prepare()
assert(not assets.status('window').available and assets.status('original_font').available)
for window_type = 2, 8 do assert(assets.status('window', window_type).available, 'Failed GPU upload only affects its window type.') end
assert(failed_releases == 1 and not assets.texture('window', 'newtex'), 'Partially uploaded groups are rolled back.')
local read_count, attempt_count = #reads, attempts
MOCK.now = 4
assets.prepare()
assert(attempts == attempt_count and #reads == read_count, 'A failed device is not retried every frame.')
MOCK.now = 5
assets.retry()
assert(assets.status('window').available and #reads == read_count, 'GPU recovery uses the already validated DAT data.')
assets.clear()
assert(failed_releases == returned, 'Rollback and final cleanup together release every uploaded texture exactly once.')

-- Configuration is descriptive: selecting XI View cannot silently use the stock file.
files[ashita_root .. '/config/pivot/pivot.ini'] = '[overlays]\n0=EraDATs\n1=NormalMaps\n'
api.upload = upload
assets._set_platform_for_tests(api)
assets.prepare()
assert(assets.status('original_font').available and not assets.status('xiview_font').available)
assert(assets.status('xiview_font').reason == 'No configured XI View overlay was found.')
assert(assets.texture('xiview_font', 'font') == nil)
assets.clear()
files[ashita_root .. '/config/pivot/pivot.ini'] = '[overlays]\n0=XiView/../../outside\n'
assets.prepare()
assert(not assets.status('xiview_font').available, 'Overlay traversal paths are not accepted.')
assets.clear()
files[ashita_root .. '/config/pivot/pivot.ini'] = '[settings]\nroot_path=C:/Overlay Root\n[overlays]\n0=XI View Standard\n'
files['C:/Overlay Root/XI View Standard/ROM/119/51.DAT'] = font
assets.prepare()
assert(assets.status('xiview_font').available and assets.status('xiview_font').path == 'C:/Overlay Root/XI View Standard/ROM/119/51.DAT')
assets.clear()

-- Runtime configuration takes priority over an unrelated ini; corrupt sources remain unavailable.
local original_configuration = AshitaCore.GetConfigurationManager
AshitaCore.GetConfigurationManager = function() return { GetString = function(_, alias, section, key)
    if alias == 'pivot' and section == 'settings' and key == 'root_path' then return 'C:/Live Overlay' end
    if alias == 'pivot' and section == 'overlays' and key == '0' then return 'XiView-Configured' end
end } end
files['C:/Live Overlay/XiView-Configured/ROM/119/51.DAT'] = font
assets.prepare()
assert(assets.status('xiview_font').path == 'C:/Live Overlay/XiView-Configured/ROM/119/51.DAT')
assets.clear()
AshitaCore.GetConfigurationManager = original_configuration
files[game .. '/ROM/0/14.DAT'] = window:sub(1, -2)
files[game .. '/ROM/119/51.DAT'] = texture('font')
assets.prepare()
assert(not assets.status('window').available and assets.status('window').reason:find('beyond', 1, true))
assert(not assets.status('original_font').available and assets.status('original_font').reason == 'A required client texture is missing.')
assets.clear()
files[game .. '/ROM/119/51.DAT'] = texture('moji', 'DXT3') .. texture('font', 'BAD!')
assets.prepare()
assert(assets.status('original_font').available and assets.texture('original_font', 'gauge') == nil,
    'The ordinary font can load without gauges, nameplate textures, or nameplate layouts.')
assets.clear()
-- A gauge that can't be used is left out with why; the font it shares a file with still loads.
files[game .. '/ROM/119/51.DAT'] = texture('moji', 'DXT3') .. texture('gauge', 'BAD!')
assets.prepare()
assert(assets.status('original_font').available and assets.texture('original_font', 'moji')
    and assets.texture('original_font', 'gauge') == nil, 'One odd texture does not cost the rest of its file.')
assert(assets.report().kinds.original_font.skipped.gauge == 'Unsupported texture compression.',
    'The report says which texture was left out and why.')
assets.clear()
-- A font texture that can't be used fails its kind with that texture's own reason.
files[game .. '/ROM/119/51.DAT'] = texture('moji', 'BAD!') .. texture('gauge')
assets.prepare()
assert(not assets.status('original_font').available and assets.status('original_font').reason == 'Unsupported texture compression.')
assets.clear()
files[game .. '/ROM/119/51.DAT'] = font
local invalid_uploads, invalid_releases = 0, 0
api.upload = function()
    invalid_uploads = invalid_uploads + 1
    return { id = 0, release = function() invalid_releases = invalid_releases + 1 end }
end
assert(not assets.prepare() and invalid_uploads > 0)
assert(invalid_releases == invalid_uploads, 'Rejected window/font uploads release their returned resources immediately.')
MOCK.now = MOCK.now + 5
assets.retry()
assert(invalid_releases == invalid_uploads, 'Repeated rejected uploads do not accumulate resources.')
assets.clear()
assert(invalid_releases == invalid_uploads, 'Rejected uploads are not released again during unload.')

api.read = function() error('Read failed') end
assert(not assets.prepare(), 'A read failure never propagates into the draw loop.')
assets.clear()
api.read = function() return string.rep('x', 16 * 1024 * 1024 + 1) end
assert(not assets.prepare(), 'Injected read boundaries do not bypass the runtime size limit.')
assets.clear()

-- The warmup's window step loads the frame the settings draw with (want_window), which asking for reads nothing.
api.read = function(filename) reads[#reads + 1] = filename; return files[filename], 'Fixture file missing.' end
api.upload = upload
files[game .. '/ROM/0/14.DAT'], files[game .. '/ROM/119/51.DAT'] = window, font
assets._set_platform_for_tests(api)
local before = #reads
assets.want_window(3)
local steps = assets.warmup_steps()
assert(#reads == before and #steps == 2 and steps[1].name == 'assets.window' and steps[2].name == 'assets.original_font',
    'The stock art steps: the frame in use, then the font.')
steps[1].run()
assert(reads[#reads] == game .. '/ROM/0/16.DAT' and assets.cached_texture('window', 'newtex', 3)
    and not assets.cached_texture('window', 'newtex', 1), 'The window step loads the frame asked for and no other.')
steps[2].run()
assets.prepare()
assert(not assets.cached_texture('window', 'newtex', 1) and assets.cached_texture('original_font', 'moji'),
    'Nothing else loads a frame no one draws.')
local read_steps = #reads
steps[1].run(); steps[2].run()
assert(#reads == read_steps, 'A finished step does nothing.')
assets.want_window(1)
assets.clear()
