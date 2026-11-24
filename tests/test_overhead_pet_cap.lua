-- At most 64 pets are remembered with their owners, and past that they are all forgotten at once. That happens before
-- a list rebuild reads whose pets are out, so each pet out then is the party's in that rebuild: here a member's pet
-- keeps its debuff's block on the frame another member's 65th pet comes. With 64 remembered and no new pet, none is
-- forgotten: a pet gone from the list keeps its debuff's block.
local W = require('overhead_fixture');
local overhead = require('core.overhead');
local JUG, CRAB, CRAB2, FIRST = 0x1000801, 0x1000100, 0x1000101, 0x1100001;
W.unit(0x401, 1002, 'player', 1, -3, { name = 'Bob', pet = 0x701 });
W.unit(0x402, 1003, 'player', 2, -4, { name = 'Dave' });
W.unit(0x701, JUG, 'pet', 1, -2, { name = 'CourierCarrie' });
W.unit(0x100, CRAB, 'mob', 0, -5, { name = 'Crab' });
W.unit(0x101, CRAB2, 'mob', 0, -6, { name = 'Crab' });
local settings = W.settings();
-- Bob comes first in the party, Dave after him.
local snapshot = W.snapshot({ { id = 1002, index = 0x401, scope = 'party' }, { id = 1003, index = 0x402, scope = 'party' } });
local debuff = { entity_id = CRAB, effect = 10, kind = 'debuff', scope = 'enemy', source = JUG };
-- Dave's first pet debuffs another crab.
local view = W.view({ debuff, { entity_id = CRAB2, effect = 10, kind = 'debuff', scope = 'enemy', source = FIRST } });
local function shown(id) return W.ids(overhead.plan):find(tostring(id or CRAB), 1, true) ~= nil; end
W.frame(view, settings, snapshot);
assert(shown(), 'Fixture: the crab Bob\'s pet debuffed has its block: ' .. W.ids(overhead.plan));
-- Dave calls 63 pets one after another at one place in the list, each gone when the next comes, so with Bob's 64 are
-- remembered.
for n = 1, 63 do
    W.unit(0x600, 0x1100000 + n, 'pet', 2, -3, { name = 'Pet ' .. n });
    W.entities[0x402].pet = 0x600;
    W.frame(view, settings, snapshot);
    assert(shown(), 'Fixture: Bob\'s pet keeps its debuff\'s block with ' .. n .. ' of Dave\'s pets seen.');
end
assert(shown(CRAB2), 'Fixture: Dave\'s first pet, gone from the list, keeps its debuff\'s block: ' .. W.ids(overhead.plan));
-- With 64 remembered, a frame with no new pet forgets none.
W.frame(view, settings, snapshot);
assert(shown(CRAB2), 'With 64 pets remembered and no new one, none is forgotten: ' .. W.ids(overhead.plan));
-- His next is the 65th. Bob's pet, still out, is the party's on that frame too.
W.unit(0x600, 0x1100000 + 64, 'pet', 2, -3, { name = 'Pet 64' });
W.frame(view, settings, snapshot);
assert(shown(), 'Bob\'s pet that is out keeps its debuff\'s block as the 65th pet comes: ' .. W.ids(overhead.plan));
assert(overhead.keeps(settings.overhead.types.mob, debuff), 'And its icon is kept.');
return 'Past 64 pets, every pet out is still its owner\'s';
