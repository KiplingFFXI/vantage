-- /vg reset navigation and Reset all settings say Undo recovers them. Both are
-- Undo steps for the settings window too: Undo puts back Hold Shift to see through this window, and for Reset all the
-- window's place and size, and Redo resets them again. Moving between pages and sections still makes no Undo step.
local store = require('core.store');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
require('ui.party_hud').draw = function() return 0, {}; end;
require('ui.native_party_hud').draw = function() return 0, {}; end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, update = function() end,
    status = function() return { active = false }; end, restore = function() return true; end, suspend = function() end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
app.state.dirty = true; assert(app.callbacks.save(), 'Fixture: the settings are on disk.');
local function s() return app.state.settings; end;
local function window() return s().window; end;
-- An earlier display change: timer font size 16 -> 20.
app.callbacks.changed('before', 'Timer font size'); s().style.font_size = 20; app.callbacks.changed('after'); assert(app.callbacks.save(), 'Fixture: saved.');
-- The player turns off peek; a page click comes with it.
window().peek = false;
window().tab = 'Profiles';
app.callbacks.editor_changed(true);
assert(#app.state.history == 1, 'Fixture: moving between pages and turning off peek made no Undo step.');
assert(app.callbacks.reset('navigation'), 'Fixture: the reset ran.');
assert(window().peek == true, 'Fixture: the navigation is reset.');
assert(#app.state.history == 2 and app.state.history[2].label == 'Reset navigation', 'The navigation reset is an Undo step.');
assert(app.callbacks.undo(), 'Fixture: Undo ran.');
assert(window().peek == false, 'Undo puts the navigation back.');
assert(s().style.font_size == 20, 'Undo takes back the reset, not the earlier font change.');
assert(store.read(app.state.path).window.peek == false, 'The navigation Undo put back is saved.');
assert(app.callbacks.redo() and window().peek == true, 'Redo resets it again.');
assert(app.callbacks.undo() and window().peek == false, 'Fixture: back to the player\'s navigation.');

-- Reset all settings, with the window moved and sized.
window().x, window().width = 640, 1200;
app.callbacks.changed('before', 'Settings window', nil, true); app.callbacks.changed('after'); assert(app.callbacks.save(), 'Fixture: saved.');
local steps = #app.state.history;
assert(app.callbacks.reset('all'), 'Fixture: the reset ran.');
assert(s().style.font_size == 16 and window().x == 100 and window().width == 960 and window().peek == true, 'Fixture: all reset.');
assert(#app.state.history == steps + 1, 'Reset all is one Undo step.');
assert(app.callbacks.undo(), 'Fixture: Undo ran.');
assert(s().style.font_size == 20, 'Undo puts the displays back.');
assert(window().peek == false and window().x == 640 and window().width == 1200,
    'Undo of Reset all puts the settings window back as it was.');
-- Another reset scope leaves the window to the window: its Undo keeps the window as it is now.
assert(app.callbacks.reset('appearance'), 'Fixture: the reset ran.');
window().peek = true; app.callbacks.editor_changed(true);
assert(app.callbacks.undo() and window().peek == true, 'Undo of another reset leaves the window navigation as it is.');
return true;
