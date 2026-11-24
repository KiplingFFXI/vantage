-- A color given as an object ("1" to "4", from a hand edit or /vg set) reads as each tidy has always read it: the pet
-- display, Phantom Roll and overhead icons tidies read its parts, and the recast tints, the ready pulse and the panels
-- read number keys only and take the default.
local object = { ['1'] = 0.2, ['2'] = 0.3, ['3'] = 0.4, ['4'] = 0.5 };
local function kept(color) return color[1] == 0.2 and color[2] == 0.3 and color[3] == 0.4 and color[4] == 0.5; end
local function same(color, fallback)
    for i = 1, 4 do if color[i] ~= fallback[i] then return false; end end
    return true;
end
local function copy(value) local out = {}; for key, item in pairs(value) do out[key] = item; end return out; end

local pet = require('core.pet');
local tidy = pet.tidy({ hp_color = copy(object) });
assert(kept(tidy.hp_color), 'The pet display keeps a color object.');
local rolls = require('core.rolls');
tidy = rolls.tidy({ lucky_color = copy(object) });
assert(kept(tidy.lucky_color), 'Phantom Roll keeps a color object.');
local overhead = require('ui.overhead_defaults');
tidy = overhead.tidy({ countdown_color = copy(object), dispel_color = copy(object), countdown_outline_color = copy(object) });
assert(kept(tidy.countdown_color) and kept(tidy.dispel_color) and kept(tidy.countdown_outline_color), 'Overhead icons keep a color object.');

local tints = require('core.recast_tints');
tidy = tints.tidy({ mp_color = copy(object) });
assert(same(tidy.mp_color, tints.make().mp_color), 'The recast tints take the default for a color object.');
local pulse = require('core.ready_pulse');
tidy = pulse.tidy({ color = copy(object) });
assert(same(tidy.color, pulse.make().color), 'The ready pulse takes the default for a color object.');
local defaults = require('ui.defaults');
local s = defaults.make();
s.panels.target.dispel_color = copy(object);
s.panels.target.countdown_outline_color = copy(object);
tidy = defaults.tidy(s);
assert(same(tidy.panels.target.dispel_color, defaults.dispel_color), 'A panel takes the default lit color for a color object.');
assert(same(tidy.panels.target.countdown_outline_color, { 0, 0, 0, 1 }), 'A panel takes the default outline color for a color object.');

-- A part a list does have wins over the object's, and a part neither has takes the default.
tidy = pet.tidy({ hp_color = { 0.9, ['2'] = 0.3 } });
local fresh = pet.make().hp_color;
assert(tidy.hp_color[1] == 0.9 and tidy.hp_color[2] == 0.3 and tidy.hp_color[3] == fresh[3] and tidy.hp_color[4] == fresh[4],
    'A number key wins, a text key fills in, and the default fills the rest.');
