-- The strips beside the game's party list make nothing per frame once running, while no countdown's text changes: six
-- members with countdowns, each strip's window and paint, and the samples, which are made once and run on from frame to
-- frame as new ones would. Measured as test_hud_draw_allocation.lua does, with the collector stopped and the compiler
-- off, on an ImGui whose calls keep nothing, time moving within one second. A table made ten times a second shows.
local bit = require('bit');
local imgui = require('imgui');
local function nothing() end
local function yes() return true; end
local function no() return false; end
local io = { DisplaySize = { x = 2400, y = 1600 } };
local list = { AddImage = nothing, AddRect = nothing, AddRectFilled = nothing, AddText = nothing, AddLine = nothing,
    PushClipRect = nothing, PopClipRect = nothing, AddImageQuad = nothing, AddPolyline = nothing,
    GetClipRectMin = function() return 0, 0; end, GetClipRectMax = function() return 2400, 1600; end };
for name, fn in pairs({ GetWindowDrawList = function() return list; end, GetForegroundDrawList = function() return list; end,
    col32 = function(a, r, g, b) return bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r); end,
    CalcTextSize = function(text) return #tostring(text) * 7, 14; end, PushFont = nothing, PopFont = nothing, GetFont = function() return 1; end,
    PushStyleVar = nothing, PopStyleVar = nothing, SetNextWindowPos = nothing, SetNextWindowSize = nothing, Begin = yes, End = nothing,
    SetCursorPos = nothing, SetCursorScreenPos = nothing, Dummy = nothing, InvisibleButton = no, IsItemHovered = no, IsItemActive = no,
    IsItemActivated = no, IsMouseClicked = no, IsMouseDown = no, IsWindowHovered = no, GetScrollY = function() return 0; end,
    GetIO = function() return io; end, GetMousePos = function() return -1, -1; end, IsPopupOpen = no }) do rawset(imgui, name, fn); end
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);

local hud, party, native = require('ui.party_hud'), require('ui.party_defaults'), require('ui.native_party_hud');
-- A kept set of samples runs as new ones would: moved on 13.5 seconds, each countdown is where a new set has it.
local _, kept = hud.sample(18, 100);
hud.sample_time(kept, 113.5);
local _, fresh = hud.sample(18, 113.5);
for id, subject in pairs(fresh) do
    for index, effect in ipairs(subject.effects) do
        assert(kept[id].effects[index].remaining == effect.remaining, 'A kept sample runs on as a new one would: ' .. effect.key);
    end
end

local p = party.make();
p.enabled, p.locked, p.show_solo, p.effects.timers = true, true, true, true;
local roster, subjects = hud.sample(6, 100);
local geometry = { available = true, groups = { [1] = { x = 1800, y = 100, width = 116, height = 240, rows = {} } } };
for _, member in ipairs(roster.members) do
    geometry.groups[1].rows[member.slot] = { x = 1800, y = 100 + member.slot * 40, width = 116, height = 40, slot = member.slot };
end
-- The settings revision, as the frame passes it, keeps the strips' look from frame to frame.
local callbacks = { native_geometry = geometry, revision = 1 };
local metrics = require('ui.text_metrics');

-- Each frame moves on by step, and time starts over at 100.3 once it reaches 100.9, so no countdown's text changes.
-- refresh, once set, runs every sixth frame, as a refresh comes ten times a second, and gives the subjects to draw.
local now, leak, made, refresh = 100.3, false, nil, nil;
local function frames(count, step)
    for i = 1, count do
        now = now + (step or 1 / 12000);
        if now >= 100.9 then now = 100.3; end
        if refresh and i % 6 == 0 then subjects = refresh(); end
        metrics.begin_frame();
        native.draw(roster, subjects, p, now, callbacks);
        metrics.end_frame();
        if leak and i % 6 == 0 then made = {}; end
    end
end
-- A full collection shrinks the Lua stack, and the next frames grow it back once, which is LuaJIT's and not a frame's,
-- so a few frames run after the collection, with the collector stopped, before counting starts. A deep call grows the
-- stack first too, as a frame that goes a little deeper now and then would grow it while counting. run, when given,
-- draws the frames in place of frames.
local function deep(n) if n > 0 then return deep(n - 1) + 1; end return 0; end
local function measure(count, run)
    run = run or frames;
    jit.off(); jit.flush();
    run(60);
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    deep(300);
    run(6);
    local before = collectgarbage('count');
    run(count);
    local each = (collectgarbage('count') - before) / count;
    collectgarbage('restart');
    jit.on();
    return each;
