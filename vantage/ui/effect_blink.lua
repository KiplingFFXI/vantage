local bit = require('bit');
local blink = {};
local phase_time, phase_brightness;

local finite = require('ui.numbers').finite;

function blink.brightness(effect, options, now)
    if not effect or options and options.blink_icons == false or not finite(now) or now < 0
        or effect.domain == 'recast' or tonumber(effect.effect) == 269 or effect.present == false
        or effect.status ~= 'server' and effect.status ~= 'estimated' then return 1; end;
    local remaining = effect.remaining;
    if effect.deadline ~= nil then
        if not finite(effect.deadline) then return 1; end;
        remaining = effect.deadline - now;
    end;
    if not finite(remaining) or remaining <= 0 then return 1; end;
    local threshold = options and options.blink_seconds;
    threshold = finite(threshold) and math.max(1, math.min(300, math.floor(threshold))) or 15;
    if math.ceil(remaining) > threshold then return 1; end;
    if phase_time ~= now then
        -- A clock-based phase keeps every icon on the same pulse. The client's blink: a 0.7 second cycle of 42 sixtieths,
        -- rising and falling over the first 40. Each color runs from 64 up to 128, and 128 is the icon at full brightness.
        local phase = math.min(40, (now * 60) % 42);
        phase_time = now;
        phase_brightness = (64 + math.floor(math.min(phase, 40 - phase) * 3.2 + 0.000001)) / 128;
    end;
    return phase_brightness;
end;

function blink.tint(effect, options, now, ink)
    local brightness = blink.brightness(effect, options, now);
    if brightness == 1 then return ink; end;
    -- The client dims RGB while keeping the icon's opacity unchanged.
    return bit.bor(bit.band(ink, 0xFF000000),
        math.floor(bit.band(ink, 0xFF) * brightness),
        bit.lshift(math.floor(bit.band(bit.rshift(ink, 8), 0xFF) * brightness), 8),
        bit.lshift(math.floor(bit.band(bit.rshift(ink, 16), 0xFF) * brightness), 16));
end;

return blink;
