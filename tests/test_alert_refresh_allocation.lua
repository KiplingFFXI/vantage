-- The alerts make nothing at a refresh or a frame while nothing fires: a party's 42 rows on 7 units, with no rules (the
-- default) and with three rules that don't fire, and the notices and the queue looked at each frame with nothing up or
-- one notice up.
-- Measured with the collector stopped after a warmup, as test_party_strip_allocation.lua does.
local A = require('core.alerts');
local defaults = require('ui.defaults');
local rows, subjects = {}, {};
for unit = 1, 7 do
    subjects[unit] = { id = 100 + unit, scope = unit == 1 and 'self' or 'party', known = true, name = 'U' .. unit };
    for effect = 1, 6 do
        rows[#rows + 1] = { key = (100 + unit) .. ':' .. (40 + effect), instance = 1, effect = 40 + effect, name = 'E' .. effect,
            scope = unit == 1 and 'self' or 'party', entity_id = 100 + unit, status = 'server', remaining = 500, total = 600,
            present = true };
    end;
end;
local view = { valid = true, rows = rows, subjects = subjects, context = { id = 101, zone = 1, job = 1 } };
local three = {};
for index, spec in ipairs({ { effect = 33, event = 'remaining', scope = 'self' }, { effect = 2, event = 'remaining', scope = 'all' },
    { effect = 6, event = 'gain', scope = 'self' } }) do
    local rule = defaults.rule('r' .. index);
    for key, value in pairs(spec) do rule[key] = value; end;
    three[index] = rule;
end;
local names, none, options = { 'Haste', 'Sleep', 'Silence' }, {}, { enabled = true };
local events = {};

local function kilobytes(count, step)
    jit.off(); jit.flush();
    for _ = 1, 50 do step(); end;
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    for _ = 1, 6 do step(); end;
    local before = collectgarbage('count');
    for _ = 1, count do step(); end;
    local each = (collectgarbage('count') - before) / count;
    collectgarbage('restart');
    jit.on();
    return each;
end;

local a, now = A.new(), 0;
local function refresh(rules)
    return function()
        now = now + 0.1;
        options.enrich_context = rules == three and names or nil;
        a:update(view, events, rules, now, options);
    end;
