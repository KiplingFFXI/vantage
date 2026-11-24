-- Reset this tab on a timer or recast panel's Look puts the Heading typed there back, with the rest of Look. Copy this tab
-- to still leaves each panel its own heading (tests/test_copy_tab.lua).
local h = require('panel_fixture')();
local names = require('ui.defaults').panel_names;

for _, case in ipairs({ { 'self_buffs', 'separate' }, { 'spell_recasts', 'separate' }, { 'recasts', 'combined' } }) do
    local id, mode = case[1], case[2];
    h.fresh(function(s) s.recast_display = mode; s.panels[id].mode = 'bars'; end);
    h.on(id, 'look');
    h.type('##frame_Heading', 'Mine');
    h.draw('Shaded bars##frame');
    h.draw();
    local p = h.s.panels[id];
    assert(p.title == 'Mine' and p.gradient == true, 'Fixture: ' .. id .. ' has a heading typed and Shaded bars on.');
    h.draw('Reset this tab##frame');
    h.draw();
    p = h.s.panels[id];
    assert(p.gradient == false, 'Fixture: Reset this tab ran on ' .. id .. '.');
    assert(p.title == names[id], ('Reset this tab on %s Look put Shaded bars back but left the Heading as %s (fresh: %s)'):format(id, tostring(p.title), tostring(names[id])));
    h.draw('Undo');
    h.draw();
    assert(h.s.panels[id].title == 'Mine' and h.s.panels[id].gradient == true, 'Undo brings the heading back with the rest.');
end;
MOCK.fire('unload');
return 'Reset this tab on Look puts the heading back';
