-- roster.read hands on each slot's row while every field it reads is the same, in a new roster each refresh, as
-- ui/native_party_hud.lua reads the game's party windows again for another roster. A field that differs makes a new row,
-- and the last roster keeps the one it had. The distance core/party_distance.lua marks on a row is marked again each
-- refresh while it is on, so a row handed on has none until then. So a refresh that reads the same makes no table for a
-- member. Measured with the collector stopped and the compiler off, as test_hud_draw_allocation.lua does.
local client = require('core.client');
local roster = require('core.roster');
local mm = AshitaCore:GetMemoryManager();
AshitaCore.GetMemoryManager = function() return mm; end;
local chat = { IsInputOpen = function() return 0; end };
AshitaCore.GetChatManager = function() return chat; end;
local me = GetPlayerEntity();
GetPlayerEntity = function() return me; end;
local stats, party = mm:GetPlayer(), mm:GetParty();
local icons = {};
for slot = 0, 31 do icons[slot] = 255; end
stats.GetBuffs = function() return icons; end;
local units = { GetServerId = function() return 0; end };
mm.GetEntity = function() return units; end;
-- You and count - 1 others, all in your zone, each with a name and jobs.
local members, jobs = {}, {};
local function gather(count)
    for slot = 0, 17 do
        members[slot] = slot < count and { id = 1001 + slot, index = 0x400 + slot, zone = 102 } or nil;
        jobs[slot] = 5;
    end
end
for name, key in pairs({ GetMemberServerId = 'id', GetMemberTargetIndex = 'index', GetMemberZone = 'zone' }) do
    party[name] = function(_, slot) return members[slot] and members[slot][key] or 0; end;
end
party.GetMemberName = function(_, slot) return 'Member' .. slot; end;
party.GetMemberIsActive = function(_, slot) return members[slot] and 1 or 0; end;
party.GetMemberMainJob = function(_, slot) return jobs[slot]; end;
party.GetMemberSubJob = function() return 3; end;
party.GetMemberZone2 = function() return 0; end;
party.GetMemberLastUpdatedTimestamp = function() return 1; end;
AshitaCore.GetResourceManager = function() return { GetString = function() return 'Somewhere'; end }; end;

local now = 1;
local function read()
    now = now + 0.1;
    local snapshot = client.read(now);
    return roster.read(now, snapshot), snapshot;
end

-- KB a roster.read makes once nothing it reads changes, with one snapshot.
local function measure(count)
    jit.off(); jit.flush();
    now = now + 0.1;
    local snapshot = client.read(now);
    for _ = 1, 60 do roster.read(now, snapshot); end
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    for _ = 1, 6 do roster.read(now, snapshot); end
    local before = collectgarbage('count');
    for _ = 1, count do roster.read(now, snapshot); end
    local each = (collectgarbage('count') - before) / count;
    collectgarbage('restart');
    jit.on();
    return each;
end
gather(6);
local party6 = measure(300);
gather(18);
local alliance18 = measure(300);
assert(#read().members == 18, 'Fixture: an alliance of eighteen.');
-- The roster's own lists grow with the members, which counts a little for each.
local each = (alliance18 - party6) / 12;
assert(each < 0.3, ('Each member past a party of six makes %.3f KB a refresh when nothing changes; only the roster\'s lists expected')
    :format(each));
-- What the roster and its list of count members cost alone, made the way roster.read makes them.
local function lists(count)
    jit.off(); jit.flush();
    local row, valid, id, zone, flag = {}, true, 1001, 102, false;
    local function make()
        local out = { valid = valid, id = id, zone = zone, members = {}, typing = flag, in_event = flag, map = flag, hidden = flag };
        for _ = 1, count do out.members[#out.members + 1] = row; end
        return out;
    end
    for _ = 1, 60 do make(); end
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    local before = collectgarbage('count');
    for _ = 1, 300 do make(); end
    local made = (collectgarbage('count') - before) / 300;
    collectgarbage('restart');
    jit.on();
    return made;
end
for _, case in ipairs({ { party6, 6 }, { alliance18, 18 } }) do
    local extra = case[1] - lists(case[2]);
    assert(extra < 0.02, ('A read of %d members makes %.3f KB past the roster and its list; nothing expected'):format(case[2], extra));
end

gather(6);
local first = read();
local second = read();
assert(first.valid and #first.members == 6 and first.members[2].name == 'Member1' and first.members[2].job == 5
    and first.members[2].subjob == 3 and first.members[2].zone_name == 'Somewhere', 'Fixture: a party of six.');
assert(second ~= first, 'Each refresh has a new roster.');
for n = 1, 6 do assert(second.members[n] == first.members[n], 'A row that reads the same is handed on: ' .. n); end
-- Another job makes a new row for that member alone, and the last roster keeps the one it had.
jobs[2] = 4;
local third = read();
assert(third.members[3] ~= second.members[3] and third.members[3].job == 4 and second.members[3].job == 5,
    'Another job makes a new row, and the last roster keeps its own.');
assert(third.members[2] == second.members[2] and third.members[4] == second.members[4], 'The others keep theirs.');
-- A member in another zone gets a new row, out of reach.
members[4].zone = 103;
local fourth = read();
assert(fourth.members[5] ~= third.members[5] and not fourth.members[5].same_zone and not fourth.members[5].available
    and third.members[5].available, 'A member in another zone gets a new row, and the last roster keeps its own.');
members[4].zone = 102;
-- The distance is marked each refresh while it is on. A row handed on has none until it is marked again.
local fifth = read();
local distance = require('core.party_distance');
fifth.members[2].tenths, fifth.members[2].reach, fifth.members[2].steep, fifth.members[2].far = 123, 210, false, false;
local sixth = read();
assert(sixth.members[2] == fifth.members[2], 'Fixture: the row is handed on.');
assert(sixth.members[2].tenths == nil and sixth.members[2].reach == nil and sixth.members[2].steep == nil
    and sixth.members[2].far == nil, 'A row handed on has no distance until it is marked again.');
assert(distance.text(sixth.members[2].tenths) == '', 'So no number shows for it.');
