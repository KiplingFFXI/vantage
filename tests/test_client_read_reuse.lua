-- client.read keeps the tables it reads your party and alliance into, and the ones it hands roster.read, and fills them
-- again each refresh, as only it, bootstrap_party and roster.read read them, within the refresh. So a read in a party or
-- an alliance leaves nothing behind that its snapshot doesn't hold. Your effects' diagnostics for /vg report, and a named
-- target's row, are handed on while they read the same, and a row handed on never changes: a reader that kept the last
-- snapshot still reads what that read gave. Measured with the collector stopped and the compiler off, as
-- test_hud_draw_allocation.lua does, with every snapshot kept, so what the collector frees after the reads is what they
-- left behind.
local client = require('core.client');
local roster = require('core.roster');
local mm = AshitaCore:GetMemoryManager();
AshitaCore.GetMemoryManager = function() return mm; end;
local chat = { IsInputOpen = function() return 0; end };
AshitaCore.GetChatManager = function() return chat; end;
local me = GetPlayerEntity();
GetPlayerEntity = function() return me; end;
local stats, party = mm:GetPlayer(), mm:GetParty();
-- Eight effects on you, in the client's buff array counted from 0.
local icons = {};
for slot = 0, 31 do icons[slot] = slot < 8 and (slot + 40) or 255; end
stats.GetBuffs = function() return icons; end;
-- A mob you have targeted, with its name.
local MOB, MOB_INDEX = 0x1000123, 0x123;
local mob_name = 'Goblin Smithy';
local units = {
    GetServerId = function(_, index) return index == MOB_INDEX and MOB or 0; end,
    GetName = function(_, index) return index == MOB_INDEX and mob_name or ''; end,
    GetSpawnFlags = function(_, index) return index == MOB_INDEX and 0x10 or 0; end,
};
mm.GetEntity = function() return units; end;
local targets = { GetTargetIndex = function(_, n) return n == 0 and MOB_INDEX or 0; end, GetIsSubTargetActive = function() return 0; end };
mm.GetTarget = function() return targets; end;
-- You and count - 1 others, all in your zone.
local members = {};
local function gather(count)
    for slot = 0, 17 do members[slot] = slot < count and { id = 1001 + slot, index = 0x400 + slot, zone = 102 } or nil; end
end
for name, key in pairs({ GetMemberServerId = 'id', GetMemberTargetIndex = 'index', GetMemberZone = 'zone' }) do
    party[name] = function(_, slot) return members[slot] and members[slot][key] or 0; end;
end
party.GetMemberName = function(_, slot) return 'Member ' .. slot; end;
party.GetMemberIsActive = function(_, slot) return members[slot] and 1 or 0; end;
party.GetMemberMainJob = function() return 5; end;
party.GetMemberLastUpdatedTimestamp = function() return 1; end;

local now = 1;
local function read()
    now = now + 0.1;
    return client.read(now);
end

-- An alliance that breaks up leaves no member behind.
gather(18);
local whole = read();
assert(whole.valid and #whole.party == 17 and #roster.read(now, whole).members == 18, 'Fixture: an alliance of eighteen.');
gather(6);
local left = read();
assert(#left.party == 5 and left.party[5].id == 1006 and #roster.read(now, left).members == 6,
    'After the alliance breaks up, the party alone is read.');
assert(#whole.party == 17 and whole.party[17].id == 1018, 'The last snapshot keeps the alliance it read.');
-- A member who leaves loses their listing, so one who comes back waits for a new one.
local listing = MOCK.bytes(244);
MOCK.put(listing, 4, 4, 1002);
MOCK.put(listing, 8, 2, 0x401);
for slot = 0, 31 do listing[20 + slot] = 255; end
listing[20] = 33;
client.accept(MOCK.packet(0x076, listing), now, left);
local listed = read();
assert(listed.party[1].id == 1002 and listed.party[1].valid and listed.party[1].effects[1].effect == 33,
    'Fixture: a 0x076 lists the member in slot 1.');
local away = members[1];
members[1] = nil;
assert(#read().party == 4, 'Fixture: the member leaves.');
members[1] = away;
local back = read();
assert(back.party[1].id == 1002 and not back.party[1].valid, 'A member who comes back has no listing until a new 0x076.');

-- Your effects' diagnostics are handed on while they read the same.
local first = read();
local second = read();
assert(second.self_diagnostics == first.self_diagnostics and #second.self_diagnostics.rejected_slots == 0,
    'Diagnostics that read the same are handed on.');
icons[12] = -2;
local third = read();
assert(third.self_diagnostics ~= second.self_diagnostics and #third.self_diagnostics.rejected_slots == 1
    and third.self_diagnostics.rejected_slots[1].raw_value == -2 and #second.self_diagnostics.rejected_slots == 0,
    'A slot it can\'t use gives new diagnostics, and the last snapshot keeps the ones it had.');
local fourth = read();
assert(fourth.self_diagnostics == third.self_diagnostics, 'The same slot it can\'t use reads the same.');
icons[12] = -3;
local fifth = read();
assert(fifth.self_diagnostics ~= fourth.self_diagnostics and fifth.self_diagnostics.rejected_slots[1].raw_value == -3
    and fourth.self_diagnostics.rejected_slots[1].raw_value == -2, 'Another value there gives new diagnostics.');
icons[12] = 255;

-- A named target keeps its row while it reads the same.
first = read();
second = read();
assert(first.target and first.target.id == MOB and first.target.name == 'Goblin Smithy' and first.target.kind == 'monster',
    'Fixture: a named mob targeted.');
assert(second.target == first.target and second.entities[MOB] == first.target, 'A named target as it was keeps its row.');
mob_name = 'Goblin Tinkerer';
third = read();
assert(third.target ~= second.target and third.target.name == 'Goblin Tinkerer' and second.target.name == 'Goblin Smithy',
    'Another name gives a new row, and the last snapshot keeps the one it had.');
-- One with no name yet gets a new row each read, as a later look can name it in place.
mob_name = '';
fourth = read();
fifth = read();
assert(fifth.target ~= fourth.target and fourth.target.name == nil, 'A target with no name yet gets a new row each read.');
mob_name = 'Goblin Smithy';
client.resolve(MOB);
assert(fourth.target.name == nil, 'The last snapshot\'s row stays as it was when a look names it.');

-- KB a read that the collector frees after count reads. A collection can also shrink the Lua stack, which the next deep
-- enough call grows back once, so the smaller of two windows counts.
local function left_over(count)
    jit.off(); jit.flush();
    local least = math.huge;
    for _ = 1, 2 do
        local kept = {};
        for _ = 1, 60 do kept[0] = read(); end
        collectgarbage('collect'); collectgarbage('collect');
        collectgarbage('stop');
        for n = 1, count do kept[n] = read(); end
        local made = collectgarbage('count');
        collectgarbage('collect'); collectgarbage('collect');
        least = math.min(least, (made - collectgarbage('count')) / count);
        collectgarbage('restart');
    end
    jit.on();
    return least;
end
gather(6);
local party6 = left_over(300);
gather(18);
local alliance18 = left_over(300);
assert(party6 < 0.01, ('A read in a party of six leaves %.3f KB its snapshot doesn\'t hold, where none is expected')
    :format(party6));
assert(alliance18 < 0.01, ('A read in an alliance of eighteen leaves %.3f KB its snapshot doesn\'t hold, where none is expected')
    :format(alliance18));
