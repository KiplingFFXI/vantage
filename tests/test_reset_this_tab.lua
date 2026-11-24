-- Reset this tab, on every tab of every display, puts each row on that tab back as a fresh install has it. Every row is
-- changed first, then the button pressed, then each row read again.
local h = require('panel_fixture')();
local defaults = require('ui.defaults');
local panels = h.panels;
local ctx = panels.ctx;

local function same(a, b)
    if type(a) ~= type(b) then return false; end;
    if type(a) ~= 'table' then return a == b; end;
    for key, value in pairs(a) do if not same(value, b[key]) then return false; end; end;
    for key in pairs(b) do if a[key] == nil then return false; end; end;
    return true;
end;

-- The rows that hold a setting, in folds and lines too. A row of its own isn't a setting of the display.
local holds = { tick = true, number = true, pick = true, radio = true, color = true, text = true };
local function rows_of(list, out)
    for _, item in ipairs(list) do
        if item.rows then rows_of(item.rows, out); end;
        if holds[item.kind] and not item.own and not item.transient then out[#out + 1] = item; end;
    end;
    return out;
end;

local function holder(item) if item.of then return item.of(ctx); end; return ctx.p; end;
local function key(item) if item.key_of then return item.key_of(ctx); end; return item.key; end;
-- A row of a list with nothing picked, as an alert's with no alerts, has nothing to read.
local function read(item)
    local ok, value = pcall(function()
        if item.read then return defaults.copy(item.read(ctx)); end;
        local into = holder(item);
        if type(into) ~= 'table' then return nil; end;
        return defaults.copy(into[key(item)]);
    end);
    if not ok then return 'nothing to read'; end;
    return value;
end;

-- A value the row can take that isn't the one it has.
local function other(item, value)
    if item.kind == 'tick' then return not value; end;
    if item.kind == 'number' then
        local low = item.low_of and item.low_of(ctx) or item.low;
        local high = item.high_of and item.high_of(ctx) or item.high;
        if value ~= high then return high; end;
        return low;
    end;
    if item.kind == 'pick' or item.kind == 'radio' then
        for _, choice in ipairs(item.choices_of and item.choices_of(ctx) or item.choices or {}) do
            if choice ~= value then return choice; end;
        end;
        return nil;
    end;
    if item.kind == 'color' then return { 0.1, 0.2, 0.3, 0.4 }; end;
    return 'changed';
end;

local function set(item, value)
    if value == nil or item.refuse and item.refuse(ctx, value) then return; end;
    if item.write then item.write(ctx, value); return; end;
    local into = holder(item);
    if type(into) == 'table' then into[key(item)] = value; end;
end;

-- Rows that read a setting above the tabs too, which a tab's reset leaves as it is.
local above = {
    ['cooldown_list/show Beside the party list'] = 'It reads the watch\'s On, which the first tick turned on.',
    ['cooldown_list/show Over heads'] = 'The same.',
};

-- A fresh install's first frame puts each display at its first spot on the screen, the mock's 1600 by 900.
local function placed(saved) require('ui.setup_defaults').place_fresh(saved, { width = 1600, height = 900 }); end;

local problems, tabs, skipped = {}, 0, 0;
panels.index({});
for _, display in ipairs(panels._displays) do
    if not display.plain then
        for _, tab in ipairs(panels.tabs) do
            local list = display.tabs[tab.key];
            if list then
                h.fresh(placed);
                h.on(display.id, tab.key);
                -- A tab that can't do anything on a fresh save doesn't open, and the Show tab shows in its place.
                if panels.context() == display.id .. '/' .. tab.key then
                    tabs = tabs + 1;
                    local rows, before, changed = rows_of(list, {}), {}, {};
                    for index, item in ipairs(rows) do before[index] = read(item); end;
                    -- One at a time, each drawn, as a row can change which panel the next one edits. A row of something
                    -- picked, as an effect's or an alert's, has nothing to change on a fresh save.
                    for index, item in ipairs(rows) do
                        changed[index] = pcall(function() set(item, other(item, read(item))); end);
                        if not changed[index] then skipped = skipped + 1; end;
                        h.bump(); h.draw();
                    end;
                    h.draw('Reset this tab##frame');
                    h.draw();
                    for index, item in ipairs(rows) do
                        local name = display.id .. '/' .. tab.key .. ' ' .. tostring(item.text or item.key);
                        if changed[index] and not above[name] and not same(read(item), before[index]) then problems[#problems + 1] = name; end;
                    end;
                end;
            end;
        end;
    end;
end;
assert(tabs >= 40, 'Fixture: the tabs of every display opened: ' .. tabs);
assert(#problems == 0, 'Reset this tab left these changed:\n' .. table.concat(problems, '\n'));

-- Members and My order are drawn rows, which the walk above has nothing to change on. Each names what it writes.
h.fresh();
h.on('party', 'show');
h.s.panels.party.members[1002], h.s.panels.party.order[1] = true, 33;
h.bump(); h.draw();
h.draw('Reset this tab##frame');
h.draw();
assert(next(h.s.panels.party.members) == nil and #h.s.panels.party.order == 0, 'Reset this tab clears Members and My order.');
MOCK.fire('unload');
return ('Reset this tab puts every row back on %d tabs, past %d rows of something picked'):format(tabs, skipped);
