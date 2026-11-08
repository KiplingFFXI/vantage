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

return controls
