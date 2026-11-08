-- A slider, list or text box has its label on the left of its row and the control filling the rest, on every page, with
-- one column down the page, which stops growing at 24 times the font size. A label too long for its column, or a page
-- under 420 pixels wide, stays above its control.
-- Hovering the label gives the control's help, and the control's id, its highlight and typing in it work as usual.
local imgui = require('imgui')
local app = dofile(ADDON_DIR .. '/vantage.lua')
local window, callbacks = require('ui.settings_window'), app.callbacks
local durations = require('ui.duration_settings')
local durations_draw, page_draw, query = durations.draw, nil, ''
durations.draw = function(gui, s, view, cb, c)
    if page_draw then return page_draw(gui, s, c) end
    return durations_draw(gui, s, view, cb, c)
end
local input_with_hint = imgui.InputTextWithHint
imgui.InputTextWithHint = function(label, hint, value, ...)
    if label == '##find_settings' then value[1] = query end
    return input_with_hint(label, hint, value, ...)
end

local s = app.state.settings
s.window.open, s.window.tab = true, 'Durations'
local function frame()
    MOCK.imgui_calls = {}
    window.draw(app.state.settings, app.state.view, callbacks)
end
local function called(name, value)
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == name and (value == nil or call[2] == value) then return call end
    end
end
local TEXT = { TextUnformatted = true, TextWrapped = true }
-- How a label was drawn, the gap after it and what its control is told to do, read from the calls of its row.
local function row(label)
    for index, call in ipairs(MOCK.imgui_calls) do
        if TEXT[call[1]] and call[2] == label then
            local gap
            for at = index + 1, #MOCK.imgui_calls do
                local following = MOCK.imgui_calls[at]
                if following[1] == 'SameLine' then gap = following[3] end
                if following[1] == 'SetNextItemWidth' then
                    return { how = call[1], gap = gap, width = following[2], aligned = MOCK.imgui_calls[index - 1][1] == 'AlignTextToFramePadding' }
                end
            end
        end
    end
    error('Fixture: no row for ' .. label)
end

local f = { size = 10, pick = 'a', name = 'Abc' }
local LONG = string.rep('x', 41)
local function page(_, _, c)
    c.number('Size', f, 'size', 1, 40, 'How big it is.')
    c.combo('Pick one', f, 'pick', { 'a', 'b' }, { a = 'Apple', b = 'Banana' }, 'Which fruit.')
    c.text('A name for the box', f, 'name', 'The name to use.', 24)
    c.number(LONG, f, 'size', 1, 40, 'A label with a lot to say.')
end
page_draw = page

