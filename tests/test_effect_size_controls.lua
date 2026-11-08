local defaults, store = require('ui.defaults'), require('core.store');
local window, hud, imgui = require('ui.settings_window'), require('ui.hud'), require('imgui');
local settings = defaults.make();
settings.window.open = true;
local pending, seen = {}, {};
local original_slider = imgui.SliderFloat;
imgui.SliderFloat = function(label, value, low, high, ...)
    seen[label] = { low = low, high = high };
    if pending[label] ~= nil then value[1], pending[label] = pending[label], nil; return true; end;
    return original_slider(label, value, low, high, ...);
end;
local callbacks = { now = function() return 100; end, changed = function() end,
    save = function() return true; end };
local panels = require('ui.panel_frame');
local function frame(page, click, label, value, tab)
    if tab then panels.open('party_ui', tab); end;
    settings.window.tab, seen = page, {};
    if click then MOCK.clicks[click] = true; end;
    if label then pending['##' .. label] = value; end;
    window.draw(settings, hud.sample(100), callbacks);
    assert(not next(pending), 'The requested size control is reachable on its display page');
    assert(#MOCK.font_stack == 0, 'Display controls balance font state');
end;
local function searchable(page, label, query)
    for _, result in ipairs(window.search(query or label)) do
        if result.tab == page and result.label == label then return true; end;
    end;
    return false;
end;
for _, spec in ipairs({
    {'Display','Most per member'}, {'Home','Icon size'},
}) do assert(searchable(spec[1], spec[2]), 'The control is searchable before opening its page: ' .. spec[2]); end;
assert(searchable('Display', 'Most per member', 'Show all matching effects'), 'Another name finds it.');
assert(searchable('Home', 'Icon size', 'Timer icon size'), 'Another name finds it.');
-- Icon size in a panel of its own shows only while a group is in one. Before the window opens none counts as in one,
-- so its name finds each group's switch for that.
assert(searchable('Display', 'Your party in a panel of its own', 'Icon size in a panel of its own')
    and not searchable('Display', 'Icon size in a panel of its own'), 'Before opening its page, Icon size in a panel of its own finds the switches.');
for _, page in ipairs({ 'Panels', 'Recasts' }) do
    assert(not searchable(page, 'Icon size'), 'Icon size is not found on ' .. page);
end;

local effects = settings.party_ui.effects;
effects.icon_size = 48;
effects.max, effects.fit_all = 7, false;
settings.party_ui.style.icon_art = 'XI View';
local party_lock = settings.party_ui.locked;
local global_size = settings.style.icon_size;
-- The icon size is for a panel of its own, so it shows while a group is in one.
settings.party_ui.groups[1].native_detached = true;
frame('Display', nil, 'frame_Icon size in a panel of its own', 12, 'place');
assert(effects.icon_size == 12, 'The quick size control sets the icon pixels at once');
assert(searchable('Display', 'Icon size in a panel of its own'), 'With a group in a panel of its own, the search finds it.');
assert(seen['##frame_Icon size in a panel of its own'].low == 12 and seen['##frame_Icon size in a panel of its own'].high == 128);
assert(settings.style.icon_size == global_size, 'Party icon sizing does not change status icons');
assert(settings.party_ui.style.icon_art == 'XI View' and settings.party_ui.locked == party_lock,
    'Icon sizing retains XI View icons and the saved lock');
settings.party_ui.groups[1].native_detached = false;
frame('Display', nil, 'frame_Most per member', 0, 'show');
assert(effects.fit_all and effects.max == 7, 'All that fit retains the saved manual limit');
assert(seen['##frame_Most per member'].low == 0 and seen['##frame_Most per member'].high == 32, 'One number holds both, with 0 for All that fit.');
frame('Display', nil, 'frame_Most per member', 7);
assert(not effects.fit_all and effects.max == 7, 'A number ends All that fit.');

-- More look has the common size control; Status timers and Recasts don't draw it.
frame('Home', nil, 'main_icon_size', 12);
assert(settings.style.icon_size == 12, 'The common size control changes status and recast icons');
assert(seen['##main_icon_size'].low == 12 and seen['##main_icon_size'].high == 64);
assert(defaults.tidy(store.copy(settings)).style.icon_size == 12, 'Twelve-pixel status icons survive settings normalization');
assert(settings.party_ui.effects.icon_size == 12, 'Shared timer size leaves the party size independent');
frame('Home', nil, 'main_icon_size', 64);
assert(settings.style.icon_size == 64 and settings.party_ui.effects.icon_size == 12, 'The full common icon range stays available');
for _, page in ipairs({ 'Panels', 'Recasts' }) do
    frame(page);
    assert(not seen['##main_icon_size'], 'Icon size is not on ' .. page);
end;

-- Party list buff icons don't use Icon size, and its help says so.
local function helps(page, words)
    for _, result in ipairs(window.search(words)) do
        if result.tab == page and result.label == 'Icon size' then return true; end;
    end;
    return false;
end;
settings.window.tab = 'Home';
window.draw(settings, hud.sample(100), callbacks);
assert(helps('Home', "party list buff icons don't use it fill the step between its rows panel of its own"),
    'Icon size says party list buff icons don\'t use it.');
assert(#MOCK.commands == 0, 'Display customization never issues gameplay commands');
imgui.SliderFloat = original_slider;
return 'Reachable effect sizing and automatic-fitting controls preserve manual choices';
