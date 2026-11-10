package.loaded['ui.icons'] = { status = function(id) return 5000 + id; end };
-- The strips ask for an icon at the size they draw it; this one has a single size.
package.loaded['ui.icons'].status_at = function(id, artwork) return package.loaded['ui.icons'].status(id, artwork), { 1, 1 }; end;
local filters = require('core.effect_filters');
local defaults, hud = require('ui.defaults'), require('ui.hud');
local party, native = require('ui.party_hud'), require('ui.native_party_hud');
local layout = require('ui.party_layout');
local copy, equal = require('core.store').copy, require('core.customization').equal;
local settings = defaults.make();
local function rule(effect, fields)
    local result = { enabled = true, effect = effect, kind = 'all', name = '', job = 0, scope = 'all' };
    for key, value in pairs(fields or {}) do result[key] = value; end;
    return result;
end;
settings.effect_filters = { enabled = true, rules = {
    rule(253), rule(269), rule(33, { name = ' aStEr ' }), rule(40, { job = 2 }), rule(4, { scope = 'alliance1' }),
} };
local roster, subjects = party.sample(18, 100);
local snapshot = { valid = true, id = roster.id, zone = roster.zone, name = 'Aster', job = 1, party = {}, entities = {},
    target = { id = 1007, name = 'Gale', kind = 'player' } };
