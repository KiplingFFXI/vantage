local menu_fonts = {}
local kinds = { ['Original FFXI'] = 'original_font', ['XI View'] = 'xiview_font' }
local prepared, faces, serial = false, {}, 0
-- What prepare found for each menu font, for /vg report: its cached file, or why there is none or it didn't load.
local results = {}
local MAX_FONT = 1048576
-- Raise this whenever generate makes different bytes, so fonts cached by older code are made again.
local GENERATOR = 1
-- The tables generate writes, all of which a cached font must hold.
local TABLES = { 'OS/2', 'cmap', 'glyf', 'head', 'hhea', 'hmtx', 'loca', 'maxp', 'name', 'post' }

local function u16(value)
    value = value % 65536
    return string.char(math.floor(value / 256), value % 256)
end

local function u32(value)
    value = value % 4294967296
    return u16(math.floor(value / 65536)) .. u16(value % 65536)
end

local function words(values)
    local out = {}
    for _, value in ipairs(values) do out[#out + 1] = u16(value) end
    return table.concat(out)
end

local function pad(value)
    return value .. string.rep('\0', (4 - #value % 4) % 4)
end

local function checksum(value)
    local sum = 0
    value = pad(value)
    for at = 1, #value, 4 do
        local a, b, c, d = value:byte(at, at + 3)
        sum = (sum + a * 16777216 + b * 65536 + c * 256 + d) % 4294967296
    end
    return sum
end

local function channels(value)
    return { math.floor(value / 2048) * 255 / 31, math.floor(value / 32) % 64 * 255 / 63, value % 32 * 255 / 31 }
end

local function ink_reader(raw)
    local blocks = {}
    return function(x, y)
        local block = math.floor(y / 4) * 256 + math.floor(x / 4)
        local index = y % 4 * 4 + x % 4
        local alpha = raw.dds:byte(129 + block * 16 + math.floor(index / 2))
        alpha = index % 2 == 0 and alpha % 16 or math.floor(alpha / 16)
        if alpha < 8 then return false end
        local colors = blocks[block]
        if not colors then
            local a, b, c, d = raw.dds:byte(137 + block * 16, 140 + block * 16)
            colors = { channels(a + b * 256), channels(c + d * 256), {}, {} }
            for channel = 1, 3 do
                colors[3][channel] = (2 * colors[1][channel] + colors[2][channel]) / 3
                colors[4][channel] = (colors[1][channel] + 2 * colors[2][channel]) / 3
            end
            blocks[block] = colors
        end
        local indices = raw.dds:byte(141 + block * 16 + math.floor(index / 4))
        local color = colors[math.floor(indices / 4 ^ (index % 4)) % 4 + 1]
        return math.max(color[1], color[2], color[3]) >= 128
    end
end

-- Each row of visible pixels becomes a closed outline. ImGui owns normal text layout and editing.
local function outline(code, ink)
    if code == 32 then return '', 0, 0, 0 end
    local index, rectangles = code - 32, {}
    local u, v = index % 64 * 16, math.floor(index / 64) * 16
    local left, bottom, right, top = 16, 16, 0, 0
    for y = 0, 15 do
        local start
        for x = 0, 16 do
            local filled = x < 16 and ink(u + x, v + y)
            if filled and not start then start = x end
            if not filled and start then
                rectangles[#rectangles + 1] = { start, y, x, y + 1 }
                left, bottom, right, top = math.min(left, start), math.min(bottom, y), math.max(right, x), math.max(top, y + 1)
                start = nil
            end
        end
    end
    if #rectangles == 0 then return nil end
    local ends, xs, ys, last_x, last_y = {}, {}, {}, 0, 0
    for i, r in ipairs(rectangles) do
        ends[i] = u16(i * 4 - 1)
        for _, point in ipairs({ { r[1], r[4] }, { r[1], r[2] }, { r[3], r[2] }, { r[3], r[4] } }) do
            local x, y = point[1] * 64, (13 - point[2]) * 64
            xs[#xs + 1], ys[#ys + 1] = u16(x - last_x), u16(y - last_y)
            last_x, last_y = x, y
        end
    end
    return words({ #rectangles, left * 64, (13 - top) * 64, right * 64, (13 - bottom) * 64 })
        .. table.concat(ends) .. u16(0) .. string.rep('\1', #rectangles * 4)
        .. table.concat(xs) .. table.concat(ys), #rectangles * 4, #rectangles, left * 64
end

local function names(family)
    local labels = { { 1, family }, { 2, 'Regular' }, { 4, family }, { 6, family:gsub(' ', '') } }
    local records, strings, offset = {}, {}, 0
    for _, label in ipairs(labels) do
        local text = label[2]:gsub('.', function(c) return '\0' .. c end)
        records[#records + 1] = words({ 3, 1, 0x409, label[1], #text, offset })
        strings[#strings + 1], offset = text, offset + #text
    end
    return words({ 0, #labels, 6 + #labels * 12 }) .. table.concat(records) .. table.concat(strings)
end

function menu_fonts.generate(raw, name)
    if not kinds[name] then return nil, 'No client menu font has that name.' end
    local face, problem = require('ui.client_fonts').parse(raw, { id = 1, width = 1024, height = 2048 })
    if not face then return nil, problem end
    local ink = ink_reader(raw)
    local glyphs, locations, metrics, length, points, contours = {}, {}, {}, 0, 0, 0
    for glyph_index = 0, 95 do
        local code = glyph_index == 0 and 63 or glyph_index + 31
        local data, count, rings, bearing = outline(code, ink)
        if not data then return nil, 'The client font is missing a printable English character.' end
        points, contours = math.max(points, count), math.max(contours, rings)
        locations[#locations + 1] = u32(length)
        glyphs[#glyphs + 1] = pad(data)
        metrics[#metrics + 1] = words({ face.glyphs[code].advance * 64, bearing })
        length = length + #pad(data)
    end
    locations[#locations + 1] = u32(length)
    local segments = 4
    local cmap = words({ 4, 16 + segments * 8, 0, segments * 2, 8, 2, 0 })
        .. words({ 126, 160, 65533, 65535, 0 }) .. words({ 32, 160, 65533, 65535 })
        .. words({ -31, -159, 35, 1 }) .. string.rep('\0', segments * 2)
    local tables = {
        ['OS/2'] = words({ 0, 512, 400, 5, 0, 650, 600, 0, 75, 650, 600, 0, 350, 50, 300, 0 })
            .. string.rep('\0', 10) .. u32(1) .. string.rep('\0', 12) .. 'VNTG'
            .. words({ 64, 32, 65533, 832, -192, 0, 832, 192 }),
        cmap = words({ 0, 1, 3, 1 }) .. u32(12) .. cmap,
        glyf = table.concat(glyphs),
        head = u32(0x10000) .. u32(0x10000) .. u32(0) .. u32(0x5F0F3CF5) .. words({ 3, 1024 })
            .. string.rep('\0', 16) .. words({ 0, -192, 1024, 832, 0, 16, 2, 1, 0 }),
        hhea = u32(0x10000) .. words({ 832, -192, 0, 1024, 0, 0, 1024, 1, 0, 0, 0, 0, 0, 0, 0, 96 }),
        hmtx = table.concat(metrics), loca = table.concat(locations),
        maxp = u32(0x10000) .. words({ 96, points, contours, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0 }),
        name = names(name .. ' Menu'),
        post = u32(0x30000) .. u32(0) .. words({ -128, 64 }) .. string.rep('\0', 20),
    }
    local tags, directory, data = {}, {}, {}
    for tag in pairs(tables) do tags[#tags + 1] = tag end
    table.sort(tags)
    local offset, head_offset = 12 + #tags * 16
    for _, tag in ipairs(tags) do
        local value = tables[tag]
        directory[#directory + 1] = tag .. u32(checksum(value)) .. u32(offset) .. u32(#value)
        data[#data + 1] = pad(value)
        if tag == 'head' then head_offset = offset end
        offset = offset + #pad(value)
    end
    local output = u32(0x10000) .. words({ #tags, 128, 3, #tags * 16 - 128 }) .. table.concat(directory) .. table.concat(data)
    if #output > MAX_FONT then return nil, 'The generated menu font exceeded its size limit.' end
    output = output:sub(1, head_offset + 8) .. u32(0xB1B0AFBA - checksum(output)) .. output:sub(head_offset + 13)
    return output
end

local function read(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local ok, value = pcall(file.read, file, MAX_FONT + 1)
    local closed, result = pcall(file.close, file)
    return ok and closed and result and type(value) == 'string' and #value <= MAX_FONT and value or nil
end

-- Sixteen hex digits for text: its Adler-32 sum and a second running sum, so two names rarely match.
local function digest(text)
    local a, b, c = 1, 0, 0
    for at = 1, #text do
        local byte = text:byte(at)
        a = (a + byte) % 65521; b = (b + a) % 65521
        c = (c * 31 + byte) % 4294967291
    end
    return ('%08x%08x'):format(b * 65536 + a, c)
end

local function word(bytes, at) local a, b = bytes:byte(at, at + 1); return a * 256 + b end
local function long(bytes, at) return word(bytes, at) * 65536 + word(bytes, at + 2) end

-- The tables the directory at the start of bytes lists, each with its tag, checksum, offset and length, or nil when
-- the directory is cut short or a table lies outside a file size bytes long. bytes need only hold the header and the
-- directory.
local function tables_of(bytes, size)
    if #bytes < 12 then return nil end
    local count = word(bytes, 5)
    if count == 0 or 12 + count * 16 > #bytes then return nil end
    local list = {}
    for i = 0, count - 1 do
        local at = 13 + i * 16
        local offset, length = long(bytes, at + 8), long(bytes, at + 12)
        if offset < 12 + count * 16 or offset + length > size then return nil end
        list[#list + 1] = { tag = bytes:sub(at, at + 3), sum = long(bytes, at + 4), offset = offset, length = length }
    end
    return list
end

-- Whether bytes are a whole font as generate writes it: every table inside the file, each table's checksum and
-- the whole file's as they should be. A file cut short or damaged fails.
local function intact(bytes)
    if type(bytes) ~= 'string' or #bytes < 12 or #bytes > MAX_FONT or #bytes % 4 ~= 0 then return false end
    if long(bytes, 1) ~= 0x10000 or word(bytes, 5) ~= #TABLES then return false end
    local tables = tables_of(bytes, #bytes)
    if not tables then return false end
    local found = {}
    for _, entry in ipairs(tables) do
        if entry.offset % 4 ~= 0 then return false end
        local value = bytes:sub(entry.offset + 1, entry.offset + entry.length)
        -- The head table's own sum leaves out the whole-file adjustment written into it last.
        if entry.tag == 'head' then
            if entry.length < 54 then return false end
            value = value:sub(1, 8) .. '\0\0\0\0' .. value:sub(13)
        end
        if checksum(value) ~= entry.sum then return false end
        found[entry.tag] = true
    end
    for _, tag in ipairs(TABLES) do if not found[tag] then return false end end
    return checksum(bytes) == 0xB1B0AFBA
end

-- The first four bytes of the fonts ImGui reads: TrueType, OpenType with CFF outlines, and the older Apple TrueType tag.
local FONT_TAGS = { ['\0\1\0\0'] = true, OTTO = true, ['true'] = true }

local function head_of(file)
    local size = file:seek('end')
    file:seek('set', 0)
    local head = file:read(12) or ''
    local count = #head == 12 and word(head, 5) or 0
    return size, head .. (count > 0 and file:read(count * 16) or '')
end

-- Whether the font file at path holds every table its directory lists, read from its header and directory alone. A
-- file cut short, as a broken download is, fails, so ImGui never reads past its end. True, or nil and why.
function menu_fonts.check(path)
    local file = io.open(path, 'rb')
    if not file then return nil, 'The font file could not be opened.' end
    local ok, size, bytes = pcall(head_of, file)
    pcall(file.close, file)
    if not ok or type(size) ~= 'number' or type(bytes) ~= 'string' then return nil, 'The font file could not be read.' end
    if not FONT_TAGS[bytes:sub(1, 4)] then return nil, 'The file is not a TrueType or OpenType font.' end
    if not tables_of(bytes, size) then return nil, 'The font file is cut short or damaged.' end
    return true
end

local function cache_folder()
    if not AshitaCore or not ashita or not ashita.fs then return nil end
    local root = AshitaCore:GetInstallPath()
    if type(root) ~= 'string' or root == '' then return nil end
    return require('core.identity').path('cache/client-fonts')
end

-- bytes written to path through a temporary file, so a reader never sees half a file. Returns path and whether it
-- was written now, or nil and why.
local function cache(bytes, path)
    if read(path) == bytes then return path, false end
    local folder = path:match('^(.*)/[^/]+$')
    local ok, exists = pcall(ashita.fs.exists, folder)
    if not ok or not exists then
        local made
        ok, made = pcall(ashita.fs.create_dir, folder)
        if not ok or made == false then
            local checked, present = pcall(ashita.fs.exists, folder)
            if not checked or not present then return nil, 'The local menu-font cache could not be created.' end
        end
    end
    local ffi, process = require('ffi'), 0
    if ffi.os == 'Windows' then
        pcall(ffi.cdef, [[unsigned long __stdcall GetCurrentProcessId(void);
            int __stdcall MoveFileExA(const char*, const char*, unsigned long);]])
        local got, value = pcall(ffi.C.GetCurrentProcessId)
        if got then process = tonumber(value) or 0 end
    end
    local temp
    repeat
        serial = serial + 1
        temp = path .. '.' .. process .. '.' .. serial .. '.tmp'
    until not ashita.fs.exists(temp)
    local file = io.open(temp, 'wb')
    if not file then return nil, 'The local menu font could not be cached.' end
    local wrote, result = pcall(file.write, file, bytes)
    local closed, closing = pcall(file.close, file)
    if not wrote or not result or not closed or not closing or read(temp) ~= bytes then
        os.remove(temp); return nil, 'The local menu font could not be cached.'
    end
    local moved
    if ffi.os == 'Windows' then
        ok, result = pcall(ffi.C.MoveFileExA, temp, path, 9)
        moved = ok and result ~= 0
    else
        ok, result = pcall(os.rename, temp, path)
        moved = ok and result ~= nil
    end
    if not moved then os.remove(temp); return nil, 'The local menu-font cache could not be replaced.' end
    return path, true
end

-- Once a new font for kind is cached at keep, the kind's other cached fonts were made for a client file that has
-- changed since, so they are removed. Only this folder's files named as this code names them are touched:
-- <kind>-v2- then 16 hex digits then .ttf.
local function remove_stale(folder, kind, keep)
    local listed, names = pcall(ashita.fs.get_directory, (folder:gsub('/', '\\')), '.*\\.ttf$', false)
    if not listed or type(names) ~= 'table' then return end
    local kept, pattern = keep:match('[^/]+$'):lower(), '^' .. kind .. '%-v2%-' .. ('%x'):rep(16) .. '%.ttf$'
    for _, name in ipairs(names) do
        if type(name) == 'string' and name:lower() ~= kept and name:match(pattern) then
            os.remove(folder .. '/' .. name)
        end
    end
end

-- The cached font for kind's source file, named for that file's path, size and last write time. Nil when that
-- file cannot be looked at; the font is then named for its own bytes once made.
local function source_path(where, assets, kind)
    local identity = where and assets.source_identity and assets.source_identity(kind)
    if type(identity) ~= 'string' then return nil end
    local key = digest('generator ' .. GENERATOR .. '|' .. kind .. '|' .. identity)
    return where .. '/' .. kind .. '-v2-' .. key .. '.ttf'
end

local function pixels(assets, kind)
    if assets.font_pixels then return assets.font_pixels(kind) end
    return assets.raw(kind, 'moji')
end

-- A cache file holds this, then why, in place of a font its client file can't make, so that file isn't read and
-- tried again at every load. A changed client file is named anew and tried again.
local FAILED = 'Vantage could not make this menu font.\n'

-- The font file for kind: the cached one when it is whole, so no client file is read, else one made from the
-- client's pixels and cached. Returns its path, or nil and why.
local function font_file(assets, kind, name)
    local where = cache_folder()
    local path = source_path(where, assets, kind)
    local held = path and read(path)
    if held and intact(held) then return path end
    if held and held:sub(1, #FAILED) == FAILED then return nil, held:sub(#FAILED + 1) end
    local raw, why, was_read = pixels(assets, kind)
    local ok, bytes, problem = pcall(menu_fonts.generate, raw, name)
    -- Nothing else at load is made from these pixels; the bitmap face lets its own go once it is made.
    if assets.release_pixels then assets.release_pixels(kind, 'moji') end
    if not ok or not bytes then
        local reason = not ok and 'The menu font could not be made.' or raw and problem or why or problem
        -- Only a client file that was read and can't make a font is noted; a read that failed may work next time.
        if path and (raw or was_read) then cache(FAILED .. tostring(reason), path) end
        return nil, reason
    end
    if not where then return nil, 'The menu-font cache folder is unavailable.' end
    local cached, written = cache(bytes, path or where .. '/' .. kind .. '-v2-' .. digest(bytes) .. '.ttf')
    if not cached then return nil, written end
    if written and intact(read(cached)) then remove_stale(where, kind, cached) end
    return cached
end

-- Called once while startup font loading is allowed. Draw-time accessors never read or write files.
-- load(path, size, sharp) adds a font file to ImGui. These are whole pixels at 16, so they ask to be drawn sharp.
function menu_fonts.prepare(load)
    if prepared then return end
    prepared = true
    local assets = require('ui.client_assets')
    for name, kind in pairs(kinds) do
        local ok, path, why = pcall(font_file, assets, kind, name)
        local result = { path = ok and path or nil, reason = not ok and 'The menu font could not be made.' or why }
        if ok and path then
            local loaded, face = pcall(load, path, 16, true)
            if loaded and face then faces[name] = face
            else result.reason = 'ImGui could not load the menu font.' end
        end
        results[name] = result
    end
end

function menu_fonts.face(name) return faces[name] end

-- Each menu font for /vg report: its cached file, whether ImGui took it, and why not when it didn't.
function menu_fonts.report()
    local out = {}
    for name in pairs(kinds) do
        local result = results[name]
        out[name] = result and { path = result.path, loaded = faces[name] ~= nil, reason = result.reason }
            or { loaded = false, reason = 'The menu fonts are made at load.' }
    end
    return out
end

return menu_fonts
