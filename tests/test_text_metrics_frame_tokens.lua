-- During one Present a font token is worked out once per font, size, base size and frame font. No token is
-- kept for the next Present, and outside a Present every call works it out again. The tables the tokens are kept in
-- stay, so a Present makes nothing for the fonts and sizes asked for before.
local metrics, fonts = require('ui.text_metrics'), require('ui.fonts');
local imgui = require('imgui');
local faces, face = 0, fonts.face;
fonts.face = function(...) faces = faces + 1; return face(...); end;

-- The app opens a frame of tokens around each Present, and closes it even when the Present fails.
local opened, closed, begin, finish = 0, 0, metrics.begin_frame, metrics.end_frame;
metrics.begin_frame = function() opened = opened + 1; return begin(); end;
metrics.end_frame = function() closed = closed + 1; return finish(); end;
dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load');
local hud = require('ui.hud');
-- The panels draw inside the Present.
local draw, inside, fail = hud.draw, nil, false;
hud.draw = function(...)
    if inside == nil then
        faces = 0;
        metrics.token('Agave', 14.25); metrics.token('Agave', 14.25); metrics.token('Agave', 14.25);
        inside = faces;
        if fail then error('Present fixture', 0); end;
    end;
    return draw(...);
end;
MOCK.fire('d3d_present');
assert(opened == 1 and closed == 1 and inside == 1, 'A Present works each token out once.');
faces = 0;
metrics.token('Agave', 14.25); metrics.token('Agave', 14.25);
assert(faces == 2, 'After the Present every token is worked out again.');
fail, inside = true, nil;
MOCK.fire('d3d_present');
faces = 0;
metrics.token('Agave', 14.25); metrics.token('Agave', 14.25);
assert(opened == 2 and closed == 2 and inside == 1 and faces == 2, 'A failed Present still closes its frame of tokens.');
hud.draw = draw;

local outside = metrics.token('Agave', 14);
metrics.begin_frame();
faces = 0;
local first, same = metrics.token('Agave', 14), true;
for _ = 1, 20 do same = same and metrics.token('Agave', 14) == first; end;
assert(same and first == outside and faces == 1, 'A Present works a token out once and gives the token it had.');
faces = 0;
local bigger, based = metrics.token('Agave', 16), metrics.token('Agave', 14, 16);
assert(faces == 2 and bigger ~= first and based ~= first, 'Sizes and base sizes each keep their own token.');
assert(metrics.token('Agave', 14, 14) == first and faces == 2, 'A base size equal to the size is the same token.');
-- The party can draw in Original FFXI at the size a target or menu text uses in Agave.
faces = 0;
local client = metrics.token('Original FFXI', 14);
assert(client ~= first and metrics.token('Original FFXI', 14) == client and metrics.token('Agave', 14) == first and faces == 1,
    'Each font keeps its own token at the same size.');
-- The next Present starts by forgetting this one's tokens.
local calc = imgui.CalcTextSize;
imgui.CalcTextSize = function(text) return #tostring(text) * 9, 18; end;
metrics.begin_frame();
local changed = metrics.token('Agave', 14);
assert(changed ~= first and metrics.token('Agave', 14) == changed, 'The next Present starts again from the current measure.');
metrics.end_frame();
imgui.CalcTextSize = calc;

-- Once its fonts and sizes were asked for, a Present makes nothing for its tokens. Measured with the collector stopped
-- and the compiler off, as the draw allocation tests measure.
local function present()
    metrics.begin_frame();
    metrics.token('Agave', 14); metrics.token('Agave', 16); metrics.token('Agave', 14, 16); metrics.token('Agave', 14);
    metrics.token('Original FFXI', 14);
    metrics.end_frame();
end;
local function measure(count, leak)
    jit.off(); jit.flush();
    for _ = 1, 10 do present(); end;
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    local before, made = collectgarbage('count'), nil;
    for i = 1, count do
        present();
        if leak and i % 6 == 0 then made = {}; end;
    end;
    local each = (collectgarbage('count') - before) / count;
    collectgarbage('restart');
    jit.on();
    return each, made;
end;
local each = measure(600);
assert(each < 0.002, ('A Present makes %.4f KB for tokens it asked for before; nothing expected'):format(each));
local leaked, made = measure(600, true);
assert(leaked >= 0.002 and made, ('A table made every sixth Present shows as %.4f KB a Present'):format(leaked));
return 'Font tokens kept for one Present';
