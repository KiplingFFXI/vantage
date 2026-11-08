-- Drawing the Phantom Roll and pet displays makes nothing per frame once running: two rolls with their numbers,
-- members and a ticking window, and a charmed pet with its bars, eight effects with countdowns that blink near their
-- end, two lines of maneuvers and six recasts, under the shared hide rules; the same pet with its effects as a list, and
-- with a jug's clock; and the sample of each pet job. Measured as test_overhead_draw_allocation.lua does, with the
-- collector stopped and the compiler off, on an ImGui whose calls keep nothing. A table made ten times a second shows.
local bit = require('bit');
local imgui = require('imgui');
local function nothing() end
local function yes() return true; end
local function no() return false; end
local io = { DisplaySize = { x = 1920, y = 1080 } };
local list = { AddImage = nothing, AddRect = nothing, AddRectFilled = nothing, AddText = nothing, AddLine = nothing,
    PushClipRect = nothing, PopClipRect = nothing, AddImageQuad = nothing, AddPolyline = nothing };
for name, fn in pairs({ GetWindowDrawList = function() return list; end, GetForegroundDrawList = function() return list; end,
    col32 = function(a, r, g, b) return bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r); end,
    CalcTextSize = function(text) return #tostring(text) * 7, 14; end, PushFont = nothing, PopFont = nothing, GetFont = function() return 1; end,
    PushStyleVar = nothing, PopStyleVar = nothing, SetNextWindowPos = nothing, SetNextWindowSize = nothing, Begin = yes, End = nothing,
    SetCursorPos = nothing, InvisibleButton = no, IsItemHovered = no, IsItemActive = no, IsMouseClicked = no, GetIO = function() return io; end,
    GetMousePos = function() return -1, -1; end, IsPopupOpen = no }) do rawset(imgui, name, fn); end
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);

local defaults, rolls, pet = require('ui.defaults'), require('core.rolls'), require('core.pet');
local roll_display, pet_display = require('ui.roll_display'), require('ui.pet_display');
local s = defaults.tidy(defaults.make());
s.rolls.enabled, s.pet.enabled = true, true;
local self_id, ally = 1001, 1002;
local snapshot = { valid = true, id = self_id, zone = 102, name = 'Tester', level = 75, job = 9, sub_job = 18,
    pet = { id = 0x1000123, index = 0x123, name = 'Crab', kind = 'pet' },
    self_effects = { { effect = 300, deadline = 500 }, { effect = 300, deadline = 700 }, { effect = 304, deadline = 900 } },
    party = { { id = ally, name = 'Ally', scope = 'party', zone = 102, slot = 1 } },
    entities = { [self_id] = { id = self_id, index = 0x400, name = 'Tester', kind = 'player' } } };
