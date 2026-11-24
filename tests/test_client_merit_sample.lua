-- Phoenix sends every merit at each zone-in, five 0x08C of 61, so the client keeps up to 305. A sample taken at an
-- action of yours hands on the merits as the client keeps them, with no copy, as its readers only look one up within the
-- packet's callback. A reset gives the client new ones, and a sample taken before keeps what it had. So a sample makes
-- no more with every merit known than with none. Measured with the collector stopped and the compiler off, as
-- test_hud_draw_allocation.lua does.
local client = require('core.client');
local mm = AshitaCore:GetMemoryManager();
AshitaCore.GetMemoryManager = function() return mm; end;
local snapshot = client.read(1);
assert(snapshot.valid, 'Fixture: a snapshot.');
-- Five 0x08C of 61 merits, each at rank 1 and the last at rank 3.
local function merits()
    for page = 0, 4 do
        local bytes = MOCK.bytes(256);
        MOCK.put(bytes, 4, 2, 61);
        for i = 0, 60 do
            MOCK.put(bytes, 8 + i * 4, 2, 0x40 + (page * 61 + i) * 2);
            bytes[8 + i * 4 + 3] = (page == 4 and i == 60) and 3 or 1;
        end
        client.accept(MOCK.packet(0x08C, bytes), 1, snapshot);
    end
end
local function garbage()
    local function run() client.sample_modifiers(snapshot); end
    jit.off(); jit.flush();
    for _ = 1, 60 do run(); end
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    for _ = 1, 6 do run(); end
    local before = collectgarbage('count');
    for _ = 1, 300 do run(); end
    local each = (collectgarbage('count') - before) * 1024 / 300;
    collectgarbage('restart');
    jit.on();
    return each;
end
local none = garbage();
merits();
local last = 0x40 + 304 * 2;
assert(client.merit(0x40) == 1 and client.merit(last) == 3, 'Fixture: 305 merits known.');
local every = garbage();
assert(every - none < 64, ('A sample with 305 merits known makes %.0f bytes more than with none; none expected'):format(every - none));

local sample = client.sample_modifiers(snapshot);
assert(sample.merits[0x40] == 1 and sample.merits[last] == 3 and sample.merits[0x41] == nil, 'A sample has the merits known.');
client.reset();
local fresh = client.sample_modifiers(snapshot);
assert(fresh.merits[last] == nil and sample.merits[last] == 3, 'After a reset a sample has none, and one taken before keeps its own.');
