-- Whether the game is in front is read at the refresh rate, not every frame, since each read of the foreground
-- window makes a new handle. Another program in front still shows within a tenth of a second, and the game back in
-- front shows on the next frame, so a click right after coming back counts.
local copy = require('core.store').copy;
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 1, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return copy(snapshot); end };
local seen = {};
package.loaded['ui.hud'] = { draw = function(_, _, _, c) seen.focused = c.focused; end, draw_notices = function() end };
local app = dofile(ADDON_DIR .. '/vantage.lua'); app.refresh(1);
MOCK.frame(.11);
assert(seen.focused == true, 'Fixture: the game is in front.');

local c = require('ffi').C;
local original, reads = c.GetForegroundWindow, 0;
c.GetForegroundWindow = function(...) reads = reads + 1; return original(...); end;
for _ = 1, 60 do MOCK.frame(1 / 60); end
c.GetForegroundWindow = original;
assert(reads >= 9 and reads <= 11, 'A second of frames reads the foreground window about ten times: ' .. reads);

MOCK.foreground_pid = 9876;
local frames = 0;
repeat MOCK.frame(1 / 60); frames = frames + 1; until seen.focused == false or frames > 12;
assert(seen.focused == false and frames <= 7, 'Another program in front shows within a tenth of a second: ' .. frames .. ' frames.');
MOCK.foreground_pid = 1234;
frames = 0;
repeat MOCK.frame(1 / 60); frames = frames + 1; until seen.focused == true or frames > 12;
assert(seen.focused == true and frames == 1, 'The game back in front shows on the next frame: ' .. frames .. ' frames.');
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return true;