local watch = rolls.new();
watch:observe({ kind = 'roll', entity_id = self_id, ability = 105, total = 4, targets = { self_id, ally }, results = { 'got', 'none' } }, 0);
watch:observe({ kind = 'roll', entity_id = ally, ability = 108, total = 9, double_up = true, targets = { ally }, results = { 'got' } }, 0);
local view = { rolls = watch:refresh(0, s, snapshot, {}) };
assert(#view.rolls == 2, 'Fixture: two rolls.');
-- A pet with eight effects, your maneuvers and six recasts.
local effects, recasts = {}, {};
for i = 1, 8 do
    effects[i] = { effect = 30 + i, name = 'Effect name', kind = i <= 3 and 'debuff' or 'buff', status = 'estimated', present = true, remaining = 5 + i * 4,
        total = 60, first_seen = i, instance = i };
end
for i, timer in ipairs({ 102, 103, 104, 97, 100, 152 }) do recasts[i] = { kind = 'ability', recast_id = timer, remaining = 10 + i * 4 }; end
local entity = { GetPetTargetIndex = function() return 0x123; end, GetServerId = function() return 0x1000123; end,
    GetName = function() return 'Crab'; end, GetHPPercent = function() return 76; end };
local player = { GetPetMPPercent = function() return 40; end, GetPetTP = function() return 1250; end,
    GetStat = function() return 60; end, GetStatModifier = function() return 10; end };
AshitaCore.GetMemoryManager = function() return { GetEntity = function() return entity; end, GetPlayer = function() return player; end }; end;
local keeper = pet.new();
keeper:observe({ kind = 'check', entity_id = 0x1000123, level = 70 }, 0, snapshot);
keeper:observe({ kind = 'charm', entity_id = 0x1000123, items = {} }, 0, snapshot);
keeper:observe({ kind = 'maneuver', entity_id = self_id, maneuver = 300, percent = 23 }, 0, snapshot);
view.pet = keeper:refresh(0, s, snapshot, { [0x1000123] = { effects = effects } }, recasts);
assert(view.pet and view.pet.recast_count == 6 and view.pet.maneuver_count == 2, 'Fixture: a pet, its recasts and two lines of maneuvers.');
local filters = require('core.effect_filters');
local callbacks = { changed = nothing, effect_filters = filters.compile({ enabled = true, rules = {
    { enabled = true, effect = 253, kind = 'all', name = '', job = 0, scope = 'all' },
    { enabled = true, effect = 0, kind = 'buff', name = 'nobody', job = 0, scope = 'enemy' } } }) };
local moving = { shift = false, over_settings = false, mx = -1, my = -1, down = false, screen_width = 1920, screen_height = 1080, hover = false };

local now, leak, made = 0, false, nil;
local function frames(count)
    for i = 1, count do
        now = now + 1 / 60;
        roll_display.draw(view, s, now, callbacks, moving);
        pet_display.draw(view, s, now, callbacks, moving);
        -- Timers tick down and start over, as rows do, within the 40 s the clock runs before it starts over too.
        for _, row in ipairs(effects) do row.remaining = row.remaining > 1 and row.remaining - 1 / 60 or 38; end
        for _, row in ipairs(recasts) do row.remaining = row.remaining > 1 and row.remaining - 1 / 60 or 38; end
        if now > 40 then now = 0; end
        if leak and i % 6 == 0 then made = {}; end
    end
end
-- A full collection shrinks the Lua stack, and the next frames grow it back once, which is LuaJIT's and not a frame's,
-- so a few frames run after the collection, with the collector stopped, before counting starts.
local function measure(count)
    jit.off(); jit.flush();
    frames(60);
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    frames(6);
    local before = collectgarbage('count');
    frames(count);
    local each = (collectgarbage('count') - before) / count;
    collectgarbage('restart');
    jit.on();
    return each;
end
-- Warm, so every countdown text has been made once.
frames(2700);
local each = measure(600);
assert(each < 0.002, ('Drawing the two displays makes %.4f KB a frame; nothing expected'):format(each));
leak = true;
each = measure(600);
leak = false;
assert(each >= 0.002 and made, ('One table made ten times a second shows as %.4f KB a frame'):format(each));
-- The effects as a list, and a jug's clock in place of the charm, make nothing more.
s.pet.effects_as = 'list';
frames(600);
each = measure(600);
s.pet.effects_as = 'icons';
assert(each < 0.002, ('The effects as a list make %.4f KB a frame'):format(each));
local charm = view.pet.charm;
view.pet.charm, view.pet.jug = nil, { name = 'SheepFamiliar', seconds = 3600, deadline = 3000 };
frames(600);
each = measure(600);
view.pet.charm, view.pet.jug = charm, nil;
assert(each < 0.002, ('A jug\'s clock makes %.4f KB a frame'):format(each));
-- The samples refill their own tables, and so does the SAMPLE tag over them, so drawing them makes nothing more.
s.rolls.preview, s.pet.preview = true, true;
frames(600);
each = measure(600);
assert(each < 0.002, ('The samples make %.4f KB a frame'):format(each));
for _, job in ipairs({ 9, 14, 15, 18 }) do
    view.context = { job = job };
    frames(600);
    each = measure(600);
    assert(each < 0.002, ('The sample for job %d makes %.4f KB a frame'):format(job, each));
end
view.context = nil;
-- Over an open settings window the samples go on the foreground list, clipped as their windows clip
-- (resize.sample_list), and still make nothing.
s.window.open = true;
local over = 0;
local top = setmetatable({ PushClipRect = function() over = over + 1; end }, { __index = list });
rawset(imgui, 'GetForegroundDrawList', function() return top; end);
list.GetClipRectMin = function() return 0, 0; end;
list.GetClipRectMax = function() return 1920, 1080; end;
frames(600);
each = measure(600);
assert(over > 0 and each < 0.002, ('The samples over the settings window make %.4f KB a frame'):format(each));

-- With no art from the client, a picture leaves nothing in its place: no tile and no edge.
local icons = require('ui.icons');
local status, boxes = icons.status, 0;
list.AddRect = function() boxes = boxes + 1; end;
list.AddRectFilled = list.AddRect;
for name, display in pairs({ roll = roll_display, pet = pet_display }) do
    icons.status, boxes = status, 0;
    display.draw(view, s, now, callbacks, moving);
    local drawn, asked = boxes, 0;
    icons.status, boxes = function() asked = asked + 1; end, 0;
    display.draw(view, s, now, callbacks, moving);
    assert(asked > 0 and boxes == drawn, 'No tile where a ' .. name .. ' picture would go.');
end
icons.status = status;
return 'Drawing the Phantom Roll and pet displays makes nothing per frame';
