-- A PUP gets the job extra's PUP page (0x044) again and again in a fight, most often the same as the last. A page whose
-- bytes are the same as the last keeps the automaton read from it, with its attachments, skills and stats, so it makes
-- no table. A page that changes makes new ones, and a reader that kept the last snapshot still has the automaton it
-- gave. Measured as test_hud_draw_allocation.lua does, with the collector stopped and the compiler off.
local client = require('core.client');
local mm = AshitaCore:GetMemoryManager();
AshitaCore.GetMemoryManager = function() return mm; end;
local PUPPET, PUPPET_INDEX = 0x1000703, 0x703;
local units = {
    GetServerId = function(_, index) return index == PUPPET_INDEX and PUPPET or index == 0x400 and MOCK.player.server_id or 0; end,
    GetPetTargetIndex = function(_, index) return index == 0x400 and PUPPET_INDEX or 0; end,
    GetName = function(_, index) return index == PUPPET_INDEX and 'Ironsides' or ''; end,
};
mm.GetEntity = function() return units; end;
MOCK.player.main_job = 18;
-- A PUP page for Ironsides with this HP, a Valoredge head and frame and its first attachment, or one cut short before the
-- build. Each has the next number in the header, as packets from the server do.
local sync = 0;
local function page(hp, attachment, short)
    local bytes = MOCK.bytes(short and 0x90 or 0xA0);
    sync = sync + 1;
    MOCK.put(bytes, 2, 2, sync);
    MOCK.put(bytes, 4, 1, 18);
    MOCK.put(bytes, 8, 1, 2); MOCK.put(bytes, 9, 1, 0x21); MOCK.put(bytes, 0x0A, 1, attachment);
    for i = 1, #'Ironsides' do bytes[0x57 + i] = ('Ironsides'):byte(i); end
    MOCK.put(bytes, 0x68, 2, hp); MOCK.put(bytes, 0x6A, 2, 1000);
    if not short then
        MOCK.put(bytes, 0x6C, 2, 0); MOCK.put(bytes, 0x6E, 2, 0);
        for index = 1, 3 do MOCK.put(bytes, 0x6C + index * 4, 2, 100 + index); MOCK.put(bytes, 0x6E + index * 4, 2, 200 + index); end
        for index = 1, 7 do MOCK.put(bytes, 0x7C + index * 4, 2, 50 + index); MOCK.put(bytes, 0x7E + index * 4, 2, index); end
    end
    return MOCK.packet(0x044, bytes);
end
local full = page(780, 97);
client.accept(full, 1);
local first = client.read(1);
local held = first.pet and first.pet.automaton;
assert(held and held.hp == 780 and held.attachments[1] == 97 and held.skills[2][1] == 102 and held.stats[7][2] == 7,
    'Fixture: the page is read.');
client.accept(page(780, 97), 2);
local second = client.read(2);
assert(second.pet.automaton == held and held.attachments and held.skills and held.stats, 'The same page keeps the automaton.');
client.accept(page(612, 97), 3);
local third = client.read(3);
assert(third.pet.automaton ~= held and third.pet.automaton.hp == 612 and third.pet.hp == 612, 'A changed page makes a new one.');
assert(second.pet.automaton.hp == 780 and second.pet.hp == 780 and held.attachments[1] == 97, 'The last snapshot keeps its own.');
client.accept(page(612, 104), 4);
local fourth = client.read(4);
assert(fourth.pet.automaton.attachments[1] == 104 and third.pet.automaton.attachments[1] == 97, 'An attachment changed is a change.');
client.accept(page(612, 104, true), 5);
local fifth = client.read(5);
assert(fifth.pet.automaton.hp == 612 and fifth.pet.automaton.attachments == nil, 'A short page is not the whole page before it.');
client.accept(page(612, 104), 6);
assert(client.read(6).pet.automaton.attachments[1] == 104, 'Fixture: the whole page again.');
-- A reset forgets the automaton, and the same page afterwards reads it again.
client.reset();
client.accept(page(612, 104), 7);
assert(client.read(7).pet.automaton.hp == 612, 'After a reset the same page is read again.');
-- So does another character on the next read.
MOCK.player.server_id = 1009;
assert(client.read(8).pet.automaton == nil, 'Fixture: another character has none.');
client.accept(page(612, 104), 9);
assert(client.read(9).pet.automaton.hp == 612, 'After another character, the same page is read again.');

local same = page(780, 97);
client.accept(same, 10);
local function pages(count) for _ = 1, count do client.accept(same, 10); end end
jit.off(); jit.flush();
pages(60);
collectgarbage('collect'); collectgarbage('collect');
collectgarbage('stop');
pages(6);
local before = collectgarbage('count');
pages(600);
local each = (collectgarbage('count') - before) / 600;
collectgarbage('restart');
jit.on();
assert(each < 0.005, ('The same PUP page again makes %.3f KB; nothing expected'):format(each));
