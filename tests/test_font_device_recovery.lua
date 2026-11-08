local function u16(value)
    return string.char(value % 256, math.floor(value / 256) % 256)
end
local function u32(value)
    return u16(value % 65536) .. u16(math.floor(value / 65536))
end
local function chunk(kind, payload)
    local length = math.ceil((16 + #payload) / 16) * 16
    return 'TEST' .. u32(length / 16 * 128 + kind) .. string.rep('\0', 8)
        .. payload .. string.rep('\0', length - 16 - #payload)
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
    local coordinates = { 0, 0, width, 0, 0, 11, width, 11 }
    local out = {}
    for _, value in ipairs(coordinates) do out[#out + 1] = u16(value) end
    out[#out + 1] = u16(width * 2 + 1) .. u16(23) .. u16(0) .. u16(0) .. '\0'
        .. string.rep(string.char(127), 16) .. string.char(1, 0, 1, 1) .. 'font    font    '
    parts[#parts + 1] = '\1' .. table.concat(out)
end
local layout = 'font    fontshp ' .. '\1' .. 'font    font    ' .. u16(95) .. table.concat(parts)
local font_dat = texture('font    moji    ', 1024, 2048) .. texture('font    font    ', 256, 256)
    .. texture('menu    gauge   ', 4, 4) .. chunk(0x31, layout)
local original_pairs = pairs
local store = require('core.store')

for _, first in ipairs({ 'Original FFXI', 'XI View' }) do
    -- Exercise either iteration order independently of Lua's hash seed.
    pairs = function(value)
        if type(value) == 'table' and value['Original FFXI'] == 'original_font' and value['XI View'] == 'xiview_font' then
            local order = { first, first == 'Original FFXI' and 'XI View' or 'Original FFXI' }
            local index = 0
            return function()
                index = index + 1
                local key = order[index]
                if key then return key, value[key] end
            end
        end
        return original_pairs(value)
    end
    local assets = assert(loadfile(ADDON_DIR .. '/ui/client_assets.lua'))()
    package.loaded['ui.client_assets'] = assets
    local reads, uploads, releases, menu_loads = 0, 0, 0, 0
    local live = {}
    assets._set_platform_for_tests({
        game_root = function() return 'C:/Fixture' end,
        ashita_root = function() return 'C:/FixtureAshita' end,
        xiview_path = function() return 'C:/FixtureView/ROM/119/51.DAT' end,
        read = function(filename)
            reads = reads + 1
            if filename:match('/51%.DAT$') then return font_dat end
            return nil, 'No fixture asset.'
        end,
        upload = function()
            uploads = uploads + 1
            local id = uploads
            live[id] = true
            return { id = id, release = function()
                assert(live[id], 'Each managed texture is released once.')
                live[id], releases = nil, releases + 1
            end }
        end,
    })
    local bitmap = assert(loadfile(ADDON_DIR .. '/ui/client_fonts.lua'))()
    package.loaded['ui.client_fonts'] = bitmap
    local menu = assert(loadfile(ADDON_DIR .. '/ui/client_menu_fonts.lua'))()
    bitmap.prepare()
    menu.prepare(function(filename)
        menu_loads = menu_loads + 1
        return { path = filename }
    end)
    local menu_faces = { ['Original FFXI'] = menu.face('Original FFXI'), ['XI View'] = menu.face('XI View') }
    for _, name in ipairs({ 'Original FFXI', 'XI View' }) do
        assert(bitmap.available(name) and menu_faces[name])
    end
    local selections = { font = first, font_size = 32, window_font = first, window_font_size = 17 }
    local saved = store.copy(selections)
    local list = {
        AddImageQuad = function(_, id) assert(live[id], 'Bitmap text uses a current-device texture.') end,
        AddImage = function(_, id) assert(live[id], 'Frame text uses a current-device texture.') end,
    }
    for recovery = 1, 3 do
        -- The device replacement handler clears managed assets without rebuilding the GUI atlas.
        assets.clear()
        assert(next(live) == nil and releases == uploads)
        local previous_reads, previous_uploads = reads, uploads
        assert(bitmap.available(first), 'The first bitmap face recovers after asset initialization.')
        assert(reads > previous_reads and uploads > previous_uploads)
        for _, name in ipairs({ 'Original FFXI', 'XI View' }) do
            assert(bitmap.available(name), 'Both font families recover regardless of iteration order.')
            assert(menu.face(name) == menu_faces[name], 'Device replacement keeps the prepared menu face.')
            assert(bitmap.draw(list, name, 'Aster', 10, 20, 32, 0xFFFFFFFF))
        end
        local ready_reads, ready_uploads = reads, uploads
        for draw = 1, 120 do
            assert(bitmap.measure(selections.font, 'Aster', selections.font_size))
            assert(bitmap.draw(list, selections.font, 'Aster', 10, 20, selections.font_size, 0xFFFFFFFF))
            menu.prepare(function() error('The menu atlas must not be rebuilt during recovery.') end)
        end
        assert(reads == ready_reads and uploads == ready_uploads and menu_loads == 2,
            'Steady draws and same-device use perform no repeated file reads, uploads, or registrations.')
        assert(store.equal(saved, selections), 'Font recovery keeps saved font choices and sizes.')
    end
    assets.clear()
    assert(releases == uploads and next(live) == nil)
end
pairs = original_pairs
return true
