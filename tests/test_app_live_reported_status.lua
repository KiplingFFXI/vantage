-- Through vantage.lua as the game drives it: two monster moves name another status than the one they put on. A
-- Seether's Occultation reports Blink and puts on Copy Image for 300 s, and Promathia's Seal of Quiescence reports Mute
-- and puts on Silence for 75 s (Phoenix scripts/actions/mobskills/occultation.lua :21-22, seal_of_quiescence.lua
-- :12-14). Each shows as what it put on, with that one's time.
local L = require('live_fixture');
local W = L.W;
local SEETHER, PROMATHIA = 0x1000100, 0x1000101;
W.unit(0x100, SEETHER, 'mob', 0, -5, { name = 'Seether' });
W.unit(0x101, PROMATHIA, 'mob', 3, -6, { name = 'Promathia' });
local app = L.start();
assert(app.state.snapshot.valid and #app.state.snapshot.party == 2, 'Fixture: you, Bob and Dave.');
L.listing({ { 1002, 0x401, {} }, { 1003, 0x402, {} } });
L.frame();

-- Occultation: category 11, its user its own target, message 186 with Blink, 36.
L.action(11, 1255, SEETHER, { { id = SEETHER, rows = { { message = 186, param = 36 } } } });
L.frame();
local copy = L.row(SEETHER, 66);
assert(not L.row(SEETHER, 36), 'No Blink row.');
assert(copy and copy.source == SEETHER and type(copy.remaining) == 'number' and copy.remaining > 295 and copy.remaining <= 300,
    'Copy Image for 300 s: ' .. tostring(copy and copy.remaining));
-- A hit that gets through says it had no shadows left.
L.action(1, 0, 1002, { { id = SEETHER, rows = { { message = 1, param = 40 } } } });
L.frame();
assert(not L.row(SEETHER, 66) and not L.row(SEETHER, 36), 'A hit that got through takes it off.');

-- Seal of Quiescence on Bob: message 242 with Mute, 29, and 277 on the next target.
L.action(11, 1507, PROMATHIA, { { id = 1002, rows = { { message = 242, param = 29 } } }, { id = 1003, rows = { { message = 277, param = 29 } } } });
L.frame();
local silence = L.row(1002, 6);
assert(not L.row(1002, 29) and not L.row(1003, 29), 'No Mute row.');
assert(silence and silence.source == PROMATHIA and type(silence.remaining) == 'number' and silence.remaining > 70 and silence.remaining <= 75,
    'Silence for 75 s: ' .. tostring(silence and silence.remaining));
assert(L.row(1003, 6), 'on each target.');
-- Bob's listing that shows Silence keeps the row, its source and its time.
L.listing({ { 1002, 0x401, { 6 } }, { 1003, 0x402, { 6 } } });
L.frame(); L.frame();
silence = L.row(1002, 6);
assert(silence and silence.source == PROMATHIA and type(silence.remaining) == 'number' and silence.remaining > 70 and silence.remaining < 75,
    'The listing keeps it: ' .. tostring(silence and silence.remaining));
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return true;
