-- The edit mode bar (ui/edit_mode.lua): the display list by plain names, Moves with in the words of the Size and place tab, Size and place
-- settings on the way to that tab, a party group's lock help, the line for a display its rules hide, how to move it, and
-- where it sits while the settings window is open.
local defaults, store = require('ui.defaults'), require('core.store');
local elements, edit, frame = require('ui.elements'), require('ui.edit_mode'), require('ui.panel_frame');
local conditions = require('core.conditions');
local imgui = require('imgui');
rawset(imgui, 'GetBackgroundDrawList', function() return imgui.GetWindowDrawList(); end);
rawset(imgui, 'GetForegroundDrawList', function() return imgui.GetWindowDrawList(); end);
local combo, opened, tips = nil, nil, {};
rawset(imgui, 'BeginCombo', function(label) return label == combo; end);
rawset(imgui, 'EndCombo', function() end);
rawset(imgui, 'IsItemHovered', function() return true; end);
rawset(imgui, 'SetTooltip', function(text) tips[text] = true; end);
local s = defaults.tidy(defaults.make());
s.rolls.enabled, s.pet.enabled, s.ready_pulse.enabled, s.ready_pulse.spot = true, true, true, 'screen';
s.party_cooldowns.enabled, s.party_cooldowns.list.enabled = true, true;
local callbacks = { open_page = function(page) opened = page; return true; end, changed = function() end, save = function() return true; end };
-- Every display in the list is on the screen.
local function all_drawn()
    for index, element in ipairs(elements.movable) do elements.record(element.id, { x = index * 10, y = 100, width = 120, height = 30 }); end;
end;
local function draw(click, list)
    all_drawn();
    MOCK.imgui_calls, tips, combo = {}, {}, list;
    if click then MOCK.clicks[click] = true; end;
    edit.draw(s, callbacks);
    assert(not click or not MOCK.clicks[click], 'The control is on the bar: ' .. tostring(click));
    MOCK.clicks = {};
end;
local function pick(id)
    draw(elements.label(id) .. '##edit_pick_' .. id, '##edit_pick');
    assert(edit.selected() == id, 'Fixture: ' .. id .. ' is picked.');
    draw();
end;
local function said(text)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'TextUnformatted' and call[2] == text then return true; end; end;
    return false;
end;
local function called(kind, label)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == kind and call[2] == label then return true; end; end;
    return false;
end;
edit.start();

-- The list has the plain names: no strip in it.
draw(nil, '##edit_pick');
for _, label in ipairs({ 'Your party##edit_pick_strip_1', 'Alliance 1##edit_pick_strip_2', 'Alliance 2##edit_pick_strip_3', 'Self buffs##edit_pick_self_buffs' }) do
    assert(called('Selectable', label), 'The list has ' .. label);
end;
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'Selectable' then assert(not call[2]:lower():find('strip ', 1, true), 'A name in the list says strip: ' .. call[2]); end;
end;

-- Moves with says what the anchor follows.
local panel = s.panels.self_debuffs;
pick('self_debuffs');
for _, case in ipairs({
    { 'Nothing', function() end },
    { 'A spot on the screen', function() panel.anchor.to = 'screen'; end },
    { 'The game\'s party list', function() panel.anchor.to = 'party'; end },
    { 'The chat log', function() panel.anchor.to = 'chat'; end },
    { 'Target timers', function() panel.anchor.to, panel.anchor.element = 'element', 'target'; end },
}) do
    panel.anchor.to, panel.anchor.element = 'none', '';
    case[2]();
    draw();
    assert(said('Moves with: ' .. case[1]), 'It says Moves with: ' .. case[1]);
end;
panel.anchor.to, panel.anchor.element = 'none', '';
-- A party group beside the game's list moves with it, and in a panel of its own with nothing.
pick('strip_1');
assert(said('Moves with: The game\'s party list'), 'A group beside the list moves with it.');
s.party_ui.groups[1].native_detached = true;
draw();
assert(said('Moves with: Nothing'), 'A group in a panel of its own moves with nothing.');
s.party_ui.groups[1].native_detached = false;
assert(tips['Locks the party list buffs. Unlocked, each group can be moved here.'], 'A group\'s Locked says what it locks, in plain words.');

