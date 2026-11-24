-- Reset this tab on Ready pulse's Show puts back Never pulse for, which is on that tab, with the rest of it.
local h = require('panel_fixture')();
h.fresh(function(s) s.ready_pulse.enabled = true; s.ready_pulse.ignore[10001] = true; s.ready_pulse.min_seconds = 300; end);
h.on('pulse', 'show');
h.draw('Reset this tab##frame');
h.draw();
assert(h.s.ready_pulse.min_seconds == 60, 'Fixture: the tab reset ran.');
assert(next(h.s.ready_pulse.ignore) == nil, 'Reset this tab on Ready pulse Show left Never pulse for as it was.');
h.draw('Undo');
h.draw();
assert(h.s.ready_pulse.ignore[10001] == true and h.s.ready_pulse.min_seconds == 300, 'Undo brings the list back.');
MOCK.fire('unload');
return 'ok';
