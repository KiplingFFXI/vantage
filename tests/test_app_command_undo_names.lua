-- /vg mute, /vg lock, /vg unlock, /vg watch, /vg unwatch and /vg skin name their Undo steps, as the main page's buttons
-- and lists name the same changes. Watch and Stop watching are named in the callbacks, which Watch my target and Stop
-- watching call too.
local SNAP = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 1, self_known = true, self_effects = {}, party = {}, entities = {},
    target = { id = 16781313, name = 'Crab', index = 1, kind = 'monster' } };
require('app_fixture')(SNAP);
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, update = function() end,
    status = function() return { active = false }; end, restore = function() return true; end, suspend = function() return true; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
local function command(text) local event = { command = text }; MOCK.fire('command', event); assert(event.blocked); end;
MOCK.fire('load'); app.refresh(0);
for _ = 1, 3 do MOCK.frame(.11); end;

-- One step, by the name of what it did. Undo hands it to Redo with that name.
local function named(change, label)
    local steps = app.callbacks.history_status().undo;
    change();
    local status = app.callbacks.history_status();
    assert(status.undo == math.min(steps + 1, 20) and status.undo_label == label, 'Undo says ' .. label .. ': ' .. tostring(status.undo_label));
    assert(app.callbacks.undo() and app.callbacks.history_status().redo_label == label, 'Redo says ' .. label .. ' after it.');
    assert(app.callbacks.redo(), 'Fixture: Redo puts it back.');
end;
named(function() command('/vg mute'); end, 'Mute alerts');
assert(app.state.settings.alerts.muted, 'Fixture: the alerts are muted.');
named(function() command('/vg mute'); end, 'Unmute alerts');
assert(not app.state.settings.alerts.muted, 'Fixture: the alerts are unmuted.');
named(function() command('/vg unlock'); end, 'Unlock all');
assert(not app.state.settings.rolls.locked, 'Fixture: every display is unlocked.');
named(function() command('/vg lock'); end, 'Lock all');
assert(app.state.settings.rolls.locked, 'Fixture: every display is locked.');
named(function() command('/vg watch'); end, 'Watch');
assert(app.state.settings.watch_ids[1] == 16781313, 'Fixture: the target is watched.');
named(function() command('/vg unwatch'); end, 'Stop watching');
assert(#app.state.settings.watch_ids == 0, 'Fixture: the target is not watched.');
named(function() assert(app.callbacks.watch(4242)); end, 'Watch');
named(function() assert(app.callbacks.unwatch(4242)); end, 'Stop watching');
-- /vg skin names a skin as the main page's list does, so the Minimal skin is Frameless however it is typed.
named(function() command('/vg skin Frameless'); end, 'Skin: Frameless');
assert(app.state.settings.style.minimal, 'Fixture: the Frameless skin is on.');
command('/vg skin Mint');
named(function() command('/vg skin minimal'); end, 'Skin: Frameless');
assert(app.state.settings.style.minimal, 'Fixture: the Frameless skin is on again.');
MOCK.fire('unload');
return 'The commands name their Undo steps';
