local theme = {}

theme.names = { 'Phoenix', 'Classic FFXI', 'Original FFXI', 'Minimal', 'High contrast', 'Ember', 'Mint', 'Lavender', 'Colorblind safe' }
theme.window_types = { 1, 2, 3, 4, 5, 6, 7, 8 }
theme.window_type_labels = { 'Window Type 1', 'Window Type 2', 'Window Type 3', 'Window Type 4',
    'Window Type 5', 'Window Type 6', 'Window Type 7', 'Window Type 8' }
theme.fields = {
    { 'background_color', 'Panel background' }, { 'text_color', 'Text' }, { 'title_color', 'Panel titles' },
    { 'border_color', 'Borders' }, { 'track_color', 'Bar track' }, { 'buff_color', 'Buffs' },
    -- unknown_color has no control: effects with no countdown take the buff or debuff color. Skins set it, and the
    -- settings window's faded text reads it. outline_color's is the Outline color beside Other text.
    { 'debuff_color', 'Debuffs' }, { 'estimate_color', 'Estimated timers' }, { 'unknown_color', 'Untimed effects', no_control = true },
    { 'warning_color', 'Ending soon and alerts' },
    -- The names the panel colors use for the same parts: the effect name, the countdown and the other fields.
    { 'label_color', 'Name' }, { 'value_color', 'Countdown' }, { 'detail_color', 'Detail text' },
    { 'outline_color', 'Text outline', no_control = true }, { 'accent_color', 'Accent color' },
}

local palettes = {
    Phoenix = { '211518', 'fff5ef', 'ffb3a0', '825957', '38282b', '78bea9', 'df7685', 'e8c375', 'adb0c0', 'ffe6a4' },
    ['Classic FFXI'] = { '101d42', 'ffffff', 'f3df9f', '7690c2', '263763', '95ccf0', 'efa19b', 'e7cf85', 'b8c3d5', 'fff0a8' },
    ['Original FFXI'] = { 'ffffff', 'ffffff', 'ffffff', 'ffffff', '202030', 'ffffff', 'ffffff', 'ffffff', 'b8c3d5', 'fff0a8' },
    Minimal = { '181b20', 'eef0f3', 'cbd2da', '5c6672', '2e343c', '96bfae', 'd6a7ac', 'd7c795', 'a7b0bc', 'ffffff' },
    ['High contrast'] = { '000000', 'ffffff', 'ffe575', 'ffffff', '262626', '56b4e9', 'e69f00', 'f0e442', 'c8c8c8', 'ffffff' },
    Ember = { '23170f', 'fff4e8', 'ffc08b', '9b6033', '42301f', 'b8ce8d', 'eb9273', 'e6c585', 'b8b3a8', 'fff0a8' },
    Mint = { '12251f', 'eefbf5', 'a5e7cd', '568b75', '294037', '80cdb4', 'e49fae', 'dfd390', 'aebdb6', 'fff0ac' },
    Lavender = { '201a2c', 'f4efff', 'd9bffa', '806c9d', '382d4b', 'a3cfbd', 'e3a5be', 'ddcb95', 'b9b0c8', 'fff0b8' },
    ['Colorblind safe'] = { '101820', 'f5f5f5', '9dd6f7', '62849a', '263743', '56b4e9', 'e69f00', 'f0e442', 'bac5cd', 'ffffff' },
}

local function color(hex)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1 }
end

function theme.colors(name)
    local palette, result = palettes[name] or palettes.Phoenix, {}
    for i = 1, 10 do result[theme.fields[i][1]] = color(palette[i]) end
    result.label_color, result.value_color = color(palette[2]), color(palette[2])
    result.detail_color, result.accent_color = color(palette[9]), color(palette[3])
    result.outline_color = { 0, 0, 0, 0.8 }
    return result
end

function theme.apply(settings, name)
    if not palettes[name] then return false end
    for key, value in pairs(theme.colors(name)) do settings.style[key] = value end
    settings.style.theme = name
    return true
end

