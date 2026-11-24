-- client.read keeps what hasn't changed since the last read, where no reader can tell. Each of your effects keeps its row
-- while its effect, raw timer and deadline are the same, and a party or alliance member with no listing has one shared
-- empty list, so a refresh that finds your effects as they were makes no table for them. A kept row never changes: a
-- reader that kept the last snapshot still reads what that read gave. Measured as test_hud_draw_allocation.lua does,
-- with the collector stopped and the compiler off: a read with sixteen effects makes about what one with none does, past
-- the list that holds them.
local raw_time = 1000;
package.preload['core.clock'] = function()
    return { available = function() return true; end, get_game_time_raw = function() return raw_time; end };
end;
local client = require('core.client');
local mm = AshitaCore:GetMemoryManager();
AshitaCore.GetMemoryManager = function() return mm; end;
local me = GetPlayerEntity();
GetPlayerEntity = function() return me; end;
local stats, party = mm:GetPlayer(), mm:GetParty();
local units = { GetServerId = function() return 0; end };
mm.GetEntity = function() return units; end;
local icons, timers = {}, {};
stats.GetStatusIcons = function() return icons; end;
stats.GetStatusTimers = function() return timers; end;
stats.GetBuffs = function() return icons; end;
-- count effects on you, each slot's raw timer ten minutes and a minute a slot on, at 60 to a second.
local function own(count)
    for slot = 0, 31 do
        icons[slot] = slot < count and (slot + 40) or 255;
        timers[slot] = slot < count and (raw_time + 600 + slot * 60) * 60 or 0;
    end
end
-- A party member and an alliance member, neither with a listing yet.
local members = { [0] = { id = 1001, index = 0x400, zone = 102 }, [1] = { id = 1002, index = 0x401, zone = 102 },
    [6] = { id = 1007, index = 0x406, zone = 102 } };
for name, key in pairs({ GetMemberServerId = 'id', GetMemberTargetIndex = 'index', GetMemberZone = 'zone' }) do
    party[name] = function(_, slot) return members[slot] and members[slot][key] or 0; end;
end
party.GetMemberName = function(_, slot) return 'Member ' .. slot; end;
party.GetMemberIsActive = function(_, slot) return members[slot] and 1 or 0; end;

own(16);
local first = client.read(1);
assert(first.valid and first.self_known and #first.self_effects == 16 and first.self_effects[3].deadline == 721,
    'Fixture: sixteen effects with timers.');
local second = client.read(1.1);
for n = 1, 16 do assert(second.self_effects[n] == first.self_effects[n], 'An effect as it was keeps its row: ' .. n); end
assert(second.self_effects ~= first.self_effects, 'Each snapshot has its own list.');
assert(#second.party == 2 and not second.party[1].valid and not second.party[2].valid and #second.party[1].effects == 0
    and second.party[1].effects == first.party[1].effects and second.party[2].effects == second.party[1].effects,
    'Members with no listing share one empty list.');
-- A renewed timer makes a new row for that slot. The last snapshot's row is as it was.
local kept = second.self_effects[3];
timers[2] = timers[2] + 1800;
local third = client.read(1.2);
assert(third.self_effects[3] ~= kept and third.self_effects[3].raw_timer == timers[2] and third.self_effects[3].deadline == 751.2,
    'A renewed effect gets a new row: ' .. tostring(third.self_effects[3].deadline));
assert(kept.raw_timer == timers[2] - 1800 and kept.deadline == 721 and second.self_effects[3] == kept,
    'The last snapshot keeps the row it had.');
assert(third.self_effects[4] == second.self_effects[4], 'The others keep theirs.');
-- Another effect in a slot, with the same timer, makes a new row too.
icons[5] = 99;
local fourth = client.read(1.3);
assert(fourth.self_effects[6] ~= third.self_effects[6] and fourth.self_effects[6].effect == 99
    and third.self_effects[6].effect == 45 and fourth.self_effects[6].deadline == third.self_effects[6].deadline,
    'Another effect in a slot gets a new row, with the deadline its timer had.');
icons[5] = 45;

local now = 2;
local function reads(count)
    for _ = 1, count do
        now = now + 0.1;
        client.read(now);
    end
end
local alloc = require('alloc_fixture');
own(16);
local sixteen = alloc.measure(reads, 300);
own(0);
local none = alloc.measure(reads, 300);
assert(sixteen - none < 1, ('Sixteen effects as they were make %.2f KB a read more than none; about the list alone expected')
    :format(sixteen - none));
