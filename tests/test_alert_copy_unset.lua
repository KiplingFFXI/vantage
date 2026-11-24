-- Copy on a New alert or a Recast ready that has nothing chosen yet makes an alert just like it: off, reading Choose an
-- effect or Choose a recast, with the line that says it stays off, and turned on by its first pick. A copy of an alert
-- with its effect chosen keeps the effect and stays on.
local h = require('panel_fixture')();
local NOTE = 'It stays off until you choose what it watches.';

-- Adds an alert with add, copies it before anything is chosen, then picks the same thing on the copy and the original.
local function copied(add, label, pick_name, pick_id)
    h.fresh();
    h.on('notices', 'show');
    h.draw(add);
    h.draw();
    local rules = h.s.alerts.rules;
    assert(#rules == 1 and rules[1].enabled == false and rules[1].effect == 0, add .. ' starts off with nothing chosen.');
    local first = { reads = h.previews['##' .. label], note = h.says(NOTE) };
    h.draw('Copy##alert');
    h.draw();
    rules = h.s.alerts.rules;
    assert(#rules == 2 and rules[2].id ~= rules[1].id, 'Copy adds one.');
    local copy = { reads = h.previews['##' .. label], note = h.says(NOTE), enabled = rules[2].enabled, effect = rules[2].effect };
    h.choose(pick_name, pick_id, label);
    rules = h.s.alerts.rules;
    copy.after_effect, copy.after_on = rules[2].effect, rules[2].enabled;
    h.draw('Edit##alert');
    h.draw();
    h.choose(pick_name, pick_id, label);
    rules = h.s.alerts.rules;
    first.after_effect, first.after_on = rules[1].effect, rules[1].enabled;
    local line = ('%s: original reads %s, note %s, after the pick %s on %s | copy (on %s, effect %s) reads %s, note %s, after the pick %s on %s')
        :format(add, tostring(first.reads), tostring(first.note), tostring(first.after_effect), tostring(first.after_on),
        tostring(copy.enabled), tostring(copy.effect), tostring(copy.reads), tostring(copy.note), tostring(copy.after_effect), tostring(copy.after_on));
    assert(first.after_effect == pick_id and first.after_on == true, 'Fixture: the original turns on at its first pick: ' .. line);
    return first, copy, line;
end;

local said = {};
local function check(first, copy, line)
    if not (copy.enabled == false and copy.reads == first.reads and copy.note == first.note and first.note == true
        and copy.after_effect == first.after_effect and copy.after_on == true) then
        said[#said + 1] = line;
    end;
end;
check(copied('New alert##frame', 'Effect', 'Haste', 33));
-- The fixture has no recast list, so a live recast row puts Provoke on the picker, as a real one would.
h.view.rows = { { domain = 'recast', effect = 10005, name = 'Provoke', kind = 'ability', group = 'ability' } };
check(copied('Recast ready##frame', 'Recast', 'Provoke', 10005));
h.view.rows = {};
assert(#said == 0, 'A copy of an alert with nothing chosen should read and act as the alert it copies: ' .. table.concat(said, ' || '));

-- A copy of an alert with its effect chosen is on and watches it.
h.fresh();
h.on('notices', 'show');
h.draw('New alert##frame');
h.draw();
h.choose('Haste', 33);
local rules = h.s.alerts.rules;
assert(rules[1].enabled == true and rules[1].effect == 33, 'The first pick turns it on.');
h.draw('Copy##alert');
h.draw();
rules = h.s.alerts.rules;
assert(#rules == 2 and rules[2].enabled == true and rules[2].effect == 33, 'The copy is on and watches Haste.');
assert(h.previews['##Effect'] ~= 'Choose an effect' and not h.says(NOTE), 'The copy reads its effect: ' .. tostring(h.previews['##Effect']));
MOCK.fire('unload');
return 'A copy of an alert with nothing chosen reads Choose';
