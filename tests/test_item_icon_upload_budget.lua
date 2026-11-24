-- New item pictures spend the same budget of new icon textures each Present as status and action icons do
-- (client_assets.spend_upload). One past it is made in a later Present with no retry wait, and a recast row counts it
-- as drawn meanwhile, so nothing is put in its place.
local bit = require('bit')
rawset(require('imgui'), 'col32', function(a, r, g, b) return bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r) end)
local assets, items, recasts = require('ui.client_assets'), require('ui.item_icons'), require('ui.recast_icons')
local loads = 0
items._set_loader_for_tests(function(item)
    loads = loads + 1
    return 7000 + item, function() end
end)

assets.icon_frame()
for item = 1, 8 do assert(items.texture(item) == 7000 + item, 'Fixture: eight new pictures in one Present.') end
local texture, waiting = items.texture(9)
assert(texture == nil and waiting == true and loads == 8, 'A ninth new picture in that Present waits for a later one.')
assert(items.texture(1) == 7001 and loads == 8, 'A picture already made still draws.')
assets.icon_frame()
assert(items.texture(9) == 7009 and loads == 9, 'It is made in the next Present, with no retry wait.')

-- Status and action icons spend the same budget.
assets.icon_frame()
for _ = 1, 8 do assert(assets.spend_upload(), 'Fixture: eight new icons in one Present.') end
assert(items.texture(10) == nil and loads == 9, 'An item picture waits behind them.')

-- A recast row whose picture waits draws nothing and counts as drawn.
local drawn = {}
local list = { AddImage = function(_, id) drawn[#drawn + 1] = id end }
local row = { kind = 'item', item_id = 11, recast_id = 11 }
assert(recasts.draw(list, row, 'Original FFXI', 0, 0, 32, 1) == true and #drawn == 0 and loads == 9,
    'A waiting item picture counts as drawn, with nothing in its place.')
assets.icon_frame()
assert(recasts.draw(list, row, 'Original FFXI', 0, 0, 32, 1) == true and drawn[1] == 7011 and loads == 10,
    'It draws in the next Present.')

-- A picture that can't be made still waits its retry time, and a row without it still says so.
items._set_loader_for_tests(function() loads = loads + 1; return false end)
assets.icon_frame()
local missing = { kind = 'item', item_id = 12, recast_id = 12 }
assert(recasts.draw(list, missing, 'Original FFXI', 0, 0, 32, 1) == false and loads == 11, 'A failed picture is not drawn.')
assets.icon_frame()
assert(recasts.draw(list, missing, 'Original FFXI', 0, 0, 32, 1) == false and loads == 11, 'It is not tried again at once.')
items.clear()
return 'Item pictures spend the per-Present upload budget'
