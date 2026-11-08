-- Through vantage.lua as the game drives it, with userdata events: a BLU's 0x044 set list with Blank Gaze in it
-- lets dispel say a mob's buff can come off, and one without it takes that back.
local L = require('live_fixture');
local dispel = require('core.dispel');
MOCK.player.main_job, MOCK.player.main_level, MOCK.player.sub_job, MOCK.player.sub_level = 16, 75, 0, 0;
-- Blank Gaze (592) learned.
AshitaCore:GetMemoryManager():GetPlayer().HasSpell = function(_, id) return id == 592; end;
L.start();
local at = MOCK.now;
local function ready() at = at + 1; return dispel.ready(at); end
assert(ready() == false, 'Before any 0x044 the set is not known.');
-- 0x044 lists the set spells as their id less 0x200: Blank Gaze is 80.
L.blue_set(16, 0, { 80, 3 });
assert(ready() == true, 'With Blank Gaze set, a buff can come off.');
L.blue_set(16, 0, { 3, 7 });
assert(ready() == false, 'With it taken off the set, it can not.');
return true;
