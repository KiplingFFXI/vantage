-- Reset all settings says Undo recovers it. It is an Undo step for the settings window too: Undo puts back Hold Shift
-- to see through this window and the window's place and size. Moving between pages and sections makes no Undo step.
-- /vg reset navigation is gone: it is refused like any other word and changes nothing.
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {}, party = {}, entities = {} };
require('app_fixture')(snapshot);
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
local refused, why = app.callbacks.reset('navigation');
assert(refused == false and tostring(why):find('^That reset scope was not found%.'), 'Reset navigation is refused: ' .. tostring(why));
assert(window().peek == false and #app.state.history == 1, 'And it changes nothing and makes no Undo step.');

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