function theme.current(settings)
    for key, value in pairs(theme.colors(settings.style.theme)) do
        local saved = settings.style[key]
        if type(saved) ~= 'table' then return 'Custom' end
        for i = 1, 4 do
            if type(saved[i]) ~= 'number' or math.abs(value[i] - saved[i]) > 0.002 then return 'Custom' end
        end
    end
    return settings.style.theme
end

-- Looked up on first use: require on every call costs more than the conversion.
local col32
function theme.u32(value, opacity)
    col32 = col32 or require('imgui').col32
    return col32(math.floor(value[4] * (opacity or 1) * 255 + 0.5), math.floor(value[1] * 255 + 0.5),
        math.floor(value[2] * 255 + 0.5), math.floor(value[3] * 255 + 0.5))
end

-- What the settings window paints: each key of its look, with the ImGui colors it fills (paints, also). One with neither
-- is read by the window's own drawing.
theme.WINDOW_COLORS = {
    { key = 'text', paints = 'Text' }, { key = 'faded_text', paints = 'TextDisabled' },
    { key = 'headings' }, { key = 'heading_lines', paints = 'Separator' },
    { key = 'notes' }, { key = 'done_messages' }, { key = 'problem_messages' },
    { key = 'selected_text', paints = 'TextSelectedBg' }, { key = 'text_cursor', paints = 'InputTextCursor' },
    { key = 'background', paints = 'WindowBg' }, { key = 'border', paints = 'Border' },
    { key = 'title_bar', paints = 'TitleBgActive' }, { key = 'title_bar_unfocused', paints = 'TitleBg', also = 'TitleBgCollapsed' },
    { key = 'resize_corner', paints = 'ResizeGrip' }, { key = 'resize_corner_hovered', paints = 'ResizeGripHovered' },
    { key = 'resize_corner_held', paints = 'ResizeGripActive' }, { key = 'resize_edges_hovered', paints = 'SeparatorHovered' },
    { key = 'resize_edges_held', paints = 'SeparatorActive' }, { key = 'scrollbar_track', paints = 'ScrollbarBg' },
    { key = 'scrollbar', paints = 'ScrollbarGrab' }, { key = 'scrollbar_hovered', paints = 'ScrollbarGrabHovered' },
    { key = 'scrollbar_held', paints = 'ScrollbarGrabActive' },
    { key = 'boxes', paints = 'FrameBg' }, { key = 'boxes_hovered', paints = 'FrameBgHovered' },
    { key = 'boxes_clicked', paints = 'FrameBgActive' }, { key = 'check_marks', paints = 'CheckMark', also = 'DragDropTarget' },
    { key = 'slider_handles', paints = 'SliderGrab' }, { key = 'slider_handles_held', paints = 'SliderGrabActive' },
    { key = 'buttons', paints = 'Button' }, { key = 'buttons_hovered', paints = 'ButtonHovered' },
    { key = 'buttons_pressed', paints = 'ButtonActive' }, { key = 'on_chips' }, { key = 'on_chip_text' },
    { key = 'dropdowns', paints = 'PopupBg' }, { key = 'row_picked', paints = 'Header' },
    { key = 'row_hovered', paints = 'HeaderHovered' }, { key = 'row_clicked', paints = 'HeaderActive' },
}

local window_sources = {
    text = 'text_color', faded_text = 'unknown_color', headings = 'title_color', heading_lines = 'border_color',
    notes = 'text_color', done_messages = 'buff_color', problem_messages = 'warning_color', selected_text = 'border_color',
    text_cursor = 'text_color', background = 'background_color', border = 'border_color', title_bar = 'track_color',
    title_bar_unfocused = 'track_color', resize_corner = 'border_color', resize_corner_hovered = 'title_color',
    resize_corner_held = 'title_color', resize_edges_hovered = 'title_color', resize_edges_held = 'warning_color',
    scrollbar_track = 'background_color', scrollbar = 'border_color', scrollbar_hovered = 'title_color', scrollbar_held = 'warning_color',
    boxes = 'track_color', boxes_hovered = 'border_color', boxes_clicked = 'border_color', check_marks = 'title_color',
    slider_handles = 'title_color', slider_handles_held = 'warning_color', buttons = 'track_color', buttons_hovered = 'border_color',
    buttons_pressed = 'estimate_color', on_chips = 'title_color', on_chip_text = 'background_color', dropdowns = 'background_color',
    row_picked = 'track_color', row_hovered = 'border_color', row_clicked = 'border_color',
}

