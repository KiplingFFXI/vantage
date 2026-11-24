-- A strip row's cells, kept from frame to frame (layout.kept_cells): when a countdown's text ticks they're worked out
-- again into the same tables, or take the new countdowns in place where the cells keep their places, as the cells a new
-- list would have, with nothing left over from before. Fewer effects drop the cells past them.
local layout, party = require('ui.party_layout'), require('ui.party_defaults');
local options = party.make().effects;
options.timers, options.icon_countdown_position, options.measure_key = true, 'below', 'test';
local function effects(times)
    local out = {};
    for index, left in ipairs(times) do out[index] = { effect = index, name = 'Effect ' .. index, remaining = left, total = 3600, kind = 'buff' }; end;
    return out;
end;
local function as_new(cells, list, rect, when)
    local fresh = layout.effect_cells(list, options, rect);
    assert(#cells == #fresh, when .. ': as many cells as a new list has.');
    for index, cell in ipairs(fresh) do
        for field, value in pairs(cell) do assert(cells[index][field] == value, when .. ': cell ' .. index .. '\'s ' .. field .. ' is as a new list has it.'); end;
        for field in pairs(cells[index]) do assert(cell[field] ~= nil, when .. ': cell ' .. index .. ' keeps no ' .. field .. ' from before.'); end;
    end;
end;

local holder, rect = {}, { x = 100, y = 50, width = 300, height = 2048 };
local list = effects({ 3000, 125, 59 });
local cells = layout.kept_cells(holder, list, options, rect);
as_new(cells, list, rect, 'First');
local first = cells[1];
assert(first.countdown and cells[2].countdown, 'Fixture: the cells have countdowns.');

-- A countdown ticks over, and another ends with no time left to show.
list[3].remaining, list[2].remaining = 58, nil;
local again = layout.kept_cells(holder, list, options, rect);
assert(again == cells and again[1] == first, 'A countdown that ticks fills the same cells again.');
as_new(again, list, rect, 'Ticked');

-- Fewer effects, in a moved area.
list = effects({ 3000, 125 });
rect.x = 140;
again = layout.kept_cells(holder, list, options, rect);
assert(again == cells and again[1] == first and again[3] == nil, 'Fewer effects drop the cells past them.');
as_new(again, list, rect, 'Fewer');

-- Beside the game's rows (a fixed countdown slot) and inside the icon, no countdown can widen the column, so one that
-- ticks over to a text of the same shape is taken in place: the plan isn't worked out again, and the cells are as a new
-- list has them. A countdown that goes works the plan out again.
for _, place in ipairs({ { true, 'below' }, { false, 'inside' } }) do
    options.fixed_countdown_slot, options.icon_countdown_position = place[1], place[2];
    local when = place[2] .. (place[1] and ', in a fixed slot' or '');
    local row, area = {}, { x = 100, y = 50, width = 300, height = 60 };
    list = effects({ 3000, 59, 45 });
    cells = layout.kept_cells(row, list, options, area);
    as_new(cells, list, area, when);
    assert(#cells == 3 and cells[2].countdown and cells[3].countdown, 'Fixture: three cells with countdowns, ' .. when);
    local plan = row.saved;
    list[2].remaining, list[3].remaining = 57.5, 44;
    again = layout.kept_cells(row, list, options, area);
    assert(again == cells and row.saved == plan, 'Ticking over takes the new countdowns in place, ' .. when);
    assert(again[2].countdown.lines[1].text == '58s' and again[3].countdown.lines[1].text == '44s', 'The new texts show, ' .. when);
    as_new(again, list, area, 'Ticked in place, ' .. when);
    list[3].remaining = nil;
    again = layout.kept_cells(row, list, options, area);
    assert(again == cells and row.saved ~= plan and again[3].countdown == nil, 'A countdown that goes works the plan out again, ' .. when);
    as_new(again, list, area, 'Gone, ' .. when);
end;

-- A tick that changes a countdown's shape works the plan out again. Here a text with an h is taller than the rest, as
-- a bitmap font's ink can be, and the fixed slot fits only the shorter texts, so 1h falls back inside its icon and 59m
-- fits below it.
local metrics = require('ui.text_metrics');
local measured = metrics.countdown;
metrics.countdown = function(_, value) return #tostring(value) * 5, tostring(value):find('h', 1, true) and 14 or 10; end;
options.fixed_countdown_slot, options.icon_countdown_position, options.measure_key = true, 'below', 'test shape';
options.icon_size, options.icon_countdown_size, options.icon_countdown_gap = 20, 10, 0;
local row, area = {}, { x = 100, y = 50, width = 300, height = 32 };
list = effects({ 3601, 3601 });
cells = layout.kept_cells(row, list, options, area);
as_new(cells, list, area, 'Before the shape changes');
assert(#cells == 2 and cells[1].countdown.fallback and cells[1].height == 20, 'Fixture: 1h falls back inside its icon.');
local plan = row.saved;
list[1].remaining, list[2].remaining = 3599, 3599;
again = layout.kept_cells(row, list, options, area);
assert(again == cells and row.saved ~= plan, 'A tick that changes a countdown\'s shape works the plan out again.');
as_new(again, list, area, 'Shape changed');
assert(again[1].countdown.below and again[1].height > 20, 'Fixture: 59m fits below its icon.');
-- With room for both under the icon, 1h and 59m stay below it but not at the same height, so the tick still works the
-- plan out again and the cells come out as a new list has them.
options.measure_key = 'test height';
row, area = {}, { x = 100, y = 50, width = 300, height = 40 };
list = effects({ 3601, 3601 });
cells = layout.kept_cells(row, list, options, area);
assert(cells[1].countdown.below and not cells[1].countdown.fallback, 'Fixture: 1h fits below its icon.');
plan = row.saved;
list[1].remaining, list[2].remaining = 3599, 3599;
again = layout.kept_cells(row, list, options, area);
assert(row.saved ~= plan and again[1].countdown.below, 'A tick that only changes a countdown\'s height works the plan out again.');
as_new(again, list, area, 'Height changed');
metrics.countdown = measured;
return 'A strip row\'s kept cells are filled again when a countdown ticks';
