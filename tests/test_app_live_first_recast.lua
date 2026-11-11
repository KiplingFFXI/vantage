-- Through vantage.lua as the game drives it: the first use of a job ability since you logged in or zoned. Phoenix lists
-- only the abilities on cooldown (0x119), so the timer comes into a slot that read nothing before. Your own use of it
-- (0x028) says it started: it knows its full length, and an alert on recasts starting says so. Provoke finishes as
-- category 6 and Jump as category 3, and the use can come before the list or just after it. A zone's list that comes
-- after the first read starts nothing. A use paralysis stops still starts its cooldown, and your request for it (0x01A)
-- says which ability it was.
local L = require('live_fixture');
-- The client's ability recasts by slot: a timer id and when it ends, read in 1/60 s.
local slots = {};
local recast = {
    GetSpellTimer = function() return 0; end,
    GetAbilityTimerId = function(_, slot) return slots[slot] and slots[slot].id or 0; end,
    GetAbilityTimer = function(_, slot)
        local entry = slots[slot];
        return entry and math.max(0, math.ceil((entry.ends - MOCK.now) * 60)) or 0;
    end,
};
AshitaCore:GetMemoryManager().GetRecast = function() return recast; end;
-- Provoke is ability 35 on timer 5 and Jump 66 on timer 158. An ability's resource id is its own plus 512.
local abilities = { [547] = { Name = { [1] = 'Provoke' }, RecastTimerId = 5, Id = 547, Type = 1 },
    [578] = { Name = { [1] = 'Jump' }, RecastTimerId = 158, Id = 578, Type = 1 } };
local resources = {
    GetAbilityById = function(_, id) return abilities[id]; end,
    GetAbilityByTimerId = function() return nil; end,
    GetSpellById = function() return nil; end,
    GetItemById = function() return nil; end,
    GetString = function() return nil; end,
};
AshitaCore.GetResourceManager = function() return resources; end;
MOCK.player.main_job, MOCK.player.main_level = 1, 75;

local app = L.start();
-- An alert in chat for each of your recasts that starts.
local rule = require('ui.defaults').rule('started');
rule.domain, rule.event, rule.effect, rule.chat, rule.cooldown = 'recast', 'started', 0, true, 0;
app.state.settings.alerts.rules = { rule };
L.frame(); L.frame();
local CRAB = 0x1000123;
local function row(timer)
    for _, value in ipairs(app.state.recasts.rows or {}) do
        if value.kind == 'ability' and value.recast_id == timer then return value; end
    end
end
local function said(from, text)
    local count = 0;
    for i = from + 1, #MOCK.printed do if MOCK.printed[i]:find(text, 1, true) then count = count + 1; end end
    return count;
end

-- Provoke: its timer comes into slot 1, which read nothing, with your use in the same frame.
local before = #MOCK.printed;
slots[1] = { id = 5, ends = MOCK.now + 30 };
L.action(6, 35, 1001, { { id = CRAB, rows = { { message = 119 } } } });
L.frame();
local provoke = row(5);
assert(provoke and provoke.total and math.abs(provoke.total - 30) < 0.5 and provoke.start,
    'The first Provoke since you logged in knows its full length: ' .. tostring(provoke and provoke.total));
assert(said(before, 'Provoke is on cooldown.') == 1, 'Its start is said once.');

-- Jump: its timer is read first, and your use (category 3, as a weapon skill finishes) comes a frame later.
before = #MOCK.printed;
slots[2] = { id = 158, ends = MOCK.now + 60 };
L.frame();
assert(said(before, 'Jump is on cooldown.') == 0 and row(158) and row(158).total == nil, 'A timer read with no use yet waits.');
L.action(3, 66, 1001, { { id = CRAB, rows = { { message = 110, param = 120 } } } });
L.frame();
local jump = row(158);
assert(jump and jump.total and jump.total > 59 and jump.total <= 60 and jump.start, 'The use just after starts it: ' .. tostring(jump and jump.total));
assert(said(before, 'Jump is on cooldown.') == 1, 'Jump\'s start is said once.');

-- A zone change, with the client's list empty until the zone's list comes after the first read: Jump's timer comes
-- back with no use, and starts nothing.
local function arrive(zone)
    L.W.party_zone, MOCK.player.zone = zone, zone;
    L.zone_in(zone);
    L.frame();
    L.self_timers();
    L.frame();
    assert(app.state.snapshot.valid and app.state.snapshot.zone == zone, 'Fixture: the 0x063 ends zoning.');
end
local listed = slots;
slots = {};
arrive(103);
L.frame();
before = #MOCK.printed;
slots = { [2] = listed[2] };
for _ = 1, 25 do L.frame(); end
assert(row(158) and said(before, 'is on cooldown.') == 0, 'The zone\'s list that came late starts nothing.');

-- Provoke is ready by now. Its first use since the zone starts it.
MOCK.now = MOCK.now + 30;
L.frame();
before = #MOCK.printed;
slots[1] = { id = 5, ends = MOCK.now + 30 };
L.action(6, 35, 1001, { { id = CRAB, rows = { { message = 119 } } } });
L.frame();
provoke = row(5);
assert(provoke and provoke.total and math.abs(provoke.total - 30) < 0.5, 'The first Provoke since the zone knows its full length.');
assert(said(before, 'Provoke is on cooldown.') == 1, 'Its start is said.');

-- Someone else's Provoke starts nothing of yours.
L.frame(31);
L.frame();
before = #MOCK.printed;
slots = { [2] = slots[2] };
L.frame();
L.action(6, 35, 1002, { { id = CRAB, rows = { { message = 119 } } } });
slots[1] = { id = 5, ends = MOCK.now + 30 };
L.frame();
assert(said(before, 'Provoke is on cooldown.') == 0, 'A party member\'s use is not yours.');

-- Paralysis stops your Provoke. Phoenix still lists its cooldown (0x119), then sends the paralysis as category 4 with no
-- ability id and message 84. Your request for Provoke (0x01A, action 9) says which ability it was.
L.frame(31);
L.frame();
before = #MOCK.printed;
slots = { [2] = slots[2] };
L.frame();
L.request(9, 35, CRAB);
slots[1] = { id = 5, ends = MOCK.now + 30 };
L.action(4, 0, 1001, { { id = CRAB, rows = { { message = 84 } } } });
L.frame();
provoke = row(5);
assert(provoke and provoke.total and math.abs(provoke.total - 30) < 0.5,
    'A paralyzed first Provoke knows its full length: ' .. tostring(provoke and provoke.total));
assert(said(before, 'Provoke is on cooldown.') == 1, 'Its start is said.');

-- A paralyzed ranged attack sends the same action, and its request (action 16) names no ability: a timer that comes
-- with it, as a zone's late list can, starts nothing.
L.frame(31);
L.frame();
before = #MOCK.printed;
slots = { [2] = slots[2] };
L.frame();
L.request(16, 0, CRAB);
slots[1] = { id = 5, ends = MOCK.now + 20 };
L.action(4, 0, 1001, { { id = 1001, rows = { { message = 84 } } } });
for _ = 1, 25 do L.frame(); end
assert(row(5) and row(5).total == nil and said(before, 'is on cooldown.') == 0, 'A paralyzed ranged attack starts no cooldown.');
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return true;
