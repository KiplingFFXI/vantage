-- A search result you click is the match the page picks. The control it names gets the thick outline, the view scrolls
-- to it and the match line counts it, even when a control drawn above it has the word in its help or other names.
-- tests/test_search_leads_to_switch.lua checks that the control lights up at all.
local store, defaults = require('core.store'), require('ui.defaults');
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {},
    party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window, imgui = require('ui.settings_window'), require('imgui');
local panels, theme = require('ui.panel_frame'), require('ui.theme');
local view = { rows = {}, context = { valid = true, job = 3, party = {}, entities = {} } };

-- What the search box holds from the next frame on.
local query;
local with_hint = imgui.InputTextWithHint;
imgui.InputTextWithHint = function(label, hint, value, ...)
    if label == '##find_settings' and query then value[1], query = query, nil; end;
    return with_hint(label, hint, value, ...);
end;

local function fresh()
    local s = defaults.tidy(defaults.make());
    s.window.tab = 'Home';
    app.state.settings_revision = (app.state.settings_revision or 0) + 1;
    return s;
end;

-- One frame of the window. Returns what it drew.
local function draw(s, click)
    s.window.open = true;
    app.state.settings = s;
    MOCK.imgui_calls = {};
    if click then MOCK.clicks[click] = true; end;
    window.draw(s, view, app.callbacks);
    if click then
        assert(MOCK.clicks[click] == nil, 'Fixture: the result is in the list to click: ' .. click);
        MOCK.clicks[click] = nil;
    end;
    return MOCK.imgui_calls;
end;

-- The control a light or a scroll belongs to: the last one drawn before it.
local controls = { SliderFloat = true, BeginCombo = true, Checkbox = true, RadioButton = true, Button = true, InputText = true,
    ColorEdit4 = true, CollapsingHeader = true, TextColored = true, Selectable = true };
local function owner(calls, at)
    for index = at - 1, 1, -1 do
        local call = calls[index];
        if controls[call[1]] then return call[1] .. ' ' .. tostring(call[1] == 'TextColored' and call[3] or call[2]); end;
    end;
    return 'nothing';
end;

