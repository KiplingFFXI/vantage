-- The Phantom Roll display with two rolls in the party: one still open to Double-Up, one that went bust.
local C = require('preview.readme.common');
require('ui.icons').prepare();
local s = C.settings();
local rolls = s.rolls;
rolls.enabled, rolls.x, rolls.y, rolls.width = true, 16, 16, 340;
local view = C.view({});
-- The display's own samples, shown as live rolls.
view.rolls = require('core.rolls').samples(C.now);
return function() C.draw({ { settings = s, view = view } }); end;
