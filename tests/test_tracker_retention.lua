local tracker = require('core.tracker');
local snapshot = { valid = true, id = 10, zone = 1, name = 'Self', self_known = true, self_effects = {}, party = {}, entities = {} };
local settings = { tracking = { max_entities = 8, stale_seconds = 30 } };

local model = tracker.new();
model:reconcile(snapshot, 0);
for id = 100, 106 do
    model:observe({ { kind = 'apply', entity_id = id, effect = 2, duration = 600 } }, id - 100, snapshot);
end
model:entity(200, 'enemy', 'Old empty target', 20);
model:drain_events();
local view = model:view(100, settings, snapshot);
assert(#view.subjects == 8 and #view.rows == 7, 'Removing an expired empty target must not evict a retained timer.');
assert(model.entities[100] and model.entities[100].entries[1].deadline == 600,
    'The oldest valid long timer survives when the retained subjects fit the cap.');
assert(model.entities[200] == nil, 'An expired empty subject is removed before applying the cap.');
assert(#model:drain_events() == 0, 'Retention cleanup does not invent wear-off events.');

model:observe({ { kind = 'apply', entity_id = 107, effect = 2, duration = 600 } }, 101, snapshot);
view = model:view(101, settings, snapshot);
assert(#view.subjects == 8 and #view.rows == 7, 'Adding a ninth retained subject still enforces the cap.');
assert(model.entities[100] == nil and model.entities[101] and model.entities[107],
    'Only the oldest retained non-party target is evicted when the cap is exceeded.');
assert(model.entities[10], 'The self subject is not evicted by target retention.');

local protected = tracker.new();
protected:reconcile(snapshot, 0);
for slot = 1, 17 do protected:entity(200 + slot, slot < 6 and 'party' or 'alliance', 'Member', 0); end
view = protected:view(1, settings, snapshot);
assert(#view.subjects == 18, 'The configured target cap never removes current party or alliance subjects.');
-- Past the cap, who goes first: a unit with nothing to show, then one with no effect of yours, then one holding an
-- effect of yours or your pet's. A watched unit goes last. Within each, whoever was heard from longest ago.
local function crowd(watch_ids)
    local held = tracker.new();
    held:reconcile(snapshot, 0);
    -- Your Sleep on one mob and your pet's on another, then a mob you watch with someone else's Slow on it.
    held:observe({ { kind = 'apply', entity_id = 0x1000123, effect = 2, duration = 600, source = 10, source_name = 'Self' } }, 1, snapshot);
    held:observe({ { kind = 'apply', entity_id = 0x1000124, effect = 2, duration = 600, source = 77, by_pet = true } }, 1.1, snapshot);
    held:observe({ { kind = 'apply', entity_id = 0x1000125, effect = 13, duration = 600, source = 55 } }, 1.2, snapshot);
    local mine = held.entities[0x1000123].entries[1];
    assert(mine.mine == true and held.entities[0x1000124].entries[1].by_pet == true and not held.entities[0x1000125].entries[1].mine,
        'Fixture: one row of yours, one of your pet and one of someone else.');
    return held, { tracking = { max_entities = 8, stale_seconds = 600 }, watch_ids = watch_ids };
end
local function alive(held, id) return held.entities[id] ~= nil; end

-- 20 other units each take an effect from someone else, all heard from after yours.
local held, crowded = crowd({ 0x1000125 });
for n = 1, 20 do
    held:observe({ { kind = 'apply', entity_id = 5000 + n, effect = 40, duration = 1800, source = 6000 + n } }, 2 + n, snapshot);
    held:view(2 + n, crowded, snapshot);
end
view = held:view(30, crowded, snapshot);
assert(#view.subjects == 8, 'The cap still holds: ' .. #view.subjects);
assert(alive(held, 0x1000123), 'A mob holding your debuff outlasts units with no effect of yours, however long ago it was heard from.');
assert(alive(held, 0x1000124), 'So does one holding an effect of your pet.');
assert(alive(held, 0x1000125), 'So does a unit on your watch list.');
assert(alive(held, 5020) and alive(held, 5017) and not alive(held, 5016), 'The rest keep the newest heard from, as before.');
assert(#held:drain_events() >= 0 and held.entities[0x1000123].entries[1].deadline == 601, 'And the timer it holds is untouched.');

-- A unit with nothing to show goes before one with a timer, though it was heard from later.
held, crowded = crowd();
for n = 1, 3 do held:observe({ { kind = 'apply', entity_id = 5000 + n, effect = 40, duration = 1800, source = 6000 + n } }, 2 + n, snapshot); end
held:entity(7001, 'enemy', 'Looked at', 10);
held:entity(7002, 'enemy', 'Looked at too', 11);
view = held:view(12, crowded, snapshot);
assert(#view.subjects == 8 and not alive(held, 7001) and alive(held, 7002), 'The cap takes the empty unit heard from longest ago first.');
for id = 5001, 5003 do assert(alive(held, id), 'A unit with a timer stays ahead of an empty one.'); end

-- With more of yours than the cap has room for, the oldest of yours goes, and never a watched one.
held, crowded = crowd({ 0x1000125 });
for n = 1, 9 do
    held:observe({ { kind = 'apply', entity_id = 0x1000200 + n, effect = 2, duration = 600, source = 10, source_name = 'Self' } }, 2 + n, snapshot);
end
view = held:view(20, crowded, snapshot);
assert(#view.subjects == 8 and alive(held, 0x1000125), 'A watched unit is the last to go.');
assert(not alive(held, 0x1000123) and not alive(held, 0x1000124) and alive(held, 0x1000209), 'Among yours, the ones heard from longest ago go first.');
-- Every unit watched: the cap still holds, by who was heard from last.
local ids = {};
for n = 1, 12 do ids[n] = 0x1000300 + n; end
held, crowded = crowd(ids);
for n = 1, 12 do held:observe({ { kind = 'apply', entity_id = 0x1000300 + n, effect = 13, duration = 600, source = 55 } }, 2 + n, snapshot); end
view = held:view(20, crowded, snapshot);
assert(#view.subjects == 8 and alive(held, 0x100030C) and not alive(held, 0x1000301), 'A watch list longer than the cap still fits it.');

-- The unit you have targeted stays, as your pet does, though it holds no effect of yours: the Target panel and its
-- overhead block read its rows. In a six-member party with a cap of 8, the oldest mob holding your effect goes instead.
local crab = 0x1000400;
local members = {};
for n = 1, 5 do members[n] = { id = 20 + n, name = 'M' .. n, zone = 1, valid = true, effects = {}, revision = 1 }; end
local targeting = { valid = true, id = 10, zone = 1, name = 'Self', self_known = true, self_effects = {}, entities = {},
    party = members, target = { id = crab, name = 'Crab', kind = 'monster' } };
local capped = { tracking = { max_entities = 8, stale_seconds = 180 } };
held = tracker.new();
-- One refresh: what came in, then the snapshot, then the view.
local function refresh(t, observations)
    if observations then held:observe(observations, t, targeting); end
    held:reconcile(targeting, t);
    return held:view(t, capped, targeting);
end
local function slept(rows)
    for _, row in ipairs(rows) do
        if row.entity_id == crab and row.effect == 2 then return true; end
    end
    return false;
end
refresh(0);
refresh(1, { { kind = 'apply', entity_id = 0x1000401, effect = 134, duration = 60, source = 10 } });
refresh(2, { { kind = 'apply', entity_id = 0x1000402, effect = 4, duration = 120, source = 10 } });
view = refresh(3, { { kind = 'apply', entity_id = crab, effect = 2, duration = 60, source = 23 } });
assert(alive(held, crab) and slept(view.rows), 'A party member\'s Sleep on your target stays in view.');
assert(#view.subjects == 8, 'The cap still holds with your target kept: ' .. #view.subjects);
assert(not alive(held, 0x1000401) and alive(held, 0x1000402), 'The oldest mob holding your effect goes instead.');
view = refresh(3.1);
assert(slept(view.rows), 'The next refresh still shows it.');
view = refresh(10, { { kind = 'apply', entity_id = crab, effect = 13, duration = 120, source = 24 } });
local slowed = false;
for _, row in ipairs(view.rows) do
    if row.entity_id == crab and row.effect == 13 then slowed = true; end
end
assert(slept(view.rows) and slowed, 'A later effect from someone else on your target shows too.');
return 'Expired empty subjects cannot evict long-running status timers';
