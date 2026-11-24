-- Look > Row text > a part's Color starts from the color the part draws in, as ui/fields.lua colors it: the panel's own
-- Name, Countdown or Detail text color, then the shared one. Who it is on, Who cast it, Time elapsed and Full length go
-- by the Detail text color, so on the default skin they don't draw in the Text color. While Color each countdown by how
-- sure Vantage is of its time is on, a countdown takes its row's color, and a note says so.
local defaults, hud = require('ui.defaults'), require('ui.hud');
local window, panels = require('ui.settings_window'), require('ui.panel_frame');
local imgui = require('imgui');

-- Party members' timers starts as bars with row text on. Every part shows here, so each is listed by its own name.
local s, view = defaults.make(), hud.sample(100);
local p = s.panels.party;
s.window.open, s.window.tab = true, 'Display';
p.show_source, p.show_elapsed, p.show_total = true, true, true;
local cb = { now = function() return 100; end, save = function() return true; end, changed = function() end };

-- What the part's Color swatch is drawn with. Every color row fills one table, so it's copied during the call.
local SWATCH = 'Color##frame_part';
local swatch;
imgui.ColorEdit4 = function(label, value)
    if label == SWATCH then swatch = { value[1], value[2], value[3], value[4] }; end;
    return false;
end;

local function frame(click)
    swatch = nil;
    MOCK.imgui_calls = {};
    if click then MOCK.clicks[click] = true; end;
    window.draw(s, view, cb);
    if click then assert(MOCK.clicks[click] == nil, 'Fixture: the click on ' .. click .. ' landed.'); end;
end

local names = { name = 'Name', target = 'Who it is on', source = 'Who cast it', elapsed = 'Time elapsed', total = 'Full length', time = 'Countdown' };
-- The swatch of a part, once it's the one open in Parts of a row.
local function shown(key)
    frame(names[key]);
    frame();
    assert(swatch, 'Fixture: the Color swatch is drawn for ' .. names[key] .. '.');
    return swatch;
end

-- What a part draws in, from the entries the panel draws its row text from.
local function drawn(row, panel, key)
    for _, entry in ipairs(hud.entries(row, panel, s.style, 100)) do
        if entry.id == key then return entry.color; end;
    end;
    error('Fixture: the row shows ' .. key .. '.');
end

local function same(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]; end
local function text(color) return ('%.3f %.3f %.3f %.3f'):format(color[1], color[2], color[3], color[4]); end

-- Whether the note about countdowns that take their row's color is drawn.
local function noted()
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'TextWrapped' and tostring(call[2]):find('takes its row\'s color', 1, true) then return true; end;
    end;
    return false;
end

-- A Haste that Tester cast on Friend, with a known time, so the row has every part.
local row = { effect = 33, name = 'Haste', domain = 'status', kind = 'buff', scope = 'party', status = 'exact',
    entity_id = 1002, entity_name = 'Friend', source_name = 'Tester', start = 90, total = 180, deadline = 270 };

panels.open('party', 'look');
frame();

-- The default skin: the four detail parts draw in the Detail text color, which isn't the Text color.
assert(not same(s.style.detail_color, s.style.text_color), 'Fixture: Detail text and Text differ on the default skin.');
for _, key in ipairs({ 'target', 'source', 'elapsed', 'total' }) do
    local color = drawn(row, p, key);
    assert(same(color, s.style.detail_color), 'Fixture: ' .. names[key] .. ' draws in the Detail text color.');
    assert(same(shown(key), color), names[key] .. '\'s swatch shows the color it draws in, ' .. text(color) .. ', not ' .. text(swatch) .. '.');
end;

-- The main page's Name and Countdown colors set apart from Text, with countdowns in the Countdown color.
s.style.label_color, s.style.value_color, s.style.status_time_color = { 0.9, 0.6, 0.2, 1 }, { 0.3, 0.8, 0.9, 1 }, false;
for _, key in ipairs({ 'name', 'time' }) do
    local color = drawn(row, p, key);
    assert(same(color, key == 'name' and s.style.label_color or s.style.value_color), 'Fixture: ' .. names[key] .. ' draws in its shared color.');
    assert(same(shown(key), color), names[key] .. '\'s swatch shows its shared color, ' .. text(color) .. ', not ' .. text(swatch) .. '.');
    assert(not noted(), 'No note while countdowns take the Countdown color.');
end;

-- The panel's own colors come first.
p.colors.label, p.colors.value, p.colors.detail = { 1, 0, 0, 1 }, { 0, 1, 0, 1 }, { 0, 0, 1, 1 };
for _, key in ipairs({ 'name', 'target', 'source', 'elapsed', 'total', 'time' }) do
    local color = drawn(row, p, key);
    local own = key == 'name' and p.colors.label or key == 'time' and p.colors.value or p.colors.detail;
    assert(same(color, own), 'Fixture: ' .. names[key] .. ' draws in the panel\'s own color.');
    assert(same(shown(key), color), names[key] .. '\'s swatch shows the panel\'s own color, ' .. text(color) .. ', not ' .. text(swatch) .. '.');
end;
assert(next(p.field_colors) == nil, 'Showing the swatches saved no part color.');

-- Color each countdown by how sure Vantage is of its time: a countdown takes its row's color over the shared Countdown
-- color, which no one swatch can show. The swatch shows the Countdown color and the note says so.
p.colors.value, s.style.status_time_color = nil, true;
p.effect_colors[33] = { 0.5, 0.25, 0.75, 1 };
assert(same(drawn(row, p, 'time'), p.effect_colors[33]), 'Fixture: the countdown takes its row\'s color.');
assert(same(shown('time'), s.style.value_color), 'The Countdown swatch shows the Countdown color: ' .. text(swatch) .. '.');
assert(noted(), 'A note says a countdown takes its row\'s color while Color each countdown by how sure Vantage is of its time is on.');
frame('Name');
frame();
assert(not noted(), 'The note is for Countdown only.');
-- The panel's own Countdown color goes over the row's color, and so does a part color.
p.colors.value = { 0, 1, 0, 1 };
assert(same(drawn(row, p, 'time'), p.colors.value), 'Fixture: the countdown takes the panel\'s own Countdown color.');
assert(same(shown('time'), p.colors.value), 'The swatch shows the panel\'s own Countdown color: ' .. text(swatch) .. '.');
assert(not noted(), 'No note while the panel has its own Countdown color.');
p.colors.value, p.field_colors.time = nil, { 0.1, 0.2, 0.3, 1 };
assert(same(drawn(row, p, 'time'), p.field_colors.time), 'A color picked for Countdown goes over the row\'s color.');
frame();
assert(same(swatch, p.field_colors.time) and not noted(), 'With a part color saved, the swatch shows it and there\'s no note.');

-- Recast panels share these rows. A recast's Time elapsed draws in the Detail text color too.
local r = s.panels.spell_recasts;
r.show_elapsed = true;
local recast = { effect = 1, name = 'Cure', domain = 'recast', kind = 'spell', status = 'exact', start = 90, total = 180, deadline = 270 };
panels.open('spell_recasts', 'look');
frame();
local color = drawn(recast, r, 'elapsed');
assert(same(color, s.style.detail_color), 'Fixture: a recast\'s Time elapsed draws in the Detail text color.');
assert(same(shown('elapsed'), color), 'A recast panel\'s Time elapsed swatch shows the color it draws in, ' .. text(color) .. ', not ' .. text(swatch) .. '.');
return 'Row text\'s part Color starts from the color the part draws in';