end;
local each = kilobytes(100, refresh(none));
assert(each < 0.002, ('A refresh with no alert rules makes %.4f KB; nothing expected'):format(each));
each = kilobytes(100, refresh(three));
assert(each < 0.002, ('A refresh with three alert rules and nothing firing makes %.4f KB; nothing expected'):format(each));
local frame = 0;
each = kilobytes(600, function()
    frame = frame + 1;
    local t = now + frame / 6000;
    a:view(t); a:drain(t, 70);
end);
assert(each < 0.002, ('Looking at the notices and the queue with nothing up makes %.4f KB a frame; nothing expected'):format(each));
-- Nor with a notice up, once it has gone out.
a:announce('up', 'One notice up.', now, 30);
a:drain(now, 70);
frame = 0;
each = kilobytes(600, function()
    frame = frame + 1;
    local t = now + frame / 6000;
    a:view(t); a:drain(t, 70);
end);
assert(each < 0.002, ('Looking at the notices and the queue with one notice up makes %.4f KB a frame; nothing expected'):format(each));
local up = a:view(now + 1);
assert(#up == 1 and up[1].message == 'One notice up.', 'The notice is up: ' .. #up);
assert(#a:view(now + 31) == 0 and #up == 0, 'Once its time is up it is gone, from the list the last look had too.');

-- A rule's notice still shows and goes out once, and goes as soon as no rule is left, the pet display's own staying.
local haste = defaults.rule('h');
haste.effect, haste.thresholds, haste.cooldown = 41, { 400 }, 0;
local b, row = A.new(), rows[1];
b:update(view, {}, { haste }, 1, {});
row.remaining = 399;
b:update(view, {}, { haste }, 1.1, {});
row.remaining = 500;
local shown, sent = b:view(1.1), b:drain(1.1, 70);
assert(#shown == 1 and shown[1].event == 'remaining' and #sent == 1 and sent[1].message == shown[1].message,
    'A crossed threshold shows its notice and sends it once: ' .. #shown .. ' ' .. #sent);
assert(#b:drain(1.15, 70) == 0, 'A sent notice is not sent again.');
b:announce('pet', 'Your pet is low.', 1.2, 5);
b:update(view, {}, none, 1.3, {});
shown = b:view(1.3);
assert(#shown == 1 and shown[1].own and #b.notices == 1, 'With no rule left only the pet display\'s notice stays: ' .. #shown);

-- Nor while alerts are off or quiet (an event, KO, a zone), nor for a rule that's off, nor for a missing rule while
-- what it looks for is on everyone, or once it has told that it's missing.
local quiet_options, off_options = { enabled = true, quiet = true }, { enabled = false };
local c = A.new();
local function update(rules, given) return function() now = now + 0.1; c:update(view, events, rules, now, given); end; end;
each = kilobytes(100, update(three, off_options));
assert(each < 0.002, ('A refresh with alerts off makes %.4f KB; nothing expected'):format(each));
each = kilobytes(100, update(three, quiet_options));
assert(each < 0.002, ('A quiet refresh makes %.4f KB; nothing expected'):format(each));
local off = defaults.rule('off');
off.effect, off.event, off.enabled = 41, 'missing', false;
each = kilobytes(100, update({ off }, options));
assert(each < 0.002, ('A refresh with a rule that is off makes %.4f KB; nothing expected'):format(each));
local found = defaults.rule('found');
found.effect, found.event, found.scope = 41, 'missing', 'all';
each = kilobytes(100, update({ found }, options));
assert(each < 0.002, ('A missing rule whose effect is on everyone makes %.4f KB a refresh; nothing expected'):format(each));
local gone = defaults.rule('gone');
gone.effect, gone.event, gone.scope, gone.repeat_seconds = 33, 'missing', 'all', 0;
each = kilobytes(100, update({ gone }, options));
c:drain(now, 70);
assert(each < 0.002, ('A missing rule that has told it is missing makes %.4f KB a refresh; nothing expected'):format(each));

-- Each still does what it did: a missing effect is told once for each unit, and found again it isn't.
local d, t = A.new(), 10;
local lost = defaults.rule('lost');
lost.effect, lost.event, lost.scope, lost.repeat_seconds, lost.cooldown = 33, 'missing', 'all', 0, 0;
for _ = 1, 40 do t = t + 0.1; d:update(view, {}, { lost }, t, options); end;
local told = d:drain(t, 70);
assert(#told == 7, 'A missing Haste is told once for each of the 7 units: ' .. #told);
for _ = 1, 40 do t = t + 0.1; d:update(view, {}, { lost }, t, options); end;
assert(#d:drain(t, 70) == 0, 'It is told only once while it stays missing.');
rows[1].effect = 33;
for _ = 1, 40 do t = t + 0.1; d:update(view, {}, { lost }, t, options); end;
rows[1].effect = 41;
local missing_state = d.states[lost.id];
assert(missing_state and missing_state.missing['missing:101:33'] == false and missing_state.missing['missing:102:33'] == true,
    'Haste found on the first unit counts as found there, and the others still miss it.');
-- Quiet and off, the notices go.
d:announce('x', 'Shown', t, 5);
d:update(view, {}, { lost }, t + 0.1, quiet_options);
assert(#d:view(t + 0.1) == 0 and #d.queue == 0, 'A quiet refresh ends the notices and the queue.');
d:announce('x', 'Shown', t + 0.2, 5);
d:update(view, {}, { lost }, t + 0.3, off_options);
assert(#d:view(t + 0.3) == 0 and #d.queue == 0, 'Alerts off end the notices and the queue.');
