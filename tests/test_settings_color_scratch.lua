-- The panel frame's color pickers hand imgui one table, filled from the setting each frame, so a frame makes no color table
-- for them. A change saves a copy with the picked color, as one Undo step, and nothing in the settings is that table.
local store, imgui = require('core.store'), require('imgui')
local app = dofile(ADDON_DIR .. '/vantage.lua')
local callbacks = app.callbacks
local window = require('ui.settings_window')
local settings = app.state.settings
settings.window.open, settings.window.tab = true, 'Display'
require('ui.panel_frame').open('recasts', 'show')
settings.recast_tints.mp_color, settings.recast_tints.spell_lock_color = { 0.1, 0.2, 0.3, 0.4 }, { 0.5, 0.6, 0.7, 0.8 }
settings.panels.spell_recasts.enabled = true
imgui.CollapsingHeader, imgui.BeginCombo = function() return true end, function() return true end
local MP, LOCK = 'Color##frame_mp', 'Color##frame_spell_lock'
local pickers = { [MP] = 'mp_color', [LOCK] = 'spell_lock_color' }
local given, picks, tables = {}, {}, nil
imgui.ColorEdit4 = function(label, value)
    if not pickers[label] then return false end
    given[#given + 1] = { label = label, value = value, seen = store.copy(value) }
    local pick = picks[label]
    if pick then for index = 1, 4 do value[index] = pick[index] end; return true end
    -- The picker may write into the table even when it reports no change.
    for index = 1, 4 do value[index] = 0.123 end
    return false
end
local function draw()
    settings = app.state.settings
    window.draw(settings, app.state.view, callbacks)
    assert(#MOCK.font_stack == 0)
end
draw()
given = {}
draw(); draw()
assert(#given == 4, 'Fixture: both color pickers drew on both frames.')
local scratch = given[1].value
for _, entry in ipairs(given) do
    assert(rawequal(entry.value, scratch), 'Every picker on every frame is handed the same table.')
    assert(store.equal(entry.seen, settings.recast_tints[pickers[entry.label]]), 'Each picker is handed its own setting\'s color.')
end
assert(store.equal(settings.recast_tints.mp_color, { 0.1, 0.2, 0.3, 0.4 }) and store.equal(settings.recast_tints.spell_lock_color, { 0.5, 0.6, 0.7, 0.8 }),
    'What a picker writes without a change reaches no setting.')

local function holds(value, seen)
    if rawequal(value, scratch) then return true end
    for _, picker in pairs(tables or {}) do if rawequal(value, picker) then return true end end
    if type(value) ~= 'table' or seen[value] then return false end
    seen[value] = true
    for key, item in pairs(value) do if holds(key, seen) or holds(item, seen) then return true end end
    return false
end
local undo = callbacks.history_status().undo
picks[LOCK] = { 0.9, 0.8, 0.7, 0.6 }
given = {}
draw()
picks = {}
callbacks.save()
settings = app.state.settings
assert(store.equal(settings.recast_tints.spell_lock_color, { 0.9, 0.8, 0.7, 0.6 }), 'The picked color is saved.')
assert(store.equal(settings.recast_tints.mp_color, { 0.1, 0.2, 0.3, 0.4 }), 'The other picker keeps its color.')
assert(not rawequal(settings.recast_tints.spell_lock_color, scratch) and not holds(settings, {}), 'Nothing in the settings is the picker\'s table.')
assert(callbacks.history_status().undo == undo + 1, 'A color change is one Undo step.')
given = {}
draw()
assert(rawequal(given[1].value, scratch) and store.equal(given[2].seen, { 0.9, 0.8, 0.7, 0.6 }), 'The next frame hands the new color in the same table.')
assert(callbacks.undo())
assert(store.equal(app.state.settings.recast_tints.spell_lock_color, { 0.5, 0.6, 0.7, 0.8 }), 'Undo puts the color back.')

-- The main page's swatches keep one table each, so a frame makes no color table for them either, and what a swatch
-- writes without a change reaches no setting.
settings = app.state.settings
settings.window.tab, settings.style.text_outline = 'Home', true
settings.style.outline_color = { 0.1, 0.2, 0.3, 0.4 }
local swatches = 0
tables = {}
imgui.ColorEdit4 = function(label, value)
    swatches = swatches + 1
    assert(tables[label] == nil or rawequal(tables[label], value), 'One table for every frame: ' .. label)
    tables[label] = value
    for index = 1, 4 do value[index] = 0.123 end
    return false
end
draw(); draw()
assert(swatches >= 4 and tables['Outline color##main_text_color'] and tables['Outline color##main_countdown_color'], 'Fixture: the swatches drew.')
assert(not rawequal(tables['Outline color##main_text_color'], tables['Outline color##main_countdown_color']), 'Each has its own table.')
assert(store.equal(settings.style.outline_color, { 0.1, 0.2, 0.3, 0.4 }) and not holds(settings, {}), 'Nothing reaches the settings.')
return true
