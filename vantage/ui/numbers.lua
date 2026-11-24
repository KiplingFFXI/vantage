-- The number checks and clamps the ui modules share. It requires nothing, so any module can use it, including
-- the font modules. Every clamp takes (value, low, high, fallback) and returns fallback unchanged when value
-- isn't a finite number; they differ only in how they round a kept value.
-- At the end are the small helpers the settings tidies share.
local numbers = {};
local floor, max, min, huge = math.floor, math.max, math.min, math.huge;

function numbers.finite(value)
    return type(value) == 'number' and value == value and value ~= huge and value ~= -huge;
end

function numbers.clamp(value, low, high, fallback)
    if not numbers.finite(value) then return fallback; end
    return max(low, min(high, value));
end

-- Down to a whole number.
function numbers.clamp_floor(value, low, high, fallback)
    if not numbers.finite(value) then return fallback; end
    return floor(max(low, min(high, value)));
end

-- To the nearest whole number, halves up.
function numbers.clamp_round(value, low, high, fallback)
    if not numbers.finite(value) then return fallback; end
    return floor(max(low, min(high, value)) + 0.5);
end

-- value when it is a table, else a new empty one.
function numbers.table_of(value) return type(value) == 'table' and value or {}; end

-- value when choices lists it, else fallback.
function numbers.choice(value, choices, fallback)
    for _, item in ipairs(choices) do if value == item then return value; end end
    return fallback;
end

-- A color of four parts from 0 to 1, each the fallback's where value has none. object, when true, also reads a part
-- saved as text ("1" to "4") where the number key has none, as a color given as an object holds it. out, when given,
-- is filled and handed back in place of a new table.
local NO_COLOR = {};
function numbers.rgba(value, fallback, out, object)
    out, value = out or {}, type(value) == 'table' and value or NO_COLOR;
    for i = 1, 4 do
        local part = value[i];
        if object and not part then part = value[tostring(i)]; end
        out[i] = numbers.clamp(part, 0, 1, fallback[i]);
    end
    return out;
end

-- Effect ids 1 to 1023 as a sorted list without repeats, from a list or from a set. fold, when given, turns an id into
-- the one it stands for. At most 256 are kept.
function numbers.effect_list(value, fold)
    local seen, result = {}, {};
    value = numbers.table_of(value);
    local function add(id)
        id = tonumber(id);
        if numbers.finite(id) and id >= 1 and id <= 1023 and id == floor(id) then
            id = fold and fold[id] or id;
            if not seen[id] then seen[id], result[#result + 1] = true, id; end
        end
    end
    for key, on in pairs(value) do if on == true then add(key); end end
    for _, id in ipairs(value) do add(id); end
    table.sort(result);
    for index = #result, 257, -1 do result[index] = nil; end
    return result;
end

return numbers;
