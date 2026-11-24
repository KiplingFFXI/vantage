-- Reset this tab on Overhead icons' Size and place clears every head offset by name, as a fresh install has none, in the
-- same Undo step as the rest of the tab.
local h = require('panel_fixture')();
h.fresh(function(s) s.overhead.head.offsets = { Crab = 1, Fafnir = 0.5 }; s.overhead.size.base = 30; end);
h.on('overhead', 'place');
assert(h.says('Crab') and h.says('Fafnir'), 'Fixture: the head offsets are listed.');
h.draw('Reset this tab##frame');
h.draw();
local o = h.s.overhead;
assert(o.size.base == 22, 'Fixture: Reset this tab puts Icon size back: ' .. tostring(o.size.base));
assert(next(o.head.offsets) == nil, ('Reset this tab clears every head offset, but left Crab=%s and Fafnir=%s')
    :format(tostring(o.head.offsets.Crab), tostring(o.head.offsets.Fafnir)));
assert(#h.app.state.history == 1, 'One Undo step.');
h.draw('Undo');
h.draw();
o = h.s.overhead;
assert(o.head.offsets.Crab == 1 and o.head.offsets.Fafnir == 0.5 and o.size.base == 30, 'Undo brings them back.');
-- An offset's slider still sets its unit's offset.
h.slide('##frame_Offset in yalms', 2);
assert(h.s.overhead.head.offsets.Crab == 2 and h.s.overhead.head.offsets.Fafnir == 0.5, 'The slider sets the first unit listed: '
    .. tostring(h.s.overhead.head.offsets.Crab));
MOCK.fire('unload');
return 'ok';
