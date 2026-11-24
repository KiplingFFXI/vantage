-- Alerts is the one place for alerts: your pet's are on its Show tab, with a link from Pet, its presets include Shadows
-- gone and Recast ready, a rule's ways to tell you are in Notice, Chat log, Bar and Sounds groups with the sounds folder
-- named, Utsu finds Copy Image, the ready pulse starts in a color of its own, and each timer panel's Ending soon line
-- colors, marks and blinks by one number.
local h = require('panel_fixture')();
local defaults = require('ui.defaults');
local alerts = require('ui.alert_panel');

-- Pet has none of its alerts, only the line that opens Alerts.
h.fresh(function(s) s.pet.enabled = true; end);
local pet_page = h.every_tab('pet');
for _, name in ipairs({ 'Tell me when my pet\'s HP is low', 'Tell me when my pet has 1000 TP', 'Tell me when a charm or a jug pet is about to end' }) do
    assert(not pet_page[name], 'Pet has no ' .. name);
end;
h.on('pet', 'show');
h.draw('Open Alerts##frame');
h.draw();
assert(h.panels.context():match('^(.-)/') == 'notices', 'Open Alerts opens Alerts.');

-- Alerts has them, writing your pet's settings, each as one Undo step.
h.fresh();
h.on('notices', 'show');
assert(h.says('Your pet') and not h.called('SliderFloat', '##frame_Pet HP is low at'), 'Alerts has Your pet, with the percent only once HP is ticked.');
h.draw('Tell me when my pet\'s HP is low##frame');
h.draw();
assert(h.s.pet.alert_hp == true and #h.app.state.history == 1 and h.app.state.history[1].label == 'Tell me when my pet\'s HP is low',
    'The tick writes your pet\'s alert in one step.');
assert(h.called('SliderFloat', '##frame_Pet HP is low at'), 'The percent shows once it is ticked.');
h.draw('Tell me when my pet has 1000 TP##frame');
h.draw('Tell me when a charm or a jug pet is about to end##frame');
h.draw();
assert(h.s.pet.alert_tp and h.s.pet.alert_ending, 'The other two write theirs.');

-- Shadows gone watches your Copy Image going, on from the start.
h.fresh();
h.on('notices', 'show');
h.draw('Shadows gone##frame');
h.draw();
local rule = h.s.alerts.rules[#h.s.alerts.rules];
assert(rule and rule.name == 'Shadows gone' and rule.effect == 66 and rule.event == 'removed' and rule.scope == 'self' and rule.enabled,
    'Shadows gone adds an alert for your shadows going.');
local count = #h.s.alerts.rules;
h.draw('Shadows gone##frame');
h.draw();
assert(#h.s.alerts.rules == count and h.says('Shadows gone is already on.'), 'Clicked again, it adds no copy.');
-- Recast ready has no recast yet, so each click adds one, off until a recast is chosen.
h.draw('Recast ready##frame');
h.draw();
rule = h.s.alerts.rules[#h.s.alerts.rules];
assert(rule.domain == 'recast' and rule.event == 'ready' and rule.enabled == false and rule.effect == 0, 'Recast ready adds a recast alert, off.');
assert(h.says('It stays off until you choose what it watches.'), 'It says why it is off.');
h.draw('Recast ready##frame');
h.draw();
assert(#h.s.alerts.rules == count + 2, 'Each click adds one.');

-- An open alert groups how it tells you, and names the sounds folder.
h.fresh(function(s)
    local made = defaults.rule('r1');
    made.name, made.effect, made.event = 'Probe', 33, 'remaining';
    s.alerts.rules = { made };
end);
alerts.edit('r1');
h.on('notices', 'show');
local order, seen = {}, {};
for _, call in ipairs(MOCK.imgui_calls) do
    local text = call[1] == 'TextColored' and call[3] or call[2];
    if (text == 'Notice' or text == 'Chat log' or text == 'Bar' or text == 'Sounds') and not seen[text] then order[#order + 1], seen[text] = text, true; end;
end;
assert(table.concat(order, ', ') == 'Notice, Chat log, Bar, Sounds', 'The groups are in order: ' .. table.concat(order, ', '));
assert(h.says('Sounds folder: ' .. require('core.identity').relative('sounds')), 'The sounds folder is named in the window.');
assert(not h.says('reminder'), 'No line says reminder.');
-- Utsu finds Copy Image in the effect picker, and nothing it isn't.
h.typed['##effect_search_Effect'] = 'utsu';
assert(h.lists('Copy Image', 66), 'Utsu lists Copy Image.');
h.typed['##effect_search_Effect'] = 'utsu';
assert(not h.lists('Haste', 33), 'Utsu doesn\'t list Haste.');

-- The ready pulse starts in a color of its own, apart from an alert's flash.
local pulse, flash = defaults.make().ready_pulse.color, defaults.rule('x').flash_color;
assert(pulse[1] ~= flash[1] or pulse[2] ~= flash[2] or pulse[3] ~= flash[3], 'Flash and pulse start in different colors.');

-- Ending soon: one number colors, marks and blinks a timer panel's rows, and says so while the blink starts elsewhere.
local function format() local call = h.calls('SliderFloat', '##frame_Seconds left')[1]; return call and call[6]; end;
h.fresh();
h.on('self_buffs', 'look');
local p = h.s.panels.self_buffs;
assert(p.warning_seconds == 15 and p.blink_seconds == 15 and format() == '%.0f seconds left', 'A fresh panel has one number: ' .. tostring(format()));
assert(h.called('Checkbox', 'Blink##frame'), 'The line has Blink.');
p.blink_seconds = 20;
h.bump(); h.draw();
assert(format() == '%.0f seconds left, blinks at 20', 'It says where the blink starts while it differs: ' .. tostring(format()));
h.slide('##frame_Seconds left', 12);
p = h.s.panels.self_buffs;
assert(p.warning_seconds == 12 and p.blink_seconds == 12 and format() == '%.0f seconds left', 'Moving it sets both.');
h.draw('Blink##frame');
h.draw();
assert(h.s.panels.self_buffs.blink_icons == false, 'Blink unticks this panel\'s blink.');
-- Recasts don't blink, so their Ready soon line has no Blink.
h.fresh(function(s) s.panels.spell_recasts.enabled = true; end);
h.on('spell_recasts', 'look');
assert(not h.called('Checkbox', 'Blink##frame') and h.s.panels.spell_recasts.warning_seconds == 10, 'Recasts have no Blink and keep 10 seconds.');
MOCK.fire('unload');
return 'Alerts is the one place for alerts, and Ending soon is one line';
