-- A copy first listed by its 0x037 alone (the datagram ended before its 0x063) takes the application waiting then.
-- When its first timer comes, a later cast that 0x063 shows, of a single effect or of a song of that tier, replaced
-- that copy in place (OverwriteStatusEffect, ApplyBardEffect), so the row names that cast, as take_pending does for
-- a listed copy. A later cast that lands on another listed copy is that copy's; a job ability counts only if it
-- started the copy's timer; one that keeps the copy's timer replaces nothing.
local SELF = 1001;
local function status(effect, slot, deadline, raw) return { effect = effect, slot = slot, deadline = deadline, raw_timer = raw }; end
local function snapshot(revision, timers, effects, pending)
    return { valid = true, id = SELF, name = 'Tester', zone = 102, job = 3, self_known = true, self_revision = revision,
        self_timer_revision = timers, self_timers_pending = pending, self_effects = effects, party = {}, entities = {} };
end
local function new()
    local tracker = require('core.tracker').new();
    local function frame(snap, now, observations)
        tracker:observe(observations or {}, now, snap);
        tracker:reconcile(snap, now);
        return tracker:view(now, {}, snap), tracker:drain_events();
    end;
    return tracker, frame;
end;
local function cast(effect, spell, source, stamp, fields)
    local value = { kind = 'apply', entity_id = SELF, effect = effect, scope = 'self', source = source, spell = spell, timer_revision = stamp, action_category = 4 };
    for key, field in pairs(fields or {}) do value[key] = field; end;
    return value;
end;
local function rows(view, effect)
    local out = {};
    for _, r in ipairs(view.rows) do if r.effect == effect and r.present ~= false then out[#out + 1] = r; end; end;
    table.sort(out, function(a, b) return (a.slot or 0) < (b.slot or 0); end);
    return out;
end;

-- Haste: the player's copy, listed alone, is replaced by 2004's before its first timer comes. Phoenix keeps
-- 2004's, so the row reads 2004, and either order of casters gives the later one.
for _, order in ipairs({ { SELF, 2004 }, { 2003, 2004 }, { 2003, SELF } }) do
    local _, frame = new();
    frame(snapshot(1, 1, {}), 0);
    frame(snapshot(2, 1, { status(33, 0, nil, nil) }, true), 8.07, { cast(33, 57, order[1], 1) });
    local view, events = frame(snapshot(5, 3, { status(33, 0, 188.4, 11304) }), 8.47, { cast(33, 57, order[2], 2) });
    local row = rows(view, 33)[1];
    assert(row and row.source == order[2] and row.mine == (order[2] == SELF),
        'The copy is the later caster\'s: ' .. order[1] .. ' then ' .. order[2] .. ' reads ' .. tostring(row and row.source));
    local gains = 0;
    for _, event in ipairs(events) do if event.kind == 'gain' then gains = gains + 1; end; end;
    assert(gains == 1 and row.start == 8.47, 'One gain, started at the cast it reads.');
end;

-- A song of the same tier replaces the copy; one of another tier lands on its own copy.
do
    local _, frame = new();
    frame(snapshot(1, 1, {}), 0);
    frame(snapshot(2, 1, { status(198, 0, nil, nil) }, true), 8.07, { cast(198, 397, 2003, 1, { tier = 4 }) });
    local view = frame(snapshot(5, 3, { status(198, 0, 152.4, 9144) }), 8.47, { cast(198, 397, 2004, 2, { tier = 4 }) });
    assert(rows(view, 198)[1].source == 2004, 'Minuet IV over Minuet IV in one reply reads the later bard.');
    local _, other = new();
    other(snapshot(1, 1, {}), 0);
    other(snapshot(2, 1, { status(198, 0, nil, nil) }, true), 8.07, { cast(198, 397, 2003, 1, { tier = 4 }) });
    view = other(snapshot(5, 3, { status(198, 0, 152.4, 9144) }), 8.47, { cast(198, 396, 2004, 2, { tier = 3 }) });
    assert(rows(view, 198)[1].source == 2003, 'Minuet III does not take the Minuet IV copy.');
end;

-- A job ability that didn't start the copy's timer replaces nothing.
do
    local _, ability = new();
    ability(snapshot(1, 1, {}), 0);
    ability(snapshot(2, 1, { status(33, 0, nil, nil) }, true), 8.07, { cast(33, 57, 2003, 1) });
    local view = ability(snapshot(5, 3, { status(33, 0, 188.4, 11304) }), 10.6, { cast(33, 57, 2004, 2, { action_category = 6 }) });
    assert(rows(view, 33)[1].source == 2003, 'A job ability that did not start the timer leaves the copy its caster.');
end;

-- Protect held from 2002, as the timers simulator plays it (fuzz seed 41 with split sends): 2002 recasts it, 2003's
-- cast lands while a second copy shows by its 0x037 alone, and the player's own cast comes with the timers. The
-- player's cast replaced 2003's copy (Phoenix keeps the player's), which is listed once more at the other slot. The
-- copy shown alone keeps 2003's cast, and the copy left when it goes reads the player's.
do
    local _, frame = new();
    frame(snapshot(50, 16, {}), 33.0);
    frame(snapshot(51, 17, { status(40, 1, 73.07, 3850331420) }), 33.5, { cast(40, 43, 2002, 16) });
    frame(snapshot(53, 18, { status(40, 1, 91.07, 3850332500) }), 34.067, { cast(40, 43, 2002, 17) });
    frame(snapshot(53, 18, { status(40, 1, 91.07, 3850332500) }), 34.467, { cast(40, 43, 2003, 18) });
    local view = frame(snapshot(54, 18, { status(40, 1, nil, nil), status(40, 2, nil, nil) }, true), 34.817);
    local listed = rows(view, 40);
    assert(#listed == 2 and listed[2].fresh and listed[2].source == 2003, "Fixture: the second copy shows with 2003's cast.");
    view = frame(snapshot(56, 19, { status(40, 1, 82.87, 3850332020), status(40, 2, 91.87, 3850332560) }), 34.867,
        { cast(40, 43, SELF, 18) });
    listed = rows(view, 40);
    assert(listed[1].source == 2003 and listed[1].raw_timer == 3850332020, "The copy shown alone keeps 2003's cast: "
        .. tostring(listed[1].source));
    assert(listed[2].source == SELF, "The copy the player's cast landed on reads it: " .. tostring(listed[2].source));
    view = frame(snapshot(58, 20, { status(40, 1, 91.87, 3850332500) }), 35.267);
    listed = rows(view, 40);
    assert(#listed == 1 and listed[1].source == SELF, "The copy left reads the player's cast: " .. tostring(listed[1] and listed[1].source));
end;
