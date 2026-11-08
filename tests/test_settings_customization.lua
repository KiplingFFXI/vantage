local defaults = require('ui.defaults')
local hud = require('ui.hud')
local window = require('ui.settings_window')
local imgui = require('imgui')
local s, view = defaults.make(), hud.sample(100)
s.panels.self_buffs.mode, s.panels.self_buffs.stack_direction = 'bars', 'vertical'
s.window.open = true
local called, input, active, popup, focused, escape = {}, {}, false, false, true, false
local cb = {
    now = function() return 100 end,
    save = function() return true end,
    changed = function() end,
    profile_list = function() return { 'Support' } end,
    profile_status = function(name) return { source = name or 'Support', token = 'revision-1', modified = true, recover_available = true, recover_kind = 'overwrite' } end,
    profile_save = function(...) called.save = { ... }; return true end,
    profile_delete = function(...) called.delete = { ... }; return true end,
    profile_rename = function(...) called.rename = { ... }; return true end,
    profile_recover = function() called.recover = true; return true end,
    profile_link = function(...) called.link = { ... }; return true end,
    reset = function(scope) called.reset = scope; return true end,
    history_status = function() return { undo = 2, redo = 1 } end,
    undo = function() called.undo = true; return true end,
    redo = function() called.redo = true; return true end,
    starter = function(name, samples) called.starter = { name, samples }; return true end,
    copy_shown = function(...) called.copy = { ... }; return true end,
    export_report = function() called.report = true; return true end,
    chat_sample = function() called.chat = true; return true end,
    sound_files = function() return {} end,
}
imgui.InputText = function(label, value)
    if input[label] ~= nil then value[1], input[label] = input[label], nil; return true end
    return false
end
imgui.InputTextWithHint = function(label, hint, value) return imgui.InputText(label, value) end
imgui.BeginCombo = function() return true end
imgui.IsAnyItemActive = function() return active end
imgui.IsPopupOpen = function() return popup end
imgui.IsWindowFocused = function() return focused end
imgui.IsKeyPressed = function() return escape end
local function frame(page, click)
    if page then s.window.tab = page end
    if click then MOCK.clicks[click] = true end
    window.draw(s, view, cb)
    assert(#MOCK.font_stack == 0, 'Each settings frame balances its font stack.')
end

assert(window.matches('window COLOR', 'Independent window colors'))
assert(not window.matches('window unknown', 'Independent window colors'))
assert(#window.search('move along the side') > 0 and #window.search('corner rounding') > 0, 'Every page is searchable before its first visit.')
local values = { 'a', 'b', 'c', 'd' }
assert(window.move(values, 2, 99) and table.concat(values) == 'acdb')
assert(window.move(values, 4, 0) and table.concat(values) == 'bacd')
assert(not window.move(values, 4, 4) and not window.move(values, 8, 1))
for _, state in ipairs({ {true,false,false,true,true}, {false,true,false,true,true}, {false,false,true,true,true}, {false,false,false,false,true}, {false,false,false,true,false} }) do
    assert(not window.can_escape(unpack(state)))
end
assert(window.can_escape(false, false, false, true, true))

local panels = require('ui.panel_frame')
panels.open('self_buffs', 'look')
s.panels.self_buffs.wrap = true
frame('Display')
frame(nil, 'Down##part')
assert(s.panels.self_buffs.field_order[2] == 'name', 'Part move buttons reorder parts, not effects.')
input['##frame_Label_part'] = 'Effect:'
frame()
assert(s.panels.self_buffs.field_labels.name == 'Effect:')
-- A part with no value is always left out, so the list has no switch for it.
MOCK.imgui_calls = {}
frame()
local field_switches = {}
for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Checkbox' then field_switches[call[2]] = true end end
assert(field_switches['Start a new line##frame_part'], 'Fixture: the part is open.')
assert(not field_switches['Hide this field when it has no value'] and not field_switches['Hide this field when unknown'],
    'The list has no switch to hide a part with no value.')
frame(nil, 'Start a new line##frame_part')
assert(s.panels.self_buffs.field_newlines.name == true)
-- The panel reset is at the foot of every tab, and asks first.
frame(nil, 'Reset this display##frame')
assert(called.reset == nil, 'Reset waits for its confirm.')
frame(nil, 'Reset##look_frame_reset_self_buffs')
assert(called.reset == 'self_buffs')

frame('Profiles', 'Support')
frame(nil, 'Overwrite##profile_overwrite')
assert(called.save == nil, 'Selecting overwrite first requests confirmation.')
frame(nil, 'Confirm overwrite')
assert(called.save[1] == 'Support' and called.save[2] == true and called.save[3] == 'revision-1')
frame(nil, 'Delete##profile_delete')
assert(called.delete == nil)
frame(nil, 'Cancel profile change')
assert(called.delete == nil, 'Cancel leaves the saved file untouched.')
frame(nil, 'Delete##profile_delete')
frame(nil, 'Confirm delete')
assert(called.delete[1] == 'Support' and called.delete[2] == 'revision-1')
frame(nil, 'Undo the last profile change')
assert(called.recover)
input['##profile_name'] = 'New profile'
frame(nil, 'Save as new')
assert(called.save[1] == 'New profile' and called.save[2] == false)
frame('Home', 'Apply##main_starter')
assert(called.starter[1] == 'crowd control' and called.starter[2] == true, 'Apply on the main page asks for samples, for the starter that suits your job.')
frame(nil, 'Redo')
assert(called.redo)
frame('Help', 'Export report')
assert(called.report)
frame(nil, 'Copy timer details')
assert(called.copy[2] == true)

input['##find_settings'] = 'corner rounding'
frame('Home')
assert(#window.search('corner rounding') > 0, 'Rendered control names and help join the search index.')
frame(nil, 'Clear search')
active, escape = true, true
frame()
assert(s.window.open, 'Typing keeps Escape for the active editor.')
active = false
frame()
assert(s.window.open, 'The first release frame keeps Escape for the prior editor.')
popup = true
frame()
assert(s.window.open)
popup = false
frame()
assert(s.window.open, 'A closing popup consumes its own Escape.')
focused = false
frame()
assert(s.window.open, 'An unfocused settings window does not consume Escape.')
focused = true
frame()
assert(not s.window.open, 'Focused idle Escape closes settings.')
s.window.open, s.window.peek, cb.shift, escape = true, true, true, false
MOCK.imgui_calls = {}
frame('Display')
for _, entry in ipairs(MOCK.imgui_calls) do assert(entry[1] ~= 'Checkbox', 'Shift peek skips settings controls.') end
view.context.chat_open = true
MOCK.imgui_calls = {}
frame()
local controls = false
for _, entry in ipairs(MOCK.imgui_calls) do if entry[1] == 'Checkbox' then controls = true end end
assert(controls, 'Typing in chat prevents Shift peek.')
view.context.chat_open, cb.shift = false, false
assert(#MOCK.commands == 0, 'Customization sends no game commands.')
