-- Fit the width sizes a panel to its widest row, so with Wrap long rows on, or with When space is short, keep the
-- higher-priority parts, nothing has to wrap or drop there. The room a row gets is worked out from the fitted width by
-- taking the padding off again, which gives the row's own width back only up to float error, so a row that fits by
-- that much still fits. Each case is drawn with the option off and on, and the two panels are the same size.
local defaults, hud, fields = require('ui.defaults'), require('ui.hud'), require('ui.fields');
local imgui = require('imgui');
local now, view = 100, hud.sample(100);
local sizes, texts = {}, 0;
local dimensions = {};
imgui.SetNextWindowPos = function() end;
imgui.SetNextWindowSize = function(value) dimensions = value; end;
imgui.Begin = function(name) sizes[name] = { dimensions[1], dimensions[2] }; return true; end;

local SCALES = { 0.5, 0.6, 0.7, 0.8, 0.9, 1, 1.1, 1.2, 1.25, 1.3, 1.4, 1.5, 1.7, 2 };
local function drawn(key, scale, icon, option)
    local s = defaults.make();
    for _, p in pairs(s.panels) do p.enabled = false; end
    local p = s.panels[key];
    p.enabled, p.mode, p.auto_width, p.show_icon, p.locked = true, 'bars', true, icon, true;
    p.show_target, p.show_source = true, true;
    -- Stacked across, a panel is a whole number of cells of its item width, and a row wider than a cell does wrap.
    p.stack_direction = 'vertical';
    if option then p[option] = true; end
    s.style.scale = scale;
    s = defaults.tidy(s);
    sizes = {};
    MOCK.imgui_calls = {};
    for _ = 1, 4 do hud.draw(view, s, now, { shift = false }); end
    local size = sizes['##vantage_' .. key];
    assert(size, 'Fixture: the ' .. key .. ' panel drew.');
    local drawn_texts = 0;
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'draw:AddText' then drawn_texts = drawn_texts + 1; end end
    return size[1], size[2], drawn_texts;
end

local cases = 0;
for _, key in ipairs({ 'self_buffs', 'target', 'party' }) do
    for _, scale in ipairs(SCALES) do
        for _, icon in ipairs({ true, false }) do
            local width, height, plain_texts = drawn(key, scale, icon);
            local where = key .. ' at Size ' .. scale .. (icon and ' with its icon' or ' with no icon');
            local wrap_width, wrap_height = drawn(key, scale, icon, 'wrap');
            assert(math.abs(wrap_width - width) < 0.001 and math.abs(wrap_height - height) < 0.001,
                'Wrap long rows leaves a fitted panel as it was: ' .. where .. ' went from ' .. height .. ' tall to ' .. wrap_height);
            local keep_width, keep_height, keep_texts = drawn(key, scale, icon, 'priority_overflow');
            assert(math.abs(keep_width - width) < 0.001 and math.abs(keep_height - height) < 0.001 and keep_texts == plain_texts,
                'Keeping the higher-priority parts drops nothing from a fitted panel: ' .. where .. ' drew ' .. keep_texts
                .. ' texts, not ' .. plain_texts);
            cases = cases + 1;
        end
    end
end
assert(cases == 84, 'Fixture: every panel, size and icon choice was drawn.');

-- The same in the small: parts that are as wide as the room, give or take float error, stay on one line and all stay.
local function measure(text) return #text * 7.3; end
local entries = { { id = 'name', text = 'Protect', priority = 3, size = 14 }, { id = 'target', text = 'Tester', priority = 1, size = 14 },
    { id = 'time', text = '29:59', priority = 2, size = 14 } };
local needed = 0;
for index, entry in ipairs(entries) do needed = needed + measure(entry.text) + (index > 1 and measure('  ') or 0); end
for _, short in ipairs({ 0, 1e-12, 1e-9 }) do
    local lines = fields.lines(entries, needed - short, { wrap = true, separator = '  ' }, measure);
    assert(#lines == 1 and #lines[1] == 3, 'A row short of room by ' .. short .. ' px stays on one line.');
    local kept = fields.fit(entries, needed - short, '  ', measure, true);
    assert(#kept == 3, 'A row short of room by ' .. short .. ' px keeps every part.');
end
-- A row that is short of room by a pixel still wraps, and still drops its lowest-priority part.
local lines = fields.lines(entries, needed - 1, { wrap = true, separator = '  ' }, measure);
assert(#lines == 2, 'A row a pixel too wide wraps.');
local kept = fields.fit(entries, needed - 1, '  ', measure, true);
assert(#kept == 2 and kept[1].id == 'name' and kept[2].id == 'time', 'A row a pixel too wide drops its lowest-priority part.');
return 'A fitted panel never wraps or drops a part for float error';
