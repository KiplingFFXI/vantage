-- The Profiles summary re-reads profiles.json every 2 seconds while it is shown, and at once after your own changes,
-- but works out whether the active profile is Modified again only when the file text, the active profile or the
-- settings changed.
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
local function command(text) local event = { command = text }; MOCK.fire('command', event); end;
MOCK.fire('load'); app.refresh(0);
app.state.dirty = true; assert(app.callbacks.save(), 'Fixture: the settings are on disk.');
-- The full check copies and tidies the settings; count those.
local defaults = require('ui.defaults');
local tidy, checks = defaults.tidy, 0;
defaults.tidy = function(...) checks = checks + 1; return tidy(...); end;
local function summary() app.state.profile_summary_cache = nil; return app.callbacks.profile_summary(); end;
local function counted() local before = checks; local value = summary(); return value, checks - before; end;

assert(app.callbacks.profile_save('Bench', false) and app.state.settings.active_profile == 'Bench', 'Fixture: Bench is active.');
local value, work = counted();
assert(value.status.name == 'Bench' and value.status.modified == false and work > 0, 'Fixture: the first summary checks Bench.');
for _ = 1, 4 do
    value, work = counted();
    assert(work == 0 and value.status.modified == false, 'With nothing changed the summary keeps its Modified check.');
end;
-- A change to the settings: checked again, and Modified.
app.callbacks.changed('before', 'Font'); app.state.settings.style.font_size = 22; app.callbacks.changed('after');
value, work = counted();
assert(work > 0 and value.status.modified == true, 'A settings change is checked again and reads Modified.');
value, work = counted();
assert(work == 0 and value.status.modified == true, 'Then it is kept.');
-- Undo puts back the settings: checked again, not Modified.
assert(app.callbacks.save() and app.callbacks.undo(), 'Fixture: Undo ran.');
value, work = counted();
assert(work > 0 and value.status.modified == false, 'Undo is checked again.');
-- Another character overwrites Bench in profiles.json: the file text changed.
local profiles_path = app.state.path:gsub('Tester_1001/settings.json$', '') .. 'profiles.json';
local data = assert(store.read(profiles_path), 'Fixture: the profile file reads.');
data.Bench.style.font_size = 30;
assert(store.write(profiles_path, data), 'Fixture: the profile file changed.');
value, work = counted();
assert(work > 0 and value.status.modified == true, 'A changed profile file is checked again.');
-- Another active profile: checked again.
assert(app.callbacks.profile_save('Second', false) and app.state.settings.active_profile == 'Second', 'Fixture: Second is active.');
value, work = counted();
assert(work > 0 and value.status.name == 'Second' and value.status.modified == false, 'A new active profile is checked.');
-- A drag changes the settings every frame: the counted change still reaches the summary.
app.state.mouse_held = true;
app.callbacks.changed('before', 'Drag'); app.state.settings.panels.self_buffs.x = app.state.settings.panels.self_buffs.x + 5;
app.callbacks.changed('after');
app.state.mouse_held = false;
value, work = counted();
assert(work > 0 and value.status.modified == true, 'A change made during a drag is checked.');
-- The shown summary is the 2 second one, refreshed from the kept check.
MOCK.now = MOCK.now + 3;
local shown = app.callbacks.profile_summary();
assert(shown.status.modified == true, 'The page shows the kept check.');
defaults.tidy = tidy;
return true;
