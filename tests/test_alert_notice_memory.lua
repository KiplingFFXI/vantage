-- A rule remembers when it last notified each effect for as long as that effect is shown, held or missing: the
-- dedup window's 300 s age-out, a quiet stretch (an event, a mute) and a reset (a zone, a long gap) don't erase
-- it. Repeat reminders over 300 s keep their interval, Repeat 0 gives one notice for a missing effect, and a
-- remaining-time repeat goes on after an event or a zone, counted from when it ended.
local A = require('core.alerts');
local function list(t) local p = {}; for i, v in ipairs(t) do p[i] = string.format('%g', v); end; return '[' .. table.concat(p, ', ') .. ']'; end;
local function same(a, b) if #a ~= #b then return false; end; for i = 1, #a do if a[i] ~= b[i] then return false; end; end; return true; end;
local subjects = { { id = 10, scope = 'self', known = true, name = 'You' } };

-- A missing effect: Haste missing on yourself.
local function missing_times(repeat_seconds, seconds, quiet)
    local rule = { id = 'm', enabled = true, event = 'missing', effect = 33, effect_name = 'Haste', scope = 'self', thresholds = { 10 },
        unit = 'seconds', cooldown = 10, repeat_seconds = repeat_seconds, visual = true, chat = true, duration = 4 };
    local view = { valid = true, rows = {}, subjects = subjects, context = { id = 10, zone = 1, job = 1 } };
    local a, times = A.new(), {};
    for t = 0, seconds do
        a:update(view, {}, { rule }, t, { quiet = quiet and quiet(t) });
        for _ in ipairs(a:drain(t)) do times[#times + 1] = t; end;
    end;
    return times;
end;
local once = missing_times(0, 1200);
assert(same(once, { 3 }), 'Repeat reminder 0 gives one notice for an effect missing 20 minutes: ' .. list(once));
local repeated = missing_times(600, 1800);
assert(same(repeated, { 3, 603, 1203 }), 'A 600 s reminder for a missing effect comes every 600 s: ' .. list(repeated));
-- An event of 5 s at 100 s after the notice: the effect was already told missing, so Repeat 0 says nothing more.
local quieted = missing_times(0, 400, function(t) return t >= 100 and t < 105; end);
assert(same(quieted, { 3 }), 'An event does not bring back a missing notice already given: ' .. list(quieted));
-- One missing only during an event is told 3 s after it ends.
local during = missing_times(0, 60, function(t) return t < 20; end);
assert(same(during, { 22 }), 'A missing effect first seen during an event is told 3 s after it: ' .. list(during));

-- A remaining-time rule on Reraise (60 min) below 50 min with a 600 s reminder.
local function remaining_times(rule, total, seconds, step, events)
    local row = { key = '10:113', instance = 1, effect = 113, name = 'Reraise', scope = 'self', entity_id = 10, status = 'server',
        remaining = total, total = total, present = true };
    local view = { valid = true, rows = { row }, subjects = subjects, context = { id = 10, zone = 1, job = 1 } };
    local a, times = A.new(), {};
    for t = 0, seconds, step do
        row.remaining = total - t;
        if events and events.reset == t then a:reset(); end;
        a:update(view, {}, { rule }, t, { quiet = events and events.quiet and events.quiet(t) });
        for _ in ipairs(a:drain(t)) do times[#times + 1] = t; end;
    end;
    return times;
end;
local reraise = { id = 'r', enabled = true, event = 'remaining', effect = 113, effect_name = 'Reraise', scope = 'self', thresholds = { 3000 },
    unit = 'seconds', cooldown = 0, repeat_seconds = 600, visual = true, chat = true, duration = 4 };
local long = remaining_times(reraise, 3600, 3500, 1);
assert(same(long, { 600, 1200, 1800, 2400, 3000 }), 'A 600 s reminder below a crossed threshold repeats while the buff lasts: ' .. list(long));
-- A threshold fires as it's crossed, whatever Minimum time between repeats says.
local spaced = { id = 'c', enabled = true, event = 'remaining', effect = 113, effect_name = 'Reraise', scope = 'self', thresholds = { 3000, 2000 },
    unit = 'seconds', cooldown = 1800, repeat_seconds = 0, visual = true, chat = true, duration = 4 };
local crossed = remaining_times(spaced, 3600, 3500, 1);
assert(same(crossed, { 600, 1600 }), 'A 1800 s minimum holds back no threshold crossed 1000 s after the first: ' .. list(crossed));

-- Haste below 60 s with a 30 s reminder, on a 3-minute Haste.
local haste = { id = 'h', enabled = true, event = 'remaining', effect = 113, effect_name = 'Haste', scope = 'self', thresholds = { 60 },
    unit = 'seconds', cooldown = 0, repeat_seconds = 30, visual = true, chat = true, duration = 4 };
local plain = remaining_times(haste, 180, 175, 1);
assert(same(plain, { 120, 150 }), 'Fixture: the crossing at 120 s and a reminder at 150 s: ' .. list(plain));
-- A 5 s event from 130 s: the reminder counts from the end of the event, as an unmute does.
local evented = remaining_times(haste, 180, 175, 1, { quiet = function(t) return t >= 130 and t < 135; end });
assert(same(evented, { 120, 165 }), 'A remaining-time reminder goes on after a 5 s event, from its end: ' .. list(evented));
-- A zone change at 130 s resets the alerts; the crossed threshold's reminder counts from the reset.
local zoned = remaining_times(haste, 180, 175, 1, { reset = 130 });
assert(same(zoned, { 120, 160 }), 'A remaining-time reminder goes on after a zone change: ' .. list(zoned));
-- A gap over 10 s resets the alerts the same way.
local function gap_times()
    local row = { key = '10:33', instance = 1, effect = 113, name = 'Haste', scope = 'self', entity_id = 10, status = 'server',
        remaining = 180, total = 180, present = true };
    local view = { valid = true, rows = { row }, subjects = subjects, context = { id = 10, zone = 1, job = 1 } };
    local a, times = A.new(), {};
    for t = 0, 175 do
        if t <= 125 or t >= 140 then
            row.remaining = 180 - t;
            a:update(view, {}, { haste }, t, {});
            for _ in ipairs(a:drain(t)) do times[#times + 1] = t; end;
        end;
    end;
    return times;
end;
local gapped = gap_times();
assert(same(gapped, { 120, 170 }), 'A remaining-time reminder goes on after a gap: ' .. list(gapped));
return true;
