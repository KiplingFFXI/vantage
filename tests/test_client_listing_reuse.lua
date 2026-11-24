-- Phoenix sends a 0x076 with every member's effects at each change to any of them, so most of its members read as they
-- did. A member whose 40 bytes of effects, index and zone are the same as their last listing's keeps that listing's list,
-- as nothing changes a list once it is made. Other bytes, or another index, make a new list, and the last snapshot keeps
-- the one it had. So a 0x076 that repeats makes no more with ten effects on each member than with none. Measured with the
-- collector stopped and the compiler off, as test_hud_draw_allocation.lua does.
local client = require('core.client');
local mm = AshitaCore:GetMemoryManager();
AshitaCore.GetMemoryManager = function() return mm; end;
local me = GetPlayerEntity();
GetPlayerEntity = function() return me; end;
local stats, party = mm:GetPlayer(), mm:GetParty();
local icons = {};
for slot = 0, 31 do icons[slot] = 255; end
stats.GetBuffs = function() return icons; end;
local units = { GetServerId = function() return 0; end };
mm.GetEntity = function() return units; end;
local members = {};
for slot = 0, 5 do members[slot] = { id = 1001 + slot, index = 0x400 + slot, zone = 102 }; end
for name, key in pairs({ GetMemberServerId = 'id', GetMemberTargetIndex = 'index', GetMemberZone = 'zone' }) do
    party[name] = function(_, slot) return members[slot] and members[slot][key] or 0; end;
end
party.GetMemberName = function(_, slot) return 'Member' .. slot; end;
party.GetMemberIsActive = function(_, slot) return members[slot] and 1 or 0; end;

-- A 0x076's bytes for the five members with count effects on each, the first of them above 255 by its top bits.
local function listing(count)
    local bytes = MOCK.bytes(244);
    for row = 0, 4 do
        local start = 4 + row * 48;
        MOCK.put(bytes, start, 4, members[row + 1].id);
        MOCK.put(bytes, start + 4, 2, members[row + 1].index);
        if count > 0 then bytes[start + 8] = 1; end
        for slot = 0, 31 do bytes[start + 16 + slot] = slot < count and (40 + slot) or 255; end
    end
    return bytes;
end
local now = 1;
local snapshot = client.read(now);
-- Bytes a 0x076 makes when it repeats.
local function measure(packet)
    local size, data = client.packet_size(packet);
    local function accept() now = now + 0.01; client.accept(packet, now, snapshot, size, data); end
    jit.off(); jit.flush();
    for _ = 1, 60 do accept(); end
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    for _ = 1, 6 do accept(); end
    local before = collectgarbage('count');
    for _ = 1, 300 do accept(); end
    local each = (collectgarbage('count') - before) * 1024 / 300;
    collectgarbage('restart');
    jit.on();
    return each;
end
local ten = MOCK.packet(0x076, listing(10));
local empty = measure(MOCK.packet(0x076, listing(0)));
local full = measure(ten);
snapshot = client.read(now);
assert(snapshot.party[1].valid and #snapshot.party[1].effects == 10 and snapshot.party[1].effects[1].effect == 296,
    'Fixture: ten effects on each member, the first above 255.');
assert(full - empty < 512, ('A 0x076 that repeats makes %.0f bytes more with ten effects a member than with none; none expected')
    :format(full - empty));

client.accept(ten, now, snapshot);
local first = client.read(now);
client.accept(ten, now + 0.1, first);
local second = client.read(now + 0.1);
for n = 1, 5 do
    assert(second.party[n].effects == first.party[n].effects and second.party[n].revision > first.party[n].revision,
        'The same bytes keep the list, with the new listing\'s count: ' .. n);
end
-- Another effect on one member makes a new list for them alone.
local bytes = listing(10);
bytes[20 + 12] = 77;
client.accept(MOCK.packet(0x076, bytes), now + 0.2, second);
local third = client.read(now + 0.2);
assert(third.party[1].effects ~= second.party[1].effects and #third.party[1].effects == 11 and third.party[1].effects[11].effect == 77,
    'Another effect makes a new list.');
assert(#second.party[1].effects == 10, 'The last snapshot keeps the list it had.');
assert(third.party[2].effects == second.party[2].effects, 'The other members keep theirs.');
-- A member listed at another index gets a new list from the same bytes.
members[2].index = 0x412;
MOCK.put(bytes, 4 + 48 + 4, 2, 0x412);
client.accept(MOCK.packet(0x076, bytes), now + 0.3, third);
local fourth = client.read(now + 0.3);
assert(fourth.party[2].valid and fourth.party[2].index == 0x412, 'Fixture: the member is listed at the new index.');
assert(fourth.party[2].effects ~= third.party[2].effects and #fourth.party[2].effects == 10, 'Another index makes a new list.');
assert(fourth.party[3].effects == third.party[3].effects, 'The members where they were keep theirs.');
