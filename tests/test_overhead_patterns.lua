-- A client pattern the scan doesn't find skips only its own check: overhead icons still show, and still hide on the
-- checks that remain. client.visibility, which needs all three, would give nothing every frame here.
local interface_scan, focus_scan = 0x120000, 0x130000;
local interface, menu, header = 0x210000, 0x230000, 0x240000;
local memory = { [interface_scan + 10] = interface, [focus_scan] = interface + 0x54, [interface + 0xB4] = 0,
    [interface + 0x54] = 0, [menu + 4] = header, [header + 0x4E] = 0x2070616D };
local reads = {};
ashita.memory.find = function(_, _, pattern)
    if pattern:sub(1, 2) == 'A0' then return 0; end
    return pattern:sub(1, 8) == '8B442404' and interface_scan or focus_scan;
end;
local function read(address) reads[address] = true; return memory[address]; end
ashita.memory.read_uint8, ashita.memory.read_uint32 = read, read;
local client = require('core.client');
client._set_pages(function() return true; end);

local W = require('overhead_fixture');
local overhead = require('core.overhead');
local plan = overhead.plan;
local settings = W.settings();
W.unit(0x100, 0x1000100, 'mob', 0, -5, { name = 'Target' });
W.target = 0x100;
local snapshot, view = W.snapshot(), W.view();
assert(client.capabilities().event == false and client.capabilities().hidden == true and client.capabilities().map == true);
assert(client.visibility(snapshot) == nil, 'client.visibility gives nothing with one pattern missing.');

W.frame(view, settings, snapshot);
assert(plan.count == 1 and plan.hidden == nil, 'With the event pattern missing the target still gets its block.');
for address in pairs(reads) do assert(address ~= 0 and address ~= 1, 'Nothing is read where the missing pattern would be.'); end
-- The checks that remain still hide.
memory[interface + 0xB4] = 1;
W.frame(view, settings, snapshot);
assert(plan.count == 0 and plan.hidden == 'The game interface is hidden.');
memory[interface + 0xB4] = 0;
memory[interface + 0x54] = menu;
W.frame(view, settings, snapshot);
assert(plan.count == 0 and plan.hidden == 'The map is open.');
memory[interface + 0x54] = 0;
-- Your own status 4 still hides in an event.
W.entities[W.self].status = 4;
W.frame(view, settings, snapshot);
assert(plan.count == 0 and plan.hidden == 'In an event.');
W.entities[W.self].status = 0;
-- A menu whose header can't be read is not the map.
memory[interface + 0x54], memory[menu + 4] = menu, nil;
W.frame(view, settings, snapshot);
assert(plan.count == 1, 'An unreadable menu hides nothing.');
