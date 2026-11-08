-- The settings window keeps its look (theme.window) until the settings change (ui/theme.lua): every way they change
-- counts a settings revision or gives new tables, so the kept look always equals one made fresh, and a frame with no
-- change makes none.
local store, theme = require('core.store'), require('ui.theme')
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 1, job_name = 'WAR', self_known = true,
    self_effects = {}, party = {}, entities = {} }
package.loaded['core.client'] = { read = function() return store.copy(snapshot) end, load = function() end }
package.loaded['core.observer'] = { read = function() return {} end }
local app = dofile(ADDON_DIR .. '/vantage.lua')
local state, callbacks = app.state, app.callbacks
local function command(text) local e = { command = text }; MOCK.fire('command', e); assert(e.blocked, text) end
MOCK.fire('load'); app.refresh(0)
command('/vantage show')

local function look() return theme.window(state.settings, callbacks.settings_revision()) end
local function fresh() return theme.window(state.settings) end
-- After each change the kept look is the fresh one, and asking again gives that same table. differs says the change
-- reaches the look, so the check can't pass by keeping the old one.
local function after(name, change, differs)
    local before = look()
    assert(rawequal(look(), before), name .. ': with no change the kept look is given again.')
    before = store.copy(before)
    change()
    local kept = look()
    assert(store.equal(kept, fresh()), name .. ': the kept look equals one made fresh.')
    assert(rawequal(look(), kept), name .. ': it is kept until the next change.')
    if differs ~= false then assert(not store.equal(kept, before), name .. ': fixture, the change reaches the look.') end
end
local function edit(label, fn) callbacks.changed('before', label); fn(state.settings); callbacks.changed('after') end

after('A page change that saves', function()
    edit('Panel theme: Mint', function(s) theme.apply(s, 'Mint') end); callbacks.save()
end)
-- A color dragged over three frames, saved at the end, as the color pickers do.
for index = 1, 3 do
    after('Color drag frame ' .. index, function()
        edit('Text color', function(s) s.style.text_color = { 0.1 * index, 0.2, 0.3, 1 } end)
    end)
end
callbacks.save()
after('Undo', function() assert(callbacks.undo()) end)
after('Redo', function() assert(callbacks.redo()) end)
after('/vg skin', function() command('/vg skin High contrast') end)
-- The timer font, which the window writes in too.
after('/vg font', function() command('/vg font Ashita') end, false)
after('/vg set', function() command('/vg set window_style.font_size 21') end)
after('A window style reset', function() assert(callbacks.reset('window_style')) end)
after('A starter', function() assert(callbacks.starter('Support')) end, false)
after('A page or section opened', function() callbacks.editor_changed() end, false)
command('/vg profile save "Look A"')
command('/vg skin Ember')
after('A profile load', function() command('/vg profile load "Look A"') end)
local share = require('core.share')
local text = assert(share.export(state.settings, 'profile', nil, 'Tester'))
command('/vg skin Lavender')
after('An export', function()
    local payload = assert(share.read(text))
    assert(callbacks.share_import(payload, 'replace'))
end)
-- Settings replaced without a count still give a fresh look, as the kept one is for those tables only.
after('New settings tables with no count', function()
    local copy = store.copy(state.settings)
    theme.apply(copy, 'Colorblind safe')
    state.settings = copy
end)
after('A new style table with no count', function()
    local style = store.copy(state.settings.style)
    style.text_color = { 0.31, 0.62, 0.93, 1 }
    state.settings.style = style
end)
after('A new window style table with no count', function()
    local menu = store.copy(state.settings.window_style)
    menu.font_size = 12
    state.settings.window_style = menu
end)

-- A page that fails puts its changes back. The look it made while drawing isn't kept.
local failing = false
package.loaded['ui.settings_window'] = { draw = function(s, _, cb)
    if not (s.window.open and failing) then return end
    cb.changed('before', 'Panel theme: Ember'); theme.apply(s, 'Ember'); cb.changed('after')
    assert(look().theme == 'Ember', 'Fixture: the failing page reaches the look.')
    error('The page failed.', 0)
end }
command('/vg')
MOCK.frame(0.2); MOCK.frame(0.2)
after('A page that fails', function()
    failing = true
    MOCK.frame(0.2)
    assert(state.settings_stopped == true, 'Fixture: the page stopped.')
end, false)
failing = false
command('/vg')

-- Another character's settings.
command('/vg skin Mint')
after('A character switch', function()
    snapshot.id, snapshot.name = 1002, 'Other'
    app.refresh(1)
    assert(state.path:find('Other_1002', 1, true), 'Fixture: the other character loaded.')
end)
return true
