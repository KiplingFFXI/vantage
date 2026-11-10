-- A unit tick the list doesn't have, from a hand edit or a newer Vantage (overhead.units.mob, say), gets no block and
-- breaks nothing: another player's charmed mob, found with the other pets, is still left out, and a mob still gets a
-- block for a reason it has, such as being your target. The tidy keeps the tick.
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
local plan = require('core.overhead').plan;
local settings = W.settings();
settings.overhead.units.mob, settings.overhead.units.zz_newer, settings.overhead.units.other_pet = true, true, true;
settings = require('ui.defaults').tidy(settings);
assert(settings.overhead.units.mob == true and settings.overhead.units.zz_newer == true, 'The tidy keeps a unit tick it doesn\'t know.');
W.unit(0x100, 0x1000100, 'mob', 0, -5, { name = 'Target' });
W.unit(0x101, 0x1000101, 'mob', 1, -6, { name = 'Charmed' });
W.target = 0x100;
local view, snapshot = W.view({ 0x1000100, { entity_id = 0x1000101, kind = 'buff', scope = 'pet' } }), W.snapshot();
for _ = 1, 3 do
    W.frame(view, settings, snapshot);
    assert(plan.valid and plan.hidden == nil, 'The plan is placed: ' .. tostring(plan.hidden));
    assert(W.ids(plan) == tostring(0x1000100), 'Only the target gets a block: ' .. W.ids(plan));
end
