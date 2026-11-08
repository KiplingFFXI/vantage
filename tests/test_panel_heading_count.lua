-- A bars, expanded or text panel's heading counts the rows it shows. Rows its row limit or its height leave out are
-- not counted, so the heading never names more rows than the panel draws.
package.loaded['ui.icons'] = { status = function(effect) return tonumber(effect) and 5000 + effect or nil; end };
local hud, defaults, fonts = require('ui.hud'), require('ui.defaults'), require('ui.fonts');
-- Tall enough for every row of the crowded view below.
MOCK.screen = { 1600, 4000 };

local painted = {};
local plain_paint = fonts.paint;
fonts.paint = function(imgui, list, look, value, x, y, ...)
    painted[#painted + 1] = { value = value, y = y };
    return plain_paint(imgui, list, look, value, x, y, ...);
end;

-- The number drawn on the heading's line, beside the title (or its shadow, a pixel lower).
local function heading_count(title)
    local lines = {};
    for _, text in ipairs(painted) do if text.value == title then lines[text.y] = true; end; end;
    assert(next(lines), 'Fixture: the heading is drawn: ' .. title);
    for _, text in ipairs(painted) do
        if lines[text.y] and tostring(text.value):match('^%d+$') then return tonumber(text.value); end;
    end;
end;

-- The rows the panel drew, as Copy shown lists them: the title, then one line a row.
local function rows_drawn(s, view, key, now)
    local copied = hud.copy_text(view, s, key, false, now);
    return select(2, copied:gsub('\n', ''));
end;

-- The usual sample with six more of each row, so a panel has more to list than it shows.
local now = 100;
local view = hud.sample(now);
local originals = #view.rows;
for extra_set = 1, 6 do
    for index = 1, originals do
        local extra = defaults.copy(view.rows[index]);
        extra.key, extra.instance = 'sample_extra_' .. extra_set .. '_' .. index, 100 * extra_set + index;
        view.rows[#view.rows + 1] = extra;
    end;
end;
for _, key in ipairs({ 'self_buffs', 'target', 'spell_recasts' }) do
    for _, mode in ipairs({ 'bars', 'expanded', 'text' }) do
        local s = defaults.make();
        s.style.font, s.style.font_size, s.style.scale = 'Ashita', 14, 1;
        for id, panel in pairs(s.panels) do panel.enabled = id == key; end;
        local p = s.panels[key];
        p.mode, p.locked, p.show_heading = mode, true, true;
        local title = defaults.panel_names[key];
        local listed = #hud.filter_rows(view, p, key, s);
        assert(listed > 3, 'Fixture: ' .. key .. ' lists more rows than it shows.');
        local function draw()
            painted, MOCK.imgui_calls = {}, {};
            hud.draw(view, s, now, {});
            return heading_count(title), rows_drawn(s, view, key, now);
        end;
        -- The row limit cuts the list.
        p.max_rows, p.auto_height, p.height_limit = 2, true, 700;
        local count, drawn = draw();
        assert(drawn == 2, 'Fixture: ' .. key .. ' ' .. mode .. ' draws two rows at its row limit: ' .. drawn);
        assert(count == drawn, key .. ' ' .. mode .. ' counts the two rows it shows, not the ' .. listed .. ' that match: ' .. tostring(count));
        -- A fixed height too short for every row cuts it instead.
        p.max_rows, p.auto_height = listed + 5, false;
        p.height_limit = hud.bounds(p, s.style, listed, 1600, 4000).min_height;
        count, drawn = draw();
        assert(drawn >= 1 and drawn < listed, 'Fixture: ' .. key .. ' ' .. mode .. ' is cut by its height: ' .. drawn);
        assert(count == drawn, key .. ' ' .. mode .. ' counts the rows its height fits: ' .. tostring(count) .. ' of ' .. drawn);
        -- With room for all of them, it counts them all.
        p.auto_height, p.height_limit = true, 4000;
        count, drawn = draw();
        assert(drawn == listed and count == listed, key .. ' ' .. mode .. ' counts every row when all fit: ' .. tostring(count));
    end;
end;

-- A count too wide for its usual place, 32 in from the right edge, ends as far in from that edge as the title starts from
-- the left, 9, and the title's clip stops short of it. A count that fits stays where it was.
do
    local metrics, elements = require('ui.text_metrics'), require('ui.elements');
    local s = defaults.make();
    s.style.font, s.style.font_size, s.style.scale = 'Ashita', 14, 1;
    for id, panel in pairs(s.panels) do panel.enabled = id == 'self_buffs'; end;
    local p = s.panels.self_buffs;
    p.mode, p.locked, p.show_heading, p.max_rows, p.auto_height = 'bars', true, true, 40, true;
    local title = defaults.panel_names.self_buffs;
    -- The count's place and the right edge of the clip the title is drawn in.
    local function heading(size)
        s.style.title_size = size;
        painted, MOCK.imgui_calls = {}, {};
        hud.draw(view, s, now, {});
        local count, rect = tostring(heading_count(title)), elements.drawn('self_buffs');
        local pushed, clip, count_x;
        for _, call in ipairs(MOCK.imgui_calls) do
            local values = MOCK.drawn[call];
            if call[1] == 'draw:PushClipRect' then pushed = values[3][1]; end;
            if call[1] == 'draw:AddText' and call[6] == title and not clip then clip = pushed; end;
            if call[1] == 'draw:AddText' and call[6] == count and clip and not count_x then count_x = values[4][1]; end;
        end;
        assert(rect and #count >= 2, 'Fixture: the heading counts ten rows or more: ' .. count);
        return count, count_x, clip, rect;
    end;
    local count, count_x, clip, rect = heading(48);
    local edge = rect.x + rect.width - 9;
    assert(count_x + metrics.width(s.style.font, count, 48, 14) <= edge + 1e-6, 'The count ends inside the right edge.');
    assert(clip <= count_x, 'The title stops short of the count: ' .. clip .. ' past ' .. count_x);
    assert(count_x < rect.x + rect.width - 32, 'Fixture: at Title size 48 the count leaves its usual place.');
    count, count_x = heading(0);
    assert(count_x == rect.x + rect.width - 32, 'A count that fits stays 32 in from the right edge.');
end;

fonts.paint = plain_paint;
return 'A panel heading counts only the rows it shows, inside its edge and clear of its title';
