-- Box sits under the heading rows on the Look tab of every bar, expanded and text panel, timers and recasts. Icons draws no
-- box, so it offers no pick and its note says the box stays saved. With No boxes or headings on, a line under the pick says
-- why nothing draws. A pick is one Undo step, and search finds the pick by its name and by its aliases. Its help and the
-- shared switches' help say which wins, Put every display back and the shared timers reset keep it, and on an Icons panel a
-- search for it lands on Layout, which shows it.
local imgui, defaults = require('imgui'), require('ui.defaults')
local app = dofile(ADDON_DIR .. '/vantage.lua')
local window = require('ui.settings_window')
local panels = require('ui.panel_frame')
local combo, shown, texts
imgui.BeginCombo = function(label, preview)
    MOCK.imgui_calls[#MOCK.imgui_calls + 1] = { 'BeginCombo', label, preview }
    shown[label] = preview
    return label == combo
end
local text_wrapped = imgui.TextWrapped
imgui.TextWrapped = function(value, ...)
    texts[#texts + 1] = value
    return text_wrapped(value, ...)
end
local view = { rows = {}, context = { valid = false } }
local function frame(click, opened)
    combo, shown, texts, MOCK.imgui_calls = opened, {}, {}, {}
    if click then MOCK.clicks[click] = true end
    window.draw(app.state.settings, view, app.callbacks)
    if click then assert(not MOCK.clicks[click], 'Fixture: the control is on screen: ' .. click) end
    MOCK.clicks = {}
end
local function open(page, change)
    local s = defaults.tidy(defaults.make())
    s.window.open, s.window.tab = true, page
    if change then change(s) end
    app.state.settings = s
    frame(); frame()
    app.state.history, app.state.redo, app.state.transaction = {}, {}, nil
    return s
end
-- The labels of the controls drawn, in order: combos by their id, checkboxes and text by their words.
local function order()
    local result = {}
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'BeginCombo' then result[#result + 1] = call[2]
        elseif call[1] == 'Checkbox' then result[#result + 1] = call[2] end
    end
    return result
end
local function after(list, label)
    for index, value in ipairs(list) do if value == label then return list[index + 1] end end
end
local function said(fragment)
    for _, value in ipairs(texts) do if tostring(value):find(fragment, 1, true) then return value end end
end
-- Search finds it on both pages by its name and its aliases, before any page is drawn and after.
local function finds(query)
    for _, result in ipairs(window.search(query)) do if result.tab == 'Display' and result.label == 'Box' then return true end end
    return false
end
local function searched(when)
    for _, query in ipairs({ 'Panel box', 'frameless', 'background', 'border', 'box', 'outline' }) do
        assert(finds(query), when .. ', searching ' .. query .. ' finds Box')
    end
end
searched('Before any page is drawn')
local names = { shared = 'Shared', both = 'Background and border', background = 'Background only', border = 'Border only',
    none = 'None' }

-- Status timers: bars and expanded, the pick under the heading rows, reading Shared on a fresh install.
local heading, box = 'Show its heading##frame', '##frame_Box'
panels.open('self_buffs', 'look')
local s = open('Display')
for _, mode in ipairs({ 'bars', 'expanded' }) do
    s.panels.self_buffs.mode = mode
    frame()
    assert(after(order(), heading) == box, 'Box is drawn under the heading rows: ' .. mode)
    assert(shown[box] == 'Shared', 'A fresh panel reads Shared: ' .. mode)
end

-- Each pick is one Undo step named for it.
s.panels.self_buffs.mode = 'bars'
for _, choice in ipairs({ 'both', 'background', 'border', 'none', 'shared' }) do
    local before = #app.state.history
    frame(names[choice] .. '##' .. choice, box)
    assert(app.state.settings.panels.self_buffs.box == choice, 'The pick sets this panel: ' .. choice)
    assert(#app.state.history == before + 1 and app.callbacks.history_status().undo_label == 'Box', 'The pick is one Undo step named Box: ' .. names[choice])
    frame()
    assert(shown[box] == names[choice], 'The pick reads back: ' .. names[choice])
end
for id, panel in pairs(app.state.settings.panels) do
    assert(id == 'self_buffs' or panel.box == 'shared', 'A pick changes only its own panel: ' .. id)
end
assert(app.callbacks.undo() and app.state.settings.panels.self_buffs.box == 'none', 'Undo puts back the pick before.')
assert(app.callbacks.redo() and app.state.settings.panels.self_buffs.box == 'shared', 'Redo makes it again.')

-- No boxes or headings: the pick goes while nothing would draw it, the choice stays saved, and a line says why.
frame()
assert(not said('No boxes or headings is on'), 'With No boxes or headings off there is no line.')
app.state.settings.style.minimal = true
frame()
assert(shown[box] == nil and said('No boxes or headings is on, so this panel draws neither.'),
    'With No boxes or headings on, a line takes the place of the pick.')
app.state.settings.style.minimal = false

-- Icons only: no pick, and the note says the box stays saved.
app.state.settings.panels.self_buffs.mode = 'icons'
frame()
assert(shown[box] == nil, 'Icons offers no Box.')
assert(said('Icons has no heading or box. They stay saved for the other layouts.'), 'The note says the box stays saved.')

-- Recasts: bars and text only have the pick, icons only doesn't.
panels.open('spell_recasts', 'look')
s = open('Display', function(settings) settings.panels.spell_recasts.enabled = true end)
for _, mode in ipairs({ 'bars', 'expanded', 'text' }) do
    s.panels.spell_recasts.mode = mode
    frame()
    assert(after(order(), heading) == box, 'A recast panel draws Box under the heading rows: ' .. mode)
end
frame('Border only##border', box)
assert(s.panels.spell_recasts.box == 'border' and app.callbacks.history_status().undo_label == 'Box', 'A Text recast panel takes the pick.')
s.panels.spell_recasts.mode = 'icons'
frame()
assert(shown[box] == nil, 'An Icons recast panel offers no Box.')

-- The help of a control, as drawn when the pointer is on it: the first tooltip text after that control.
local function help_after(kind, label)
    local seen
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == kind and call[2] == label then seen = true
        elseif seen and call[1] == 'TextUnformatted' then return call[2] end
    end
end
local function hovered()
    imgui.IsItemHovered = function() return true end
    frame()
    imgui.IsItemHovered = nil
end
-- The pick's help says what each choice draws.
panels.open('self_buffs', 'look')
open('Display', function(settings) settings.panels.self_buffs.mode = 'bars' end)
hovered()
assert(help_after('BeginCombo', box) == 'Shared follows Background and Border under More look on the main page. The other choices set this panel\'s own background and border. Show its heading still shows or hides the title.',
    'The Box help says what each choice draws.')
-- More look: the shared switches say a panel's own pick keeps its choice.
open('Home', function(settings) settings.window.sections['Home/More look'] = true end)
hovered()
for _, label in ipairs({ 'Background##main_background', 'Border##main_border' }) do
    local help = help_after('Checkbox', label)
    assert(help and help:find('A panel with its own Box keeps its own choice.', 1, true), label .. ' says a panel\'s own Box keeps its choice.')
end

-- Put every display back on Profiles and sharing and the shared timers reset keep every panel's pick, as they keep
-- Panel heading. Reset selected panel puts its panel back to Shared (test_panel_box_saved).
local picks = { 'both', 'background', 'border', 'none' }
local function varied(settings)
    for index, id in ipairs(defaults.panel_order) do settings.panels[id].box = picks[(index - 1) % #picks + 1] end
end
local function kept()
    for index, id in ipairs(defaults.panel_order) do
        if app.state.settings.panels[id].box ~= picks[(index - 1) % #picks + 1] then return false end
    end
    return true
end
-- Each case also moves something its reset puts back, so the reset is one Undo step.
open('Profiles', function(settings) varied(settings); settings.panels.self_buffs.x = 321 end)
frame('Put every display back where it started')
assert(app.callbacks.history_status().undo_label == 'Reset displays' and kept(), 'Put every display back keeps every panel\'s pick.')
open('Home', function(settings) varied(settings); settings.style.font_size = 30 end)
app.callbacks.reset('appearance')
assert(app.callbacks.history_status().undo_label == 'Reset appearance' and kept(), 'The appearance reset keeps every panel\'s pick.')

-- A fresh install's Self buffs is Icons: a search for Panel box lights Layout, which shows the pick, on Show.
local query
imgui.InputTextWithHint = function(label, _, value)
    if label == '##find_settings' and query ~= nil then value[1], query = query, nil; return true end
    return false
end
panels.open('self_buffs', 'show')
open('Display')
query = 'panel box'
frame(); frame()
local layout, marked, matches
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'TextUnformatted' and tostring(call[2]):find('matching controls on this page', 1, true) then matches = call[2] end
    if call[1] == 'BeginCombo' and call[2] == '##frame_Layout' then layout = true
    elseif layout and not marked then
        if call[1] == 'draw:AddRect' then marked = true
        elseif call[1] == 'TextWrapped' or call[1] == 'TextUnformatted' or call[1] == 'BeginCombo' or call[1] == 'Checkbox' or call[1] == 'Button' then layout = false end
    end
end
assert(app.state.settings.panels.self_buffs.mode == 'icons' and marked and tostring(matches):match('^1 of [1-9]'),
    'A search for Panel box on an Icons panel lands on Layout.')
query = ''
frame()

searched('Once both pages are drawn')
MOCK.fire('unload')
return 'Box is a pick under the heading rows with a named Undo step, and search finds it'
