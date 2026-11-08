-- A setup, as /vg commands run it, and the Size buttons keep each timer and recast panel's Panel heading switch and Panel
-- title as the player set them, beside its Panel box. A setup does at every size, skin and font choice, and in its preview,
-- and the rest of each panel still takes its defaults; a Size button leaves the rest alone too. Fresh installs show
-- every heading with the panel's own name, and Reset this display puts both back on its panel only.
local defaults, store, custom = require('ui.defaults'), require('core.store'), require('core.customization')
local presets, appearance = require('setup_fixture'), require('ui.appearance')
local imgui = require('imgui')
local equal = custom.equal

-- Hidden headings, custom titles and a blank one (the panel's own name), and a box pick, spread over the panels.
-- Show icons is off everywhere: Apply still resets it.
local function chosen(s)
    for index, id in ipairs(defaults.panel_order) do
        local p = s.panels[id]
        p.show_heading = index % 2 == 0
        p.title = index % 3 == 0 and '' or 'My ' .. id
        p.box = defaults.panel_boxes[index % #defaults.panel_boxes + 1]
        p.show_icon = false
    end
    return s
end
local function kept(s)
    local result = {}
    for _, id in ipairs(defaults.panel_order) do
        local p = s.panels[id]
        result[id] = { heading = p.show_heading, title = p.title, box = p.box }
    end
    return result
end
-- A panel without the three kept keys, to compare the rest.
local function rest(panel)
    local value = store.copy(panel)
    value.show_heading, value.title, value.box = nil, nil, nil
    return value
end

-- A fresh install.
for _, s in ipairs({ defaults.make(), defaults.tidy({}) }) do
    for _, id in ipairs(defaults.panel_order) do
        assert(s.panels[id].show_heading == true and s.panels[id].title == defaults.panel_names[id],
            'A fresh install shows the heading with the panel\'s own name: ' .. id)
    end
end

-- Every size, skin and font choice, with fonts kept and a screen to re-space on.
local skins = { 'keep' }
for _, name in ipairs(appearance.names) do skins[#skins + 1] = name end
for _, size in ipairs({ 'minimal', 'minimal_1_5x', 'minimal_2x' }) do
    for _, skin in ipairs(skins) do
        for _, matching in ipairs({ true, false }) do
            local options = { size = size, skin = skin, matching = matching, window_type = 3, label = 'full',
                screen_width = 1600, screen_height = 900 }
            local name = size .. ' ' .. skin .. (matching and ' matching' or ' own fonts')
            local s = chosen(defaults.tidy(defaults.make()))
            local before = kept(s)
            local preview = presets.build(s, options)
            assert(preview and equal(kept(preview), before), 'The preview keeps every heading, title and box: ' .. name)
            assert(presets.apply(s, options) and equal(kept(s), before), 'Apply keeps every heading, title and box: ' .. name)
            local plain = defaults.tidy(defaults.make())
            assert(presets.apply(plain, options), 'Fixture: the setup applies to a fresh install: ' .. name)
            for _, id in ipairs(defaults.panel_order) do
                assert(equal(rest(s.panels[id]), rest(plain.panels[id])), 'The rest of the panel takes the setup\'s defaults: ' .. name .. ' ' .. id)
            end
        end
    end
end

-- Through the settings window: the Size buttons on the main page.
local app = dofile(ADDON_DIR .. '/vantage.lua')
local window = require('ui.settings_window')
local combo
imgui.BeginCombo = function(label)
    MOCK.imgui_calls[#MOCK.imgui_calls + 1] = { 'BeginCombo', label }
    return label == combo
end
local function frame(click, opened)
    combo, MOCK.imgui_calls = opened, {}
    if click then MOCK.clicks[click] = true end
    window.draw(app.state.settings, { rows = {}, context = { valid = false } }, app.callbacks)
    if click then assert(not MOCK.clicks[click], 'Fixture: the control is on screen: ' .. click) end
    MOCK.clicks = {}
end
local function open(tab)
    local s = chosen(defaults.tidy(defaults.make()))
    s.window.open, s.window.tab = true, tab
    app.state.settings = s
    frame(); frame()
    app.state.history, app.state.redo, app.state.transaction = {}, {}, nil
    return kept(s)
end
local function applied(label)
    local history = app.state.history
    return #history == 1 and history[1].label == label
end

local before = open('Home')
frame('2x##main_size')
assert(applied('Size 2x') and app.state.settings.style.scale == 2, 'Fixture: the Size button ran as one Undo step.')
assert(equal(kept(app.state.settings), before), 'A Size button keeps every panel\'s heading, title and box.')
assert(app.state.settings.panels.self_buffs.show_icon == false, 'A Size button resets nothing else of a panel.')

-- Reset this display puts the heading on and the panel's own name back on its panel only.
require('ui.panel_frame').open('self_buffs', 'show')
before = open('Display')
frame('Reset this display##frame')
frame('Reset##look_frame_reset_self_buffs')
local id = 'self_buffs'
local panel = app.state.settings.panels[id]
assert(app.callbacks.history_status().undo_label == 'Reset Self buffs', 'Undo says it by the name the player knows.')
assert(panel and panel.show_heading == true and panel.title == defaults.panel_names[id] and panel.box == 'shared',
    'Reset this display shows its heading with its own name again.')
local after = kept(app.state.settings)
after[id], before[id] = nil, nil
assert(equal(after, before), 'Reset this display leaves the other panels\' heading, title and box.')
MOCK.fire('unload')
return 'A setup and the Size buttons keep each panel\'s heading and title; Reset this display resets them'
