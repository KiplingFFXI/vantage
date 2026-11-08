package.loaded['core.catalog'] = {get = function(id)
    return {id = id, name = 'Effect ' .. id, kind = id < 32 and 'debuff' or 'buff', group = 'Test'};
end};
local Tracker = require('core.tracker');
local copy = require('core.store').copy;
local function snapshot(effects)
    return {valid = true, id = 10, name = 'Self', zone = 1, self_known = true,
        self_effects = effects or {}, party = {}, entities = {}, self_revision = 1};
end;
local function by_effect(view, id, effect)
    for _, row in ipairs(view.rows) do
        if row.entity_id == id and row.effect == effect then return row; end;
    end;
end;
local function unchanged(row, before)
    assert(row and row.key == before.key and row.first_seen == before.first_seen
        and row.first_sequence == before.first_sequence,
        'Continuous presence keeps its first observation through timer and slot changes.');
end;
local model = Tracker.new();
local current = snapshot();
for index = 1, 12 do
    current.self_effects[index] = {effect = 39 + index, slot = index - 1,
        deadline = index % 2 == 1 and 200 + index or nil, raw_timer = index % 2 == 1 and 12000 + index or 0};
end;
model:reconcile(current, 100);
local view = model:view(100, {}, current);
local baseline, last_sequence = {}, 0;
assert(#view.rows == 12 and #model:drain_events() == 0, 'Loading an existing icon list remains a quiet baseline.');
for index = 1, 12 do
    local row = by_effect(view, 10, 39 + index);
    assert(row.first_seen == 100, 'An initial snapshot does not claim an earlier application time.');
    assert(type(row.first_sequence) == 'number' and row.first_sequence > last_sequence,
        'Effects first seen in one snapshot retain their observed order beyond the ninth row.');
    assert(row.start == nil and row.total == nil and row.elapsed == nil,
        'An ordering token never invents a start time or duration.');
    baseline[row.effect], last_sequence = copy(row), row.first_sequence;
end;

-- A reordered snapshot and changed slots must not replace the observed arrival order.
local reordered = {};
for index = #current.self_effects, 1, -1 do
    local status = copy(current.self_effects[index]); status.slot = #reordered;
    reordered[#reordered + 1] = status;
end;
current.self_effects = reordered;
model:reconcile(current, 101);
view = model:view(101, {}, current);
for effect, before in pairs(baseline) do unchanged(by_effect(view, 10, effect), before); end;
assert(#model:drain_events() == 0, 'Slot changes remain distinct from new applications.');

-- Refreshes alter timer metadata, while unknown durations still retain their arrival order.
model:observe({{kind = 'apply', entity_id = 10, effect = 40, source = 10, spell = 57}}, 102, current);
for _, status in ipairs(current.self_effects) do
    if status.effect == 40 then status.deadline, status.raw_timer = 500, 30000; end;
    if status.effect == 41 then status.deadline, status.raw_timer = 600, 36000; end;
end;
model:reconcile(current, 102);
view = model:view(102, {}, current);
local refreshed = by_effect(view, 10, 40);
unchanged(refreshed, baseline[40]); unchanged(by_effect(view, 10, 41), baseline[41]);
assert(refreshed.start == 102 and refreshed.observed_at == 102 and refreshed.instance == 2,
    'Fresh timer metadata remains independent of the original presence order.');
for _, event in ipairs(model:drain_events()) do
    assert(event.kind == 'refresh' and event.first_sequence == baseline[event.effect].first_sequence,
        'Refresh events expose the same immutable presence order as display rows.');
end;

-- Incomplete reads do not confirm removal, so recovering the same icon retains its age.
local complete = copy(current.self_effects);
current.self_known, current.self_effects = false, {};
for _, status in ipairs(complete) do
    if status.effect ~= 41 then current.self_effects[#current.self_effects + 1] = copy(status); end;
end;
model:reconcile(current, 103);
view = model:view(103, {}, current);
unchanged(by_effect(view, 10, 41), baseline[41]);
assert(by_effect(view, 10, 41).present == nil, 'A partial omission remains unconfirmed presence.');
current.self_known, current.self_effects = true, complete;
model:reconcile(current, 104);
unchanged(by_effect(model:view(104, {}, current), 10, 41), baseline[41]);

-- A confirmed absence followed by a new appearance is a new presence.
for index = #current.self_effects, 1, -1 do
    if current.self_effects[index].effect == 42 then table.remove(current.self_effects, index); end;
end;
model:reconcile(current, 105);
assert(not by_effect(model:view(105, {}, current), 10, 42));
current.self_effects[#current.self_effects + 1] = {effect = 42, slot = 11};
model:reconcile(current, 106);
local returned = by_effect(model:view(106, {}, current), 10, 42);
assert(returned.key ~= baseline[42].key and returned.first_seen == 106 and returned.first_sequence > last_sequence,
    'A removed and reapplied effect follows all continuously present effects.');
assert(returned.remaining == nil and returned.status == 'unknown',
    'Unknown-duration effects still receive honest presence ordering.');

-- Action observations follow the same lifecycle for party, alliance and enemy effects.
for _, scope in ipairs({'party', 'alliance', 'enemy'}) do
    local id = scope == 'party' and 20 or scope == 'alliance' and 30 or 100;
    model:observe({{kind = 'apply', entity_id = id, effect = 2, scope = scope, source = 10, duration = 60},
        {kind = 'apply', entity_id = id, effect = 3, scope = scope, source = 10}}, 107, current);
    view = model:view(107, {}, current);
    local first, second = by_effect(view, id, 2), by_effect(view, id, 3);
    assert(first.first_seen == second.first_seen and first.first_sequence < second.first_sequence,
        'Same-tick action observations have an unambiguous numeric arrival order.');
    model:observe({{kind = 'apply', entity_id = id, effect = 2, scope = scope, source = 10, duration = 180}}, 108, current);
    local next_row = by_effect(model:view(108, {}, current), id, 2);
    unchanged(next_row, first);
    assert(next_row.instance > first.instance and next_row.start == 108 and next_row.total == 180);
    model:observe({{kind = 'remove', entity_id = id, effect = 2, scope = scope}}, 110, current);
    assert(not by_effect(model:view(110, {}, current), id, 2));
    model:observe({{kind = 'apply', entity_id = id, effect = 2, scope = scope}}, 110, current);
    local reapplied = by_effect(model:view(110, {}, current), id, 2);
    assert(reapplied.first_seen == 110 and reapplied.first_sequence > second.first_sequence
        and reapplied.key ~= first.key, 'An explicit remove/reapply moves the effect after its surviving neighbor.');
end;

-- Snapshot duplicates keep their individual identities when slots are rearranged.
local duplicate_model = Tracker.new();
local duplicates = snapshot({{effect = 33, slot = 0, deadline = 200, raw_timer = 12000},
    {effect = 33, slot = 1, deadline = 300, raw_timer = 18000}});
duplicate_model:reconcile(duplicates, 100);
local original = duplicate_model:view(100, {}, duplicates).rows;
assert(original[1].first_sequence < original[2].first_sequence and original[1].first_seen == original[2].first_seen);
duplicates.self_effects = {{effect = 33, slot = 0, deadline = 300, raw_timer = 18000},
    {effect = 33, slot = 1, deadline = 200, raw_timer = 12000}};
duplicate_model:reconcile(duplicates, 101);
local moved = duplicate_model:view(101, {}, duplicates).rows;
for index, row in ipairs(moved) do unchanged(row, original[index]); end;
duplicates.self_effects[2].deadline, duplicates.self_effects[2].raw_timer = 400, 24000;
duplicate_model:reconcile(duplicates, 102);
local renewed = duplicate_model:view(102, {}, duplicates).rows;
for index, row in ipairs(renewed) do unchanged(row, original[index]); end;

-- Tick projection and client-data expiry never become a new application.
duplicate_model:project({rows = renewed}, 500);
for index, row in ipairs(renewed) do
    unchanged(row, original[index]);
    assert(row.status == 'server' and row.remaining == 0,
        'An expired server timer stays known at zero without changing the observed presence order.');
end;
renewed[1].first_sequence = -1;
unchanged(duplicate_model:view(103, {}, duplicates).rows[1], original[1]);

-- A new session starts a new baseline without suggesting knowledge of pre-load age.
duplicates.zone = 2;
duplicate_model:reconcile(duplicates, 200);
local fresh = duplicate_model:view(200, {}, duplicates).rows;
for _, row in ipairs(fresh) do
    assert(row.first_seen == 200 and row.first_sequence > original[2].first_sequence
        and row.start == nil and row.elapsed == nil,
        'Session changes assign a new observation order, without inventing earlier application times.');
end;
return 'Immutable first observation order across ties, refreshes, incomplete reads, unknown timers and remove/reapply cycles';
