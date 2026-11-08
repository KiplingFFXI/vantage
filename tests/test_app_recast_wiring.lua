-- The recast tints, the ready pulse and the party cooldown watch through the real vantage.lua: each refresh marks the
-- recast rows from your status and MP, starts a pulse from a long recast's ready, reads every recast kind for a pulse
-- at its own screen spot, and hands each member's estimates and the watch's settings to the party list strips and the
-- estimates to the overhead blocks. The
-- recast reader and the game's party list are fixtures.
local store = require('core.store');
local SILENCE = 6;
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 4, job_name = 'BLM', self_known = true, mp = 10,
    self_effects = { { effect = SILENCE, slot = 0, deadline = 1000 } },
    party = { { id = 1002, name = 'Ally', zone = 102, slot = 1, group = 1, scope = 'party', valid = true, revision = 1, effects = {} } },
    entities = { [1002] = { id = 1002, name = 'Ally', kind = 'player' } } };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function(e) return e.observations or {}; end };
package.loaded['ui.hud'] = { draw = function() end, draw_notices = function() end, cancel_gesture = function() end };
package.loaded['ui.settings_window'] = { draw = function() end };
local roster = { valid = true, id = 1001, zone = 102, members = {} };
for _, identity in ipairs({ { 1001, 0, 4 }, { 1002, 1, 3 } }) do
    roster.members[#roster.members + 1] = { id = identity[1], slot = identity[2], group = 1, job = identity[3], subjob = 0,
        name = identity[1] == 1002 and 'Ally' or 'Tester', zone = 102, active = true, same_zone = true, available = true, known = true };
end;
package.loaded['core.roster'] = { read = function(_, s)
    local result = store.copy(roster); result.valid, result.in_event, result.map, result.hidden = s.valid, s.in_event, s.map, s.hidden;
    return result;
end };
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, status = function() return { available = true }; end };
local strip_subjects, strip_options;
package.loaded['ui.native_party_hud'] = {
    draw = function(_, subjects, _, _, options) strip_subjects, strip_options = subjects, options; return false, {}, {}; end,
    cancel_layout_gesture = function() end,
};
-- The recast reader: a Fire recast row (its era cost is 24 MP), and the events the next refresh drains.
local fire = { key = 'recast:1001:spell:144', instance = 1, domain = 'recast', kind = 'spell', group = 'spell_recasts', effect = 10144,
    recast_id = 144, spell_id = 144, name = 'Fire', scope = 'self', entity_id = 1001, remaining = 20, total = 180, deadline = 30, start = -150 };
local asked, pending = nil, {};
package.loaded['core.recasts'] = { catalog = function() return {}; end, preview_icon = function() return nil; end, new = function() return {
    reset = function() end, update = function(_, _, _, options) asked = options; end, project = function() end,
    view = function() return { rows = { fire }, version = 1 }; end,
    drain_events = function() local events = pending; pending = {}; return events; end,
}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local s = app.state.settings;
-- The tints, the pulse and the watch are off at first, so they are turned on for the refreshes below.
s.recast_tints.mp, s.recast_tints.spell_lock, s.recast_tints.ability_lock = true, true, true;
s.ready_pulse.enabled, s.party_cooldowns.enabled = true, true;
app.refresh(0.1);

-- The refresh marks the recast rows it shows: Silenced, with 10 MP for Fire's 24.
local row;
for _, shown in ipairs(app.state.view.rows) do if shown.key == fire.key then row = shown; end end
assert(row and row.locked and row.lock_deadline == 1000 and row.tint_mp, 'The refresh locks and tints the spell row it shows.');
snapshot.self_effects, snapshot.mp = {}, 500;
app.refresh(0.2);
assert(not fire.locked and not fire.tint_mp, 'With the Silence gone and MP enough, the next refresh clears them.');

-- A long recast's ready starts a pulse.
local ready = store.copy(fire);
ready.kind, ready.category, ready.remaining, ready.time = 'ready', 'spell', 0, 0.4;
pending = { ready };
app.refresh(0.4);
assert(app.state.view.pulses and #app.state.view.pulses == 1 and app.state.view.pulses[1].effect == 10144,
    'The ready of a 180 s recast starts a pulse at the refresh.');

-- A pulse at its own screen spot reads every recast kind, whatever the panels show; on rows it reads only what the
-- panels and alerts ask for.
s.alerts.enabled, s.window.open = false, false;
for key in pairs(require('ui.defaults').recast_panels) do s.panels[key].enabled = false; end
app.refresh(0.6);
assert(asked and not asked.enabled, 'With no recast panel and the pulse on rows, no recast is read.');
s.ready_pulse.spot = 'screen';
app.refresh(0.8);
assert(asked.enabled and asked.spells and asked.abilities and asked.items, 'A pulse at its screen spot reads spells, abilities and items.');

-- A member's use reaches their strip at the next refresh, and the strips get the watch's settings.
MOCK.fire('packet_in', { id = 0x028, observations = { { kind = 'cooldown', entity_id = 1002, ability = 18, entity_name = 'Ally', scope = 'party' } } });
app.refresh(1);
local subject = app.state.party_subjects[1002];
assert(subject and subject.cooldowns and subject.cooldowns[1].ability == 18, 'The member\'s subject carries their Benediction.');
assert(app.state.view.member_cooldowns and app.state.view.member_cooldowns[1002] == subject.cooldowns,
    'The view tells the overhead blocks who has estimates.');
MOCK.frame(0.2);
assert(strip_subjects and strip_subjects[1002] and strip_subjects[1002].cooldowns, 'The strips are handed it.');
assert(strip_options and strip_options.cooldowns == s.party_cooldowns, 'and the party cooldown settings with it.');
assert(#MOCK.commands == 0, 'Nothing here sends a game command.');
MOCK.fire('unload');
return 'The refresh marks tints, starts pulses, reads recasts for the screen spot and hands the strips their estimates';
