-- Through vantage.lua as the game drives it, with userdata events: client.accept counts each 0x063 status listing
-- and each 0x076 party listing as it arrives, and the party listing gives Bob's row in the next snapshot his effects.
local L = require('live_fixture');
local client = require('core.client');
local app = L.start();
assert(app.state.snapshot.valid, 'Fixture: in the zone.');

local timers, listings = client.self_timer_revision(), client.party_revision();
L.self_timers();
assert(client.self_timer_revision() == timers + 1, 'A 0x063 is counted: ' .. client.self_timer_revision() .. ' after ' .. timers);
L.listing({ { 1002, 0x401, { 40, 43 } }, { 1003, 0x402, {} } });
assert(client.party_revision() == listings + 1, 'A 0x076 is counted: ' .. client.party_revision() .. ' after ' .. listings);
L.frame();
local bob;
for _, row in ipairs(app.state.snapshot.party) do if row.id == 1002 then bob = row; end end
assert(bob and bob.valid and #bob.effects == 2 and bob.effects[1].effect == 40 and bob.effects[2].effect == 43,
    'Bob\'s row carries the Protect and Refresh his listing gave.');
assert(L.row(1002, 40) and L.row(1002, 43), 'and both are rows on him in the view.');
L.self_timers(); L.self_timers();
assert(client.self_timer_revision() == timers + 3, 'Each 0x063 counts once.');
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return true;
