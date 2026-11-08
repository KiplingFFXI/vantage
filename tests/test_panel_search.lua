-- Search on the panels. Every name on a panel is a result, and a result goes where it says: its display, its tab and any
-- fold around it, which stays open once the search is cleared, with the row it names lit up. A row hidden now goes by the
-- row that shows it. tests/test_search_leads_to_switch.lua does the same for the other pages.
local store, defaults = require('core.store'), require('ui.defaults');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {},
    party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window, imgui = require('ui.settings_window'), require('imgui');
local panels = require('ui.panel_frame');
local view = { rows = {}, context = { valid = true, job = 3, party = {}, entities = {} } };

local query;
local with_hint = imgui.InputTextWithHint;
imgui.InputTextWithHint = function(label, hint, value, ...)
    if label == '##find_settings' and query then value[1], query = query, nil; end;
    return with_hint(label, hint, value, ...);
end;
local opened = {};
imgui.SetNextItemOpen = function(value) opened.next = value; end;
imgui.CollapsingHeader = function(label) opened[label] = opened.next; return opened.next; end;
-- What each frame lights, by the words of the row.
local lit, looking_for = {}, nil;
local light = window.main_helpers.light;
window.main_helpers.light = function(text, named)
    if looking_for and window.matches(looking_for, text) then lit[#lit + 1] = named; end;
    return light(text, named);
end;
local function draw(s, click)
    s.window.open = true;
    app.state.settings = s;
    MOCK.imgui_calls = {};
    lit = {};
    if click then MOCK.clicks[click] = true; end;
    window.draw(s, view, app.callbacks);
    if click then assert(not MOCK.clicks[click], 'The control is on screen: ' .. click); end;
end;
local function seen(kind, text)
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == kind and tostring(call[2]):find(text, 1, true) then return true; end;
    end;
    return false;
end;
local function lights(label)
    for _, words in ipairs(lit) do
        if words:sub(1, #label + 1) == label .. ' ' then return true; end;
    end;
    return false;
end;
local function display_of(panel) return defaults.recast_panels[panel] and 'recasts' or panel; end;
local fold_pages = { party_ui = 'Party & alliance', overhead = 'Overhead', cooldown_list = 'Cooldowns', rolls = 'Rolls', pet = 'Pet', notices = 'Alerts', hidden = 'Filters' };
local function fold_key(result)
    return (fold_pages[result.panel] or defaults.recast_panels[result.panel] and 'Recasts' or 'Panels') .. '/' .. result.fold.key;
end;

local function fresh(change)
    local s = defaults.tidy(defaults.make());
    s.window.tab = 'Home';
    if change then change(s); end;
    app.state.settings_revision = (app.state.settings_revision or 0) + 1;
    return s;
end;

-- Follows a result as a player does: types, clicks it, reads what opens, then clears the search.
local function follow(s, typed, result)
    local when = typed .. ' -> ' .. result.label .. ' / ' .. result.where;
    s.window.tab, s.window.sections = 'Home', {};
    looking_for, query = nil, typed;
    draw(s);
    draw(s, result.label .. '  /  ' .. result.where);
    looking_for = typed;
    draw(s);
    assert(s.window.tab == 'Display', when .. ' opens the panel.');
    assert(panels.context() == display_of(result.panel) .. '/' .. result.place, when .. ' opens its tab: ' .. panels.context());
    assert(seen('TextUnformatted', 'matching controls on this page'), when .. ' lights something up.');
    assert(lights(result.label), when .. ' lights up what it named.');
    if result.fold then
        assert(s.window.sections[fold_key(result)] == true, when .. ' saves its fold open.');
        looking_for = nil;
        draw(s, 'Clear search');
        draw(s);
        assert(panels.context() == display_of(result.panel) .. '/' .. result.place and opened[result.fold.label] == true,
            when .. ' leaves its tab and fold open once the search is cleared.');
    else
        looking_for = nil;
        draw(s, 'Clear search');
    end;
end;

local function every_name(s)
    draw(s);
    local names = {};
    for label in pairs(require('ui.search_index').controls.Display) do names[#names + 1] = label; end;
    table.sort(names);
    assert(#names > 200, 'Fixture: the panels have their names in the index: ' .. #names);
    local followed = 0;
    for _, label in ipairs(names) do
        local results, own = window.search(label), false;
        for _, result in ipairs(results) do
            if result.tab == 'Display' and result.label == label and not result.topic then
                own = true;
                follow(s, label, result);
                followed = followed + 1;
            end;
        end;
        -- Hidden on every panel now: it goes by what shows it.
        if not own then
            for _, result in ipairs(results) do
                if result.tab == 'Display' and result.place then
                    follow(s, label, result);
                    break;
                end;
            end;
        end;
    end;
    assert(followed > 200, 'Fixture: the names were followed: ' .. followed);
end;
every_name(fresh());
every_name(fresh(function(s)
    for _, id in ipairs(defaults.panel_order) do
        local p = s.panels[id];
        p.enabled, p.mode, p.bar_style, p.gradient, p.dispel_light = true, 'bars', 'rail', true, true;
    end;
    s.recast_display, s.ready_pulse.enabled, s.ready_pulse.spot = 'combined', true, 'screen';
    s.panels.self_buffs.anchor.to, s.panels.self_debuffs.anchor.to, s.panels.target.anchor.to = 'screen', 'chat', 'party';
    -- An alert rule open with all it can show, and a rule in the fold of Hidden everywhere.
    local rule = defaults.rule('alert_search');
    rule.event, rule.emphasis, rule.flash = 'remaining', true, true;
    s.alerts.rules = { rule };
    require('ui.alert_panel').edit(rule.id);
    s.effect_filters.rules = { { enabled = false, effect = 0, kind = 'all', scope = 'party', name = '', job = 0 } };
end));
require('ui.alert_panel').edit(nil);

-- With a recast panel for each kind, a result goes to the one being edited, and only that way's rows are offered.
do
    local s = fresh();
    draw(s);
    local found;
    for _, result in ipairs(window.search('Never pulse for')) do
        if result.tab == 'Display' and result.panel then found = result; end;
    end;
    assert(found and found.label == 'Pulse when a long recast is ready' and found.place == 'show' and found.panel == 'spell_recasts',
        'With the pulse off, its rows find the tick that turns it on.');
    follow(s, 'Never pulse for', found);
end;

-- The names of what a row offers find it: a choice is a label too.
do
    local s = fresh();
    draw(s);
    for typed, label in pairs({ ['Only while engaged'] = 'Fighting', ['Only with no pet out'] = 'Pet', ['Only while synced'] = 'Level Sync',
        ['The chat log'] = 'Moves with', ['Down, then to the left'] = 'Fills', ['A panel for each kind'] = 'Show as',
        ['Ready soonest'] = 'Sort', ['Longest remaining'] = 'Sort', ['Background only'] = 'Box', ['Expanded bars'] = 'Layout' }) do
        local found = false;
        for _, result in ipairs(window.search(typed)) do found = found or result.tab == 'Display' and result.label == label; end;
        assert(found, typed .. ' finds ' .. label);
    end;
end;

-- Everything a tab draws can be found, by the words it shows. What a row's label holds for an effect, a member or a part is
-- the player's own, and Up, Down, Remove and Delete go with the row they are on.
do
    local s = fresh(function(s)
        for _, id in ipairs(defaults.panel_order) do s.panels[id].mode = 'bars'; end;
        s.ready_pulse.enabled, s.ready_pulse.spot = true, 'screen';
        s.alerts.rules = { defaults.rule('alert_words') };
        s.alerts.rules[1].name, s.alerts.rules[1].emphasis, s.alerts.rules[1].flash = 'My alert', true, true;
        require('ui.alert_panel').edit('alert_words');
    end);
    local own = { ['My alert'] = true, Up = true, Down = true, Remove = true, Delete = true, ['< Back'] = true, Reset = true, Cancel = true, ['Clear search'] = true,
        Undo = true, Redo = true, Close = true, Tools = true, Displays = true, Show = true, Size = true, Look = true, Filters = true, Place = true, ['When to show'] = true };
    draw(s);
    s.window.tab = 'Display';
    for _, id in ipairs({ 'self_buffs', 'self_debuffs', 'target', 'party', 'watch', 'spell_recasts', 'party_ui', 'overhead', 'cooldown_list', 'rolls', 'pet', 'notices', 'hidden' }) do
        for _, tab in ipairs({ 'show', 'place', 'look', 'filters', 'when' }) do
            panels.open(id, tab);
            draw(s);
            for _, call in ipairs(MOCK.imgui_calls) do
                if call[1] == 'Checkbox' or call[1] == 'Button' or call[1] == 'CollapsingHeader' then
                    local name = tostring(call[2]):match('^(.-)###') or tostring(call[2]):match('^(.-)##') or tostring(call[2]);
                    if name ~= '' and not own[name] and not name:find('\n', 1, true) then
                        local found = false;
                        for _, result in ipairs(window.search(name)) do found = found or result.tab == 'Display'; end;
                        assert(found, id .. '/' .. tab .. ': ' .. name .. ' can be found.');
                    end;
                end;
            end;
        end;
    end;
end;

require('ui.alert_panel').edit(nil);

-- A tab clicked while a search is on keeps the words and lights its own rows.
do
    local s = fresh();
    s.window.tab = 'Display';
    panels.open('self_buffs', 'show');
    query = 'Sort';
    draw(s); draw(s);
    assert(seen('TextUnformatted', 'matching controls on this page'), 'Fixture: Show has the row.');
    draw(s, 'Size and place##frame_tab');
    assert(panels.context() == 'self_buffs/place' and seen('Button', 'Clear search'), 'A tab keeps the search going.');
    draw(s, 'Clear search');
end;

assert(#MOCK.commands == 0, 'Searching sends no game commands.');
MOCK.fire('unload');
return 'Every name on a panel is a result, and every result opens its display, tab and fold';