end
-- Warm.
frames(600);
local each = measure(600);
assert(each < 0.002, ('The strips make %.4f KB a frame; nothing expected'):format(each));
leak = true;
each = measure(600);
leak = false;
assert(each >= 0.002 and made, ('One table made ten times a second shows as %.4f KB a frame'):format(each));
-- Countdowns that tick, with time running on: on each row Protect and Haste run down in their last minute, Protect some
-- seconds longer, and longer on each row than on the row before, so each second shows each row a pair of texts it
-- hasn't shown before. Once each text has been shown somewhere, a row takes its new countdowns in place and the strips
-- make nothing.
local ends, kept_left = {}, {};
local function run_down(count)
    for _ = 1, count do
        now = now + 1 / 60;
        for effect, at in pairs(ends) do effect.remaining = at - now; end
        metrics.begin_frame();
        native.draw(roster, subjects, p, now, callbacks);
        metrics.end_frame();
    end
end
local function start(apart)
    for id, subject in pairs(subjects) do
        local protect, haste = subject.effects[1], subject.effects[2];
        assert(protect.name == 'Protect' and haste.name == 'Haste', 'Fixture: Protect and Haste come first.');
        kept_left[protect], kept_left[haste] = kept_left[protect] or protect.remaining, kept_left[haste] or haste.remaining;
        ends[haste], ends[protect] = now + 59.5, now + 59.5 + apart + id % 1000;
    end
end
-- Every text from 59s down to 2s, shown once.
start(20);
run_down(58 * 60);
start(3);
each = measure(600, run_down);
assert(each < 0.002, ('Countdowns that tick make %.4f KB a frame; nothing expected'):format(each));
for effect, left in pairs(kept_left) do effect.remaining = left; end
now = 100.3;
-- The samples, with their outline.
p.preview = true;
frames(600);
each = measure(600);
assert(each < 0.002, ('The samples make %.4f KB a frame; nothing expected'):format(each));
-- A strip on a panel of its own, with its members' names over their rows.
p.preview = false;
local own = p.groups[1];
own.native_detached, own.detached_x, own.detached_y, own.detached_width, own.detached_height = true, 300, 200, 260, 500;
frames(600);
each = measure(600);
assert(each < 0.002, ('A strip on a panel of its own makes %.4f KB a frame; nothing expected'):format(each));
-- The distance (core/party_distance.lua): a number on each other member's row, one past Spell range, beside the game's
-- list, then the samples by slot, then in a panel of its own. The text for each tenth is kept, so it makes nothing.
own.native_detached, p.distance = false, true;
for _, member in ipairs(roster.members) do
    if member.slot > 0 then member.tenths, member.far = 40 + member.slot * 37, member.slot == 5; end
