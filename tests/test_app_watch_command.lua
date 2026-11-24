-- /vg watch with no ID takes an enemy target, as Watch my target does. A player target, you or a party member, is
-- refused with the button's line and changes nothing. A typed ID still watches anyone, and /vg unwatch still takes a
-- watched player off while they're targeted.
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 1, self_known = true,
    self_effects = { { effect = 33, slot = 0, deadline = 100, raw_timer = 6000 } }, party = {}, entities = {} };
require('app_fixture')(snapshot);
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, update = function() end,
    status = function() return { active = false }; end, restore = function() return true; end, suspend = function() return true; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
local function command(text) local event = { command = text }; MOCK.fire('command', event); assert(event.blocked); end;
MOCK.fire('load'); app.refresh(0);
assert(not app.state.settings.panels.watch.enabled, 'Fixture: Watched enemy timers starts off.');

for _, target in ipairs({ { id = 1001, name = 'Tester', index = 1, kind = 'player' }, { id = 1002, name = 'Member', index = 2, kind = 'player' } }) do
    snapshot.target = target;
    app.refresh(1);
    local printed, steps = #MOCK.printed, app.callbacks.history_status().undo;
    command('/vg watch');
    local s = app.state.settings;
    assert(#s.watch_ids == 0 and not s.panels.watch.enabled and app.callbacks.history_status().undo == steps,
        '/vg watch with ' .. target.name .. ' targeted watches nothing and turns nothing on.');
    assert(#MOCK.printed == printed + 1 and MOCK.printed[#MOCK.printed]:find('Target an enemy first.', 1, true),
        'It says so with the line Watch my target uses: ' .. tostring(MOCK.printed[#MOCK.printed]));
end;

-- A typed ID goes by that ID alone, and the player it names can be taken off with them targeted.
command('/vg watch 1002');
assert(app.state.settings.watch_ids[1] == 1002 and app.state.settings.panels.watch.enabled, 'A typed ID watches a player.');
command('/vg unwatch');
assert(#app.state.settings.watch_ids == 0, '/vg unwatch takes the targeted player off.');

-- An enemy target is watched as before.
snapshot.target = { id = 16781313, name = 'Crab', index = 3, kind = 'monster' };
app.refresh(2);
command('/vg watch');
assert(app.state.settings.watch_ids[1] == 16781313, 'An enemy target is watched.');
MOCK.fire('unload');
return '/vg watch with no ID takes an enemy target';
