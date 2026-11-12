-- The menu fonts are cached by the client file they are made from: its path, size and last write time. A whole
-- cached font loads with no client file read and no client art loaded; a changed client file, or a cached font cut
-- short or damaged, makes the font again, and only whole fonts reach the loader. Once a font is newly cached, the
-- kind's other cache files, made for client files since changed, are removed: only names this code writes, and only
-- in its own folder. A client file that can't make a font is noted under its name, so it isn't read again each load.
local function u16(value) return string.char(value % 256, math.floor(value / 256) % 256) end
local function u32(value) return u16(value % 65536) .. u16(math.floor(value / 65536)) end
local function chunk(kind, payload)
    local length = math.ceil((16 + #payload) / 16) * 16
    return 'TEST' .. u32(length / 16 * 128 + kind) .. string.rep('\0', 8) .. payload .. string.rep('\0', length - 16 - #payload)
end
local function texture(name, width, height)
    local data = string.rep(string.rep('\255', 10) .. string.rep('\0', 6), math.ceil(width / 4) * math.ceil(height / 4))
    return chunk(0x20, string.char(0xA1) .. name .. u32(40) .. u32(width) .. u32(height)
        .. string.rep('\0', 28) .. '3TXD' .. u32(#data) .. u32(0) .. data)
end
local stock = 'C:/Fixture/ROM/119/51.DAT'
local files = { [stock] = texture('font    moji    ', 1024, 2048) .. texture('menu    gauge   ', 4, 4) }
local stamps = { [stock] = { 4286240, '01dc2a5b3c4d5e6f' } }
local reads, uploads, stat = 0, 0, true
local platform = {
    game_root = function() return 'C:/Fixture' end,
    ashita_root = function() return 'C:/FixtureAshita' end,
    xiview_path = function() return nil end,
    read = function(filename)
        -- Client files only: the overlay settings may be read to find where XI View is.
        if filename:match('%.DAT$') then reads = reads + 1 end
        return files[filename], 'No fixture asset.'
    end,
    upload = function() uploads = uploads + 1; return { id = uploads, release = function() end } end,
    stat = function(filename)
        if not stat then error('No file times here.') end
        local found = stamps[filename]
        if found then return found[1], found[2] end
    end,
}
local function upvalue(fn, wanted)
    for index = 1, 200 do
        local name, value = debug.getupvalue(fn, index)
        if name == wanted then return value end
        if not name then break end
    end
end
local function contents(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local bytes = file:read('*a'); file:close()
    return bytes
end
local function write(path, bytes)
    local file = assert(io.open(path, 'wb')); file:write(bytes); file:close()
end

local assets = require('ui.client_assets')
local generated = assert(require('ui.client_menu_fonts').generate(
    assert(assets.parse(files[stock], { 'font    moji    ' })).textures['font    moji    '], 'Original FFXI'))
-- A new addon session: client art and menu fonts start over, and parses counts glyph sheets read for a font.
local parses, loaded
local function session()
    assets._set_platform_for_tests(platform)
    reads, uploads, parses, loaded = 0, 0, 0, {}
    package.loaded['ui.client_menu_fonts'], package.loaded['ui.client_fonts'] = nil, nil
    local bitmap = require('ui.client_fonts')
    local parse = bitmap.parse
    bitmap.parse = function(raw, ...) if raw then parses = parses + 1 end; return parse(raw, ...) end
    local menu = require('ui.client_menu_fonts')
    menu.prepare(function(filename, size)
        assert(size == 16 and not filename:find('-v1-', 1, true), 'Only this version\'s cache files are loaded.')
        loaded[#loaded + 1] = { path = filename, bytes = contents(filename) }
        return { path = filename }
    end)
    return menu
end
local function stock_loaded()
    local state = upvalue(assets.clear, 'state')
    return state.original_font ~= nil or state.window ~= nil
end

-- An older version's file in the folder is never loaded, replaced or removed.
local folder = require('core.identity').path('cache/client-fonts')
assert(ashita.fs.create_dir(folder))
MOCK.fs[folder] = true
local older = folder .. '/original_font-v1-0badf00d.ttf'
write(older, generated)
-- Nor is any file not named as this code names its own: another kind's, a short or odd name, a temporary file.
local others = { 'xiview_font-v2-0123456789abcdef.ttf', 'original_font-v2-0123.ttf', 'original_font-v2-0123456789abcdeg.ttf',
    'Original_Font-v2-0123456789abcdef.ttf', 'notes-original_font-v2-0123456789abcdef.ttf',
    'original_font-v2-0123456789abcdef.ttf.7.1.tmp' }
for _, name in ipairs(others) do write(folder .. '/' .. name, 'other') end
-- Nor one beside the folder, named as this code names its files.
local outside = folder:match('^(.*)/[^/]+$') .. '/original_font-v2-0123456789abcdef.ttf'
write(outside, 'outside')
-- The folder's listing as Ashita gives it: the names of its files the filter matches. The fixture knows every name the
-- folder can hold: these, and the fonts and notes the menu fonts write (named).
local names, listings = { 'original_font-v1-0badf00d.ttf', '../original_font-v2-0123456789abcdef.ttf' }, 0
for _, name in ipairs(others) do names[#names + 1] = name end
ashita.fs.get_directory = function(path, filter)
    assert(path == (folder:gsub('/', '\\')) and filter == '.*\\.ttf$', 'The cache folder is listed for its .ttf files.')
    listings = listings + 1
    local out = {}
    for _, name in ipairs(names) do if name:match('%.ttf$') and contents(folder .. '/' .. name) then out[#out + 1] = name end end
    return out
end
local function named(path) names[#names + 1] = path:match('[^/]+$'); return path end
local function untouched()
    for _, name in ipairs(others) do if contents(folder .. '/' .. name) ~= 'other' then return false end end
    return contents(older) == generated and contents(outside) == 'outside'
end

-- First load: no cache yet. The font is made from one read of the client file, which the stock art then shares.
local menu = session()
local first = loaded[1] and named(loaded[1].path)
assert(#loaded == 1 and first:match('/cache/client%-fonts/original_font%-v2%-%x+%.ttf$') and #first:match('%-v2%-(%x+)%.ttf$') == 16,
    'The font is cached under a name made from its client file.')
assert(loaded[1].bytes == generated and reads == 1 and parses == 1, 'A missing cache makes the font from one read.')
assert(menu.face('Original FFXI') and not menu.face('XI View'), 'XI View is not configured here.')
assert(uploads == 0 and not stock_loaded(), 'Making a menu font loads and uploads no client art.')
assert(listings == 1 and untouched(), 'A new font looks for older ones of its kind; there are none yet.')
assets.prepare()
assert(reads == 2 and uploads > 0, 'The stock art reuses the read the menu font made: the frame file in use and the font file.')

-- Next load: the cached font is whole, so nothing is read, made or loaded but the font file.
menu = session()
assert(#loaded == 1 and loaded[1].path == first and loaded[1].bytes == generated, 'The cached font is loaded.')
assert(reads == 0 and parses == 0 and uploads == 0 and not stock_loaded(),
    'A whole cached font needs no client file read, no glyph sheet and no client art.')
assert(listings == 1, 'A cached font writes nothing, so nothing is looked for.')

-- A changed client file makes the font again under a new name, and the font made for the old one is removed.
stamps[stock][2] = '01dc2a5b3c4d5e70'
menu = session()
local second = loaded[1] and named(loaded[1].path)
assert(#loaded == 1 and second ~= first and loaded[1].bytes == generated and reads == 1 and parses == 1,
    'A newer client file makes its font again.')
assert(contents(first) == nil and contents(second) == generated and untouched(), 'The font made for the older client file is removed.')
stamps[stock][1] = 4286256
menu = session()
local third = loaded[1] and named(loaded[1].path)
assert(third ~= second and third ~= first and reads == 1, 'A client file of another size makes its font again.')
assert(contents(second) == nil and contents(third) == generated and untouched() and listings == 3,
    'Only the kind\'s own cache files are removed, and only from its folder.')

-- Damaged or cut short: made again, and only the whole font reaches the loader.
local function damaged(bytes, label)
    write(third, bytes)
    menu = session()
    assert(#loaded == 1 and loaded[1].path == third and loaded[1].bytes == generated and reads == 1 and parses == 1,
        label .. ' is made again and replaced; the loader gets the whole font.')
    assert(contents(third) == generated and untouched(), label .. ': the font it replaces is the only one of its kind.')
end
local middle = math.floor(#generated / 2)
damaged(generated:sub(1, middle) .. string.char((generated:byte(middle + 1) + 1) % 256) .. generated:sub(middle + 2),
    'A font with one changed byte')
damaged(generated:sub(1, middle), 'A font cut short')
damaged(generated:sub(1, #generated - 4), 'A font missing its last four bytes')
damaged(generated:sub(1, 12) .. string.rep('\0', #generated - 12), 'A font with an empty table directory')
damaged('', 'An empty file')

-- A read-only cache folder: a whole font loads with no write; a font that must be made doesn't load.
local original_open, original_create = io.open, ashita.fs.create_dir
local writes = 0
io.open = function(filename, mode)
    if mode ~= 'rb' then writes = writes + 1; return nil end
    return original_open(filename, mode)
end
ashita.fs.create_dir = function() return false end
menu = session()
assert(#loaded == 1 and loaded[1].path == third and writes == 0 and reads == 0, 'A read-only cache still loads its fonts.')
stamps[stock][2] = '01dc2a5b3c4d5e71'
menu = session()
assert(#loaded == 0 and not menu.face('Original FFXI'),
    'A font that cannot be cached is not loaded.')
assert(menu.report()['Original FFXI'].reason == 'The local menu font could not be cached.' and contents(third) == generated,
    'It says why, and the cached font of the older client file stays.')
io.open, ashita.fs.create_dir = original_open, original_create

-- A client file that can't make a font: the reason is noted under its name in place of the font, so the next load
-- reads no client file and gives the same reason, and /vg report has it.
local good, reason = files[stock], 'The ordinary client font texture is missing or unsupported.'
files[stock] = texture('font    moji    ', 512, 512) .. texture('menu    gauge   ', 4, 4)
stamps[stock][2] = '01dc2a5b3c4d5e72'
menu = session()
local note = named(upvalue(upvalue(menu.prepare, 'font_file'), 'source_path')(folder, assets, 'original_font'))
assert(#loaded == 0 and reads == 1 and menu.report()['Original FFXI'].reason == reason and menu.report()['Original FFXI'].path == nil
    and menu.report()['Original FFXI'].loaded == false, 'A client file that can\'t make a font says why.')
assert(contents(note) == 'Vantage could not make this menu font.\n' .. reason, 'The reason is noted under the client file\'s name.')
menu = session()
assert(#loaded == 0 and reads == 0 and parses == 0 and menu.report()['Original FFXI'].reason == reason,
    'The next load reads the note, not the client file.')
-- A changed client file is tried again; the font made from it replaces the note and the older font.
files[stock], stamps[stock][2] = good, '01dc2a5b3c4d5e73'
menu = session()
local fourth = loaded[1] and named(loaded[1].path)
assert(#loaded == 1 and loaded[1].bytes == generated and reads == 1 and contents(note) == nil and contents(third) == nil
    and untouched(), 'A changed client file makes its font, and the note and the older font are removed.')
-- A client file that couldn't be read is not noted: it may read next time.
files[stock], stamps[stock][2] = nil, '01dc2a5b3c4d5e74'
menu = session()
assert(#loaded == 0 and reads == 1 and menu.report()['Original FFXI'].reason == 'No fixture asset.')
menu = session()
assert(#loaded == 0 and reads == 1 and contents(fourth) == generated, 'A failed read is tried again at the next load.')
files[stock] = good

-- Without file times the font is named for its own bytes.
stat = false
menu = session()
assert(#loaded == 1 and loaded[1].bytes == generated and reads == 1
    and loaded[1].path:match('/original_font%-v2%-(%x+)%.ttf$'), 'With no file times the font is made each load.')
named(loaded[1].path)
assert(contents(fourth) == nil and untouched(),
    'It replaces the kind\'s other fonts too; the older version\'s file and the files not named as this code names them stay.')

-- A font the first generator made for this same client file has other shapes, so it is named apart: it is never
-- loaded, the font is made again, and that one goes.
stat = true
menu = session()
local current = named(loaded[1].path)
local source_path = upvalue(upvalue(menu.prepare, 'font_file'), 'source_path')
local digest = upvalue(source_path, 'digest')
local before = named(folder .. '/original_font-v2-' .. digest('generator 1|original_font|' .. assets.source_identity('original_font')) .. '.ttf')
assert(#before:match('%-v2%-(%x+)%.ttf$') == 16 and before ~= current, 'This generator names its fonts apart from the first one\'s.')
os.remove(current)
write(before, generated)
menu = session()
assert(#loaded == 1 and loaded[1].path == current and loaded[1].bytes == generated and reads == 1 and parses == 1,
    'A font the first generator cached is not loaded: the font is made again.')
assert(contents(before) == nil and contents(current) == generated and untouched(), 'The first generator\'s font is removed.')
assets.clear()
return true
