-- client.read hands on your pet's row while every field it reads is the same, its place included, and never changes it:
-- a field that differs makes a new row, and the last snapshot keeps the one it had. A pet out of your view has no place,
-- and only a pet with your automaton's name has its HP. So a pet standing still adds no table to a read. Measured with
-- the collector stopped and the compiler off, as test_hud_draw_allocation.lua does.
local client = require('core.client');
local mm = AshitaCore:GetMemoryManager();
AshitaCore.GetMemoryManager = function() return mm; end;
local PET, PET_INDEX = 0x1000703, 0x703;
local out, x = true, 10;
local units = {
    GetServerId = function(_, index) return index == PET_INDEX and PET or index == 0x400 and MOCK.player.server_id or 0; end,
    GetPetTargetIndex = function(_, index) return index == 0x400 and out and PET_INDEX or 0; end,
    GetName = function(_, index) return index == PET_INDEX and 'Ironsides' or ''; end,
    GetLocalPositionX = function() return x; end,
    GetLocalPositionY = function() return 20; end,
    GetLocalPositionZ = function() return -3; end,
};
mm.GetEntity = function() return units; end;

local now = 1;
local function read()
    now = now + 0.1;
    return client.read(now);
end
local alloc = require('alloc_fixture');
-- Reads count times, for the KB a read makes once nothing it reads changes.
local function reads(count) for _ = 1, count do read(); end end
out = false;
local alone = alloc.measure(reads, 300);
assert(read().pet == nil, 'Fixture: no pet out.');
out = true;
local still = alloc.measure(reads, 300);
assert(read().pet.x == 10, 'Fixture: a pet out where the game shows it.');
-- The snapshot's own list of units has one more in it, which counts a little.
assert(still - alone < 0.15, ('A pet standing still adds %.3f KB to a read; only the snapshot\'s list of units expected')
    :format(still - alone));

local first = read();
local second = read();
assert(first.pet and first.pet.id == PET and first.pet.name == 'Ironsides' and first.pet.y == 20, 'Fixture: the pet is read.');
assert(second.pet == first.pet and second.entities[PET] == second.pet, 'A pet that reads the same keeps its row.');
x = 12;
local third = read();
assert(third.pet ~= second.pet and third.pet.x == 12 and second.pet.x == 10, 'A pet that moves gets a new row, and the last snapshot keeps its own.');
-- Out of your view (a despawn 0x00E) it has no place, and back in view it has one again.
local update = MOCK.bytes(64);
MOCK.put(update, 4, 4, PET);
update[10] = 0x20;
client.accept(MOCK.packet(0x00E, update), now, third);
local fourth = read();
local fifth = read();
assert(fourth.pet.away and fourth.pet.x == nil and fourth.pet.y == nil and fourth.pet.z == nil and third.pet.x == 12,
    'A pet out of view has no place, and the last snapshot keeps its own.');
assert(fifth.pet == fourth.pet, 'One that stays out of view keeps its row.');
update[10] = 0;
client.accept(MOCK.packet(0x00E, update), now, fifth);
local sixth = read();
assert(sixth.pet ~= fifth.pet and not sixth.pet.away and sixth.pet.x == 12 and fifth.pet.away, 'Back in view it has its place again.');
-- A PUP page for your automaton gives the pet with its name its HP, and the same page again keeps the row.
local page = MOCK.bytes(0x70);
MOCK.put(page, 4, 1, 18);
for i = 1, #'Ironsides' do page[0x57 + i] = ('Ironsides'):byte(i); end
MOCK.put(page, 0x68, 2, 780); MOCK.put(page, 0x6A, 2, 1000);
client.accept(MOCK.packet(0x044, page), now, sixth);
local seventh = read();
client.accept(MOCK.packet(0x044, page), now, seventh);
local eighth = read();
assert(seventh.pet.hp == 780 and seventh.pet.max_hp == 1000 and seventh.pet.automaton and sixth.pet.hp == nil,
    'Fixture: the automaton\'s HP is read.');
assert(eighth.pet == seventh.pet, 'The same page keeps the row.');
-- A pet by another name has no HP from that page.
units.GetName = function(_, index) return index == PET_INDEX and 'Carbuncle' or ''; end;
local ninth = read();
assert(ninth.pet.name == 'Carbuncle' and ninth.pet.hp == nil and ninth.pet.max_hp == nil and ninth.pet.automaton == nil
    and eighth.pet.hp == 780, 'A pet by another name has no HP from the page, and the last snapshot keeps its own.');
