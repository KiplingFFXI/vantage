-- client.read hands on each party and alliance member's row, each member's unit row and your own unit row while every
-- field it reads is the same, as it does your effects' rows. It never changes a row it handed on: a field that differs
-- makes a new row, and the last snapshot keeps the one it had. A unit row with no name yet is new each read, as a later
-- look can name it in place. So a read in a party or an alliance that reads the same makes no table for a member.
-- Measured with the collector stopped and the compiler off, as test_hud_draw_allocation.lua does.
local client = require('core.client');
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
-- You and count - 1 others, all in your zone, each with a name and full HP.
local members, names, hp = {}, {}, {};
local function gather(count)
    for slot = 0, 17 do
        members[slot] = slot < count and { id = 1001 + slot, index = 0x400 + slot, zone = 102 } or nil;
        names[slot], hp[slot] = 'Member' .. slot, 100;
    end
end
for name, key in pairs({ GetMemberServerId = 'id', GetMemberTargetIndex = 'index', GetMemberZone = 'zone' }) do
    party[name] = function(_, slot) return members[slot] and members[slot][key] or 0; end;
end
party.GetMemberName = function(_, slot) return names[slot]; end;
party.GetMemberIsActive = function(_, slot) return members[slot] and 1 or 0; end;
party.GetMemberHPPercent = function(_, slot) return hp[slot]; end;

local now = 1;
local function read()
    now = now + 0.1;
    return client.read(now);
end

local alloc = require('alloc_fixture');
-- Reads count times, for the KB a read makes once nothing it reads changes.
local function reads(count) for _ = 1, count do read(); end end
gather(6);
local party6 = alloc.measure(reads, 300);
gather(18);
local alliance18 = alloc.measure(reads, 300);
assert(#read().party == 17, 'Fixture: an alliance of eighteen.');
-- The snapshot's own lists grow with the members, which counts a little for each.
local each = (alliance18 - party6) / 12;
assert(each < 0.3, ('Each member past a party of six makes %.3f KB a read when nothing changes; only the snapshot\'s lists expected')
    :format(each));

gather(6);
-- A 0x076 lists the member in slot 1 with one effect.
local listing = MOCK.bytes(244);
MOCK.put(listing, 4, 4, 1002);
MOCK.put(listing, 8, 2, 0x401);
for slot = 0, 31 do listing[20 + slot] = 255; end
listing[20] = 33;
client.accept(MOCK.packet(0x076, listing), now, read());
local first = read();
local second = read();
assert(first.valid and #first.party == 5 and first.party[1].valid and first.party[1].effects[1].effect == 33,
    'Fixture: a party of six, the member in slot 1 listed.');
for n = 1, 5 do
    assert(second.party[n] == first.party[n], 'A member\'s row that reads the same is handed on: ' .. n);
    local id = first.party[n].id;
    assert(second.entities[id] == first.entities[id] and second.entities[id].name == 'Member' .. n,
        'So is their unit row: ' .. n);
end
assert(second.entities[1001] == first.entities[1001] and second.entities[1001].name == 'Member0',
    'Your own unit row that reads the same is handed on.');

-- Another HP makes a new row for that member alone, and the last snapshot keeps the one it had.
hp[2] = 40;
local third = read();
assert(third.party[2] ~= second.party[2] and third.party[2].hpp == 40 and second.party[2].hpp == 100,
    'Another HP makes a new row, and the last snapshot keeps its own.');
assert(third.party[1] == second.party[1] and third.party[3] == second.party[3], 'The other members keep theirs.');
assert(third.entities[1003] == second.entities[1003], 'HP isn\'t on a unit row, so that one is handed on.');
-- Another name makes a new row and a new unit row.
names[3] = 'Renamed';
local fourth = read();
assert(fourth.party[3] ~= third.party[3] and fourth.party[3].name == 'Renamed' and third.party[3].name == 'Member3',
    'Another name makes a new row, and the last snapshot keeps its own.');
assert(fourth.entities[1004] ~= third.entities[1004] and fourth.entities[1004].name == 'Renamed'
    and third.entities[1004].name == 'Member3', 'And a new unit row.');
-- A member with no name yet gets a new unit row each read.
names[4] = '';
local fifth, sixth = read(), read();
assert(fifth.party[4].name == nil and sixth.party[4] == fifth.party[4], 'A row with no name yet that reads the same is handed on.');
assert(fifth.entities[1005].name == nil and sixth.entities[1005] ~= fifth.entities[1005],
    'A unit row with no name yet is new each read.');
names[4] = 'Member4';
-- A new listing makes a new row for the member it lists, with the time and count it came with.
client.accept(MOCK.packet(0x076, listing), now, sixth);
local seventh = read();
assert(seventh.party[1] ~= sixth.party[1] and seventh.party[1].revision > sixth.party[1].revision,
    'A new listing makes a new row with its own count.');
assert(seventh.party[5] == sixth.party[5], 'The others keep theirs.');
-- A member who moves to another slot is a new row there.
members[2], members[3] = members[3], members[2];
local eighth = read();
assert(eighth.party[2].id == 1004 and eighth.party[2] ~= seventh.party[3] and eighth.party[2].slot == 2
    and seventh.party[3].slot == 3, 'A member in another slot gets a new row there.');
