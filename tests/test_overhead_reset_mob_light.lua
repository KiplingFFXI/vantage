-- Reset this tab on the Show tab of Overhead icons puts back the rows for the kind picked under Change the settings for.
-- Light up buffs you can remove is a Mobs row, so only a reset with Mobs picked puts it back, and a reset with another
-- kind picked leaves it as you set it.
local h = require('panel_fixture')();
local page = require('ui.overhead_settings');
local LIGHT = 'Light up buffs you can remove##frame';

local function start()
    h.fresh(function(s) s.overhead.enabled = true; end);
    page._selection.kind = 'mob';
    h.on('overhead', 'show');
    assert(h.called('Checkbox', LIGHT), 'Mobs shows the light.');
    h.draw(LIGHT);
    assert(h.s.overhead.dispel_light == false, 'The tick turns it off.');
end;

-- With Mobs picked the reset puts the light and the rows every kind shares back, in one step.
start();
h.s.overhead.max_units = 5; h.s.overhead.types.mob.layout = 'split'; h.bump(); h.draw();
h.draw('Reset this tab##frame');
h.draw();
local o = h.s.overhead;
assert(o.dispel_light == true and o.max_units == 10 and o.types.mob.layout == 'single', 'Mobs picked: the light, the shared rows and Mobs\' layout go back.');
assert(h.app.state.history[#h.app.state.history].label == 'Reset this tab', 'It is one step named Reset this tab.');
assert(h.app.callbacks.undo() and h.app.state.settings.overhead.dispel_light == false, 'Undo brings the light back off.');

-- With any other kind picked, that kind's rows and the shared ones go back, and the Mobs light and layout stay.
local said = {};
for _, entry in ipairs({ { 'party', 'Party' }, { 'alliance', 'Alliance' }, { 'other', 'Other players' }, { 'pet', 'Your pet' },
    { 'other_pet', 'Other players\' pets' }, { 'self', 'You' } }) do
    local kind = entry[1];
    start();
    h.s.overhead.types.mob.layout = 'split'; h.bump(); h.draw();
    h.draw(entry[2] .. '##frame_Change the settings for_' .. kind);
    h.draw();
    assert(page._selection.kind == kind, kind .. ' is picked.');
    assert(not h.called('Checkbox', LIGHT), kind .. ' has no Mobs light row.');
    h.s.overhead.types[kind].layout = 'lines'; h.s.overhead.max_units = 5; h.bump(); h.draw();
    local steps = #h.app.state.history;
    h.draw('Reset this tab##frame');
    h.draw();
    o = h.s.overhead;
    assert(o.types[kind].layout == 'single' and o.max_units == 10, kind .. ' picked: its own layout and the shared rows go back.');
    assert(#h.app.state.history == steps + 1 and h.app.state.history[#h.app.state.history].label == 'Reset this tab', kind .. ': one step.');
    if o.dispel_light ~= false or o.types.mob.layout ~= 'split' then
        said[#said + 1] = ('%s: light %s, mob layout %s'):format(kind, tostring(o.dispel_light), tostring(o.types.mob.layout));
    end;
end;
page._selection.kind = 'mob';
MOCK.fire('unload');
assert(#said == 0, 'A reset with another kind picked changed the Mobs rows: ' .. table.concat(said, ' | '));
return 'Reset this tab leaves the Mobs light to Mobs';
