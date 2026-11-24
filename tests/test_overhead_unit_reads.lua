-- The overhead list reads from the client what placing a block uses. A unit's model size and type place nothing, and
-- a mob's or a player's type isn't needed to tell what it is, so making the list reads neither. /vg report and
-- /vg overhead calibrate still read them for their own lines.
local W = require('overhead_fixture');
local overhead = require('core.overhead');
local entities = AshitaCore:GetMemoryManager():GetEntity();
local reads, model_size, kind = { size = 0, type = 0 }, entities.GetModelSize, entities.GetType;
entities.GetModelSize = function(self, index) reads.size = reads.size + 1; return model_size(self, index); end;
entities.GetType = function(self, index) reads.type = reads.type + 1; return kind(self, index); end;
W.unit(0x100, 0x1000100, 'mob', 0, -5, { name = 'Crab' });
W.unit(0x401, 1002, 'player', 1, -3, { name = 'Member' });
W.target = 0x100;
local settings = W.settings();
local snapshot = W.snapshot({ { id = 1002, index = 0x401, scope = 'party' } });
for _ = 1, 4 do W.frame(W.view({ 0x1000100, 1002 }), settings, snapshot); end
assert(overhead.plan.count == 2, 'Fixture: the crab and the member have blocks: ' .. W.ids(overhead.plan));
assert(reads.size == 0 and reads.type == 0, ('Making the list read %d model sizes and %d types'):format(reads.size, reads.type));
return 'The overhead list reads no model size or type';
