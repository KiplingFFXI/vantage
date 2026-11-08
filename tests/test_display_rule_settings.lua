-- Party list buffs has no hidden count switch and no no-timer color, the main page's Colors has no color for untimed
-- effects, and the field editor no switch to hide a field with no value.
local defaults, hud = require('ui.defaults'), require('ui.hud');
local window, imgui = require('ui.settings_window'), require('imgui');

-- Colors, under More look on the main page.
local s, view = defaults.make(), hud.sample(100);
s.window.open, s.window.tab = true, 'Home';
local cb = { now = function() return 100; end, save = function() return true; end, changed = function() end,
    profile_list = function() return {}; end, profile_status = function() return {}; end,
    history_status = function() return { undo = 0, redo = 0 }; end, sound_files = function() return {}; end };
imgui.BeginCombo = function() return true; end;
local function frame(click)
    if click then MOCK.clicks[click] = true; end;
    MOCK.imgui_calls = {};
    window.draw(s, view, cb);
end;
frame();
local colors = {};
for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'ColorEdit4' then colors[call[2]] = true; end; end;
for _, name in ipairs({ 'Buffs', 'Debuffs', 'Estimated timers', 'Ending soon and alerts', 'Bar track' }) do
    assert(colors[name .. '##main_color'], 'Fixture: Colors shows ' .. name);
end;
for _, name in ipairs({ 'Unknown time', 'Untimed effects' }) do
    assert(not colors[name .. '##main_color'], 'Colors has no color for untimed effects: ' .. name);
end;
for _, name in ipairs({ 'Unknown time', 'Untimed effects' }) do
    for _, result in ipairs(window.search(name)) do
        assert(tostring(result.label) ~= name, 'Search finds no untimed effect color: ' .. name);
    end;
end;

-- Party list buffs.
local panels = require('ui.panel_frame');
local labels = {};
s.party_ui.groups[1].style = { colors = {} };
s.window.tab = 'Display';
for _, tab in ipairs(panels.tabs) do
    panels.open('party_ui', tab.key);
    frame();
    for _, call in ipairs(MOCK.imgui_calls) do
        if type(call[2]) == 'string' then labels[call[2]:match('^##frame_(.+)$') or call[2]:match('^(.-)##') or call[2]] = true; end;
    end;
end;
-- The party list buffs wear the timer panels' colors, so the panel has no colors of its own either.
assert(labels['Countdowns'] and labels['Party buff icons'], 'Fixture: the panel draws its controls.');
for _, label in ipairs({ 'Show hidden effect count', 'Party no-timer color', 'Group no-timer color', 'Party unknown color',
    'Party buff color', 'Party debuff color' }) do
    assert(not labels[label], 'The panel doesn\'t offer ' .. label);
end;

-- A panel's matching count and its empty line take the shared Detail text color, which the window offers.
local fonts, theme = require('ui.fonts'), require('ui.theme');
local inks, plain_paint = {}, fonts.paint;
fonts.paint = function(gui, list, style, value, x, y, size, tint, ...)
    inks[value] = tint;
    return plain_paint(gui, list, style, value, x, y, size, tint, ...);
end;
local painted = defaults.make();
painted.style.font, painted.style.minimal = 'Ashita', false;
painted.style.detail_color, painted.style.unknown_color = { 0.2, 0.9, 0.3, 1 }, { 0.9, 0.1, 0.1, 1 };
for id, panel in pairs(painted.panels) do panel.enabled = id == 'target'; end;
local empty_panel = painted.panels.target;
empty_panel.mode, empty_panel.empty, empty_panel.show_heading, empty_panel.locked = 'bars', 'show', true, true;
local empty_view = hud.sample(100);
empty_view.rows = {};
hud.draw(empty_view, painted, 100, {});
fonts.paint = plain_paint;
assert(inks['No matching effects'] and inks['0'], 'Fixture: the empty panel draws its count and its empty line.');
assert(inks['No matching effects'] == theme.u32(painted.style.detail_color), 'The empty line takes the Detail text color.');
assert(inks['0'] == theme.u32(painted.style.detail_color), 'The matching count takes the Detail text color.');

-- The field editor has no switch to hide a field with no value: such a field is always left out.
for _, name in ipairs({ 'Hide this field when it has no value', 'Hide this field when unknown' }) do
    for _, result in ipairs(window.search(name)) do
        assert(tostring(result.label) ~= name, 'Search finds no switch to hide a field with no value: ' .. name);
    end;
end;

-- Fresh settings have only the keys something reads.
local fresh = defaults.make();
assert(fresh.party_ui.effects.overflow == nil and fresh.panels.self_buffs.field_known_only == nil
    and type(fresh.style.unknown_color) == 'table', 'Fresh settings have only the keys something reads.');
return 'The window has no marker or untimed color settings';
