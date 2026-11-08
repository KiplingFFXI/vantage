-- /load while a character whose saved look uses XI View is in the game: the load event makes only XI View's menu
-- font, and the first refresh reads the settings, which ask the warmup for XI View. The next Present's steps read,
-- parse and upload the rest of it (its fonts, frame font and pointer, status icons and action icons) before any
-- display draws, and the first draw, in the Present after, finds it all, so no frame after reads any of it.
package.loaded['core.performance'] = {
    now = function() return MOCK.now * 1000 end,
    record = function() return true end,
    add = function() return true end,
    zone_begin = function() return true end, zone_ready = function() return true end,
    snapshot = function() return {} end,
    origin_ms = 0,
}
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

local store, defaults, appearance = require('core.store'), require('ui.defaults'), require('ui.appearance')
local folder = MOCK_INSTALL_PATH .. '/config/addons/vantage/'
local view = defaults.make()
assert(appearance.apply(view, 'XI View', { matching = true }))
assert(store.write(folder .. 'Tester_1001/settings.json', view))

-- What of XI View the first draw finds.
local hud = require('ui.hud')
local draw, first = hud.draw, nil
hud.draw = function(...)
    if not first then
        local loaded_fonts, loaded_icons, loaded_actions = loaded()
        first = { fonts = loaded_fonts, icons = loaded_icons, actions = loaded_actions,
            faces = require('ui.client_fonts').available('XI View') }
    end
    return draw(...)
end
local app = dofile(ADDON_DIR .. '/vantage.lua')
assert(not app.state.path, 'Before /load no settings are read.')
MOCK.fire('load')
local fonts, icons, actions = loaded()
assert(not fonts and not icons and not actions and not reads[view_root .. '/ROM/119/57.DAT'],
    "The load event loads none of XI View's art.")
MOCK.frame()
assert(app.state.path == folder .. 'Tester_1001/settings.json' and app.state.ready == false and not first,
    'The first Present reads the settings and draws nothing.')
fonts, icons, actions = loaded()
assert(not fonts and not icons and not actions, 'It runs no step.')
MOCK.frame()
fonts, icons, actions = loaded()
assert(fonts and icons and actions, "The next Present's steps load XI View for the saved look.")
assert(reads[view_root .. '/ROM/119/57.DAT'] == 1 and reads[view_root .. '/ROM/280/15.DAT'] == 1, 'Its icon files are read then.')
assert(require('ui.client_fonts').available('XI View'),
    'Its faces are made then.')
assert(not first and app.state.ready == false, 'The Present that made them draws nothing.')
MOCK.frame()
assert(first and first.fonts and first.icons and first.actions and first.faces, 'The first draw, in the next Present, finds all of it.')
local before = view_reads()
MOCK.frame()
MOCK.frame()
assert(view_reads() == before, 'The frames after read nothing more.')

return 'A saved XI View look loads XI View in the warmup, before the first draw'
