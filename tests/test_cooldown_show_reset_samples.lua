-- Reset this tab on Party cooldowns' Show puts In a list back off, and the list's samples end with it, as unticking In a
-- list does (core/party_cooldowns.lua place). Ticking In a list again brings no samples unasked, and the main page's Show
-- samples and /vg preview on still show them. Undo brings the list and its samples back together.
local h = require('panel_fixture')();
local defaults = require('ui.defaults');
local function command(text) local event = { command = text }; MOCK.fire('command', event); assert(event.blocked, 'Fixture: ' .. text .. ' is ours.'); end;
local function said()
    local s = h.s.party_cooldowns;
    return ('list %s, samples %s, the main page lists samples on [%s]'):format(tostring(s.list.enabled), tostring(s.preview),
        table.concat(defaults.samples_on_displays(h.s), ', '));
end;

h.fresh(function(s) s.party_cooldowns.enabled, s.party_cooldowns.list.enabled = true, true; end);
h.on('cooldown_list', 'show');
h.draw('Show samples##frame');
h.draw();
assert(h.s.party_cooldowns.preview == true, 'Fixture: the list shows its samples.');
h.draw('Reset this tab##frame');
h.draw();
assert(h.s.party_cooldowns.list.enabled == false and h.app.callbacks.history_status().undo_label == 'Reset this tab', 'Fixture: Reset this tab put In a list back off.');
assert(h.s.party_cooldowns.preview == false and #defaults.samples_on_displays(h.s) == 0, 'With the list off its samples end: ' .. said());
h.s.window.tab = 'Home';
h.draw();
assert(h.called('Button', 'Show samples##main') and not h.called('Button', 'End samples##main'), 'The main page offers Show samples: ' .. said());

-- Undo brings both back.
h.draw('Undo');
h.draw();
assert(h.s.party_cooldowns.list.enabled == true and h.s.party_cooldowns.preview == true, 'Undo brings the list and its samples back: ' .. said());
h.draw('Redo');
h.draw();
assert(h.s.party_cooldowns.list.enabled == false and h.s.party_cooldowns.preview == false, 'Redo ends them again: ' .. said());

-- In a list again: no samples until asked, and both ways of asking still work.
h.on('cooldown_list', 'show');
h.draw('In a list##frame_list');
h.draw();
assert(h.s.party_cooldowns.list.enabled == true and h.s.party_cooldowns.preview == false, 'Ticking In a list again shows no samples unasked: ' .. said());
h.s.window.tab = 'Home';
h.draw('Show samples##main');
h.draw();
assert(h.s.party_cooldowns.preview == true, 'The main page\'s Show samples shows them in the list: ' .. said());
h.draw('End samples##main');
h.draw();
assert(h.s.party_cooldowns.preview == false, 'Fixture: End samples ends them.');
command('/vg preview on');
assert(h.app.state.settings.party_cooldowns.preview == true, '/vg preview on shows them in the list.');
MOCK.fire('unload');
return 'Reset this tab on Party cooldowns\' Show ends the list\'s samples';
