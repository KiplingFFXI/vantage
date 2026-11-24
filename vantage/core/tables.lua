-- Plain deep copy and deep equal for tables without cycles. It requires nothing, so any module can use it. A table
-- that can hold a cycle is copied with store.copy (core/store.lua).
local tables = {};

-- A copy of value at every level. A value that is no table comes back as it is.
local function copy(value)
    if type(value) ~= 'table' then return value; end
    local result = {};
    for k, v in pairs(value) do result[k] = type(v) == 'table' and copy(v) or v; end
    return result;
end
tables.copy = copy;

-- Whether a and b hold the same values at every level.
local function same(a, b)
    if type(a) ~= type(b) then return false; end
    if type(a) ~= 'table' then return a == b; end
    for key, value in pairs(a) do if not same(value, b[key]) then return false; end end
    for key in pairs(b) do if a[key] == nil then return false; end end
    return true;
end
tables.same = same;

return tables;
