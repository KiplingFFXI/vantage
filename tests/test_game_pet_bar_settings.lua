-- Replace the game's pet bar is under While playing on the main page, not on the Pet display's page. It starts off and
-- writes its own key as one Undo step. Ticked but not in effect, a line under it says why, from the settings first and
-- then from the game side (core/game_pet_bar.lua).
local said;
package.loaded['core.game_pet_bar'] = {
    warmup_steps = function() return {}; end,
    update = function() return nil; end,
    release = function() return true; end,
    status = function() return { on = false }; end,
    problem = function() return said; end,
};
local h = require('panel_fixture')();
local TICK = 'Replace the game\'s pet bar##main_replace_pet_bar';
local NEEDS = 'This needs the Pet display on with Show HP, MP and TP. Until then the game draws its own pet bar.';
local SAMPLE = 'While the sample pet shows, the game draws its own pet bar.';
local CLIENT = 'This game client\'s pet bar drawing is missing, so the game\'s pet bar stays as it is.';

h.fresh(function(s) s.pet.enabled, s.pet.show_vitals, s.pet.preview = true, true, false; end);
-- None of the Pet display's tabs has it.
for _, tab in ipairs({ 'show', 'place', 'look', 'filters', 'when' }) do
    h.on('pet', tab);
    assert(not h.called('Checkbox', TICK) and not h.called('Checkbox', 'Replace the game\'s pet bar##frame'),
        'The tick is not on the Pet display\'s ' .. tab .. ' tab.');
end
h.s.window.tab = 'Home';
h.draw();
assert(h.called('Checkbox', TICK), 'The main page has the tick.');
-- It starts off, and off it says nothing, whatever the game side would say.
said = CLIENT;
h.draw();
assert(h.s.replace_game_pet_bar == false and not h.says(NEEDS) and not h.says(SAMPLE) and not h.says(CLIENT), 'It starts off, and off it says nothing.');
-- A click turns it on, as one Undo step, in the settings' own key and not the display's.
local steps = #h.app.state.history;
h.draw(TICK);
h.draw();
assert(h.s.replace_game_pet_bar == true and h.s.pet.replace_game_pet_bar == nil and #h.app.state.history == steps + 1, 'A click turns it on as one step.');
-- In effect it says nothing. What the game side says shows under it.
said = nil;
h.bump(); h.draw();
assert(not h.says(NEEDS) and not h.says(SAMPLE) and not h.says(CLIENT), 'In effect, it says nothing.');
-- Paused timer panels leave the Pet display on, so it is still in effect and still says nothing.
h.s.enabled = false;
h.bump(); h.draw();
assert(not h.says(NEEDS) and not h.says(SAMPLE) and not h.says(CLIENT), 'Paused timer panels don\'t stop it.');
h.s.enabled = true;
said = CLIENT;
h.bump(); h.draw();
assert(h.says(CLIENT), 'What the game side says shows under it.');
-- The settings' own reasons come first.
h.s.pet.preview = true;
h.bump(); h.draw();
assert(h.says(SAMPLE) and not h.says(CLIENT) and not h.says(NEEDS), 'A sample pet says so.');
h.s.pet.preview = false;
for _, case in ipairs({ { 'The Pet display off', 'enabled' }, { 'Without its bars', 'show_vitals' } }) do
    h.s.pet[case[2]] = false;
    h.bump(); h.draw();
    assert(h.called('Checkbox', TICK) and h.says(NEEDS) and not h.says(CLIENT), case[1] .. ', the tick stays and the line says what it needs.');
    h.s.pet[case[2]] = true;
end
-- A click turns it off again, and Undo brings it back.
h.bump();
h.draw(TICK);
h.draw();
assert(h.s.replace_game_pet_bar == false, 'A click turns it off again.');
h.draw('Undo');
h.draw();
assert(h.s.replace_game_pet_bar == true, 'Undo puts it back.');
-- Reset all of this display on Pet leaves it, as it is not one of the display's own settings. The reset turns the display
-- off, and turned on again the game's pet bar is replaced again.
h.on('pet', 'show');
h.draw('Reset all of this display##frame');
h.draw();
h.draw('Reset##look_frame_reset_pet');
h.draw();
assert(h.s.replace_game_pet_bar == true and h.s.pet.enabled == false, 'The reset keeps the tick and turns the display off.');
h.s.pet.enabled = true;
assert(require('ui.defaults').game_pet_bar_replaced(h.s) == true, 'Turned on again, the game\'s pet bar is replaced again.');
return 'Replace the game\'s pet bar has its tick on the main page';
