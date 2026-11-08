-- The party list strips through the real vantage.lua: what they are handed, when they step aside and how a failure is
-- reported. The game's own party list and its geometry are fixtures.
local store = require('core.store');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 1, job_name = 'WAR', self_known = true,
    self_effects = { { effect = 127, slot = 0 } }, party = {
        { id = 1002, name = 'Party', zone = 102, slot = 1, group = 1, scope = 'party', valid = true, revision = 1, effects = {} },
        { id = 1007, name = 'Alliance', zone = 102, slot = 6, group = 2, scope = 'alliance', valid = false, effects = {} },
        { id = 1013, name = 'Alliance 3', zone = 102, slot = 12, group = 3, scope = 'alliance', valid = false, effects = {} } },
    entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function(e) return e.observations or {}; end };
package.loaded['ui.hud'] = { draw = function() end, draw_notices = function() end, cancel_gesture = function() end };
package.loaded['ui.settings_window'] = { draw = function() end };
local roster = { valid = true, id = 1001, zone = 102, members = {} };
for _, identity in ipairs({ { 1001, 0 }, { 1002, 1 }, { 1007, 6 }, { 1013, 12 } }) do
    roster.members[#roster.members + 1] = { id = identity[1], slot = identity[2], group = math.floor(identity[2] / 6) + 1,
        name = 'Member ' .. identity[1], zone = 102, active = true, same_zone = true, available = true, known = true };
end;
package.loaded['core.roster'] = { read = function(_, s)
    local result = store.copy(roster); result.valid, result.in_event, result.map, result.hidden = s.valid, s.in_event, s.map, s.hidden;
    return result;
end };
local treasure = false;
package.loaded['core.native_party_ui'] = { treasure_open = function() return treasure; end,
    status = function() return { available = true }; end };
local drawn, fail, subjects = 0, false, nil;
package.loaded['ui.native_party_hud'] = {
    draw = function(_, given)
        drawn, subjects = drawn + 1, given;
        if fail then error('Fixture strip failure'); end;
        return false, {}, {};
    end,
    cancel_layout_gesture = function() end,
};
local app = dofile(ADDON_DIR .. '/vantage.lua');
local function command(text) local e = { command = text }; MOCK.fire('command', e); return e; end;
local function frame() MOCK.frame(0.2); end;
MOCK.fire('load'); app.refresh(0); frame();

-- The strips are handed the observed effects without changing what the tracker holds.
assert(subjects and subjects[1001].effects[1].kind == 'neutral' and app.state.view.rows[1].kind == 'other',
    'Presentation mapping does not mutate tracker metadata.');
assert(subjects[1001].complete and not subjects[1007].complete, 'Alliance identity alone cannot claim a complete effect set.');

-- The Treasure Pool draws each member's lot or pass inside the game's party windows, so the strips step aside while
-- it is open and come back when it closes. Neither changes a setting.
command('/vg party show'); frame();
local saved_before, before = store.copy(app.state.settings), drawn;
treasure = true; frame(); frame();
assert(drawn == before, 'The strips are not drawn while the Treasure Pool is open.');
assert(require('core.customization').equal(app.state.settings, saved_before), 'The Treasure Pool never edits saved options or positions.');
treasure = false; frame();
assert(drawn == before + 1, 'Closing the Treasure Pool brings the strips back.');
-- A sample shows whatever the game draws in its windows.
command('/vg party preview'); treasure = true; frame();
assert(drawn == before + 2, 'The sample strips draw while the Treasure Pool is open.');
treasure = false; command('/vg party live'); frame();

-- A strip failure is reported, and a later good frame draws again.
fail = true; frame();
assert(app.state.problem and app.state.problem:find('Fixture strip failure', 1, true), 'A strip failure is reported.');
local failed = drawn;
fail = false; frame();
assert(drawn > failed, 'A later successful frame recovers drawing.');
assert(#MOCK.commands == 0, 'The strips send no game commands.');
MOCK.fire('unload');
return true;
