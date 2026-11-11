-- The settings window paints the stock skin under itself, its lists and its tooltips (skin.menu in ui/client_skin.lua)
-- every frame, so painting makes no table or function: what it paints with is filled in place, and the grip corner's
-- color is worked out once for each look. It paints the same each time. Measured as test_menu_prepare_allocation.lua
-- does, on an ImGui whose calls keep nothing.
local bit = require('bit')
rawset(require('imgui'), 'col32', function(a, r, g, b) return bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r) end)
local textures = {}
for _, name in ipairs({ 'newtex', 'corner', 'hfr1', 'vfr1' }) do
    local size = name == 'newtex' and 128 or 32
    textures[name] = { id = name, width = size, height = size }
end
package.loaded['ui.client_assets'] = {
    texture = function(_, name) return textures[name] end,
    status = function() return { available = true } end,
}
local skin, theme, defaults = require('ui.client_skin'), require('ui.theme'), require('ui.defaults')
local s = defaults.make()
require('original_skin_fixture')(s)
local look = theme.window(s)
s.style.window_type = 7
local light = theme.window(s)

local images, triangles, depth, corner = 0, 0, 0, nil
local list = {
    GetClipRectMin = function() return 0, 0 end,
    GetClipRectMax = function() return 1600, 1200 end,
    PushClipRect = function() depth = depth + 1 end,
    PopClipRect = function() depth = depth - 1 end,
    AddImage = function() images = images + 1 end,
    AddRectFilled = function() error('The skin paints with its art here.') end,
    AddTriangleFilled = function(_, _, _, _, color) triangles, corner = triangles + 1, color end,
}
local style = { WindowRounding = 4 }
local gui = {
    GetWindowDrawList = function() return list end,
    GetWindowPos = function() return 100, 80 end,
    GetWindowSize = function() return 420, 300 end,
    GetFrameHeight = function() return 20 end,
    GetFontSize = function() return 16 end,
    GetStyle = function() return style end,
}

-- What one paint of each kind draws, the same every time.
local drawn = {}
for _, kind in ipairs({ 'window', 'popup', 'tooltip' }) do
    images, triangles = 0, 0
    assert(skin.menu(gui, look, kind) and images > 0 and depth == 0, 'Fixture: the ' .. kind .. ' is painted.')
    drawn[kind] = { images, triangles }
end
assert(drawn.window[2] == 1 and drawn.popup[2] == 0 and drawn.tooltip[2] == 0,
    'The window paints the corner under its resize grip; a list or tooltip has none.')
for _, each in ipairs({ look, light, look }) do
    assert(skin.menu(gui, each, 'window') and corner == theme.u32(theme.window_paint(each, 'background')),
        'The grip corner takes each look\'s own background.')
end
assert(theme.u32(theme.window_paint(look, 'background')) ~= theme.u32(theme.window_paint(light, 'background')),
    'Fixture: the two looks differ.')

local function run(kind, count)
    for _ = 1, count do
        images, triangles = 0, 0
        assert(skin.menu(gui, look, kind) and images == drawn[kind][1] and triangles == drawn[kind][2] and depth == 0, kind)
    end
end
local function measure(kind, count)
    jit.off(); jit.flush()
    run(kind, 60)
    collectgarbage('collect'); collectgarbage('collect')
    collectgarbage('stop')
    run(kind, 6)
    local before = collectgarbage('count')
    run(kind, count)
    local each = (collectgarbage('count') - before) / count
    collectgarbage('restart')
    jit.on()
    return each
end
for _, kind in ipairs({ 'window', 'popup', 'tooltip' }) do
    local each = measure(kind, 2000)
    assert(each < 0.0005, ('Painting a %s makes %.4f KB each time; nothing expected'):format(kind, each))
end
return 'The settings window paints its skin without making tables'
