-- A search result opens a page that shows what it named. A control a page draws only in some state is left out while
-- that state is off, and its name finds the switch that shows it, or the Add button of a list with no entries yet. The
-- match line and its buttons show only while something matches, and a topic with nothing to light up takes the search
-- away, as a link does. tests/test_search_hidden_controls.lua covers Grid mode and panels of their own.
local store, defaults = require('core.store'), require('ui.defaults');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {},
    party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window, imgui = require('ui.settings_window'), require('imgui');
local view = { rows = {}, context = { valid = true, job = 3, party = {}, entities = {} } };

local query;
local with_hint = imgui.InputTextWithHint;
imgui.InputTextWithHint = function(label, hint, value, ...)
    if label == '##find_settings' and query then value[1], query = query, nil; end;
    return with_hint(label, hint, value, ...);
end;
local function fresh(change)
    local s = defaults.tidy(defaults.make());
    if change then change(s); end;
    return s;
end;
local function draw(s, page)
    s.window.open, s.window.tab = true, page or s.window.tab or 'Home';
    app.state.settings = s;
    MOCK.imgui_calls = {};
    window.draw(s, view, app.callbacks);
end;
local function found(text, page, label)
    for _, result in ipairs(window.search(text)) do
        if result.tab == page and result.label == label then return true; end;
    end;
    return false;
end;
local function seen(kind, text)
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == kind and tostring(call[2]):find(text, 1, true) then return true; end;
    end;
    return false;
end;

