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
return 'Expired empty subjects cannot evict long-running status timers';
