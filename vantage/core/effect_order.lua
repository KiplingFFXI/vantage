local order = {};

local function known(value)
    return type(value) == 'number' and value == value and math.abs(value) < math.huge and value or math.huge;
end;

function order.oldest(a, b)
    local first, second = known(a.first_seen), known(b.first_seen);
    if first ~= second then return first < second; end;
    first, second = known(a.first_sequence), known(b.first_sequence);
    if first ~= second then return first < second; end;
    return nil;
end;

local function remaining(row)
    if tonumber(row.effect) == 269 and row.domain ~= 'recast' then return -1; end;
    local value = row.remaining;
    return type(value) == 'number' and value == value and value >= 0 and value < math.huge and value or -1;
end;

function order.longest(a, b)
    local first, second = remaining(a), remaining(b);
    if first ~= second then return first > second; end;
    return nil;
end;

return order;
