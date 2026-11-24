-- A steady refresh of the tracker in a full alliance makes little: reconcile and drain_events make nothing, and view
-- makes only the lists it hands out, not a table for each unit it lists. You have 16 timed effects, 5 party members 10
-- listed effects each, 12 alliance members none, and your target 3 debuffs. Measured as
-- test_tracker_snapshot_allocation.lua does, with the collector stopped and the compiler off.
local Tracker = require('core.tracker');
local SELF, MOB = 1001, 0x1000123;
local own = {};
for slot, effect in ipairs({ 33, 40, 41, 42, 43, 116, 251, 56, 57, 58, 68, 71, 196, 196, 198, 198 }) do
    own[slot] = { effect = effect, slot = slot - 1, raw_timer = 100000 + slot * 600, deadline = 5000 + slot * 10 };
end
local party = {};
for n = 1, 17 do
    local effects = {};
    if n <= 5 then
        for slot, effect in ipairs({ 33, 40, 41, 42, 43, 116, 57, 58, 68, 71 }) do effects[slot] = { effect = effect, slot = slot }; end
    end
    party[n] = { id = 2000 + n, name = 'M' .. n, zone = 100, slot = n, group = math.floor(n / 6) + 1,
        scope = n <= 5 and 'party' or 'alliance', hpp = 100, valid = n <= 5, effects = effects, revision = 5 };
end
local snapshot = { valid = true, id = SELF, name = 'Self', zone = 100, self_known = true, self_revision = 7, self_timer_revision = 9,
    self_effects = own, party = party, entities = { [MOB] = { id = MOB, name = 'Mob', kind = 'monster' } },
    target = { id = MOB, name = 'Mob', kind = 'monster' } };
local t = Tracker.new();
t:reconcile(snapshot, 100);
t:observe({ { kind = 'apply', entity_id = MOB, effect = 5, source = SELF, duration = 600 },
    { kind = 'apply', entity_id = MOB, effect = 134, source = SELF, duration = 600 },
    { kind = 'apply', entity_id = MOB, effect = 13, source = SELF, duration = 600 } }, 100, snapshot);
local settings = { tracking = {} };
local now, view = 100, nil;
-- One refresh as vantage.lua runs it. made adds up what each part made, while measure is on.
local made = { reconcile = 0, view = 0, drain = 0 };
local function refresh(count, measure)
    for _ = 1, count do
        now = now + 0.1;
        t:observe({}, now, snapshot);
        local a = measure and collectgarbage('count');
        t:reconcile(snapshot, now);
        local b = measure and collectgarbage('count');
        view = t:view(now, settings, snapshot);
        local c = measure and collectgarbage('count');
        t:drain_events();
        local d = measure and collectgarbage('count');
        if measure then
            made.reconcile, made.view, made.drain = made.reconcile + b - a, made.view + c - b, made.drain + d - c;
        end
    end
