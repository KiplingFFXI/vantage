local assets = require('ui.client_assets')
local theme = require('ui.theme')
local skin = {}
local prepared_menu

local finite = require('ui.numbers').finite

-- Every piece fills these before it draws. The binding copies a vector when it is called and keeps none.
local p1, p2, t1, t2 = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }

local function image(list, texture, x, y, w, h, u, v, uw, vh, color)
    if w <= 0 or h <= 0 then return end
    p1[1], p1[2], p2[1], p2[2] = x, y, x + w, y + h
    t1[1], t1[2], t2[1], t2[2] = u / texture.width, v / texture.height, (u + uw) / texture.width, (v + vh) / texture.height
    list:AddImage(texture.id, p1, p2, t1, t2, color)
end

local function tile(list, texture, x, y, w, h, u, v, uw, vh, scale, color)
    if w <= 0 or h <= 0 then return end
    local step_x, step_y = uw * scale, vh * scale
    for top = y, y + h - 0.01, step_y do
        for left = x, x + w - 0.01, step_x do
            local tw, th = math.min(step_x, x + w - left), math.min(step_y, y + h - top)
            image(list, texture, left, top, tw, th, u, v, tw / scale, th / scale, color)
        end
    end
end

function skin.active(style)
    return style.theme == 'Original FFXI'
end

-- Keep texture pieces at their own size, including partial tiles at the edges.
-- background and border, when given, replace style.background and style.border for this box.
function skin.panel(list, rect, style, colors, opacity, background, border)
    if not skin.active(style) or style.minimal then return false end
    if background == nil then background = style.background end
    if border == nil then border = style.border end
    local bg, corner = assets.texture('window', 'newtex', style.window_type), assets.texture('window', 'corner', style.window_type)
    local horizontal, vertical = assets.texture('window', 'hfr1', style.window_type), assets.texture('window', 'vfr1', style.window_type)
    if not bg or not corner or not horizontal or not vertical then return false end
    colors = colors or {}
    local x, y, w, h = rect.x, rect.y, rect.width, rect.height
    local scale = style.scale
    opacity = opacity or style.opacity
    if background then
        tile(list, bg, x, y, w, h, 0, 0, 128, 128, scale, theme.u32(colors.background or style.background_color, opacity))
    end
    if border then
        local c = math.min(16 * scale, w / 2, h / 2)
        local tint = theme.u32(colors.border or style.border_color, opacity)
        image(list, corner, x, y, c, c, 0, 0, 16, 16, tint)
        image(list, corner, x + w - c, y, c, c, 16, 0, 16, 16, tint)
        image(list, corner, x, y + h - c, c, c, 0, 16, 16, 16, tint)
        image(list, corner, x + w - c, y + h - c, c, c, 16, 16, 16, 16, tint)
        tile(list, horizontal, x + c, y, w - 2 * c, c, 0, 0, 32, 16, c / 16, tint)
        tile(list, horizontal, x + c, y + h - c, w - 2 * c, c, 0, 16, 32, 16, c / 16, tint)
        tile(list, vertical, x, y + c, c, h - 2 * c, 0, 0, 16, 32, c / 16, tint)
        tile(list, vertical, x + w - c, y + c, c, h - 2 * c, 16, 0, 16, 32, c / 16, tint)
    end
    return true
end

-- What the last prepare found, filled in place each time so a frame makes no table for it. skin.menu reads it once.
local last_prepare = { look = nil, suppressed = false }
local menu_pieces = { 'newtex', 'corner', 'hfr1', 'vfr1' }

local function background_setter(imgui)
    return imgui.SetNextWindowBgAlpha
end

-- Probe shared draw methods without activating ImGui's implicit Debug window.
local function draw_list_ready(imgui)
    local list = imgui.GetBackgroundDrawList()
    local x1, y1 = list:GetClipRectMin()
    local x2, y2 = list:GetClipRectMax()
    if type(list.PushClipRect) ~= 'function' or type(list.PopClipRect) ~= 'function'
        or type(list.AddImage) ~= 'function' or type(list.AddRectFilled) ~= 'function'
        or type(list.AddTriangleFilled) ~= 'function' then return false end
    return finite(x1) and finite(y1) and finite(x2) and finite(y2)
end

