-- A panel's own Show samples counts only while the panel is on, as End samples on the main page does: a recast panel the
-- combined layout doesn't show, or a panel turned off, keeps its tick but makes no samples to draw.
local defaults = require('ui.defaults');

local s = defaults.make();
assert(not defaults.any_sampled(s), 'Fixture: nothing shows samples at first.');

-- Spell recasts' own Show samples, then One panel for all.
s.panels.spell_recasts.enabled, s.recast_display = true, 'separate';
defaults.sample_panel(s, 'spell_recasts', true);
assert(defaults.any_sampled(s) and defaults.samples_showing(s), 'Fixture: Spell recasts shows samples while it is on the screen.');
s.recast_display = 'combined';
assert(not defaults.panel_enabled(s, 'spell_recasts') and s.panels.spell_recasts.preview == true,
    'Fixture: the combined layout doesn\'t show Spell recasts, which keeps its tick.');
assert(not defaults.samples_showing(s), 'Fixture: the main page says no samples show.');
assert(not defaults.any_sampled(s), 'A sampled panel the layout doesn\'t show makes no samples.');
s.recast_display = 'separate';
assert(defaults.any_sampled(s), 'Shown again, its samples are back.');

-- A panel turned off.
s.panels.spell_recasts.enabled = false;
assert(not defaults.any_sampled(s), 'A sampled panel that is off makes no samples.');

-- Show samples on the main page still counts.
s.preview = true;
assert(defaults.any_sampled(s), 'Show samples on the main page makes them.');
return 'Only a panel that is on makes samples';
