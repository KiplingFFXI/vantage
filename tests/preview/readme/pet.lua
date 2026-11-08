-- The pet display for two jobs: a Beastmaster's jug pet with the time until it leaves, and a Puppetmaster's automaton
-- with the maneuvers up and the overload risk.
local C = require('preview.readme.common');
local pet = require('core.pet');
require('ui.icons').prepare();
require('ui.recast_icons').prepare();
C.resources();
local sets = {};
for index, spec in ipairs({ { 9, 'SheepFamiliar', false }, { 18, 'Automaton', true } }) do
    local s = C.settings();
    local config = s.pet;
    config.enabled, config.x, config.y, config.width = true, 16 + (index - 1) * 296, 16, 280;
    local view = C.view({});
    -- The display's own samples for that job, shown as a live pet.
    local shown = pet.samples(C.now, spec[1]);
    shown.name, shown.has_mp = spec[2], spec[3];
    view.pet = shown;
    sets[index] = { settings = s, view = view };
end;
return function() C.draw(sets); end;
