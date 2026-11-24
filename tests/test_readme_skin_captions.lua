-- The README's skins picture (tests/preview/readme/skins.lua) captions each skin with the name the Skin list and
-- /vg skin give it, so the Minimal theme shows as Frameless there too.
local C = require('preview.readme.common');
local appearance, theme = require('ui.appearance'), require('ui.theme');
local draw = require('preview.readme.skins');
local captions = {};
C.caption = function(_, _, _, text) captions[#captions + 1] = text; end;
C.draw = function() end;
draw();

assert(#captions == #theme.names, 'The picture has one caption for each theme: ' .. #captions);
local shown = {};
for index, name in ipairs(theme.names) do
    shown[captions[index]] = true;
    assert(captions[index] == appearance.labels[name],
        'The ' .. name .. ' skin is captioned ' .. tostring(captions[index]) .. ', not ' .. appearance.labels[name] .. '.');
end;
assert(shown.Frameless and not shown.Minimal, 'The Minimal theme is captioned Frameless.');
