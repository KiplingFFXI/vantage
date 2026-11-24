-- A panel that fills down, other than Icons, puts the rows that don't fit in its height in more columns, which share
-- its width. hud.split_columns says how many, and the panel's Size and place tab says so under Column width. Timer
-- panels take a Width and Narrowest up to 2400, and a saved one keeps it.
local hud, defaults, elements = require('ui.hud'), require('ui.defaults'), require('ui.elements');

-- The combined Recasts panel's four sample recasts, at 1200 wide and 80 tall unless change says otherwise. With
-- separate, the Spell recasts panel's two.
local function laid_out(change, separate)
    local s = defaults.tidy(defaults.make());
    local key = separate and 'spell_recasts' or 'recasts';
    s.recast_display, s.preview = separate and 'separate' or 'combined', true;
    for id, p in pairs(s.panels) do p.enabled = id == key; end;
    local p = s.panels[key];
    p.width, p.height_limit = 1200, 80;
    if change then change(s, p); end;
    hud.draw({ valid = true, context = { id = 1001, valid = true }, rows = {} }, s, 1000, {});
    return hud.split_columns(key);
end;

local columns = laid_out();
assert(columns == 4, 'Four rows in a panel one row tall go down in four columns: ' .. tostring(columns));
assert(laid_out(nil, true) == 2 and hud.split_columns('recasts') == nil, 'A recast panel of its own goes by its own key.');
-- The places stay while the panels aren't drawn, as with Vantage off or hidden, so the count goes with them.
laid_out();
elements.frame();
assert(hud.split_columns('recasts') == 4, 'A panel drawn the Present before still counts.');
elements.frame();
assert(hud.split_columns('recasts') == nil, 'One not drawn since says nothing.');
assert(laid_out(function(_, p) p.height_limit = 400; end) == nil, 'With room for every row, they stay in one column.');
-- A Column width only one column fits leaves the other rows out, and that still counts, so the row and its line stay
-- to put it back.
assert(laid_out(function(_, p) p.item_width = 700; end) == 1, 'A Column width only one column fits leaves one column, and says so.');
assert(laid_out(function(_, p) p.item_width = 700; p.height_limit = 400; end) == nil, 'With every row in that one column, nothing is said.');
assert(laid_out(function(_, p) p.mode = 'icons'; end) == nil, 'Icons keep their size in any column, so nothing is said.');
assert(laid_out(function(_, p) p.stack_direction = 'horizontal'; end) == nil, 'Rows that fill across are side by side by choice.');
assert(laid_out(function(_, p) p.enabled = false; end) == nil, 'A panel that isn\'t drawn has no columns.');
assert(hud.split_columns('self_buffs') == nil, 'Nor does one that was never laid out.');

-- A saved width up to 2400 stays, and past it comes back to 2400.
local s = defaults.make();
s.panels.recasts.width, s.panels.recasts.min_width, s.panels.recasts.max_width = 2400, 2400, 2400;
s = defaults.tidy(s);
assert(s.panels.recasts.width == 2400 and s.panels.recasts.min_width == 2400, 'A saved Width and Narrowest of 2400 stay.');
s.panels.recasts.width, s.panels.recasts.min_width = 3000, 3000;
s = defaults.tidy(s);
assert(s.panels.recasts.width == 2400 and s.panels.recasts.min_width == 2400, 'Past 2400 they come back to it.');

-- The tab, with the column count stood in for, as the settings draw without the panels.
local h = require('panel_fixture')();
local real = hud.split_columns;
local split = nil;
hud.split_columns = function(key) return key == 'recasts' and split or nil; end;
local LINE = 'so they go down in 3 columns that share its width';
h.fresh(function(fresh)
    fresh.recast_display = 'combined';
    fresh.panels.recasts.enabled, fresh.panels.recasts.locked = true, false;
end);
h.on('recasts', 'place');
assert(not h.says('columns that share its width'), 'No line while the rows are in one column.');
split = 3;
h.draw();
assert(h.says(LINE) and h.says('More height fits them in one') and h.says('a wider panel widens the columns')
    and h.says('A Column width too wide makes fewer columns and leaves rows out'),'The line names the columns and what widens rows.');
split = nil;
h.draw();
assert(not h.says('columns that share its width'), 'It goes once they fit in one column again.');
split = 1;
h.draw();
assert(h.called('SliderFloat', '##frame_Column width') and h.says("there's room across for one column only, so the rest are left out")
    and h.says('and so does room across for a second column') and not h.says('columns that share its width'),
    'With one column and rows left out, Column width stays and the line says why.');
hud.split_columns = real;

h.slide('##frame_Fixed width', 2400);
assert(h.s.panels.recasts.width == 2400, 'Width takes 2400: ' .. tostring(h.s.panels.recasts.width));
h.slide('##frame_Fixed width', 5000);
assert(h.s.panels.recasts.width == 2400, 'Width goes no further than 2400.');
h.s.panels.recasts.auto_width = true;
h.bump();
h.draw();
h.slide('##frame_Narrowest', 2400);
assert(h.s.panels.recasts.min_width == 2400 and h.s.panels.recasts.max_width == 2400, 'Narrowest takes 2400 and Widest follows it.');
return 'Rows split into columns say so on Size and place, and timer panels go up to 2400 wide.';
