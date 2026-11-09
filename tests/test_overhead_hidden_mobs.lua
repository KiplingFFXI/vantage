-- No overhead block goes on a mob the server keeps out of players' sight, whatever put it on the list, the target too.
-- That is a server status other than 0 or 1 at 0x20 of its last 0x00E, its name hidden and untargetable at once in its
-- last update with the HP bit, or no 0x00E seen for it yet. The block goes the frame the packet comes, between two
-- list rebuilds too. Players are left alone.
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
local function has(id)
    for i = 1, plan.count do if plan.units[i].id == id then return true; end end
    return false;
end

local settings = W.settings();
-- Your target, a mob you claimed, a watched mob and one Bob debuffed, each with an effect to show, and Bob.
W.unit(0x100, 0x1000100, 'mob', 0, -5, { name = 'Target' });
W.unit(0x101, 0x1000101, 'mob', 1, -6, { name = 'Claimed' });
W.unit(0x102, 0x1000102, 'mob', -1, -7, { name = 'Watched' });
W.unit(0x103, 0x1000103, 'mob', 2, -8, { name = 'Debuffed' });
W.unit(0x401, 1002, 'player', 1, -3, { name = 'Bob' });
W.target, settings.watch_ids = 0x100, { 0x1000102 };
local snapshot = W.snapshot({ { id = 1002, index = 0x401, scope = 'party' } });
local view = W.view({ 0x1000100, 0x1000101, 0x1000102, { entity_id = 0x1000103, kind = 'debuff', scope = 'enemy', source = 1002 },
    1002 });
W.update(0x101, { mask = 0x02, claimer = 1001 });
local all = table.concat({ 0x1000100, 0x1000101, 0x1000102, 0x1000103, 1002 }, ' ');
W.frame(view, settings, snapshot);
assert(W.ids(plan) == all, 'Spawned at status 0, every mob has its block: ' .. W.ids(plan));
-- Phoenix's status change is an update with the HP bit.
local function status(index, value) W.update(index, { mask = 0x04, server_status = value }); end
for index = 0x100, 0x103 do status(index, 1); end
W.frame(view, settings, snapshot);
assert(W.ids(plan) == all, 'Status 1 shows them too: ' .. W.ids(plan));

-- Invisible (3), as Shikigami Weapon out of a fight. The debuffed mob's block goes the next frame, before the list is
-- made again, and stays gone when it is.
status(0x103, 3);
W.frame(view, settings, snapshot, false, 1 / 16);
local rest = table.concat({ 0x1000100, 0x1000101, 0x1000102, 1002 }, ' ');
assert(W.ids(plan) == rest, 'An invisible mob loses its block at once: ' .. W.ids(plan));
W.frame(view, settings, snapshot);
assert(W.ids(plan) == rest, 'The list made again leaves it out: ' .. W.ids(plan));
-- So do a claimed mob, a watched one and your target.
for index = 0x100, 0x102 do status(index, 3); end
W.frame(view, settings, snapshot);
assert(W.ids(plan) == '1002', 'No invisible mob has a block: ' .. W.ids(plan));
-- Disappearing (2), cutscene only (6) and every other status but 0 and 1 hide it too.
for _, value in ipairs({ 2, 4, 5, 6, 7, 18, 20 }) do
    status(0x100, value);
    W.frame(view, settings, snapshot);
    assert(not has(0x1000100), ('Status %d hides the target.'):format(value));
end
-- Engaged, Shikigami Weapon is sent at status 1 again.
for index = 0x100, 0x103 do status(index, 1); end
W.frame(view, settings, snapshot);
assert(W.ids(plan) == all, 'Back at status 1 every mob has its block: ' .. W.ids(plan));

-- Its name hidden (0x08 at 0x2B) and untargetable (0x800 in the flags at 0x21) at once, as a worm going under or a
-- chigoe roaming hidden.
W.update(0x100, { mask = 0x04, server_status = 1, namevis = 0x08, entity_flags = 0x800 });
W.frame(view, settings, snapshot, false, 1 / 16);
assert(not has(0x1000100), 'A target with its name hidden and untargetable loses its block at once.');
-- An update without the HP bit carries neither, so they stay as they were.
W.update(0x100, { mask = 0x01, server_status = 1 });
W.frame(view, settings, snapshot);
assert(not has(0x1000100), 'A position update keeps it hidden.');
-- Either one alone leaves the block.
W.update(0x100, { mask = 0x04, server_status = 1, namevis = 0x08 });
W.frame(view, settings, snapshot);
assert(has(0x1000100), 'A hidden name alone leaves the block.');
W.update(0x100, { mask = 0x04, server_status = 1, entity_flags = 0x800 });
W.frame(view, settings, snapshot);
assert(has(0x1000100), 'So does untargetable alone.');
-- Entity flags 0x080 and 0x008 change nothing, as many mobs players can see carry them.
W.update(0x100, { mask = 0x04, server_status = 1, namevis = 0x08, entity_flags = 0x088 });
W.frame(view, settings, snapshot);
assert(has(0x1000100), 'Entity flags 0x080 and 0x008 leave the block.');
status(0x100, 1);

-- A despawn (0x20 in the update bits) forgets the mob, so it has no block while the client still holds it, until its
-- spawn comes.
W.update(0x100, { mask = 0x30 });
W.frame(view, settings, snapshot);
assert(not has(0x1000100), 'After its despawn the target has no block.');
W.update(0x100);
W.frame(view, settings, snapshot);
assert(has(0x1000100), 'Its spawn brings the block back.');
-- A zone change forgets them all. No mob has a block until its spawn, as after reloading Vantage near it, and Bob keeps
-- his.
overhead.packet({ id = 0x00A, data = '', size = 0 });
W.frame(view, settings, snapshot);
assert(W.ids(plan) == '1002', 'With no 0x00E seen no mob has a block: ' .. W.ids(plan));
W.spawns();
W.update(0x101, { mask = 0x02, claimer = 1001 });
W.frame(view, settings, snapshot);
assert(W.ids(plan) == all, 'Their spawns bring them back: ' .. W.ids(plan));
return true;
