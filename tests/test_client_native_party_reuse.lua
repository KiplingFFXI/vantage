-- After a load in a party, until the first 0x076, each refresh reads your party's effects from the client's party icons
-- (bootstrap_party in core/client.lua). A member whose icons and mask read the same as last time keeps their entry and
-- its list, as a member's listing from a 0x076 does, so such a refresh makes nothing for them, with a mask the client
-- gives as a number or as 64-bit cdata. Icons that change make a new list, and the last snapshot keeps the one it had.
-- Measured as test_hud_draw_allocation.lua does, with the collector stopped and the compiler off: a read while the icons
-- are read makes no more than one after a 0x076 has given the members' effects. Icons that read the same keep the time
-- they were first read, as a listing keeps the time its packet came, so neither kind of read makes a member's row anew.
local client = require('core.client');
client._set_pages(function() return true; end);
local mm = AshitaCore:GetMemoryManager();
AshitaCore.GetMemoryManager = function() return mm; end;
local me = GetPlayerEntity();
GetPlayerEntity = function() return me; end;
local stats, party = mm:GetPlayer(), mm:GetParty();
local buffs = {};
for slot = 0, 31 do buffs[slot] = 255; end
stats.GetBuffs = function() return buffs; end;
local units = { GetServerId = function() return 0; end };
mm.GetEntity = function() return units; end;
local members = { [0] = { id = 1001, index = 0x400, zone = 102 } };
for slot = 1, 5 do members[slot] = { id = 1001 + slot, index = 0x400 + slot, zone = 102 }; end
for name, key in pairs({ GetMemberServerId = 'id', GetMemberTargetIndex = 'index', GetMemberZone = 'zone' }) do
    party[name] = function(_, slot) return members[slot] and members[slot][key] or 0; end;
end
party.GetMemberName = function(_, slot) return 'Member ' .. slot; end;
party.GetMemberIsActive = function(_, slot) return members[slot] and 1 or 0; end;
-- Twelve effects on each member, in the client's icon tables counted from 0.
local icons = {};
for entry = 0, 4 do
    icons[entry] = {};
    for slot = 0, 31 do icons[entry][slot] = slot < 12 and (slot + 40) or 255; end
end
local mask = 0;
party.GetStatusIconsServerId = function(_, entry) return members[entry + 1].id; end;
party.GetStatusIconsTargetIndex = function(_, entry) return members[entry + 1].index; end;
party.GetStatusIcons = function(_, entry) return icons[entry]; end;
party.GetStatusIconsBitMask = function() return mask; end;

local first = client.read(1);
local second = client.read(2);
for n = 1, 5 do
    assert(first.party[n].valid and #first.party[n].effects == 12, 'Fixture: twelve effects on member ' .. n);
    assert(second.party[n].effects == first.party[n].effects and second.party[n].revision == first.party[n].revision,
        'Icons that read the same keep the member\'s list and revision: ' .. n);
    assert(second.party[n].observed_at == 1, 'The time they were first read stays: ' .. tostring(second.party[n].observed_at));
    assert(second.party[n] == first.party[n], 'Icons that read the same keep the member\'s row: ' .. n);
end
icons[0][3] = 77;
local third = client.read(3);
assert(third.party[1].effects ~= second.party[1].effects and third.party[1].effects[4].effect == 77
    and third.party[1].revision > second.party[1].revision, 'A changed icon makes a new list with a new revision.');
assert(#second.party[1].effects == 12 and second.party[1].effects[4].effect == 43, 'The last snapshot keeps the list it had.');
assert(third.party[2].effects == second.party[2].effects, 'The other members keep theirs.');
icons[0][3] = 43;
-- A 64-bit mask is read by value: a new one with the same bits keeps the list, and other bits make a new one.
mask = 0x10ULL;
local fourth = client.read(4);
assert(fourth.party[2].effects ~= third.party[2].effects and fourth.party[2].effects[3].effect == 42 + 256,
    'The mask\'s top bits are part of the effect.');
mask = 0x10ULL + 0;
local fifth = client.read(5);
assert(fifth.party[2].effects == fourth.party[2].effects, 'A new mask with the same bits keeps the list.');
mask = 0x40ULL;
local sixth = client.read(6);
assert(sixth.party[2].effects ~= fifth.party[2].effects and sixth.party[2].effects[4].effect == 43 + 256
    and fifth.party[2].effects[3].effect == 42 + 256, 'Other bits make a new list, and the last snapshot keeps its own.');

local now = 10;
party.GetMemberHPPercent = function() return 90; end;
local function reads(count)
    for _ = 1, count do
        now = now + 0.1;
        client.read(now);
    end
end
local alloc = require('alloc_fixture');
mask = 0;
local as_number = alloc.measure(reads, 300);
mask = 0x10ULL;
local as_cdata = alloc.measure(reads, 300);
-- A 0x076 gives the same five members their effects, and from then on the icons aren't read for them.
local bytes = MOCK.bytes(244);
for row = 0, 4 do
    local start = 4 + row * 48;
    MOCK.put(bytes, start, 4, members[row + 1].id);
    MOCK.put(bytes, start + 4, 2, members[row + 1].index);
    for slot = 0, 31 do bytes[start + 16 + slot] = slot < 12 and (slot + 40) or 255; end
end
local before_packet = client.read(now);
client.accept(MOCK.packet(0x076, bytes), now, before_packet);
local after_packet = client.read(now + 0.05);
assert(after_packet.party[1].valid and after_packet.party[1].effects ~= before_packet.party[1].effects
    and after_packet.party[1].revision > before_packet.party[1].revision, 'Fixture: the 0x076 gives the members\' listings.');
local listed = alloc.measure(reads, 300);
assert(as_number - listed < 0.05, ('Reading icons that read the same makes %.3f KB a read more than a 0x076 listing; nothing expected')
    :format(as_number - listed));
assert(as_cdata - listed < 0.05, ('With a 64-bit mask, %.3f KB a read more; nothing expected'):format(as_cdata - listed));
