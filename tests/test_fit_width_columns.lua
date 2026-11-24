-- A panel that fills down with Width at Fits the rows widens for the columns its rows need once they don't fit in its
-- height, as many as Widest holds at the width a row needs, so the rows past the height show in the next column as they
-- do at a Fixed width that wide. Rows that fit in one column, or a Widest with room for one column only, leave it at the
-- width one row needs.
package.loaded['ui.icons'] = { status = function() return 123; end };
rawset(require('imgui'), 'CalcTextSize', function(text) return #tostring(text) * 8, 18; end);
local hud, defaults = require('ui.hud'), require('ui.defaults');
local elements = require('ui.elements');
MOCK.screen = { 1920, 1080 };
local rows = {};
for index = 1, 20 do
    rows[index] = { key = 'r' .. index, effect = 40 + index, slot = index - 1, scope = 'party', entity_id = 1002, entity_name = 'Bob',
        kind = 'buff', status = 'estimated', name = 'Buff ' .. index, deadline = 1000 + 60 * index, start = 990, total = 600 };
end
-- The party panel's window width, its column count (hud.split_columns) and how many of the rows it drew.
local function laid(change)
    local s = defaults.tidy(defaults.make());
    s.style.font, s.style.font_size, s.style.scale = 'Ashita', 14, 1;
    for id, panel in pairs(s.panels) do panel.enabled = id == 'party'; end
    local p = s.panels.party;
    p.mode, p.stack_direction, p.max_rows, p.height_limit = 'bars', 'vertical', 32, 300;
    p.min_width, p.max_width = 160, 900;
    change(p);
    elements.frame();
    MOCK.imgui_calls = {};
    hud.draw({ valid = true, context = { id = 1001, valid = true, party = {} }, rows = rows }, s, 1000, {});
    local size, last, window, names = nil, nil, nil, {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'SetNextWindowSize' then last = call[2];
        elseif call[1] == 'Begin' then
            window = call[2];
            if window == '##vantage_party' then size = last; end
        elseif call[1] == 'End' then window = nil;
        elseif call[1] == 'draw:AddText' and window == '##vantage_party' then
            local text = MOCK.drawn[call][6];
            if type(text) == 'string' and text:match('^Buff %d+$') then names[text] = true; end
        end
    end
    local shown = 0;
    for _ in pairs(names) do shown = shown + 1; end
    return size and size[1], hud.split_columns('party'), shown;
end

-- At a Fixed width of 900 the 20 rows go down in columns.
local fixed_width, fixed_split = laid(function(p) p.auto_width, p.width = false, 900; end);
assert(fixed_split and fixed_split >= 2, 'Fixture: at a fixed 900 the 20 rows go down in columns: ' .. tostring(fixed_split));

-- Tall enough for every row: one column, at the width one row needs.
local one_width, one_split = laid(function(p) p.auto_width, p.height_limit = true, 2000; end);
assert(one_width and one_split == nil, 'With room for every row they stay in one column: ' .. tostring(one_split));

-- 300 tall: Fits the rows makes room for the columns they need, within Widest, and every row shows.
local fit_width, fit_split = laid(function(p) p.auto_width = true; end);
print(('fixed: width %s columns %s; one column: width %s; fits: width %s columns %s'):format(tostring(fixed_width),
    tostring(fixed_split), tostring(one_width), tostring(fit_width), tostring(fit_split)));
assert(fit_split ~= 1, ('With Fits the rows and Widest 900, the panel stays %s wide with one column and leaves rows out (split %s)')
    :format(tostring(fit_width), tostring(fit_split)));
assert(fit_split and fit_split >= 2 and fit_width > one_width and fit_width <= 900,
    'It widens for more columns, no wider than Widest: ' .. tostring(fit_width) .. ', ' .. tostring(fit_split));
-- Each column has the room one row needs, or Column width when that is more.
local cell = math.max(280, one_width - 16);
assert(math.abs(fit_width - (fit_split * (cell + 4) - 4 + 16)) < 0.001,
    'The columns are as wide as one row needs: ' .. fit_width .. ' for ' .. fit_split .. ' of ' .. cell);
local _, _, fit_shown = laid(function(p) p.auto_width = true; end);
assert(fit_shown == 20, 'Every row shows: ' .. fit_shown);

-- A Widest with room for one column only leaves it at the width one row needs, and the rest left out, as before.
local narrow_width, narrow_split = laid(function(p) p.auto_width, p.max_width = true, one_width + 100; end);
assert(narrow_split == 1 and narrow_width == one_width,
    'With room for one column only, the width stays: ' .. tostring(narrow_width) .. ', ' .. tostring(narrow_split));

-- Most shown counts as it does for the width: rows past it need no column.
local most_width, most_split = laid(function(p) p.auto_width, p.max_rows = true, 5; end);
assert(most_split == nil and most_width == one_width, 'Rows past Most shown add no column: ' .. tostring(most_width));

-- Expanded rows are taller, so they need more columns, and get them while Widest holds them.
local expanded_width, expanded_split, expanded_shown = laid(function(p) p.auto_width, p.mode, p.max_width = true, 'expanded', 1400; end);
assert(expanded_split and expanded_split >= 2 and expanded_width <= 1400 and expanded_shown == 20,
    'Expanded rows get their columns too: ' .. tostring(expanded_width) .. ', ' .. tostring(expanded_split) .. ', ' .. expanded_shown);
-- With room for fewer, they show what a Fixed width that wide shows.
local _, held_split, held_shown = laid(function(p) p.auto_width, p.mode = true, 'expanded'; end);
local _, fixed_held_split, fixed_held_shown = laid(function(p) p.auto_width, p.mode, p.width = false, 'expanded', 900; end);
assert(held_split == fixed_held_split and held_shown == fixed_held_shown and held_shown < 20,
    ('Widest 900 holds as many columns as a Fixed 900: %s and %s columns, %s and %s rows'):format(tostring(held_split),
        tostring(fixed_held_split), held_shown, fixed_held_shown));

-- Rows that fill across work out their columns as before.
local across_width = laid(function(p) p.auto_width, p.stack_direction = true, 'horizontal'; end);
assert(across_width == math.floor((900 - 16 + 4) / 284) * 284 - 4 + 16, 'Rows that fill across keep their width: ' .. tostring(across_width));
return 'Fits the rows makes room for the columns a panel that fills down needs';
