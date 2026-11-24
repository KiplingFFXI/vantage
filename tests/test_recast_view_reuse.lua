-- Each refresh vantage.lua asks for a recast view (core/recasts.lua), and a view copied every recast row into new
-- tables: with twenty spells and four abilities running, about 20 KB each tenth of a second. A view now hands out the
-- same list and the same copy of each row, refilled from its row. A copy holds what its row does, what was written on
-- it goes at the next view, and a new use of a recast gets a new copy, so one held from before keeps what it had.
local spells, slots = {}, {};
-- Twenty spells on data/actions.lua's list, as a spell off it isn't read.
local RUNNING = { 1, 2, 3, 4, 5, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 23 };
local manager = {
    GetSpellTimer = function(_, id) return spells[id] or 0; end,
    GetAbilityTimerId = function(_, slot) return slots[slot] and slots[slot].id or 0; end,
    GetAbilityTimer = function(_, slot) return slots[slot] and slots[slot].timer or 0; end,
};
local memory = { GetRecast = function() return manager; end, GetInventory = function() return nil; end };
AshitaCore.GetMemoryManager = function() return memory; end;
local spell_names, ability_names = {}, {};
for id = 1, 40 do spell_names[id] = { Name = { 'Spell ' .. id }, ListIconNQ = id, ListIconHQ = id }; end;
for id = 1, 8 do ability_names[512 + id] = { Name = { 'Ability ' .. id }, RecastTimerId = id, ListIconId = id, Element = 1, Id = 512 + id }; end;
AshitaCore.GetResourceManager = function() return {
    GetSpellById = function(_, id) return spell_names[id]; end,
    GetAbilityById = function(_, id) return ability_names[id]; end,
    GetAbilityByTimerId = function() return nil; end }; end;
local model = require('core.recasts').new();
local tints = require('core.recast_tints');
local settings = { recast_tints = tints.make() };
local snapshot = { valid = true, id = 1001, zone = 230, job = 4, name = 'Aster', mp = 500, self_effects = {} };
local options = { spells = true, abilities = true, items = false };
local now = 100;
model:update(snapshot, now, options);
-- Twenty spells and four abilities start.
for _, id in ipairs(RUNNING) do spells[id] = 60 * 600; end;
for slot = 1, 4 do slots[slot] = { id = slot, timer = 60 * 900 }; end;
now = now + 0.1;
model:update(snapshot, now, options);
assert(#model:view(now).rows == 24, 'Fixture: 24 recasts are running.');

-- The view of a refresh, tinted as vantage.lua tints it.
local function refresh()
    now = now + 0.1;
    local view = model:view(now);
    tints.mark(view.rows, snapshot, settings);
    return view;
end
for _ = 1, 50 do refresh(); end;
collectgarbage('collect'); collectgarbage('collect');
collectgarbage('stop');
local before = collectgarbage('count');
for _ = 1, 100 do refresh(); end;
local each = (collectgarbage('count') - before) / 100;
collectgarbage('restart');
assert(each < 0.5, ('A recast view of 24 rows makes %.2f KB a refresh, at most 0.5 expected'):format(each));

-- A sample counts the timers down (vantage.lua samples at the same refresh), and the next view has each row's copy
-- again, in key order, with the row's own values and the time left now.
local function sample(seconds)
    now = now + seconds;
    for _, id in ipairs(RUNNING) do if spells[id] > 0 then spells[id] = math.max(0, spells[id] - math.floor(seconds * 60 + 0.5)); end; end;
    for slot = 1, 4 do slots[slot].timer = math.max(0, slots[slot].timer - math.floor(seconds * 60 + 0.5)); end;
    model:update(snapshot, now, options);
end
local function by_key(view)
    local result = {};
    for _, row in ipairs(view.rows) do result[row.key] = row; end;
    return result;
end
local function holds_its_row(view)
    for key, held in pairs(model.rows) do
        local shown;
        for _, row in ipairs(view.rows) do if row.key == held.key then shown = row; end; end;
        assert(shown, 'The view has a copy of ' .. key .. '.');
        for field, value in pairs(held) do
            if field ~= 'remaining' then assert(shown[field] == value, 'The copy of ' .. key .. ' has its ' .. field .. '.'); end;
        end;
        assert(math.abs(shown.remaining - (held.deadline - now)) < 1e-9, 'The copy of ' .. key .. ' has the time left now.');
    end;
end
-- Fifteen seconds of views with no sample is a pause, which the first sample after starts again from.
sample(0.1);
local first = refresh();
local copies = by_key(first);
sample(0.1);
local second = refresh();
assert(#second.rows == 24 and second.version == model.version and second.valid == model.valid, 'The view is the model\'s.');
for index, row in ipairs(second.rows) do
    assert(copies[row.key] == row, 'A running recast\'s copy is handed out again.');
    if index > 1 then assert(second.rows[index - 1].key < row.key, 'The rows stay in key order.'); end;
end;
holds_its_row(second);

-- A projection past a deadline marks the copy waiting, and anything else written on it stays only until the next view.
local spell = copies['recast:1001:spell:1'];
model:project(second, now + 700);
assert(spell.status == 'unknown' and spell.remaining == nil, 'Fixture: the projection ended it.');
spell.written, spell.locked, spell.name = true, true, 'Changed';
sample(0.1);
local third = refresh();
assert(by_key(third)[spell.key] == spell and spell.status == 'server' and spell.written == nil and spell.locked == nil
    and spell.name == 'Spell 1', 'What was written on a copy goes at the next view.');
holds_its_row(third);

-- Used again, a recast's row starts over and its copy is a new one. The old copy keeps the use it had.
local instance, total = spell.instance, spell.total;
spells[1] = 60 * 900;
sample(0.1);
local fourth = refresh();
local again = by_key(fourth)[spell.key];
assert(again ~= spell and again.instance ~= instance and again.total > 899, 'A new use has a new copy.');
assert(spell.instance == instance and spell.total == total, 'The old copy keeps what it had.');
for _, row in ipairs(fourth.rows) do
    if row ~= again then assert(copies[row.key] == row, 'The others keep theirs.'); end;
end;
holds_its_row(fourth);

-- A recast that ends leaves the list, with nothing left past its new end.
spells[2] = 0;
sample(0.1);
local fifth = refresh();
assert(#fifth.rows == 23 and fifth.rows[24] == nil and not by_key(fifth)['recast:1001:spell:2'], 'A recast that ended leaves the list.');
assert(fifth.version == model.version, 'The view has the model\'s new version.');
holds_its_row(fifth);
-- Back on cooldown, it has a new copy.
local gone = copies['recast:1001:spell:2'];
spells[2] = 60 * 600;
sample(0.1);
local sixth = refresh();
assert(#sixth.rows == 24 and by_key(sixth)['recast:1001:spell:2'] ~= gone, 'A recast that comes back has a new copy.');
holds_its_row(sixth);

-- A zone change drops every row, and the next view is empty.
model:reset();
local seventh = model:view(now);
assert(#seventh.rows == 0 and seventh.rows[1] == nil and seventh.valid == false, 'A reset leaves an empty view.');
return 'A recast view reuses its copies and stays as a full copy would be';
