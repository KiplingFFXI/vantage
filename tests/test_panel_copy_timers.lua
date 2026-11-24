-- Copy shown timers and Copy timer details sit on a timer panel's Show tab and on Recasts' Show tab, and nowhere else.
-- Each copies that panel's timers, the second with their details, and a line says it is done. Neither is a setting.
local h = require('panel_fixture')();
local custom = require('core.customization');
local copied;
h.app.callbacks.copy_shown = function(panel, details) copied = { panel, details }; return true; end;
local SHOWN, DETAILS = 'Copy shown timers##frame', 'Copy timer details##frame';
h.fresh();
local before = custom.history_value(h.s);
for _, id in ipairs({ 'self_buffs', 'target', 'spell_recasts' }) do
    h.on(id, 'show');
    assert(h.called('Button', SHOWN) and h.called('Button', DETAILS), id .. '\'s Show tab has both.');
    for _, tab in ipairs({ 'place', 'look', 'filters', 'when' }) do
        h.on(id, tab);
        if h.panels.context():sub(-#tab - 1) == '/' .. tab then
            assert(not h.called('Button', SHOWN), id .. '\'s ' .. tab .. ' tab has neither.');
        end;
    end;
end;
h.on('self_buffs', 'show');
copied = nil;
h.draw(SHOWN);
assert(copied and copied[1] == 'self_buffs' and copied[2] == false, 'Copy shown timers copies the panel\'s timers.');
h.draw();
assert(h.says('Copied to the clipboard.'), 'A line says it is done.');
copied = nil;
h.draw(DETAILS);
assert(copied and copied[1] == 'self_buffs' and copied[2] == true, 'Copy timer details copies them with their details.');
assert(custom.equal(custom.history_value(h.s), before) and #h.app.state.history == 0, 'Neither is a setting or an Undo step.');
-- A copy that fails says nothing done.
h.app.callbacks.copy_shown = function() return false, 'Nothing to copy.'; end;
h.on('self_buffs', 'show');
h.draw(SHOWN);
h.draw();
assert(not h.says('Copied to the clipboard.'), 'A copy that fails doesn\'t say it is done.');
-- The other displays have neither.
for _, id in ipairs({ 'party_ui', 'overhead', 'pet', 'rolls', 'notices' }) do
    h.on(id, 'show');
    assert(not h.called('Button', SHOWN), id .. ' has no copy buttons.');
end;
MOCK.fire('unload');
return 'Copy shown timers and Copy timer details are on the timer panels\' Show tabs';
