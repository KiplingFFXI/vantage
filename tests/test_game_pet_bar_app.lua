-- Replace the game's pet bar in the addon: the tick is under While playing on the main page and is each character's
-- own. The game's pet line is skipped only while Vantage's Pet display can stand in for it: the display on with its
-- bars, no sample pet, not hidden by /vg hide or by its When to show, and after the client searches have run as
-- warmup steps. Whenever that stops being so the game draws its own again, and unload puts it back.
local ORDER = { 'pet_line', 'layout' };
local ran, wants, released, problem = {}, {}, 0, nil;
package.loaded['core.game_pet_bar'] = {
    warmup_steps = function()
        local list = {};
        for index, name in ipairs(ORDER) do
            list[index] = { name = 'game_pet_bar.' .. name, run = function() ran[#ran + 1] = name; end };
        end
        return list;
    end,
    update = function(want) wants[#wants + 1] = { want = want, searched = #ran }; return nil; end,
    release = function() released = released + 1; return true; end,
    status = function() return { on = false }; end,
    problem = function() return problem; end,
};
local defaults = require('ui.defaults');
local h = require('self_panel_fixture')();
MOCK.fire('load');
h.app.refresh(MOCK.now);
local s = h.app.state.settings;
local function last() return wants[#wants] and wants[#wants].want; end

-- Off at first, and with the tick off no client search is made.
assert(s.replace_game_pet_bar == false and defaults.make().replace_game_pet_bar == false, 'It starts off.');
h.run(5);
assert(#ran == 0 and #wants > 0, 'With the tick off nothing is searched: ' .. #ran);
for _, call in ipairs(wants) do assert(call.want == false, 'And the game draws its own pet bar.'); end

-- Ticked with the Pet display off, or without its bars, the game keeps its own, and the page says why.
s.replace_game_pet_bar = true;
s.pet.enabled, s.pet.show_vitals, s.pet.preview = false, true, false;
h.run(5);
local asked, why = defaults.game_pet_bar_replaced(s);
assert(last() == false and asked == false and why == 'This needs the Pet display on with Show HP, MP and TP. Until then the game draws its own pet bar.',
    'The Pet display must be on: ' .. tostring(why));
s.pet.enabled, s.pet.show_vitals = true, false;
h.run(3);
asked, why = defaults.game_pet_bar_replaced(s);
assert(last() == false and asked == false and why:find('Show HP, MP and TP', 1, true), 'And its bars.');
-- A sample pet isn't yours.
s.pet.show_vitals, s.pet.preview = true, true;
h.run(3);
asked, why = defaults.game_pet_bar_replaced(s);
assert(last() == false and asked == false and why == 'While the sample pet shows, the game draws its own pet bar.', 'A sample pet keeps the game\'s bar: ' .. tostring(why));

-- With the display on and its bars shown, each pattern is searched once, and only then is the game's line skipped.
s.pet.preview = false;
h.run(10);
assert(#ran == #ORDER, 'Each pattern is searched once: ' .. #ran);
local first;
for _, call in ipairs(wants) do if call.want == true then first = first or call; end end
assert(first and first.searched == #ORDER and last() == true, 'The game\'s pet bar is replaced only after both searches have run.');
assert(defaults.game_pet_bar_replaced(s) == true, 'And the settings say it is asked for.');
-- /vg hide gives the game's back, and showing again replaces it again, with nothing searched again.
do local event = { command = '/vg hide' }; MOCK.fire('command', event); end
h.run(3);
assert(last() == false, 'Hidden displays leave the game its own pet bar.');
do local event = { command = '/vg show' }; MOCK.fire('command', event); end
h.run(3);
assert(last() == true and #ran == #ORDER, 'Shown again, it is replaced again.');
-- Pausing the timer panels doesn't pause the Pet display, so hud still calls it and the game's pet bar stays
-- replaced, with no line under the tick. Resumed, it is still replaced, and it never came back in between.
local pet_display = require('ui.pet_display');
local pet_draw, pet_draws, before = pet_display.draw, 0, #wants;
pet_display.draw = function(...) pet_draws = pet_draws + 1; return pet_draw(...); end;
do local event = { command = '/vg set enabled false' }; MOCK.fire('command', event); end
h.run(3);
s = h.app.state.settings;
asked, why = defaults.game_pet_bar_replaced(s);
assert(s.enabled == false and pet_draws > 0, 'The timer panels are paused and hud still calls the Pet display: ' .. pet_draws);
assert(last() == true and asked == true and why == nil, 'Paused timer panels leave the game\'s pet bar replaced: ' .. tostring(why));
do local event = { command = '/vg set enabled true' }; MOCK.fire('command', event); end
h.run(3);
s = h.app.state.settings;
pet_display.draw = pet_draw;
for index = before + 1, #wants do assert(wants[index].want == true, 'The game\'s pet bar never came back while paused.'); end
assert(s.enabled == true and last() == true, 'Resumed, it is still replaced.');
-- While the Pet display's When to show hides it, the game draws its own pet bar, so a pet bar always shows. Edit mode
-- shows the display, so it is replaced then. Shown again, it is replaced again, with nothing searched again.
do
    local conditions = require('core.conditions');
    s.pet.conditions = conditions.tidy({ engaged = 'yes' });
    h.app.refresh(MOCK.now);
    before = #wants;
    h.run(3);
    for index = before + 1, #wants do assert(wants[index].want == false, 'Hidden by When to show, the game draws its own pet bar.'); end
    do local event = { command = '/vg edit' }; MOCK.fire('command', event); end
    h.run(2);
    assert(last() == true, 'Edit mode shows the Pet display, so the game\'s pet bar is replaced then.');
    do local event = { command = '/vg edit' }; MOCK.fire('command', event); end
    h.run(2);
    assert(last() == false, 'Out of edit mode the game draws its own again.');
    s.pet.conditions = conditions.tidy({});
    h.app.refresh(MOCK.now);
    before = #wants;
    h.run(3);
    for index = before + 1, #wants do assert(wants[index].want == true, 'Shown again by When to show, it is replaced again.'); end
    assert(#ran == #ORDER, 'Nothing is searched again: ' .. #ran);
end

-- The tick is the character's own: no profile carries it, and no import changes it, not even a string made by hand.
local profiles, share = require('core.profiles'), require('core.share');
assert(profiles.capture(s).replace_game_pet_bar == nil, 'A profile doesn\'t carry it.');
local text = assert(share.export(s, 'profile', nil, 'Tester'));
local payload = assert(share.read(text));
assert(payload.data.replace_game_pet_bar == nil, 'An export doesn\'t carry it.');
for _, mode in ipairs({ 'replace', 'add' }) do
    assert(assert(share.candidate(s, payload, mode)).replace_game_pet_bar == true, 'An import by ' .. mode .. ' keeps yours.');
end
payload.data.replace_game_pet_bar = false;
assert(assert(share.candidate(s, payload, 'replace')).replace_game_pet_bar == true, 'A string that says off leaves yours on.');
payload.data.replace_game_pet_bar = true;
s.replace_game_pet_bar = false;
assert(assert(share.candidate(s, payload, 'add')).replace_game_pet_bar == false and assert(share.candidate(s, payload, 'replace')).replace_game_pet_bar == false,
    'A string that says on leaves yours off.');
s.replace_game_pet_bar = true;
-- /vg set reaches it, as it reaches the buff icons' tick.
local function command(line) local event = { command = line }; MOCK.fire('command', event); assert(event.blocked); end
command('/vg set replace_game_pet_bar false');
assert(h.app.state.settings.replace_game_pet_bar == false, '/vg set turns it off.');
h.run(3);
assert(last() == false, 'And the game draws its own again.');
command('/vg set replace_game_pet_bar true');
h.run(3);
assert(h.app.state.settings.replace_game_pet_bar == true and last() == true, '/vg set turns it on.');

-- A display that keeps failing draws nothing of Vantage's, so after three failed frames in a row the game draws its
-- own pet bar again, and it is replaced again once a frame draws. One or two bad frames change nothing.
local hud = h.hud;
local draw, broken = hud.draw, false;
hud.draw = function(...)
    if broken then error('Panel failed', 0); end
    return draw(...);
end;
broken = true;
h.frame(); h.frame();
assert(last() == true, 'Two bad frames change nothing.');
h.frame();
assert(last() == false, 'After a third the game draws its own pet bar.');
h.frame();
assert(last() == false, 'And it stays the game\'s while the display fails.');
broken = false;
h.frame(); h.frame();
assert(last() == true, 'Once a frame draws, it is replaced again.');
hud.draw = draw;

-- Unload puts the game's pet bar back.
MOCK.fire('unload');
assert(released == 1, 'Unload releases it: ' .. released);
return 'Replace the game\'s pet bar is in effect only while the Pet display can stand in';
