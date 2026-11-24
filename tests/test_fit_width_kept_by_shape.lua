-- Fits the rows measures a countdown or an elapsed time as the widest text of its shape, every digit the font's widest
-- (widest_width in ui/hud.lua). So a row's width is kept while its times keep their shape, and a ticking row isn't
-- built and measured again for the width each second, on top of its lines. First what that saves, measured as
-- test_hud_draw_allocation.lua does, with the collector stopped and the compiler off. Then that the width drawn is the
-- same each frame as one worked out fresh, with digits of different widths, in ImGui's font, a bitmap font and a font
-- of your own, for countdowns, ranges, counting up and elapsed times as they change shape.
local bit = require('bit');
local imgui = require('imgui');
local function nothing() end
local function yes() return true; end
local function no() return false; end
-- Each digit is its own width, so a width that went by the digits shown would change as they tick.
local ADVANCE = {};
for code = 0, 255 do ADVANCE[code] = 7; end
for digit = 0, 9 do ADVANCE[48 + digit] = 5 + digit; end
ADVANCE[('s'):byte()], ADVANCE[('m'):byte()], ADVANCE[('h'):byte()] = 6, 11, 8;
local function advance(text)
    local width = 0;
    for index = 1, #text do width = width + ADVANCE[text:byte(index)]; end
    return width;
end
local io = { DisplaySize = { x = 1920, y = 1080 }, KeyShift = false };
local list = { AddImage = nothing, AddRect = nothing, AddRectFilled = nothing, AddRectFilledMultiColor = nothing, AddText = nothing,
    AddLine = nothing, PushClipRect = nothing, PopClipRect = nothing, AddImageQuad = nothing, AddPolyline = nothing };
local window, size, widths = nil, { 0, 0 }, nil;
for name, fn in pairs({ GetWindowDrawList = function() return list; end, GetForegroundDrawList = function() return list; end,
    col32 = function(a, r, g, b) return bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r); end,
    CalcTextSize = function(text) return advance(tostring(text)), 14; end, PushFont = nothing, PopFont = nothing, GetFont = function() return 1; end,
    PushStyleVar = nothing, PopStyleVar = nothing, SetNextWindowPos = nothing,
    SetNextWindowSize = function(value) size[1], size[2] = value[1], value[2]; end,
    Begin = function(name) if widths and name == '##vantage_party' then widths[#widths + 1] = size[1]; end return true; end, End = nothing,
    SetCursorPos = nothing, InvisibleButton = no, IsItemHovered = no, IsItemActive = no, IsMouseClicked = no, IsMouseDown = no,
    GetIO = function() return io; end, GetMousePos = function() return -1, -1; end }) do rawset(imgui, name, fn); end
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);
-- Original FFXI stands for a bitmap font, measured by its own glyphs.
local fonts = require('ui.fonts');
local plain_bitmap, plain_measure, plain_countdown = fonts.is_bitmap, fonts.measure, fonts.measure_countdown;
fonts.is_bitmap = function(name) return name == 'Original FFXI' or plain_bitmap(name); end;
fonts.measure = function(name, text, at) if name == 'Original FFXI' then return advance(tostring(text)) * at / 12; end return plain_measure(name, text, at); end;
fonts.measure_countdown = function(name, text, at, compact)
    if name == 'Original FFXI' then return advance(tostring(text)) * at / (compact and 13 or 12), at; end
    return plain_countdown(name, text, at, compact);
end;

local hud, defaults, fields = require('ui.hud'), require('ui.defaults'), require('ui.fields');
local builds = 0;
local build = fields.build;
fields.build = function(...) builds = builds + 1; return build(...); end;
local function settings(font, auto)
    local s = defaults.tidy(defaults.make());
    s.style.font, s.style.font_size, s.style.scale = font, 14, 1;
    for id, p in pairs(s.panels) do p.enabled = id == 'party'; end
    local p = s.panels.party;
    p.mode, p.auto_width, p.min_width, p.max_rows, p.height_limit = 'bars', auto, 1, 64, 4000;
    return s;
end

-- What Fits the rows saves: 30 rows in their last minute, each text changing once a second.
local rows = {};
for index = 1, 30 do
    rows[index] = { key = 'r' .. index, instance = index, effect = 40 + index, name = 'Effect ' .. index, kind = 'buff', scope = 'party',
        group = 'Buffs', entity_id = 1002, entity_name = 'Member', status = 'server', present = true, deadline = 1020 + index * 1.2,
        total = 120 };
