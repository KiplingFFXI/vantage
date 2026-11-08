-- A Required effect missing rule tells each time the effect goes missing. One found and lost again is told again,
-- also when it was lost during an event or a mute (3 s after it ends), and one the minimum time between repeats
-- held back is told once that time is up, if it is still missing.
local A = require('core.alerts');
local function list(t) local p = {}; for i, v in ipairs(t) do p[i] = string.format('%g', v); end; return '[' .. table.concat(p, ', ') .. ']'; end;
local function same(a, b) if #a ~= #b then return false; end; for i = 1, #a do if a[i] ~= b[i] then return false; end; end; return true; end;
local function times(present, quiet, repeat_seconds, cooldown, last)
    local rule = { id = 'm', enabled = true, event = 'missing', effect = 33, effect_name = 'Haste', scope = 'self', unit = 'seconds',
        cooldown = cooldown, repeat_seconds = repeat_seconds, visual = true, chat = true, duration = 4 };
    local row = { key = '10:33', instance = 1, effect = 33, name = 'Haste', scope = 'self', entity_id = 10, status = 'server',
        remaining = 100, total = 180, present = true };
    local view = { valid = true, rows = {}, subjects = { { id = 10, scope = 'self', known = true, name = 'You' } }, context = { id = 10, zone = 1, job = 1 } };
    local a, result = A.new(), {};
    for t = 0, last do
        view.rows = present(t) and { row } or {};
        a:update(view, {}, { rule }, t, quiet and quiet(t) or {});
        for _ in ipairs(a:drain(t)) do result[#result + 1] = t; end;
    end;
    return result;
end;

-- Haste missing from the start (told at 3 s), cast at 50 s and worn off at 200 s, inside an event or a mute from 190
-- to 209 s.
local function worn_at_200(t) return t >= 50 and t < 200; end;
local function event(t) return t >= 190 and t < 210 and { quiet = true } or nil; end;
local function mute(t) return t >= 190 and t < 210 and { muted = true } or nil; end;
local told = times(worn_at_200, event, 0, 0, 900);
assert(same(told, { 3, 212 }), 'Lost again during an event, it is told 3 s after the event: ' .. list(told));
told = times(worn_at_200, mute, 0, 0, 900);
assert(same(told, { 3, 212 }), 'Lost again during a mute, it is told 3 s after the unmute: ' .. list(told));
told = times(worn_at_200, event, 600, 0, 900);
assert(same(told, { 3, 212, 812 }), 'With a 600 s reminder it is told after the event and reminded 600 s later: ' .. list(told));

-- Cast at 50 s and dispelled at 55 s, seen by an ordinary update.
local function dispelled_at_55(t) return t >= 50 and t < 55; end;
told = times(dispelled_at_55, nil, 0, 10, 200);
assert(same(told, { 3, 55 }), 'Lost again after the minimum time between repeats, it is told at once: ' .. list(told));
told = times(dispelled_at_55, nil, 0, 60, 200);
assert(same(told, { 3, 63 }), 'Lost again within a 60 s minimum time between repeats, it is told once that time is up: ' .. list(told));
local function back_at_60(t) return t >= 50 and t < 55 or t >= 60; end;
told = times(back_at_60, nil, 0, 60, 200);
assert(same(told, { 3 }), 'One back before the minimum time is up is not told: ' .. list(told));
return true;
