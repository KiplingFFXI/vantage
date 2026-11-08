-- Head heights and icon sizes for overhead icons, against docs/OVERHEAD.md: the race table, posture, the mob hitbox
-- line and its clamps, the name overrides and offsets, and the section 3.3 sizes at 1080p.
local overhead = require('core.overhead');
local config = require('ui.overhead_defaults').make();
local head = config.head;
local function near(a, b) return math.abs(a - b) < 1e-9; end

-- Players stand by race; race 0 or another one stands as a Hume man.
for race, expected in ipairs({ 1.80, 1.70, 2.05, 1.95, 1.00, 1.00, 1.55, 2.05 }) do
    local height, source = overhead.head_height(true, race, 0, 0.4, 'Member', head, 0);
    assert(near(height, expected) and source == 'race', ('race %d stands at %.2f, not %.2f'):format(race, expected, height));
end
assert(near(overhead.head_height(true, 0, 0, 0.4, 'Odd', head, 0), 1.80), 'Race 0 stands as the default.');
-- Mounted is 1.35 + 0.55 H, on a chocobo (5) or a mount (85); sitting or healing 0.6 H; a chair 0.75 H.
assert(near(overhead.head_height(true, 8, 5, 0.8, 'Galka', head, 0), 1.35 + 0.55 * 2.05), 'A mounted Galka.');
assert(near(overhead.head_height(true, 5, 85, 0.3, 'Taru', head, 0), 1.35 + 0.55 * 1.00), 'A Tarutaru on a mount.');
assert(near(overhead.head_height(true, 7, 33, 0.4, 'Mithra', head, 0), 1.55 * 0.6), 'Healing sits.');
assert(near(overhead.head_height(true, 7, 47, 0.4, 'Mithra', head, 0), 1.55 * 0.6), 'Sitting.');
assert(near(overhead.head_height(true, 1, 63, 0.4, 'Hume', head, 0), 1.80 * 0.75), 'In a chair.');
assert(near(overhead.head_height(true, 1, 73, 0.4, 'Hume', head, 0), 1.80 * 0.75), 'In a chair.');
assert(near(overhead.head_height(true, 1, 1, 0.4, 'Hume', head, 0), 1.80), 'Engaged stands.');

