-- When to show: Main job, Support job and Where each fold to a line that says what they pick, and each can show a display
-- for what is ticked or for everything else.
local conditions = require('core.conditions');
local h = require('panel_fixture')();

-- The rule: Only these holds for a pick, All but these for anything else, and an empty list for anything.
local value = conditions.make();
local at = { valid = true, job = 3, sub_job = 5, level = 75, synced = false, kind = 'town', battlefield = false, group = 'solo', engaged = false, pet = false };
value.main_jobs[3] = true;
assert(conditions.holds(value, at), 'Only these holds for WHM.');
value.main_except = true;
assert(not conditions.holds(value, at), 'All but these doesn\'t hold for WHM.');
at.job = 4;
assert(conditions.holds(value, at), 'All but these holds for BLM.');
value = conditions.make();
value.sub_jobs[5], value.sub_except = true, true;
at.sub_job = 0;
assert(conditions.holds(value, at), 'No support job is all but RDM.');
value = conditions.make();
value.zones.town, value.zones_except = true, true;
assert(not conditions.holds(value, at), 'All but Towns doesn\'t hold in a town.');
at.kind = 'field';
assert(conditions.holds(value, at), 'It holds in a field.');
value.zones.battlefield, at.battlefield = true, true;
assert(not conditions.holds(value, at), 'All but Battlefields doesn\'t hold with the Battlefield status.');
-- An All but these with nothing ticked is no condition.
value = conditions.make();
value.main_except = true;
assert(not conditions.any(value) and conditions.holds(value, at), 'All but nothing is no condition.');

-- The words: the summary line and each fold's title.
value = conditions.make();
value.main_jobs[3], value.main_jobs[5], value.main_except = true, true, true;
value.zones.town, value.zones.dynamis = true, true;
local said = table.concat(conditions.describe(value), ' ');
assert(said == 'Any main job but WHM and RDM. In Towns or Dynamis.', said);
assert(conditions.picks(value, 'main_jobs') == 'all but WHM and RDM' and conditions.picks(value, 'zones') == 'Towns or Dynamis'
    and conditions.picks(value, 'sub_jobs') == 'any', 'The titles say what each picks.');
value.zones_except = true;
assert(table.concat(conditions.describe(value), ' ') == 'Any main job but WHM and RDM. Anywhere but Towns and Dynamis.', 'Anywhere but.');
-- Tidy keeps All but these, and an older save without it is Only these.
local tidied = conditions.tidy({ main_jobs = { [3] = true }, main_except = true, zones = { town = true } });
assert(tidied.main_except == true and tidied.sub_except == false and tidied.zones_except == false, 'Tidy keeps the lists\' choice.');

-- The tab: each list starts folded, titled any, and the rest show as they did.
h.fresh();
h.on('self_buffs', 'when');
for _, title in ipairs({ 'Main job: any##Main job', 'Support job: any##Support job', 'Where: any##Where' }) do
    assert(h.called('CollapsingHeader', title), 'Folded: ' .. title);
end;
-- Each starts closed. The test's headers always open, so this reads the rows.
local folds = 0;
for _, row in ipairs(require('ui.condition_settings').rows) do
    if row.kind == 'fold' then folds = folds + 1; assert(row.opened ~= true, row.text .. ' starts folded.'); end;
end;
assert(folds == 3, 'Three lists fold: ' .. folds);
assert(h.called('SliderFloat', '##frame_From_min'), 'Level shows as it did.');
-- Opened, it ticks a job and picks All but these, each as one Undo step, and the title follows.
h.s.window.sections['Panels/Main job'] = true;
h.bump(); h.draw();
h.draw('WHM##frame_main');
h.draw();
local set = h.s.panels.self_buffs.conditions;
assert(set.main_jobs[3] == true and h.called('CollapsingHeader', 'Main job: WHM##Main job'), 'Ticked, the title says WHM.');
h.draw('All but these##frame_Show it for_main_list_except');
h.draw();
set = h.s.panels.self_buffs.conditions;
assert(set.main_except == true and h.called('CollapsingHeader', 'Main job: all but WHM##Main job'), 'All but these: the title says so.');
assert(h.says('Self buffs: Any main job but WHM.'), 'The summary line says so too.');
MOCK.fire('unload');
return 'Main job, Support job and Where fold to what they pick, and each can show for everything but its ticks';