local filled_controls = {
    boxes_hovered = 0.2, boxes_clicked = 0.3, buttons_hovered = 0.2, buttons_pressed = 0.28,
    row_picked = 0.16, row_hovered = 0.2, row_clicked = 0.3,
}

local function same_color(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end
    for i = 1, 4 do
        if type(a[i]) ~= 'number' or a[i] ~= a[i] or math.abs(a[i] - b[i]) > 0.000000001 then return false end
    end
    return true
end

local function numeric(value, low, high, fallback)
    if type(value) ~= 'number' or value ~= value or math.abs(value) == math.huge then return fallback end
    return math.max(low, math.min(high, value))
end

local original_window = {
    text = 'ffffff', faded_text = 'a8a8b8', headings = 'ffffff', heading_lines = 'a4a4ba', notes = 'eeeeef',
    done_messages = 'bfe5c3', problem_messages = 'fff0a8', selected_text = '545482', text_cursor = 'ffffff',
    background = 'ffffff', border = 'ffffff', title_bar = '31305a', title_bar_unfocused = '23233f',
    resize_corner = '89899d', resize_corner_hovered = 'cfcfdf', resize_corner_held = 'ffffff',
    resize_edges_hovered = 'cfcfdf', resize_edges_held = 'ffffff', scrollbar_track = '17172a',
    scrollbar = '828297', scrollbar_hovered = 'b2b2c6', scrollbar_held = 'd8d8e4',
    boxes = '202039', boxes_hovered = '42425f', boxes_clicked = '515171', check_marks = 'ffffff',
    slider_handles = 'c8c8dd', slider_handles_held = 'ffffff', buttons = '292944',
    buttons_hovered = '4b4b68', buttons_pressed = '696985', on_chips = 'c8c8dd', on_chip_text = '17172a',
    dropdowns = 'ffffff', row_picked = '525276', row_hovered = '444464', row_clicked = '686886',
}
local light_window = {
    text = '201b13', faded_text = '554d39', headings = '201b13', heading_lines = '655936', notes = '30291b',
    done_messages = '254629', problem_messages = '6c2719', selected_text = 'b6a16c', text_cursor = '201b13',
    title_bar = 'd6c995', title_bar_unfocused = 'bcb18a', boxes = 'ddd1a7', boxes_hovered = 'f0e5c5',
    boxes_clicked = 'c5b680', check_marks = '302619', slider_handles = '756333', slider_handles_held = '473a20',
    buttons = 'd1c392', buttons_hovered = 'eee1b7', buttons_pressed = 'bba66c',
    on_chips = '66572e', on_chip_text = 'fff4d5', row_picked = 'c4b078', row_hovered = 'ddca98', row_clicked = 'b8a067',
}

-- Background values tint the artwork; the normal renderer needs a dark fallback. A tinted color goes into out when it's
-- given, so a caller that hands it straight to ImGui makes no table.
function theme.window_paint(look, key, out)
    local value = look[key]
    if look.theme == 'Original FFXI' and (key == 'background' or key == 'dropdowns') then
        out = out or {}
        if look.window_type == 7 then out[1], out[2], out[3] = value[1] * 198 / 255, value[2] * 185 / 255, value[3] * 133 / 255
        else out[1], out[2], out[3] = value[1] * 49 / 255, value[2] * 48 / 255, value[3] * 90 / 255 end
        out[4] = value[4]
        return out
    end
    return value
end

function theme.window_defaults(settings)
    local s = type(settings) == 'table' and type(settings.style) == 'table' and settings.style or {}
    local name = s.theme or 'Phoenix'
    local colors = theme.colors(name)
    local out = { theme = palettes[name] and name or 'Phoenix',
        window_type = math.floor(numeric(s.window_type, 1, 8, 1)),
        font_size = 17 }
    for _, entry in ipairs(theme.WINDOW_COLORS) do
        local field = window_sources[entry.key]
        local saved = name == 'Original FFXI' and color(out.window_type == 7 and light_window[entry.key] or original_window[entry.key])
            or type(s[field]) == 'table' and s[field] or colors[field]
        out[entry.key] = {}
        for i = 1, 4 do out[entry.key][i] = numeric(saved[i], 0, 1, colors[field][i]) end
        local mix = name ~= 'Original FFXI' and filled_controls[entry.key]
        if mix and same_color(saved, colors[field]) and (type(s.track_color)~='table' or same_color(s.track_color, colors.track_color)) then
            -- Accent colors stay bright for ink. Filled controls mix them into the dark track.
            for i = 1, 3 do out[entry.key][i] = colors.track_color[i] * (1 - mix) + colors[field][i] * mix end
        end
    end
    out.selected_text[4] = 0.35
    return out
end

-- What older Vantage builds saved in the window's look before it followed the skin: its own skin, type, font, rounding,
-- spacing and colors, the tab colors among them. A save loses those and keeps the rest.
local retired_window = { linked = true, theme = true, window_type = true, window_art = true, font = true, rounding = true,
    spacing = true, tabs = true, tabs_hovered = true, tabs_unfocused = true, open_tab = true, open_tab_line = true,
    open_tab_unfocused = true, open_tab_line_unfocused = true }
for _, entry in ipairs(theme.WINDOW_COLORS) do retired_window[entry.key] = true end

function theme.tidy_window(settings)
    if type(settings) ~= 'table' then return end
    local saved = type(settings.window_style) == 'table' and settings.window_style or {}
    settings.window_style = require('core.store').keep_unknown({ font_size = numeric(saved.font_size, 8, 36, 17) }, saved, retired_window)
end

-- The window follows the skin, and writes in the main font at its own saved size.
local function window_look(settings)
    local out, saved = theme.window_defaults(settings), settings.window_style
    out.font_size = saved and saved.font_size or out.font_size
    local font = type(settings.style) == 'table' and settings.style.font
    out.font = type(font) == 'string' and font or 'Agave'
    return out
end

-- The settings window's look. Given the settings revision, the look is made again only when that revision, the
-- settings, their style table or the saved text size change, as every settings change counts one; callers of that one
-- only read it.
local kept_window = {}
function theme.window(settings, revision)
    if revision == nil then return window_look(settings) end
    local kept = kept_window
    local size = settings.window_style and settings.window_style.font_size
    if kept.revision ~= revision or kept.settings ~= settings or kept.style ~= settings.style or kept.font_size ~= size then
        kept.look = window_look(settings)
        kept.revision, kept.settings, kept.style, kept.font_size = revision, settings, settings.style, size
    end
    return kept.look
end

-- ImGui copies a pushed color during the call, so one table takes each tinted one.
local pushed = { 0, 0, 0, 0 }
local CLEAR = { 0, 0, 0, 0 }
-- The window's colors, and two things its look has no key for, which would come from Ashita's own style: the page is
-- drawn in child windows, so their background is clear and the window's own shows, and buttons and boxes get no
-- outline. A tick box draws its own (controls.lua). Returns how many colors theme.pop takes off.
function theme.push(settings, resolved)
    local imgui = require('imgui')
    local count = 0
    local w = resolved or theme.window(settings)
    for _, entry in ipairs(theme.WINDOW_COLORS) do
        local key = entry.paints and _G['ImGuiCol_' .. entry.paints]
        if key then imgui.PushStyleColor(key, theme.window_paint(w, entry.key, pushed)); count = count + 1 end
        key = entry.also and _G['ImGuiCol_' .. entry.also]
        if key then imgui.PushStyleColor(key, w[entry.key]); count = count + 1 end
    end
    if ImGuiCol_ChildBg then imgui.PushStyleColor(ImGuiCol_ChildBg, CLEAR); count = count + 1 end
    if ImGuiStyleVar_FrameBorderSize then imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 0) end
    return count
end

function theme.pop(colors)
    local imgui = require('imgui')
    if ImGuiStyleVar_FrameBorderSize then imgui.PopStyleVar(1) end
    if (colors or 0) > 0 then imgui.PopStyleColor(colors) end
end

return theme
