-- Panel box is one saved key per timer and recast panel. Fresh installs and saves without it read Shared;
-- tidying keeps the five choices and turns anything else into Shared. Apply setup and Apply size
-- leave each panel's pick as it was, profiles and shared presentation carry it, and copies of a panel keep it.
local defaults, store, custom = require('ui.defaults'), require('core.store'), require('core.customization')
local presets, profiles = require('setup_fixture'), require('core.profiles')
local equal = custom.equal
-- The five Panel box choices.
local choices = { 'shared', 'both', 'background', 'border', 'none' }

-- A pick for each panel, cycling through the four that differ from Shared.
local picks = { 'both', 'background', 'border', 'none' }
local function varied(s)
    for index, id in ipairs(defaults.panel_order) do s.panels[id].box = picks[(index - 1) % #picks + 1] end
    return s
end
local function boxes(s)
    local result = {}
    for _, id in ipairs(defaults.panel_order) do result[id] = s.panels[id].box end
    return result
end
local function all_shared(s)
    for _, id in ipairs(defaults.panel_order) do if s.panels[id].box ~= 'shared' then return false, id end end
    return true
end

-- Fresh installs.
assert(all_shared(defaults.make()), 'Fresh defaults are Shared for every panel.')
assert(all_shared(defaults.tidy({})), 'A fresh install is Shared for every panel.')

-- A save without the key: every panel reads Shared, and the save tidies exactly as one saying Shared does.
local saved = defaults.make()
saved.style.theme, saved.panels.self_buffs.x, saved.panels.spell_recasts.mode = 'Original FFXI', 321, 'text'
for _, id in ipairs(defaults.panel_order) do saved.panels[id].box = nil end
local old = defaults.tidy(store.copy(saved))
assert(all_shared(old), 'A save without the key reads Shared for every panel.')
local marked = store.copy(saved)
for _, id in ipairs(defaults.panel_order) do marked.panels[id].box = 'shared' end
assert(equal(old, defaults.tidy(marked)), 'A save without the key loads as one that says Shared.')
assert(old.panels.self_buffs.x == 321 and old.panels.spell_recasts.mode == 'text', 'Tidying keeps the other saved values.')

-- The five choices are kept; anything else is Shared.
for _, box in ipairs(choices) do
    local s = defaults.make()
    for _, id in ipairs(defaults.panel_order) do s.panels[id].box = box end
    s = defaults.tidy(s)
    for _, id in ipairs(defaults.panel_order) do assert(s.panels[id].box == box, 'Tidying keeps ' .. box .. ' on ' .. id) end
end
for _, junk in ipairs({ 'Both', 'frameless', 'None', 'background_only', '', 7, true, {} }) do
    local s = defaults.make()
    s.panels.target.box, s.panels.item_recasts.box = junk, junk
    s = defaults.tidy(s)
    assert(s.panels.target.box == 'shared' and s.panels.item_recasts.box == 'shared',
        'Tidying turns ' .. tostring(junk) .. ' into Shared.')
end

-- The settings file keeps the pick.
local folder = MOCK_INSTALL_PATH .. '/config/addons/vantage/'
local path = folder .. 'Boxes_1/settings.json'
local written = store.write(path, varied(defaults.make()))
assert(written and equal(boxes(defaults.tidy(store.read(path))), boxes(varied(defaults.make()))), 'A saved pick loads back.')

-- Apply setup, Apply size and their preview keep each panel's pick.
local setups = {
    { name = 'Apply setup', options = { skin = 'Original FFXI', size = 'minimal', matching = true, window_type = 3, label = 'full' } },
    { name = 'Apply setup with XI View', options = { skin = 'XI View', size = 'minimal_2x', matching = true, window_type = 1, label = 'full' } },
    { name = 'Apply size', options = { skin = 'keep', size = 'minimal_1_5x', matching = false, window_type = 1, label = 'full',
        screen_width = 1600, screen_height = 900 } },
}
for _, setup in ipairs(setups) do
    local s = varied(defaults.tidy(defaults.make()))
    local before = boxes(s)
    local preview = presets.build(s, setup.options)
    assert(preview and equal(boxes(preview), before), setup.name .. ' previews with every panel keeping its pick.')
    assert(presets.apply(s, setup.options) and equal(boxes(s), before), setup.name .. ' keeps every panel\'s pick.')
end

-- Profiles save it and load it back; a profile without it loads as Shared and reads unmodified.
local saved_profiles = profiles.new(MOCK_INSTALL_PATH .. '/config/addons/vantage')
local s = varied(defaults.tidy(defaults.make()))
local chosen = boxes(s)
local stored = saved_profiles:save_new('Boxes', s)
for _, id in ipairs(defaults.panel_order) do s.panels[id].box = 'shared' end
local loaded = stored and saved_profiles:load('Boxes', s)
s = defaults.tidy(s)
assert(loaded and equal(boxes(s), chosen), 'Loading a profile puts back each panel\'s pick.')
local data = store.read(saved_profiles.path)
for _, panel in pairs(data.Boxes.panels) do panel.box = nil end
loaded = store.write(saved_profiles.path, data) and saved_profiles:load('Boxes', s)
s = defaults.tidy(s)
assert(loaded and all_shared(s), 'A profile without the key loads as Shared.')
assert(not saved_profiles:source('Boxes', s).modified, 'A profile without the key reads unmodified once loaded.')

-- Shared presentation carries it; placement doesn't.
local source, target = varied(defaults.tidy(defaults.make())), defaults.tidy(defaults.make())
local applied = profiles.apply_layout(target, profiles.capture_layout(source, 'presentation'), 'presentation')
assert(applied and equal(boxes(target), boxes(source)), 'Shared presentation carries each panel\'s pick.')
target = defaults.tidy(defaults.make())
source.panels.self_buffs.x = 77
applied = profiles.apply_layout(target, profiles.capture_layout(source, 'placement'), 'placement')
assert(applied and target.panels.self_buffs.x == 77 and all_shared(target), 'Shared placement leaves the pick alone.')

-- Copies of a panel keep it: a copy, a starter, and /vg set; a panel reset goes back to Shared.
s = varied(defaults.tidy(defaults.make()))
assert(defaults.copy(s.panels.self_debuffs).box == s.panels.self_debuffs.box, 'A copied panel keeps its pick.')
local starter = require('core.starters').apply(s, 'Support')
assert(starter and equal(boxes(starter), boxes(s)), 'A starter keeps each panel\'s pick.')
local set = custom.set(s, 'panels.self_buffs.box', 'none')
assert(set and set.panels.self_buffs.box == 'none', '/vg set takes a choice.')
assert(custom.set(s, 'panels.self_buffs.box', 'frameless') == nil, '/vg set refuses anything else.')
local reset = custom.reset(store.copy(s), 'target')
assert(reset and reset.panels.target.box == 'shared' and reset.panels.self_debuffs.box == s.panels.self_debuffs.box,
    'Reset selected panel puts only that panel back to Shared.')
return 'Panel box is saved per panel, tidied, kept by Apply and carried by profiles'
