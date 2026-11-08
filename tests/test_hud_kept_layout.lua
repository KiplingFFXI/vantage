-- What the panels keep from frame to frame never shows. A row's lines, its width for Auto width, where its text goes,
-- the panels' places, the samples and the alerts' wraps are kept, and after each change below the frame drawn with
-- them is the same, call for call and value for value, as that frame drawn by a fresh copy of the HUD that has kept
-- nothing yet. The copy command's text matches too, and each change shows.
local bit = require('bit');
local imgui = require('imgui');
local calls = {};
local function put(value)
    if type(value) == 'number' then return ('%.17g'):format(value); end
    if type(value) == 'table' then
        local parts = {};
        for index = 1, 4 do if value[index] ~= nil then parts[#parts + 1] = put(value[index]); end end
        return '{' .. table.concat(parts, ',') .. '}';
    end
    return tostring(value);
end
local function record(name, ...)
    local parts = { name };
    for index = 1, select('#', ...) do parts[#parts + 1] = put((select(index, ...))); end
    calls[#calls + 1] = table.concat(parts, ' ');
end
-- A draw list that writes down each call it gets, whatever its name.
local list = setmetatable({}, { __index = function(self, name)
    local method = function(_, ...) record(name, ...); end;
    rawset(self, name, method);
    return method;
end });
local function noted(name, result) return function(...) record(name, ...); return result; end; end
local function no() return false; end
-- Fonts are pushed to measure text the shared text cache hasn't measured yet, which the first of two HUDs does, so
-- pushes aren't written down. Text names its own font and size where it is drawn.
-- A screen tall enough for every row, however big its text.
local io = { DisplaySize = { x = 1920, y = 6000 }, KeyShift = false };
for name, fn in pairs({ GetWindowDrawList = function() return list; end, GetForegroundDrawList = function() return list; end,
    col32 = function(a, r, g, b) return bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r); end,
    CalcTextSize = function(text) return #tostring(text) * 7, 14; end, GetFont = function() return 1; end,
    PushFont = no, PopFont = no, PushStyleVar = noted('PushStyleVar'), PopStyleVar = noted('PopStyleVar'),
    SetNextWindowPos = noted('SetNextWindowPos'), SetNextWindowSize = noted('SetNextWindowSize'), Begin = noted('Begin', true),
    End = noted('End'), SetCursorPos = noted('SetCursorPos'), InvisibleButton = noted('InvisibleButton', false), IsItemHovered = no,
    IsItemActive = no, IsMouseClicked = no, IsMouseDown = no, GetIO = function() return io; end,
    GetMousePos = function() return -1, -1; end }) do rawset(imgui, name, fn); end
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);

local defaults = require('ui.defaults');
local kept = require('ui.hud');
-- A copy of the HUD that has kept nothing, while the add-on goes on using the one that has.
local function fresh()
    package.loaded['ui.hud'] = nil;
    local copy = require('ui.hud');
    package.loaded['ui.hud'] = kept;
    return copy;
end

local s = defaults.tidy(defaults.make());
local status = { 'self_buffs', 'self_debuffs', 'target', 'party', 'watch' };
for _, id in ipairs(defaults.panel_order) do
    local p = s.panels[id];
    p.enabled, p.mode, p.height_limit = true, 'bars', 6000;
end
local function each(change) for _, id in ipairs(status) do change(s.panels[id]); end end
-- The samples' rows twice over.
local view = kept.sample(100);
local originals = #view.rows;
for index = 1, originals do
    local extra = defaults.copy(view.rows[index]);
    extra.key, extra.instance = 'extra_' .. index, 100 + index;
    view.rows[#view.rows + 1] = extra;
end
local function row_of(name)
    for _, row in ipairs(view.rows) do if row.name == name then return row; end end
    error('Fixture: a ' .. name .. ' row.');
end
local now, callbacks = 100.25, {};

-- One frame by a HUD: its calls, then the copy command's text.
local function frame(hud)
    calls = {};
    hud.draw(view, s, now, callbacks);
    calls[#calls + 1] = hud.copy_text(view, s, nil, false, now);
    return table.concat(calls, '\n');
end
local last = frame(kept);
assert(last == frame(fresh()), 'Fixture: two fresh frames are the same.');
local function check(name, change)
    change();
    local drawn, expected = frame(kept), frame(fresh());
    if drawn ~= expected then
        local a, b = {}, {};
        for line in (drawn .. '\n'):gmatch('(.-)\n') do a[#a + 1] = line; end
        for line in (expected .. '\n'):gmatch('(.-)\n') do b[#b + 1] = line; end
        for index = 1, math.max(#a, #b) do
            assert(a[index] == b[index], name .. ': kept ' .. tostring(a[index]) .. ', fresh ' .. tostring(b[index]));
        end
    end
    assert(drawn ~= last, 'Fixture: ' .. name .. ' shows.');
    last = drawn;
end

check('A second later', function() now = now + 1; end);
check('A field\'s label', function() each(function(p) p.field_labels.time = 'Left'; end); end);
check('Labels after their values', function() each(function(p) p.label_position = 'after'; end); end);
check('More fields', function() each(function(p) p.show_source, p.show_target, p.show_elapsed, p.show_total = true, true, true, true; end); end);
check('Expanded', function() each(function(p) p.mode = 'expanded'; end); end);
check('Text', function() each(function(p) p.mode = 'text'; end); end);
check('Icons', function() each(function(p) p.mode = 'icons'; end); end);
check('Bars again', function() each(function(p) p.mode = 'bars'; end); end);
check('Fields in another order', function()
    each(function(p) p.field_order[1], p.field_order[2] = p.field_order[2], p.field_order[1]; end);
end);
check('A line break before the countdown', function() each(function(p) p.field_newlines.time = true; end); end);
check('A field\'s color', function() each(function(p) p.field_colors.name = { 1, 0.2, 0.2, 1 }; end); end);
check('That color changed in place', function() each(function(p) p.field_colors.name[2] = 0.8; end); end);
check('Bigger text', function() s.style.font_size = 20; end);
check('A bigger scale', function() s.style.scale = 1.25; end);
check('Another separator and divider', function() each(function(p) p.separator, p.field_dividers.time = ' | ', ' / '; end); end);
check('Wrapped in a narrow panel', function() each(function(p) p.wrap, p.width = true, 170; end); end);
check('Centered', function() each(function(p) p.alignment = 'center'; end); end);
check('An effect\'s own name', function() each(function(p) p.labels[40] = 'Wall'; end); end);
check('An effect\'s own color', function() each(function(p) p.effect_colors[41] = { 0.2, 0.9, 0.3, 1 }; end); end);
check('Times in the text color', function() s.style.status_time_color = false; end);
check('The panels\' value color', function() each(function(p) p.colors.value = { 0, 1, 1, 1 }; end); end);
check('Another caster', function() row_of('Haste').source_name = 'Someone else'; end);
check('An estimated row', function() row_of('Shell').status = 'estimated'; end);
check('A range', function()
    local row = row_of('Shell');
    row.duration_min = row.total - 30;
end);
check('Another name', function() row_of('Paralysis').name = 'Paralyze'; end);
check('Auto width', function() each(function(p) p.auto_width = true; end); end);
check('A longer name under Auto width', function() row_of('Paralyze').name = 'Paralyze with a much longer name'; end);
check('Text under Auto width', function() each(function(p) p.mode = 'text'; end); end);
check('Bars under Auto width', function() each(function(p) p.mode = 'bars'; end); end);
check('Auto width off', function() each(function(p) p.auto_width = false; end); end);
check('Bold countdowns', function() each(function(p) p.countdown_bold = true; end); end);
check('Ending soon with no fill', function() each(function(p) p.show_fill, p.warning_seconds = false, 3600; end); end);
check('A big heading', function() s.style.title_size = 48; end);
check('A title of its own', function() each(function(p) p.title = 'My timers'; end); end);
check('Text outline', function() s.style.text_outline = true; end);
check('A row gone', function() table.remove(view.rows, 1); end);
check('Fewer rows', function() each(function(p) p.max_rows = 2; end); end);
check('Two alerts', function()
    view.notices = { { visual = true, ends = 1e9, message = 'Haste wears off in 10s' },
        { visual = true, ends = 1e9, estimated = true, message = 'Dia on Goblin Bandit wears off in 30s, a longer line that wraps' } };
end);
check('An alert\'s text', function() view.notices[1].message = 'Protect wears off in 1m'; end);
check('Fewer alerts', function() s.alerts.max_notices = 1; end);
check('The samples', function() s.preview = true; end);
check('The samples a second later', function() now = now + 1; end);
check('The samples\' tints', function()
    local tints = s.recast_tints;
    tints.mp, tints.spell_lock, tints.ability_lock = not tints.mp, not tints.spell_lock, not tints.ability_lock;
end);
check('Samples off', function() s.preview = false; end);
return 'What the panels keep never shows';
