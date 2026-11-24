-- When to show: the levels go to Phoenix's cap of 75, where 75 leaves no top, and the Pet display has no Pet row, as it
-- shows only with a pet out.
local conditions = require('core.conditions');
local h = require('panel_fixture')();
h.fresh();
h.on('self_buffs', 'when');
local function kept() return h.s.panels.self_buffs.conditions; end;
local function top(label)
    local call = h.calls('SliderFloat', label)[1];
    return call and call[5];
end;
assert(top('##frame_From_min') == 75 and top('##frame_To_max') == 75, 'Both levels go up to 75.');
h.slide('##frame_To_max', 60);
assert(kept().level_max == 60 and conditions.any(kept()), 'A top under 75 is kept.');
h.slide('##frame_To_max', 75);
assert(kept().level_max == 99 and not conditions.any(kept()), '75 leaves no top, as a fresh condition has.');
h.slide('##frame_From_min', 30);
local words = table.concat(conditions.describe(kept()), ' ');
assert(words == 'Level 30 and up.', 'No top reads as and up: ' .. words);
h.slide('##frame_To_max', 20);
assert(kept().level_min == 20 and kept().level_max == 20, 'A top under the lowest level takes the lowest down with it.');
h.slide('##frame_From_min', 75);
assert(kept().level_min == 75 and kept().level_max == 99, 'From 75 leaves no top.');

local EITHER = 'Either##frame_Pet_pet_any';
assert(h.called('RadioButton', EITHER), 'Another display has the Pet row.');
h.on('pet', 'when');
assert(h.called('SliderFloat', '##frame_To_max') and not h.called('RadioButton', EITHER), 'The Pet display has no Pet row.');
h.s.pet.conditions.pet = 'no';
h.draw();
assert(h.called('RadioButton', EITHER), 'With one saved before, it has the row to take it off.');
MOCK.fire('unload');
return 'When to show levels end at 75 and the Pet display has no Pet row';