local rows = {};
for _, member in ipairs(roster.members) do
    local subject = subjects[member.id];
    subject.effects[#subject.effects + 1] = { effect = 253, name = 'Signet', kind = 'buff', present = true, status = 'unknown' };
    subject.effects[#subject.effects + 1] = { effect = 269, name = 'Level Sync', kind = 'neutral', present = true, status = 'unknown' };
    local scope = member.id == roster.id and 'self' or member.group == 1 and 'party' or 'alliance';
    if member.id ~= roster.id then snapshot.party[#snapshot.party + 1] = {
        id = member.id, name = member.name, group = member.group, slot = member.slot, scope = scope, valid = true,
    }; end;
    for index, entry in ipairs(subject.effects) do
        entry.entity_id, entry.entity_name, entry.scope = member.id, member.name, scope;
        entry.key = member.id .. ':' .. index;
        entry.source_name = 'Aster';
        rows[#rows + 1] = entry;
    end;
end;
rows[#rows + 1] = { key = 'recast', domain = 'recast', effect = 253, kind = 'spell', scope = 'self',
    entity_id = 1001, entity_name = 'Aster', name = 'A recast with a matching number', present = true };
local recipients = filters.recipients(snapshot, roster);
local view = { valid = true, context = snapshot, rows = rows, effect_recipients = recipients };
local source_before = copy({ view = view, subjects = subjects, roster = roster });
local function ids(entries)
    local result = {};
    for _, effect in ipairs(entries or {}) do result[#result + 1] = effect.effect; end;
    table.sort(result);
    return table.concat(result, ',');
end;
assert(ids(hud.filter_rows(view, settings.panels.self_buffs, 'self_buffs', settings)) == '40,56');
assert(ids(hud.filter_rows(view, settings.panels.self_debuffs, 'self_debuffs', settings)) == '4');
assert(ids(hud.filter_rows(view, settings.panels.target, 'target', settings)) == '33,40');
assert(ids(hud.filter_rows(view, settings.panels.spell_recasts, 'spell_recasts', settings)) == '253',
    'Status exclusions never affect recast IDs.');
settings.panels.target.include, settings.panels.target.pinned = { 4, 33, 40 }, { 4 };
assert(ids(hud.filter_rows(view, settings.panels.target, 'target', settings)) == '33,40',
    'A local include or pin cannot restore an effect hidden by a shared rule.');
local party_rows = hud.filter_rows(view, settings.panels.party, 'party', settings);
local bramble = {};
for _, effect in ipairs(party_rows) do if effect.entity_id == 1002 then bramble[#bramble + 1] = effect; end; end;
assert(ids(bramble) == '4,33', 'Job rules use the recipient; the caster Aster does not hide another player\'s Haste.');
local without_jobs = { valid = true, context = snapshot, rows = rows };
bramble = {};
for _, effect in ipairs(hud.filter_rows(without_jobs, settings.panels.party, 'party', settings)) do
    if effect.entity_id == 1002 then bramble[#bramble + 1] = effect; end;
end;
assert(ids(bramble) == '4,33,40', 'An unknown recipient job stays visible.');
local saved_before = copy(settings);
MOCK.screen, MOCK.content_width = { 2400, 2200 }, 700;
settings.style.font, settings.style.font_size = 'Ashita', 14;
settings.party_ui.enabled = true;
local callbacks = { effect_filters = filters.compile(settings.effect_filters), effect_recipients = recipients };
local expected = { [1001] = '4,40,56', [1002] = '4,33', [1003] = '4,33,40', [1007] = '33,40', [1013] = '4,33,40' };
local planned;
local function assert_subjects(selected, label)
    for id, want in pairs(expected) do
        assert(ids(selected[id].effects) == want, label .. ' selects the right effects for ' .. id);
        local visible, hidden = layout.effects(selected[id], settings.party_ui.effects, {});
        assert(ids(visible) == want and hidden == 0, label .. ' excludes intentional hiding from overflow counts.');
    end;
end;
local runtime_settings = copy(settings);

local geometry = { available = true, groups = {} };
for group = 1, 3 do
    local frame = { x = 1500, y = 40 + (group - 1) * 220, width = 116, height = 192, rows = {} };
    for _, member in ipairs(roster.members) do if member.group == group then
        frame.rows[member.slot] = { x = frame.x, y = frame.y + member.slot % 6 * 32, width = 116, height = 32,
            slot = member.slot };
    end; end;
    geometry.groups[group] = frame;
end;
callbacks.native_geometry = geometry;
local native_plan = native.plan;
native.plan = function(current, selected, ...)
    planned = selected;
    return native_plan(current, selected, ...);
end;
for _, detached in ipairs({ false, true }) do
    for _, group in ipairs(settings.party_ui.groups) do group.native_detached = detached; end;
    for _ = 1, 2 do
        planned = nil;
        native.draw(roster, subjects, settings.party_ui, 100, callbacks);
        assert(planned, 'Live strips pass through the real layout.');
        assert_subjects(planned, detached and 'Detached native strip' or 'Attached native strip');
    end;
end;
for _, group in ipairs(settings.party_ui.groups) do group.native_detached = false; end;
callbacks.effect_recipients = nil;
native.draw(roster, subjects, settings.party_ui, 100, callbacks);
assert_subjects(planned, 'Roster fallback');
callbacks.effect_recipients = recipients;
settings.party_ui.preview = true;
native.draw(roster, subjects, settings.party_ui, 100, callbacks);
assert(ids(planned[1001].effects) == '4,40,56' and ids(planned[1002].effects) == '4,33',
    'Native samples keep the real roster identities when replacing only their effect samples.');
settings.party_ui.preview = false;
assert(equal(settings, runtime_settings), 'Rendering keeps every saved setting and lock unchanged.');
assert(equal({ view = view, subjects = subjects, roster = roster }, source_before),
    'Display exclusions leave all tracker rows and source subjects available to alerts and diagnostics.');
assert(#MOCK.font_stack == 0);

settings.effect_filters.enabled = false;
callbacks.effect_filters = filters.compile(settings.effect_filters);
native.draw(roster, subjects, settings.party_ui, 100, callbacks);
assert(planned == subjects, 'Disabled shared filtering keeps the original subject map on the fast path.');
assert(ids(hud.filter_rows(view, settings.panels.self_buffs, 'self_buffs', settings)) == '33,40,56,253,269');
assert(equal(saved_before.effect_filters.rules, settings.effect_filters.rules), 'Compilation never rewrites saved rules.');

settings.effect_filters.enabled = true;
local compile, recipient_map = filters.compile, filters.recipients;
local raw_compiles, maps = 0, 0;
filters.compile = function(value)
    if value == settings.effect_filters then raw_compiles = raw_compiles + 1; end;
    return compile(value);
end;
filters.recipients = function(...)
    maps = maps + 1;
    return recipient_map(...);
end;
local compiled = compile(settings.effect_filters);
hud.draw(view, settings, 100, { effect_filters = compiled });
assert(raw_compiles == 0 and maps == 0, 'A live timer draw reuses the compiled rules and recipient map.');
raw_compiles, maps = 0, 0;
hud.draw(without_jobs, settings, 100, {});
assert(raw_compiles == 1 and maps == 1, 'Fallback rules and recipients resolve once for all timer panels.');
raw_compiles, maps = 0, 0;
hud.copy_text(without_jobs, settings, nil, false, 100);
assert(raw_compiles == 1 and maps == 1, 'Copying all visible panels also resolves shared filtering once.');
filters.compile, filters.recipients = compile, recipient_map;
settings.effect_filters.rules = { rule(33, { name = 'You' }), rule(42, { job = 3 }) };
local sample = hud.sample(100);
assert(ids(hud.filter_rows(sample, settings.panels.self_buffs, 'self_buffs', settings)) == '40,41,214,214,251');
assert(ids(hud.filter_rows(sample, settings.panels.party, 'party', settings)) == '3,78',
    'Timer samples carry coherent known jobs and player identities.');
local selected_rows = {};
local select_rows = hud.filter_rows;
hud.filter_rows = function(current, panel, key, ...)
    local selected = select_rows(current, panel, key, ...);
    selected_rows[key] = selected;
    return selected;
end;
settings.preview = true;
hud.draw(view, settings, 100, { effect_filters = compile(settings.effect_filters), effect_recipients = recipients });
assert(ids(selected_rows.self_buffs) == '40,41,214,214,251',
    'Timer preview uses sample recipients even when callbacks contain the real player metadata.');
hud.filter_rows = select_rows;
