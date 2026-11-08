local assets, icons = require('ui.client_assets'), require('ui.icons')
local function le16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
local function le32(n) return le16(n % 65536) .. le16(math.floor(n / 65536)) end
local function record(bits, pixels)
    local data = string.rep('\0', 0x280) .. le32(57 + #pixels) .. '\145' .. string.rep(' ', 16)
        .. le32(40) .. le32(32) .. le32(32) .. le16(1) .. le16(bits)
        .. string.rep('\0', 24) .. pixels
    return data .. string.rep('\0', 0x1800 - #data)
end
local function replace(data, offset, value) return data:sub(1, offset) .. value .. data:sub(offset + #value + 1) end
local red, blue, white = '\0\0\255\128', '\255\0\0\128', '\255\255\255\255'
local stock = record(32, string.rep(red, 32 * 31) .. string.rep(blue, 32))
local view = record(32, white .. string.rep(red, 1023))
local palette = '\0\0\0\0' .. blue .. string.rep('\0', 254 * 4)
local indexed = record(8, palette .. string.rep('\1', 1024))
local bad = replace(stock, 0x299, le32(64))
local parsed = assert(assets.parse_icons(stock .. indexed .. bad))
assert(parsed.count == 3 and parsed.valid == 2 and parsed.errors[2], 'One corrupt record cannot hide the other valid images.')
assert(parsed.records[0].dds:sub(129, 132) == '\255\0\0\255', 'Bottom-up source rows become top-down DDS pixels.')
assert(parsed.records[0].dds:sub(-4) == '\0\0\255\255', 'Stock half-range alpha becomes opaque.')
assert(parsed.records[1].dds:sub(129, 132) == '\255\0\0\255', 'Indexed icons preserve their palette and alpha.')
local replacement = assert(assets.parse_icons(view)).records[0]
assert(replacement.dds:sub(129, 132) == red and replacement.dds:sub(-128, -125) == white,
    'Full-range replacement artwork retains partially transparent pixels, including alpha128.')
assert(#replacement.dds == 128 + 32 * 32 * 4 and replacement.width == 32 and replacement.height == 32)
-- Only whole records count, the first 1024 at most: a cut record at the end is left out with the rest still used.
for _, case in ipairs({ { stock .. 'x', 1, 1 }, { stock .. indexed:sub(1, -2), 1, 1 }, { string.rep('\0', 0x1800 * 1024 + 1), 1024, 0 } }) do
    local whole = assert(assets.parse_icons(case[1]))
    assert(whole.count == case[2] and whole.valid == case[3], 'Whole records count: ' .. case[2])
end
for _, invalid in ipairs({ '', stock:sub(1, -2), string.rep('\0', 16 * 1024 * 1024 + 1) }) do
    assert(not assets.parse_icons(invalid), 'Truncated and oversized containers are rejected before upload.')
end
for _, invalid in ipairs({
    replace(stock, 0x280, le32(9999)), replace(stock, 0x284, '\0'), replace(stock, 0x295, le32(108)),
    replace(stock, 0x299, le32(512)), replace(stock, 0x29D, le32(0xFFFFFFE0)),
    replace(stock, 0x2A1, le16(2)), replace(stock, 0x2A3, le16(24)), replace(stock, 0x2A5, le32(1)),
}) do assert(assets.parse_icons(invalid).valid == 0, 'Unsupported bitmap headers never produce a texture.') end

local files = {
    ['C:/Client/ROM/119/57.DAT'] = stock .. stock .. stock .. bad,
    ['C:/Ashita/config/pivot/pivot.ini'] = '[settings]\nroot_path=polplugins/DATs\n[overlays]\n0=EraDATs\n1=XiView-Standard\n',
    ['C:/Ashita/polplugins/DATs/XiView-Standard/ROM/119/57.DAT'] = view .. bad,
}
local reads, uploads, releases, client_calls, now, fail_upload = 0, 0, 0, 0, 0, false
local previous_clock = os.clock
os.clock = function() return now end
local api = {
    game_root = function() return 'C:/Client' end,
    ashita_root = function() return 'C:/Ashita' end,
    read = function(path, limit)
        reads = reads + 1
        assert(limit <= 16 * 1024 * 1024)
        return files[path], 'Fixture artwork missing.'
    end,
    upload = function(data, width, height)
        uploads = uploads + 1
        assert(data:sub(1, 4) == 'DDS ' and #data == 4224 and width == 32 and height == 32)
        if fail_upload then return { id = 0, release = function() releases = releases + 1 end }, 'Device unavailable.' end
        return { id = 100 + uploads, release = function() releases = releases + 1 end }
    end,
}
assets._set_platform_for_tests(api)
icons._set_loader_for_tests(function(id) client_calls = client_calls + 1; return 9000 + id end)
assert(icons.status(0, 'XI View') == 9000 and reads == 0, 'Unprepared draw calls fall back without reading files.')
assert(icons.reason('XI View'):find('not been prepared', 1, true))
icons.prepare()
assert(reads == 2 and uploads == 0, 'Startup reads the stock pack once, uploads none of its icons, and leaves XI View for its first use.')
local original, xiview = icons.status(0, 'Original FFXI'), icons.status(0, 'XI View')
assert(reads == 3, 'The first XI View icon reads its pack once.')
assert(original == 101 and xiview == 102 and original ~= xiview)
assert(icons.artwork_status('XI View', 0).using == 'XI View' and icons.reason('XI View', 0) == nil)
assert(icons.artwork_status('XI View').count == 2 and icons.reason('XI View'):find('unsupported', 1, true))
for _ = 1, 20 do
    assert(icons.status(0, 'XI View') == xiview and icons.status(0, 'Original FFXI') == original)
    icons.artwork_status('XI View', 0)
end
assert(uploads == 2 and reads == 3, 'Steady rendering uses one GPU handle per pack and index, with no new reads.')
assert(icons.status(1, 'XI View') == 103 and icons.artwork_status('XI View', 1).using == 'Original FFXI')
assert(icons.reason('XI View', 1):find('Unsupported', 1, true), 'A corrupt replacement has an explicit per-image fallback reason.')
assert(icons.status(639, 'XI View') == 9639 and icons.artwork_status('XI View', 639).using == 'Client')
assert(icons.status(1023, 'Original FFXI') == 10023, 'Wire indices outside a pack retain the client-image fallback.')
local before_calls = client_calls
for _, invalid in ipairs({ -1, 1024, 1.5, math.huge, 0 / 0, '33' }) do assert(not icons.status(invalid, 'XI View')) end
assert(client_calls == before_calls and uploads == 3 and reads == 3)
assert(icons.status(0) == 9000 and icons.status(0, 'unknown') == 9000, 'The default and invalid selections preserve Client artwork.')

fail_upload = true
assert(icons.status(2, 'Original FFXI') == 9002 and uploads == 4 and releases == 1)
assert(icons.reason('Original FFXI', 2):find('Device unavailable', 1, true))
assert(icons.reason('Original FFXI'):find('using fallback artwork', 1, true),
    'Settings can explain a GPU fallback without requiring a particular status index.')
for _ = 1, 20 do assert(icons.status(2, 'Original FFXI') == 9002) end
assert(uploads == 4 and reads == 3, 'Failed uploads do not retry each frame or reopen the source file.')
fail_upload, now = false, 5
assert(icons.status(2, 'Original FFXI') == 105 and icons.reason('Original FFXI', 2) == nil)
assert(reads == 3, 'A recovered upload uses only cached validated bitmap bytes.')
icons.clear()
assert(releases == 5, 'Failed and successful explicit textures are each released exactly once.')
icons.clear(); assets.clear(); assert(releases == 5)

files['C:/Client/ROM/119/57.DAT'] = nil
files['C:/Client/ROM/0/12.DAT'] = indexed
files['C:/Ashita/polplugins/DATs/XiView-Standard/ROM/119/57.DAT'] = nil
local before_reads = reads
icons.prepare()
assert(icons.artwork_status('Original FFXI').path == 'C:/Client/ROM/0/12.DAT')
assert(icons.reason('XI View'):find('Fixture artwork missing', 1, true))
local after_reads = reads
files['C:/Ashita/polplugins/DATs/XiView-Standard/ROM/119/57.DAT'] = view
assert(icons.status(0, 'XI View') and icons.artwork_status('XI View', 0).using == 'Original FFXI')
icons.prepare(); assert(reads == after_reads and reads > before_reads, 'Installing replacement files takes effect on reload, never during drawing.')
icons.clear()

-- From the first Present on, up to 8 new icon textures are made in each. An icon past them draws nothing, not another
-- artwork's image, and is made in a later Present.
files['C:/Client/ROM/119/57.DAT'] = string.rep(stock, 12)
assets.clear()
icons.prepare()
assets.icon_frame()
uploads, client_calls = 0, 0
for id = 0, 7 do assert(icons.status(id, 'Original FFXI')) end
assert(icons.status(8, 'Original FFXI') == nil and icons.status(9, 'XI View') == nil and uploads == 8 and client_calls == 0,
    'The ninth new texture waits, with nothing drawn in its place.')
assert(icons.status(10) == nil and client_calls == 0, 'Client art waits for the same budget.')
assert(icons.status(3, 'Original FFXI') and icons.artwork_status('Original FFXI', 8).available, 'Made icons draw, and a waiting one is not missing.')
assets.icon_frame()
assert(icons.status(8, 'Original FFXI') and icons.status(9, 'XI View') and icons.status(10) == 9010 and uploads == 10 and client_calls == 1,
    'They are made in the next Present.')
icons.clear()
os.clock = previous_clock

-- Actual local resources remain optional for portable development tests.
-- Two folders up from addons/libs, whatever its case or slashes.
local game = ASHITA_LIBS:gsub('\\', '/'):gsub('/+$', ''):gsub('/[^/]+/[^/]+$', '')
for _, root in ipairs({
    game .. '/SquareEnix/FINAL FANTASY XI',
    game .. '/polplugins/DATs/XiView-Standard',
}) do
    local file = io.open(root .. '/ROM/119/57.DAT', 'rb')
    if file then
        local data = file:read(1024 * 0x1800 + 1); file:close()
        local parsed_real = assert(assets.parse_icons(data))
        assert(parsed_real.count == 640 and parsed_real.valid == 640, 'All installed status records decode, including indexed stock icons.')
        for _, id in ipairs({ 0, 3, 33, 40, 490, 639 }) do
            assert(parsed_real.records[id] and #parsed_real.records[id].dds == 4224)
        end
    end
end
return true
