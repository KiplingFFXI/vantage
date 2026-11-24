-- A group in a panel of its own lists its members in the slot order chosen on Party list, and leaves you out
-- when Your own row is Never. The Up and Down buttons reorder the slots as one Undo step each, and the frame of a click
-- still shows each slot once.
local layout, overlay, hud = require('ui.party_layout'), require('ui.native_party_hud'), require('ui.party_hud');
local defaults = require('ui.defaults');
local copy, equal = require('core.store').copy, require('core.customization').equal;
local roster, subjects = hud.sample(18, 100);
local settings = defaults.make();
local config = settings.party_ui;
config.enabled = true;
local groups = layout.groups(roster, config);
assert(#groups[1] == 6 and #groups[2] == 6 and #groups[3] == 6, 'Each party lists its six members.');
config.groups[1].order = { 5, 3, 1, 0, 4, 2 };
groups = layout.groups(roster, config);
assert(groups[1][1].slot == 5 and groups[1][2].slot == 3 and groups[1][4].slot == 0 and roster.members[1].slot == 0,
    'The chosen slot order sorts the members without reordering the roster.');
config.include_self = false;
groups = layout.groups(roster, config);
assert(#groups[1] == 5, 'Show my own row off leaves you out.');
config.include_self = true;
-- A detached strip draws its rows in that order.
for group = 1, 3 do config.groups[group].native_detached = true; end;
local plans = overlay.plan(roster, subjects, config, { available = false, groups = {} }, 1600, 900);
assert(#plans == 3, 'Every detached strip has a plan.');
local slots = {};
for index, row in ipairs(plans[1].rows) do slots[index] = row.member.slot; end;
assert(table.concat(slots, ',') == '5,3,1,0,4,2', 'The detached strip follows the slot order: ' .. table.concat(slots, ','));
-- All three strips wear one look, kept from frame to frame until the settings change.
local theme = require('ui.party_theme');
local resolve, built = theme.resolve, 0;
theme.resolve = function(...) built = built + 1; return resolve(...); end;
overlay.plan(roster, subjects, config, { available = false, groups = {} }, 1600, 900);
assert(built == 1, 'One look does for three strips: ' .. built);
local plan_at = function(revision) return overlay.plan(roster, subjects, config, { available = false, groups = {} }, 1600, 900, nil, nil, nil, revision); end;
built = 0;
plan_at(7); plan_at(7);
assert(built == 1, 'Frames of one settings revision share it: ' .. built);
plan_at(8);
assert(built == 2, 'The next revision makes it again: ' .. built);
theme.resolve = resolve;

-- The panel's Up and Down buttons, under Member order on Place. The first of each goes with the first slot that has one.
local h = require('panel_fixture')();
settings = h.fresh(function(s)
    s.party_ui.enabled, s.party_ui.groups[1].order = true, { 5, 3, 1, 0, 4, 2 };
    for group = 1, 3 do s.party_ui.groups[group].native_detached = true; end;
end);
config = settings.party_ui;
local history = h.app.state.history;
local before = copy(config);
h.on('party_ui', 'place');
assert(equal(config, before) and #history == 0, 'Opening the slot order changes nothing.');
-- The move waits for the list to be drawn, so the frame of the click shows each slot once, in the order it had.
local function slot_rows(click)
    h.draw(click);
    local rows = {};
    for _, call in ipairs(h.calls('TextUnformatted')) do
        if tostring(call[2]):find('^Slot %d$') then rows[#rows + 1] = call[2]; end;
    end;
    return table.concat(rows, ',');
end;
local shown = slot_rows('Down##party_slot');
assert(table.concat(config.groups[1].order, ',') == '3,5,1,0,4,2' and #history == 1 and history[1].label == 'Member order',
    'Down moves a slot one place later, as one Undo step.');
assert(shown == 'Slot 6,Slot 4,Slot 2,Slot 1,Slot 5,Slot 3', 'The frame of the click draws each slot once: ' .. shown);
h.draw('Up##party_slot');
assert(table.concat(config.groups[1].order, ',') == '5,3,1,0,4,2' and #history == 2, 'Up moves it back.');
assert(table.concat(config.groups[2].order, ',') == '0,1,2,3,4,5', 'Only the party chosen to edit is reordered.');
-- Reset this tab puts back what Size and place sets for every group, not only the one picked: its member order and
-- where a moved group sits. A panel of its own gets what ticking it gives where it is now, so no two panels end up on
-- top of each other. Which groups have a panel of their own is Show's, so it stays.
local widget, elements = require('ui.party_size_widget'), require('ui.elements');
config = h.s.party_ui;
config.groups[3].native_detached = false;
config.groups[2].order = { 1, 0, 2, 3, 4, 5 };
config.groups[2].detached_width, config.groups[2].detached_x = 335, 702;
config.groups[3].native_side, config.groups[3].native_x, config.groups[3].native_y = 'left', 30, -12;
elements.record('strip_1', { x = 830, y = 600, width = 420, height = 200 });
elements.record('strip_2', { x = 380, y = 600, width = 420, height = 200 });
local fresh = require('ui.party_defaults').make();
local ticked = copy(config);
for group = 1, 3 do
    local start = fresh.groups[group];
    ticked.groups[group].native_side, ticked.groups[group].native_x, ticked.groups[group].native_y = start.native_side, start.native_x, start.native_y;
    if ticked.groups[group].native_detached then widget.place(ticked, group, widget.rooms(h.s, h.app.callbacks), h.s.style); end;
end;
h.draw('Reset this tab##frame');
h.draw();
local panels = h.s.party_ui.groups;
for group = 1, 3 do
    local now, start = panels[group], fresh.groups[group];
    assert(table.concat(now.order, ',') == table.concat(start.order, ',') and now.native_side == start.native_side
        and now.native_x == start.native_x and now.native_y == start.native_y and now.native_detached == (group ~= 3),
        'Reset this tab puts back group ' .. group .. '\'s order and spot, and keeps which groups have a panel of their own.');
end;
for group = 1, 2 do
    for _, key in ipairs({ 'detached_x', 'detached_y', 'detached_width', 'detached_height' }) do
        assert(panels[group][key] == ticked.groups[group][key], 'Panel ' .. group .. ' gets what ticking it gives: ' .. key);
    end;
end;
local one, two = panels[1], panels[2];
assert(one.detached_x >= two.detached_x + two.detached_width or two.detached_x >= one.detached_x + one.detached_width
    or one.detached_y >= two.detached_y + two.detached_height or two.detached_y >= one.detached_y + one.detached_height,
    'The two panels don\'t cover each other.');
assert(#MOCK.commands == 0);
return true;
