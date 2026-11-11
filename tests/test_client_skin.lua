local available, missing_gauge = true, false
local requested_types, status_types = {}, {}
local textures = {}
for _, name in ipairs({ 'newtex', 'corner', 'hfr1', 'vfr1', 'gauge' }) do
    local size = name == 'newtex' and 128 or name == 'gauge' and 64 or 32
    textures[name] = { id = name, width = size, height = size }
end
package.loaded['ui.client_assets'] = {
    texture = function(kind, name, window_type)
        if kind == 'window' then requested_types[#requested_types + 1] = window_type or 1 end
        return available and not (name == 'gauge' and missing_gauge) and textures[name] or nil
    end,
    status = function(_, window_type)
        status_types[#status_types + 1] = window_type or 1
        return { available = available, reason = 'Test assets missing.' }
    end,
}
local skin = require('ui.client_skin')
local theme = require('ui.theme')
local defaults = require('ui.defaults')
local original_skin = require('original_skin_fixture')
local s = defaults.make()
s.style.minimal = true
original_skin(s)
assert(theme.window_paint(theme.window(s), 'background')[1] < 0.3 and theme.window(s).text[1] == 1,
    'Texture tint colors must not create white-on-white settings controls.')
assert(theme.window(s).theme == 'Original FFXI')
assert(theme.apply(s, 'Classic FFXI'))
assert(not skin.active(s.style) and s.style.font == 'Original FFXI', 'Theme selection keeps the independent font choice.')
local classic = theme.colors('Classic FFXI')
assert(classic.background_color[1] == 16 / 255 and classic.border_color[1] == 118 / 255)
original_skin(s)
local images = {}
local list = { AddImage = function(_, id, start, finish, uv1, uv2, color)
    local copy = MOCK.copy_vector
    images[#images + 1] = { id = id, start = copy(start), finish = copy(finish), uv1 = copy(uv1), uv2 = copy(uv2), color = color }
end }
local rect = { x = 17, y = 29, width = 301, height = 117 }
assert(not skin.panel(list, rect, s.style, {}), 'Minimal must skip all outer artwork.')
assert(#images == 0)
s.style.minimal = false
assert(skin.panel(list, rect, s.style, {}))
assert(#images > 8)
for _, image in ipairs(images) do
    assert(image.start[1] >= rect.x and image.start[2] >= rect.y)
    assert(image.finish[1] <= rect.x + rect.width + 0.01 and image.finish[2] <= rect.y + rect.height + 0.01)
    assert(image.uv1[1] >= 0 and image.uv1[2] >= 0 and image.uv2[1] <= 1 and image.uv2[2] <= 1)
end
assert(images[1].finish[1] - images[1].start[1] == 128, 'Background texture is tiled at its own pixel size.')
images = {}
assert(skin.panel(list, { x = 0, y = 0, width = 9, height = 6 }, s.style, {}), 'Short boxes stay bounded.')
local p = s.panels.self_buffs
images = {}
assert(skin.gauge(list, 10, 20, 108, 8, 0.25, s.style, p, { 1, 1, 1, 1 }))
assert(#images == 4 and images[4].finish[1] - images[4].start[1] == 25)
assert(images[4].start[1] == 14 and images[4].start[2] == 21)
p.fill_direction = 'left'
images = {}
assert(skin.gauge(list, 10, 20, 108, 8, 0.25, s.style, p, { 1, 1, 1, 1 }))
assert(images[4].start[1] == 89)
images = {}
assert(skin.gauge(list, 10, 20, 108, 8, nil, s.style, p, { 1, 1, 1, 1 }))
assert(#images == 3, 'Unknown duration draws only the track, never a made-up fill.')
p.gradient = true
assert(not skin.gauge(list, 10, 20, 108, 8, 0.5, s.style, p, { 1, 1, 1, 1 }), 'Custom gradients keep their existing drawing path.')
available = false
assert(not skin.panel(list, rect, s.style, {}))
assert(skin.reason() == 'Test assets missing.')
assert(skin.fallback_background(s.style)[1] == 49 / 255)
assert(skin.fallback_background(s.style, { 0.2, 0.3, 0.4, 1 })[1] == 0.2)

available = true
requested_types = {}
s.style.window_type = 7
assert(skin.panel(list, rect, s.style, {}))
for _, chosen in ipairs(requested_types) do assert(chosen == 7, 'HUD artwork uses its selected window type.') end
missing_gauge = true
assert(skin.window_reason(3) == nil and status_types[#status_types] == 3,
    'Menus do not report an unrelated gauge failure.')
assert(skin.reason(3) == 'The client gauge artwork is unavailable.')
missing_gauge = false

local frame_height, rounding, clip_depth, font_size = 20, 0, 0, 16
local window_bounds, clip_bounds = { 10, 30, 400, 300 }, { 12, 50, 398, 320 }
local active_clip, recorded, triangles, fallbacks = nil, {}, {}, {}
local draw = {
    GetClipRectMin = function() return clip_bounds[1], clip_bounds[2] end,
    GetClipRectMax = function() return clip_bounds[3], clip_bounds[4] end,
    PushClipRect = function(_, first, last, intersect)
        assert(intersect == true, 'The menu must respect the current window or popup clip.')
        clip_depth = clip_depth + 1
        active_clip = { first[1], first[2], last[1], last[2] }
    end,
    PopClipRect = function() clip_depth = clip_depth - 1; active_clip = nil end,
    AddImage = function(_, id, first, last, _, _, tint)
        assert(active_clip and clip_depth == 1)
        local x1, y1 = math.max(first[1], active_clip[1]), math.max(first[2], active_clip[2])
        local x2, y2 = math.min(last[1], active_clip[3]), math.min(last[2], active_clip[4])
        if x2 > x1 and y2 > y1 then recorded[#recorded + 1] = { id = id, x1 = x1, y1 = y1, x2 = x2, y2 = y2, tint = tint } end
    end,
    AddTriangleFilled = function(_, a, b, c, tint)
        assert(active_clip and clip_depth == 1)
        triangles[#triangles + 1] = { a, b, c, tint }
    end,
    AddRectFilled = function(_, first, last, tint)
        assert(active_clip and clip_depth == 1)
        fallbacks[#fallbacks + 1] = { first, last, tint }
    end,
}
local gui = {
    GetWindowDrawList = function() return draw end,
    GetWindowPos = function() return window_bounds[1], window_bounds[2] end,
    GetWindowSize = function() return window_bounds[3], window_bounds[4] end,
    GetFrameHeight = function() return frame_height end,
    GetFontSize = function() return font_size end,
    GetStyle = function() return { WindowRounding = rounding } end,
    Begin = function() error('The menu painter must not create or replace a window.') end,
    GetBackgroundDrawList = function() error('The menu painter must not escape popup ordering.') end,
    GetForegroundDrawList = function() error('The menu painter must not cover unrelated windows.') end,
}
local look = { theme = 'Original FFXI', window_type = 6, background = { 0.8, 0.6, 0.4, 0.5 },
    dropdowns = { 0.4, 0.7, 1, 0.75 }, border = { 1, 0.2, 0.4, 0.8 } }
s.style.minimal = true
requested_types = {}
assert(skin.menu(gui, look, 'window') and #recorded > 0 and clip_depth == 0,
    'Native settings artwork is independent of Minimal HUD mode and keeps clip calls balanced.')
-- ImGui's resize grip reaches floor(max(font * 1.10, rounding + 1 + font * 0.2)) along the bottom and right edges from
-- the window's corner, here 17 from 410, 330. The art stops at that square and no further from the corner, as the
-- window has no backdrop of its own and anything left bare shows the game.
local function corner_filled(reach, label)
    local cut_x, cut_y = 410 - reach, 330 - reach
    assert(#triangles == 1, label .. ': one fill beside the grip.')
    local a, b, c = triangles[1][1], triangles[1][2], triangles[1][3]
    assert(a[1] == cut_x and a[2] == cut_y and b[1] == 411 and b[2] == cut_y and c[1] == cut_x and c[2] == 331,
        label .. ': the half of the square the grip leaves is filled, a pixel past the long edge of the grip.')
    local above, beside = false, false
    for _, painted in ipairs(recorded) do
        assert(not (painted.x2 > cut_x and painted.y2 > cut_y), label .. ': the native resize corner must stay visible.')
        if painted.id == 'newtex' then
            above = above or painted.x2 == 398 and painted.y2 == math.min(320, cut_y)
            beside = beside or painted.x2 == math.min(398, cut_x) and painted.y2 == 320
        end
    end
    assert(above and beside, label .. ': the art reaches the square from above and from its left.')
end
corner_filled(17, 'Font 16')
for _, chosen in ipairs(requested_types) do assert(chosen == 6, 'Settings artwork has its own selected window type.') end
for _, painted in ipairs(recorded) do
    assert(painted.x1 >= 12 and painted.y1 >= 50 and painted.x2 <= 398 and painted.y2 <= 320,
        'Menu paint stays below the title and inside the existing clip, leaving scrollbar space intact.')
    assert(painted.tint == theme.u32(painted.id == 'newtex' and look.background or look.border),
        'Independent background and border colors tint the artwork.')
end
-- A taller title bar doesn't widen the square: the grip follows the font and the corner rounding alone.
frame_height, recorded, triangles = 40, {}, {}
assert(skin.menu(gui, look, 'window'))
corner_filled(17, 'A tall title bar')
frame_height, font_size, recorded, triangles = 20, 32, {}, {}
assert(skin.menu(gui, look, 'window'))
corner_filled(35, 'Font 32')
font_size, rounding, recorded, triangles = 16, 20, {}, {}
assert(skin.menu(gui, look, 'window'))
corner_filled(24, 'Rounded corners')
rounding = 0
-- With Shift held ImGui draws no grip, so the whole body is painted and nothing is cut.
recorded, triangles = {}, {}
assert(skin.menu(gui, look, 'window', true) and #triangles == 0 and clip_depth == 0)
local whole = false
for _, painted in ipairs(recorded) do whole = whole or painted.id == 'newtex' and painted.x2 == 398 and painted.y2 == 320 end
assert(whole, 'A window with no resize grip is painted to its corner.')
for _, bad in ipairs({ 0, -16, 0 / 0, math.huge, 'big' }) do
    font_size, recorded, triangles = bad, {}, {}
    assert(not skin.menu(gui, look, 'window') and #recorded == 0 and #triangles == 0 and clip_depth == 0,
        'A font size that is no size paints nothing.')
end
font_size = 16

recorded, requested_types = {}, {}
look.window_type = 8
window_bounds, clip_bounds = { 200, 100, 120, 90 }, { 201, 101, 309, 189 }
assert(skin.menu(gui, look, 'popup') and #recorded > 0 and clip_depth == 0)
local covers_bottom_right = false
for _, painted in ipairs(recorded) do
    assert(painted.x1 >= 201 and painted.y1 >= 101 and painted.x2 <= 309 and painted.y2 <= 189)
    assert(painted.tint == theme.u32(painted.id == 'newtex' and look.dropdowns or look.border),
        'Popup tint uses the dropdown customization, not the main background.')
    covers_bottom_right = covers_bottom_right or painted.x2 == 309 and painted.y2 == 189
end
assert(covers_bottom_right, 'Non-resizable popups use their full clipped body.')
for _, chosen in ipairs(requested_types) do assert(chosen == 8) end
recorded = {}
assert(skin.menu(gui, look, 'tooltip') and #recorded > 0 and clip_depth == 0)
recorded = {}
look.theme = 'Classic FFXI'
assert(not skin.menu(gui, look, 'window') and #recorded == 0, 'Classic FFXI remains unchanged.')
look.theme = 'Original FFXI'
available = false
assert(not skin.menu(gui, look, 'popup') and #recorded == 0 and clip_depth == 0,
    'Missing assets leave the already rendered readable ImGui fallback untouched.')
available = true
assert(not skin.menu(gui, look, 'invalid'))
clip_bounds = { 400, 400, 500, 500 }
assert(not skin.menu(gui, look, 'popup') and clip_depth == 0, 'An occluded body has no paint area.')
clip_bounds = { 201, 101, 309, 189 }
window_bounds[3] = 0 / 0
assert(not skin.menu(gui, look, 'popup'))
window_bounds[3] = nil
assert(not skin.menu(gui, look, 'popup'), 'Incomplete window geometry must not throw.')
window_bounds[3] = 120
local add_image = draw.AddImage
draw.AddImage = function() error('Injected draw failure') end
assert(not pcall(skin.menu, gui, look, 'popup') and clip_depth == 0,
    'A drawing error must still restore the previous clip before propagating.')
draw.AddImage = add_image

local alpha_calls = {}
gui.SetNextWindowBgAlpha = function(value) alpha_calls[#alpha_calls + 1] = value end
local probe = {
    GetClipRectMin = function() return 0, 0 end,
    GetClipRectMax = function() return 1600, 1200 end,
}
for _, name in ipairs({ 'PushClipRect', 'PopClipRect', 'AddImage', 'AddRectFilled', 'AddTriangleFilled' }) do
    probe[name] = function() error('The global drawlist is inspected only; it must not be painted.') end
end
gui.GetBackgroundDrawList = function() return probe end
local window_draw = gui.GetWindowDrawList
gui.GetWindowDrawList = function() error('Preflight must not activate the implicit Debug window.') end
assert(skin.prepare_menu(gui, look) and alpha_calls[1] == 0,
    'Available native surfaces suppress only the next plain background, so opacity applies once.')
gui.GetWindowDrawList = window_draw
recorded, fallbacks = {}, {}
assert(skin.menu(gui, look, 'popup') and #recorded > 0 and #fallbacks == 0 and clip_depth == 0)
available = false
local alpha_count = #alpha_calls
assert(not skin.prepare_menu(gui, look) and #alpha_calls == alpha_count)
assert(not skin.menu(gui, look, 'popup') and #fallbacks == 0, 'Unavailable textures retain the default background.')
available = true
assert(skin.prepare_menu(gui, look))
available = false
assert(not skin.menu(gui, look, 'popup') and #fallbacks == 1 and clip_depth == 0,
    'If assets disappear after suppression, a bounded fallback restores the body.')
assert(fallbacks[1][3] == theme.u32(theme.window_paint(look, 'dropdowns')))
available = true
assert(skin.prepare_menu(gui, look))
local minimum = draw.GetClipRectMin
draw.GetClipRectMin = function() return {} end
assert(not skin.menu(gui, look, 'popup') and #fallbacks == 2 and clip_depth == 0,
    'A changed clip return shape still gets an intersected fallback after suppression.')
draw.GetClipRectMin = minimum
local probe_minimum = probe.GetClipRectMin
probe.GetClipRectMin = function() return {} end
alpha_count = #alpha_calls
assert(not skin.prepare_menu(gui, look) and #alpha_calls == alpha_count,
    'Unexpected binding return shapes must never cause a false background suppression.')
assert(not skin.menu(gui, look, 'popup'))
probe.GetClipRectMin = probe_minimum
gui.SetNextWindowBgAlpha = nil
assert(not skin.prepare_menu(gui, look) and not skin.menu(gui, look, 'popup'))
return true
