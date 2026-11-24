-- Your pet's alerts are ticked on Alerts but come from the Pet display, so they don't fire while it's off. Alerts says
-- so while one of them is ticked and the Pet display is off, with a button that turns it on in one Undo step.
local h = require('panel_fixture')();
local custom = require('core.customization');
local store = require('core.store');
local LINE = 'The Pet display is off, so your pet\'s alerts don\'t fire.';
local BUTTON = 'Turn on the Pet display##frame';

local function alerts_page(change)
    h.fresh(change);
    h.on('notices', 'show');
    return h.says(LINE), h.called('Button', BUTTON);
end;

assert(not alerts_page(), 'Fixture: at first no pet alert is ticked, and there is no line.');
for _, key in ipairs({ 'alert_hp', 'alert_tp', 'alert_ending' }) do
    local line, button = alerts_page(function(s) s.pet[key] = true; end);
    assert(line and button, key .. ' ticked with the Pet display off: Alerts says so and has the button.');
    line, button = alerts_page(function(s) s.pet[key], s.pet.enabled = true, true; end);
    assert(not line and not button, key .. ' ticked with the Pet display on: no line.');
end;
assert(not alerts_page(function(s) s.pet.alert_hp, s.pet.alert_tp, s.pet.alert_ending = false, false, false; end), 'With every pet alert unticked there is no line.');
assert(not h.says('Alerts are muted'), 'Fixture: Alerts isn\'t muted.');

-- The button turns on the Pet display, and nothing else, in one step that Undo takes back.
alerts_page(function(s) s.pet.alert_tp = true; end);
local before = store.copy(h.s);
h.draw(BUTTON);
h.draw();
local s = h.app.state.settings;
assert(s.pet.enabled == true and not h.says(LINE), 'The button turns on the Pet display, and the line goes.');
assert(#h.app.state.history == 1 and h.app.state.history[1].label == 'Turn on the Pet display', 'One Undo step named for the button.');
local after = store.copy(s);
-- The window's own state and the job a profile goes with aren't settings the button sets, as in test_element_settings.lua.
after.pet.enabled, after.window, after.profile_job = false, before.window, before.profile_job;
local changed = {};
for key in pairs(after) do if not custom.equal(after[key], before[key]) then changed[#changed + 1] = key; end; end;
for key in pairs(after.pet) do if not custom.equal(after.pet[key], before.pet[key]) then changed[#changed + 1] = 'pet.' .. key; end; end;
assert(#changed == 0, 'Nothing else changes: ' .. table.concat(changed, ' '));
assert(h.app.callbacks.undo() and h.app.state.settings.pet.enabled == false, 'Undo turns the Pet display off again.');

-- The Pet display's own page doesn't carry the line.
h.fresh(function(s2) s2.pet.alert_tp = true; end);
h.on('pet', 'show');
assert(not h.says(LINE), 'The Pet display\'s page doesn\'t say it.');
MOCK.fire('unload');
return 'Alerts says when the Pet display is off for your pet\'s alerts';
