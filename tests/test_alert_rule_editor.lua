-- The alert rule editor keeps a rule the alerts can use and the list can show: Percent keeps only the thresholds a
-- percent can be, a name left blank reads Alert, a thresholds box left with nothing it can read shows the rule's
-- thresholds again, and Specific member lists a member by name only.
local h = require('panel_fixture')();
local defaults = require('ui.defaults');
local alerts = require('ui.alert_panel');

-- A rule counting down Haste with these thresholds, open in the editor.
local function open(thresholds, change)
    h.fresh(function(s)
        local rule = defaults.rule('r1');
        rule.name, rule.effect, rule.event, rule.unit, rule.thresholds = 'Probe', 33, 'remaining', 'seconds', thresholds;
        if change then change(rule); end;
        s.alerts.rules = { rule };
    end);
    alerts.edit('r1');
    h.on('notices', 'show');
    assert(h.called('InputText', '##thresholds'), 'Fixture: the rule is open.');
end;
local function rule() return h.s.alerts.rules[1]; end;
local function listed(list) return table.concat(list, ', '); end;
local function box() return h.calls('InputText', '##thresholds')[1][3][1]; end;

-- Percent keeps the thresholds up to 100, as one Undo step.
open({ 300, 90, 30 });
local steps = #h.app.state.history;
h.pick('##frame_Threshold unit', 'Percent remaining##percent');
assert(rule().unit == 'percent' and listed(rule().thresholds) == '90, 30', 'Percent keeps 90 and 30: ' .. listed(rule().thresholds));
assert(box() == '90, 30', 'The box shows what is kept: ' .. box());
assert(#h.app.state.history == steps + 1, 'One Undo step.');
h.draw('Undo');
h.draw();
assert(rule().unit == 'seconds' and listed(rule().thresholds) == '300, 90, 30', 'Undo puts the seconds back.');
-- With none that low, 10 stands in, as reading the settings gives.
open({ 300, 120 });
h.pick('##frame_Threshold unit', 'Percent remaining##percent');
assert(rule().unit == 'percent' and listed(rule().thresholds) == '10', 'With none left, 10 stands in: ' .. listed(rule().thresholds));
h.pick('##frame_Threshold unit', 'Seconds remaining##seconds');
assert(rule().unit == 'seconds' and listed(rule().thresholds) == '10', 'Seconds keep every threshold.');

-- A name left blank reads Alert, so the list has no blank tick.
h.type('##frame_Rule name', '   ');
assert(rule().name == 'Alert', 'A blank name reads Alert: ' .. rule().name);
h.type('##frame_Rule name', 'Haste low');
assert(rule().name == 'Haste low', 'Any other name stays as typed.');

-- The thresholds box left with nothing it can read shows the thresholds the rule still uses.
open({ 30, 10 });
h.type('##thresholds', 'soon');
assert(listed(rule().thresholds) == '30, 10' and box() == '30, 10', 'Words it can\'t read go: ' .. box());
h.type('##thresholds', '');
assert(listed(rule().thresholds) == '30, 10' and box() == '30, 10', 'An empty box shows them again too.');
h.type('##thresholds', '20, 5');
assert(listed(rule().thresholds) == '20, 5' and box() == '20, 5', 'What it can read is kept.');

-- Specific member lists a member once the game sent the name, and one saved before then reads in words.
open({ 30, 10 }, function(r) r.scope = 'party'; end);
h.view.context.party = { { id = 7001, name = 'Aerith', scope = 'party' }, { id = 7002, name = '', scope = 'party' },
    { id = 7003, name = '18392', scope = 'party' }, { id = 7004, scope = 'party' } };
local function offered()
    h.combo = '##frame_Specific member';
    h.draw();
    h.combo = nil;
    local found = {};
    for _, call in ipairs(h.calls('Selectable')) do
        if call[2]:find('##%d+$') then found[#found + 1] = call[2]; end;
    end;
    return table.concat(found, ' | ');
end;
assert(offered() == 'Everyone in this scope##0 | Aerith##7001', 'Only a member with a name is offered: ' .. offered());
rule().entity_id = 7003;
h.bump();
h.draw();
assert(h.previews['##frame_Specific member'] == 'A party member', 'A saved member with no name reads in words: '
    .. tostring(h.previews['##frame_Specific member']));
assert(offered() == 'Everyone in this scope##0 | Aerith##7001 | A party member##7003', 'and stays on the list in words: ' .. offered());
h.view.context.party = {};
return 'The alert rule editor keeps rules the alerts can use and the list can show';
