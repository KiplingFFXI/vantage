-- What an export from a stranger can't do: stop the settings window or hold the game up.
local share = require('core.share');
local store = require('core.store');
local defaults = require('ui.defaults');
local filters = require('core.effect_filters');
local durations = require('core.durations');
local settings = defaults.tidy(defaults.make());
local function string_of(body) return 'VG:1:' .. share.crc32(body) .. ':' .. body; end;

-- share.read checks names, not types, so each of these reads as good and comes apart in share.candidate.
local wrong = {
    { 'add', '{"kind":"layout","data":{"panels":{"target":5}}}' },
    { 'replace', '{"kind":"layout","data":{"panels":{"target":5}}}' },
    { 'add', '{"kind":"layout","data":{"panels":"x"}}' },
    { 'replace', '{"kind":"layout","data":{"panels":5}}' },
    { 'add', '{"kind":"filters","data":{"effect_filters":{"rules":"x"}}}' },
    { 'add', '{"kind":"alerts","data":{"rules":5}}' },
    { 'add', '{"kind":"alerts","data":{"rules":true}}' },
    { 'add', '{"kind":"profile","data":{"panels":5}}' },
    -- Rules that are a number, true, false, text or a table with names would be read as none, so Replace would wipe
    -- yours. They're refused as Add refuses them, and so are filters that aren't a table. A whole profile string's
    -- alert rules, hide rules and duration overrides are refused the same way.
    { 'replace', '{"kind":"alerts","data":{"rules":5}}' },
    { 'replace', '{"kind":"alerts","data":{"rules":true}}' },
    { 'replace', '{"kind":"alerts","data":{"rules":false}}' },
    { 'replace', '{"kind":"alerts","data":{"rules":"x"}}' },
    { 'add', '{"kind":"alerts","data":{"rules":false}}' },
    { 'replace', '{"kind":"filters","data":{"effect_filters":{"rules":"x"}}}' },
    { 'replace', '{"kind":"filters","data":{"effect_filters":{"rules":5}}}' },
    { 'replace', '{"kind":"filters","data":{"effect_filters":5}}' },
    { 'replace', '{"kind":"filters","data":{"effect_filters":"x"}}' },
    { 'add', '{"kind":"filters","data":{"effect_filters":5}}' },
    { 'replace', '{"kind":"alerts","data":{"rules":{"a":{}}}}' },
    { 'replace', '{"kind":"filters","data":{"effect_filters":{"rules":{"a":{}}}}}' },
    { 'replace', '{"kind":"profile","data":{"alerts":{"rules":5}}}' },
    { 'replace', '{"kind":"profile","data":{"alerts":{"rules":{"a":{}}}}}' },
    { 'replace', '{"kind":"profile","data":{"effect_filters":{"rules":"x"}}}' },
    { 'replace', '{"kind":"profile","data":{"durations":{"overrides":5}}}' },
    { 'replace', '{"kind":"profile","data":{"durations":{"overrides":{"a":{}}}}}' },
    { 'add', '{"kind":"profile","data":{"alerts":{"rules":true}}}' },
    -- Anything else that isn't a table where the settings hold one would be read as none or as the default, and so
    -- would a list the settings read in order written as a table with names. A whole profile or One display string
    -- holding one is refused too.
    { 'replace', '{"kind":"profile","data":{"panels":{"target":5}}}' },
    { 'replace', '{"kind":"profile","data":{"panels":{"target":{"include":"x"}}}}' },
    { 'replace', '{"kind":"profile","data":{"panels":{"target":{"pinned":true}}}}' },
    { 'replace', '{"kind":"profile","data":{"party_ui":{"effects":{"include":5}}}}' },
    { 'replace', '{"kind":"profile","data":{"party_ui":{"effects":{"pinned":{"a":40}}}}}' },
    { 'replace', '{"kind":"profile","data":{"party_cooldowns":{"ignore":5}}}' },
    { 'replace', '{"kind":"profile","data":{"party_cooldowns":{"list":{"jobs":"x"}}}}' },
    { 'add', '{"kind":"profile","data":{"panels":{"target":false}}}' },
    { 'replace', '{"kind":"element","element":"target","data":{"exclude":5}}' },
    { 'replace', '{"kind":"element","element":"party_ui","data":{"effects":{"exclude":{"a":40}}}}' },
    { 'add', '{"kind":"element","element":"cooldown_list","data":{"ignore":"x"}}' },
    -- A list tidy reads in order with a gap, which JSON's null leaves, loses what comes after the gap or goes back to
    -- the default. One written as a table with names reads as none.
    { 'replace', '{"kind":"alerts","data":{"rules":[null,{}]}}' },
    { 'replace', '{"kind":"profile","data":{"durations":{"overrides":[null,{}]}}}' },
    { 'replace', '{"kind":"element","element":"party_ui","data":{"effects":{"include":[null,40]}}}' },
    { 'replace', '{"kind":"element","element":"target","data":{"order":{"1":40}}}' },
    { 'replace', '{"kind":"element","element":"target","data":{"field_order":{"1":"name"}}}' },
    { 'replace', '{"kind":"profile","data":{"edit_mode":{"grid_displays":{"a":"target"}}}}' },
    { 'replace', '{"kind":"profile","data":{"party_ui":{"groups":[{"order":[null,1]}]}}}' },
};
-- Lists and maps the settings hold still read from a good string, whether a map's keys come back as text or not.
local fine = assert(share.read(string_of('{"kind":"profile","data":{"panels":{"target":{"include":{"40":true},"order":[40,33]}},'
    .. '"party_ui":{"effects":{"pinned":[40]}},"party_cooldowns":{"ignore":{"5":true}}}}')), 'Fixture: a good string reads.');
