-- ui.numbers: one finite check and one clamp per rounding rule, and saved settings still rounding as each tidy did.
local numbers = require('ui.numbers');
for _, value in ipairs({ 0, -5, 1.5, 1e300, -1e300 }) do assert(numbers.finite(value), tostring(value)); end
for _, value in ipairs({ 0 / 0, math.huge, -math.huge, '5', nil, true, {} }) do assert(not numbers.finite(value), tostring(value)); end

assert(numbers.clamp(5.5, 1, 9, 3) == 5.5 and numbers.clamp(-1, 1, 9, 3) == 1 and numbers.clamp(20, 1, 9, 3) == 9);
assert(numbers.clamp_floor(5.7, 1, 9, 3) == 5 and numbers.clamp_floor(0.2, 1.5, 9, 3) == 1 and numbers.clamp_floor(9.9, 1, 9.5, 3) == 9);
assert(numbers.clamp_round(5.5, 1, 9, 3) == 6 and numbers.clamp_round(5.49, 1, 9, 3) == 5 and numbers.clamp_round(-2, 1, 9, 3) == 1);
for _, clamp in ipairs({ numbers.clamp, numbers.clamp_floor, numbers.clamp_round }) do
    for _, value in ipairs({ 0 / 0, math.huge, -math.huge, '5', nil, false }) do
        assert(clamp(value, 1, 9, 2.5) == 2.5, 'A value that is not a finite number takes the fallback as it is.');
    end
    assert(clamp(0 / 0, 1, 9, 100) == 100, 'The fallback is not clamped.');
end

-- Each tidy keeps its own rounding: the main settings round whole-number keys halves up, and party settings round
-- them down.
local defaults = require('ui.defaults');
local s = defaults.make();
s.style.window_type, s.style.font_size, s.style.opacity = 4.5, 17.5, 'dim';
s = defaults.tidy(s);
assert(s.style.window_type == 5 and s.style.font_size == 17.5 and s.style.opacity == 0.92);
s.style.window_type = 4.49; s = defaults.tidy(s); assert(s.style.window_type == 4);
local party = require('ui.party_defaults');
local p = party.make();
p.native.width, p.name_length, p.effects.icon_size, p.effects.max = 250.9, 5.9, 1e9, 0 / 0;
p = party.tidy(p);
assert(p.native.width == 250 and p.name_length == 5 and p.effects.icon_size == 128 and p.effects.max == 12);
p.native.width = 20; p = party.tidy(p); assert(p.native.width == 40);
p.style.opacity = 0.333; p = party.tidy(p); assert(p.style.opacity == 0.333, 'Fractions stay fractions.');

-- The client frame font's glyphs are 11 of its 16 pixels tall.
