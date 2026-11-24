-- The main page's Party group: Party buffs and Party cooldowns each tick the places they show, a tick for the distance,
-- and an Edit for each. A place ticked while its display is off shows there alone, and with no place left the display
-- goes off. Each tick is one Undo step named for it, and Party list links to the other two places party buffs show.
local h = require('panel_fixture')();
local window = require('ui.settings_window');
local overhead = require('ui.overhead_defaults');
local BUFFS_LIST, BUFFS_BESIDE, BUFFS_HEADS = 'In a list##main_party', 'Beside the party list##main_party_ui', 'Over heads##main_party_heads';
local CD_LIST, CD_BESIDE, CD_HEADS = 'In a list##main_cooldowns_list', 'Beside the party list##main_cooldowns_strips', 'Over heads##main_cooldowns_heads';
local DISTANCE = 'Show the distance to each member##main_distance';
-- The state a tick was last drawn with.
local function ticked(label)
    local value;
    for _, call in ipairs(h.calls('Checkbox', label)) do value = call[3][1]; end;
    return value;
end;
-- Clicks a tick and checks it made one Undo step with that name.
local function tick(label, name)
    local steps = #h.app.state.history;
    h.draw(label);
    h.draw();
    assert(#h.app.state.history == steps + 1 and h.app.state.history[#h.app.state.history].label == name,
        'One Undo step named ' .. name .. ': ' .. tostring((h.app.state.history[#h.app.state.history] or {}).label));
end;
-- Only these overhead units are ticked.
local function only_units(...)
    local wanted = {};
    for _, id in ipairs({ ... }) do wanted[id] = true; end;
    for _, id in ipairs(overhead.units) do
        if (h.s.overhead.units[id] == true) ~= (wanted[id] == true) then return false; end;
    end;
    return true;
end;

-- Every tick is drawn, each with the state it reads, and both Edits.
h.fresh(function(s) s.party_ui.enabled, s.party_cooldowns.enabled, s.overhead.enabled = false, false, false; end);
h.draw();
for _, label in ipairs({ BUFFS_LIST, BUFFS_BESIDE, BUFFS_HEADS, CD_LIST, CD_BESIDE, CD_HEADS, DISTANCE }) do
    assert(ticked(label) ~= nil, 'The main page draws ' .. label);
end;
assert(ticked(BUFFS_BESIDE) == false and ticked(CD_BESIDE) == false and ticked(BUFFS_HEADS) == false and ticked(DISTANCE) == false,
    'With Party list and Overhead icons off, nothing reads ticked there.');
assert(h.says('Party buffs') and h.says('Party cooldowns'), 'Both lines have their caption.');

-- In a list is Party members' timers.
h.fresh(function(s) s.panels.party.enabled = false; end);
h.draw();
tick(BUFFS_LIST, 'Party members\' timers');
assert(h.s.enabled and h.s.panels.party.enabled and ticked(BUFFS_LIST) == true, 'In a list turns Party members\' timers on.');

-- Over heads, while Overhead icons is off, shows your party and alliance there alone, and unticked with no one left it
-- turns Overhead icons off.
h.fresh(function(s) s.overhead.enabled = false; end);
h.draw();
tick(BUFFS_HEADS, 'Party buffs over heads');
assert(h.s.overhead.enabled and only_units('party', 'alliance') and ticked(BUFFS_HEADS) == true, 'Over heads shows your party there alone.');
tick(BUFFS_HEADS, 'Party buffs over heads');
assert(not h.s.overhead.enabled and only_units(), 'With no one left, Overhead icons goes off.');
-- While Overhead icons is on, the other units stay as they are either way.
h.fresh(function(s) s.overhead.enabled = true; end);
h.draw();
tick(BUFFS_HEADS, 'Party buffs over heads');
assert(h.s.overhead.enabled and h.s.overhead.units.target and not h.s.overhead.units.party and not h.s.overhead.units.alliance,
    'Unticked with others left, Overhead icons stays on for them.');
tick(BUFFS_HEADS, 'Party buffs over heads');
assert(h.s.overhead.units.target and h.s.overhead.units.party and h.s.overhead.units.alliance, 'Ticked again, the others stay too.');

-- The distance, ticked while Party list is off, shows there alone.
h.fresh(function(s) s.party_ui.enabled, s.party_ui.distance = false, false; s.party_cooldowns.enabled, s.party_cooldowns.strips = true, true; end);
h.draw();
tick(DISTANCE, 'Show the distance to each member');
local p = h.s.party_ui;
assert(p.enabled and p.distance and p.effects.kind == 'none' and not h.s.party_cooldowns.strips, 'The distance shows beside the party list alone.');
assert(ticked(DISTANCE) == true and ticked(BUFFS_BESIDE) == false and ticked(CD_BESIDE) == false, 'Only the distance reads ticked.');
-- The buffs join it, and unticked while the distance is still there Party list stays on.
tick(BUFFS_BESIDE, 'Party list');
p = h.s.party_ui;
assert(p.enabled and p.distance and p.effects.kind == 'all', 'The buffs join the distance.');
tick(BUFFS_BESIDE, 'Party list');
p = h.s.party_ui;
assert(p.enabled and p.distance and p.effects.kind == 'none', 'Unticked, the buffs go and the distance stays.');
tick(DISTANCE, 'Show the distance to each member');
assert(not h.s.party_ui.enabled and not h.s.party_ui.preview, 'With nothing left beside the party list, Party list goes off.');

-- Party cooldowns beside the party list turns Party list on for them alone, and the watch with them alone.
h.fresh(function(s)
    s.party_ui.enabled, s.party_ui.distance = false, true;
    s.party_cooldowns.enabled, s.party_cooldowns.list.enabled, s.party_cooldowns.overhead = false, true, true;
end);
h.draw();
assert(ticked(CD_BESIDE) == false and ticked(CD_LIST) == false, 'With the watch off, its places read off.');
tick(CD_BESIDE, 'Party cooldowns beside the party list');
local watch;
p, watch = h.s.party_ui, h.s.party_cooldowns;
assert(p.enabled and p.effects.kind == 'none' and not p.distance and p.strips.party, 'Party list is on for the cooldowns alone.');
assert(watch.enabled and watch.strips and not watch.list.enabled and not watch.overhead, 'The watch shows beside the party list alone.');
assert(ticked(CD_BESIDE) == true, 'It reads ticked.');
-- Unticked with nothing else there, Party list and the watch both go off.
tick(CD_BESIDE, 'Party cooldowns beside the party list');
assert(not h.s.party_ui.enabled and not h.s.party_cooldowns.enabled, 'With nothing left, both go off.');
-- With Party list off, a cooldown strip left on from before reads off.
h.fresh(function(s) s.party_ui.enabled, s.party_cooldowns.enabled, s.party_cooldowns.strips = false, true, true; end);
h.draw();
assert(ticked(CD_BESIDE) == false, 'With Party list off, Beside the party list reads off.');

-- Party cooldowns over heads, while Overhead icons is off, shows your party there alone.
h.fresh(function(s) s.overhead.enabled, s.party_cooldowns.enabled = false, false; end);
h.draw();
tick(CD_HEADS, 'Party cooldowns over heads');
assert(h.s.party_cooldowns.enabled and h.s.party_cooldowns.overhead and h.s.overhead.enabled and only_units('party', 'alliance'),
    'Over heads turns Overhead icons on for your party.');
assert(ticked(CD_HEADS) == true, 'It reads ticked.');
-- Unticked, Overhead icons stays as it is: the party buffs show there too.
tick(CD_HEADS, 'Party cooldowns over heads');
assert(not h.s.party_cooldowns.enabled and h.s.overhead.enabled and only_units('party', 'alliance'), 'Unticked, Overhead icons stays on.');

-- In a list of Party cooldowns, and Undo takes a tick back.
h.fresh(function(s) s.party_cooldowns.enabled = false; end);
h.draw();
tick(CD_LIST, 'Party cooldowns in a list');
assert(h.s.party_cooldowns.enabled and h.s.party_cooldowns.list.enabled and not h.s.party_cooldowns.strips, 'In a list shows them in the list alone.');
assert(h.app.callbacks.undo());
h.draw();
assert(not h.app.state.settings.party_cooldowns.enabled, 'Undo turns the watch off again.');

-- Each Edit opens its display.
for _, entry in ipairs({ { 'Edit##main_party_ui', 'party_ui' }, { 'Edit##main_party_cooldowns', 'cooldown_list' } }) do
    h.fresh();
    h.draw(entry[1]);
    h.draw();
    assert(h.s.window.tab == 'Display' and h.panels.context():match('^(.-)/') == entry[2], entry[1] .. ' opens ' .. entry[2]);
end;

-- Search finds each place by what it is.
for _, entry in ipairs({ { 'Party members\' timers', 'Party members\' timers' }, { 'Party list', 'Party list' },
    { 'Party buffs over heads', 'Party buffs over heads' }, { 'Party cooldowns in a list', 'Party cooldowns in a list' },
    { 'Party cooldowns beside the party list', 'Party cooldowns beside the party list' },
    { 'Party cooldowns over heads', 'Party cooldowns over heads' }, { 'Party distance', 'Show the distance to each member' } }) do
    local found = false;
    for _, result in ipairs(window.search(entry[1])) do found = found or result.tab == 'Home' and result.label == entry[2]; end;
    assert(found, entry[1] .. ' finds ' .. entry[2] .. ' on the main page.');
end;

-- Party list links to the other two places, each opening its display.
for _, entry in ipairs({ { 'Open Party members\' timers##frame', 'party' }, { 'Open Overhead icons##frame', 'overhead' } }) do
    h.fresh(function(s) s.party_ui.enabled = true; end);
    h.on('party_ui', 'show');
    h.draw(entry[1]);
    h.draw();
    assert(h.panels.context():match('^(.-)/') == entry[2], entry[1] .. ' opens ' .. entry[2]);
end;
-- In two columns On you sits beside Target and enemies, with Alerts under that, and Party takes the whole width under
-- both, so each Party row's places stay on one line. In one column the groups keep their order.
local function groups_drawn()
    local out, table_ended = {}, false;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'EndTable' then table_ended = true; end;
        if call[1] == 'TableNextColumn' then out[#out + 1] = '|'; end;
        if call[1] == 'TextUnformatted' and (call[2] == 'On you' or call[2] == 'Target and enemies' or call[2] == 'Party' or call[2] == 'Alerts') then
            out[#out + 1] = call[2] .. (table_ended and ' (under the columns)' or '');
        end;
    end;
    return table.concat(out, ', ');
end;
h.fresh();
MOCK.content_width = 1000;
h.draw();
local wide = groups_drawn();
MOCK.content_width = nil;
h.draw();
local narrow = groups_drawn();
assert(wide == '|, On you, |, Target and enemies, Alerts, Party (under the columns)', 'Two columns: ' .. wide);
assert(narrow == 'On you, Target and enemies, Party, Alerts', 'One column: ' .. narrow);
-- Recasts' ticks and the Blink seconds slider go on the line before them while it has room, and under it when it
-- hasn't, as at a big Settings text size in a narrow window, so none runs off the window.
local function beside(kind, label)
    local before;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == kind and call[2] == label then return before; end;
        -- Sizes, item widths and the colors a tick pushes come between a line and what goes on it.
        local name = call[1];
        if not (name:find('^Get') or name:find('^Calc') or name:find('^Push') or name:find('^Pop') or name == 'SetNextItemWidth') then
            before = name;
        end;
    end;
end;
local ROOMY = { { 'Checkbox', 'Spells##main_recast_spell' }, { 'Checkbox', 'Items##main_recast_item' }, { 'SliderFloat', '##main_blink_seconds' } };
h.draw();
for _, item in ipairs(ROOMY) do local before = beside(item[1], item[2]); assert(before == 'SameLine', 'With room it goes on the line before it: ' .. item[2] .. ', after ' .. tostring(before)); end;
MOCK.content_width = 150;
h.draw();
MOCK.content_width = nil;
for _, item in ipairs(ROOMY) do local before = beside(item[1], item[2]); assert(before and before ~= 'SameLine', 'With no room it goes under: ' .. item[2] .. ', after ' .. tostring(before)); end;
MOCK.fire('unload');
return 'The main page ticks each place Party buffs and Party cooldowns show';
