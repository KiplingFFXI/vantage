-- Through vantage.lua as the game drives it, with userdata events: Dave's Haste on Bob (0x028) is a row on Bob
-- credited to Dave, with Haste's estimate counting down, and Bob's own listing (0x076) that shows it keeps both.
local L = require('live_fixture');
local app = L.start();
assert(app.state.snapshot.valid and #app.state.snapshot.party == 2, 'Fixture: you, Bob and Dave.');
L.listing({ { 1002, 0x401, {} }, { 1003, 0x402, {} } });
L.frame();

-- Dave casts Haste (spell 57) on Bob: message 230 with Haste, 33.
L.action(4, 57, 1003, { { id = 1002, rows = { { message = 230, param = 33 } } } });
L.frame();
local haste = L.row(1002, 33);
assert(haste and haste.kind == 'buff' and haste.scope == 'party', 'Dave\'s Haste is a row on Bob.');
assert(haste.source == 1003 and haste.spell == 57, 'Credited to Dave, from Haste: ' .. tostring(haste.source) .. ' ' .. tostring(haste.spell));
assert(type(haste.remaining) == 'number' and haste.remaining > 170 and haste.remaining <= 180,
    'With Haste\'s estimate counting down: ' .. tostring(haste.remaining));

-- Bob's listing that shows the Haste keeps the row, its caster and its estimate.
L.listing({ { 1002, 0x401, { 33 } }, { 1003, 0x402, {} } });
L.frame(); L.frame();
haste = L.row(1002, 33);
assert(haste and haste.source == 1003 and haste.spell == 57 and haste.remaining > 170 and haste.remaining < 180,
    'The listing keeps the caster and the estimate: ' .. tostring(haste and haste.remaining));
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return true;