-- Only the next explicit window loses its plain backdrop. Internal widget popups keep theirs.
function skin.prepare_menu(imgui, look)
    last_prepare.look, last_prepare.suppressed = look, false
    prepared_menu = last_prepare
    if not look or look.theme ~= 'Original FFXI' then return false end
    local setter_ok, setter = pcall(background_setter, imgui)
    if not setter_ok or setter == nil then return false end
    for _, name in ipairs(menu_pieces) do
        if not assets.texture('window', name, look.window_type) then return false end
    end
    local ok, capable = pcall(draw_list_ready, imgui)
    if not ok or not capable then return false end
    local applied = pcall(setter, 0)
    last_prepare.suppressed = applied
    return applied
end

-- What paint_menu paints with, filled in place each time so a frame makes no table or closure for it. The binding
-- copies a vector when it is called and keeps none, and skin.panel keeps neither the box nor the style.
local menu_box, menu_style = { x = 0, y = 0, width = 0, height = 0 }, { scale = 1, opacity = 1, background = true, border = true }
local clip_min, clip_max, point_a, point_b, point_c, no_colors = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, {}

local function clip_bounds(draw)
    local a, b = draw:GetClipRectMin()
    local c, d = draw:GetClipRectMax()
    return a, b, c, d
end

-- The window's draw list, position and size, and its clip. A fallback paint uses the window's own box when the clip
-- can't be read.
local function window_box(imgui, fallback)
    local draw = imgui.GetWindowDrawList()
    local wx, wy = imgui.GetWindowPos()
    local ww, wh = imgui.GetWindowSize()
    local bounds_ok, x1, y1, x2, y2 = pcall(clip_bounds, draw)
    if not bounds_ok or not finite(x1) or not finite(y1) or not finite(x2) or not finite(y2) then
        if not fallback then error('The draw clip is unavailable.') end
        x1, y1, x2, y2 = wx, wy, wx + ww, wy + wh
    end
    return draw, wx, wy, ww, wh, x1, y1, x2, y2
end

local function fill(list, look, kind, fallback)
    if fallback then
        point_a[1], point_a[2] = menu_box.x, menu_box.y
        point_b[1], point_b[2] = menu_box.x + menu_box.width, menu_box.y + menu_box.height
        list:AddRectFilled(point_a, point_b, theme.u32(theme.window_paint(look, kind == 'window' and 'background' or 'dropdowns')), 0)
        return true
    end
    return skin.panel(list, menu_box, menu_style, no_colors)
end

-- One part of the box, clipped to x1, y1, x2, y2, and whether it painted.
local function paint(list, look, kind, fallback, x1, y1, x2, y2)
    if x2 <= x1 or y2 <= y1 then return false end
    clip_min[1], clip_min[2], clip_max[1], clip_max[2] = x1, y1, x2, y2
    list:PushClipRect(clip_min, clip_max, true)
    local success, result = pcall(fill, list, look, kind, fallback)
    list:PopClipRect()
    if not success then error(result) end
    return result
end

-- The grip corner's color, worked out again only for a new look. A look is only read, and the settings window makes a
-- new one when the settings change (theme.window), so a frame makes no table for it.
local grip_look, grip_color

local function grip_corner(list, look, cut_x, cut_y, far_x, far_y)
    if grip_look ~= look then grip_look, grip_color = look, theme.u32(theme.window_paint(look, 'background')) end
    point_a[1], point_a[2], point_b[1], point_b[2], point_c[1], point_c[2] = cut_x, cut_y, far_x, cut_y, cut_x, far_y
    list:AddTriangleFilled(point_a, point_b, point_c, grip_color)
end

