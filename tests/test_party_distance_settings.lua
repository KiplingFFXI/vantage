-- Show the distance to each member, Warning color past and Distance size in the settings: off, Spell range and Small
-- to start, kept by a save, back to those after Reset Party list and left alone by a starter. They're on the Show
-- tab of Party list right after Countdowns, the picks show only while the tick is on, each change is one Undo
-- step, search finds them by what they're about, and their help reads plainly.
local defaults, custom, starters = require('ui.defaults'), require('core.customization'), require('core.starters');
local party = require('ui.party_defaults');
local TICK, PICK, SIZE = 'Show the distance to each member', 'Warning color past', 'Distance size';

do
    local s = defaults.tidy(defaults.make());
    local function three(save) local u = save.party_ui; return tostring(u.distance) .. ' ' .. u.distance_warn .. ' ' .. u.distance_size; end
    assert(three(s) == 'false spell small', 'Off, on Spell range and Small, at first: ' .. three(s));
    s.party_ui.distance, s.party_ui.distance_warn, s.party_ui.distance_size = true, 'ten', 'large';
    s = defaults.tidy(s);
    assert(three(s) == 'true ten large', 'A save keeps them.');
    for _, pick in ipairs({ 'spell', 'ten', 'eight', 'sixteen', 'none' }) do
        s.party_ui.distance_warn = pick;
        assert(defaults.tidy(s).party_ui.distance_warn == pick, 'A save keeps ' .. pick .. '.');
    end
    for _, pick in ipairs({ 'small', 'medium', 'large', 'largest' }) do
        s.party_ui.distance_size = pick;
        assert(defaults.tidy(s).party_ui.distance_size == pick, 'A save keeps ' .. pick .. '.');
    end
    s.party_ui.distance, s.party_ui.distance_warn, s.party_ui.distance_size = 'yes', 'far', 'huge';
    s = defaults.tidy(s);
    assert(three(s) == 'false spell small', 'Anything else reads as off, Spell range and Small.');
    s.party_ui.distance, s.party_ui.distance_warn, s.party_ui.distance_size = nil, nil, nil;
    s = defaults.tidy(s);
    assert(three(s) == 'false spell small', 'A save from before has them off, Spell range and Small.');
    s.party_ui.distance, s.party_ui.distance_warn, s.party_ui.distance_size = true, 'eight', 'largest';
    s = custom.reset(s, 'party_ui');
    assert(three(s) == 'false spell small', 'Reset Party list puts them back.');
    -- They're your own pick whatever the role, so a starter leaves them.
    for _, entry in ipairs(starters.list) do
        local save = defaults.tidy(defaults.make());
        save.party_ui.distance, save.party_ui.distance_warn, save.party_ui.distance_size = true, 'sixteen', 'medium';
        save = starters.apply(save, entry.name);
        assert(three(save) == 'true sixteen medium', entry.name .. ' leaves them.');
    end
end

-- The help reads plainly: no dashes for a missing number, no semicolons, no unknown, and Phoenix's numbers.
for _, help in ipairs({ party.distance_help, party.warn_help, party.size_help }) do
    assert(not help:find('[^ -~]') and not help:find('--', 1, true) and not help:find(';', 1, true), 'Plain: ' .. help);
    assert(not help:lower():find('unknown', 1, true) and not help:find('?', 1, true), 'Plain: ' .. help);
end
assert(party.distance_help:find('counting height as Phoenix checks range', 1, true), party.distance_help);
assert(party.warn_help:find('Spell range is Cure\'s, about 21 yalms', 1, true) and party.warn_help:find('Luzaf', 1, true), party.warn_help);
-- The guide has the rest of Phoenix's numbers.
local guide_file = assert(io.open(ADDON_DIR .. '/../docs/GUIDE.md', 'rb'));
local guide = guide_file:read('*a');
guide_file:close();
for _, text in ipairs({ 'like 20.4', 'about 50 yalms off', '20.8 between two Humes', '8 or more yalms above or below you' }) do
    assert(guide:find(text, 1, true), 'The guide says: ' .. text);
end;

