-- Put party buffs back beside the party list (ui/party_size_widget.lua): the way back from panels of their own, on
-- Party & alliance, whenever a group whose strip is shown is in a panel of its own. It puts every group in
-- a panel back beside the game's rows, a hidden strip's group too, keeps the strips' saved offsets and each panel's
-- saved size and place, is one Undo step, works while Locked and leaves the lock alone. Icons fill the room beside the
-- rows, so their size slider is for a panel of its own, and nothing is ever too big for the room: there is no button
-- to put party buffs in a panel of their own. The result line and the slider follow.
local defaults, store = require('ui.defaults'), require('core.store');
local imgui = require('imgui');
-- A 1920x1080 screen, where the game's rows are 14 px tall and 20 px apart.
MOCK.screen = { 1920, 1080 };

-- The game's party list: for each group { row height, step between rows, members }.
local function geometry(groups)
    local out = { available = true, groups = {} };
    for group, spec in pairs(groups) do
        local rows = {};
        for slot = 1, spec[3] or 3 do rows[slot] = { height = spec[1] }; end;
        out.groups[group] = { rows = rows, row_height = spec[1], pitch = spec[2], measured_by = 'rows' };
    end;
    return out;
end;

local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {},
    party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window, panels = require('ui.settings_window'), require('ui.panel_frame');
local game_rows;
local status = app.callbacks.party_native_status;
app.callbacks.party_native_status = function()
    local value = status();
    value.geometry = game_rows;
    return value;
end;
local sliders, texts = {}, {};
local slider_float, wrapped = imgui.SliderFloat, imgui.TextWrapped;
imgui.SliderFloat = function(label, value, low, high)
    sliders[label] = { low = low, high = high, value = value[1] };
    return false;
end;
imgui.TextWrapped = function(value, ...) if value ~= nil then texts[value] = true; end; return wrapped(value, ...); end;
local BACK = 'Put party buffs back beside the party list##frame';
local function buttons()
    local out = {};
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Button' then out[call[2]:match('###(.*)$') or call[2]] = true; end; end;
    return out;
end;
local view = { rows = {}, context = { valid = true, job = 3 } };
local function draw(page, tab, clicks)
    local s = app.state.settings;
    s.window.open, s.window.tab = true, page;
    if tab then panels.open('party_ui', tab); end;
    sliders, texts, MOCK.imgui_calls = {}, {}, {};
    for label in pairs(clicks or {}) do MOCK.clicks[label] = true; end;
    window.draw(s, view, app.callbacks);
    assert(not next(MOCK.clicks), 'The control is on the page: ' .. tostring(next(MOCK.clicks)));
    MOCK.clicks = {};
    assert(#MOCK.font_stack == 0);
end;
local function history() app.callbacks.save(); return app.callbacks.history_status(); end;
local function fresh(change)
    local s = defaults.tidy(defaults.make());
    s.party_ui.enabled, s.party_ui.effects.icon_size = true, 37;
    if change then change(s); end;
    app.state.settings, app.state.history, app.state.redo, app.state.transaction = s, {}, {}, nil;
    app.state.settings_revision = app.state.settings_revision + 1;
    return s;
end;
-- A group in a panel of its own, moved and sized by hand, with its strip's offsets and side set.
local function in_panel(s, group)
    local saved = s.party_ui.groups[group];
    saved.native_detached, saved.native_side, saved.native_x, saved.native_y = true, 'right', 30, -12;
    saved.detached_x, saved.detached_y, saved.detached_width, saved.detached_height = 700 + group, 300 + group, 380 + group, 260 + group;
end;
local function kept(s, group)
    local saved = s.party_ui.groups[group];
    return saved.native_side == 'right' and saved.native_x == 30 and saved.native_y == -12 and saved.detached_x == 700 + group
        and saved.detached_y == 300 + group and saved.detached_width == 380 + group and saved.detached_height == 260 + group;
end;

-- The icons fill the step beside the rows: 20 px for these rows.
game_rows = geometry({ { 14, 20 } });
local SIZE = '##frame_Icon size in a panel of its own';
-- No group in a panel: no way back, no icon size and no result line.
local s = fresh();
draw('Display', 'place');
assert(not buttons()[BACK] and not sliders[SIZE], 'Nothing in a panel: no way back and no icon size.');
assert(texts["Beside the game's party list the icons fill the step from one row to the next (20 px here), with no space between them."]
    and not texts['In a panel of its own: 37 px.'], 'Only the line about the step.');

-- The party in a panel of its own, Locked: the way back shows, and the slider runs the whole range and says the size
-- the icons draw at in the panel, so there is no result line.
s = fresh(function(value) in_panel(value, 1); value.party_ui.locked = true; end);
draw('Display', 'place');
local shown = buttons();
assert(shown[BACK], 'In a panel: the way back.');
assert(sliders[SIZE].high == 128, 'In a panel: the whole range.');
assert(sliders[SIZE].value == 37 and not texts['In a panel of its own: 37 px.'], 'The slider says the size, with no result line.');
assert(history().undo == 0, 'Drawing writes nothing.');
draw('Display', 'place', { [BACK] = true });
local steps = history();
assert(not s.party_ui.groups[1].native_detached and kept(s, 1), 'Back beside the rows, with its offsets, side and panel kept.');
assert(s.party_ui.locked == true and steps.undo == 1 and steps.undo_label == 'Put party buffs back beside the party list', 'One Undo step while Locked, the lock left on.');
draw('Display', 'place');
shown = buttons();
assert(not sliders[SIZE] and not texts['In a panel of its own: 37 px.'], 'Every group beside the rows: no icon size and no result line.');
assert(not shown[BACK], 'The way back is gone.');
app.callbacks.undo();
s = app.state.settings;
assert(s.party_ui.groups[1].native_detached and kept(s, 1) and s.party_ui.locked == true, 'Undo puts it back in its panel.');

-- Every group in a panel goes back, a hidden strip's group too, so it isn't in a panel when its strip is shown again.
s = fresh(function(value) for group = 1, 3 do in_panel(value, group); end; value.party_ui.strips.alliance2 = false; end);
draw('Display', 'place', { [BACK] = true });
for group = 1, 3 do assert(not s.party_ui.groups[group].native_detached and kept(s, group), 'Group ' .. group .. ' is back.'); end;
assert(history().undo == 1, 'All three in one Undo step.');
-- Only a hidden strip's group in a panel offers no way back and no icon size: nothing they set shows.
s = fresh(function(value) in_panel(value, 3); value.party_ui.strips.alliance2 = false; end);
draw('Display', 'place');
assert(not buttons()[BACK] and not sliders[SIZE], 'A hidden strip\'s group in a panel: no way back and no icon size.');
-- The party in a panel with no other group shown: the way back, and the icon size slider runs the whole range.
game_rows = geometry({ { 14, 20 }, { 14, 20 } });
s = fresh(function(value) in_panel(value, 1); value.party_ui.strips.alliance1, value.party_ui.strips.alliance2 = false, false; end);
draw('Display', 'place');
shown = buttons();
assert(shown[BACK], 'The way back.');
assert(not sliders['##frame_Bar height'] and sliders[SIZE].high == 128, 'No bar height, and the icon size runs the whole range.');

imgui.SliderFloat, imgui.TextWrapped = slider_float, wrapped;
MOCK.fire('unload');
return 'The way back from panels of their own puts every group beside the rows and keeps their offsets and panels';