end
refresh(200);
assert(#view.subjects == 19 and #view.rows == 69, 'Fixture: 19 units and 69 rows: ' .. #view.subjects .. ' ' .. #view.rows);
jit.off(); jit.flush();
refresh(60);
collectgarbage('collect'); collectgarbage('collect');
collectgarbage('stop');
refresh(6);
local count = 1000;
refresh(count, true);
collectgarbage('restart');
jit.on();
for name, kb in pairs(made) do made[name] = kb / count; end
assert(made.reconcile < 0.002, ('A steady reconcile makes %.4f KB; nothing expected'):format(made.reconcile));
assert(made.drain < 0.002, ('Draining no events makes %.4f KB; nothing expected'):format(made.drain));
assert(made.view < 1.5, ('A steady view makes %.4f KB; only its lists expected'):format(made.view));

-- Each view hands out the same subject for a unit while it reads the same, in a list of its own. One that changed gets
-- a new subject, and its old one stays as it was.
local function subject_of(list, id) for _, subject in ipairs(list.subjects) do if subject.id == id then return subject; end end end
local first = t:view(now, settings, snapshot);
local second = t:view(now + 0.1, settings, snapshot);
assert(second.subjects ~= first.subjects, 'Each view has its own list of subjects.');
for index, subject in ipairs(second.subjects) do
    assert(first.subjects[index] == subject, 'An unchanged unit\'s subject is handed out again, in order: ' .. subject.id);
end
local moved, kept = subject_of(second, 2003), subject_of(second, 2004);
party[3].slot, party[3].group = 9, 2;
t:reconcile(snapshot, now + 0.2);
local third = t:view(now + 0.2, settings, snapshot);
local now_moved = subject_of(third, 2003);
assert(now_moved ~= moved and now_moved.slot == 9 and now_moved.group == 2 and moved.slot == 3 and moved.group == 1,
    'A unit that moved gets a new subject with its new place, and the old one keeps the old.');
assert(subject_of(third, 2004) == kept, 'The others keep theirs.');
for _, subject in ipairs(third.subjects) do
    local entity = t.entities[subject.id];
    assert(subject.name == entity.name and subject.scope == entity.scope and subject.known == entity.known and subject.zone == entity.zone
        and subject.group == entity.group and subject.slot == entity.slot, 'Each subject reads as its unit does: ' .. subject.id);
end

-- The events drained in one refresh are that refresh's. What the app adds to the list (the recasts' events) and what
-- came before are gone from the next one, and a refresh with nothing new hands back an empty list.
t:queue('gain', { key = 'a', effect = 33, entity_id = SELF }, now);
local events = t:drain_events();
assert(#events == 1 and events[1].key == 'a', 'Fixture: one event drained.');
events[#events + 1] = { kind = 'started', domain = 'recast' };
t:queue('gain', { key = 'b', effect = 40, entity_id = SELF }, now);
events = t:drain_events();
assert(#events == 1 and events[1].key == 'b', 'The next drain has only what came since: ' .. #events);
assert(#t:drain_events() == 0, 'Then nothing.');
t:clear('Test', now);
events = t:drain_events();
assert(#events == 1 and events[1].kind == 'reset', 'A clear\'s reset is drained.');
assert(#t:drain_events() == 0, 'Once.');

-- In a crowd past tracking.max_entities, each refresh that hears of a new unit runs the cap, which lets go of the one
-- heard from longest ago. The cap keeps what it works with from run to run, so a view that lets one go makes no more
-- than one where that unit left by a despawn in the same batch and the cap had nothing to do.
local crowd = Tracker.new();
local alone = { valid = true, id = SELF, name = 'Self', zone = 100, self_known = true, self_revision = 7, self_timer_revision = 9,
    self_effects = {}, party = {}, entities = {} };
local capped = { tracking = { max_entities = 64, stale_seconds = 180 }, watch_ids = {} };
crowd:reconcile(alone, 100);
local at, stranger = 100, 0x2000;
local buffed = { kind = 'apply', entity_id = 0, effect = 40, source = 0, duration = 1800 };
local gone = { kind = 'despawn', entity_id = 0 };
local new_one, swapped = { buffed }, { gone, buffed };
local function units()
    local count, oldest = 0, nil;
    for id, entity in pairs(crowd.entities) do
        count = count + 1;
        if entity.scope == 'other' and (not oldest or id < oldest) then oldest = id; end
    end
    return count, oldest;
end
-- One refresh with a new stranger buffed. With leave, the stranger heard from longest ago despawns in the same batch.
-- Gives the KB the view made and the units it started with.
local function crowded(leave)
    at, stranger = at + 0.1, stranger + 1;
    buffed.entity_id, buffed.source = stranger, stranger;
    if leave then gone.entity_id = select(2, units()); end
    crowd:observe(leave and swapped or new_one, at, alone);
    crowd:reconcile(alone, at);
    local held = units();
    local before = collectgarbage('count');
    crowd:view(at, capped, alone);
    local spent = collectgarbage('count') - before;
    crowd:drain_events();
    return spent, held;
end
for _ = 1, 200 do crowded(false); end
assert(units() == 64, 'Fixture: the cap holds 64 units: ' .. units());
jit.off(); jit.flush();
for _ = 1, 60 do crowded(false); crowded(true); end
collectgarbage('collect'); collectgarbage('collect');
collectgarbage('stop');
local capping, leaving = 0, 0;
for _ = 1, 300 do
    local spent, held = crowded(false);
    assert(held == 65, 'Fixture: a new unit puts the crowd one past the cap.');
    capping = capping + spent;
    spent, held = crowded(true);
    assert(held == 64, 'Fixture: with one leaving, the crowd stays at the cap.');
    leaving = leaving + spent;
end
collectgarbage('restart');
jit.on();
local extra = (capping - leaving) / 300;
assert(extra < 0.05, ('Letting a unit go makes %.3f KB a view past one with nothing to let go; nothing expected'):format(extra));
assert(units() == 64, 'The cap still holds 64 units.');
return 'A steady tracker refresh makes only the view\'s lists';
