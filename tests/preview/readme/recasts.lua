-- Recasts two ways: spells and abilities in panels of their own, and the same recasts in one combined panel.
local C = require('preview.readme.common');
require('ui.icons').prepare();
require('ui.recast_icons').prepare();
local rows = {
    C.recast('spell', 54, 21, 30),
    C.recast('spell', 53, 12, 20),
    C.recast('spell', 109, 7, 18),
    C.recast('spell', 57, 16, 20),
    C.recast('ability', 20, 4320, 7200),
    C.recast('ability', 83, 432, 600),
    C.recast('ability', 74, 181, 600),
};
local separate = C.settings();
separate.recast_display = 'separate';
for key, x in pairs({ spell_recasts = 16, ability_recasts = 282 }) do
    local p = separate.panels[key];
    p.enabled, p.x, p.y, p.width = true, x, 40, 250;
end;
local combined = C.settings();
combined.recast_display = 'combined';
local p = combined.panels.recasts;
p.enabled, p.x, p.y, p.width = true, 564, 40, 250;
local sets = { { settings = separate, view = C.view(rows) }, { settings = combined, view = C.view(rows) } };
return function()
    C.caption(1, 16, 8, 'Separate panels');
    C.caption(2, 564, 8, 'Combined');
    C.draw(sets);
end;
