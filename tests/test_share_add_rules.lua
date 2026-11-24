-- Import and add with an Alert rules string (core/share.lua) adds the string's rules after yours and skips each one
-- you already have, as the guide says. A rule that is yours once tidied counts as the same, whatever the string's text
-- looks like: one kept to Only on these main jobs with jobs that aren't a run from WAR, such as WHM alone, which the
-- string writes with its job as text ("3"), and one from a string made by Vantage 1.3.0, whose rules had no notice
-- colors. Adding the same string again adds nothing more, and rules that are a number, true or text are still refused.
local share, defaults, store = require('core.share'), require('ui.defaults'), require('core.store');
local starters = require('core.starters');
local NAME = 'Tester';

local function fresh() return defaults.tidy(defaults.make()); end;
local function string_of(payload)
    local body = store.encode(payload);
    return 'VG:1:' .. share.crc32(body) .. ':' .. body;
end;
-- What the page's preview says an import changes.
local function said(settings, candidate)
    return type(candidate) == 'table' and table.concat(share.changes(settings, candidate), ' | ') or 'no settings';
end;
-- Settings with one alert rule for Protect (effect 40), kept to the main jobs given.
local function protect_on(jobs)
    local settings = fresh();
    local rule = defaults.rule('rule_1');
    rule.name, rule.effect, rule.jobs = 'Protect reminder', 40, jobs;
    settings.alerts.rules = { rule };
    return defaults.tidy(settings);
end;
local function job_list(rule)
    local list = {};
    for job in pairs(rule.jobs) do list[#list + 1] = tostring(job) .. ':' .. type(job); end;
    table.sort(list);
    return table.concat(list, ',');
end;

-- 1. A rule kept to WHM alone, which any version writes with its job as text.
local held = protect_on({ [3] = true });
assert(#held.alerts.rules == 1 and held.alerts.rules[1].effect == 40 and job_list(held.alerts.rules[1]) == '3:number',
    'Fixture: you have one rule, kept to WHM alone: ' .. job_list(held.alerts.rules[1]));
-- The same rule kept to WAR and MNK, a run from WAR, reads back with its jobs as numbers.
local run = protect_on({ [1] = true, [2] = true });
assert(job_list(run.alerts.rules[1]) == '1:number,2:number', 'Fixture: the other rule is kept to WAR and MNK.');
local run_added = share.candidate(run, assert(share.read(assert(share.export(run, 'alerts', nil, NAME)))), 'add');
assert(type(run_added) == 'table' and #run_added.alerts.rules == 1 and said(run, run_added) == 'Nothing changes.',
    'Add skips the same rule kept to WAR and MNK: ' .. said(run, run_added));
local text = share.export(held, 'alerts', nil, NAME);
assert(type(text) == 'string' and text:find('"jobs":{"3":true}', 1, true), 'Fixture: the string writes the job as text: ' .. tostring(text));
local payload = share.read(text);
assert(type(payload) == 'table' and payload.kind == 'alerts' and #payload.data.rules == 1, 'Fixture: the string reads back with your one rule.');
local replaced = share.candidate(held, payload, 'replace');
assert(said(held, replaced) == 'Nothing changes.',
    'Fixture: Import and replace with it changes nothing, so it holds the rule you have: ' .. said(held, replaced));
local added = share.candidate(held, payload, 'add');
assert(type(added) == 'table' and #added.alerts.rules == 1 and said(held, added) == 'Nothing changes.',
    'Add skips the rule kept to WHM alone you already have: ' .. said(held, added));

-- 2. The Silenced rule a starter adds, from a string made by Vantage 1.3.0, which had no notice colors in a rule.
local healer = assert(starters.apply(fresh(), 'healer'), 'Fixture: the Healer starter applies.');
local silenced = healer.alerts.rules;
assert(#silenced == 1 and silenced[1].name == 'Silenced' and silenced[1].effect == 6 and silenced[1].event == 'gain'
    and type(silenced[1].notice_colors) == 'table' and next(silenced[1].notice_colors) == nil,
    'Fixture: you have the Silenced starter rule, with no notice colors of its own.');
local today = assert(share.read(assert(share.export(healer, 'alerts', nil, NAME))));
local today_added = share.candidate(healer, today, 'add');
assert(type(today_added) == 'table' and #today_added.alerts.rules == 1 and said(healer, today_added) == 'Nothing changes.',
    'Add skips it from a string this Vantage made: ' .. said(healer, today_added));
local older = store.copy(today);
for _, rule in ipairs(older.data.rules) do rule.notice_colors = nil; end;
local old = share.read(string_of(older));
assert(type(old) == 'table' and #old.data.rules == 1 and old.data.rules[1].name == 'Silenced' and old.data.rules[1].notice_colors == nil,
    'Fixture: this Vantage reads the 1.3.0 string, whose Silenced rule has no notice colors.');
local old_replaced = share.candidate(healer, old, 'replace');
assert(said(healer, old_replaced) == 'Nothing changes.',
    'Fixture: Import and replace with it changes nothing, so it holds the rule you have: ' .. said(healer, old_replaced));
local old_added = share.candidate(healer, old, 'add');
assert(type(old_added) == 'table' and #old_added.alerts.rules == 1 and said(healer, old_added) == 'Nothing changes.',
    'Add skips the Silenced rule from a 1.3.0 string: ' .. said(healer, old_added));

-- 3. A rule you don't have goes in once. Adding the same string again adds nothing more.
local both = store.copy(older);
both.data.rules[2] = store.copy(payload.data.rules[1]);
both.data.rules[2].notice_colors = nil;
local strings = { { 'the rule kept to WHM alone', payload, 1 }, { 'the Silenced rule from a 1.3.0 string', old, 1 },
    { 'both from a 1.3.0 string', assert(share.read(string_of(both))), 2 } };
for _, case in ipairs(strings) do
    local none = fresh();
    local once = share.candidate(none, case[2], 'add');
    assert(type(once) == 'table' and #once.alerts.rules == case[3], case[1] .. ': the first Add takes it: ' .. said(none, once));
    local twice = share.candidate(once, case[2], 'add');
    assert(type(twice) == 'table' and #twice.alerts.rules == case[3] and said(once, twice) == 'Nothing changes.',
        case[1] .. ': a second Add of the same string adds nothing: ' .. said(once, twice));
end;

-- 4. Rules that are a number, true or text are refused, never read as none, and a string with no rules adds none.
for _, rules in ipairs({ 5, true, 'x' }) do
    local read = assert(share.read(string_of({ kind = 'alerts', data = { rules = rules } })), 'Fixture: it reads as good: ' .. tostring(rules));
    local candidate, why = share.candidate(held, read, 'add');
    assert(candidate == nil and why == 'That export holds settings that are not valid.', 'Rules of ' .. tostring(rules) .. ' are refused: ' .. tostring(why));
end;
local empty = share.candidate(held, assert(share.read(string_of({ kind = 'alerts', data = {} }))), 'add');
assert(said(held, empty) == 'Nothing changes.', 'A string with no rules adds none: ' .. said(held, empty));

return 'Import and add skips an alert rule you already have, one kept to WHM alone or one from a 1.3.0 string, and adds a new one once';
