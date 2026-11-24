-- A display's page says why the display isn't on the screen now, under its top line: timer panels paused, with
-- Resume, Vantage hidden by /vg hide, with Show, its When to show rules, or nothing to show. The first that holds is
-- said, and nothing while the display is off, as its On tick says that, or while samples or Arrange on screen show it.
local h = require('panel_fixture')();
local conditions, elements = require('core.conditions'), require('ui.elements');
local PAUSED = 'Timer panels are paused, so this panel is hidden.';
local HIDDEN = 'Vantage displays are hidden (/vg hide).';
local RULES = 'Its When to show rules hide it now.';
local EMPTY = 'It has nothing to show now, so it is hidden.';
-- The lines drawn, in order.
local function said()
    local out = {};
    for _, text in ipairs({ PAUSED, HIDDEN, RULES, EMPTY }) do if h.says(text) then out[#out + 1] = text; end; end;
    return table.concat(out, ' | ');
end;
local function drawn() elements.record('self_buffs', { x = 10, y = 10, width = 100, height = 40 }); end;
local function gone() elements.frame(); elements.frame(); end;

-- On and on the screen, it says nothing.
h.fresh();
drawn();
h.on('self_buffs', 'show');
assert(said() == '', 'On and drawn, nothing is said: ' .. said());
-- Paused timer panels say so, and Resume turns them back on as one Undo step.
h.s.enabled = false;
h.bump(); h.draw();
assert(said() == PAUSED and h.called('Button', 'Resume##frame'), 'Paused, it says so with Resume: ' .. said());
h.draw('Resume##frame');
assert(h.s.enabled == true and #h.app.state.history == 1 and h.app.state.history[1].label == 'Resume', 'Resume turns timer panels on as one step.');
h.draw();
assert(said() == '', 'Resumed, nothing is said.');
-- /vg hide says so, and Show shows them again without a setting changed.
h.app.state.hidden = true;
h.draw();
assert(said() == HIDDEN, 'Hidden by /vg hide, it says so: ' .. said());
h.draw('Show##frame');
assert(h.app.state.hidden == false and #h.app.state.history == 1, 'Show shows them again and saves nothing.');
-- Paused and hidden at once, the pause comes first.
h.app.state.hidden, h.s.enabled = true, false;
h.bump(); h.draw();
assert(said() == PAUSED, 'Paused and hidden, the pause is said: ' .. said());
h.app.state.hidden, h.s.enabled = false, true;
-- Its When to show rules.
conditions.hidden.self_buffs = true;
h.bump(); h.draw();
assert(said() == RULES, 'Its rules hide it, and it says so: ' .. said());
conditions.hidden.self_buffs = nil;
-- Nothing to show.
gone();
h.draw();
assert(said() == EMPTY, 'With nothing to show it says so: ' .. said());
-- Samples or Arrange on screen show it anyway, so nothing is said.
h.s.preview = true;
h.bump(); h.draw();
assert(said() == '', 'Samples show it, so nothing is said: ' .. said());
h.s.preview = false;
h.app.callbacks.edit_mode(true);
conditions.hidden.self_buffs = true;
h.draw();
assert(said() == '', 'Arrange on screen shows it, so nothing is said: ' .. said());
h.app.callbacks.edit_mode(false);
conditions.hidden.self_buffs = nil;
-- Off, its On tick says so, and the lines say nothing.
h.s.panels.self_buffs.enabled = false;
h.bump(); h.draw();
assert(said() == '', 'Off, nothing is said: ' .. said());
-- The overhead icons have no place of their own on the screen, so nothing to show is never said for them.
h.fresh(function(s) s.overhead.enabled = true; end);
h.on('overhead', 'show');
assert(not h.says(EMPTY), 'The overhead icons never say they have nothing to show.');
-- The Hide list is no display on the screen and says none of it.
h.fresh(function(s) s.enabled = false; end);
h.on('hidden', 'show');
assert(said() == '', 'The Hide list says none of it: ' .. said());
MOCK.fire('unload');
return 'A display\'s page says why it is hidden now, with the fix where there is one';
