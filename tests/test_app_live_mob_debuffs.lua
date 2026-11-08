-- Through vantage.lua as the game drives it, with userdata events: Bob's Paralyze and Dia on your target become
-- rows in the tracker view and a block over the mob with both icons; a mob Bob claimed, known only by its 0x00E,
-- gets a block for his Dia on it; a 0x029 wear-off takes Paralysis off and leaves Dia; a zone-in clears them.
local L = require('live_fixture');
local W = L.W;
W.unit(0x100, 0x1000100, 'mob', 0, -5, { name = 'Goblin Mugger', hitbox = 1.2 });
-- Its id's low 12 bits are not its index, so only its 0x00E says where it is.
W.unit(0x150, 0x10A0234, 'mob', 4, -8, { name = 'Goblin Gambler', hitbox = 1.2 });
W.target = 0x100;
local app = L.start();
assert(app.state.snapshot.valid and #app.state.snapshot.party == 2, 'Fixture: you, Bob and Dave.');

-- Bob's Paralyze (spell 58, message 236 with Paralysis, 4) and Dia (spell 23, message 2 with its damage).
L.action(4, 58, 1002, { { id = 0x1000100, rows = { { message = 236, param = 4 } } } });
L.action(4, 23, 1002, { { id = 0x1000100, rows = { { message = 2, param = 6 } } } });
L.frame();
local paralysis, dia = L.row(0x1000100, 4), L.row(0x1000100, 134);
assert(paralysis and paralysis.source == 1002 and paralysis.kind == 'debuff' and paralysis.scope == 'enemy',
    'Bob\'s Paralyze is a row on the mob.');
assert(dia and dia.source == 1002 and dia.kind == 'debuff', 'So is his Dia.');
local block = L.unit(0x1000100);
assert(block and block.kind == 'mob' and block.target, 'The mob, your target, keeps a block.');
assert(L.drew(4) and L.drew(134), 'Its block draws the Paralysis and Dia icons.');
assert(block.anchor_y < block.y, 'Above its name.');

-- A mob Bob claimed: its 0x00E gives its index and claimer, and his Dia on it gives it a block.
L.entity(0x10A0234, 0x150, 1002);
L.action(4, 23, 1002, { { id = 0x10A0234, rows = { { message = 2, param = 6 } } } });
L.frame();
assert(L.row(0x10A0234, 134), 'Bob\'s Dia on the mob he claimed is a row.');
assert(require('core.overhead')._claimer(0x10A0234) == 1002, 'Its 0x00E names Bob as the claimer.');
local claimed = L.unit(0x10A0234);
assert(claimed and claimed.kind == 'mob' and claimed.index == 0x150 and not claimed.target, 'The claimed mob keeps a block too.');

-- Paralysis wears off the target (0x029, message 206): its row goes, Dia stays, and the block draws Dia alone.
L.message(0x1000100, 0x1000100, 4, 206);
L.frame();
assert(not L.row(0x1000100, 4) and L.row(0x1000100, 134), 'The wear-off takes the Paralysis row off and leaves Dia.');
assert(L.unit(0x1000100) and not L.drew(4) and L.drew(134), 'The block draws Dia without Paralysis.');

-- A zone-in (0x00A) clears every row, and nothing is placed while you zone.
L.zone_in(102, false);
L.frame();
assert(not L.row(0x1000100, 134) and not L.row(0x10A0234, 134), 'The zone-in clears the rows.');
assert(not app.state.snapshot.valid and require('core.overhead').plan.count == 0, 'Nothing is placed while you zone.');
L.self_timers();
L.frame();
assert(app.state.snapshot.valid and not L.row(0x1000100, 134), 'Back in the zone with nothing on the mob.');
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return true;