-- The search's outlines in draw order: the warning color, rounding 2, 1 thick or 2 for the match picked.
local function lights(calls, s)
    local color, out = theme.u32(s.style.warning_color), {};
    for index, call in ipairs(calls) do
        if call[1] == 'draw:AddRect' and call[4] == color and call[5] == 2 and call[6] == 0 then
            out[#out + 1] = { thick = call[7] == 2, owner = owner(calls, index) };
        end;
    end;
    return out;
end;

-- Where the search scrolled to last in these frames, newest first.
local function scrolled(...)
    for _, calls in ipairs({ ... }) do
        local last;
        for index, call in ipairs(calls) do
            if call[1] == 'SetScrollHereY' and call[2] == 0.35 then last = owner(calls, index); end;
        end;
        if last then return last; end;
    end;
    return 'nowhere';
end;

local function match_line(calls)
    for _, call in ipairs(calls) do
        if call[1] == 'TextUnformatted' and tostring(call[2]):find(' matching controls on this page', 1, true) then return call[2]; end;
    end;
    return 'no match line';
end;

-- Types the words on the main page, clicks the result, then reads the frame after, once the pick has settled. control is
-- what the result names, as the mock records its draw call.
local wrong = {};
local function follow(typed, click, control, tab, context)
    local when = typed .. ' -> ' .. click;
    local s = fresh();
    query = '';
    draw(s);
    query = typed;
    draw(s); draw(s);
    local clicked = draw(s, click);
    local after = draw(s);
    assert(s.window.tab == tab, 'Fixture: ' .. when .. ' opens its page: ' .. tostring(s.window.tab));
    if context then assert(panels.context() == context, 'Fixture: ' .. when .. ' opens its display and tab: ' .. panels.context()); end;
    local lit, position, thick = lights(after, s), nil, {};
    for index, light in ipairs(lit) do
        if light.owner == control and not position then position = index; end;
        if light.thick then thick[#thick + 1] = light.owner; end;
    end;
    assert(position, 'Fixture: ' .. when .. ' draws ' .. control .. ' and lights it up.');
    assert(position > 1, 'Fixture: ' .. when .. ' has a match above ' .. control .. ', so match 1 is not it.');
    assert(#thick == 1, when .. ' has one thick outline: ' .. #thick);
    local line = match_line(after);
    local shown, total = tostring(line):match('^(%d+) of (%d+) matching');
    assert(shown and tonumber(total) == #lit, 'Fixture: ' .. when .. ' counts what lights up: ' .. line .. ' for ' .. #lit);
    local scroll = scrolled(after, clicked);
    if thick[1] ~= control or scroll ~= control or tonumber(shown) ~= position then
        wrong[#wrong + 1] = ('%s: outlined %s, scrolled to %s, line "%s", where %s is match %d'):format(when, thick[1], scroll, line, control, position);
    end;
end;

-- The main page lights Quick setup for a role first, as its help says sizes.
follow('size', 'Settings text size  /  Main page', 'SliderFloat ##main_window_text', 'Home');
-- Its whole name typed: Font comes first, as its help says Text sizes and it is also found by Settings font.
follow('settings text size', 'Settings text size  /  Main page', 'SliderFloat ##main_window_text', 'Home');
-- The window's own example word. Quick setup for a role's help says fonts too.
follow('font', 'Font  /  Main page', 'BeginCombo ##main_font', 'Home');
-- Help: Export report's help says event history, and the trailing s finds it.
follow('events', 'Record recent events  /  Help', 'Checkbox Record recent events', 'Help');
-- A row of the panel frame: Bigger or smaller draws above it on Self buffs' Size and place.
follow('fixed width', 'Fixed width  /  Self buffs, Size and place', 'SliderFloat ##frame_Fixed width', 'Display', 'self_buffs/place');
-- The header's Locked tick, found by Lock position and size, draws above every tab.
follow('size', 'Icon countdown size  /  Self buffs, Size and place', 'SliderFloat ##frame_Countdown size_countdown', 'Display', 'self_buffs/place');

assert(#wrong == 0, 'A clicked search result is the match picked: the thick outline, the scroll and the match line go to the control it names. '
    .. table.concat(wrong, '; '));

-- Every result on the main page, Timer durations, Profiles and Help, each found by its whole name, is the match picked.
-- tests/test_panel_search.lua does the same for every row of the panel frame.
do
    local names, typed = {}, nil;
    local light = window.light;
    window.light = function(text, named, label)
        if typed and window.matches(typed, text) then names[#names + 1] = label; end;
        return light(text, named, label);
    end;
    local pages = { Home = 'Main page', Durations = 'Timer durations', Profiles = 'Profiles and sharing', Help = 'Help' };
    local order, followed, wrong_pick = { 'Home', 'Durations', 'Profiles', 'Help' }, 0, {};
    local s = fresh();
    for _, page in ipairs(order) do s.window.tab = page; draw(s); end;
    local index = require('ui.search_index').controls;
    for _, page in ipairs(order) do
        local labels = {};
        for label in pairs(index[page]) do labels[#labels + 1] = label; end;
        table.sort(labels);
        for _, label in ipairs(labels) do
            for _, result in ipairs(window.search(label)) do
                if result.tab == page and result.label == label and not result.topic then
                    s.window.tab, query, typed = 'Home', label, label;
                    draw(s);
                    draw(s, label .. '  /  ' .. pages[page]);
                    names = {};
                    local shown = tonumber(tostring(match_line(draw(s))):match('^(%d+) of'));
                    if names[shown] ~= label then wrong_pick[#wrong_pick + 1] = page .. ' / ' .. label .. ' picked ' .. tostring(names[shown]); end;
                    followed, query, typed = followed + 1, '', nil;
                    draw(s);
                    break;
                end;
            end;
        end;
    end;
    window.light = light;
    assert(followed > 100, 'Fixture: the results of every page are followed: ' .. followed);
    assert(#wrong_pick == 0, 'Each result is the match picked: ' .. table.concat(wrong_pick, '; '));
end;

MOCK.fire('unload');
return 'A clicked search result is the match picked: outlined, scrolled to and counted, on every page';
