-- A refresh that finds the same listings as the last makes nothing as the tracker pairs them with their rows: a party
-- member's twelve effects with no timers, and the player's sixteen with timers, two Ballads and two Minuets among them.
-- Measured as test_hud_draw_allocation.lua does, with the collector stopped and the compiler off. A table made every
-- tenth refresh shows.
local t = require('core.tracker').new();
t.self_id = 1001;
local member, you = t:entity(1002, 'party', 'Bob', 0), t:entity(1001, 'self', 'Tester', 0);
local listing, own = {}, {};
for slot, effect in ipairs({ 33, 40, 41, 42, 43, 116, 251, 56, 57, 58, 68, 71 }) do listing[slot] = { effect = effect, slot = slot }; end
for slot, effect in ipairs({ 33, 40, 41, 42, 43, 116, 251, 56, 57, 58, 68, 71, 196, 196, 198, 198 }) do
    own[slot] = { effect = effect, slot = slot, raw_timer = 100000 + slot * 600, deadline = 5000 + slot * 10 };
end
local now, leak, made = 0, false, nil;
local function refresh(count)
    for i = 1, count do
        now = now + 0.1;
        t:snapshot(member, listing, now, false, 5);
        t:snapshot(you, own, now, true, 7, true, false, 9);
        if leak and i % 10 == 0 then made = {}; end
    end
end
local function measure(count)
    jit.off(); jit.flush();
    refresh(60);
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    refresh(6);
    local before = collectgarbage('count');
    refresh(count);
    local each = (collectgarbage('count') - before) / count;
    collectgarbage('restart');
    jit.on();
    return each;
end
refresh(200);
assert(#member.entries == 12 and #you.entries == 16, 'Fixture: a row for each listed effect.');
t:drain_events();
local each = measure(2000);
assert(each < 0.002, ('A refresh of the same listings makes %.4f KB; nothing expected'):format(each));
assert(#t:drain_events() == 0 and #member.entries == 12 and #you.entries == 16, 'Fixture: the same listings change nothing.');
leak = true;
each = measure(2000);
leak = false;
assert(each >= 0.002 and made, ('A table made every tenth refresh shows as %.4f KB'):format(each));
