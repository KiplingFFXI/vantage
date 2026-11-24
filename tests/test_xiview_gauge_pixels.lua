-- A look that uses XI View only for its gauges (the Original FFXI skin with Gauges on XI View) loads XI View's font
-- file for its art, and no XI View face is made. So nothing would let that file's 2 MB of font pixels go, and the
-- warmup lets them go once the art is up. A later switch to the XI View font still makes its face, from the file read
-- again. A look with the XI View font keeps them for its face, which lets them go itself.
local dat = require('dat_fixture')
local texture, upvalue = dat.texture, dat.upvalue
local font_dat = texture('font    moji    ', 1024, 2048) .. texture('menu    gauge   ', 64, 64)
local window_dat = texture('menu    newtex  ', 128, 128) .. texture('menu    hfr1    ', 32, 32)
    .. texture('menu    corner  ', 32, 32) .. texture('menu    vfr1    ', 32, 32)
local stock_path, view_path = 'C:/Fixture/ROM/119/51.DAT', 'C:/FixtureView/ROM/119/51.DAT'
local files = { [stock_path] = font_dat, [view_path] = font_dat, ['C:/Fixture/ROM/0/14.DAT'] = window_dat }
local reads = {}
local assets = require('ui.client_assets')
assets._set_platform_for_tests({
    game_root = function() return 'C:/Fixture' end,
    ashita_root = function() return 'C:/FixtureAshita' end,
    xiview_path = function() return view_path end,
    read = function(filename)
        reads[filename] = (reads[filename] or 0) + 1
        return files[filename], 'No fixture asset.'
    end,
    upload = function(_, _, _, label) return { id = 900 + #label, release = function() end } end,
})
local moji = 'font    moji    '
local function kept() return upvalue(assets.clear, 'state').xiview_font.data.textures[moji].dds end

-- The stock warmup makes the stock face, which lets the stock pixels go.
for _, step in ipairs(require('ui.fonts').warmup_steps()) do step.run() end

local defaults, appearance, client_fonts = require('ui.defaults'), require('ui.appearance'), require('ui.client_fonts')
local function warm(font)
    local settings = defaults.make()
    assert(appearance.apply(settings, 'Original FFXI', { matching = true }))
    settings.style.gauge_art, settings.style.font = 'XI View', font
    assert(appearance.uses_xiview(settings), 'Fixture: the look uses XI View.')
    for _, step in ipairs(appearance.warmup_steps()) do step.run() end
    assert(assets.texture('xiview_font', 'gauge'), 'Fixture: the XI View gauge art is up.')
end

-- Gauges alone: no face, and the pixels go after the art step.
warm('Original FFXI')
assert(reads[view_path] == 1 and not client_fonts.current('XI View'), 'Fixture: XI View art read once, and no face made.')
local held = kept()
assert(held == nil, 'XI View font pixels kept with no face to make them: ' .. tostring(held and #held) .. ' bytes')
local raw = upvalue(assets.clear, 'state').xiview_font.data.textures[moji]
assert(raw.width == 1024 and raw.height == 2048, 'Their size stays.')
-- A later switch to the XI View font makes its face from the file read again, and it draws.
assert(client_fonts.available('XI View') and reads[view_path] == 2, 'The XI View face is made from the file read again.')
local drawn
local list = { AddImageQuad = function(_, id) drawn = id end, AddImage = function(_, id) drawn = id end }
assert(client_fonts.draw(list, 'XI View', 'Aster', 0, 0, 16, 0xFFFFFFFF) and drawn, 'That face draws.')
assert(kept() == nil, 'Nothing keeps the pixels read again.')

-- With the XI View font, the art step keeps the pixels for the face that follows, which reads no file again.
assets.clear()
warm('XI View')
assert(client_fonts.current('XI View') and reads[view_path] == 3, 'The face is made from the pixels the art step read.')
assert(kept() == nil, 'The face lets them go.')
assets.clear()
return 'XI View gauges alone keep no font pixels'