end
local view = { valid = true, now = 1000, rows = rows, context = { id = 1001, valid = true, party = {} } };
local callbacks, s = {}, nil;
local now = 1000;
local function frames(count) for _ = 1, count do now = now + 1 / 60; hud.draw(view, s, now, callbacks); end end
local function regrow(n) if n > 0 then return 1 + regrow(n - 1); end return 0; end
local function made(auto)
    s = settings('Ashita', auto);
    jit.off(); jit.flush();
    now = 1000; frames(120);
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    regrow(300);
    frames(6);
    builds = 0;
    local before = collectgarbage('count');
    frames(600);
    local each = (collectgarbage('count') - before) / 600;
    collectgarbage('restart');
    jit.on();
    return each, builds;
end
local fixed, fixed_builds = made(false);
local fitted, fitted_builds = made(true);
assert(fixed_builds >= 250, 'Fixture: the rows are laid out again as they tick: ' .. fixed_builds);
assert(fitted <= fixed * 1.25, ('Fits the rows makes %.3f KB a frame as the rows tick, %.3f without it (%d rows built, %d without it)')
    :format(fitted, fixed, fitted_builds, fixed_builds));

-- The same width as one worked out fresh. The fresh run gives its row a new key each frame, so nothing is kept for it.
local START = 1000;
local KINDS = {
    countdown = { status = 'server', deadline = START + 3650, total = 4000, start = START - 350 },
    hours = { status = 'server', deadline = START + 360065, total = 400000, start = START - 39935 },
    short = { status = 'server', deadline = START + 70, total = 120, start = START - 50 },
    range = { status = 'estimated', duration_min = 50, total = 125, start = START - 10, deadline = START + 115 },
    up = { status = 'server', count_up = true, start = START - 50, total = 300, deadline = START + 250 },
    elapsed = { status = 'server', start = START - 55, total = 200, deadline = START + 145 },
};
local function run(font, kind, fresh)
    s = settings(font, true);
    local p = s.panels.party;
    p.show_elapsed, p.show_total = true, true;
    widths, builds = {}, 0;
    local spec = KINDS[kind];
    local frame_rows = { {} };
    local frame_view = { valid = true, now = START, rows = frame_rows, context = { id = 1001, valid = true, party = {} } };
    for frame = 0, 520 do
        local row = frame_rows[1];
        if fresh then row = {}; frame_rows[1] = row; end
        for key, value in pairs(spec) do row[key] = value; end
        row.key = fresh and kind .. frame or kind;
        row.instance, row.effect, row.name, row.kind, row.scope, row.group = 1, 33, 'Haste', 'buff', 'party', 'Buffs';
        row.entity_id, row.entity_name, row.source_name, row.present = 1002, 'Member', 'Caster', true;
        hud.draw(frame_view, s, START + frame / 4, callbacks);
    end
    local out = widths;
    widths = nil;
    return out, builds;
end
for _, font in ipairs({ 'Ashita', 'Original FFXI', 'My Own Font' }) do
    for kind in pairs(KINDS) do
        local kept, kept_builds = run(font, kind, false);
        local fresh, fresh_builds = run(font, kind, true);
        assert(#kept == 521 and #fresh == 521, 'Fixture: the panel is drawn each frame.');
        local differ, first;
        for frame = 1, #kept do
            if kept[frame] ~= fresh[frame] then differ = (differ or 0) + 1; first = first or frame; end
        end
        assert(not differ, ('%s, %s: %d frames drawn at another width than fresh, first %s (%s against %s)'):format(font, kind,
            differ or 0, tostring(first), tostring(first and kept[first]), tostring(first and fresh[first])));
        assert(kept_builds < fresh_builds, 'Fixture: the kept run keeps its row: ' .. kept_builds .. ' of ' .. fresh_builds);
        -- Building a range's width again each second, as before, takes 256 builds here, and keeping it by shape 160.
        assert(kind ~= 'range' or kept_builds <= 200,
            font .. ', range: a range keeps its width while both ends keep their shape: ' .. kept_builds .. ' builds');
    end
end
fonts.is_bitmap, fonts.measure, fonts.measure_countdown = plain_bitmap, plain_measure, plain_countdown;
fields.build = build;
return true;
