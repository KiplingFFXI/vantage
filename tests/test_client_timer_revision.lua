-- The client counts the 0x063 status timer updates it takes (type 9), so the tracker can tell whether a
-- listing was read after a 0x063 that came after an application. Nothing else moves the count.
package.preload['core.clock'] = function() return {available=function() return true; end,get_game_time_raw=function() return 1000; end}; end;
local client = require('core.client');
local stats = AshitaCore:GetMemoryManager():GetPlayer();
local icons, timers = {}, {};
for slot = 0, 31 do icons[slot], timers[slot] = 255, 0; end
icons[0], timers[0] = 33, 66000;
stats.GetBuffs = function() return icons; end;
stats.GetStatusIcons = function() return icons; end;
stats.GetStatusTimers = function() return timers; end;
local function timer_update(kind, size)
    local bytes = MOCK.bytes(size or 200); MOCK.put(bytes, 4, 2, kind or 9);
    return MOCK.packet(0x063, bytes);
end;

local snapshot = client.read(10);
local start = snapshot.self_timer_revision;
assert(type(start) == 'number' and start == client.self_timer_revision(), 'The snapshot carries the count.');
client.accept(MOCK.packet(0x037, MOCK.bytes(0x50)), 11, snapshot);
assert(client.self_timer_revision() == start and client.read(11).self_timer_revision == start,
    'A 0x037 alone is no 0x063.');
client.accept(timer_update(), 12, snapshot);
assert(client.self_timer_revision() == start + 1 and client.read(12).self_timer_revision == start + 1,
    'A status timer update moves it by one.');
client.accept(timer_update(5), 13, snapshot);
client.accept(timer_update(9, 120), 13, snapshot);
local injected = timer_update(); injected.injected = true;
local blocked = timer_update(); blocked.blocked = true;
client.accept(injected, 13, snapshot);
client.accept(blocked, 13, snapshot);
assert(client.self_timer_revision() == start + 1, 'Other 0x063 types, short, injected or blocked packets do not count.');
client.reset();
assert(client.read(14).self_timer_revision == start + 1, 'A reset keeps the count, so a later 0x063 is still after.');
local zone = MOCK.bytes(52); MOCK.put(zone, 4, 4, 1001); MOCK.put(zone, 0x30, 2, 102);
client.accept(MOCK.packet(0x00A, zone), 15, snapshot);
client.accept(timer_update(), 16, snapshot);
assert(client.self_timer_revision() == start + 2, 'The 0x063 that ends a zone wait counts too.');