-- Paint before the controls, in their own window layer. ImGui keeps ownership of its chrome.
local function paint_menu(imgui, look, kind, fallback)
    if not look or look.theme ~= 'Original FFXI' then return false end
    if kind ~= 'window' and kind ~= 'popup' and kind ~= 'tooltip' then return false end
    local ok, list, x, y, width, height, left, top, right, bottom = pcall(window_box, imgui, fallback)
    if not ok then return false end
    if not finite(x) or not finite(y) or not finite(width) or not finite(height) or not finite(left) or not finite(top)
        or not finite(right) or not finite(bottom) then return false end
    if width <= 0 or height <= 0 then return false end
    local frame = kind == 'window' and imgui.GetFrameHeight() or 0
    if type(frame) ~= 'number' or frame < 0 or frame ~= frame or frame == math.huge then return false end
    left, top = math.max(left, x), math.max(top, y + frame)
    right, bottom = math.min(right, x + width), math.min(bottom, y + height)
    if left >= right or top >= bottom then return false end
    menu_box.x, menu_box.y, menu_box.width, menu_box.height = left, top, right - left, bottom - top
    menu_style.theme, menu_style.window_type, menu_style.border_color = look.theme, look.window_type, look.border
    menu_style.background_color = kind == 'window' and look.background or look.dropdowns
    if kind ~= 'window' then return paint(list, look, kind, fallback, left, top, right, bottom) end
    local gui_style = imgui.GetStyle and imgui.GetStyle() or nil
    local rounding = gui_style and gui_style.WindowRounding or 0
    -- ImGui draws the resize grip in Begin, before this paint, so the corner triangle under it stays unpainted.
    local grip = math.max(frame * 1.5, rounding + frame * 0.25)
    local cut_x, cut_y = x + width - grip, y + height - grip
    local painted = paint(list, look, kind, fallback, left, top, right, math.min(bottom, cut_y))
    painted = paint(list, look, kind, fallback, left, math.max(top, cut_y), math.min(right, cut_x), bottom) or painted
    if cut_x < right and cut_y < bottom then
        clip_min[1], clip_min[2], clip_max[1], clip_max[2] = left, top, right, bottom
        list:PushClipRect(clip_min, clip_max, true)
        local success, problem = pcall(grip_corner, list, look, cut_x, cut_y, x + width, y + height)
        list:PopClipRect()
        if not success then error(problem) end
    end
    return painted
end

function skin.menu(imgui, look, kind)
    -- The settings window's tooltips and lists come here, so a sample drawn over the window steps back from them.
    if kind == 'tooltip' or kind == 'popup' then require('ui.resize').cover(imgui, kind == 'popup') end
    local prepared = prepared_menu
    prepared_menu = nil
    if prepared and prepared.look == look and not prepared.suppressed then return false end
    local ok, painted = pcall(paint_menu, imgui, look, kind, false)
    if not ok or not painted then
        if prepared and prepared.look == look and prepared.suppressed then
            paint_menu(imgui, look, kind, true)
        elseif not ok then
            error(painted)
        end
        return false
    end
    return true
end

local function valid_gauge(kind)
    local texture = assets.texture(kind, 'gauge')
    if texture and texture.width == 64 and texture.height == 64 then return texture end
end

local function gauge_texture(gauge_art)
    if gauge_art == 'XI View' then
        local texture = valid_gauge('xiview_font')
        if texture then return texture end
    end
    return valid_gauge('original_font')
end

-- track, when given, is the track tint to use instead of the panel's.
function skin.gauge(list, x, y, width, height, fraction, style, panel, color, track)
    if not skin.active(style) or panel.gradient or panel.bar_style == 'full' then return false end
    local texture = gauge_texture(style.gauge_art)
    if not texture then return false end
    local cap = math.min(4 * height / 8, width / 2)
    local body = width - 2 * cap
    track = theme.u32(track or panel.colors.track or style.track_color, style.opacity)
    image(list, texture, x, y, cap, height, 0, 8, 4, 8, track)
    image(list, texture, x + cap, y, body, height, 0, 0, 64, 8, track)
    image(list, texture, x + width - cap, y, cap, height, 4, 8, 4, 8, track)
    if fraction and fraction > 0 and body > 0 then
        local fill = math.max(0, math.min(1, fraction))
        local inset = height / 8
        local left = x + cap + (panel.fill_direction == 'left' and body * (1 - fill) or 0)
        image(list, texture, left, y + inset, body * fill, height - 2 * inset,
            0, 0, 64, 8, theme.u32(color, style.opacity))
    end
    return true
end

-- The client window's color, made once: callers only read it.
local NATIVE_BACKGROUND = { 49 / 255, 48 / 255, 90 / 255, 1 }
function skin.fallback_background(style, override)
    if override then return override end
    if skin.active(style) then return NATIVE_BACKGROUND end
    return style.background_color
end

function skin.window_reason(window_type)
    local status = assets.status('window', window_type)
    return not status.available and status.reason or nil
end

function skin.gauge_reason(style)
    if style.gauge_art ~= 'XI View' then return nil end
    local name = 'XI View'
    local selected = assets.texture('xiview_font', 'gauge')
    if selected and selected.width == 64 and selected.height == 64 then return nil end
    if gauge_texture('Original FFXI') then return name .. ' gauge artwork is unavailable. Stock client gauges are being used.' end
    return name .. ' and stock client gauge artwork are unavailable. Regular bars are being used.'
end

function skin.reason(window_type, gauge_art)
    local why = skin.window_reason(window_type)
    if why then return why end
    if not gauge_texture(gauge_art) then return 'The client gauge artwork is unavailable.' end
end

return skin
