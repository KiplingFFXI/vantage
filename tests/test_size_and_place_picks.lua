-- Size and place on a timer panel: Width is one pick of Fixed, Fits the rows and Same as the chat log, Height one pick of
-- Grows with its rows and Fixed, Column width shows only while rows sit side by side, a line says what a resize changes,
-- and every display Size reaches points to it on the main page.
local h = require('panel_fixture')();
local function place(change)
    h.fresh(function(s)
        s.panels.self_buffs.mode, s.panels.self_buffs.stack_direction = 'bars', 'vertical';
        if change then change(s.panels.self_buffs, s); end;
    end);
    h.on('self_buffs', 'place');
end;
local function shown(label) return h.called('SliderFloat', '##frame_' .. label); end;

-- Fresh: a fixed width, growing up to Tallest, with no Column width while the rows go down in one column.
place();
assert(h.previews['##frame_Width'] == 'Fixed' and shown('Fixed width') and not shown('Narrowest') and not shown('Widest'),
    'Fixed shows Fixed width alone.');
assert(h.previews['##frame_Height'] == 'Grows with its rows' and shown('Tallest') and not shown('Fixed height'), 'Grows shows Tallest.');
assert(not shown('Column width'), 'One column has no Column width.');
assert(h.says('Moving or resizing it on the screen stops it moving with anything.'), 'It says what a resize changes.');
-- Fits the rows writes auto_width as one Undo step and shows Narrowest and Widest.
h.pick('##frame_Width', 'Fits the rows##fits');
local p = h.s.panels.self_buffs;
assert(p.auto_width == true and p.dock_match_width == false and #h.app.state.history == 1 and h.app.state.history[1].label == 'Width',
    'Fits the rows is one step.');
assert(shown('Narrowest') and shown('Widest') and not shown('Fixed width'), 'Fits shows Narrowest and Widest.');
-- Fixed height writes auto_height and shows Fixed height on the same saved number.
h.pick('##frame_Height', 'Fixed##fixed');
assert(h.s.panels.self_buffs.auto_height == false and shown('Fixed height') and not shown('Tallest'), 'Fixed shows Fixed height.');
h.slide('##frame_Fixed height', 300);
assert(h.s.panels.self_buffs.height_limit == 300, 'Fixed height writes the height.');

-- Same as the chat log is a choice only while the panel moves with the chat log, and then it wins.
place(function(panel) panel.anchor.to, panel.anchor.side = 'chat', 'above'; end);
h.pick('##frame_Width', 'Same as the chat log##chat');
p = h.s.panels.self_buffs;
assert(p.dock_match_width == true and p.auto_width == false and h.previews['##frame_Width'] == 'Same as the chat log', 'It writes the chat log\'s.');
assert(not shown('Fixed width') and not shown('Narrowest'), 'Neither width row shows while the chat log\'s wins.');
-- A save with both ticked reads as the chat log's.
place(function(panel) panel.anchor.to, panel.auto_width, panel.dock_match_width = 'chat', true, true; end);
assert(h.previews['##frame_Width'] == 'Same as the chat log', 'An older save with both reads as the chat log\'s.');
-- Away from the chat log the older key says nothing.
place(function(panel) panel.auto_width, panel.dock_match_width = true, true; end);
assert(h.previews['##frame_Width'] == 'Fits the rows', 'Away from the chat log it is Fits the rows.');

-- Column width shows while rows fill across, or once they go down in columns.
place(function(panel) panel.stack_direction = 'horizontal'; end);
assert(shown('Column width'), 'Rows filling across have Column width.');
local hud = require('ui.hud');
local real = hud.split_columns;
hud.split_columns = function(key) return key == 'self_buffs' and 2 or nil; end;
place();
assert(shown('Column width') and h.says('Column width too wide'), 'Rows in columns have Column width and the line names it.');
hud.split_columns = real;
place(function(panel) panel.mode = 'icons'; end);
assert(not shown('Column width'), 'Icons have none.');

-- Bigger or smaller opens How it looks on the main page, on each display Size reaches.
for _, id in ipairs({ 'self_buffs', 'spell_recasts', 'pet', 'rolls', 'cooldown_list', 'notices', 'pulse' }) do
    h.fresh(function(s)
        s.panels.spell_recasts.enabled, s.pet.enabled, s.rolls.enabled = true, true, true;
        s.party_cooldowns.enabled, s.party_cooldowns.list.enabled = true, true;
        s.ready_pulse.enabled, s.ready_pulse.spot = true, 'screen';
    end);
    h.on(id, 'place');
    assert(h.called('Button', 'Open Size##frame'), id .. ' points to Size.');
end;
h.draw('Open Size##frame');
h.draw();
assert(h.s.window.tab == 'Home', 'Open Size opens the main page.');
-- The party list beside the game's doesn't follow Size, so it has no pointer.
h.fresh(function(s) s.party_ui.enabled = true; end);
h.on('party_ui', 'place');
assert(not h.called('Button', 'Open Size##frame'), 'Party list has no pointer.');
-- The displays with one Height say what a resize does to it.
h.fresh(function(s) s.pet.enabled = true; end);
h.on('pet', 'place');
assert(h.says('Resizing by its top or bottom edge gives it a fixed Height.'), 'Pet says what a resize changes.');
-- Their Height was called Tallest, so a search for that still finds it on each.
h.fresh(function(s) s.pet.enabled, s.rolls.enabled, s.party_cooldowns.enabled, s.party_cooldowns.list.enabled = true, true, true, true; end);
h.draw();
local heights = {};
for _, result in ipairs(h.window.search('tallest')) do
    if result.label == 'Height' and result.place == 'place' then heights[result.panel] = true; end;
end;
for _, id in ipairs({ 'rolls', 'pet', 'cooldown_list', 'notices' }) do
    assert(heights[id], 'A search for Tallest finds Height on ' .. id .. '.');
end;
MOCK.fire('unload');
return 'Size and place has one Width and one Height pick, Column width only for columns, and says where Size is';