do
    local h = require('panel_fixture')();
    local window = h.window;
    local function ticked() return h.called('Checkbox', TICK .. '##frame'); end
    local function picked() return h.called('BeginCombo', '##frame_' .. PICK); end
    local function sized() return h.called('BeginCombo', '##frame_' .. SIZE); end
    local function steps() h.app.callbacks.save(); return h.app.callbacks.history_status(); end
    local function found(text, label)
        for _, entry in ipairs(window.search(text)) do
            if entry.panel == 'party_ui' and entry.label == label then return true; end
        end
        return false;
    end

    h.fresh(function(s) s.party_ui.enabled = true; end);
    for _, tab in ipairs(h.panels.tabs) do
        h.on('party_ui', tab.key);
        assert(ticked() == (tab.key == 'show'), 'The tick is on Show and nowhere else: ' .. tab.key);
        assert(not picked() and not sized(), 'The picks wait for the tick: ' .. tab.key);
    end
    -- Right after Countdowns, which shows with every kind.
    h.on('party_ui', 'show');
    local order = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Checkbox' and (call[2] == 'Countdowns##frame' or call[2] == TICK .. '##frame') then order[#order + 1] = call[2]; end
    end
    assert(table.concat(order, '|') == 'Countdowns##frame|' .. TICK .. '##frame', 'After Countdowns: ' .. table.concat(order, '|'));

    h.draw(TICK .. '##frame');
    h.draw();
    local status = steps();
    assert(h.s.party_ui.distance == true and status.undo == 1 and status.undo_label == TICK, 'The tick is one Undo step.');
    assert(picked() and h.previews['##frame_' .. PICK] == 'Spell range', 'On, the pick shows Spell range.');
    assert(sized() and h.previews['##frame_' .. SIZE] == 'Small', 'And Distance size shows Small.');
    -- Distance size sits right under the tick, before Warning color past.
    local after = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'Checkbox' and call[2] == TICK .. '##frame') or (call[1] == 'BeginCombo' and (call[2] == '##frame_' .. PICK
            or call[2] == '##frame_' .. SIZE)) then after[#after + 1] = call[2]; end
    end
    assert(table.concat(after, '|') == TICK .. '##frame|##frame_' .. SIZE .. '|##frame_' .. PICK, 'Under the tick: ' .. table.concat(after, '|'));
    h.pick('##frame_' .. PICK, '10 yalms##ten');
    status = steps();
    assert(h.s.party_ui.distance_warn == 'ten' and status.undo == 2 and status.undo_label == PICK, 'The pick is one Undo step.');
    h.pick('##frame_' .. PICK, 'Never##none');
    assert(h.s.party_ui.distance_warn == 'none', 'Never is a pick.');
    h.app.callbacks.undo();
    assert(h.app.state.settings.party_ui.distance_warn == 'ten', 'Undo brings 10 yalms back.');
    h.draw();
    h.pick('##frame_' .. SIZE, 'Largest##largest');
    status = steps();
    assert(h.s.party_ui.distance_size == 'largest' and status.undo_label == SIZE, 'Distance size is one Undo step.');
    h.app.callbacks.undo();
    assert(h.app.state.settings.party_ui.distance_size == 'small', 'Undo brings Small back.');
    -- With None on Show, the tick stays, as the distance doesn't depend on it.
    h.fresh(function(s) s.party_ui.enabled, s.party_ui.effects.kind = true, 'none'; end);
    h.on('party_ui', 'show');
    assert(ticked() and not h.called('Checkbox', 'Countdowns##frame'), 'With None, the tick stays and Countdowns goes.');

    -- Search finds them by what they're about, the pick through the tick while it's hidden.
    h.fresh(function(s) s.party_ui.enabled = true; end);
    h.on('party_ui', 'show');
    for _, text in ipairs({ 'distance', 'yalms', 'how far', 'range' }) do
        assert(found(text, TICK), 'Search for ' .. text .. ' finds the tick.');
    end
    for _, text in ipairs({ 'Luzaf', 'Phantom Roll', 'Spell range', 'warning color' }) do
        assert(found(text, TICK) or found(text, PICK), 'Search for ' .. text .. ' finds the pick or the tick that shows it.');
    end
    for _, text in ipairs({ 'distance size', 'text size', 'bigger', 'Largest' }) do
        assert(found(text, TICK) or found(text, SIZE), 'Search for ' .. text .. ' finds Distance size or the tick that shows it.');
    end
    local controls = require('ui.search_index').controls.Display;
    assert(controls[TICK] and controls[PICK] and controls[SIZE], 'The search index has all three.');

    -- Only a group beside the game's list uses Distance size, so with every group that shows in a panel of its own the
    -- pick goes, and Warning color past stays. The search finds the tick in its place, as while the distance is off.
    h.fresh(function(s)
        s.party_ui.enabled, s.party_ui.distance = true, true;
        s.party_ui.strips.alliance1, s.party_ui.strips.alliance2 = false, false;
        s.party_ui.groups[1].native_detached = true;
    end);
    h.on('party_ui', 'show');
    assert(ticked() and picked() and not sized(), 'With every group in a panel of its own, Distance size goes and Warning color past stays.');
    for _, text in ipairs({ 'distance size', 'bigger' }) do
        assert(found(text, TICK) and not found(text, SIZE), 'Search for ' .. text .. ' finds the tick, not the pick that is gone.');
    end
    h.s.party_ui.strips.alliance1 = true;
    h.bump();
    h.on('party_ui', 'show');
    assert(sized(), 'A group beside the game\'s list brings it back.');
end
return 'The distance settings start off on Spell range and Small, sit after Countdowns, and read plainly';
