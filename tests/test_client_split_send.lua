-- A busy send can deliver the buff array (0x037) before the status icons and timers (0x063). Until the
-- 0x063 arrives, the timers still describe the old slots, so no slot timer is read.
local raw_time = 1000;
package.preload['core.clock'] = function() return {available=function() return true; end,get_game_time_raw=function() return raw_time; end}; end;
local client = require('core.client');
local stats = AshitaCore:GetMemoryManager():GetPlayer();
local buffs, icons, timers = {}, {}, {};
for slot = 1, 32 do buffs[slot], icons[slot], timers[slot] = -1, 255, 0; end
buffs[1], icons[1], timers[1] = 33, 33, 66000;
buffs[2], icons[2], timers[2] = 40, 40, 72000;
stats.GetBuffs = function() return buffs; end;
stats.GetStatusIcons = function() return icons; end;
stats.GetStatusTimers = function() return timers; end;
local function rows(snapshot)
    local out = {};
    for _, row in ipairs(snapshot.self_effects) do out[#out + 1] = row; end;
    return out;
end;
local snapshot = client.read(10);
assert(snapshot.self_known and not snapshot.self_timers_pending and #snapshot.self_effects == 2);
assert(snapshot.self_effects[1].raw_timer == 66000 and snapshot.self_effects[2].raw_timer == 72000);
assert(snapshot.self_effects[1].deadline == 10 + (66000 - 60000) / 60, 'The clock is loaded, so deadlines are real.');

-- Effect 33 wears off: the buff array shifts 40 into slot 0, while the old icons still list 33 there.
buffs[1], buffs[2] = 40, -1;
client.accept(MOCK.packet(0x037, MOCK.bytes(0x50)), 11, snapshot);
snapshot = client.read(11);
local listed = rows(snapshot);
assert(snapshot.self_timers_pending and #listed == 1 and listed[1].effect == 40 and listed[1].slot == 0);
assert(listed[1].raw_timer == nil and listed[1].deadline == nil, 'No timer is read while the 0x063 is pending.');

-- A recast of the same effect would also have matched the old icon; it is not trusted either.
icons[1] = 40;
snapshot = client.read(11.1);
assert(rows(snapshot)[1].raw_timer == nil, 'A matching stale icon still is not trusted before its 0x063.');

-- The 0x063 arrives with the shifted slots.
icons[1], icons[2], timers[1], timers[2] = 40, 255, 72000, 0;
local bytes = MOCK.bytes(200); MOCK.put(bytes, 4, 2, 9);
client.accept(MOCK.packet(0x063, bytes), 12, snapshot);
snapshot = client.read(12);
assert(not snapshot.self_timers_pending and rows(snapshot)[1].raw_timer == 72000, 'Timers return with the 0x063.');

-- A trailing 0x037 that leaves the list alone (Phoenix sends one after HP, MP or TP changes) keeps the timers.
client.accept(MOCK.packet(0x037, MOCK.bytes(0x50)), 13, snapshot);
snapshot = client.read(13);
assert(not snapshot.self_timers_pending and rows(snapshot)[1].raw_timer == 72000 and rows(snapshot)[1].deadline ~= nil,
    'An unchanged buff array keeps its timers.');
return true;
