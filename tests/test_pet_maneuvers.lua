-- A PUP's maneuver lines on the pet display: one for each element with a maneuver up or an overload chance to show. A
-- square for each maneuver up, the time to the soonest ending from your own timers, and the chance your last maneuver of
-- that element reported, which falls no faster than the server can lower it, so it is never below the real one.
local fx = require('pet_fixture')();
local game, settings = fx.game, fx.settings;
local pet = require('core.pet');
local self_id, automaton, index = game.id, 0x1000703, 0x703;
local FIRE, DARK, FIRE_UP, THUNDER_UP = 141, 148, 300, 304;
game.job = 18;
game.pet = { index = index, id = automaton, name = 'Ironsides', flags = 0x02, hpp = 100 };
fx.step();
local function shown() return fx.app.state.view.pet; end
local function line(name)
    for at = 1, shown().maneuver_count do
        if shown().maneuvers[at].name == name then return shown().maneuvers[at]; end
    end
end
-- The squares drawn, as one square each at the size they are.
local function squares()
    local count, size = 0, math.max(4, math.floor(settings.style.font_size * settings.style.scale * 0.5 + 0.5));
    for _, call in ipairs(MOCK.imgui_calls) do
        local args = MOCK.drawn[call];
        if call[1] == 'draw:AddRectFilled' and args[3][1] - args[2][1] == size and args[3][2] - args[2][2] == size then count = count + 1; end
    end
    return count;
end
local function maneuver(ability, message, percent) fx.action(self_id, 6, ability, { { self_id, message, percent } }); end

assert(shown().maneuver_count == 0, 'Nothing up, no lines.');
-- Two Fire and a Thunder up, with their own timers.
local start = MOCK.now;
game.buffs = { { effect = FIRE_UP, ends = start + 90 }, { effect = FIRE_UP, ends = start + 40 }, { effect = THUNDER_UP, ends = start + 150 } };
fx.status();
fx.step();
local fire, thunder = line('Fire'), line('Thunder');
assert(fire and thunder and shown().maneuver_count == 2, 'A line for each element up.');
assert(fire.count == 2 and thunder.count == 1, 'Each counts its own.');
assert(math.abs(fire.deadline - (start + 40)) < 1, 'The soonest to end is the one shown.');
assert(not fire.percent, 'No chance has been reported yet.');
local text = fx.draw();
assert(text:find('|Fire|', 1, true) and text:find('|Thunder|', 1, true) and text:find('|40s|', 1, true) and text:find('|2m|', 1, true), text);
assert(squares() == 3, 'A square for each maneuver up: ' .. squares());
assert(not text:find('|%d+%%|'), 'A line with no chance reported has none.');

-- A chance reported shows at once, and falls by 1 every 3 seconds at most.
maneuver(FIRE, 798, 23);
fx.step();
assert(line('Fire').percent == 23 and fx.draw():find('|23%|', 1, true), 'The chance your maneuver reported.');
assert(not line('Thunder').percent, 'and only for its element.');
fx.step(2.5);
assert(line('Fire').percent == 23, 'Nothing falls before 3 seconds.');
fx.step(0.6);
assert(line('Fire').percent == 22, 'One after 3.');
fx.step(29.85);
assert(line('Fire').percent == 12, 'Eleven after 33.');
assert(pet.maneuver_details(line('Fire'), MOCK.now):find('Overload risk 12%. At most this. Reported by your last Fire maneuver 34s ago.', 1, true),
    pet.maneuver_details(line('Fire'), MOCK.now));
-- The next maneuver of that element says again.
maneuver(FIRE, 798, 30);
fx.step();
assert(line('Fire').percent == 30, 'The next report takes over.');

-- At 0 it says nothing, and with no maneuver up there's no line to show.
game.buffs = { { effect = THUNDER_UP, ends = start + 150 } };
fx.status();
fx.step();
assert(line('Fire').percent == 30 and line('Fire').count == 0, 'A chance outlasts the maneuvers.');
text = fx.draw();
assert(text:find('|Fire|', 1, true) and text:find('|30%|', 1, true), text);
fx.step(90);
assert(not line('Fire'), 'At 0 with nothing up the line goes.');
assert(not fx.draw():find('|0%|', 1, true), 'And 0% is never drawn.');

-- Message 799 is a chance too: the one that overloaded you.
maneuver(DARK, 799, 45);
fx.step();
assert(line('Dark') and line('Dark').percent == 45, 'An overload reports its number.');

-- Only for a PUP, main or support.
game.job, game.sub = 9, 18;
fx.step();
assert(line('Dark'), 'On /PUP it shows.');
game.job, game.sub = 9, 0;
fx.step();
assert(shown().maneuver_count == 0, 'On no PUP at all it doesn\'t.');
game.job = 18;
fx.step();
-- It has its switch.
settings.pet.show_maneuvers = false;
fx.step();
assert(shown().maneuver_count == 0 and not fx.draw():find('Dark', 1, true), 'Show maneuvers off, no lines.');
settings.pet.show_maneuvers = true;
fx.step();

-- A new pet, or a zone, starts over.
game.pet = { index = 0x704, id = 0x1000704, name = 'Ironsides', flags = 0x02, hpp = 100 };
fx.step();
assert(not line('Dark'), 'A new automaton has no burden.');
maneuver(FIRE, 798, 20);
fx.step();
assert(line('Fire').percent == 20, 'Fixture: a chance on the new one.');
fx.zone(103);
fx.step();
fx.step();
assert(not line('Fire'), 'A zone starts over.');

-- An icon near its end blinks, at the display's seconds, as an effect does.
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);
local function tint(effect)
    for _, call in ipairs(MOCK.imgui_calls) do
        local args = MOCK.drawn[call];
        if call[1] == 'draw:AddImage' and args[2] == 5000 + effect then return args[7]; end
    end
end
game.buffs = { { effect = 302, ends = MOCK.now + 10 }, { effect = 303, ends = MOCK.now + 100 } };
fx.status();
fx.step();
assert(fx.draw():find('|Wind|', 1, true) and tint(302) and tint(303), 'Fixture: both lines drawn with their icons.');
assert(tint(302) ~= tint(303), 'The line near its end blinks.');
settings.pet.blink_icons = false;
fx.draw();
assert(tint(302) == tint(303), 'With blink off it doesn\'t.');
settings.pet.blink_icons = true;
return 'A PUP\'s maneuver lines';
