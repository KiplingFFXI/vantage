-- Only the top 64 rows of the client font texture go to the device: the bitmap face draws only its first two rows
-- of 16-pixel glyphs. The pixels the menu fonts and the countdown atlas read stay whole, and every texel a glyph
-- quad can sample, whether the sampler wraps or clamps, is the same as in the whole texture.
local function u16(value) return string.char(value % 256, math.floor(value / 256) % 256) end
local function u32(value) return u16(value % 65536) .. u16(math.floor(value / 65536)) end
local function chunk(kind, payload)
    local length = math.ceil((16 + #payload) / 16) * 16
    return 'TEST' .. u32(length / 16 * 128 + kind) .. string.rep('\0', 8) .. payload .. string.rep('\0', length - 16 - #payload)
end
local function texture(name, width, height, data)
    data = data or string.rep(string.rep('\255', 8) .. '\255\255\0\0\0\0\0\0', math.ceil(width / 4) * math.ceil(height / 4))
    return chunk(0x20, string.char(0xA1) .. name .. u32(40) .. u32(width) .. u32(height)
        .. string.rep('\0', 28) .. '3TXD' .. u32(#data) .. u32(0) .. data)
end
-- Each block row of the font is told apart by its second colour; every pixel is white ink at full alpha. The
-- last block row is blank but for a second colour, as XI View's is, so it differs from zero bytes.
local blocks = {}
for row = 0, 511 do
    local block = row == 511 and string.rep('\0', 8) .. '\0\0\1\0' .. string.rep('\85', 4)
        or string.rep('\255', 8) .. '\255\255' .. u16(row + 1) .. '\0\0\0\0'
    blocks[#blocks + 1] = string.rep(block, 256)
end
local moji = table.concat(blocks)
local path = 'C:/Fixture/ROM/119/51.DAT'
local files = { [path] = texture('font    moji    ', 1024, 2048, moji) .. texture('menu    gauge   ', 4, 4) }
local uploads, next_id = {}, 0
local assets = require('ui.client_assets')
assets._set_platform_for_tests({
    game_root = function() return 'C:/Fixture' end,
    ashita_root = function() return 'C:/FixtureAshita' end,
    xiview_path = function() return nil end,
    read = function(filename) return files[filename], 'No fixture asset.' end,
    upload = function(dds, width, height, label)
        next_id = next_id + 1
        uploads[#uploads + 1] = { dds = dds, width = width, height = height, label = label }
        return { id = next_id, release = function() end }
    end,
})
local function upvalue(fn, wanted)
    for index = 1, 200 do
        local name, value = debug.getupvalue(fn, index)
        if name == wanted then return value end
        if not name then break end
    end
end
local function le(text, at) local a, b, c, d = text:byte(at, at + 3); return a + b * 256 + c * 65536 + d * 16777216 end

assets.prepare()
local sent
for _, upload in ipairs(uploads) do if upload.label == 'original_font.moji' then sent = upload end end
assert(sent and sent.width == 1024 and sent.height == 64 and #sent.dds == 128 + 65536,
    'The font texture goes to the device as its top 64 rows: 16 rows of DXT3 blocks.')
local raw = assets.raw('original_font', 'moji')
assert(raw and raw.width == 1024 and raw.height == 2048 and #raw.dds == 128 + 2097152,
    'The pixels kept for the menu fonts and the countdown atlas are the whole texture.')
assert(le(sent.dds, 13) == 64 and le(sent.dds, 17) == 1024 and le(sent.dds, 21) == 65536
    and sent.dds:sub(1, 12) == raw.dds:sub(1, 12) and sent.dds:sub(25, 128) == raw.dds:sub(25, 128),
    'Only the header height and size change.')
local row = 4096
assert(sent.dds:sub(129, 128 + row * 9) == raw.dds:sub(129, 128 + row * 9), 'Rows 0 to 35 are the texture\'s own.')
assert(sent.dds:sub(129 + row * 9, 128 + row * 15) == string.rep('\0', row * 6), 'Rows 36 to 59 are blank.')
assert(sent.dds:sub(-row) == raw.dds:sub(-row) and sent.dds:sub(-row) ~= string.rep('\0', row),
    'Rows 60 to 63 are the texture\'s last four rows, so row 63 is its row 2047.')
local image = assets.cached_texture('original_font', 'moji')
assert(image and image.width == 1024 and image.height == 64, 'The uploaded texture records its own height.')
local labels = {}
for _, upload in ipairs(uploads) do labels[upload.label] = (labels[upload.label] or 0) + 1 end
assert(labels['original_font.gauge'] == 1 and labels['original_font.moji'] == 1, 'Each upload names its texture.')

-- The face reads its glyphs from the whole pixels and draws them from the short texture.
local fonts = require('ui.client_fonts')
local face = assert(fonts.parse(raw, image))
local glyph = face.glyphs[65].pieces[1]
assert(glyph.image == image and glyph.uv[2] == 0 and glyph.uv[4] == 16 / 64, 'Top-row glyphs span rows 0 to 16.')
assert(face.glyphs[96].pieces[1].uv[2] == 16 / 64 and face.glyphs[96].pieces[1].uv[4] == 32 / 64,
    'Second-row glyphs span rows 16 to 32.')
local whole = assert(fonts.parse(raw, { id = 9, width = 1024, height = 2048 }))
for code = 32, 126 do
    local a, b = face.glyphs[code], whole.glyphs[code]
    assert(a.advance == b.advance and table.concat(a.pixels) == table.concat(b.pixels)
        and a.pieces[1].uv[1] == b.pieces[1].uv[1] and a.pieces[1].uv[3] == b.pieces[1].uv[3]
        and a.pieces[1].uv[2] * 64 == b.pieces[1].uv[2] * 2048 and a.pieces[1].uv[4] * 64 == b.pieces[1].uv[4] * 2048,
        'Each glyph keeps its pixels and advance, and covers the same texel rows.')
end
assert(not fonts.parse(raw, { id = 9, width = 512, height = 64 }) and not fonts.parse(raw, { id = 9, width = 1024, height = 31 })
    and not fonts.parse(raw, { id = 9, width = 1024, height = 4096 }) and not fonts.parse(raw, { id = 9, width = 1024 }),
    'A texture of another width, too few rows for the glyphs, or more rows than the font has is refused.')

-- Every texel a glyph quad can sample, one texel beyond each edge for filtering, at every scale: the same DXT3
-- block bytes at the same place in the block in the short texture as in the whole one, wrapped or clamped.
local function texel(dds, width, height, x, y, wrap)
    if wrap then x, y = x % width, y % height
    else x, y = math.max(0, math.min(width - 1, x)), math.max(0, math.min(height - 1, y)) end
    local at = 129 + (math.floor(y / 4) * (width / 4) + math.floor(x / 4)) * 16
    return dds:sub(at, at + 15) .. string.char(y % 4 * 4 + x % 4)
end
local moji_upload = upvalue(upvalue(assets.prepare, 'load_stock'), 'upload_kind')
moji_upload = upvalue(moji_upload, 'moji_upload')
local function same_sampling(source, label)
    local short, height = moji_upload(source)
    assert(height == 64 and #short == 128 + source.width / 4 * 16 * 16, label .. ': the short texture is 64 rows.')
    for code = 32, 126 do
        local index = code - 32
        local u, v = index % 64 * 16, math.floor(index / 64) * 16
        for y = v - 1, v + 16 do
            for x = u - 1, u + 16 do
                for _, wrap in ipairs({ true, false }) do
                    if texel(short, 1024, 64, x, y, wrap) ~= texel(source.dds, 1024, 2048, x, y, wrap) then
                        error(('%s: glyph %d samples a different texel at %d,%d'):format(label, code, x, y))
                    end
                end
            end
        end
    end
end
same_sampling(raw, 'Fixture')
local unchanged, rows = moji_upload({ format = 'DXT3', width = 1024, height = 64, dds = sent.dds })
assert(unchanged == sent.dds and rows == 64, 'A font texture already 64 rows tall goes up as it is.')

-- The installed client's own font textures, stock and XI View, when they are on this machine (read only).
local root = ASHITA_LIBS:gsub('\\', '/'):gsub('/+$', ''):gsub('/[^/]+/[^/]+$', '')
for _, relative in ipairs({ 'SquareEnix/FINAL FANTASY XI/ROM/119/51.DAT', 'polplugins/DATs/XiView-Standard/ROM/119/51.DAT' }) do
    local file = io.open(root .. '/' .. relative, 'rb')
    if file then
        local bytes = file:read('*a')
        file:close()
        local parsed = assert(assets.parse(bytes, { 'font    moji    ' }))
        same_sampling(assert(parsed.textures['font    moji    ']), relative)
    end
end
assets.clear()
return true
