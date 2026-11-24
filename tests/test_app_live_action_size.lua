-- Through vantage.lua as the game drives it, with userdata events: a 0x028 action is read from its bits, so the
-- packet_in handler takes its size from the event and never copies its data, and the action still makes its rows.
local L = require('live_fixture');
local W = L.W;
local client = require('core.client');
W.unit(0x100, 0x1000100, 'mob', 0, -5, { name = 'Goblin Mugger', hitbox = 1.2 });
W.target = 0x100;
local app = L.start();
assert(app.state.snapshot.valid, 'Fixture: in the zone.');

local copies, packet_size = 0, client.packet_size;
client.packet_size = function(e, ...)
    if e.id == 0x028 then copies = copies + 1; end
    return packet_size(e, ...);
end;
-- Bob's Paralyze (spell 58, message 236 with Paralysis, 4).
L.action(4, 58, 1002, { { id = 0x1000100, rows = { { message = 236, param = 4 } } } });
client.packet_size = packet_size;
L.frame();
assert(copies == 0, 'A 0x028 is not copied: ' .. copies .. ' copies.');
local paralysis = L.row(0x1000100, 4);
assert(paralysis and paralysis.source == 1002, 'Bob\'s Paralyze is still a row on the mob.');
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return true;
