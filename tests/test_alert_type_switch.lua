-- Switching Alert type on an alert that's on clears what it watches, so it goes off until something is chosen, as a
-- New alert does. Effect 0 would watch every effect or recast. The first pick turns it on again, Undo brings the old
-- alert back on, and an alert that was off stays off.
local h = require('panel_fixture')();
local alerts = require('ui.alert_panel');
local NOTE = 'It stays off until you choose what it watches.';
local function rule() return h.s.alerts.rules[#h.s.alerts.rules]; end;

h.fresh();
h.on('notices', 'show');
h.draw('Haste ending##frame');
h.draw();
assert(rule().effect == 33 and rule().enabled == true, 'Fixture: Haste ending is on.');
local steps = #h.app.state.history;

h.pick('##frame_Alert type', 'Recast##recast');
assert(rule().domain == 'recast' and rule().effect == 0, 'The switch clears the effect.');
assert(#h.app.state.history == steps + 1, 'The switch is one Undo step.');
assert(rule().enabled == false, 'An alert that was on goes off when its Alert type changes.');
assert(h.previews['##Recast'] == 'Choose a recast', 'It reads Choose a recast: ' .. tostring(h.previews['##Recast']));
assert(h.says(NOTE), 'The note says why it is off.');

-- The fixture has no recast list, so a live recast row puts Provoke on the picker, as a real one would.
h.view.rows = { { domain = 'recast', effect = 10005, name = 'Provoke', kind = 'ability', group = 'ability' } };
h.choose('Provoke', 10005, 'Recast');
h.view.rows = {};
assert(rule().effect == 10005 and rule().enabled == true, 'The first pick turns it on again.');

-- Undo the pick, then the switch.
h.draw('Undo'); h.draw();
assert(rule().effect == 0 and rule().enabled == false, 'Undo of the pick: off with nothing chosen.');
h.draw('Undo'); h.draw();
assert(rule().domain == 'status' and rule().effect == 33 and rule().enabled == true, 'Undo of the switch: Haste ending is back on.');
assert(not h.says(NOTE), 'No note once Haste is back.');
h.draw('Redo'); h.draw();
assert(rule().enabled == false and h.previews['##Recast'] == 'Choose a recast', 'Redo: off with nothing chosen.');

-- All recasts is still a choice, and switching back from it goes off too.
h.pick('##Recast', 'All recasts##all');
assert(rule().effect == 0 and rule().enabled == true and h.previews['##Recast'] == 'All recasts', 'All recasts turns it on.');
h.pick('##frame_Alert type', 'Buff or debuff##status');
assert(rule().enabled == false and h.previews['##Effect'] == 'Choose an effect', 'Back to Buff or debuff: off, reads Choose an effect.');
h.choose('Haste', 33);
assert(rule().enabled == true and rule().effect == 33, 'Picking Haste turns it on.');

-- The player turns it off with its tick, then switches again. Having gone off on a switch once doesn't turn it on later.
h.draw(rule().name .. '##alert_on'); h.draw();
assert(rule().enabled == false, 'Its tick turns it off.');
h.pick('##frame_Alert type', 'Recast##recast');
assert(not h.says(NOTE), 'No note on an alert the player turned off.');
h.view.rows = { { domain = 'recast', effect = 10005, name = 'Provoke', kind = 'ability', group = 'ability' } };
h.choose('Provoke', 10005, 'Recast');
h.view.rows = {};
assert(rule().effect == 10005, 'Fixture: Provoke is picked.');
assert(rule().enabled == false, 'An alert the player turned off, switched and picked, stays off: enabled=' .. tostring(rule().enabled));

-- A New alert switched to Recast before anything is picked still waits for its first choice, and that pick turns it on.
h.fresh();
h.on('notices', 'show');
h.draw('New alert##frame');
h.draw();
assert(rule().effect == 0 and rule().enabled == false and h.says(NOTE), 'Fixture: a New alert waits for its first choice.');
h.pick('##frame_Alert type', 'Recast##recast');
assert(h.says(NOTE), 'A New alert switched to Recast still says why it is off.');
assert(h.previews['##Recast'] == 'Choose a recast', 'It reads Choose a recast: ' .. tostring(h.previews['##Recast']));
h.view.rows = { { domain = 'recast', effect = 10005, name = 'Provoke', kind = 'ability', group = 'ability' } };
h.choose('Provoke', 10005, 'Recast');
h.view.rows = {};
assert(rule().effect == 10005 and rule().enabled == true, 'Its first pick turns it on.');

-- An alert that's off before the switch stays off.
h.fresh(function(s)
    local made = require('ui.defaults').rule('r_off');
    made.name, made.effect, made.enabled = 'Off alert', 33, false;
    s.alerts.rules = { made };
end);
alerts.edit('r_off');
h.on('notices', 'show');
h.pick('##frame_Alert type', 'Recast##recast');
assert(rule().enabled == false, 'An alert that was off stays off.');
MOCK.fire('unload');
return 'Switching Alert type turns an alert that is on off until something is chosen';
