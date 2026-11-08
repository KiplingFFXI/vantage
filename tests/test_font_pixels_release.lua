-- XI View art waits for its first use, and uploaded pixels are let go: a face keeps what it needs, a late
-- upload of another kind leaves a face alone, and a device change reads the files again.
local function u16(value) return string.char(value % 256, math.floor(value / 256) % 256) end
local function u32(value) return u16(value % 65536) .. u16(math.floor(value / 65536)) end
local function chunk(kind, payload)
    local length = math.ceil((16 + #payload) / 16) * 16
    return 'TEST' .. u32(length / 16 * 128 + kind) .. string.rep('\0', 8) .. payload .. string.rep('\0', length - 16 - #payload)
end
local function texture(name, width, height)
    local block = string.rep('\255', 8) .. '\255\255\0\0\0\0\0\0'
    local data = string.rep(block, math.ceil(width / 4) * math.ceil(height / 4))
    return chunk(0x20, string.char(0xA1) .. name .. u32(40) .. u32(width) .. u32(height)
        .. string.rep('\0', 28) .. '3TXD' .. u32(#data) .. u32(0) .. data)
end
local parts = {}
for code = 32, 126 do
    local width = code == 32 and 4 or 9
    local out = {}
    for _, value in ipairs({ 0, 0, width, 0, 0, 11, width, 11 }) do out[#out + 1] = u16(value) end
    out[#out + 1] = u16(width * 2 + 1) .. u16(23) .. u16(0) .. u16(0) .. '\0'
        .. string.rep(string.char(127), 16) .. string.char(1, 0, 1, 1) .. 'font    font    '
    parts[#parts + 1] = '\1' .. table.concat(out)
end
local layout = 'font    fontshp ' .. '\1' .. 'font    font    ' .. u16(95) .. table.concat(parts)
local font_dat = texture('font    moji    ', 1024, 2048) .. texture('font    font    ', 256, 256)
    .. texture('menu    gauge   ', 4, 4) .. chunk(0x31, layout)
local window_dat = texture('menu    newtex  ', 128, 128) .. texture('menu    hfr1    ', 32, 32)
    .. texture('menu    corner  ', 32, 32) .. texture('menu    vfr1    ', 32, 32)
local stock_path, view_path = 'C:/Fixture/ROM/119/51.DAT', 'C:/FixtureView/ROM/119/51.DAT'
local files = { [stock_path] = font_dat, [view_path] = font_dat, ['C:/Fixture/ROM/0/14.DAT'] = window_dat }
local reads, uploads, window_ready, font_down = {}, 0, false, false
local assets = require('ui.client_assets')
assets._set_platform_for_tests({
    game_root = function() return 'C:/Fixture' end,
    ashita_root = function() return 'C:/FixtureAshita' end,
    xiview_path = function() return view_path end,
    read = function(filename)
        reads[filename] = (reads[filename] or 0) + 1
        return files[filename], 'No fixture asset.'
    end,
    upload = function(dds, width, _, label)
        -- An upload without its pixels fails, as the device would refuse it. Not an assert: how many uploads a
        -- rolled-back kind tries first depends on table order, and the count would change with it.
        if type(dds) ~= 'string' or dds:sub(1, 4) ~= 'DDS ' then error('An upload came without its pixels.') end
        -- The window art (each of its textures named window.) fails until window_ready: a late upload of another kind.
        if label:match('^window%.') and not window_ready or width == 1024 and font_down then return nil, 'Device not ready.' end
        uploads = uploads + 1
        return { id = 500 + uploads, release = function() end }
    end,
})
local function upvalue(fn, wanted)
    for index = 1, 200 do
        local name, value = debug.getupvalue(fn, index)
        if name == wanted then return value end
        if not name then break end
    end
end
local state = function() return upvalue(assets.clear, 'state') end
local function pixels(kind, name) return state()[kind].data.textures[name] end
local bitmap = require('ui.client_fonts')
local parses, parse = 0, bitmap.parse
bitmap.parse = function(...) parses = parses + 1; return parse(...) end
local menu = require('ui.client_menu_fonts')

menu.prepare(function(filename) return { path = filename } end)
assert(menu.face('Original FFXI') and menu.face('XI View'), 'Both menu fonts are made at load.')
-- From here parses counts faces: the menu fonts parse the glyphs for their own use.
parses = 0
bitmap.prepare()
assert(parses == 1, 'The stock face is made after them.')
parses = 0
assert(reads[view_path] == 1 and reads[stock_path] == 1 and uploads == 3 and state().xiview_font.data == nil,
    'The XI View menu font reads its pixels for itself; nothing of XI View is kept or uploaded.')
local moji = pixels('original_font', 'font    moji    ')
assert(moji.dds == nil and moji.width == 1024 and moji.height == 2048, 'The face lets the stock font pixels go.')
assert(not pixels('original_font', 'menu    gauge   ').dds
    and pixels('original_font', 'menu    gauge   ').width == 4, 'Uploaded pixels nothing reads again are let go; their size stays.')

local drawn
local list = { AddImageQuad = function(_, id) drawn = id end, AddImage = function(_, id) drawn = id end }
assert(bitmap.available('Original FFXI') and parses == 0, 'The stock face made at load is kept.')
assert(bitmap.draw(list, 'Original FFXI', 'Aster', 0, 0, 16, 0xFFFFFFFF) and drawn)
local stock_image = drawn

-- The window art uploads later. The stock face's own texture is unchanged, so the face stays.
local generation = assets.generation()
window_ready, MOCK.now = true, MOCK.now + 5
assert(bitmap.measure('Original FFXI', 'Aster', 16) and assets.generation() > generation
    and state().window.available, 'The late upload recovers.')
assert(parses == 0 and bitmap.draw(list, 'Original FFXI', 'Aster', 0, 0, 16, 0xFFFFFFFF) and drawn == stock_image,
    'Another kind\'s late upload keeps the face it does not touch, though that face\'s pixels are gone.')

-- XI View is read once, uploaded, and its face made, the first time it is used. Each face also uploads its countdown
-- atlas: 2 stock textures, the stock atlas, 4 of window art, then 2 of XI View and its atlas.
assert(bitmap.available('XI View') and reads[view_path] == 2 and uploads == 10 and parses == 1,
    'The first XI View use reads its file once and uploads its art.')
assert(not pixels('xiview_font', 'font    moji    ').dds and not pixels('xiview_font', 'menu    gauge   ').dds,
    'A face made after load lets its pixels go at once.')
local steady_reads, steady_uploads = reads[stock_path] + reads[view_path], uploads
for _ = 1, 100 do
    for _, name in ipairs({ 'Original FFXI', 'XI View' }) do
        assert(bitmap.draw(list, name, 'Aster', 0, 0, 16, 0xFFFFFFFF))
    end
end
assert(reads[stock_path] + reads[view_path] == steady_reads and uploads == steady_uploads and parses == 1,
    'Steady drawing reads, uploads and parses nothing.')

-- A device change clears everything; the stock face is made again from a fresh read, XI View at its next use.
assets.clear()
assert(bitmap.available('Original FFXI') and reads[stock_path] == 2 and reads[view_path] == 2 and parses == 2
    and not pixels('original_font', 'font    moji    ').dds, 'After a device change the stock face is made again from the files.')
assert(bitmap.draw(list, 'Original FFXI', 'Aster', 0, 0, 16, 0xFFFFFFFF) and drawn ~= stock_image)
assert(bitmap.available('XI View') and reads[view_path] == 3 and parses == 3, 'XI View is read again at its next use.')
menu.prepare(function() error('The menu fonts are made once.') end)

-- A font whose upload failed at load keeps its pixels, so its retry can upload them.
assets.clear()
font_down = true
bitmap = assert(loadfile(ADDON_DIR .. '/ui/client_fonts.lua'))()
package.loaded['ui.client_fonts'] = bitmap
menu = assert(loadfile(ADDON_DIR .. '/ui/client_menu_fonts.lua'))()
menu.prepare(function(filename) return { path = filename } end)
bitmap.prepare()
assert(not bitmap.available('Original FFXI') and pixels('original_font', 'font    moji    ').dds,
    'The pixels of a font still waiting to upload stay.')
local waiting_reads = reads[stock_path]
font_down, MOCK.now = false, MOCK.now + 5
assert(bitmap.available('Original FFXI') and reads[stock_path] == waiting_reads and not pixels('original_font', 'font    moji    ').dds,
    'The retry uploads the kept pixels, the face is made, and only then are they let go.')
assets.clear()
return true
