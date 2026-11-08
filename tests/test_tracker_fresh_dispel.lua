-- 2002's Protect lands and its 0x037 comes alone (the datagram ends before its 0x063). A mob dispels it before its
-- timer is read. Whether the next reply's listing still shows it or not, the removal is what the player is told:
-- a copy whose removal came before its first timer was never gained.
local SELF = 1001;
local function status(effect, slot, deadline, raw) return { effect = effect, slot = slot, deadline = deadline, raw_timer = raw }; end
local function snapshot(revision, timers, effects, pending)
    return { valid = true, id = SELF, name = 'Tester', zone = 102, job = 3, self_known = true, self_revision = revision,
        self_timer_revision = timers, self_timers_pending = pending, self_effects = effects, party = {}, entities = {} };
end
local rules = {
    { id = 'removed', enabled = true, event = 'removed', effect = 0, scope = 'self', cooldown = 0, duration = 30, visual = true },
    { id = 'gain', enabled = true, event = 'gain', effect = 0, scope = 'self', cooldown = 0, duration = 30, visual = true },
};
local function run(steps)
    local tracker, alerts = require('core.tracker').new(), require('core.alerts').new();
    local kinds, notices = {}, {};
    for _, step in ipairs(steps) do
        tracker:observe(step[3] or {}, step[2], step[1]);
        tracker:reconcile(step[1], step[2]);
        local view = tracker:view(step[2], {}, step[1]);
        local events = tracker:drain_events();
        for _, e in ipairs(events) do if e.effect == 40 then kinds[#kinds + 1] = e.kind; end; end;
        alerts:update(view, events, rules, step[2], {});
        for _, n in ipairs(alerts:drain(step[2])) do notices[#notices + 1] = n.event; end;
    end;
    return table.concat(kinds, ','), table.concat(notices, ',');
end;
local cast = { kind = 'apply', entity_id = SELF, effect = 40, scope = 'self', source = 2002, spell = 45,
    timer_revision = 1, action_category = 4 };
local dispel = { kind = 'remove', entity_id = SELF, effect = 40, scope = 'self', reason = 'Observed removal', timer_revision = 2 };

-- The next reply ends after the dispel, so the listing read still shows Protect with its timer; the next tick's
-- listing drops it.
local kinds, notices = run({
    { snapshot(1, 1, {}), 0 },
    { snapshot(2, 1, { status(40, 0, nil, nil) }, true), 6.47, { cast } },
    { snapshot(3, 2, { status(40, 0, 1806.47, 108000) }), 6.87, { dispel } },
    { snapshot(5, 3, {}), 7.27 },
    { snapshot(5, 3, {}), 8.0 },
});
assert(kinds == 'removed', 'The dispel is a removal, with no gain before it: ' .. kinds);
assert(notices == 'removed', 'The player is told it was removed: ' .. notices);

-- The next reply holds the late 0x063, the dispel and the next tick's listing without Protect.
kinds, notices = run({
    { snapshot(1, 1, {}), 0 },
    { snapshot(2, 1, { status(40, 0, nil, nil) }, true), 6.47, { cast } },
    { snapshot(5, 3, {}), 6.87, { dispel } },
    { snapshot(5, 3, {}), 7.5 },
});
assert(kinds == 'removed' and notices == 'removed', 'Read in one listing, it is a removal too: ' .. kinds .. ' | ' .. notices);

-- A copy that stays gets its gain at its first timer as before.
kinds, notices = run({
    { snapshot(1, 1, {}), 0 },
    { snapshot(2, 1, { status(40, 0, nil, nil) }, true), 6.47, { cast } },
    { snapshot(3, 2, { status(40, 0, 1806.47, 108000) }), 6.87 },
    { snapshot(5, 3, { status(40, 0, 1806.87, 108000) }), 7.27 },
});
assert(kinds == 'gain' and notices == 'gain', 'An undispelled copy is gained at its first timer: ' .. kinds .. ' | ' .. notices);