-- The bar has no typed spot and no Anchor button: Place settings is the way there, for each display.
assert(not called('InputInt', 'X##edit_x') and not called('InputInt', 'Y##edit_y'), 'The bar has no typed spot.');
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'Button' then assert(not call[2]:find('Anchor', 1, true), 'The bar has no Anchor button: ' .. call[2]); end;
end;
local before = store.copy(s);
for _, case in ipairs({ { 'self_buffs', 'self_buffs' }, { 'target', 'target' }, { 'strip_1', 'party_ui' }, { 'strip_3', 'party_ui' },
    { 'pulse', 'recasts' }, { 'cooldown_list', 'cooldown_list' }, { 'rolls', 'rolls' } }) do
    pick(case[1]);
    opened = nil;
    draw('Size and place##edit_place');
    assert(opened == 'Display' and frame.opened() == case[2] and frame.context():find('/place$'),
        case[1] .. ' opens the Size and place tab of ' .. case[2] .. ': ' .. tostring(opened) .. ', ' .. frame.context());
end;
for _, id in ipairs({ 'pet', 'notices' }) do
    pick(id);
    opened = nil;
    draw('Size and place##edit_place');
    assert(opened == 'Display' and frame.context():find('/place$'), id .. ' opens its Size and place tab.');
end;
assert(store.equal(before, s), 'Place settings changes no setting, and no lock.');

-- The line for a display its rules hide, and the help that stays.
pick('self_buffs');
assert(not said('Its When to show rules hide it right now. Edit mode shows it anyway.'), 'No line while its rules show it.');
local shown = conditions.shown;
conditions.shown = function(id) return id ~= 'self_buffs'; end;
draw();
assert(said('Its When to show rules hide it right now. Edit mode shows it anyway.'), 'Its rules hide it: the bar says so.');
conditions.shown = function(id) return id ~= 'party_ui'; end;
pick('strip_2');
assert(said('Its When to show rules hide it right now. Edit mode shows it anyway.'), 'A party group goes by the party list buffs\' rules.');
conditions.shown = shown;
draw();
assert(not said('Its When to show rules hide it right now. Edit mode shows it anyway.'), 'The line goes with the rule.');
assert(said('Click a display to pick it. Hold Shift and drag to move it. Arrow keys move it 1 pixel, 10 with Shift. Esc ends.'), 'The bar says how to move a display.');

-- The bar sits at the top middle of the screen, or at the bottom middle while the open settings window reaches its spot
-- up there, so the window's title and first row stay clear.
local spot, placed;
local set_pos, begin = imgui.SetNextWindowPos, imgui.Begin;
rawset(imgui, 'SetNextWindowPos', function(pos, cond, pivot) spot = { pos[1], pos[2], pivot and pivot[2] }; return set_pos(pos, cond, pivot); end);
rawset(imgui, 'Begin', function(name, ...) if name == 'Vantage edit mode##vantage_edit_bar' then placed = spot; end; return begin(name, ...); end);
MOCK.screen, MOCK.window_size = { 1280, 720 }, { 970, 82 };
edit.stop(); edit.start();
local function bar_at(area)
    callbacks.settings_area = area and function() return area; end;
    placed = nil;
    draw();
    return table.concat(placed or {}, ',');
end;
assert(bar_at(nil) == '640,6,0', 'With no settings window open, the bar is at the top middle.');
local where = bar_at({ x = 100, y = 40, width = 960, height = 680 });
assert(where == '640,714,1', 'The window at the top sends it to the bottom middle: ' .. where);
assert(bar_at({ x = 100, y = 40, width = 960, height = 680 }) == '640,714,1', 'It stays there the next frame.');
assert(bar_at({ x = 100, y = 300, width = 960, height = 400 }) == '640,6,0', 'Lower down, the window leaves it at the top.');
assert(bar_at({ x = 0, y = 0, width = 150, height = 700 }) == '640,6,0', 'So does a window beside its spot.');
callbacks.settings_area, MOCK.screen, MOCK.window_size = nil, nil, nil;
rawset(imgui, 'SetNextWindowPos', nil);
rawset(imgui, 'Begin', nil);

edit.stop();
rawset(imgui, 'BeginCombo', nil);
rawset(imgui, 'EndCombo', nil);
rawset(imgui, 'IsItemHovered', nil);
rawset(imgui, 'SetTooltip', nil);
return 'The edit mode bar says what a display moves with and opens its Size and place tab';
