-- Icons on XI View with no XI View overlay set up: the Artwork fold and Party list's Look tab ask icons.reason('XI View')
-- each frame, and the note that it falls back to Original FFXI makes no garbage.
local assets, icons = require('ui.client_assets'), require('ui.icons')
local function le16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
local function le32(n) return le16(n % 65536) .. le16(math.floor(n / 65536)) end
local function record(bits, pixels)
    local data = string.rep('\0', 0x280) .. le32(57 + #pixels) .. '\145' .. string.rep(' ', 16)
        .. le32(40) .. le32(32) .. le32(32) .. le16(1) .. le16(bits)
        .. string.rep('\0', 24) .. pixels
    return data .. string.rep('\0', 0x1800 - #data)
end
local stock = record(32, string.rep('\0\0\255\128', 1024))
assets._set_platform_for_tests({
    game_root = function() return 'C:/Fixture' end,
    ashita_root = function() return 'C:/FixtureAshita' end,
    read = function(filename) if filename == 'C:/Fixture/ROM/119/57.DAT' then return stock end; return nil, 'missing' end,
    upload = function() return { id = 77, release = function() end } end,
})
icons.prepare()
local reason = icons.reason('XI View')
assert(reason and reason:find('Falling back to Original FFXI', 1, true), 'Fixture: XI View is missing and falls back: ' .. tostring(reason))
-- The JIT's own traces are garbage too, so it is off while counting, and a few calls run after the collection first.
jit.off(); jit.flush()
for _ = 1, 50 do icons.reason('XI View') end
collectgarbage('collect'); collectgarbage('collect'); collectgarbage('stop')
for _ = 1, 6 do icons.reason('XI View') end
local before = collectgarbage('count')
for _ = 1, 600 do icons.reason('XI View') end
local grown = collectgarbage('count') - before
collectgarbage('restart')
jit.on()
assert(grown < 1, ('icons.reason on a missing XI View makes %.1f KB in 600 frames'):format(grown))
assert(icons.reason('XI View') == reason, 'The note is the same.')
assets._set_platform_for_tests(nil)
return 'The XI View fallback note makes no garbage'
