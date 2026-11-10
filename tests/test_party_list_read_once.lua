-- A refresh reads the game's party list once. The read for a display that moves with it is the one the strips draw
-- beside, so the strips' draw after the refresh reads nothing more.
local store = require('core.store');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 1, job_name = 'WAR', self_known = true,
    self_effects = {}, party = { { id = 1002, name = 'Party', zone = 102, slot = 1, group = 1, scope = 'party', valid = true,
        revision = 1, effects = {} } }, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function(e) return e.observations or {}; end };
package.loaded['ui.hud'] = { draw = function() end, draw_notices = function() end, cancel_gesture = function() end };
package.loaded['ui.settings_window'] = { draw = function() end };
local roster = { valid = true, id = 1001, zone = 102, members = {} };
for slot, id in ipairs({ 1001, 1002 }) do
    roster.members[slot] = { id = id, slot = slot - 1, group = 1, name = 'Member ' .. id, zone = 102, active = true,
        same_zone = true, available = true, known = true };
end;
package.loaded['core.roster'] = { read = function(_, s)
    local result = store.copy(roster); result.valid = s.valid;
    return result;
end };
local game = { available = true, groups = { { x = 1700, y = 950, width = 200, height = 40, row_height = 20, rows = {
    [0] = { x = 1700, y = 950, width = 200, height = 20, slot = 0 }, [1] = { x = 1700, y = 970, width = 200, height = 20, slot = 1 },
} } } };
local reads, rosters = 0, {};
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end,
    status = function() return { available = true }; end,
    geometry = function(given) reads, rosters[given] = reads + 1, true; return game; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local s = app.state.settings;
s.party_ui.enabled, s.alerts.notice_anchor.to = true, 'party';
for _ = 1, 6 do MOCK.frame(0.2); end
local refreshed = 0;
for _ in pairs(rosters) do refreshed = refreshed + 1; end
assert(refreshed >= 5 and require('ui.elements').party_list == game.groups[1], 'Fixture: each refresh reads the party list for the alerts: ' .. refreshed);
assert(reads == refreshed, 'and the strips draw beside that read, with no second: ' .. reads .. ' reads, ' .. refreshed .. ' refreshes.');
