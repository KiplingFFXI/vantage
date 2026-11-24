-- A panel's rows are filtered and sorted again only when something they come from changed (ui/hud.lua place_panels):
-- a new view, which each refresh makes, other settings or a change to them, the hide rules or the units they go by, or
-- the end of a row's countdown. First that no panel is filtered again between refreshes. Then that the rows drawn are
-- the same each frame as rows filtered fresh, with hud.draw driven as vantage.lua drives it: a view made each refresh,
-- its times worked out again each frame between them, and a count of settings changes. Across countdowns that run out
-- between refreshes, setting changes, a new settings table, folded casts, each sort, hide rules, recasts and samples.
local hud, defaults, store = require('ui.hud'), require('ui.defaults'), require('core.store');
local effect_filters = require('core.effect_filters');
local tracker, recasts = require('core.tracker').new(), require('core.recasts').new();
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);

local plain = hud.filter_rows;
local calls, lists, sources = 0, {}, {};
hud.filter_rows = function(view, panel, key, settings, filtering, into)
    calls = calls + 1;
    if into then lists[key], sources[key] = into, view; end
    return plain(view, panel, key, settings, filtering, into);
end;

-- You are 1001, with Bob (1002) and Dave (1003) in your party. A crab (2001) is your target and a bee (2002) is
-- watched. Rows the tracker estimates end at their deadline, and a server row still listed stays at zero.
local ME, BOB, DAVE, CRAB, BEE = 1001, 1002, 1003, 2001, 2002;
local T = 1000;
local held = {};
local function add(row)
    row.instance, row.key = #held + 1, row.key or 'row' .. (#held + 1);
    row.first_seen, row.first_sequence, row.observed_at = row.start or T - 1, #held + 1, T - 1;
    held[#held + 1] = row;
end
local function buff(effect, name, scope, id, who, status, start, total, extra)
    local row = { effect = effect, name = name, kind = 'buff', group = 'Buffs', scope = scope, entity_id = id, entity_name = who,
        status = status, start = start, total = total, deadline = start and total and start + total or nil };
    for field, value in pairs(extra or {}) do row[field] = value; end
    add(row);
end
buff(40, 'Protect', 'self', ME, 'You', 'server', T - 60, 1800, { present = true, source = DAVE, source_name = 'Dave' });
buff(33, 'Haste', 'self', ME, 'You', 'estimated', T - 177.39, 180, { mine = true, source = ME, source_name = 'You' });
buff(43, 'Refresh', 'self', ME, 'You', 'server', T - 145.95, 150, { present = true });
buff(3, 'Poison', 'self', ME, 'You', 'estimated', T - 24.97, 30, { kind = 'debuff', group = 'Debuffs' });
buff(13, 'Slow', 'self', ME, 'You', 'unknown', nil, nil, { kind = 'debuff', group = 'Debuffs', present = true });
-- Dave's Protectra on Bob and Dave, your Haste on each at other times, and a Refresh with no countdown.
buff(40, 'Protect', 'party', BOB, 'Bob', 'estimated', T - 100, 1800, { source = DAVE, source_name = 'Dave' });
buff(40, 'Protect', 'party', DAVE, 'Dave', 'estimated', T - 100, 1800, { source = DAVE, source_name = 'Dave' });
buff(33, 'Haste', 'party', BOB, 'Bob', 'estimated', T - 178.23, 180, { mine = true, source = ME, source_name = 'You' });
buff(33, 'Haste', 'party', DAVE, 'Dave', 'estimated', T - 169.53, 180, { mine = true, source = ME, source_name = 'You' });
buff(43, 'Refresh', 'party', BOB, 'Bob', 'unknown', nil, nil, {});
-- Your Dia and Sleep on the crab, and Dia and Bob's Bio on the bee.
buff(134, 'Dia', 'enemy', CRAB, 'Crab', 'estimated', T - 54.49, 60, { kind = 'debuff', group = 'Debuffs', mine = true, source = ME, source_name = 'You' });
buff(2, 'Sleep', 'enemy', CRAB, 'Crab', 'estimated', T - 56.67, 60, { kind = 'debuff', group = 'Debuffs', mine = true, source = ME, source_name = 'You' });
buff(134, 'Dia', 'enemy', BEE, 'Bee', 'estimated', T - 51.81, 60, { kind = 'debuff', group = 'Debuffs', mine = true, source = ME, source_name = 'You' });
buff(135, 'Bio', 'enemy', BEE, 'Bee', 'estimated', T - 48.87, 60, { kind = 'debuff', group = 'Debuffs', source = BOB, source_name = 'Bob' });
-- Recasts, each gone once the client says it's ready.
local function recast(kind, effect, name, id, start, total)
    add({ key = 'recast:' .. kind .. ':' .. id, domain = 'recast', kind = kind, group = kind .. '_recasts', effect = effect, name = name,
        recast_id = id, scope = 'self', entity_id = ME, status = 'server', present = true, start = start, total = total, deadline = start + total });
end
recast('spell', 10057, 'Haste', 57, T - 13.73, 20);
recast('ability', 20035, 'Provoke', 35, T - 27.79, 30);
recast('spell', 10023, 'Dia', 23, T - 0.1, 10);

local s = defaults.tidy(defaults.make());
for _, key in ipairs(defaults.panel_order) do s.panels[key].enabled = false; end
for _, key in ipairs({ 'self_buffs', 'self_debuffs', 'target', 'party', 'watch', 'spell_recasts', 'ability_recasts' }) do
    s.panels[key].enabled = true;
end
s.panels.recasts.enabled, s.panels.recasts.recast_categories.spell, s.panels.recasts.recast_categories.ability = true, true, true;
s.panels.party.fold_casts, s.panels.party.sort = true, 'longest';
s.watch_ids = { BEE };
s.style.hover = false;

-- What vantage.lua does: a revision counted up by each settings change, a view made each refresh from what the tracker
-- holds, its times worked out each frame between refreshes, and the hide rules' units read again for a new view.
local revision = 0;
local callbacks = { settings_revision = function() return revision; end,
    changed = function(stage) if stage == 'after' then revision = revision + 1; end end };
local roster = { valid = true, id = ME, members = { { id = ME, name = 'You', job = 5, slot = 0, group = 1, available = true },
    { id = BOB, name = 'Bob', job = 3, slot = 1, group = 1, available = true }, { id = DAVE, name = 'Dave', job = 10, slot = 2, group = 1, available = true } } };
local view, snapshot, refreshed, recipients, recipients_from;
local function refresh(t)
    for index = #held, 1, -1 do
        local row = held[index];
        if row.deadline and row.deadline <= t then
            if row.domain == 'recast' then table.remove(held, index);
            elseif not (row.present ~= nil and row.status == 'server') then row.deadline, row.status = nil, 'unknown'; end
        end
    end
    snapshot = { valid = true, id = ME, name = 'You', job = 5, target = { id = CRAB, name = 'Crab', kind = 'enemy' },
        party = { { id = BOB, name = 'Bob', slot = 1, group = 1, scope = 'party', valid = true }, { id = DAVE, name = 'Dave', slot = 2, group = 1, scope = 'party', valid = true } },
        entities = { [CRAB] = { id = CRAB, name = 'Crab', kind = 'enemy' }, [BEE] = { id = BEE, name = 'Bee', kind = 'enemy' } } };
    local rows = {};
    for index, row in ipairs(held) do rows[index] = store.copy(row); end
    view = { valid = true, now = t, rows = rows, context = snapshot, subjects = {} };
    tracker:project(view, t);
    recasts:project(view, t);
    refreshed = t;
end
local function frame(t, using)
    if not refreshed or t - refreshed >= 0.1 then refresh(t);
    else tracker:project(view, t); recasts:project(view, t); end
    using = using or callbacks;
    using.effect_filters = effect_filters.compile(s.effect_filters);
    if using.effect_filters.active and recipients_from ~= snapshot then
        recipients, recipients_from = effect_filters.recipients(snapshot, roster, recipients), snapshot;
    end
    view.effect_recipients = using.effect_filters.active and recipients or nil;
    hud.draw(view, s, t, using);
end
local function shown_panels()
    local count = 0;
    for _, key in ipairs(defaults.panel_order) do if defaults.panel_enabled(s, key) then count = count + 1; end end
    return count;
end

-- Between refreshes no panel is filtered again. Right after one, each one is. With no count of settings changes,
-- each one is every frame.
local t = T;
frame(t);
local panels = shown_panels();
calls = 0;
refreshed = nil;
frame(t);
assert(calls == panels, 'Fixture: a refresh filters each panel shown: ' .. calls .. ' of ' .. panels);
calls = 0;
for _ = 1, 5 do t = t + 1 / 60; frame(t); end
assert(calls == 0, ('Between refreshes no panel is filtered again, %d calls in 5 frames for %d panels'):format(calls, panels));
local bare = {};
calls = 0;
for _ = 1, 5 do t = t + 1 / 120; frame(t, bare); end
assert(calls == 5 * panels, 'With no count of settings changes each panel is filtered every frame: ' .. calls);

-- The rows drawn against rows filtered fresh. A folded row is made again by a fresh filter, so it is compared field by
-- field, but for its time left and time since it landed, which it holds from when it was made and nothing drawn reads
-- from it: its countdown, bar and blink go by its deadline.
local function differs(a, b)
    if a == b then return nil; end
    if not (a and b and a.folded and b.folded) then return 'another row'; end
    for field, value in pairs(a) do
        if field ~= 'remaining' and field ~= 'elapsed' and field ~= 'folded' and b[field] ~= value then return field; end
    end
    for field in pairs(b) do
        if a[field] == nil and field ~= 'remaining' and field ~= 'elapsed' then return field; end
    end
    if #a.folded ~= #b.folded then return 'its members'; end
    for index = 1, #a.folded do if a.folded[index] ~= b.folded[index] then return 'its members'; end end
    return nil;
end
local function names(rows)
    local out = {};
    for index, row in ipairs(rows) do out[index] = tostring(row.name) .. '/' .. tostring(row.entity_name) .. '/' .. tostring(row.status); end
    return table.concat(out, ',');
end
local compared = 0;
local function check(label)
    for _, key in ipairs(defaults.panel_order) do
        if defaults.panel_enabled(s, key) then
            -- This frame's view, or the samples, which hud.draw makes once and fills again each frame.
            local source = view;
            if defaults.any_sampled(s) and defaults.sampled(s, key) then
                source = sources[key];
                assert(source.context.sample, 'Fixture: the samples were filtered for ' .. key);
            end
            local kept, fresh = lists[key], plain(source, s.panels[key], key, s, nil);
            assert(kept and #kept == #fresh, ('%s, %s: %d rows drawn, %d fresh (%s against %s)'):format(label, key, kept and #kept or -1, #fresh,
                names(kept or {}), names(fresh)));
            for index = 1, #fresh do
                local why = differs(kept[index], fresh[index]);
                assert(not why, ('%s, %s: row %d is not the fresh one, by %s (%s against %s)'):format(label, key, index, why, names(kept), names(fresh)));
            end
            compared = compared + 1;
        end
    end
