-- Countdown text is set once, under More look on the main page, and reaches every display's own keys. A pick leaves the
-- font and the locks alone, and Undo has what was there before.
local defaults = require('ui.defaults')
local window, hud = require('ui.settings_window'), require('ui.hud')
local imgui = require('imgui')
local s, changes = defaults.make(), {}
s.window.open, s.window.tab = true, 'Home'
s.window.sections['Home/More look'] = true
s.style.font = 'XI View'
local snapshot = require('core.customization').history_value
local cb = { now = function() return 100 end, save = function() return true end,
    changed = function(stage, label) changes[#changes + 1] = { stage = stage, label = label, state = snapshot(s) } end }
local combo
imgui.BeginCombo = function(label) return label == combo end
local function click(label, opened)
    combo, MOCK.clicks[label] = opened, true
    window.draw(s, hud.sample(100), cb)
    assert(not MOCK.clicks[label], label .. ' is available on the selected page.')
end
for _, term in ipairs({ 'Bold countdowns', 'Countdown text shadow', 'Countdown text outline', 'Effect countdown shadow' }) do
    local found = false
    for _, result in ipairs(window.search(term)) do found = found or result.tab == 'Home' end
    assert(found, term .. ' is searchable on the main page before opening it.')
end
click('Bold##main_countdown_bold')
local targets = { s.panels.self_buffs, s.panels.watch, s.panels.recasts, s.panels.item_recasts, s.party_ui.effects, s.overhead, s.rolls, s.pet }
for _, target in ipairs(targets) do assert(target.countdown_bold, 'Bold reaches every countdown.') end
click('Shadow##main_countdown_shadow')
for _, target in ipairs(targets) do assert(not target.countdown_shadow, 'So does Shadow.') end
click('Every display##every', '##main_countdown_outline')
for _, target in ipairs(targets) do assert(target.countdown_outline, 'So does an outline for Every display.') end
click('None##none', '##main_countdown_outline')
for _, target in ipairs(targets) do assert(not target.countdown_outline, 'And None.') end
for _, result in ipairs(window.search('Target effect countdown outline')) do
    assert(result.label ~= 'Target effect countdown outline', 'The target frame countdowns are not offered.')
end
assert(s.style.font == 'XI View')
assert(s.party_ui.locked and s.panels.self_buffs.locked)
assert(changes[#changes].stage == 'after' and changes[#changes - 1].stage == 'before')
local before = changes[#changes - 1].state
assert(before.panels.self_buffs.countdown_outline and not before.panels.self_buffs.countdown_shadow, 'The Undo snapshot holds the choices before the pick.')
