local controls = {}

-- The label of a slider, list or text box, on the left of the row with the control filling the rest. The column is 42
-- percent of the page, up to 24 times the font size, so a very wide window leaves no big gap. A label too long for its
-- column, or a page under 420 pixels wide, goes above a full-width control. What follows it sets the control's width to
-- -1 either way. gui is passed in, as the settings window's own helpers, the main page, the panel frame and the alert
-- editor use this too.
function controls.label(gui, label)
    local available, width = gui.GetContentRegionAvail(), gui.CalcTextSize(label)
    local column = math.floor(math.min(available * 0.42, 24 * gui.GetFontSize()))
    if available < 420 or width + 10 > column then
        gui.TextWrapped(label)
        return
    end
    if gui.AlignTextToFramePadding then gui.AlignTextToFramePadding() end
    gui.TextUnformatted(label)
    gui.SameLine(0, column - width)
end

-- A tick box or radio button in a thin outline, as an empty one on some skins is the color of the page behind it. look
-- is the settings window's.
local function outline(gui, look)
    gui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1)
    gui.PushStyleColor(ImGuiCol_Border, look.heading_lines)
end

local function plain(gui)
    gui.PopStyleColor()
    gui.PopStyleVar()
end

function controls.checkbox(gui, look, label, value)
    outline(gui, look)
    local clicked = gui.Checkbox(label, value)
    plain(gui)
    return clicked
end

function controls.radio(gui, look, label, active)
    outline(gui, look)
    local clicked = gui.RadioButton(label, active)
    plain(gui)
    return clicked
end

-- A button with a folder drawn before its caption, in the caption's color, as Vantage ships no icon font. Spaces at the
-- caption's start make room for the folder, so ImGui sizes the button and draws the caption as it does any other's.
local function folder_caption(gui, caption)
    local font = gui.GetFontSize()
    local side = math.floor(font * 0.9 + 0.5)
    local space = math.max(1, (gui.CalcTextSize(' ')))
    return string.rep(' ', math.ceil((side + font * 0.35) / space)) .. caption, side
end

-- How wide the button is, as a page measures its other buttons.
function controls.folder_width(gui, caption)
    return (gui.CalcTextSize((folder_caption(gui, caption)))) + 20
end

local tab_from, tab_to, front_from, front_to = {}, {}, {}, {}
-- id keeps it the same button whatever its caption. Returns whether it was clicked.
function controls.folder_button(gui, look, caption, id)
    local shown, side = folder_caption(gui, caption)
    local clicked = gui.Button(shown .. '###' .. id)
    if gui.GetItemRectMin and gui.GetItemRectMax and gui.GetWindowDrawList then
        local left, top = gui.GetItemRectMin()
        local right, bottom = gui.GetItemRectMax()
        local x = math.floor(left + math.max(0, (right - left - gui.CalcTextSize(shown)) / 2) + 0.5)
        local height = math.floor(side * 0.78 + 0.5)
        local y = math.floor((top + bottom - height) / 2 + 0.5)
        -- The folder's tab, then its front over it, so the two make one shape.
        tab_from[1], tab_from[2], tab_to[1], tab_to[2] = x, y, x + math.floor(side * 0.45 + 0.5), y + math.floor(height * 0.4 + 0.5)
        front_from[1], front_from[2], front_to[1], front_to[2] = x, y + math.floor(height * 0.22 + 0.5), x + side, y + height
        local ink = require('ui.theme').u32(look and look.text or { 1, 1, 1, 1 })
        local list = gui.GetWindowDrawList()
        list:AddRectFilled(tab_from, tab_to, ink, 1)
        list:AddRectFilled(front_from, front_to, ink, 1)
    end
    return clicked
end

return controls
