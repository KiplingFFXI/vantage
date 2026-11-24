-- Exports (core/share.lua) look for your names in text you typed, never in the settings' own keys or in a choice from
-- a list, so a character that shares its name with one keeps it. A choice kept as a map key counts too: When to show's
-- kinds of zone and groups on every display, a panel's own colors, its part maps and the kinds of effect it shows, and
-- the alert notices' and a rule's own text color. A hide rule's kind and scope are choices as well. A name in a label
-- you typed is still blanked.
local share, defaults, json = require('core.share'), require('ui.defaults'), require('core.json');
local conditions, elements = require('core.conditions'), require('ui.elements');
local function fresh() return defaults.tidy(defaults.make()); end;
local function data_of(text) return json.decode(text:match('^VG:1:%x+:(.+)$')).data; end;

-- Settings with a choice of each kind set. Each choice is a word a character can be named, and a key joined with _ is
-- found by either of its words. Every display shows only in a party in towns.
local s = fresh();
for _, element in ipairs(elements.list) do
    local set = elements.conditions(s, element.id);
    set.group, set.zones = { party = true }, { town = true };
end;
local buffs = s.panels.self_buffs;
buffs.conditions.zones.mog_house = true;
s.pet.conditions.zones.field = true;
buffs.colors = { title = { 1, 0, 0, 1 }, fill_start = { 0, 1, 0, 1 }, fill_end = { 0, 0, 1, 1 } };
buffs.field_labels, buffs.field_alignments = { name = 'Spell', target = 'Party pick' }, { time = 'right' };
buffs.field_newlines, buffs.field_dividers, buffs.field_priority = { source = true }, { elapsed = '/' }, { total = 70 };
buffs.field_colors = { name = { 1, 1, 0, 1 } };
buffs.groups = { Food = true, Songs = true };
s.alerts.notice_colors = { text = { 1, 0, 0, 1 } };
local rule = defaults.rule('rule_1');
rule.notice_colors = { text = { 0, 1, 0, 1 } };
s.alerts.rules = { rule };
s.effect_filters.rules = { { enabled = true, effect = 253, kind = 'buff', name = '', job = 3, scope = 'party' } };
s = defaults.tidy(s);

-- What of those choices data has lost: a panel's own, the rest from a whole profile.
local function panel_lost(p, out)
    local function need(ok, what) if not ok then out[#out + 1] = what; end; end;
    need(p.conditions.group.party == true, 'In a party');
    need(p.conditions.zones.town == true and p.conditions.zones.mog_house == true, 'Towns and Mog House');
    need(p.colors.title and p.colors.fill_start and p.colors.fill_end, 'the title and bar fill colors');
    need(p.field_labels.name == 'Spell', 'the name part\'s label');
    need(p.field_alignments.time == 'right', 'the time part\'s alignment');
    need(p.field_newlines.source == true and p.field_dividers.elapsed == '/' and p.field_priority.total == 70 and p.field_colors.name,
        'the other part maps');
    need(p.groups.Food == true and p.groups.Songs == true, 'the kinds Food and Songs');
    return out;
end;
local function profile_lost(data)
    local out = panel_lost(data.panels.self_buffs, {});
    for _, element in ipairs(elements.list) do
        local set = elements.conditions(data, element.id);
        if not (set and set.group.party == true and set.zones.town == true) then out[#out + 1] = element.label .. '\'s When to show'; end;
    end;
    if data.pet.conditions.zones.field ~= true then out[#out + 1] = 'the Pet display\'s Fields'; end;
    if not data.alerts.notice_colors.text then out[#out + 1] = 'the notices\' text color'; end;
    if not data.alerts.rules[1].notice_colors.text then out[#out + 1] = 'the rule\'s text color'; end;
    local hide = data.effect_filters.rules[1];
    if not (hide and hide.kind == 'buff' and hide.scope == 'party' and hide.job == 3 and hide.effect == 253) then
        out[#out + 1] = 'the hide rule\'s kind, scope or job';
    end;
    return out;
end;
assert(#profile_lost(s) == 0, 'Fixture: the settings hold every choice: ' .. table.concat(profile_lost(s), ', '));

local characters = { 'Tester', 'Party', 'Town', 'Mog', 'House', 'Field', 'Title', 'Fill', 'Start', 'End', 'Name', 'Time', 'Right',
    'Source', 'Elapsed', 'Total', 'Food', 'Songs', 'Text', 'Buff', 'Scope', 'Job', 'Kind', 'Effect' };
for _, character in ipairs(characters) do
    local text, why = share.export(s, 'profile', nil, character);
    assert(text, character .. ' exports a whole profile: ' .. tostring(why));
    local missing = profile_lost(data_of(text));
    assert(#missing == 0, character .. ': a whole profile keeps every choice, but lost ' .. table.concat(missing, ', '));
    text, why = share.export(s, 'element', 'self_buffs', character);
    assert(text, character .. ' exports Self buffs: ' .. tostring(why));
    missing = panel_lost(data_of(text), {});
    assert(#missing == 0, character .. ': One display keeps every choice, but lost ' .. table.concat(missing, ', '));
end;
-- The other kinds that hold one of them.
for _, character in ipairs({ 'Party', 'Town', 'Text' }) do
    local notices = data_of(assert(share.export(s, 'element', 'notices', character)));
    assert(notices.notice_colors.text and notices.notice_conditions.group.party == true and notices.notice_conditions.zones.town == true,
        character .. ': the Alerts display keeps its text color and When to show.');
end;
assert(data_of(assert(share.export(s, 'element', 'pet', 'Field'))).conditions.zones.field == true, 'The Pet display keeps Fields.');
assert(data_of(assert(share.export(s, 'alerts', nil, 'Text'))).rules[1].notice_colors.text, 'Alert rules keep a rule\'s text color.');
for _, character in ipairs({ 'Party', 'Buff', 'Scope', 'Job', 'Kind' }) do
    local hide = data_of(assert(share.export(s, 'filters', nil, character))).effect_filters.rules[1];
    assert(hide and hide.kind == 'buff' and hide.scope == 'party' and hide.job == 3,
        character .. ': the Hide list keeps the hide rule\'s kind, scope and job.');
end;

-- A label you typed is still looked at. One that holds the name is blanked, and one that doesn't stays.
local labels = data_of(assert(share.export(s, 'profile', nil, 'Party'))).panels.self_buffs.field_labels;
assert(labels.target == '' and labels.name == 'Spell', 'A typed label that holds the name is blanked: ' .. tostring(labels.target));
assert(data_of(assert(share.export(s, 'profile', nil, 'Tester'))).panels.self_buffs.field_labels.target == 'Party pick',
    'and one that doesn\'t stays.');

-- The one who imports gets the display as it was set.
local got = share.candidate(fresh(), assert(share.read(assert(share.export(s, 'profile', nil, 'Party')))), 'replace');
local said = table.concat(conditions.describe(got.panels.self_buffs.conditions), ' ');
assert(said == 'In Towns or Mog House. While in a party.', 'Imported, the display shows where it was set to: ' .. said);

return 'An export keeps every choice that shares its name with a character';
