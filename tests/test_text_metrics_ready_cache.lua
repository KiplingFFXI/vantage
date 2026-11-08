-- A bitmap font's text token asks whether its countdown atlas is up only until it is: once a token was
-- measured with the atlas, later tokens of that assets generation reuse it, and a new generation asks again.
local generation, atlas, asked = 1, false, 0;
package.loaded['ui.client_assets'] = { generation = function() return generation; end, retry_pending = function() return false; end };
package.loaded['ui.fonts'] = {
    is_bitmap = function(font) return font == 'Original FFXI'; end,
    face = function(font) return font; end,
    measure = function() return 10, 10; end,
    countdown_renderer = function() asked = asked + 1; return atlas and {} or nil; end,
};
package.loaded['ui.text_metrics'] = nil;
local metrics = require('ui.text_metrics');
local first = metrics.token('Original FFXI', 14, 14);
assert(metrics.token('Original FFXI', 14, 14) == first and asked == 2, 'Fixture: before the atlas, each token asks again.');
atlas = true;
local ready = metrics.token('Original FFXI', 14, 14);
assert(ready ~= first, 'The atlas coming up gives the font a new token.');
asked = 0;
for _ = 1, 50 do assert(metrics.token('Original FFXI', 14, 14) == ready); end;
assert(asked == 0, 'Once measured with its atlas, the token is reused without asking again.');
generation = 2;
local after = metrics.token('Original FFXI', 14, 14);
assert(after ~= ready and asked == 1, 'A new assets generation asks again and makes a new token.');
atlas = false;generation = 3;
local lost = metrics.token('Original FFXI', 14, 14);
assert(lost ~= after and asked == 2, 'An atlas lost with a new generation is not taken for ready.');
asked = 0;
metrics.token('Agave', 14, 14);
assert(asked == 0, 'A TTF font never asks.');