-- Mobs: 0.6 + 1.0 per hitbox yalm, clamped 1.2 to 8.0; no hitbox reads as 1.5 (the doc's 2.3 table).
for _, case in ipairs({ { 0.3, 1.2 }, { 1.1, 1.7 }, { 1.2, 1.8 }, { 1.5, 2.1 }, { 1.7, 2.3 }, { 2.3, 2.9 }, { 3.0, 3.6 },
    { 3.4, 4.0 }, { 3.8, 4.4 }, { 4.2, 4.8 }, { 4.5, 5.1 }, { 5.0, 5.6 }, { 5.7, 6.3 }, { 0, 2.1 }, { 9.0, 8.0 } }) do
    local height, source = overhead.head_height(false, 0, 1, case[1], 'Mob', head, 0);
    assert(near(height, case[2]) and source == 'hitbox', ('hitbox %.1f gives %.2f, not %.2f'):format(case[1], height, case[2]));
end
-- Pets use the same line: a wyvern (0.8) 1.4, an avatar (3.0) 3.6.
assert(near(overhead.head_height(false, 0, 0, 0.8, 'Wyvern', head, 0), 1.4));
assert(near(overhead.head_height(false, 0, 0, 3.0, 'Ifrit', head, 0), 3.6));
-- A mob doesn't sit, whatever its status says.
assert(near(overhead.head_height(false, 0, 33, 1.5, 'Mob', head, 0), 2.1), 'Posture is for players.');
-- A unit that isn't a player goes by its hitbox, whatever race the client says it has.
assert(near(overhead.head_height(false, 5, 0, 0.8, 'Odd pet', head, 0), 1.4), 'A race is for players.');

-- heights[name] replaces the standing height or the line; offsets[name] and the type's offset are added.
head.heights['Wild Rabbit'], head.offsets['Wild Rabbit'] = 1.0, -0.25;
local height, source = overhead.head_height(false, 0, 0, 1.1, 'Wild Rabbit', head, 0.5);
assert(near(height, 1.0 - 0.25 + 0.5) and source == 'name', 'A name height with its offset and the type offset.');
head.heights.Tester = 1.5;
assert(near(overhead.head_height(true, 1, 5, 0.4, 'Tester', head, 0), 1.35 + 0.55 * 1.5), 'A player name height still mounts.');
assert(near(overhead.head_height(false, 0, 0, 1.2, 'Goblin Mugger', head, -1), 0.8), 'A type offset lowers it.');
head.heights, head.offsets = {}, {};

-- Sizes at 1080p, style scale 1, against the doc's 3.3 table: raw, then as drawn on whole pixels, and as the target.
local function size(player, race, hitbox, depth, target)
    return overhead.icon_size(player, race, hitbox, 'Unit', depth, target, config, 1, 1);
end
local function px(value) return math.floor(value + 0.5); end
local cases = {
    { 'Tarutaru player', true, 5, 0.3, { 28, 16, 14 }, { 33, 19, 14 } },
    { 'Galka player', true, 8, 0.8, { 36, 21, 15 }, { 40, 25, 18 } },
    { 'Goblin Mugger', false, 0, 1.2, { 28, 16, 14 }, { 33, 19, 14 } },
    { 'Fafnir', false, 0, 4.2, { 40, 29, 20 }, { 40, 34, 24 } },
    { 'Nidhogg', false, 0, 5.0, { 40, 29, 20 }, { 40, 34, 24 } },
};
for _, case in ipairs(cases) do
    for index, depth in ipairs({ 5, 15, 30 }) do
        local plain, aimed = px(size(case[2], case[3], case[4], depth, false)), px(size(case[2], case[3], case[4], depth, true));
        assert(plain == case[5][index], ('%s at depth %d is %d px, not %d'):format(case[1], depth, plain, case[5][index]));
        assert(aimed == case[6][index], ('%s as target at depth %d is %d px, not %d'):format(case[1], depth, aimed, case[6][index]));
    end
end
-- The raw values before the clamp, at depth 5: Tarutaru 27.8, Galka 35.9 (the doc rounds to one place).
assert(math.abs(size(true, 5, 0.3, 5, false) - 27.8) < 0.05 and math.abs(size(true, 8, 0.8, 5, false) - 35.9) < 0.05);
-- Dragon against Tarutaru at depth 15: 1.6 / 0.894 until a clamp bites.
assert(math.abs(size(false, 0, 4.2, 15, false) / size(true, 5, 0.3, 15, false) - 1.6 / math.sqrt(1.2 / 1.5)) < 1e-6);
-- A mob with no hitbox sizes as the 1.5 median; an elemental (0.3) at the 0.85 floor.
assert(near(size(false, 0, 0, 10, false), 22), 'No hitbox sizes as the median, 22 px at the reference depth.');
assert(near(size(false, 0, 0.3, 10, false), 22 * 0.85), 'An elemental sits on the size floor.');
-- A unit that isn't a player sizes by its hitbox, whatever race the client says it has.
assert(near(size(false, 5, 0.8, 10, false), size(false, 0, 0.8, 10, false)), 'A race is for players.');
-- A name factor multiplies the size class, past its clamp; a type's size_scale before the px clamp; ui after it.
config.head.sizes.Unit = 1.25;
assert(near(size(false, 0, 1.5, 10, false), 22 * 1.25), 'A name factor.');
config.head.sizes = {};
assert(near(overhead.icon_size(false, 0, 1.5, 'Unit', 10, false, config, 1, 1.5), 33), 'A type scale.');
assert(near(overhead.icon_size(false, 0, 1.5, 'Unit', 10, false, config, 2, 1), 44), 'ui scales after the clamp.');
assert(near(overhead.icon_size(false, 0, 1.5, 'Unit', 2, false, config, 2, 1), 80), 'The clamp is before ui: 40 px times 2.');
-- Fixed size with alpha 0, all units equal with beta 0.
config.size.alpha, config.size.beta = 0, 0;
assert(near(size(false, 0, 4.2, 30, false), 22) and near(size(true, 5, 0.3, 3, false), 22));

-- The fade: full to 20 yalms, then down to half at the 30 yalm cap; the target never fades.
local base = require('ui.overhead_defaults').make();
assert(overhead.fade(10, false, base) == 1 and overhead.fade(20, false, base) == 1, 'Full up to fade_start.');
assert(near(overhead.fade(25, false, base), 0.75) and near(overhead.fade(30, false, base), 0.5), 'Linear to fade_alpha at the cap.');
assert(overhead.fade(30, true, base) == 1, 'The target is exempt.');
