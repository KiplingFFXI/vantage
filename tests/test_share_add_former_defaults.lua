-- Import and add (core/share.lua) takes every setting you never changed. A settings file saved by 1.3.0 still holds
-- what 1.3.0 started with where this version starts with something else (defaults.former): the timer panels' Seconds
-- left at 10 and the gold ready pulse. Add counts those as never changed too, as it does a fresh install's, and still
-- keeps a value you picked.
local share, defaults, store, json = require('core.share'), require('ui.defaults'), require('core.store'), require('core.json');
local equal = require('core.customization').equal;
local function fresh() return defaults.tidy(defaults.make()); end;
-- Settings as a reload reads them back from the saved file.
local function reloaded(settings) return defaults.tidy(json.decode(store.encode(settings))); end;
local function export(settings, kind, id)
    local text, why = share.export(settings, kind, id, 'Tester');
    assert(text, 'Fixture: ' .. kind .. ' exports: ' .. tostring(why));
    return assert(share.read(text));
end;
local timers = { 'self_buffs', 'self_debuffs', 'target', 'party', 'watch' };
local GOLD, BLUE = { 1, 0.86, 0.45, 1 }, { 0.2, 0.4, 1, 1 };

-- What 1.3.0 started with, which differs from what this version starts with.
local start = defaults.make();
for _, id in ipairs(timers) do
    assert(start.panels[id].warning_seconds ~= 10, 'Fixture: ' .. id .. ' no longer starts at 10 seconds left.');
end;
assert(not equal(start.ready_pulse.color, GOLD), 'Fixture: the ready pulse no longer starts gold.');

-- An upgrader who never changed either: 1.3.0 saved what it started with, and this version reads it back.
local upgrader = fresh();
for _, id in ipairs(timers) do upgrader.panels[id].warning_seconds = 10; end;
upgrader.ready_pulse.color = { 1, 0.86, 0.45, 1 };
upgrader = reloaded(upgrader);
local theirs = fresh();
for _, id in ipairs(timers) do theirs.panels[id].warning_seconds = 20; end;
theirs.ready_pulse.color = { 0.2, 0.4, 1, 1 };
theirs = defaults.tidy(theirs);

local candidate = assert(share.candidate(upgrader, export(theirs, 'profile'), 'add'));
for _, id in ipairs(timers) do
    assert(candidate.panels[id].warning_seconds == 20, 'Whole profile: Add takes the export\'s Seconds left on ' .. id
        .. ' for an upgrader who never changed it, but it is ' .. candidate.panels[id].warning_seconds);
end;
assert(equal(candidate.ready_pulse.color, BLUE), 'Whole profile: and the export\'s ready pulse color.');
for _, id in ipairs(timers) do
    candidate = assert(share.candidate(upgrader, export(theirs, 'element', id), 'add'));
    assert(candidate.panels[id].warning_seconds == 20, 'One display: Add takes the export\'s Seconds left on ' .. id .. ': '
        .. candidate.panels[id].warning_seconds);
end;
candidate = assert(share.candidate(upgrader, export(theirs, 'element', 'pulse'), 'add'));
assert(equal(candidate.ready_pulse.color, BLUE), 'One display: Add takes the export\'s ready pulse color.');

-- A value you picked stays.
local picked = store.copy(upgrader);
picked.panels.target.warning_seconds, picked.ready_pulse.color = 12, { 0.9, 0.1, 0.1, 1 };
candidate = assert(share.candidate(picked, export(theirs, 'profile'), 'add'));
assert(candidate.panels.target.warning_seconds == 12 and candidate.panels.self_buffs.warning_seconds == 20,
    'Add keeps the Seconds left you picked and takes the rest.');
assert(equal(candidate.ready_pulse.color, { 0.9, 0.1, 0.1, 1 }), 'and keeps the ready pulse color you picked.');

-- Import and replace takes the export's either way, as before.
candidate = assert(share.candidate(picked, export(theirs, 'profile'), 'replace'));
assert(candidate.panels.target.warning_seconds == 20 and equal(candidate.ready_pulse.color, BLUE), 'Replace takes what the export holds.');
