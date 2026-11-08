-- Placing overhead icons makes nothing per frame once running: the camera, the hide checks, the ten-a-second unit list
-- and every unit's head point, size and fade refill tables made once. Measured as the other allocation fixtures do,
-- with the collector stopped, and with the compiler off and its traces dropped: LuaJIT compiles traces late and at
-- random, and they count here too though the code makes nothing. The fixture's own getters read tables and make nothing.
local event_scan, interface_scan, focus_scan = 0x110000, 0x120000, 0x130000;
local interface, event_flag = 0x210000, 0x220000;
local memory = { [event_scan + 1] = event_flag, [interface_scan + 10] = interface, [focus_scan] = interface + 0x54,
    [interface + 0xB4] = 0, [event_flag] = 0, [interface + 0x54] = 0 };
ashita.memory.find = function(_, _, pattern)
    return pattern:sub(1, 2) == 'A0' and event_scan or pattern:sub(1, 8) == '8B442404' and interface_scan or focus_scan;
end;
local function read(address) return memory[address]; end
ashita.memory.read_uint8, ashita.memory.read_uint32 = read, read;
require('core.client')._set_pages(function() return true; end);

local W = require('overhead_fixture');
local overhead = require('core.overhead');
local plan = overhead.plan;
local settings = W.settings();
settings.overhead.units.other, settings.overhead.units.other_pet = true, true;
-- Twelve mobs, a party of five, another player's pet, your pet, the target and a subtarget, all with effects to show.
local members, rows = {}, {};
for i = 0, 11 do
    local id = 0x1000200 + i;
    W.unit(0x200 + i, id, 'mob', (i % 4) - 1.5, -4 - i, { name = 'Mob ' .. i, hitbox = 1 + i / 4 });
    rows[#rows + 1] = { entity_id = id, kind = 'debuff', scope = 'enemy', source = 1001 };
end
for i = 1, 4 do
    W.unit(0x400 + i, 1001 + i, 'player', i - 2.5, -2, { name = 'Member' .. i, race = i });
    members[#members + 1] = { id = 1001 + i, index = 0x400 + i, scope = 'party' };
    rows[#rows + 1] = { entity_id = 1001 + i, kind = 'buff', scope = 'party', source = 1001, mine = true };
end
W.unit(0x300, 0x1000300, 'pet', 2, -3, { name = 'Their pet' });
rows[#rows + 1] = { entity_id = 0x1000300, kind = 'buff', scope = 'pet', source = 1001, mine = true };
W.unit(0x301, 0x1000301, 'pet', -2, -1, { name = 'Pet' });
W.entities[W.self].pet = 0x301;
rows[#rows + 1] = { entity_id = 0x1000301, kind = 'buff', scope = 'pet', source = 1001, mine = true };
W.target, W.sub, W.sub_active = 0x203, 0x205, 1;
local snapshot, view = W.snapshot(members), W.view(rows);
settings.watch_ids = { 0x1000204 };

-- leak makes one empty table every sixth frame, ten a second, to show the measure catches it.
local leak, made = false, nil;
local function frames(count)
    for i = 1, count do
        W.frame(view, settings, snapshot, false, 1 / 60);
        if leak and i % 6 == 0 then made = {}; end
    end
end
-- KB a frame over count frames.
local function measure(count)
    jit.off(); jit.flush();
    frames(60);
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    local before = collectgarbage('count');
    frames(count);
    local each = (collectgarbage('count') - before) / count;
    collectgarbage('restart');
    jit.on();
    return each;
end
-- Warm, so the tables have grown.
frames(1200);
assert(plan.valid and plan.count == 10, 'Ten units placed: ' .. tostring(plan.count) .. ' ' .. tostring(plan.hidden));
local each = measure(600);
assert(plan.count == 10 and plan.considered >= 18, 'Still placing ' .. plan.count .. ' of ' .. plan.considered);
-- Under 2 bytes a frame: a table or cdata made even ten times a second would be more.
assert(each < 0.002, ('Placing overhead icons makes %.4f KB a frame; nothing expected'):format(each));
leak = true;
each = measure(600);
leak = false;
assert(each >= 0.002 and made, ('One table made ten times a second shows as %.4f KB a frame'):format(each));

-- Hidden and off frames make nothing either.
W.entities[W.self].status = 4;
frames(600);
assert(plan.hidden == 'In an event.');
each = measure(300);
assert(each < 0.002, ('A hidden frame makes %.4f KB'):format(each));
W.entities[W.self].status = 0;
settings.overhead.enabled = false;
frames(600);
each = measure(300);
assert(each < 0.002 and plan.hidden == 'Off.', ('An off frame makes %.4f KB'):format(each));