-- A word's trailing s, up to the end of a word, and the aliases the window's first users typed.
assert(window.matches('samples', 'Sample displays') and window.matches('displays', 'Sample display'), 'A trailing s is not needed.');
assert(not window.matches('debuffs', 'the debuffed mobs'), 'It reads as the same word, not as the start of another.');
assert(not window.matches('bus', 'bu'), 'A short word keeps its s.');
local sample, samples = window.search('sample'), {};
for _, result in ipairs(window.search('samples')) do samples[result.tab .. '/' .. result.label] = true; end;
for _, result in ipairs(sample) do assert(samples[result.tab .. '/' .. result.label], 'samples finds ' .. result.label .. ' as sample does.'); end;
assert(#sample >= 19, 'Fixture: sample finds what it should.');
assert(found('change font', 'Home', 'Font'), 'change font finds the font.');
assert(found('other character', 'Profiles', 'Share settings across my characters'), 'other character finds what shares settings.');

-- Each row names a page, a control and what shows it: off is the settings it isn't drawn in, on those it is.
local rule = defaults.rule('rule_1');
local function with_rule(flash, event, domain, scope)
    return function(s)
        local copy = defaults.copy(rule);
        copy.flash, copy.event, copy.domain, copy.scope = flash, event or copy.event, domain or copy.domain, scope or copy.scope;
        s.alerts.rules = { copy };
        require('ui.alert_panel').edit(copy.id);
    end;
end;
local function override(mode)
    return function(s)
        local entry = require('core.durations').override();
        entry.id, entry.mode = 33, mode;
        s.durations.overrides = { entry };
    end;
end;
local hide_rule = function(s) s.effect_filters.rules = { { enabled = true, effect = 253, kind = 'all', name = '', job = 0, scope = 'self' } }; end;
local function detached(s) s.party_ui.groups[1].native_detached = true; end;
local function layout(name) return function(s) s.overhead.types.mob.layout = name; end; end;
local function bars(s) for _, panel in pairs(s.panels) do panel.mode = 'bars'; end; end;
local function icons(s) for _, panel in pairs(s.panels) do panel.mode = 'icons'; end; end;
local function combined(s)
    s.recast_display = 'combined';
    require('ui.panel_frame').open('recasts', 'show');
end;
local function spell_panel(s) s.panels.spell_recasts.enabled = true; end;
local function ability_panel(s) s.panels.ability_recasts.enabled = true; end;
local function pulse_on(s) s.ready_pulse.enabled = true; end;
for _, row in ipairs({
    { 'Display', 'Rule name', 'New alert', nil, with_rule(false), nil, 'notices' },
    { 'Display', 'Your alerts', 'New alert', nil, with_rule(false), nil, 'notices' },
    { 'Display', 'Flash color', 'New alert', nil, with_rule(true), nil, 'notices' },
    { 'Display', 'Flash color', 'Flash the bar', with_rule(false), with_rule(true), nil, 'notices' },
    { 'Display', 'Flash length', 'Flash the bar', with_rule(false), with_rule(true), nil, 'notices' },
    { 'Display', 'Threshold unit', 'Trigger', with_rule(false, 'gain'), with_rule(false, 'remaining'), nil, 'notices' },
    { 'Display', 'Specific member', 'Alert type', with_rule(false, 'ready', 'recast'), with_rule(false, 'gain', 'status', 'party'), nil, 'notices' },
    { 'Display', 'Specific member', 'Who to watch', with_rule(false, 'gain', 'status'), with_rule(false, 'gain', 'status', 'party'), nil, 'notices' },
    { 'Durations', 'Change the time to', 'Add duration override', nil, override('fixed') },
    { 'Durations', 'Fixed time', 'Add duration override', nil, override('fixed') },
    { 'Durations', 'Fixed time', 'Change the time to', override('percent'), override('fixed') },
    { 'Durations', 'Percent of the estimate', 'Change the time to', override('fixed'), override('percent') },
    { 'Durations', 'Clear learned durations', 'Learn from my casts', nil,
        function(s) s.durations.learned = { ['spell:253:2:crab'] = { samples = { 58 }, unit = 'Crab', at = 1 } }; end },
    { 'Display', 'Use this rule', 'Add a rule', nil, hide_rule, nil, 'hidden' },
    { 'Display', 'Player name', 'Add a rule', nil, hide_rule, nil, 'hidden' },
    { 'Display', 'Part label', 'Layout', icons, bars, nil, 'self_buffs' },
    { 'Display', 'Bar shape', 'Layout', icons, bars },
    { 'Display', 'Icon countdown size', 'Layout', bars, icons },
    { 'Display', 'Editing', 'Show as', combined, nil, true },
    -- The other panels' Moves with stays a result: each panel has its own.
    { 'Display', 'Side', 'Moves with', nil, function(s) s.panels.self_buffs.anchor.to = 'chat'; end, true },
    { 'Display', 'Across from it', 'Moves with', nil, function(s) s.panels.self_buffs.anchor.to = 'screen'; end, true },
    { 'Display', 'Across the screen', 'Your party in a panel of its own', nil, detached, nil, 'party_ui', 'place' },
    { 'Display', 'Panel height', 'Your party in a panel of its own', nil, detached, nil, 'party_ui', 'place' },
    -- Layout's own help and the other swap's name share these words, so it stays a result too.
    { 'Display', 'Swap the lines', 'Layout', layout('single'), layout('lines'), true, 'overhead' },
    { 'Display', 'Swap the sides', 'Layout', layout('lines'), layout('split'), true, 'overhead' },
    { 'Display', 'Offset in yalms', 'Add head offset', nil, function(s) s.overhead.head.offsets = { Crab = 1 }; end, nil, 'overhead', 'place' },
    -- What can't do anything now goes, and its name finds what brings it back.
    { 'Display', 'Make the effect\'s bar stand out', 'Trigger', with_rule(false, 'ready', 'recast'), with_rule(false, 'gain'), true, 'notices' },
    { 'Display', 'Repeat reminder', 'Trigger', with_rule(false, 'gain'), with_rule(false, 'remaining'), true, 'notices' },
    { 'Display', 'Minimum time between repeats', 'Trigger', with_rule(false, 'gain'), with_rule(false, 'missing'), true, 'notices' },
    { 'Display', 'Spells while my MP is too low', 'Show this display', nil, spell_panel, true, 'spell_recasts' },
    { 'Display', 'Abilities under Amnesia', 'Show this display', spell_panel, ability_panel, true, 'spell_recasts' },
    { 'Display', 'When the pulse plays', 'Pulse when a long recast is ready', nil, pulse_on, nil, 'spell_recasts' },
    { 'Display', 'Not reached color', 'Show who got it', function(s) s.rolls.show_members = false; end, function(s) s.rolls.show_members = true; end, nil, 'rolls' },
    { 'Display', 'HP bar', 'Show HP, MP and TP', function(s) s.pet.show_vitals = false; end, function(s) s.pet.show_vitals = true; end, nil, 'pet', 'show' },
    { 'Display', 'Show automaton HP as a number', 'Show HP, MP and TP', function(s) s.pet.show_vitals = false; end, function(s) s.pet.show_vitals = true; end, nil,
        'pet', 'show' },
    { 'Display', 'Space between lines', 'Layout', layout('single'), layout('lines'), true, 'overhead' },
    { 'Display', 'Faded opacity', 'Fade starts at', function(s) s.overhead.fade_start = s.overhead.distance_cap; end, nil, true, 'overhead' },
    { 'Display', 'Player name', 'Who', function(s) hide_rule(s); s.effect_filters.rules[1].scope = 'enemy'; end, hide_rule, nil, 'hidden' },
}) do
    local page, label, switch, off, on = row[1], row[2], row[3], row[4], row[5];
    local when = page .. ' / ' .. label;
    if row[7] then require('ui.panel_frame').open(row[7], row[8] or 'show'); end;
    draw(fresh(off), page);
    assert(not found(label, page, label), when .. ' is left out while it isn\'t drawn.');
    assert(found(label, page, switch), when .. ' finds ' .. switch .. ' while it isn\'t drawn.');
    query = label;
    draw(app.state.settings, page); draw(app.state.settings, page);
    assert(seen('TextUnformatted', 'matching controls on this page'), when .. ' lights up what shows it.');
    query = '';
    draw(app.state.settings, page);
    draw(fresh(on), page);
    assert(found(label, page, label), when .. ' is found while it is drawn.');
    assert(row[6] or not found(label, page, switch) or window.matches(label, require('ui.search_index').controls[page][switch]), when .. ' no longer needs ' .. switch .. '.');
end;

-- What only some panels show: a result goes to the panel that has it, and one a panel hides goes to the tick that shows it.
do
    draw(fresh(), 'Home');
    local function panels_of(text, label)
        local out = {};
        for _, result in ipairs(window.search(text)) do
            if result.tab == 'Display' and result.label == label then out[result.panel] = true; end;
        end;
        return out;
    end;
    local members = panels_of('Selected members', 'Members');
    assert(members.party and next(members, 'party') == nil and next(members) == 'party', 'Members is on Party members\' timers only.');
    local watching = panels_of('Watching', 'Watching');
    assert(watching.watch and next(watching, 'watch') == nil and next(watching) == 'watch', 'Watching is on Watched enemy timers only.');
    for _, id in ipairs({ 'target', 'watch' }) do
        assert(panels_of('Light up buffs you can remove', 'Light up buffs you can remove')[id], id .. ' has the light.');
        assert(panels_of('Glow around lit icons', 'Light up buffs you can remove')[id] and not panels_of('Glow around lit icons', 'Glow around lit icons')[id],
            'With the light off, its glow finds the switch on ' .. id);
    end;
end;

-- A result opens a page that lights something up, on a fresh save and with everything on.
local function every_result(s)
    -- tests/test_panel_search.lua walks the results of the panel frame.
    local pages = {};
    for _, page in ipairs(window._tabs) do if page ~= 'Display' then pages[#pages + 1] = page; end; end;
    for _, page in ipairs(pages) do draw(s, page); end;
    local index, drawn = require('ui.search_index').controls, {};
    -- What each page really draws: a search draws every tab and section of it.
    for _, page in ipairs(pages) do
        local kept = {};
        for label, text in pairs(index[page]) do kept[label], index[page][label] = text, '\0'; end;
        query = 'zzzz';
        draw(s, page); draw(s, page);
        drawn[page] = {};
        for label, text in pairs(index[page]) do
            if text ~= '\0' then drawn[page][label] = true; else index[page][label] = kept[label]; end;
        end;
        query = '';
        draw(s, page);
    end;
    for _, page in ipairs(pages) do
        for label in pairs(index[page]) do
            local shown = found(label, page, label);
            -- A label ending in a space stands for the controls it begins, such as Confirm overwrite.
            if label:sub(-1) ~= ' ' then
                assert(not shown or drawn[page][label], page .. ' / ' .. label .. ' is a result, so its page draws it.');
            end;
            assert(shown or not drawn[page][label], page .. ' / ' .. label .. ' is drawn, so it is a result.');
        end;
    end;
end;
every_result(fresh());
every_result(fresh(function(s)
    bars(s); with_rule(true, 'remaining')(s); override('fixed')(s); hide_rule(s); detached(s); s.party_ui.enabled = true;
    s.party_ui.effects.timers, s.party_ui.effects.fit_all = true, false;
    s.overhead.head.offsets = { Crab = 1 };
    s.recast_display = 'combined';
end));

-- Each of the states counts.
assert(#require('ui.search_index').states >= 40, 'Fixture: the search key has room for every state.');
for index, state in ipairs(require('ui.search_index').states) do assert(type(state.on) == 'function', 'State ' .. index .. ' reads the settings.'); end;

-- Nothing is read with an empty box.
do
    local state = require('ui.search_index').states[1];
    local shown_reads, on = 0, state.on;
    state.on = function(...) shown_reads = shown_reads + 1; return on(...); end;
    local s = fresh();
    draw(s, 'Home'); draw(s, 'Home');
    assert(shown_reads == 0, 'With an empty box no state is read.');
    query = 'font';
    draw(s, 'Home');
    assert(shown_reads == 1, 'With text in the box each state is read once a frame.');
    query = '';
    draw(s, 'Home');
    state.on = on;
end;

-- The match line and its buttons, only with a match.
do
    local s = fresh();
    query = 'zzzz';
    draw(s, 'Home'); draw(s, 'Home');
    assert(seen('Button', 'Clear search'), 'A search can always be cleared.');
    assert(not seen('TextUnformatted', 'matching controls') and not seen('Button', 'Previous match') and not seen('Button', 'Next match'),
        'No match, so no match line and no buttons.');
    query = 'skin';
    draw(s, 'Home'); draw(s, 'Home');
    assert(seen('TextUnformatted', ' matching controls on this page') and seen('Button', 'Previous match') and seen('Button', 'Next match'),
        'A match brings them back.');
    query = '';
    draw(s, 'Home');
end;

-- A topic opens its page. Nothing on it to light up takes the search away; a match keeps it.
do
    local s = fresh();
    local function click(typed, name)
        query = typed;
        draw(s, 'Home');
        MOCK.clicks[name] = true;
        draw(s, 'Home');
        MOCK.clicks = {};
    end;
    local function box()
        local value;
        local read = imgui.InputTextWithHint;
        imgui.InputTextWithHint = function(label, hint, text, ...)
            if label == '##find_settings' then value = text[1]; end;
            return read(label, hint, text, ...);
        end;
        draw(s, s.window.tab);
        imgui.InputTextWithHint = read;
        return value;
    end;
    click('passive', 'Understand timing evidence and limits  /  Help');
    assert(s.window.tab == 'Help' and box() == '', 'No match on the page: the page opens and the search goes.');
    click('record', 'Local diagnostic report  /  Help');
    assert(s.window.tab == 'Help' and box() == 'record', 'A match on the page: the search stays and lights it up.');
    query = '';
    draw(s, 'Home');
    -- A topic for a display opens it as a link does.
    click('wav', 'Alert sounds and notices  /  Alerts');
    assert(s.window.tab == 'Display' and require('ui.panel_frame').context() == 'notices/show' and box() == '', 'A topic says the display, and goes there.');
    query = '';
    draw(s, 'Home');
end;

-- While the box holds text the search goes by what the page last read of the profiles, so it never reads their file.
do
    local real, reads = app.callbacks.profile_summary, 0;
    app.callbacks.profile_summary = function(...) reads = reads + 1; return real(...); end;
    local s = fresh();
    require('ui.panel_frame').open('notices', 'show');
    draw(s, 'Display');
    reads, query = 0, 'font';
    draw(s, 'Display');
    draw(s, 'Display');
    assert(reads == 0, 'The search reads no profile file: ' .. reads);
    app.callbacks.profile_summary = real;
    local function offered()
        for _, result in ipairs(window.search('undo the last profile change')) do
            if result.tab == 'Profiles' and result.label == 'Undo the last profile change' then return true; end;
        end;
        return false;
    end;
    assert(not offered(), 'With nothing to recover the search leaves it out.');
    require('ui.profiles_page').seen = { recover_available = true };
    assert(offered(), 'With something to recover it is there.');
    query = '';
    draw(s, 'Home');
end;

-- The search knows the 18 jobs a rule can tick. A job past PUP leads nowhere, and a rule that holds one shows no tick for
-- it. The word geo is in Dungeons, on a When to show tab, and the word run is in Trigger's Time running low.
do
    require('ui.panel_frame').open('notices', 'show');
    draw(fresh(), 'Display');
    for _, job in ipairs({ 'DNC', 'dnc', 'sch' }) do assert(#window.search(job) == 0, job .. ' finds nothing.'); end;
    assert(not found('geo', 'Display', 'New alert') and not found('RUN', 'Display', 'RUN'), 'Neither is a tick to find.');
    for _, job in ipairs({ 'WAR', 'BLU', 'PUP' }) do assert(found(job, 'Display', 'New alert'), job .. ' leads to New alert.'); end;
    local s = fresh(with_rule(false));
    s.alerts.rules[1].jobs[19] = true;
    draw(s, 'Display');
    assert(not seen('Checkbox', 'DNC##frame_alert') and not found('DNC', 'Display', 'DNC'), 'A rule that holds one shows no tick for it.');
end;
MOCK.fire('unload');
return true;
