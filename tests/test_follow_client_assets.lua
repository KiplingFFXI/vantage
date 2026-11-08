local assets = require('ui.client_assets')
local function le16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
local function le32(n) return le16(n % 65536) .. le16(math.floor(n / 65536)) end
local function chunk(kind, payload)
    local length = math.ceil((16 + #payload) / 16) * 16
    return 'TEST' .. le32(length / 16 * 128 + kind) .. string.rep('\0', 8)
        .. payload .. string.rep('\0', length - 16 - #payload)
end
local function texture(name)
    return chunk(0x20, '\161' .. name .. le32(40) .. le32(4) .. le32(4)
        .. string.rep('\0', 28) .. '3TXD' .. le32(16) .. le32(0) .. string.rep('\0', 16))
end
local font = texture('font    moji    ') .. texture('font    font    ') .. texture('menu    gauge   ')
    .. texture('menu    menu2fon') .. texture('menu    keytop  ') .. texture('menu    colorbal')
    .. texture('anc     anc     ') .. texture('menu    acre    ')
    .. chunk(0x31, 'font    fontshp ' .. '\0\0\0')
local window = texture('menu    newtex  ') .. texture('menu    hfr1    ')
    .. texture('menu    corner  ') .. texture('menu    vfr1    ')
local function icon(value)
    local bytes = string.rep('\0', 0x280) .. le32(4153) .. '\145' .. string.rep(' ', 16)
        .. le32(40) .. le32(32) .. le32(32) .. le16(1) .. le16(32)
        .. string.rep('\0', 24) .. string.rep(string.char(value, 0, 0, 255), 1024)
    return bytes .. string.rep('\0', 0x1800 - #bytes)
end
local action_name = 'white   cure    '
local action = texture(action_name) .. chunk(0x31, 'menu    magiconw' .. '\0\0\0')
local secondary = texture(action_name) .. chunk(0x31, 'menu    magico2w' .. '\0\0\0')
local game, root, overlay_root = 'C:/Client', 'C:/Ashita', 'C:/Mods'
local era, view, third = overlay_root .. '/EraDATs', overlay_root .. '/XiView-Standard', overlay_root .. '/Other Art'
local common, status, primary, second = '/ROM/119/51.DAT', '/ROM/119/57.DAT', '/ROM/280/15.DAT', '/ROM/324/95.DAT'
local config_path = root .. '/config/pivot/pivot.ini'
local files = {
    [config_path] = '[settings]\nroot_path=C:/Mods\n[overlays]\n2=Other Art\n0=EraDATs\n1=XiView-Standard\n',
    [game .. common] = font, [view .. common] = font,
    [game .. status] = icon(1), [view .. status] = icon(2), [era .. status] = icon(3),
    [game .. primary] = action, [view .. primary] = action,
    [game .. second] = secondary, [third .. second] = secondary,
    [era .. '/ROM/0/15.DAT'] = window,
}
for index = 14, 21 do files[game .. '/ROM/0/' .. index .. '.DAT'] = window end
local reads, uploads, releases = {}, 0, 0
local api = {
    game_root = function() return game end,
    ashita_root = function() return root end,
    read = function(filename, limit)
        reads[filename] = (reads[filename] or 0) + 1
        assert(limit <= 16 * 1024 * 1024)
        return files[filename], 'Fixture file missing.'
    end,
    upload = function(data, width, height)
        assert(data:sub(1, 4) == 'DDS ' and width == height)
        uploads = uploads + 1
        return { id = uploads, release = function() releases = releases + 1 end }
    end,
}
local function clean()
    assets.clear()
    assert(uploads == releases, 'Every shared or independent texture is released exactly once.')
    assets.clear()
    assert(uploads == releases, 'Repeated cleanup cannot release aliases twice.')
    reads = {}
end
assets._set_platform_for_tests(api)
local normal_manager, pol_manager = AshitaCore.GetPluginManager, AshitaCore.GetPolPluginManager
AshitaCore.GetPluginManager = function() error('Manual artwork must not query plugin activation.') end
AshitaCore.GetPolPluginManager = AshitaCore.GetPluginManager
assert(assets.prepare())
assert(assets.status('original_font').path == game .. common)
assert(assets.status('xiview_font').path == view .. common)
for index = 1, 8 do
    assert(assets.status('window', index).path == game .. '/ROM/0/' .. (13 + index) .. '.DAT')
end
assert(not assets.status('client_font').available and not assets.cached_texture('client_font', 'moji'), 'There are no automatic banks.')
assert(not reads[era .. common] and not reads[third .. common], 'Unrelated overlays never replace manually selected fonts.')
assets.prepare_icons()
assert(assets.icon_status('original').path == game .. status)
assert(assets.icon_status('xiview').path == view .. status)
assert(not assets.icon_status('client').available)
assets.prepare_actions()
assert(assets.action_layout('original', 'main'))
assert(assets.action_layout('xiview', 'main'))
local before_reads, before_uploads = {}, uploads
for key, count in pairs(reads) do before_reads[key] = count end
for i = 1, 100 do
    assets.prepare(); assets.prepare_icons(); assets.prepare_actions()
    assets.cached_texture('original_font', 'moji'); assets.cached_texture('xiview_font', 'moji')
end
assert(require('core.customization').equal(reads, before_reads) and uploads == before_uploads,
    'Prepared manual artwork performs no repeated file reads or uploads.')
clean()
files[view .. common] = nil
assert(assets.prepare() and assets.status('original_font').available and not assets.status('xiview_font').available)
clean()
files[view .. common] = font
files[config_path] = '[overlays]\n0=../XiView-Outside\n1=C:/XiView-Outside\n'
assert(not assets.status('xiview_font').available, 'Invalid pack paths are rejected.')
clean()
files[config_path] = '[settings]\nroot_path=C:/Mods\n[overlays]\n0=XiView-Standard\n'
assert(assets.status('xiview_font').available, 'Clearing assets allows a newly available manual pack to be discovered.')
clean()
AshitaCore.GetPluginManager, AshitaCore.GetPolPluginManager = normal_manager, pol_manager
assets._set_platform_for_tests(nil)
return 'Manual client asset discovery, no automatic banks, and cleanup'
