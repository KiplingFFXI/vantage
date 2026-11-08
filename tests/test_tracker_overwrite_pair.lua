-- Two other casters recast the player's held Refresh (Always_Overwrite) within one reply. Phoenix sends each old
-- copy's 0x029 and its replacement's 0x028 back to back (enhancing_spell.lua), so each removal pairs with the first
-- application after it on the same 0x063 count. The held row is refreshed in place twice: no removal, no new gain
-- and one key throughout, with the last caster's name.
local SELF = 1001;
local function status(effect, slot, deadline, raw) return { effect = effect, slot = slot, deadline = deadline, raw_timer = raw }; end
local function snapshot(revision, timers, effects)
    return { valid = true, id = SELF, name = 'Tester', zone = 102, job = 3, self_known = true, self_revision = revision,
        self_timer_revision = timers, self_effects = effects, party = {}, entities = {} };
end
local function cast(source, stamp) return { kind = 'apply', entity_id = SELF, effect = 43, scope = 'self', source = source, spell = 109, timer_revision = stamp, action_category = 4 }; end
local function wear(stamp) return { kind = 'remove', entity_id = SELF, effect = 43, scope = 'self', reason = 'Observed wearoff', timer_revision = stamp }; end
local function row43(view) for _, r in ipairs(view.rows) do if r.effect == 43 and r.present ~= false then return r; end end end
local rules = {
    { id = 'removed', enabled = true, event = 'removed', effect = 43, scope = 'self', cooldown = 0, duration = 30, visual = true },
    { id = 'gain', enabled = true, event = 'gain', effect = 43, scope = 'self', cooldown = 0, duration = 30, visual = true },
};
local function run(steps)
    local tracker, alerts = require('core.tracker').new(), require('core.alerts').new();
    local kinds, notices, view = {}, {}, nil;
    for index, step in ipairs(steps) do
        tracker:observe(step[3] or {}, step[2], step[1]);
        tracker:reconcile(step[1], step[2]);
        view = tracker:view(step[2], {}, step[1]);
        local events = tracker:drain_events();
        if index > (steps.quiet or 0) then
            for _, e in ipairs(events) do kinds[#kinds + 1] = e.kind .. ':' .. tostring(e.source); end;
        end;
        alerts:update(view, events, rules, step[2], {});
        for _, n in ipairs(alerts:drain(step[2])) do if index > (steps.quiet or 0) then notices[#notices + 1] = n.event; end; end;
        steps[index].key = row43(view) and row43(view).key;
    end;
    return view, table.concat(kinds, ','), table.concat(notices, ',');
end;

-- One ticking before the player and one after, in one zone tick: 0x029 0x028(2002) 0x037 0x063 0x029 0x028(2003);
-- the next tick's 0x063 lists 2003's copy.
local steps = {
    { snapshot(1, 0, {}), 0 },
    { snapshot(3, 1, { status(43, 0, 150, 9000) }), 1, { cast(SELF, 0) } },
    { snapshot(3, 1, { status(43, 0, 150, 9000) }), 60 },
    { snapshot(5, 2, { status(43, 0, 220, 13200) }), 70, { wear(1), cast(2002, 1), wear(2), cast(2003, 2) } },
    { snapshot(7, 3, { status(43, 0, 220.4, 13200) }), 70.4 },
    quiet = 3,
};
local view, kinds, notices = run(steps);
assert(kinds == 'refresh:2002,refresh:2003', 'Each recast refreshes the held row: ' .. kinds);
assert(steps[5].key == steps[2].key and row43(view).source == 2003, 'One row throughout, with the last caster.');
assert(notices == '', 'No removal or gain is told: ' .. notices);

-- Both ticking before the player in two zone ticks that share one reply: 0x029 0x028(2002) 0x037 0x063(count 2)
-- 0x029 0x028(2003) 0x037 0x063(count 3). The listing read shows 2003's copy.
steps = { { snapshot(1, 0, {}), 0 }, { snapshot(3, 1, { status(43, 0, 150, 9000) }), 1, { cast(SELF, 0) } } };
for t = 2, 70 do steps[#steps + 1] = { snapshot(3, 1, { status(43, 0, 150, 9000) }), t }; end;
steps.quiet = #steps;
steps[#steps + 1] = { snapshot(7, 3, { status(43, 0, 220.4, 13200) }), 70.4, { wear(1), cast(2002, 1), wear(2), cast(2003, 2) } };
steps[#steps + 1] = { snapshot(7, 3, { status(43, 0, 220.4, 13200) }), 71 };
view, kinds, notices = run(steps);
assert(notices == '' and row43(view).source == 2003, 'Two ticks in one reply refresh it quietly: ' .. kinds .. ' | ' .. notices);

-- A removal pairs with no application before it, nor with one on a later count: each is a removal as it comes,
-- not a recast held for the next listing.
for _, batch in ipairs({ { cast(2002, 2), wear(2) }, { wear(2), cast(2002, 3) } }) do
    steps = {
        { snapshot(1, 0, {}), 0 },
        { snapshot(3, 1, { status(43, 0, 150, 9000) }), 1, { cast(SELF, 0) } },
        { snapshot(5, 2, { status(43, 0, 150, 9000) }), 60, batch },
        quiet = 2,
    };
    view, kinds, notices = run(steps);
    assert(kinds == 'removed:1001', 'The wear-off is a removal: ' .. kinds);
end;
