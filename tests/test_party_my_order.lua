-- Party list's My order: Sort's fifth choice, the list under it on Show with Up, Down and Remove, and Add to My order on
-- Filters. Every member's effects go by that list, so the rows line up, and what it leaves out follows by name.
local h = require('panel_fixture')();
local party, layout = require('ui.party_defaults'), require('ui.party_layout');
local find = h.choose;

-- A fresh save has an empty list and sorts longest first. A save keeps only effect ids on it, each once.
local fresh = party.make().effects;
assert(type(fresh.order) == 'table' and #fresh.order == 0 and fresh.sort == 'longest', 'A fresh save has an empty My order.');
local saved = party.make();
saved.effects.sort, saved.effects.order = 'fixed', { 40, 33, 40, 'x', 0, 2000, 445, 66 };
saved = party.tidy(saved);
assert(saved.effects.sort == 'fixed', 'A save keeps My order as its sort.');
assert(table.concat(saved.effects.order, ',') == '40,33,66', 'A save keeps each effect once, and a Copy Image shadow is Copy Image: '
    .. table.concat(saved.effects.order, ','));

-- What a member's row draws goes by the list, whatever time each effect has left.
local function effect(id, name, remaining)
    return { effect = id, key = 'effect:' .. id, name = name, remaining = remaining, first_seen = id, first_sequence = id,
        present = true, kind = 'buff' };
end;
local function names(subject, options)
    local out = {};
    for _, row in ipairs((layout.effects(subject, options))) do out[#out + 1] = row.name; end;
    return table.concat(out, ',');
end;
local one = { effects = { effect(40, 'Protect', 100), effect(41, 'Shell', 300), effect(33, 'Haste', 50), effect(42, 'Regen', 10), effect(251, 'Food', nil) } };
local two = { effects = { effect(40, 'Protect', 290), effect(41, 'Shell', 20), effect(33, 'Haste', 170), effect(42, 'Regen', 60), effect(251, 'Food', nil) } };
local options = party.make().effects;
assert(names(one, options) ~= names(two, options), 'Sorted by time left, two members can differ.');
options.sort, options.order = 'fixed', { 41, 40 };
assert(names(one, options) == 'Shell,Protect,Food,Haste,Regen', 'My order comes first, and the rest follow by name: ' .. names(one, options));
assert(names(two, options) == names(one, options), 'Every member goes by the same order.');
options.pinned = { 33 };
assert(names(one, options) == 'Haste,Shell,Protect,Food,Regen', 'Pinned still comes first.');
options.pinned = {};
-- A change to the list reaches the rows already worked out.
options.order[1], options.order[2] = 40, 41;
assert(names(one, options) == 'Protect,Shell,Food,Haste,Regen', 'A reordered list sorts again: ' .. names(one, options));

-- On the settings window: My order is one of Sort's choices, and with nothing on it a line says so.
h.fresh(function(s) s.party_ui.enabled = true; end);
h.on('party_ui', 'show');
assert(not h.called('Button', 'Up##order'), 'My order\'s list shows only while it has effects.');
h.pick('##frame_Sort', 'My order##fixed');
assert(h.s.party_ui.effects.sort == 'fixed', 'Sort takes My order.');
assert(h.says('Nothing is on My order yet'), 'An empty My order says the effects go by name.');

-- Add to My order puts the effect on the end, once, and sorts by it.
h.fresh(function(s) s.party_ui.enabled = true; end);
h.on('party_ui', 'filters');
assert(not h.called('Button', 'Add to My order##frame'), 'With nothing picked there is nothing to add.');
find('Haste', 33);
h.draw('Add to My order##frame');
h.draw();
local effects = h.s.party_ui.effects;
assert(#effects.order == 1 and effects.order[1] == 33 and effects.sort == 'fixed', 'Add to My order lists it and sorts by it.');
h.draw('Add to My order##frame');
h.draw();
assert(#h.s.party_ui.effects.order == 1, 'An effect is on the list once.');
h.s.party_ui.effects.sort = 'longest';
h.draw('Add to My order##frame');
h.draw();
assert(#h.s.party_ui.effects.order == 1 and h.s.party_ui.effects.sort == 'fixed', 'One already listed still sorts by it.');
find('Protect', 40);
h.draw('Add to My order##frame');
h.draw();
find('Regen', 42);
h.draw('Add to My order##frame');
h.draw();
assert(table.concat(h.s.party_ui.effects.order, ',') == '33,40,42', 'Each goes on the end.');

-- The list sits under Sort on Show, each line with Up, Down and Remove.
h.on('party_ui', 'show');
assert(h.says('My order') and h.says('Haste') and h.says('Regen'), 'The line under Sort lists them by name.');
assert(not h.says('Nothing is on My order yet'), 'A list with effects needs no line about an empty one.');
assert(#h.calls('Button', 'Up##order') == 3 and #h.calls('Button', 'Down##order') == 3, 'Each line has its Up and Down.');
-- The mock clicks the first Down it meets, which moves the first line down.
h.draw('Down##order');
h.draw();
assert(table.concat(h.s.party_ui.effects.order, ',') == '40,33,42', 'Down moves its line down.');
h.draw('Undo');
h.draw();
assert(table.concat(h.s.party_ui.effects.order, ',') == '33,40,42', 'A move is one Undo step.');
local real_button, count = h.imgui.Button, 0;
h.imgui.Button = function(label, ...)
    if label == 'Remove##effect' then
        count = count + 1;
        if count == 2 then MOCK.clicks[label] = true; end;
    end;
    return real_button(label, ...);
end;
h.draw();
h.imgui.Button = real_button;
h.draw();
assert(table.concat(h.s.party_ui.effects.order, ',') == '33,42', 'Remove goes by its line.');

-- None shows no effects, so the list goes with Sort.
h.s.party_ui.effects.kind = 'none';
h.bump(); h.draw(); h.draw();
assert(not h.called('Button', 'Up##order'), 'With None the list is gone too.');
h.s.party_ui.effects.kind = 'all';
h.bump(); h.draw(); h.draw();

-- Reset this tab on Show puts the list and the sort back.
h.draw('Reset this tab##frame');
h.draw();
assert(#h.s.party_ui.effects.order == 0 and h.s.party_ui.effects.sort == 'longest', 'Reset this tab clears My order and Sort.');
