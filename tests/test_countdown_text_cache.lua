-- Every countdown's text comes from one cache in countdown.time (ui/countdown_text.lua), and every effect's countdown
-- from one rule, countdown.effect_text. A ticking countdown makes nothing once its texts have shown, whichever display
-- asks, the ones that kept no cache of their own too. Measured with the collector stopped and the compiler off.
local countdown = require('ui.countdown_text');

-- The texts read as before: whole hours, whole minutes, seconds rounded up, nothing for a time that isn't one.
for _, case in ipairs({ { 0, '0s' }, { 0.2, '1s' }, { 59.5, '60s' }, { 60, '1m' }, { 3599.9, '59m' }, { 3600, '1h' },
    { 7300, '2h' }, { -0.5, '' }, { 0 / 0, '' }, { math.huge, '' }, { 'x', '' }, { nil, '' } }) do
    assert(countdown.time(case[1]) == case[2], ('%s reads %q: %q'):format(tostring(case[1]), case[2], countdown.time(case[1])));
end
-- A negative time is turned away before the cache, so it never takes the slot 0 has: ceil(-0.5) is -0, the same key.
assert(countdown.time(-0.5) == '' and countdown.time(0) == '0s', 'A negative time never changes what 0 reads.');

-- The effect rule: nothing for Level Sync outside the recasts, the time since it landed for a duration override that
-- counts up, else the time left.
local rule = countdown.effect_text;
assert(type(rule) == 'function', 'countdown.effect_text is the one effect rule.');
assert(rule({ effect = 269, remaining = 30 }) == '' and rule({ effect = '269', remaining = 30 }) == '', 'Level Sync shows nothing.');
assert(rule({ effect = 269, domain = 'recast', remaining = 30 }) == '30s', 'A recast with that id shows its time.');
assert(rule({ effect = 1, remaining = 90 }) == '1m', 'The time left.');
assert(rule({ effect = 1, count_up = true, elapsed = 5, remaining = 90 }) == '5s', 'A count-up shows the time since it landed.');
assert(rule({ effect = 1, remaining = math.huge }) == '' and rule({ effect = 1 }) == '', 'No time, no text.');

-- Each display that showed countdown text through a cache of its own now asks the one cache.
assert(require('ui.element_box').time == countdown.time, 'box.time is countdown.time.');
assert(require('ui.party_layout').effect_time({ effect = 1, remaining = 3 }) == '3s', 'The party strips\' rule reads the same.');
for _, path in ipairs({ 'ui/hud.lua', 'ui/overhead_icons.lua', 'ui/element_box.lua' }) do
    local file = assert(io.open(ADDON_DIR .. '/' .. path, 'rb'));
    local text = file:read('*a');
    file:close();
    assert(not text:find('20000 +', 1, true), path .. ' keeps no countdown text cache of its own.');
end
-- The Pet display reads the same rule, behind its own Show countdowns tick.
local pet_file = assert(io.open(ADDON_DIR .. '/ui/pet_display.lua', 'rb'));
local pet_text = pet_file:read('*a');
pet_file:close();
assert(pet_text:find('config.show_countdowns and countdown.effect_text(effect)', 1, true)
    and not pet_text:find('effect.count_up', 1, true), 'The Pet display keeps no copy of the effect rule.');

-- A countdown that ticks makes nothing once each of its texts has shown: forty timers from 2 hours down, a frame a
-- tenth of a second, run once to show every text and then counted.
local jit_on = jit and jit.status and jit.status();
if jit then jit.off(); end
local function run()
    for frame = 0, 1200 do
        for timer = 1, 40 do countdown.time(7200 - frame * 6 - timer * 0.1); end
    end
end
run();
run();
-- Collected after the warm-up, so only the texts the cache holds are still alive while the third run is counted.
collectgarbage('collect');
collectgarbage('collect');
collectgarbage('stop');
local before = collectgarbage('count');
run();
local made = collectgarbage('count') - before;
collectgarbage('restart');
if jit and jit_on then jit.on(); end
assert(made < 0.5, ('A ticking countdown makes nothing: %.3f KB'):format(made));
return 'One countdown text cache and one effect rule';