-- Beside, each control starts in the same column: 42 percent of the page.
frame()
for _, label in ipairs({ 'Size', 'Pick one', 'A name for the box' }) do
    local shown = row(label)
    assert(shown.how == 'TextUnformatted' and shown.aligned and shown.width == -1, label .. ': the label sits on the left of its row, with the control filling the rest.')
    assert(#label * 8 + shown.gap == math.floor(820 * 0.42), label .. ': the control starts in the column.')
end
local shown = row(LONG)
assert(shown.how == 'TextUnformatted', 'The widest label that fits with 10 pixels to spare at this width stays beside.')
assert(called('SliderFloat', '##Size') and called('BeginCombo', '##Pick one') and called('InputText', '##A name for the box'),
    'The controls keep their ids, so a box being typed in stays that box.')

-- The label takes the same widths through every helper, and a width of 786 makes the column exactly 330 pixels.
MOCK.content_width = 786
frame()
assert(row(string.rep('x', 41)).how == 'TextWrapped', 'A label 10 pixels short of its column is too long.')
page_draw = function(_, _, c) c.number(string.rep('y', 40), f, 'size', 1, 40) end
frame()
assert(row(string.rep('y', 40)).how == 'TextUnformatted', 'A label that leaves 10 pixels stays beside.')
page_draw = page

-- On a very wide page the column stops at 24 times the font size, so no big gap opens up, and the control takes the
-- rest. It follows the font, and up to there the 42 percent stands.
local font_size, size = imgui.GetFontSize, 17
imgui.GetFontSize = function() return size end
MOCK.content_width = 1600
frame()
assert(#'Size' * 8 + row('Size').gap == 24 * 17, 'At 1600 pixels the control starts at 24 font sizes.')
assert(row('Size').width == -1, 'The control fills the rest.')
size = 20
frame()
assert(#'Size' * 8 + row('Size').gap == 24 * 20, 'The column grows with the font.')
size = 17
MOCK.content_width = math.floor(24 * 17 / 0.42)
frame()
assert(#'Size' * 8 + row('Size').gap == math.floor(MOCK.content_width * 0.42), 'Just under the cap the 42 percent stands.')
page_draw = function(_, _, c) c.number(string.rep('z', 60), f, 'size', 1, 40) end
MOCK.content_width = 1600
frame()
assert(row(string.rep('z', 60)).how == 'TextWrapped', 'A label too long for the capped column goes above its control.')
page_draw = page
imgui.GetFontSize, MOCK.content_width = font_size, nil

-- Stacked, the label is above a full-width control as it always was: no gap, nothing on the same line.
for width, stacked in pairs({ [419] = true, [420] = false, [300] = true, [60] = true }) do
    MOCK.content_width = width
    frame()
    local size = row('Size')
    assert((size.how == 'TextWrapped') == stacked and (size.gap == nil) == stacked and size.width == -1,
        'At ' .. width .. ' pixels the label is ' .. (stacked and 'above its control.' or 'beside it.'))
end
MOCK.content_width = nil

-- Hovering the label gives the help the control gives, and only the label is hovered here.
local hover, tips = nil, {}
local text_unformatted, is_hovered, begin_tooltip = imgui.TextUnformatted, imgui.IsItemHovered, imgui.BeginTooltip
imgui.TextUnformatted = function(value, ...)
    if value == hover then hover = true end
    tips[#tips + 1] = value
    return text_unformatted(value, ...)
end
imgui.IsItemHovered = function()
    if hover == true then hover = nil; return true end
    return false
end
local function said(label, help)
    hover, tips = label, {}
    frame()
    for _, value in ipairs(tips) do if value == help then return true end end
    return false
end
assert(said('Size', 'How big it is. Ctrl-click the slider to type a value.'), 'A slider\'s label has its help.')
assert(said('Pick one', 'Which fruit.'), 'A list\'s label has its help.')
assert(said('A name for the box', 'The name to use.'), 'A text box\'s label has its help.')
imgui.TextUnformatted, imgui.IsItemHovered, imgui.BeginTooltip = text_unformatted, is_hovered, begin_tooltip

-- The search lights the control on the row, the same as when the label was over it, and counts it once.
query = 'pick one'
frame(); frame()
local lit, control_at
for index, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'BeginCombo' and call[2] == '##Pick one' then control_at = index end
    if call[1] == 'draw:AddRect' and control_at and not lit then lit = index end
end
assert(control_at and lit and lit > control_at, 'The highlight is drawn on the row.')
assert(tostring((called('TextUnformatted', '1 of 1 matching controls on this page') or {})[2]):find('1 of 1', 1, true), 'One row is one match.')
query = ''
frame()
page_draw = nil

-- Every page, as its controls are shown on a fresh save: a label over a control named after it fits nowhere else.
local function rows(on)
    local beside, above = 0, {}
    for index, call in ipairs(MOCK.imgui_calls) do
        local following = MOCK.imgui_calls[index + 1]
        if TEXT[call[1]] and type(call[2]) == 'string' then
            for at = index + 1, math.min(index + 5, #MOCK.imgui_calls) do
                local control = MOCK.imgui_calls[at]
                if control[2] == '##' .. call[2] or control[2] == '##frame_' .. call[2] then
                    if #call[2] * 8 + 10 > math.floor(820 * 0.42) then break end
                    local gapped
                    for between = index + 1, at do gapped = gapped or MOCK.imgui_calls[between][1] == 'SameLine' end
                    if gapped then beside = beside + 1 else above[#above + 1] = on .. ': ' .. call[2] end
                    break
                end
            end
        end
    end
    return beside, above
end
local total, stacked_rows = 0, {}
local function count(name)
    frame()
    local beside, above = rows(name)
    total = total + beside
    for _, line in ipairs(above) do stacked_rows[#stacked_rows + 1] = line end
end
for _, name in ipairs({ 'Display', 'Durations', 'Profiles', 'Help' }) do
    app.state.settings.window.tab = name
    count(name)
end
local panels = require('ui.panel_frame')
app.state.settings.window.tab = 'Display'
for _, id in ipairs({ 'party_ui', 'overhead', 'cooldown_list', 'rolls', 'pet', 'notices', 'hidden' }) do
    for _, tab in ipairs(panels.tabs) do
        panels.open(id, tab.key)
        count(id .. ' ' .. tab.key)
    end
end
assert(#stacked_rows == 0, 'A label that fits sits beside its control: ' .. table.concat(stacked_rows, ', '))
assert(total >= 50, 'Fixture: the pages drew their rows: ' .. total)

-- The rows that draw their own control use the same label.
local function beside(tab, label)
    app.state.settings.window.tab = tab
    frame()
    assert(row(label).how == 'TextUnformatted' and row(label).gap ~= nil, label .. ' sits beside its control.')
end
beside('Home', 'Skin')
app.state.settings.shared_layout = true
beside('Profiles', 'What to share')
app.state.settings.shared_layout = false
beside('Profiles', 'Saved profiles')
beside('Profiles', 'Load this profile when I change to')
require('ui.panel_frame').open('self_buffs', 'filters')
beside('Display', 'Show only names containing')
local defaults = require('ui.defaults')
local rule = defaults.rule('rule_1')
rule.event = 'remaining'
app.state.settings.alerts.rules = { rule }
require('ui.alert_panel').edit('rule_1')
require('ui.panel_frame').open('notices', 'show')
beside('Display', 'Thresholds, separated by commas')
beside('Display', 'Effect')
require('ui.alert_panel').edit(nil)
query = 'skin'
beside('Home', 'Skin')
beside('Home', 'Text size')
query = ''
