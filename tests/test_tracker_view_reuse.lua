-- A view hands out a row's copy again while the row holds just what it did (core/tracker.lua), so a refresh doesn't copy
-- every row: in a full alliance that was about half a megabyte each tenth of a second. A row that changed gets a new
-- copy, each view has a list of its own, and what projecting a copy changed on it goes back at the next view.
package.loaded['core.catalog'] = {get = function(id)
    return {id = id, name = 'Effect ' .. id, kind = id < 32 and 'debuff' or 'buff', group = 'Test'};
end};
local Tracker = require('core.tracker');
local SELF, MOB = 10, 0x1000123;
local listed = {};
for index = 1, 24 do
    listed[index] = {effect = 39 + index, slot = index - 1, deadline = 200 + index, raw_timer = 12000 + index};
end;
local current = {valid = true, id = SELF, name = 'Self', zone = 1, self_known = true, self_revision = 1,
    self_effects = listed, party = {}, entities = {[MOB] = {id = MOB, name = 'Mob', kind = 'monster'}}};
local model = Tracker.new();
model:reconcile(current, 100);
model:observe({{kind = 'apply', entity_id = MOB, effect = 5, source = SELF, duration = 60}}, 100, current);
local first = model:view(100, {}, current);
model:drain_events();
local function row_of(view, id, effect)
    for _, row in ipairs(view.rows) do if row.entity_id == id and row.effect == effect then return row; end; end;
end;
assert(#first.rows == 25 and row_of(first, MOB, 5).remaining == 60, 'Fixture: 24 listed rows and a mob\'s debuff.');
local copies = {};
for _, row in ipairs(first.rows) do copies[row.key] = row; end;

-- Nothing changed: the same copies, in a list of its own, with the time left now.
local second = model:view(100.5, {}, current);
assert(second ~= first and second.rows ~= first.rows and second.subjects ~= first.subjects and #second.rows == 25,
    'Each view has its own list.');
for index, row in ipairs(second.rows) do
    assert(copies[row.key] == row and first.rows[index] == row, 'An unchanged row\'s copy is handed out again, in order.');
    assert(math.abs(row.remaining - (row.deadline - 100.5)) < 1e-9, 'Its time left is now\'s.');
end;
-- The app adds the recasts to the list it was given: the next view's list doesn't have them.
second.rows[#second.rows + 1] = {key = 'recast:10:spell:57', domain = 'recast'};
assert(#model:view(100.6, {}, current).rows == 25, 'What the app added to one view isn\'t in the next.');

-- A projection past the debuff's estimate marks its copy ended. The next view gives it its row's own status again.
local debuff = row_of(second, MOB, 5);
local status, reason = debuff.status, debuff.reason;
model:project(second, 170);
assert(debuff.status == 'unknown' and debuff.remaining == nil and debuff.reason ~= reason, 'Fixture: the projection ended it.');
local third = model:view(100.7, {}, current);
assert(row_of(third, MOB, 5) == debuff and debuff.status == status and debuff.reason == reason
    and math.abs(debuff.remaining - 59.3) < 1e-9, 'The next view gives the copy its row\'s status and time left again.');
-- Nor does anything else written on a copy stay into the next view.
local sequence = debuff.first_sequence;
debuff.first_sequence, debuff.written = -1, true;
assert(row_of(model:view(100.8, {}, current), MOB, 5) == debuff and debuff.first_sequence == sequence and debuff.written == nil,
    'A write on a copy goes at the next view.');

-- A row that changed gets a new copy, and only it does. Its old copy stays as it was.
listed[3].deadline, listed[3].raw_timer, current.self_revision = 400, 24000, 2;
model:reconcile(current, 101);
local fourth = model:view(101, {}, current);
local changed = row_of(fourth, SELF, 42);
local old = copies[changed.key];
assert(changed ~= old and changed.deadline == 400 and old.deadline == 203, 'The changed row has a new copy.');
for _, row in ipairs(fourth.rows) do
    if row ~= changed then assert(copies[row.key] == row, 'The rows that didn\'t change keep theirs.'); end;
end;
-- Each copy holds what its row does, as a full copy would.
local function same(view)
    for _, entity in pairs(model.entities) do
        for _, held in ipairs(entity.entries) do
            local shown;
            for _, row in ipairs(view.rows) do if row.key == held.key then shown = row; end; end;
            for key, value in pairs(held) do
                if type(value) ~= 'table' then assert(shown[key] == value, 'The copy of ' .. held.key .. ' has its ' .. key .. '.'); end;
            end;
        end;
    end;
end;
same(fourth);

-- A row that went takes its record with it, and the next view has its copy no more.
table.remove(listed, 24);
current.self_revision = 3;
model:reconcile(current, 102);
model:drain_events();
local fifth = model:view(102, {}, current);
assert(#fifth.rows == 24 and not row_of(fifth, SELF, 63), 'The row that went is gone.');
same(fifth);
local records = 0;
for _ in pairs(model.records) do records = records + 1; end;
assert(records == 24 and next(model.spare_records) == nil, 'One record for each row there is, and nothing kept for the gone one.');

-- A view of rows that didn't change makes a list, not 24 copies.
collectgarbage('collect'); collectgarbage('collect');
collectgarbage('stop');
local before = collectgarbage('count');
for step = 1, 20 do model:view(102 + step / 10, {}, current); end;
local each = (collectgarbage('count') - before) / 20;
collectgarbage('restart');
assert(each < 3, ('A view of 24 unchanged rows makes %.1f KB, at most 3 expected'):format(each));
return 'A view hands out an unchanged row\'s copy again';
