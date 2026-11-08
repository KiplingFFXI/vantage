local real_assets = assert(loadfile(ADDON_DIR .. '/ui/client_assets.lua'))()

local function fixture()
    local bytes = {}
    for i = 1, 32768 do bytes[i] = 0 end
    -- DXT3 white/black endpoints; transparent pixels choose black.
    for block = 0, 2047 do
        bytes[block * 16 + 9], bytes[block * 16 + 10] = 255, 255
        for i = 13, 16 do bytes[block * 16 + i] = 85 end
    end
    local function pixel(px, py, white)
        local block = math.floor(py / 4) * 256 + math.floor(px / 4)
        local index = py % 4 * 4 + px % 4
        local alpha = block * 16 + math.floor(index / 2) + 1
        local factor = 16 ^ (index % 2)
        bytes[alpha] = bytes[alpha] + (15 - math.floor(bytes[alpha] / factor) % 16) * factor
        if white then
            local color = block * 16 + math.floor(index / 4) + 13
            local shift = 4 ^ (index % 4)
            bytes[color] = bytes[color] - math.floor(bytes[color] / shift) % 4 * shift
        end
    end
    for code = 33, 126 do
        local index = code - 32
        local u, v = index % 64 * 16, math.floor(index / 64) * 16
        local width = code == 105 and 3 or code == 87 and 13 or 8
        for y = 2, 13 do for x = 0, width - 1 do pixel(u + x, v + y, true) end end
        pixel(u + 1, v + 14, false)
        pixel(u + 15, v + 7, false)
    end
    local chunks = {}
    for i = 1, #bytes do chunks[i] = string.char(bytes[i]) end
    local header = 'DDS ' .. string.rep('\0', 80) .. 'DXT3' .. string.rep('\0', 40)
    return { width = 1024, height = 2048, format = 'DXT3',
        dds = header .. table.concat(chunks) .. string.rep('\0', 1024 * 2048 - #bytes) }
end

local raw = fixture()
local image = { id = 123, width = 1024, height = 2048 }
local prepares, reads, textures, retries, generation, recovered = 0, 0, 0, 0, 1, false
local original_available = true
package.loaded['ui.client_assets'] = {
    prepare = function() prepares = prepares + 1 end,
    retry = function() retries = retries + 1 end,
    generation = function() return generation end,
    raw = function(_, name) reads = reads + 1; assert(name == 'moji'); return raw end,
    texture = function(kind, name)
        textures = textures + 1; assert(name == 'moji')
        if kind == 'original_font' and original_available or kind == 'xiview_font' and recovered then return image end
    end,
    status = function() return { available = false, reason = 'Upload unavailable.' } end,
}
local fonts = require('ui.client_fonts')
local face = assert(fonts.parse(raw, image))
assert(face.size == 16 and face.glyphs[32].advance == 8)
assert(face.glyphs[65].advance == 9 and face.glyphs[105].advance == 4 and face.glyphs[87].advance == 14,
    'Only light glyph ink determines spacing; opaque black neighbor bleed cannot widen a letter.')
local glyph = face.glyphs[65].pieces[1]
assert(glyph.xy[3] == 9 and glyph.xy[8] == 16 and glyph.uv[1] == 528 / 1024 and glyph.uv[3] == 537 / 1024)
assert(face.glyphs[105].pieces[1].uv[1] == 144 / 1024 and face.glyphs[105].pieces[1].uv[2] == 16 / 2048,
    'The second ASCII row retains its exact atlas offset.')
assert(not fonts.parse({ dds = raw.dds:sub(1, -2), width = 1024, height = 2048, format = 'DXT3' }, image))
assert(not fonts.parse({ dds = raw.dds, width = 1024, height = 2048, format = 'DXT1' }, image))
assert(not fonts.parse({ dds = 'BAD ' .. raw.dds:sub(5), width = 1024, height = 2048, format = 'DXT3' }, image))
assert(not fonts.parse(raw, { id = 1, width = 256, height = 256 }))
assert(not fonts.parse(raw, { id = 0 / 0, width = 1024, height = 2048 }))
assert(not fonts.parse(raw, nil))
assert(not fonts.parse({ dds = raw.dds:sub(1, 128) .. string.rep('\0', 1024 * 2048),
    width = 1024, height = 2048, format = 'DXT3' }, image), 'A missing printable glyph rejects the incomplete face.')

fonts.prepare()
assert(fonts.available('Original FFXI') and not fonts.available('XI View'))
assert(fonts.reason('Original FFXI') == nil and fonts.reason('XI View') == 'Upload unavailable.')
local width, height = fonts.measure('Original FFXI', 'Ai g', 16)
assert(width == 30 and height == 16)
width, height = fonts.measure('Original FFXI', 'Ai g', 32)
assert(width == 60 and height == 32)
width, height = fonts.measure('Original FFXI', 'A\r\ni', 16)
assert(width == 9 and height == 32, 'CRLF is one line break, and each line has its own width.')
assert(fonts.measure('Original FFXI', 'A\ti', 16) == 45)
assert(fonts.measure('Original FFXI', '', 16) == 0)
assert(fonts.measure('Original FFXI', 'A\194\160i', 16) == 21)
assert(fonts.measure('Original FFXI', 'A\195\169\230\151\165\240\159\152\128i', 16) == 40,
    'Unsupported UTF-8 becomes one visible replacement per character.')
assert(fonts.measure('Original FFXI', '\255\192\175', 16) == 27, 'Malformed bytes remain visible.')
assert(fonts.measure('Agave', 'A', 16) == nil)

local images = {}
local list = { AddImageQuad = function(_, ...) images[#images + 1] = MOCK.copy_arguments(...) end }
assert(fonts.draw(list, 'Original FFXI', 'Ai g', 10, 20, 32, 0x88776655))
assert(#images == 3 and images[1][1] == 123 and images[1][2][1] == 10 and images[1][3][1] == 28)
assert(images[1][4][2] == 52 and images[1][6][1] == 528 / 1024 and images[1][10] == 0x88776655)
assert(images[3][2][1] == 52 and images[3][4][2] == 52, 'Drawing uses the exact measured spacing and scale.')
images = {}
assert(fonts.draw(list, 'Original FFXI', 'i\195\169', 0, 0, 16, 0xffffffff))
assert(#images == 2 and images[2][2][1] == 4 and images[2][6][1] == 496 / 1024)
assert(not fonts.draw(list, 'XI View', 'A', 0, 0, 16, 0xffffffff))
images = {}
assert(fonts.draw(list, 'Original FFXI', 'AiW\ni', 10.3, 20.7, 14, 0xffffffff))
width, height = fonts.measure('Original FFXI', 'AiW\ni', 14)
assert(width == 24 and height == 28, 'Bitmap layout measures the same whole-pixel advances used for drawing.')
assert(images[1][2][1] == 10 and images[1][2][2] == 21 and images[1][3][1] == 18)
assert(images[2][2][1] == 18 and images[2][3][1] == 22 and images[3][3][1] == 34)
assert(images[4][2][1] == 10 and images[4][2][2] == 35)
for _, draw in ipairs(images) do
    for point = 2, 5 do
        for axis = 1, 2 do assert(draw[point][axis] % 1 == 0, 'Every bitmap glyph edge is pixel aligned.') end
    end
end
assert(fonts.measure('Original FFXI', 'AiW\ni', 14.2) == width,
    'Fractional UI scale chooses a stable whole-pixel bitmap size.')
local old_reads, old_textures = reads, textures
fonts.prepare(); fonts.measure('Original FFXI', 'Haste', 16); fonts.draw(list, 'Original FFXI', 'Haste', 0, 0, 16, 0xffffffff)
assert(prepares == 1 and reads == old_reads and textures == old_textures and retries > 0,
    'Steady rendering checks only cached retry state, without rereading or parsing textures.')

recovered, generation = true, generation + 1
assert(fonts.available('XI View') and fonts.reason('XI View') == nil, 'A recovered upload becomes available without reloading the addon.')
image = { id = 456, width = 1024, height = 2048 }; generation = generation + 1
images = {}; fonts.draw(list, 'Original FFXI', 'A', 0, 0, 16, 0xffffffff)
assert(images[1][1] == 456, 'Recreated textures replace old GPU handles.')
original_available, recovered, generation = false, false, generation + 1
assert(not fonts.available('Original FFXI') and not fonts.draw(list, 'Original FFXI', 'A', 0, 0, 16, 0xffffffff))

package.loaded['ui.client_assets'].font_texture = function()
    error('Rendering must not create a nearest-neighbor copy that can remove source strokes.')
end
original_available, recovered, generation = true, true, generation + 1
for _, name in ipairs({ 'Original FFXI', 'XI View' }) do
    for _, size in ipairs({ 8, 12, 13, 14, 16, 24, 48, 120 }) do
        images = {}
        assert(fonts.draw(list, name, 'AiW', 10.3, 20.7, size, 0xffffffff))
        assert(#images == 3 and images[1][1] == 456 and images[2][1] == 456 and images[3][1] == 456,
            'Every requested size uses the original uploaded client glyph texture.')
        assert(images[1][6][1] == 528 / 1024 and images[1][7][1] == 537 / 1024
            and images[1][6][2] == 0 and images[1][8][2] == 16 / 2048,
            'The full original glyph UVs stay intact instead of discarding rows and columns before drawing.')
        assert(fonts.measure(name, 'AiW', size) == images[3][3][1] - images[1][2][1],
            'Custom sizing preserves agreement between clipping/layout and actual drawn advances.')
        assert(fonts.reason(name) == nil)
    end
end
images = {}; fonts.draw(list, 'Original FFXI', 'A', .1, .1, 16, 0xffffffff)
assert(images[1][3][1] - images[1][2][1] == 9 and images[1][4][2] - images[1][2][2] == 16,
    'Native 16-pixel sizing keeps source glyph dimensions without shrinking any strokes.')
assert(fonts.measure('Original FFXI', 'A') == 9, 'An omitted size retains the native size.')
image = { id = 789, width = 1024, height = 2048 }; generation = generation + 1
images = {}; fonts.draw(list, 'Original FFXI', 'A', 0, 0, 14, 0xffffffff)
assert(images[1][1] == 789 and images[1][6][1] == 528 / 1024,
    'A source texture recovery updates custom-size glyph handles without any derived cache.')

-- Local integration remains optional so the portable fixture does not require the game.
-- Two folders up from addons/libs, whatever its case or slashes.
local game = ASHITA_LIBS:gsub('\\', '/'):gsub('/+$', ''):gsub('/[^/]+/[^/]+$', '')
for _, path in ipairs({
    game .. '/SquareEnix/FINAL FANTASY XI/ROM/119/51.DAT',
    game .. '/polplugins/DATs/XiView-Standard/ROM/119/51.DAT',
}) do
    local file = io.open(path, 'rb')
    if file then
        local data = file:read('*a'); file:close()
        local parsed = assert(real_assets.parse(data, { 'moji' }))
        local native_raw = assert(parsed.textures['font    moji    '])
        local native = assert(fonts.parse(native_raw, image))
        assert(native.size == 16 and native.glyphs[65].advance == 11 and native.glyphs[87].advance == 14)
        assert(native.glyphs[105].advance <= 5 and native.glyphs[108].advance <= 6 and native.glyphs[117].advance <= 9,
            'Actual narrow XI View cells must not acquire a 16-pixel advance from neighboring shadow bleed.')
        assert(native.glyphs[126].pieces[1].uv[1] == 480 / 1024)
    end
end
return true
