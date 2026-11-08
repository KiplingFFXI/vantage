-- Vantage's windows never dock (ImGuiWindowFlags_NoDocking). Every window Vantage opens carries the flag: the settings window, the edit mode bar and outlines, the timer
-- panels, the alert notices, the party cooldown list, the ready pulse, the Phantom Roll and pet displays, and the party
-- list buffs beside the game's list and in a panel of its own. An Ashita build without the constant reads it as 0, so
-- every window keeps its other flags.
local bit = require('bit');
local store, defaults, elements = require('core.store'), require('ui.defaults'), require('ui.elements');
local imgui = require('imgui');
assert(ImGuiWindowFlags_NoDocking == bit.lshift(1, 19), 'Fixture: Ashita\'s libs/imgui.lua names the flag.');
local seen = {};
local function collect()
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Begin' then
            local name = tostring(call[2]);
            assert(bit.band(call[4] or 0, ImGuiWindowFlags_NoDocking) ~= 0, 'This window never docks: ' .. name);
            seen[name] = true;
        end;
    end;
end;

-- 1. Through the addon: the settings window open over the displays' samples, then edit mode.
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 17, level = 75, self_known = true, self_effects = {},
    party = {}, entities = { [1001] = { id = 1001, index = 0x400, name = 'Tester', kind = 'player' } } };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
rawset(imgui, 'GetBackgroundDrawList', function() return imgui.GetWindowDrawList(); end);
rawset(imgui, 'GetForegroundDrawList', function() return imgui.GetWindowDrawList(); end);
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local s = app.state.settings;
s.rolls.enabled, s.rolls.preview, s.pet.enabled, s.pet.preview, s.window.open = true, true, true, true, true;
local function frame() MOCK.imgui_calls = {}; MOCK.frame(1 / 60); collect(); end;
frame(); frame();
local event = { command = '/vg edit' };
MOCK.fire('command', event);
assert(event.blocked, 'Fixture: /vg edit.');
frame(); frame();

-- 2. The displays with something to show: the party cooldown list, the ready pulse at its screen spot, the pet display
-- and the alert notices.
local hud, conditions = require('ui.hud'), require('core.conditions');
local gate = defaults.tidy(defaults.make());
gate.party_cooldowns.enabled, gate.party_cooldowns.list.enabled, gate.pet.enabled = true, true, true;
gate.ready_pulse.enabled, gate.ready_pulse.spot, gate.alerts.enabled, gate.alerts.muted = true, 'screen', true, false;
local pulses = require('core.ready_pulse').new();
pulses:test(gate, 500).test = false;
local live = { valid = true, rows = {}, context = { valid = true, id = 1001 },
    cooldowns = store.copy(require('core.party_cooldowns').samples(500)), pet = store.copy(require('core.pet').samples(500)),
    pulses = pulses.active, notices = { { visual = true, test = true, ends = 510, message = 'Haste wore off' } } };
conditions.update(gate, { valid = true, id = 1001, zone = 102, job = 3, level = 75, self_effects = {}, party = {},
    combat = false, entities = { [1001] = { id = 1001, index = 0x400 } } });
elements.frame();
MOCK.imgui_calls = {};
hud.draw(live, gate, 500.2, {});
collect();

-- 3. The party list buffs: groups 1 and 3 beside the game's party list, group 2 in a panel of its own.
local overlay, party_defaults, party_hud = require('ui.native_party_hud'), require('ui.party_defaults'), require('ui.party_hud');
local p = party_defaults.make();
p.enabled = true;
p.groups[2].native_detached = true;
local roster, subjects = party_hud.sample(18, 100);
local geometry = { available = true, groups = {} };
for group = 1, 3 do
    local rows = {};
    for _, member in ipairs(roster.members) do
        if member.group == group then
            rows[member.slot] = { x = 1000, y = 60 + (group - 1) * 180 + (member.slot % 6) * 22, width = 116, height = 22,
                slot = member.slot };
        end;
    end;
    geometry.groups[group] = { x = 1000, y = 60 + (group - 1) * 180, width = 116, height = 132, rows = rows };
end;
MOCK.screen = { 1600, 900 };
MOCK.imgui_calls = {};
overlay.draw(roster, subjects, p, 100, { native_geometry = geometry });
collect();

for _, name in ipairs({ 'Vantage##settings', 'Vantage edit mode##vantage_edit_bar', '##vantage_edit_rolls', '##vantage_rolls',
    '##vantage_pet', '##vantage_self_buffs', '##vantage_cooldowns', '##vantage_pulse', '##vantage_notices',
    '##vantage_native_1', '##vantage_native_2', '##vantage_native_3' }) do
    assert(seen[name], 'Fixture: this window was drawn: ' .. name);
end;

-- Without the constant, the windows keep their other flags.
local policy, kept = package.loaded['ui.frame_policy'], ImGuiWindowFlags_NoDocking;
ImGuiWindowFlags_NoDocking = nil;
package.loaded['ui.frame_policy'] = nil;
local plain = require('ui.frame_policy').overlay_flags();
package.loaded['ui.frame_policy'] = policy;
MOCK.imgui_calls = {};
require('ui.settings_window').draw(s, hud.sample(100), { now = function() return 100; end, save = function() return true; end,
    changed = function() end });
ImGuiWindowFlags_NoDocking = kept;
local window_flags;
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'Begin' and call[2] == 'Vantage##settings' then window_flags = call[4]; end;
end;
assert(plain == bit.band(policy.overlay_flags(), bit.bnot(kept)) and window_flags
    and bit.band(window_flags, ImGuiWindowFlags_NoSavedSettings) ~= 0 and bit.band(window_flags, kept) == 0,
    'Without the constant the windows open with their other flags.');
return 'Every Vantage window carries NoDocking, and a missing constant reads as 0';
