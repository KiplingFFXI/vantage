-- A row shows while it changes something on the screen, and the row that turns that on stands in for it in the search.
local h = require('panel_fixture')();
local window = h.window;
local ID = 'self_buffs';

local function rows(tab, change, id)
    id = id or ID;
    h.fresh(function(s)
        s.window.sections['Panels/Panel appearance overrides'], s.window.sections['Panels/Field layout and wording'] = true, true;
        s.style.minimal, s.panels[id].mode = false, 'bars';
        if change then change(s.panels[id], s); end;
    end);
    h.on(id, tab);
    return h.drawn();
end;
local function all(names, list, says)
    for _, label in ipairs(list) do assert(names[label], says .. ': ' .. label); end;
end;
local function none(names, list, says)
    for _, label in ipairs(list) do assert(not names[label], says .. ': ' .. label); end;
end;

local BAR = { 'Bar shape', 'Bar runs', 'Fill from', 'Shaded bars', 'Bar track color', 'Bar fill start color' };
local TEXT = { 'Row text', 'Name color' };
all(rows('look'), { 'Show its heading', 'Heading', 'Box', 'Show the bar', 'Show row text', 'Ending soon', 'Title color', 'Countdown color', 'Row text' }, 'A fresh panel has it');
all(rows('look'), BAR, 'A fresh panel has it');
all(rows('look', function(p) p.gradient = true; end), { 'Bar fill end color' }, 'Shaded bars has its end color');
none(rows('look'), { 'Bar fill end color' }, 'One color has no end');

-- The bar off: what shapes it goes, and the tick stays to turn it back on.
local names = rows('look', function(p) p.show_fill = false; end);
none(names, BAR, 'With no bar it goes');
all(names, { 'Show the bar', 'Show row text', 'Ending soon' }, 'With no bar it stays');
none(names, { 'Mark it too' }, 'A mark sits on the bar');
assert(rows('place')['Bar thickness'] and not rows('place', function(p) p.show_fill = false; end)['Bar thickness'], 'Bar thickness goes with the bar.');
local function lands(query)
    for _, result in ipairs(window.search(query)) do if result.panel == ID then return result.label; end; end;
end;
h.on(ID, 'look');
assert(lands('bar shape') == 'Show the bar', 'Search leads to the row that shows it: ' .. tostring(lands('bar shape')));

-- Row text off: only the icon has anything to change, and the page says so.
names = rows('look', function(p) p.show_text = false; end);
none(names, TEXT, 'With no row text it goes');
all(names, { 'Show row text', 'Show the bar' }, 'With no row text it stays');
names = rows('show', function(p) p.show_text = false; end);
none(names, { 'Name', 'Countdown', 'Who cast it', 'Time elapsed', 'Full length' }, 'With no row text the part goes');
assert(names.Icon and h.says('Row text is off under Look, so only the icon can change here.'), 'The icon stays, and a line says why.');

-- Nothing on a bar and nothing in text: nothing to color.
none(rows('look', function(p) p.show_fill, p.show_text = false, false; end), { 'Ending soon', 'Ending soon color' }, 'With no bar and no text it goes');

-- The heading off.
none(rows('look', function(p) p.show_heading = false; end), { 'Heading', 'Title color' }, 'With no heading it goes');

-- No boxes or headings, for every panel.
names = rows('look', function(_, s) s.style.minimal = true; end);
none(names, { 'Show its heading', 'Heading', 'Box', 'Title color', 'Background color', 'Border color' }, 'No boxes or headings takes it');
assert(h.says('No boxes or headings is on, so this panel draws neither. Turn it off under More look on the main page to use them.'), 'And says where to turn it off.');
h.fresh(function(s) s.style.minimal = true; end);
h.on(ID, 'look');
assert(lands('panel box') == 'Why there is no box or heading' or lands('panel box') == 'Layout', 'Box leads to what hides it: ' .. tostring(lands('panel box')));

-- The box: a color shows while its part is drawn.
names = rows('look', function(p) p.box = 'none'; end);
none(names, { 'Background color', 'Border color' }, 'Box None takes it');
all(rows('look', function(p) p.box = 'both'; end), { 'Background color', 'Border color' }, 'Background and border has it');
names = rows('look', function(p) p.box = 'background'; end);
assert(names['Background color'] and not names['Border color'], 'Background only has its color alone.');

-- Text has no bar and no row text tick, and takes its Row text fold.
names = rows('look', function(p) p.mode = 'text'; end);
none(names, BAR, 'Text has no bar');
none(names, { 'Show the bar', 'Show row text' }, 'Text has no switch for it');
all(names, { 'Ending soon', 'Row text' }, 'Text has it');

-- The glow goes behind a picture.
local function glow(change) return rows('look', function(p) p.dispel_light = true; if change then change(p); end; end, 'self_debuffs')['Glow around lit icons']; end;
assert(glow(), 'Bars with an icon have a glow.');
assert(not glow(function(p) p.show_icon = false; end), 'Bars with no icon have none.');
assert(not glow(function(p) p.mode = 'text'; end), 'Text has none.');
assert(glow(function(p) p.mode = 'icons'; end), 'Icons have one.');

-- Who it is on: yours are always on you, so a self panel never shows it.
assert(not rows('show')['Who it is on'], 'On a self panel it has nothing to say.');
assert(not rows('show', function(p) p.show_target = true; end)['Who it is on'], 'A save with it on changes nothing.');
assert(rows('show', nil, 'target')['Who it is on'], 'On Target it stays.');

-- A color for one effect shows on a bar, or a countdown that takes a row's color. Otherwise a line says where it would.
local TINT = 'A color shows on a bar, or on a countdown while Color each countdown by how sure Vantage is of its time is on under More look.';
local function picked(change)
    rows('filters', change);
    h.type('##frame_Find an effect', 'Haste');
    return h.drawn();
end;
assert(picked().Color and not h.says(TINT), 'A panel with bars takes a color.');
names = picked(function(p, s) p.show_fill, s.style.status_time_color = false, false; end);
assert(not names.Color and h.says(TINT), 'With no bar and no color on countdowns, a line says what would take it.');
assert(picked(function(p, s) p.show_fill, s.style.status_time_color = false, true; end).Color, 'A countdown that takes it has the row.');
return 'Rows that change nothing in a state wait for what turns them on';
