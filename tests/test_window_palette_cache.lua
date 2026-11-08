-- The settings window's look is made once per settings change, and every draw until the next change shares it.
local store, theme = require('core.store'), require('ui.theme')
local defaults = require('ui.defaults')

local settings = defaults.tidy(defaults.make())
theme.apply(settings, 'Mint')
local one = theme.window(settings, 1)
assert(rawequal(one, theme.window(settings, 1)), 'A draw with no change shares the look.')
local two = theme.window(settings, 2)
assert(store.equal(one.text, two.text) and rawequal(two, theme.window(settings, 2)), 'A change makes it once more.')
local other = store.copy(settings)
other.style.text_color = { 0.9, 0.8, 0.7, 0.6 }
assert(store.equal(theme.window(other, 2).text, other.style.text_color), 'Undo swapping the settings table gets its own look.')
return true
