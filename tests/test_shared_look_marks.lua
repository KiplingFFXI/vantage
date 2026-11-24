-- Shared or a display's own look, said plainly: the main page names the timer panels with a box or colors of their own
-- under Boxes and Colors, says the party list's opacity is its own only while Party list is on, and its Skin says
-- (changed) once the colors differ from the skin's. Lit icons there sets every display's light at once, and Party list
-- lights in a look of its own, which an older save takes from Overhead icons. A timer panel's Look tab names what it
-- sets for itself and gives it all back to the main page in one step.
local h = require('panel_fixture')();
local defaults = require('ui.defaults');
local look = require('ui.shared_look');
local function home(change)
    h.fresh(function(s)
        for _, fold in ipairs({ 'Boxes', 'Colors' }) do s.window.sections['Home/' .. fold] = true; end;
        if change then change(s); end;
    end);
    h.draw();
end;

-- Fresh: no panel has its own, Party list is off and the skin is as it comes.
home();
assert(not h.says('of its own, so') and not h.says('of their own, so'), 'Fresh, no panel is named.');
assert(not h.says('Opacity and corner rounding don\'t change Party list.'), 'With Party list off, its opacity isn\'t mentioned.');
assert(not h.previews['##main_skin']:find('(changed)', 1, true), 'The skin is as it comes: ' .. h.previews['##main_skin']);
-- One panel with its own box, then two with their own colors.
home(function(s) s.panels.self_buffs.box = 'both'; s.party_ui.enabled = true; end);
assert(h.says('Self buffs has a box of its own, so Background and Border don\'t change it.'), 'One panel\'s own box is named.');
assert(h.says('Opacity and corner rounding don\'t change Party list.'), 'With Party list on, its opacity is mentioned.');
home(function(s) s.panels.self_buffs.colors.title = { 1, 0, 0, 1 }; s.panels.target.colors.title = { 0, 1, 0, 1 }; end);
assert(h.says('Self buffs and Target timers have colors of their own, so these don\'t change them.'), 'Two panels\' own colors are named.');
-- A panel that is off isn't named.
home(function(s) s.panels.self_buffs.box, s.panels.self_buffs.enabled = 'both', false; end);
assert(not h.says('Self buffs has a box of its own'), 'A panel that is off isn\'t named.');
-- A color changed from the skin's says so on Skin.
home(function(s) s.style.text_color = { 0.1, 0.2, 0.3, 1 }; end);
assert(h.previews['##main_skin']:find('(changed)', 1, true), 'Skin says (changed): ' .. h.previews['##main_skin']);

-- Lit icons sets the glow on every display that lights icons, as one Undo step.
home();
assert(h.called('ColorEdit4', 'Lit icons##main_lit_color') and h.called('Checkbox', 'Glow around them##main_lit_glow'), 'The main page has Lit icons.');
h.draw('Glow around them##main_lit_glow');
h.draw();
local s = h.s;
for _, holder in ipairs({ s.panels.target, s.panels.watch, s.panels.self_debuffs, s.panels.party, s.overhead, s.party_ui.effects }) do
    assert(holder.dispel_glow == false, 'Every display that lights icons loses its glow.');
end;
assert(#h.app.state.history == 1 and h.app.state.history[1].label == 'Glow around lit icons', 'One Undo step.');
-- While they differ there is no one value.
s.overhead.dispel_glow = true;
assert(look.light(s, 'dispel_glow') == nil, 'Differing, there is no one value.');
look.set_light(s, 'dispel_color', { 0, 1, 1, 1 });
assert(look.light(s, 'dispel_color')[2] == 1 and s.party_ui.effects.dispel_color[3] == 1 and s.panels.target.dispel_color[1] == 0,
    'One color goes to every display.');

-- Party list lights in its own color now, so Overhead icons' doesn't change it.
s = defaults.tidy(defaults.make());
s.overhead.dispel_color = { 1, 0, 0, 1 };
assert(s.party_ui.effects.dispel_color[1] == 1 and s.party_ui.effects.dispel_color[2] == 0.82, 'Party list keeps its own color.');
-- An older save, from before Party list had one, takes Overhead icons'.
local old = defaults.make();
old.party_ui.effects.dispel_color, old.party_ui.effects.dispel_glow = nil, nil;
old.overhead.dispel_color, old.overhead.dispel_glow = { 0, 1, 0, 1 }, false;
old = defaults.tidy(old);
assert(old.party_ui.effects.dispel_color[2] == 1 and old.party_ui.effects.dispel_color[1] == 0 and old.party_ui.effects.dispel_glow == false,
    'An older save takes Overhead icons\' light.');
-- Party list's Look tab has its light while it lights debuffs.
h.fresh(function(f) f.party_ui.enabled, f.party_ui.effects.cleanse_light = true, true; end);
h.on('party_ui', 'look');
assert(h.called('Checkbox', 'Glow around lit icons##frame') and h.called('ColorEdit4', 'Light color##frame'), 'Party list\'s Look tab has its light.');

-- A timer panel's Look tab names its own box and colors, and gives them back to the main page in one step.
h.fresh(function(f)
    local p = f.panels.watch;
    p.enabled, p.box, p.colors.title = true, 'both', { 1, 0, 0, 1 };
end);
h.on('watch', 'look');
assert(h.says('Has its own: Box, Title color.'), 'The Look tab names its own box and colors.');
h.draw('Use the main page\'s look##frame');
h.draw();
local p = h.s.panels.watch;
assert(p.box == 'shared' and next(p.colors) == nil and #h.app.state.history == 1 and h.app.state.history[1].label == 'Use the main page\'s look',
    'One step gives the box and colors back.');
assert(not h.says('Has its own:'), 'Then it says nothing of its own.');
MOCK.fire('unload');
return 'The main page and each Look tab say what is shared and what is a display\'s own';
