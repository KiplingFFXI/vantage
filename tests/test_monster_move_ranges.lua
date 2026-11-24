-- A monster move whose length goes by the mob's TP, or by a roll, counts down a range on whoever it lands on: from its
-- time at 1000 TP, or the roll's low end, to its longest. The game sends neither the TP nor the roll, and a mob uses a
-- move at any TP from 1000 to 3000. Real 0x028s through observer.read and the tracker.
local observer, tracker, alerts, hud = require('core.observer'), require('core.tracker'), require('core.alerts'), require('ui.hud');
local SELF, MOB, PET = 1001, 0x1000123, 0x1000801;
local snapshot = { valid = true, id = SELF, name = 'Tester', zone = 102, job = 9, level = 75, self_known = true, self_revision = 1,
    self_timer_revision = 1, self_effects = {}, party = {}, pet = { id = PET, index = 0x701, name = 'CourierCarrie', kind = 'pet' },
    entities = { [SELF] = { id = SELF, name = 'Tester', kind = 'player' }, [MOB] = { id = MOB, name = 'Crawler', kind = 'monster' },
        [PET] = { id = PET, name = 'CourierCarrie', kind = 'pet' } } };
-- One action: its actor, category and id, and each target as { id, message, param }.
local function action(actor, category, id, rows)
    local targets = {};
    for i, row in ipairs(rows) do targets[i] = { id = row[1], rows = { { message = row[2], param = row[3] } } }; end
    return MOCK.packet(0x028, MOCK.action_bytes(actor, category, id, targets));
end
local settings = { tracking = { max_entities = 64, stale_seconds = 180 } };
local model = tracker.new();
model:reconcile(snapshot, 0);
local function view(at) return model:view(at, settings, snapshot); end
local function find(rows, effect)
    for _, row in ipairs(rows) do if row.entity_id == PET and row.effect == effect then return row; end end
end

-- A crawler's Sticky Thread, move 344, slows your pet for 180 to 540 seconds by the crawler's TP.
model:observe(observer.read(action(MOB, 11, 344, { { PET, 242, 13 } }), 100, snapshot), 100, snapshot);
local slow = find(view(100).rows, 13);
assert(slow and slow.duration_min == 180 and slow.total == 540,
    'Sticky Thread counts 180 to 540 seconds: ' .. tostring(slow and slow.duration_min) .. ' to ' .. tostring(slow and slow.total));
assert(hud.timer_text(slow, 100) == '3m - 9m', 'Its countdown shows the range: ' .. hud.timer_text(slow, 100));
-- A percent alert has no known total to go by, so it stays quiet past 505, when 25% of 540 seconds is left. One in seconds
-- still counts to the longest end, so its 60 seconds left come at 580. The alerts are checked every 10 seconds, as a
-- longer gap starts them over.
local percent = { id = 'slow_percent', enabled = true, event = 'remaining', effect = 13, scope = 'pet', thresholds = { 25 },
    unit = 'percent', cooldown = 0, visual = true, chat = false, sound = '', duration = 4 };
local seconds = { id = 'slow_seconds', enabled = true, event = 'remaining', effect = 13, scope = 'pet', thresholds = { 60 },
    unit = 'seconds', cooldown = 0, visual = true, chat = false, sound = '', duration = 4 };
local watcher, notices = alerts.new(), {};
for now = 500, 590, 10 do
    watcher:update(view(now), {}, { percent, seconds }, now, {});
    for _, notice in ipairs(watcher:drain(now)) do notices[#notices + 1] = notice; end
end
assert(#notices == 1 and notices[1].rule_id == 'slow_seconds' and notices[1].time == 580,
    'Only the seconds alert fires, at 580: ' .. #notices .. ' ' .. tostring(notices[1] and notices[1].rule_id) .. ' '
    .. tostring(notices[1] and notices[1].time));
-- Dream Flower, move 301, rolls its sleep from 15 to 60 seconds.
model:observe(observer.read(action(MOB, 11, 301, { { PET, 242, 2 } }), 600, snapshot), 600, snapshot);
local sleep = find(view(600).rows, 2);
assert(sleep and sleep.duration_min == 15 and sleep.total == 60 and hud.timer_text(sleep, 600) == '15s - 1m',
    'Dream Flower counts 15 to 60 seconds: ' .. tostring(sleep and hud.timer_text(sleep, 600)));
return 'A monster move timed by TP or a roll counts down its range';
