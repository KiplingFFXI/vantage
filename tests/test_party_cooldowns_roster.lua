-- Party cooldowns read the party's jobs on their own (vantage.lua needs_party_roster), so with Party list buffs off a
-- member who changes job still loses that job's abilities and keeps the two-hour.
local store = require('core.store');
local self_id, ally = 1001, 1002;
local live = { valid = true, id = self_id, name = 'Tester', zone = 102, job = 1, level = 75, self_known = true, self_effects = {},
    party = { { id = ally, name = 'Rowan', scope = 'party', zone = 102, slot = 1 } }, entities = {} };
local ally_job, roster_reads = 1, 0;
package.loaded['core.client'] = {
    read = function() return store.copy(live); end,
    load = function() end, capabilities = function() return {}; end,
};
package.loaded['core.observer'] = { read = function(event) return event.observations or {}; end };
package.loaded['core.roster'] = {
    read = function()
        roster_reads = roster_reads + 1;
        return { valid = true, id = self_id, zone = 102, members = {
            { id = self_id, slot = 0, group = 1, active = true, job = 1 },
            { id = ally, slot = 1, group = 1, active = true, job = ally_job, subjob = 3 } } };
    end,
};
package.loaded['ui.hud'] = { draw = function() end, draw_notices = function() end, cancel_gesture = function() end };
package.loaded['ui.party_hud'] = { draw = function() return false, {}; end, cancel_layout_gesture = function() end };
package.loaded['ui.native_party_hud'] = { draw = function() return false, {}; end, cancel_layout_gesture = function() end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.now = 1; app.refresh(1);
local s = app.state.settings;
assert(not s.party_ui.enabled and not s.party_cooldowns.enabled and roster_reads == 0 and not app.state.roster_ready,
    'With nothing that needs it, the party list is not read');

s.party_cooldowns.enabled = true;
MOCK.now = 2; app.refresh(2);
assert(roster_reads == 1 and app.state.roster_ready, 'Party cooldowns on their own read the party list');
local function use(ability)
    MOCK.fire('packet_in', { id = 0x028, observations = { { kind = 'cooldown', entity_id = ally, ability = ability, entity_name = 'Rowan' } } });
end
use(31); use(16);
MOCK.now = 3; app.refresh(3);
local function abilities()
    local out = {};
    for _, entry in ipairs(app.state.view.member_cooldowns[ally] or {}) do out[entry.ability] = true; end
    return out;
end
local listed = abilities();
assert(listed[31] and listed[16], 'Berserk and Mighty Strikes count down for a Warrior');

ally_job = 3;
MOCK.now = 4; app.refresh(4);
listed = abilities();
assert(not listed[31] and listed[16], 'A Warrior who changed to White Mage keeps only the two-hour, with Party list buffs off');
