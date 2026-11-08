local cache = {};

-- Fixed-size FIFO storage keeps changing labels and profiles from accumulating.
function cache.new(capacity)
    local values, slots, next_slot, count = {}, {}, 1, 0;
    local result = {};
    function result:get(key) return values[key]; end;
    function result:put(key, value)
        if values[key] == nil then
            local old = slots[next_slot];
            if old then values[old] = nil; else count = count + 1; end;
            slots[next_slot], next_slot = key, next_slot % capacity + 1;
        end;
        values[key] = value;
        return value;
    end;
    function result:count() return count; end;
    return result;
end;

-- One piece list for every key: table.concat writes numbers as tostring does, so a key makes one new string.
-- Each piece starts with its type, and strings carry their length, so two argument lists never share a key.
local pieces = {};
function cache.key(...)
    local count = 0;
    for index = 1, select('#', ...) do
        local value = select(index, ...);
        local kind = type(value);
        if kind == 'number' then
            pieces[count + 1], pieces[count + 2], pieces[count + 3] = 'n', value, ';';
            count = count + 3;
        elseif kind == 'string' then
            pieces[count + 1], pieces[count + 2], pieces[count + 3], pieces[count + 4] = 's', #value, ':', value;
            count = count + 4;
        elseif kind == 'boolean' then
            pieces[count + 1] = value and 't' or 'f';
            count = count + 1;
        elseif value == nil then
            pieces[count + 1] = 'z';
            count = count + 1;
        else
            local text = tostring(value);
            pieces[count + 1], pieces[count + 2], pieces[count + 3], pieces[count + 4] = 'o', #text, ':', text;
            count = count + 4;
        end;
    end;
    return table.concat(pieces, '', 1, count);
end;

local function same(a, b, ignored)
    if a == b then return true; end;
    if type(a) ~= 'table' or type(b) ~= 'table' then return false; end;
    for key, value in pairs(a) do if not (ignored and ignored[key]) and not same(value, b[key]) then return false; end; end;
    for key in pairs(b) do if not (ignored and ignored[key]) and a[key] == nil then return false; end; end;
    return true;
end;

-- ignored names top-level keys of each field whose changes don't count.
function cache.revisions(capacity, fields, ignored)
    local retained, sequence = cache.new(capacity), 0;
    return function(value, identity)
        local store = require('core.store');
        identity = identity or value;
        local saved = retained:get(identity);
        local changed = saved == nil;
        if saved then
            for _, field in ipairs(fields) do
                if not same(saved.values[field], value[field], ignored) then changed = true; break; end;
            end;
        end;
        if changed then
            local copied = {};
            for _, field in ipairs(fields) do copied[field] = store.copy(value[field]); end;
            sequence = sequence + 1;
            saved = retained:put(identity, {values=copied,revision=sequence});
        end;
        return saved.revision;
    end;
end;

return cache;
