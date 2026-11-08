-- An action icon looks up each of its parts' textures every time it is drawn (assets.action_texture), so a lookup of
-- one already made makes no table: the files it looks in are kept lists. Measured as test_menu_paint_allocation.lua
-- does.
local assets = require('ui.client_assets')
local function le16(v) v = v % 65536; return string.char(v % 256, math.floor(v / 256)) end
local function le32(v) return le16(v % 65536) .. le16(math.floor(v / 65536)) end
local function chunk(kind, payload)
    local n = math.ceil((16 + #payload) / 16) * 16
    return 'TEST' .. le32(n / 16 * 128 + kind) .. string.rep('\0', 8) .. payload .. string.rep('\0', n - 16 - #payload)
end
local function texture(name)
    return chunk(0x20, string.char(0xA1) .. name .. le32(40) .. le32(32) .. le32(32) .. string.rep('\0', 28)
        .. '3TXD' .. le32(1024) .. le32(0) .. string.rep('\0', 1024))
end
-- A layout with one shape of one part, as the client's action files hold them.
local base, tier = 'white   cure    ', 'misc    numsx   '
local function layout(name)
    local values = { 0, 0, 16, 0, 0, 16, 16, 16, 32, 32, 0, 0 }
    local part = {}
    for _, v in ipairs(values) do part[#part + 1] = le16(v) end
    part = table.concat(part) .. '\0' .. string.rep(string.char(127, 64, 32, 127), 4) .. '\1\0\1\1' .. base
    return name .. '\2' .. base .. tier .. le16(1) .. '\1' .. part
end
local files = {
    ['C:/Game/ROM/280/15.DAT'] = texture(base) .. chunk(0x31, layout('menu    magiconw')),
    ['C:/Game/ROM/324/95.DAT'] = texture(base) .. chunk(0x31, layout('menu    magico2w')),
    ['C:/Game/ROM/119/51.DAT'] = texture('menu    acre    '),
}
local uploads = 0
assets._set_platform_for_tests({
    game_root = function() return 'C:/Game' end,
    ashita_root = function() return 'C:/Ashita' end,
    read = function(path) return files[path], 'No fixture file.' end,
    upload = function() uploads = uploads + 1; return { id = 100 + uploads } end,
})
assets.prepare_actions()
local made = assets.action_texture('original', false, base, 255)
local second = assets.action_texture('original', true, base, 255)
assert(made and second and uploads == 2, 'Fixture: a main and a secondary texture are made.')

local function run(count)
    for _ = 1, count do
        assert(assets.action_texture('original', false, base, 255) == made
            and assets.action_texture('original', true, base, 255) == second)
    end
end
jit.off(); jit.flush()
run(60)
collectgarbage('collect'); collectgarbage('collect')
collectgarbage('stop')
run(6)
local before = collectgarbage('count')
run(2000)
local each = (collectgarbage('count') - before) / 4000
collectgarbage('restart')
jit.on()
assert(uploads == 2, 'Fixture: nothing is made again.')
assert(each < 0.0005, ('Looking up an action texture makes %.4f KB each time; nothing expected'):format(each))
assets.clear()
return 'Action texture lookups make no table'