end
frames(600);
local planned = 0;
for _, item in ipairs(native._kept.groups[1].rows) do if item.distance_cell then planned = planned + 1; end end
assert(planned > 0 and planned == #native._kept.groups[1].rows, 'Fixture: every row has the column: ' .. planned);
each = measure(600);
assert(each < 0.002, ('The distances make %.4f KB a frame; nothing expected'):format(each));
-- Largest searches for its size each frame, and that makes nothing either.
p.distance_size = 'largest';
frames(600);
each = measure(600);
assert(each < 0.002, ('The distances on Largest make %.4f KB a frame; nothing expected'):format(each));
p.distance_size = 'small';
p.preview = true;
frames(600);
each = measure(600);
assert(each < 0.002, ('The sample distances make %.4f KB a frame; nothing expected'):format(each));
p.preview, own.native_detached = false, true;
frames(600);
local ended = 0;
for _, item in ipairs(native._kept.detached[1].rows) do if item.distance_right then ended = ended + 1; end end
assert(ended > 0 and ended == #native._kept.detached[1].rows, 'Fixture: each name line ends at the number: ' .. ended);
each = measure(600);
assert(each < 0.002, ('Distances in a panel of its own make %.4f KB a frame; nothing expected'):format(each));
-- A long night of pickup parties: a new member takes slot 1 again and again. The panel keeps the widths it measured, and
-- those stop growing however many names come and go.
local member = roster.members[2];
local first_name = member.name;
for index = 1, 3000 do
    member.name = 'Pickup' .. index;
    frames(2);
end
local widths, kept_widths = native._kept.detached[1].widths, 0;
if type(widths.count) == 'function' then kept_widths = widths:count(); else for _ in pairs(widths) do kept_widths = kept_widths + 1; end end
assert(kept_widths <= 512, 'A panel of its own keeps ' .. kept_widths .. ' widths after 3000 names; at most 512 expected');
member.name = first_name;

-- Through a refresh, as the app makes the strips' subjects (party_subjects in vantage.lua). Each refresh's view has a
-- new table for each unit and a new list of the tracker's same rows, and one row on each member is neither a buff nor
-- a debuff, which the subjects hold a copy of. While the rows hold the same, the strips make nothing then either.
local app = dofile(ADDON_DIR .. '/vantage.lua');
own.native_detached, p.distance = false, false;
local rows = {};
for id, subject in pairs(subjects) do
    for _, effect in ipairs(subject.effects) do
        local row = { entity_id = id };
        for key, value in pairs(effect) do row[key] = value; end
        rows[#rows + 1] = row;
    end
    rows[#rows + 1] = { entity_id = id, effect = 251, name = 'Food', status = 'estimated', present = true, key = 'f' .. id,
        remaining = 200 };
end
table.sort(rows, function(a, b) return a.key < b.key; end);
local function view_of(list, members)
    local view = { rows = {}, subjects = {} };
    for at, row in ipairs(list) do view.rows[at] = row; end
    for _, member in ipairs(members) do view.subjects[#view.subjects + 1] = { id = member.id, known = true, scope = 'party' }; end
    return view;
end
local views, turn = {}, 0;
for index = 1, 160 do views[index] = view_of(rows, roster.members); end
refresh = function()
    turn = turn % #views + 1;
    return app.party_subjects(views[turn]);
end;
frames(600);
local function row_of(id)
    for _, item in ipairs(native._kept.groups[1].rows) do if item.member.id == id then return item; end end
end
local food, food_row;
for _, effect in ipairs(subjects[1003].effects) do if effect.key == 'f1003' then food = effect; end end
for _, row in ipairs(rows) do if row.key == 'f1003' then food_row = row; end end
assert(#row_of(1002).effects == #subjects[1002].effects and subjects[1002].effects[1].entity_id == 1002,
    'Fixture: each strip row shows its member\'s rows: ' .. #row_of(1002).effects);
assert(food and food.kind == 'neutral' and food.name == 'Food' and food ~= food_row and food_row.kind == nil,
    'A row neither a buff nor a debuff is shown as a copy, neutral.');
each = measure(600);
assert(each < 0.002, ('Through a refresh the strips make %.4f KB a frame; nothing expected'):format(each));
-- With a hide rule on, what the rules work out is kept from refresh to refresh too (effect_filters.subjects).
local effect_filters = require('core.effect_filters');
local hide = effect_filters.make();
hide.rules = { { enabled = true, effect = 4, kind = 'all', name = '', job = 0, scope = 'all' } };
callbacks.effect_filters, callbacks.effect_recipients = effect_filters.compile(hide), effect_filters.recipients(nil, roster);
frames(600);
assert(#row_of(1002).effects == #subjects[1002].effects - 1, 'Fixture: the rule hides Paralysis: ' .. #row_of(1002).effects);
each = measure(600);
assert(each < 0.002, ('Through a refresh with a hide rule the strips make %.4f KB a frame; nothing expected'):format(each));
callbacks.effect_filters, callbacks.effect_recipients = nil, nil;
-- What a refresh changes shows: a row gone, a row that changed, one that lost a field and a unit gone.
refresh = nil;
frames(6);
local shown = #row_of(1002).effects;
local fewer, members = {}, {};
for _, row in ipairs(rows) do
    if row.key ~= 'p2' then fewer[#fewer + 1] = row; end
    if row.key == 'f1003' then row.name = 'Meal'; end
    if row.key == 'f1004' then row.remaining = nil; end
end
for _, member in ipairs(roster.members) do if member.id ~= 1006 then members[#members + 1] = member; end end
local remapped;
subjects, remapped = app.party_subjects(view_of(fewer, members));
frames(1);
local kept_food, timeless;
for _, effect in ipairs(subjects[1003].effects) do if effect.key == 'f1003' then kept_food = effect; end end
for _, effect in ipairs(subjects[1004].effects) do if effect.key == 'f1004' then timeless = effect; end end
assert(#row_of(1002).effects == shown - 1, 'A row gone leaves the strip: ' .. #row_of(1002).effects .. ' of ' .. shown);
assert(kept_food == food and kept_food.name == 'Meal' and kept_food.kind == 'neutral', 'A kept copy holds what its row holds now.');
assert(timeless and timeless.remaining == nil and timeless.name == 'Food', 'A field its row lost leaves the copy.');
assert(subjects[1006] == nil and #row_of(1006).effects == 0, 'A unit gone from the view has no subject.');
assert(#remapped == 5 and remapped[6] == nil, 'Only the copies shown are moved on each frame: ' .. #remapped);