end

-- Each change goes through the settings' own Undo steps, as the settings window and commands do.
local function change(fn) callbacks.changed('before'); fn(); callbacks.changed('after'); end
local party, buffs = s.panels.party, s.panels.self_buffs;
local steps = {
    { 0.53, 'a text filter', function() change(function() party.filter = 'bob'; end); end },
    { 0.91, 'no text filter', function() change(function() party.filter = ''; end); end },
    { 1.29, 'known times only', function() change(function() party.known_only = true; end); end },
    { 1.97, 'oldest first', function() change(function() party.sort = 'oldest'; end); end },
    { 2.39, 'soonest first', function() change(function() party.sort = 'remaining'; end); end },
    { 2.83, 'My order', function() change(function() party.sort, party.order = 'fixed', { 33, 40 }; end); end },
    { 3.17, 'by name, Protect pinned', function() change(function() party.sort, party.pinned[40] = 'name', true; end); end },
    { 3.61, 'longest, Refresh hidden', function() change(function() party.sort, party.pinned[40], party.exclude[43] = 'longest', nil, true; end); end },
    { 4.03, 'Include me', function() change(function() party.include_self, party.known_only = true, false; end); end },
    { 4.41, 'no folds', function() change(function() party.fold_casts = false; end); end },
    { 4.79, 'folds by target', function() change(function() party.fold_casts, party.group_by = true, 'target'; end); end },
    { 5.21, 'a renamed effect found by its name', function() change(function() buffs.labels[33], buffs.filter = 'Speed', 'spe'; end); end },
    { 5.59, 'only mine', function() change(function() buffs.filter, buffs.mine_only = '', true; end); end },
    { 6.07, 'nobody watched', function() change(function() s.watch_ids = {}; end); end },
    { 6.43, 'the bee watched, debuffed listed', function() change(function() s.watch_ids, s.panels.watch.list_debuffed = { BEE }, true; end); end },
    { 6.81, 'Protect hidden on the party', function() change(function()
        local rule = effect_filters.rule();
        rule.effect, rule.scope = 40, 'party';
        s.effect_filters.rules[#s.effect_filters.rules + 1] = rule;
    end); end },
    { 7.23, 'everything on Bob hidden', function() change(function()
        local rule = effect_filters.rule();
        rule.name = 'Bob';
        s.effect_filters.rules[#s.effect_filters.rules + 1] = rule;
    end); end },
    -- The hide rules' units read into a new list and a rule edited, neither with a new view or a change counted.
    { 7.41, 'Bob read again as Robert', function()
        roster.members[2].name = 'Robert';
        recipients, recipients_from = nil, nil;
    end },
    { 7.49, 'a hide rule edited', function() s.effect_filters.rules[1].effect = 33; end },
    { 7.61, 'no hide rules', function() change(function() s.effect_filters.rules = {}; end); end },
    { 8.03, 'only Bob ticked', function() change(function() party.members[BOB] = true; end); end },
    { 8.39, 'only buffs', function() change(function() party.members[BOB], party.groups.Buffs = nil, true; end); end },
    { 8.81, 'recasts in one panel', function() change(function() s.recast_display = 'combined'; end); end },
    -- Undo and a profile put a new settings table in place. This one comes with no change counted.
    { 9.19, 'new settings', function()
        local fresh = store.copy(s);
        fresh.panels.party.filter = 'dave';
        s = fresh;
        party, buffs = s.panels.party, s.panels.self_buffs;
    end },
    { 9.63, 'every panel shows samples', function() change(function() s.preview = true; end); end },
    { 10.41, 'only Party members shows samples', function() change(function() s.preview, s.panels.party.preview = false, true; end); end },
    { 10.97, 'no samples', function() change(function() s.panels.party.preview = false; end); end },
};
local frames, step, label = 0, 1, 'start';
calls = 0;
while t < T + 12 do
    t = t + 1 / 60;
    -- Each step lands between refreshes, so the view stays the same.
    while steps[step] and t >= T + steps[step][1] and t - refreshed < 0.1 do
        label = steps[step][2];
        steps[step][3]();
        step = step + 1;
    end
    frame(t);
    frames = frames + 1;
    check(('%s at %.3f'):format(label, t - T));
end
assert(step > #steps, 'Fixture: every step ran.');
assert(compared > frames * 5, 'Fixture: the panels were compared each frame: ' .. compared);
-- The sameness above is only worth something if most frames kept their rows.
assert(calls < frames * panels / 2, ('Fixture: most frames kept their rows, %d calls in %d frames'):format(calls, frames));
for _, row in ipairs(held) do
    assert(row.domain == 'recast' or row.deadline == nil or row.deadline > T + 12 or row.status == 'server',
        'Fixture: each estimate ran out on the way: ' .. row.name);
end
hud.filter_rows = plain;
return true;
