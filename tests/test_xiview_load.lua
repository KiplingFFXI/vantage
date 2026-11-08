-- A character whose saved look uses XI View loads all of XI View outside any frame: during /load, or on the zone-in
-- packet that brings it in after /load (a character change, or /load before logging in): its fonts, frame font and
-- pointer, its status icons and its action icons, so neither its first frame nor its first buff waits for them. A
-- settings read inside a frame loads nothing more, and a character not using XI View, or using it only on a display
-- that is off, still leaves it for its first use.
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
local glyphs = 'font    fontshp ' .. '\1' .. 'font    font    ' .. u16(95) .. table.concat(parts)
local font_dat = texture('font    moji    ', 1024, 2048) .. texture('font    font    ', 256, 256)
    .. texture('menu    gauge   ', 4, 4) .. texture('menu    colorbal', 4, 4) .. texture('menu    anc     ', 4, 4)
    .. chunk(0x31, glyphs)
local stock_root, view_root = 'C:/Fixture', 'C:/FixtureView'
local view_font = view_root .. '/ROM/119/51.DAT'
local files = { [stock_root .. '/ROM/119/51.DAT'] = font_dat .. texture('menu    menu2fon', 128, 128), [view_font] = font_dat }
local reads = {}
local assets = require('ui.client_assets')
assets._set_platform_for_tests({
    game_root = function() return stock_root end,
    ashita_root = function() return 'C:/FixtureAshita' end,
    xiview_path = function() return view_font end,
    read = function(filename)
        reads[filename] = (reads[filename] or 0) + 1
        return files[filename], 'No fixture asset.'
    end,
    upload = function(dds) return { id = 700 + #dds % 97, release = function() end } end,
})
local function view_reads()
    local total = 0
    for filename, count in pairs(reads) do if filename:sub(1, #view_root) == view_root then total = total + count end end
    return total
end
local function upvalue(fn, wanted)
    for index = 1, 200 do
        local name, value = debug.getupvalue(fn, index)
        if name == wanted then return value end
        if not name then break end
    end
end
-- What of XI View is loaded: its fonts (deferred until read), its status icons and its action icons.
local function loaded()
    local state = upvalue(assets.clear, 'state')
    local icons = upvalue(assets.clear_icons, 'icon_sources')
    local packs = upvalue(require('ui.action_icons').clear, 'packs')
    return state.xiview_font ~= nil and not state.xiview_font.deferred, icons ~= nil and icons.xiview ~= nil,
        packs ~= nil and packs.xiview ~= nil
end

-- Two characters: Tester plays the default look, Viewer saved XI View.
local store, defaults, appearance = require('core.store'), require('ui.defaults'), require('ui.appearance')
local folder = MOCK_INSTALL_PATH .. '/config/addons/vantage/'
local plain = defaults.make()
assert(not appearance.uses_xiview(plain), 'The fresh look does not use XI View.')
assert(store.write(folder .. 'Tester_1001/settings.json', plain))
local view = defaults.make()
assert(appearance.apply(view, 'XI View', { matching = true }) and appearance.uses_xiview(view), 'The XI View look uses it.')
assert(store.write(folder .. 'Viewer_1002/settings.json', view))
-- One XI View piece anywhere that is on is enough, such as the party list buffs' own icons. A display that is off
-- draws nothing.
local piece = defaults.make(); piece.party_ui.style.icon_art = 'XI View'
piece.party_ui.enabled = false
assert(not appearance.uses_xiview(piece), 'Party list buffs that are off do not use their XI View icons.')
piece.party_ui.enabled = true
assert(appearance.uses_xiview(piece), 'Party list buffs with XI View icons use it.')

-- /load while Tester is in the game: XI View is left for its first use. (Its menu font is still made at load from
-- the XI View font file, as before.)
local app = dofile(ADDON_DIR .. '/vantage.lua')
MOCK.fire('load')
local fonts, icons, actions = loaded()
assert(not fonts and not icons and not actions, 'A character without XI View leaves it for its first use at /load.')
app.refresh(1)
fonts, icons, actions = loaded()
assert(app.state.path == folder .. 'Tester_1001/settings.json' and not fonts and not icons and not actions,
    'And when its settings load.')

-- Viewer comes in. Its settings read inside a frame loads nothing more of XI View there: that frame would wait for
-- all of it.
MOCK.player.name, MOCK.player.server_id = 'Viewer', 1002
local before = view_reads()
app.refresh(2)
assert(app.state.path == folder .. 'Viewer_1002/settings.json', 'Viewer\'s settings load.')
fonts, icons, actions = loaded()
assert(not fonts and not icons and not actions and view_reads() == before, 'A settings read in a frame loads no XI View.')
-- The zone-in packet that brings Viewer in, before its first frame there: every XI View piece is read then.
local function zone_in(id, name)
    local bytes = MOCK.bytes(0x104)
    MOCK.put(bytes, 4, 4, id)
    MOCK.put(bytes, 0x30, 2, 230)
    for index = 1, #name do bytes[0x84 + index - 1] = name:byte(index) end
    return MOCK.packet(0x00A, bytes)
end
assert(require('core.client').zone_in_identity(zone_in(1002, 'Viewer')) == 1002
    and select(2, require('core.client').zone_in_identity(zone_in(1002, 'Viewer'))) == 'Viewer', 'Fixture: the packet names Viewer.')
MOCK.fire('packet_in', zone_in(1001, 'Tester'))
fonts, icons, actions = loaded()
assert(not fonts and not icons and not actions and view_reads() == before, 'Tester coming in loads no XI View.')
MOCK.fire('packet_in', zone_in(1002, 'Viewer'))
fonts, icons, actions = loaded()
assert(fonts and icons and actions, 'Its XI View fonts, status icons and action icons load on the zone-in that brings it in.')
assert(reads[view_root .. '/ROM/119/57.DAT'] == 1 and reads[view_root .. '/ROM/280/15.DAT'] == 1 and view_reads() > before,
    'Their files are read then.')
before = view_reads()
MOCK.fire('packet_in', zone_in(1002, 'Viewer'))
assert(view_reads() == before, 'The next zone-in reads nothing more.')
app.refresh(3)
assert(require('ui.client_fonts').available('XI View'),
    'The XI View faces are made.')
before = view_reads()
MOCK.events.d3d_present.vantage_present()
assert(view_reads() == before, 'Its first frame reads nothing more.')
return 'A saved XI View look loads XI View outside any frame, and other looks leave it for first use'
