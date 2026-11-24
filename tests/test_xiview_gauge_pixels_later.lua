-- Gauges on XI View picked after login, with a font that isn't XI View: no XI View warmup ran, so the gauge's first draw
-- reads XI View's font file. Its 2 MB of font pixels go once the art is up, as the warmup lets them go, since only a
-- face reads them. A later switch to the XI View font still makes its face, from the file read again. When the face is
-- what asks first, the pixels stay for it, and it lets them go itself.
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
local function raw() return upvalue(assets.clear, 'state').xiview_font.data.textures[moji] end

-- The stock warmup makes the stock face, which lets the stock pixels go.
for _, step in ipairs(require('ui.fonts').warmup_steps()) do step.run() end
local client_fonts = require('ui.client_fonts')

-- The next panel draw asks for the XI View gauge art (client_skin.gauge), with the font left on Original FFXI.
local skin = require('ui.client_skin')
local style = { theme = 'Original FFXI', gauge_art = 'XI View', track_color = { 0, 0, 0, 1 }, opacity = 1 }
local panel = { colors = {}, bar_style = 'rail' }
local list = { AddImage = function() end }
assert(skin.gauge(list, 0, 0, 100, 8, 0.5, style, panel, { 1, 1, 1, 1 }), 'Fixture: the XI View gauge draws.')
assert(reads[view_path] == 1 and not client_fonts.current('XI View'), 'Fixture: XI View art read once, and no face made.')
for _ = 1, 10 do skin.gauge(list, 0, 0, 100, 8, 0.5, style, panel, { 1, 1, 1, 1 }) end
local held = raw().dds
assert(held == nil, 'XI View font pixels kept with no face after a mid-session Gauges pick: ' .. tostring(held and #held) .. ' bytes')
assert(raw().width == 1024 and raw().height == 2048, 'Their size stays.')
assert(reads[view_path] == 1, 'The gauge draws read the file once.')

-- A later switch to the XI View font makes its face from the file read again, and it draws.
assert(client_fonts.available('XI View') and reads[view_path] == 2, 'The XI View face is made from the file read again.')
local drawn
local text_list = { AddImageQuad = function(_, id) drawn = id end, AddImage = function(_, id) drawn = id end }
assert(client_fonts.draw(text_list, 'XI View', 'Aster', 0, 0, 16, 0xFFFFFFFF) and drawn, 'That face draws.')
assert(raw().dds == nil, 'Nothing keeps the pixels read again.')

-- The XI View font asked for first: its first use keeps the pixels for the face, which reads no file again.
assets.clear()
for _, step in ipairs(require('ui.fonts').warmup_steps()) do step.run() end
reads[view_path] = 0
assert(assets.texture('xiview_font', 'moji') and raw().dds ~= nil, 'The font\'s own first use keeps the pixels for its face.')
assert(client_fonts.available('XI View') and reads[view_path] == 1, 'The face is made from them, with no second read.')
assert(raw().dds == nil, 'The face lets them go.')
assets.clear()
return 'XI View gauges picked later keep no font pixels'