local took = assert(share.candidate(settings, fine, 'replace'), 'A good string with lists and maps applies.');
assert(took.panels.target.include[40] and took.panels.target.order[1] == 40 and took.party_ui.effects.pinned[1] == 40
    and took.party_cooldowns.ignore[5], 'It takes them.');
for _, case in ipairs(wrong) do
    local payload = assert(share.read(string_of(case[2])), 'Fixture: it reads as good: ' .. case[2]);
    local ok, candidate, why = pcall(share.candidate, settings, payload, case[1]);
    assert(ok, 'It does not raise: ' .. case[2] .. ' ' .. tostring(candidate));
    assert(candidate == nil and why == 'That export holds settings that are not valid.', 'It says why: ' .. case[2]);
end;
local good = assert(share.read(string_of('{"kind":"layout","data":{"panels":{"target":{"x":700}}}}')), 'Fixture: a good string reads.');
assert(share.candidate(settings, good, 'replace').panels.target.x == 700, 'A good string still applies.');

-- The trim on a name takes seconds on a long run of spaces, so a name that long never reaches it, and is refused.
local inner = 'a' .. string.rep(' ', 64000) .. 'b';
local match, trims = string.match, 0;
string.match = function(value, pattern, ...)
    if pattern == '^%s*(.-)%s*$' and #value > 256 then trims = trims + 1; end;
    return match(value, pattern, ...);
end;
assert(#filters.tidy({ rules = { { name = inner } } }).rules == 0, 'A hide rule with that name is refused, never made broader.');
assert(durations.unit_name(inner) == '', 'That is no unit name.');
string.match = match;
assert(trims == 0, 'Neither reaches the trim.');
assert(filters.tidy({ rules = { { name = '  Crawler  ' } } }).rules[1].name == 'Crawler', 'A real name is still trimmed.');
assert(durations.unit_name('  Crawler  ') == 'Crawler', 'A real unit name is still trimmed.');
assert(filters.tidy({ rules = { { name = string.rep(' ', 240) .. 'Crawler' } } }).rules[1].name == 'Crawler',
    'Spaces around a name are trimmed up to the length that is checked first.');
assert(durations.unit_name(string.rep(' ', 240) .. 'Crawler') == 'Crawler', 'So are a unit name\'s.');

-- A list of rules is looked at up to the 128 it can hold.
local full = store.copy(settings);
for index = 1, 128 do full.effect_filters.rules[index] = filters.rule(); full.effect_filters.rules[index].effect = index; end;
local many = {};
for index = 1, 80000 do many[index] = {}; end;
local customization = require('core.customization');
local equal, compared = customization.equal, 0;
customization.equal = function(...) compared = compared + 1; return equal(...); end;
local tidied = assert(share.candidate(full, { kind = 'filters', data = { effect_filters = { rules = many } } }, 'add'), 'Fixture: Add reads.');
customization.equal = equal;
assert(#tidied.effect_filters.rules == 128 and compared < 1000, 'A full list stops at once: ' .. compared .. ' compared.');
local one = store.copy(settings);
one.effect_filters.rules[1] = filters.rule();
local again = {};
for index = 1, 128 do again[index] = filters.rule(); end;
again[129] = filters.rule();
again[129].effect = 9;
tidied = assert(share.candidate(one, { kind = 'filters', data = { effect_filters = { rules = again } } }, 'add'), 'Fixture: Add reads.');
assert(#tidied.effect_filters.rules == 1, 'A rule past the 128th is not looked at.');
local some = store.copy(settings);
some.effect_filters.rules[1] = filters.rule();
some.effect_filters.rules[1].effect = 1;
local others = { filters.rule(), filters.rule(), filters.rule() };
others[1].effect, others[2].effect, others[3].effect = 1, 2, 3;
tidied = assert(share.candidate(some, { kind = 'filters', data = { effect_filters = { rules = others } } }, 'add'), 'Fixture: Add reads.');
assert(#tidied.effect_filters.rules == 3 and tidied.effect_filters.rules[3].effect == 3, 'Add still takes what is new, after what is held.');
return 'Hostile exports refused';
