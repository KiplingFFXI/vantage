-- Fits the rows on a panel that fills down counts its rows at the height they're drawn at, so rows taller than the set
-- row height, a Thin rail's or a part on a new line, still get the columns they need within Widest, and every row shows.
package.loaded['ui.icons'] = { status = function() return 123; end };
rawset(require('imgui'), 'CalcTextSize', function(text) return #tostring(text) * 8, 18; end);
local hud, defaults = require('ui.hud'), require('ui.defaults');
local elements = require('ui.elements');
MOCK.screen = { 1920, 1080 };
local function make_rows(count)
    local rows = {};
    for index = 1, count do
        rows[index] = { key = 'r' .. index, effect = 40 + index, slot = index - 1, scope = 'party', entity_id = 1002, entity_name = 'Bob',
            kind = 'buff', status = 'estimated', name = 'Buff ' .. index, deadline = 1000 + 60 * index, start = 990, total = 600 };
    end
    return rows;
end
-- The party panel's window width, its column count (hud.split_columns) and how many of the rows it drew.
local function laid(count, change)
    local s = defaults.tidy(defaults.make());
    s.style.font, s.style.font_size, s.style.scale = 'Ashita', 14, 1;
    for id, panel in pairs(s.panels) do panel.enabled = id == 'party'; end
    local p = s.panels.party;
    p.mode, p.stack_direction, p.max_rows = 'bars', 'vertical', 32;
    p.min_width, p.max_width, p.auto_width = 160, 900, true;
    change(p);
    elements.frame();
    MOCK.imgui_calls = {};
    hud.draw({ valid = true, context = { id = 1001, valid = true, party = {} }, rows = make_rows(count) }, s, 1000, {});
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

local function rail(p) p.height_limit, p.bar_style, p.bar_thickness = 390, 'rail', 8; end
local function new_line(p) p.height_limit, p.field_newlines = 300, { time = true }; end
for _, case in ipairs({ { 'Thin rail', rail, { 10, 19, 20 } }, { 'time on a new line', new_line, { 6, 12, 14 } } }) do
    local name, change, counts = case[1], case[2], case[3];
    -- What one column holds: every row shows while the rows fit, and the width stays what one row needs.
    local one_width, one_split, one_shown = laid(1, change);
    assert(one_split == nil and one_shown == 1, name .. ': one row needs one column: ' .. tostring(one_split));
    for _, count in ipairs(counts) do
        local width, split, shown = laid(count, change);
        assert(shown == count, ('%s, %d rows: Fits the rows within Widest 900 leaves %d out at %s wide in %s columns')
            :format(name, count, count - shown, tostring(width), tostring(split)));
        assert(width <= 900 and width >= one_width, name .. ': it stays within Widest: ' .. tostring(width));
        -- No wider than the columns it needs, each as wide as one row needs or Column width.
        local cell = math.max(280, one_width - 16);
        if split and split > 1 then
            assert(math.abs(width - (split * (cell + 4) - 4 + 16)) < 0.001,
                ('%s, %d rows: %s wide for %d columns of %s'):format(name, count, tostring(width), split, cell));
        end
    end
    -- Rows that fit keep the width one row needs.
    local fit_width, fit_split = laid(3, change);
    assert(fit_split == nil and fit_width == one_width, name .. ': rows that fit keep the width: ' .. tostring(fit_width));
end
return 'Fits the rows counts rows at the height they are drawn at';
