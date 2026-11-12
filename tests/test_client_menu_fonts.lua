local raw = { width = 1024, height = 2048, format = 'DXT3',
    dds = 'DDS ' .. string.rep('\0', 80) .. 'DXT3' .. string.rep('\0', 40)
        .. string.rep(string.rep('\255', 10) .. string.rep('\0', 6), 1024 * 2048 / 16) }
local reads = 0
package.loaded['ui.client_assets'] = { raw = function(kind, name)
    assert(name == 'moji'); reads = reads + 1
    return kind == 'original_font' and raw or nil
end }
local fonts = require('ui.client_menu_fonts')
local bytes = assert(fonts.generate(raw, 'Original FFXI'))
assert(#bytes < 1048576 and bytes == fonts.generate(raw, 'Original FFXI'), 'Generation is bounded and deterministic.')
assert(not fonts.generate(raw, 'Untrusted name') and not fonts.generate(nil, 'XI View'))
local function u16(text, at)
    local a, b = text:byte(at, at + 1); return a * 256 + b
end
local function u32(text, at) return u16(text, at) * 65536 + u16(text, at + 2) end
local function checksum(text)
    text = text .. string.rep('\0', (4 - #text % 4) % 4)
    local result = 0
    for at = 1, #text, 4 do result = (result + u32(text, at)) % 4294967296 end
    return result
end
assert(u32(bytes, 1) == 0x10000 and checksum(bytes) == 0xB1B0AFBA, 'The generated file has a valid SFNT checksum.')
local tables = {}
for i = 1, u16(bytes, 5) do
    local at = 13 + (i - 1) * 16
    local tag, offset, length = bytes:sub(at, at + 3), u32(bytes, at + 8), u32(bytes, at + 12)
    assert(offset % 4 == 0 and offset + length <= #bytes)
    local value = bytes:sub(offset + 1, offset + length)
    tables[tag] = value
    if tag == 'head' then value = value:sub(1, 8) .. string.rep('\0', 4) .. value:sub(13) end
    assert(checksum(value) == u32(bytes, at + 4), 'Each SFNT table checksum must agree with its directory.')
end
assert(#tables.head == 54 and #tables.hhea == 36 and #tables.maxp == 32 and #tables['OS/2'] == 78)
assert(u16(tables.head, 19) == 1024 and u16(tables.head, 51) == 1 and u16(tables.maxp, 5) == 96)
assert(#tables.loca == 97 * 4 and #tables.hmtx == 96 * 4)
assert(u32(tables.loca, 9) == u32(tables.loca, 5), 'Space has advance but no visible glyph outlines.')
for index = 0, 95 do
    local at, finish = u32(tables.loca, index * 4 + 1), u32(tables.loca, index * 4 + 5)
    assert(at <= finish and finish <= #tables.glyf)
    if index ~= 1 then
        local glyph = tables.glyf:sub(at + 1, finish)
        assert(u16(glyph, 1) == 16 and u16(glyph, 11 + 30) == 63, 'All filled rows retain closed pixel contours.')
    end
end
-- The client's font is a bright core with softer grey pixels at its edges and a dark shadow. A fully lit pixel joins
-- its row's run. A part-lit one becomes a square in the middle of its pixel, as much of the pixel's area as the pixel
-- is lit, so ImGui draws it grey. A dark or see-through one is left out. A DXT3 block is 8 bytes of alpha (4 bits a
-- pixel), two 565 colors and 2 bits a pixel picking one of them or one of the two colors between.
local function block(alphas, first, second, picks)
    local alpha, pick = {}, {}
    for at = 1, 16, 2 do alpha[#alpha + 1] = string.char(alphas[at] + alphas[at + 1] * 16) end
    for row = 0, 3 do
        pick[#pick + 1] = string.char(picks[row * 4 + 1] + picks[row * 4 + 2] * 4 + picks[row * 4 + 3] * 16 + picks[row * 4 + 4] * 64)
    end
    return table.concat(alpha) .. string.char(first % 256, math.floor(first / 256), second % 256, math.floor(second / 256))
        .. table.concat(pick)
end
-- raw's texture with the blocks at the given places changed. A place is the block's column and row.
local function sheet(edits)
    local at, parts, places = 1, {}, {}
    for place in pairs(edits) do places[#places + 1] = place end
    table.sort(places)
    for _, place in ipairs(places) do
        local offset = 128 + place * 16
        parts[#parts + 1] = raw.dds:sub(at, offset)
        parts[#parts + 1] = edits[place]
        at = offset + 17
    end
    parts[#parts + 1] = raw.dds:sub(at)
    return { width = raw.width, height = raw.height, format = raw.format, dds = table.concat(parts) }
end
local function place(column, row) return row * 256 + column end
local full = { 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15 }
local WHITE, BLACK = 0xFFFF, 0x0000
-- White and black give the picks 0 white (255), 1 black (0), 2 grey (170) and 3 dark (85).
local edits = {}
-- '!' is the second cell, so its top left block is column 4. Its other blocks stay white.
edits[place(4, 0)] = block({ 15, 15, 15, 15, 8, 7, 14, 15, 15, 15, 15, 15, 15, 15, 15, 15 }, WHITE, BLACK,
    { 0, 2, 0, 0, 2, 0, 0, 3, 1, 1, 1, 1, 2, 2, 2, 2 })
-- '"' is all black but for one grey pixel at 5, 7 of its cell: column 9, row 1, the pixel at 1, 3 of that block.
for row = 0, 3 do
    for column = 8, 11 do edits[place(column, row)] = block(full, WHITE, BLACK, { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }) end
end
edits[place(9, 1)] = block(full, WHITE, BLACK, { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1 })
-- '#': greens of 56 and 55 of 63 are 226.7 and 222.6, and the two between are 225.3 and 223.97, either side of the 224
-- a core pixel starts at.
edits[place(12, 0)] = block(full, 56 * 32, 55 * 32, { 0, 2, 3, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 })
-- '$': greens of 32 and 31 are 129.5 and 125.5, and the two between are 128.2 and 126.8, either side of the 128 a lit
-- pixel starts at.
edits[place(16, 0)] = block(full, 32 * 32, 31 * 32, { 0, 2, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 })
local soft = assert(fonts.generate(sheet(edits), 'Original FFXI'))
assert(soft ~= bytes and soft == fonts.generate(sheet(edits), 'Original FFXI'))
local soft_tables = {}
for i = 1, u16(soft, 5) do
    local at = 13 + (i - 1) * 16
    soft_tables[soft:sub(at, at + 3)] = soft:sub(u32(soft, at + 8) + 1, u32(soft, at + 8) + u32(soft, at + 12))
end
local function signed(value) return value >= 32768 and value - 65536 or value end
-- A glyph's box and its outlines, each as the pixel-space rectangle it covers in 64ths of a pixel from the cell's top
-- left: left, top, right, bottom.
local function shapes(code)
    local index = code - 31
    local at, finish = u32(soft_tables.loca, index * 4 + 1), u32(soft_tables.loca, index * 4 + 5)
    local glyph = soft_tables.glyf:sub(at + 1, finish)
    local count = u16(glyph, 1)
    local box = { signed(u16(glyph, 3)), signed(u16(glyph, 5)), signed(u16(glyph, 7)), signed(u16(glyph, 9)) }
    local points = count * 4
    assert(u16(glyph, 11 + (count - 1) * 2) == points - 1 and u16(glyph, 11 + count * 2) == 0, 'Four points to an outline, no instructions.')
    local flags = 11 + count * 2 + 2
    local xs, ys = flags + points, flags + points + points * 2
    local out, x, y = {}, 0, 0
    for outline = 0, count - 1 do
        local corner = {}
        for point = 0, 3 do
            local n = outline * 4 + point
            assert(glyph:byte(flags + n) == 1, 'Every point is on its outline.')
            x, y = x + signed(u16(glyph, xs + n * 2)), y + signed(u16(glyph, ys + n * 2))
            corner[point + 1] = { x, 13 * 64 - y }
        end
        assert(corner[1][1] == corner[2][1] and corner[3][1] == corner[4][1] and corner[2][2] == corner[3][2]
            and corner[1][2] == corner[4][2] and corner[1][1] < corner[3][1] and corner[2][2] < corner[1][2],
            'Each outline is a rectangle, drawn the way a filled outline goes.')
        out[#out + 1] = { corner[1][1], corner[2][2], corner[3][1], corner[1][2] }
    end
    return out, box, signed(u16(soft_tables.hmtx, index * 4 + 3))
end
local function same(found, wanted, label)
    assert(#found == #wanted, label .. ': ' .. #found .. ' outlines, not ' .. #wanted)
    for index, rect in ipairs(wanted) do
        for side = 1, 4 do
            assert(found[index][side] == rect[side], ('%s: outline %d is %s, not %s'):format(label, index,
                table.concat(found[index], ' '), table.concat(rect, ' ')))
        end
    end
end
-- '!': the top left block's rows, then the cell's other twelve rows whole.
local wanted = {
    -- white, grey, white, white: a run of one, a square of 52 (170 of 255 lit, as 52 * 52 is of 64 * 64), the rest.
    { 0, 0, 64, 64 }, { 70, 6, 122, 58 }, { 128, 0, 1024, 64 },
    -- Grey at 8 of 15 opaque is a smaller square of 38. White under half opaque is left out. White at 14 of 15 is
    -- core, and the dark pixel after it ends its run.
    { 13, 77, 51, 115 }, { 128, 64, 192, 128 }, { 256, 64, 1024, 128 },
    -- Black is left out.
    { 256, 128, 1024, 192 },
    -- Four grey pixels in a row stay four squares: a run is for fully lit pixels only.
    { 6, 198, 58, 250 }, { 70, 198, 122, 250 }, { 134, 198, 186, 250 }, { 198, 198, 250, 250 }, { 256, 192, 1024, 256 },
}
for row = 4, 15 do wanted[#wanted + 1] = { 0, row * 64, 1024, row * 64 + 64 } end
local found, box, bearing = shapes(33)
same(found, wanted, '!')
assert(box[1] == 0 and box[2] == -192 and box[3] == 1024 and box[4] == 832 and bearing == 0)
-- '"': one grey pixel. Its box and bearing are the whole pixel's, so ImGui gives the glyph the pixel's place.
found, box, bearing = shapes(34)
same(found, { { 5 * 64 + 6, 7 * 64 + 6, 5 * 64 + 58, 7 * 64 + 58 } }, 'One grey pixel')
assert(box[1] == 320 and box[2] == (13 - 8) * 64 and box[3] == 384 and box[4] == (13 - 7) * 64 and bearing == 320,
    'A part-lit pixel at a glyph\'s edge counts as its whole pixel for the glyph\'s box.')
-- '#': 226.7 and 225.3 are core and join one run. 223.97 is a square of 60, the largest there is. 222.6 is one too.
found = shapes(35)
same({ found[1], found[2], found[3], found[4] },
    { { 0, 0, 128, 64 }, { 130, 2, 190, 62 }, { 194, 2, 254, 62 }, { 256, 0, 1024, 64 } }, 'Either side of core')
-- '$': 129.5 and 128.2 are lit, as squares of 46, the smallest there is. 126.8 and 125.5 are left out.
found = shapes(36)
same({ found[1], found[2], found[3] }, { { 9, 9, 55, 55 }, { 73, 9, 119, 55 }, { 256, 0, 1024, 64 } }, 'Either side of lit')
local cmap = tables.cmap:sub(13)
assert(u16(cmap, 1) == 4 and u16(cmap, 3) == #cmap)
local function mapped(code)
    local count = u16(cmap, 7) / 2
    for i = 1, count do
        local finish = u16(cmap, 15 + (i - 1) * 2)
        local start = u16(cmap, 17 + count * 2 + (i - 1) * 2)
        if code >= start and code <= finish then return (code + u16(cmap, 17 + count * 4 + (i - 1) * 2)) % 65536 end
    end
    return 0
end
assert(mapped(32) == 1 and mapped(65) == 34 and mapped(126) == 95)
assert(mapped(160) == 1 and mapped(65533) == mapped(63) and mapped(65535) == 0,
    'Nonbreaking space and the Unicode replacement glyph have explicit mappings.')
local loads, path = 0
fonts.prepare(function(filename, size, sharp)
    loads, path = loads + 1, filename
    assert(size == 16 and filename:find('/config/addons/vantage/cache/client-fonts/original_font-v2-', 1, true))
    assert(sharp == true, 'A menu font is whole pixels, so it asks to be drawn at its own width.')
    local file = assert(io.open(filename, 'rb')); local saved = file:read('*a'); file:close()
    assert(saved == bytes, 'Only the validated generated bytes are passed to the font loader.')
    return { filename = filename }
end)
assert(fonts.face('Original FFXI') and not fonts.face('XI View'))
assert(fonts.face('Original FFXI').filename == path)
fonts.prepare(function() error('Cannot load fonts twice.') end)
fonts.face('Original FFXI')
assert(loads == 1 and reads == 2, 'Lookup and repeated preparation cannot read files or rebuild fonts.')

-- A new addon session reuses the exact cache, even if writes become unavailable.
package.loaded['ui.client_menu_fonts'] = nil
local cached = require('ui.client_menu_fonts')
local original_open = io.open
local original_create, original_exists, creates = ashita.fs.create_dir, ashita.fs.exists, 0
ashita.fs.create_dir = function() creates = creates + 1; return false end
io.open = function(filename, mode)
    assert(mode ~= 'wb', 'A verified unchanged cache must not be rewritten.')
    return original_open(filename, mode)
end
cached.prepare(function(filename) assert(filename == path); return {} end)
io.open = original_open
assert(cached.face('Original FFXI') and creates == 0, 'A valid read-only cache requires neither directory creation nor writes.')

-- An existing directory is usable even when create_dir would return false for it.
local folder = path:match('^(.*)/[^/]+$')
ashita.fs.exists = function(filename) return filename == folder or original_exists(filename) end
local stale = assert(io.open(path, 'wb')); stale:write('old'); stale:close()
package.loaded['ui.client_menu_fonts'] = nil
local existing = require('ui.client_menu_fonts')
existing.prepare(function(filename)
    local file = assert(io.open(filename, 'rb')); local rebuilt = file:read('*a'); file:close()
    assert(rebuilt == bytes); return {}
end)
assert(existing.face('Original FFXI') and creates == 0, 'Rebuilding within an existing cache folder must skip create_dir.')
ashita.fs.create_dir, ashita.fs.exists = original_create, original_exists

-- A failed cache write produces a visible fallback instead of loading stale/corrupt bytes.
local file = assert(io.open(path, 'wb')); file:write('corrupt'); file:close()
package.loaded['ui.client_menu_fonts'] = nil
local failed = require('ui.client_menu_fonts')
io.open = function(filename, mode) if mode == 'wb' then return nil end return original_open(filename, mode) end
failed.prepare(function() error('Invalid cache must never reach the font loader.') end)
io.open = original_open
assert(not failed.face('Original FFXI'))

-- Menu faces can remain usable when the separate HUD texture upload is unavailable.
package.loaded['ui.client_menu_fonts'], package.loaded['ui.client_fonts'], package.loaded['ui.fonts'] = nil, nil, nil
local assets = package.loaded['ui.client_assets']
assets.prepare = function() end
assets.generation = function() return 0 end
assets.retry_pending = function() return false end
assets.layout = function() return nil end
assets.cached_texture = function() return nil end
assets.texture = function() return nil end
assets.status = function() return { reason = 'No GPU texture.' } end
assets.step = function(stage, done, work) return { name = stage, run = function() if not done() then work() end end } end
local all = require('ui.fonts')
all.load()
for _, step in ipairs(all.warmup_steps()) do step.run() end
assert(#all.names() == 19)
assert(not all.window_failed('Original FFXI') and all.failed('Original FFXI'),
    'A generated menu font and its native HUD bitmap have independent availability.')
assert(all.window_failed('XI View'))
local pushed, pushed_size
require('imgui').PushFont = function(font, size) pushed, pushed_size = font, size end
all.push_window('Original FFXI', 16)
assert(type(pushed) == 'string' and pushed:find('/cache/client-fonts/original_font-v2-', 1, true))
all.push('Original FFXI', 16)
assert(pushed == 'default', 'The menu TTF must not replace the HUD bitmap fallback path.')
-- The menu font's glyphs are made on a 16 px grid, so it draws at the multiple of 16 nearest the saved size: 17, the
-- default, at 16. The saved size isn't changed, and any other font draws at it.
for _, case in ipairs({ { 17, 16 }, { 16, 16 }, { 8, 16 }, { 23, 16 }, { 24, 32 }, { 40, 48 } }) do
    all.push_window('Original FFXI', case[1])
    assert(pushed:find('/cache/client-fonts/', 1, true) and pushed_size == case[2], 'The menu font at ' .. case[1] .. ' draws at ' .. case[2] .. '.')
end
all.push_window('XI View', 17)
assert(pushed == 'default' and pushed_size == 17, 'A font that is not a menu font draws at the saved size.')
all.push_window('Segoe UI', 17)
assert(pushed_size == 17)
-- ImGui multiplies a pushed size by the style's main font scale and its DPI scale before it draws. So the menu font
-- is pushed at the multiple of 16 nearest the size on screen, divided by that scale: what is drawn is a whole
-- multiple of 16 whatever the scale. Each case is the main scale, the DPI scale, the saved size and the size drawn.
local gui = require('imgui')
local style = {}
gui.GetStyle = function() return style end
for _, case in ipairs({ { 1, 1, 17, 16 }, { 1.25, 1, 17, 16 }, { 1, 1.25, 17, 16 }, { 1.1, 1, 17, 16 }, { 1.5, 1, 17, 32 },
    { 1, 1.5, 17, 32 }, { 2, 1, 17, 32 }, { 1.25, 1.2, 17, 32 }, { 0.5, 1, 17, 16 }, { 0.75, 1, 40, 32 }, { 3, 1, 17, 48 },
    { 1.25, 1, 40, 48 } }) do
    style.FontScaleMain, style.FontScaleDpi = case[1], case[2]
    all.push_window('Original FFXI', case[3])
    local drawn = pushed_size * case[1] * case[2]
    assert(pushed:find('/cache/client-fonts/', 1, true) and math.abs(drawn - case[4]) < 1e-9,
        ('With a font scale of %s and %s the menu font at %s draws at %s: %s.'):format(case[1], case[2], case[3], case[4], drawn))
    all.push_window('Segoe UI', case[3])
    assert(pushed_size == case[3], 'Another font is pushed at the saved size, as ImGui scales it.')
end
-- A scale that is no scale counts as 1.
for _, bad in ipairs({ { nil, 1 }, { 1, nil }, { 0, 1 }, { -2, 1 }, { 0 / 0, 1 }, { math.huge, 1 }, { 'big', 1 }, { 1, 'big' },
    { 1, 0 }, { 1, -1 } }) do
    style.FontScaleMain, style.FontScaleDpi = bad[1], bad[2]
    all.push_window('Original FFXI', 17)
    assert(pushed_size == 16, 'A font scale of ' .. tostring(bad[1]) .. ' and ' .. tostring(bad[2]) .. ' counts as 1.')
end
gui.GetStyle = function() error('No style.') end
all.push_window('Original FFXI', 17)
assert(pushed_size == 16, 'A style that can\'t be read counts as a scale of 1.')
gui.GetStyle = function() return nil end
all.push_window('Original FFXI', 24)
assert(pushed_size == 32)
gui.GetStyle = nil
return true
