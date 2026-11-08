local layout = {}

local finite = require('ui.numbers').finite
local clear = require('table.clear')

-- Read each frame, so the keys are kept here.
local CHAT_KEYS = { 'x', 'y', 'width', 'height' }
function layout.chat(context)
    local rect = context and context.chat
    if type(rect) ~= 'table' or rect.visible == false then return nil end
    for _, key in ipairs(CHAT_KEYS) do if not finite(rect[key]) then return nil end end
    return rect.width > 0 and rect.height > 0 and rect or nil
end

-- The game's chat log on a width x height screen: the client's chat windows when Vantage can read them (rect, as
-- core.chat gives it), otherwise where the main one usually sits, at the bottom left, scaled from 1920 x 1080.
local USUAL_CHAT, usual = { 16, 821, 1086, 1044 }, nil
function layout.chat_area(width, height, rect)
    local chat = layout.chat({ chat = rect })
    if chat or not (finite(width) and finite(height) and width > 0 and height > 0) then return chat end
    if not usual or usual.screen_width ~= width or usual.screen_height ~= height then
        local sx, sy = width / 1920, height / 1080
        usual = { x = USUAL_CHAT[1] * sx, y = USUAL_CHAT[2] * sy, width = (USUAL_CHAT[3] - USUAL_CHAT[1]) * sx,
            height = (USUAL_CHAT[4] - USUAL_CHAT[2]) * sy, windows = {}, usual = true, screen_width = width, screen_height = height }
    end
    return usual
end

-- Where the game's own party list and target window sit on a width x height screen: the bottom right corner a full
-- party and the target window above it take on the user's client at 1920 x 1080 (from x 1780 and y 880 to the
-- screen's edges), scaled to the screen.
local USUAL_NATIVE, native = { 1780, 880 }, nil
function layout.native_corner(width, height)
    if not (finite(width) and finite(height) and width > 0 and height > 0) then return nil end
    if not native or native.screen_width ~= width or native.screen_height ~= height then
        local x, y = USUAL_NATIVE[1] * width / 1920, USUAL_NATIVE[2] * height / 1080
        native = { x = x, y = y, width = width - x, height = height - y, screen_width = width, screen_height = height }
    end
    return native
end

function layout.clamp(rect, width, height)
    rect.width, rect.height = math.min(rect.width, width), math.min(rect.height, height)
    rect.x, rect.y = math.max(0, math.min(rect.x, width - rect.width)), math.max(0, math.min(rect.y, height - rect.height))
    return rect
end

local function overlaps(rect, other)
    return rect.x < other.x + other.width and rect.x + rect.width > other.x
        and rect.y < other.y + other.height and rect.y + rect.height > other.y
end

-- Whether rect lies on any of the chat log's windows. One kept table hands each window to layout.chat.
local window_context = {}
local function on_windows(rect, chat)
    if type(chat.windows) ~= 'table' then return false end
    for _, window in pairs(chat.windows) do
        window_context.chat = window
        local readable = layout.chat(window_context)
        window_context.chat = nil
        if readable and overlaps(rect, window) then return true end
    end
    return false
end

-- What one resolve works with, set as it starts. The panels placed so far, and those being placed, which stops a loop of
-- anchors, are kept and cleared, so a frame makes no table or function for them.
local done, active = {}, {}
local panels_now, rectangles_now, settings_now, width_now, height_now, chat_now

local function place(key)
    local rect, panel = rectangles_now[key], panels_now[key]
    if not rect or done[key] then return rect end
    if active[key] then return nil end
    active[key] = true
    local anchor = panel.anchor
    if settings_now and type(anchor) == 'table' and anchor.to ~= nil and anchor.to ~= 'none' then
        -- A panel drawn this frame is placed first; any other display is where it was last drawn.
        local target = anchor.to == 'element' and rectangles_now[anchor.element] and place(anchor.element) or nil
        if anchor.to ~= 'element' or target or not rectangles_now[anchor.element] then
            local elements, spot_x, spot_y = require('ui.elements'), rect.x, rect.y
            if elements.place(settings_now, key, rect, width_now, height_now, target) and anchor.to == 'chat'
                and anchor.gap >= 0 and chat_now then
                -- A panel beside the chat log never covers it: pushed onto it at the screen's edge, or onto
                -- another of its windows, it is at its own spot. Only a gap below 0 asks for that.
                layout.clamp(rect, width_now, height_now)
                if overlaps(rect, chat_now) or on_windows(rect, chat_now) then
                    rect.x, rect.y = spot_x, spot_y
                    elements.unplace(key)
                end
            end
        end
    end
    layout.clamp(rect, width_now, height_now)
    active[key], done[key] = nil, true
    return rect
end

-- settings holds each panel's anchor (core/anchors.lua).
function layout.resolve(panels, rectangles, context, width, height, settings)
    clear(done)
    clear(active)
    panels_now, rectangles_now, settings_now, width_now, height_now = panels, rectangles, settings, width, height
    chat_now = layout.chat(context)
    for key in pairs(rectangles) do place(key) end
    panels_now, rectangles_now, settings_now, chat_now = nil, nil, nil, nil
    return rectangles
end

if VANTAGE_TEST_MODE then
    function layout.grip(rect, x, y, size)
        size = size or 8
        local right, bottom = x >= rect.x + rect.width - size, y >= rect.y + rect.height - size
        return right and bottom and 'both' or right and 'width' or bottom and 'height' or nil
    end
end

return layout
