local raw_time = 1000;
package.preload['core.clock'] = function () return { available = function() return true; end, get_game_time_raw = function () return raw_time; end }; end
local client = require('core.client');
local mm = AshitaCore:GetMemoryManager();
local stats, party = mm:GetPlayer(), mm:GetParty();
local icons, timers = {}, {};
for i = 0, 31 do icons[i], timers[i] = 255, 0; end
icons[0], timers[0], icons[1], timers[1], icons[31], timers[31] = 33, 66000, 33, 67800, 40, 0x7FFFFFFF;
stats.GetStatusIcons = function () return icons; end;
stats.GetStatusTimers = function () return timers; end;
-- A synchronized client: its buff array lists the same effects as the status icons.
stats.GetBuffs = function () return icons; end;
local ally = { id = 1002, index = 0x401, zone = 102 };
local ally_visible = true;
mm.GetEntity = function () return { GetServerId = function (_, index) return ally_visible and index == 0x401 and 1002 or 0; end }; end;
AshitaCore.GetMemoryManager = function () return mm; end;
party.GetMemberServerId = function (_, slot) return slot == 0 and 1001 or slot == 1 and ally.id or 0; end;
party.GetMemberZone = function (_, slot) return slot == 0 and 102 or ally.zone; end;
party.GetMemberTargetIndex = function (_, slot) return slot == 0 and 0x400 or ally.index; end;
party.GetMemberName = function (_, slot) return slot == 0 and 'Tester' or 'Ally'; end;
local ally_hpp = 0;
party.GetMemberHPPercent = function (_, slot) return slot == 0 and 100 or ally_hpp; end;
assert(client.remaining(66000, 60000) == 100);
assert(client.remaining(0, 60000) == nil and client.remaining(0x7FFFFFFF, 60000) == nil);
assert(client.remaining(5000, 60000) == nil);
assert(client.remaining(30, 4294967266) == 1, 'Status clock wraps as uint32.');
local s = client.read(10);
assert(s.valid and s.self_known and #s.self_effects == 3);
assert(s.self_effects[1].deadline == 110 and s.self_effects[2].deadline == 140);
assert(s.self_effects[3].slot == 31 and s.self_effects[3].deadline == nil);
assert(#s.party == 1 and not s.party[1].valid, 'No packet means unavailable, not absent.');
assert(client.read(10.5).self_effects[1].deadline == 110, 'Frame reads do not move the deadline.');
raw_time = 1001;
assert(client.read(11).self_effects[1].deadline == 110);
timers[0] = 69000;
assert(client.read(12).self_effects[1].deadline == 161, 'Changed native timer refreshes the deadline.');
icons[5] = nil;
assert(not client.read(13).self_known);
icons[5] = 255;
local p = MOCK.bytes(244);
MOCK.put(p, 4, 4, 1002); MOCK.put(p, 8, 2, 0x401);
for i = 0, 31 do p[20 + i] = 255; end
p[20], p[21], p[12] = 52, 15, 1;
client.accept(MOCK.packet(0x076, p), 15, s);
s = client.read(15);
assert(s.party[1].valid and #s.party[1].effects == 2);
assert(type(s.party[1].revision) == 'number');
assert(s.party[1].effects[1].effect == 308 and s.party[1].effects[2].effect == 15, 'Party high bits preserve full status IDs.');
assert(s.party[1].hpp == 0, 'A party row carries the member HP percent, so a KO is read quietly.');
ally_visible = false;
assert(client.read(15.1).party[1].valid, 'A validated same-zone party snapshot does not require a spawned entity.');
ally_visible = true;
assert(client.read(15.2).party[1].valid, 'Returning into entity range preserves the party snapshot.');
client.accept(MOCK.packet(0x076, p), 15.3, s);
local broken = MOCK.packet(0x076, p); broken.size = 60;
client.accept(broken, 16, s);
assert(client.read(16).party[1].valid, 'A partial packet never replaces a complete snapshot.');
ally.index = 0x402;
assert(not client.read(17).party[1].valid, 'Reused IDs with mismatched indices stay unknown.');
ally.index, ally.zone = 0x401, 103;
assert(not client.read(18).party[1].valid);
ally.zone = 102;
assert(not client.read(19).party[1].valid, 'Returning to a zone requires fresh presence data.');
client.accept(MOCK.packet(0x076, p), 20, s);
local empty = MOCK.bytes(244);
client.accept(MOCK.packet(0x076, empty), 21, s);
assert(not client.read(21).party[1].valid, 'Omitted members are unknown.');
local merit = MOCK.bytes(12); MOCK.put(merit, 4, 2, 1); MOCK.put(merit, 8, 2, 0x0C04); merit[11] = 3;
client.accept(MOCK.packet(0x08C, merit), 22, s);
assert(client.sample_modifiers(s).merits[0x0C04] == 3);
client.reset();
s = client.read(23);
assert(s.valid and #s.self_effects == 3 and s.self_known, 'Reload recovers current paired native icons.');
assert(client.sample_modifiers(s).merits[0x0C04] == nil);
local zone = MOCK.bytes(52); MOCK.put(zone, 4, 4, 1001); MOCK.put(zone, 0x30, 2, 102);
client.accept(MOCK.packet(0x00A, zone), 24, s);
assert(not client.read(24).valid, 'Do not pair stale icons with the new zone.');
local status = MOCK.bytes(200); MOCK.put(status, 4, 2, 9);
client.accept(MOCK.packet(0x063, status), 25, s);
assert(client.read(25).valid and client.read(25).self_revision > s.self_revision);
MOCK.zoning = true;
assert(not client.read(26).valid);
MOCK.zoning=false;
mm.GetTarget=function() return {GetIsSubTargetActive=function() return 1; end,
    GetTargetIndex=function(_,slot) return slot==1 and 0x402 or 0x401; end}; end;
mm.GetEntity=function() return {GetServerId=function(_,index) return index==0x402 and 1003 or index==0x401 and 1002 or 0; end}; end;
local options=require('ui.defaults').make();
assert(client.read(27,options).target.id==1002, 'The active subtarget is native target index zero.');
options.tracking.follow_subtarget=false;
assert(client.read(28,options).target.id==1003, 'The underlying main target is native target index one while subtargeting.');

-- A focused menu whose title can't be read is not taken for the map.
local event_scan, interface_scan, focus_scan = 0x110000, 0x120000, 0x130000;
local interface, event_flag, menu, header = 0x210000, 0x220000, 0x230000, 0x240000;
local native = { [event_scan + 1] = event_flag, [interface_scan + 10] = interface, [focus_scan] = interface + 0x54,
    [interface + 0xB4] = 0, [event_flag] = 0, [interface + 0x54] = menu, [menu + 4] = header, [header + 0x4E] = 0x2070616D };
ashita.memory.find = function(_, _, pattern)
    if pattern:sub(1, 2) == 'A0' then return event_scan; end;
    return pattern:sub(1, 8) == '8B442404' and interface_scan or focus_scan;
end;
ashita.memory.read_uint8 = function(at) return native[at]; end;
ashita.memory.read_uint32 = function(at) return native[at]; end;
package.loaded['core.client'] = nil;
client = require('core.client');
-- Every address this fixture maps is on a readable page.
client._set_pages(function() return true; end);
assert(client.read(30).map == true, 'Fixture: the map is the focused menu.');
native[header + 0x4E] = nil;
assert(client.read(31).map == false, 'An unreadable map title reads as closed.');
