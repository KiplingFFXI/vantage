local defaults, store, custom = require('ui.defaults'), require('core.store'), require('core.customization');
local window, imgui, hud = require('ui.settings_window'), require('imgui'), require('ui.hud');
local panels = require('ui.panel_frame');
-- Icon size in a panel of its own shows only while a group is in one. Before the window opens none counts as in one,
-- so its name finds each group's switch for that.
for _, entry in ipairs({ { 'Strip maximum width', 'Longest row' },
    { 'Icon size in a panel of its own', 'Your party in a panel of its own' } }) do
    local found = false;
    for _, result in ipairs(window.search(entry[1])) do found = found or result.tab == 'Display' and result.label == entry[2]; end;
    assert(found, 'Before opening their page, ' .. entry[1] .. ' finds ' .. entry[2]);
end;
local s, writes, edits = defaults.make(), 0, 0;
s.window.open = true;
local opened, combo = false, nil;
imgui.SetNextItemOpen = function(value) opened = value; end;
imgui.CollapsingHeader = function() return opened; end;
imgui.BeginCombo = function(label) return label == combo; end;
local cb = {
    save=function() writes = writes + 1; return true; end,
    editor_changed=function() end,
    changed=function(stage) if stage == 'before' then edits = edits + 1; end; end,
};
local function draw(click, picker)
    combo, MOCK.imgui_calls = picker, {};
    if click then MOCK.clicks[click] = true; end;
    window.draw(s, hud.sample(100), cb);
    if click then assert(not MOCK.clicks[click], 'Control is reachable: ' .. click); end;
    assert(#MOCK.font_stack == 0, 'Navigation keeps the font stack balanced.');
end;
local function called(kind, label)
    for _, value in ipairs(MOCK.imgui_calls) do if value[1] == kind and value[2] == label then return true; end; end;
    return false;
end;
local before = custom.history_value(s);
draw('Edit##main_self_buffs');
assert(s.window.tab == 'Display' and custom.equal(before, custom.history_value(s)) and edits == 0,
    'The main page\'s Edit only navigates and keeps current looks, sizes, filters and locks.');
s.window.tab = 'Home';
draw('Edit##main_hidden');
draw();
assert(s.window.tab == 'Display' and panels.context() == 'hidden/show' and called('Button', 'Pause this list##frame'),
    'The main page opens the single shared filter editor.');
s.window.tab = 'Filters';
draw();
assert(s.window.tab == 'Display' and panels.context() == 'hidden/show', 'The Filters page opens it.');
local function filters_of(id)
    s.window.tab = 'Display';
    panels.open(id, 'filters');
    draw();
end;
filters_of('party_ui');
assert(panels.context() == 'party_ui/filters');
assert(not called('Button', 'Pause this list##frame') and called('Button', 'Edit the list##frame'), 'Party list buff filtering is local and links the shared editor.');
draw('Size and place##frame_tab');
assert(panels.context() == 'party_ui/place' and not called('Button', 'Edit the list##frame'), 'The tabs go where they say.');
draw('Filters##frame_tab');
draw();
draw('Edit the list##frame');
assert(s.window.tab == 'Display' and panels.context() == 'hidden/show', 'Edit the list opens the shared editor.');
-- A panel's filters are on its panel.
for _, entry in ipairs({
    { 'self_debuffs', 'self_debuffs/filters', false },
    { 'spell_recasts', 'recasts/filters', true },
}) do
    filters_of(entry[1]);
    assert(s.window.tab == 'Display' and panels.context() == entry[2]);
    draw();
    assert(not called('Button', 'Pause this list##frame'), 'Local filtering never repeats the global editor.');
    assert(called('Button', 'Edit the list##frame') ~= entry[3], 'Shared status rules remain separate from recast filters.');
end;
local local_settings = store.copy({ s.panels, s.party_ui, s.alerts });
panels.open('hidden', 'show');
draw();
local count = edits;
local input_text = imgui.InputText;
imgui.InputText = function(label, value, ...)
    if label == '##frame_Find an effect' then value[1] = 'Level Sync'; return true; end;
    return input_text(label, value, ...);
end;
draw();
imgui.InputText = input_text;
draw('Hide it everywhere##frame');
assert(edits == count + 1 and #s.effect_filters.rules == 1 and s.effect_filters.rules[1].effect == 269);
draw();
draw('Remove##effect');
assert(edits == count + 2 and #s.effect_filters.rules == 0, 'Remove takes it off the list.');
assert(custom.equal(local_settings, { s.panels, s.party_ui, s.alerts }), 'Shared hiding keeps every local setting and lock.');

-- Links reach their pages without changing presentation.
local home = require('ui.main_page');
local draw_home, route = home.draw, nil;
for _, entry in ipairs({
    { { 'Home', nil, 'How it looks' }, 'Home' },
    { { 'Filters' }, 'Display', 'hidden/show' },
    { { 'Display', 'self_debuffs', 'filters' }, 'Display', 'self_debuffs/filters' },
}) do
    route = entry[1]; s.window.tab = 'Home'; count = edits;
    -- A nil panel must not truncate the destination argument.
    if route[3] then
        home.draw = function(_, _, _, _, controls) controls.open_page(route[1], route[2], route[3]); end;
    else home.draw = function(_, _, _, _, controls) controls.open_page(route[1], route[2]); end; end;
    draw();
    assert(s.window.tab == entry[2] and edits == count, 'Setup and filter links are navigation-only.');
    assert(not entry[3] or panels.context() == entry[3], 'A link opens where it says.');
end;
home.draw = draw_home;
assert(panels.context() == 'self_debuffs/filters');
local remembered = store.copy(s); remembered.window.tab = 'Filters';
defaults.tidy(remembered);
assert(remembered.window.tab == 'Home', 'A saved tab that is no page loads as Home.');
for _, term in ipairs({ 'Hide Signet everywhere', 'Affected player name', 'Affected main job' }) do
    local found = {};
    for _, result in ipairs(window.search(term)) do if result.tab == 'Display' and result.place then found[result.panel] = true; end; end;
    assert(found.hidden and next(found) == 'hidden' and next(found, 'hidden') == nil, 'Shared-rule search points to a single page: ' .. term);
end;
assert(#MOCK.commands == 0, 'Setup and filtering never issue gameplay commands.');
