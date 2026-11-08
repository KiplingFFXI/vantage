local theme = require('ui.party_theme');
local common = require('ui.theme');
local defaults = require('ui.party_defaults');
local store = require('core.store');
local config = defaults.make();
local plain = { theme = 'Original FFXI', font = 'Original FFXI', font_size = 14 };
local global = { font = 'Consolas', font_size = 20, scale = 1, minimal = true };
local before = store.encode(plain);
local global_before = store.encode(global);
local look = theme.resolve(plain, global);
assert(look.theme == 'Original FFXI' and look.font == 'Original FFXI' and look.font_size == 14);
assert(look.background and look.border and not look.minimal, 'A look takes Minimal only from its own style.');
assert(store.encode(plain) == before and store.encode(global) == global_before);
assert(#theme.names == 9 and #theme.color_keys == 4);
for _, name in ipairs(theme.names) do
    local colors, original = theme.colors(name, 1), common.colors(name);
    assert(colors.background[1] == original.background_color[1] and colors.text[2] == original.text_color[2]);
    for _, key in ipairs(theme.color_keys) do
        assert(type(colors[key]) == 'table' and #colors[key] == 4);
        for i = 1, 4 do assert(colors[key][i] >= 0 and colors[key][i] <= 1); end
    end
end

-- The party's own style is its icons and opacity: a saved skin and colors go as it is tidied.
local saved = defaults.make();
saved.style.theme, saved.style.colors = 'Original FFXI', { text = { 0.1, 0.2, 0.3, 0.4 } };
saved = defaults.tidy(saved);
assert(saved.style.theme == nil and saved.style.colors == nil, 'The party style keeps only its icons and opacity.');
-- Every exposed color survives sanitation, and a look holds its own copies.
local colored = { colors = {} };
for _, key in ipairs(theme.color_keys) do colored.colors[key] = { 0.1, 0.2, 0.3, 0.4 }; end
look = theme.resolve(colored, global);
for _, key in ipairs(theme.color_keys) do
    assert(look.colors[key][1] == 0.1);
    assert(look[key .. '_color'] == look.colors[key]);
    assert(look.colors[key] ~= colored.colors[key]);
end
look.colors.text[1] = 0;
assert(colored.colors.text[1] == 0.1);
-- The party list buffs wear the timer panels' look, with the party's own icons and opacity.
config.style.icon_art, config.style.opacity = 'XI View', 0.5;
local timer_style = { theme = 'Mint', window_type = 3, font = 'Consolas', font_size = 20, icon_art = 'Client', opacity = 0.9,
    rounding = 7, minimal = true, background = false, border = false };
local party = theme.party(config, timer_style);
local main = theme.resolve(timer_style);
assert(party.theme == 'Mint' and party.window_type == 3 and party.font == 'Consolas' and party.font_size == 20 and party.rounding == 7
    and party.minimal and not party.background and not party.border, 'The party list buffs wear the timer panels\' look.');
assert(party.icon_art == 'XI View' and party.opacity == 0.5, 'with their own icons and opacity');
for _, key in ipairs(theme.color_keys) do
    assert(store.encode(party.colors[key]) == store.encode(main.colors[key]), 'and the timer panels\' colors: ' .. key);
end
config.style.icon_art, config.style.opacity = nil, nil;
party = theme.party(config, timer_style);
assert(party.icon_art == 'Client' and party.opacity == 0.9, 'Without icons or opacity of their own they take the timer panels\'.');
-- Given the settings revision the look is kept until that revision or those settings change, and without one it is new.
local kept = theme.party(config, timer_style, 1);
assert(theme.party(config, timer_style, 1) == kept, 'A revision has one look.');
timer_style.font_size = 22;
local changed = theme.party(config, timer_style, 2);
assert(changed ~= kept and changed.font_size == 22, 'A change of settings is a new revision, and a new look.');
assert(theme.party(defaults.make(), timer_style, 2) ~= changed, 'Other party settings make it again.');
assert(theme.party(config, { font = 'Consolas' }, 2).font == 'Consolas', 'So do other timer panel settings.');
assert(theme.party(config, timer_style) ~= theme.party(config, timer_style), 'Without a revision it is made every time.');
local inherited = theme.resolve({}, global);
assert(inherited.font == 'Consolas' and inherited.font_size == 20 and not inherited.minimal);
local invalid = theme.resolve({ theme = 'Invalid', font = false, font_size = 0 / 0, window_type = 99,
    opacity = math.huge, scale = 0, colors = { title = { -1, 9, 0 / 0, 0.2 } } });
assert(invalid.theme == 'Phoenix' and invalid.font == 'Ashita' and invalid.font_size == 14);
assert(invalid.window_type == 8 and invalid.opacity == 1 and invalid.scale == 0.5);
assert(invalid.colors.title[1] == 0 and invalid.colors.title[2] == 1 and invalid.colors.title[4] == 0.2);
local ordinary = theme.resolve({ theme = 'Classic FFXI' });
assert(theme.fallback_background(ordinary)[1] == ordinary.colors.background[1]);
local native = theme.resolve({ theme = 'Original FFXI', window_type = 7 });
assert(native.colors.text[1] < 0.15 and native.colors.title[1] < 0.15);
assert(native.gauge_text_color[1] == 1, 'Parchment still has dark native gauge tracks.');
local fonts = require('ui.fonts');
local failed = fonts.failed;
for _, font in ipairs({ 'Original FFXI', 'XI View' }) do
    fonts.failed = function() return false; end;
    local bitmap = theme.resolve({ theme = 'Original FFXI', window_type = 7, font = font });
    assert(bitmap.colors.text[1] == 1 and bitmap.colors.title[1] == 1, 'Native bitmap shadows need their light foreground.');
    bitmap = theme.resolve({ theme = 'Original FFXI', window_type = 7, font = font, colors = { text = {0.2, 0.4, 0.6, 1} } });
    assert(bitmap.colors.text[1] == 0.2 and bitmap.gauge_text_color[1] == 0.2, 'Explicit text choices still win.');
    fonts.failed = function() return true; end;
    local missing = theme.resolve({ theme = 'Original FFXI', window_type = 7, font = font });
    assert(missing.colors.text[1] < 0.15 and missing.colors.title[1] < 0.15,
        'The ordinary fallback font needs dark parchment text when client glyphs are unavailable.');
end
-- On parchment the game's font loading changes the text color with no setting changed, so that look isn't kept.
local parchment = { theme = 'Original FFXI', window_type = 7, font = 'Original FFXI' };
fonts.failed = function() return true; end;
assert(theme.party(config, parchment, 3).colors.text[1] < 0.15, 'Dark text until the game font is there.');
fonts.failed = function() return false; end;
assert(theme.party(config, parchment, 3).colors.text[1] == 1, 'Its light text on the next frame it is.');
fonts.failed = failed;
assert(theme.fallback_background(native)[1] == 198 / 255);
assert(theme.fallback_background(theme.resolve({ theme = 'Original FFXI' }))[1] == 49 / 255);

-- Exercise the timer panels' window art through the party bridge.
local available = true;
local requests, images = {}, {};
package.loaded['ui.client_assets'] = {
    texture = function(kind, name, window_type)
        requests[#requests + 1] = { kind, name, window_type };
        if not available then return nil; end
        local size = name == 'newtex' and 128 or name == 'gauge' and 64 or 32;
        return { id = kind == 'xiview_font' and 'xiview_' .. name or name, width = size, height = size };
    end,
};
package.loaded['ui.client_skin'] = nil;
local list = { AddImage = function(_, id, first, last, uv1, uv2, tint)
    local copy = MOCK.copy_vector;
    images[#images + 1] = { id = id, first = copy(first), last = copy(last), uv1 = copy(uv1), uv2 = copy(uv2), tint = tint };
end };
local rect = { x = 20, y = 30, width = 310, height = 220 };
for window_type = 1, 8 do
    images, requests = {}, {};
    look = theme.resolve({ theme = 'Original FFXI', window_type = window_type });
    assert(theme.panel(list, rect, look));
    for _, request in ipairs(requests) do assert(request[3] == window_type); end
    assert(#images > 8 and images[1].last[1] - images[1].first[1] == 128);
    for _, image in ipairs(images) do
        assert(image.first[1] >= rect.x and image.first[2] >= rect.y);
        assert(image.last[1] <= rect.x + rect.width and image.last[2] <= rect.y + rect.height);
        assert(image.uv1[1] >= 0 and image.uv1[2] >= 0 and image.uv2[1] <= 1 and image.uv2[2] <= 1);
    end
end
local selected = theme.resolve({ style = { theme = 'Original FFXI', gauge_art = 'XI View', font = 'Agave' } });
assert(selected.gauge_art == 'XI View' and selected.font == 'Agave');
assert(theme.resolve({style={gauge_art='Original FFXI'}}, {gauge_art='XI View'}).gauge_art == 'Original FFXI');
assert(theme.resolve({}).gauge_art == 'Original FFXI' and theme.resolve({gauge_art='Invalid'}).gauge_art == 'Original FFXI');
available = false;
assert(not theme.panel(list, rect, look));
assert(not theme.panel(list, rect, ordinary));
