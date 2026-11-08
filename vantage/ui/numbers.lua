-- The number checks and clamps the ui modules share. It requires nothing, so any module can use it, including
-- the font modules. Every clamp takes (value, low, high, fallback) and returns fallback unchanged when value
-- isn't a finite number; they differ only in how they round a kept value.
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

return numbers;
