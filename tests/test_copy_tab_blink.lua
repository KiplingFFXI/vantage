-- Seconds left on Look sets when a row blinks too, so Copy this tab to gives the other panel both, and it blinks where
-- the panel it was copied from does.
local h = require('panel_fixture')();
h.fresh(function(s)
    s.panels.self_buffs.warning_seconds, s.panels.self_buffs.blink_seconds = 20, 20;
    s.panels.self_debuffs.warning_seconds, s.panels.self_debuffs.blink_seconds = 45, 45;
end);
h.on('self_buffs', 'look');
h.pick('##frame_Copy this tab to', 'Self debuffs##frame_copy_self_debuffs');
local into = h.s.panels.self_debuffs;
assert(into.warning_seconds == 20, 'Fixture: the copy ran: ' .. tostring(into.warning_seconds));
assert(into.blink_seconds == 20, 'Copy this tab to left the other panel blinking at ' .. tostring(into.blink_seconds) .. ' while its Seconds left is 20.');
MOCK.fire('unload');
return 'ok';
