local defaults, custom = require('ui.defaults'), require('core.customization');
local store, imgui = require('core.store'), require('imgui');
local copy, equal = store.copy, custom.equal;
local expected = {
    { 'minimal', '1x', 1 },
    { 'minimal_1_5x', '1.5x', 1.5 },
    { 'minimal_2x', '2x', 2 },
};
-- A setup takes 1x, 1.5x and 2x.
for _, name in ipairs({ 'extended', 'minimal1.5x', 'extended_1_5x', 'extended_2x', 'compact', 'original', 'native_compact', 'invalid' }) do
    assert(require('setup_fixture').apply(defaults.make(), { size = name, skin = 'keep' }) == false,
        'Only the three sizes are setup variants.');
end;

local fonts = require('ui.fonts');
fonts.measure = function(_, value, size) return #value * size * .4; end;
MOCK.screen = { 4000, 3000 };
local app, window, panels = dofile(ADDON_DIR .. '/vantage.lua'), require('ui.settings_window'), require('ui.panel_frame');
local combo, inputs;
local slider = imgui.SliderFloat;
imgui.BeginCombo = function(label) return label == '##' .. tostring(combo); end;
imgui.SliderFloat = function(label, value, ...)
    if inputs and inputs[label] ~= nil then value[1], inputs[label] = inputs[label], nil; return true; end;
    return slider(label, value, ...);
end;
local function value() return custom.history_value(app.state.settings); end;
local function difference(a, b, path)
    if type(a) ~= type(b) then return path .. ': ' .. type(a) .. ' ~= ' .. type(b); end;
    if type(a) == 'number' and math.abs(a - b) < 1e-12 then return nil; end;
    if type(a) ~= 'table' then return a ~= b and path .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b) or nil; end;
    for key, entry in pairs(a) do
        local found = difference(entry, b[key], path .. '.' .. tostring(key));
        if found then return found; end;
    end;
    for key in pairs(b) do if a[key] == nil then return path .. '.' .. tostring(key) .. ': added'; end; end;
end;
local function frame(tab, category, click, opened, numbers)
    local s = app.state.settings;
    s.window.open, s.window.tab = true, tab;
    if category then panels.open('party_ui', category); end;
    combo, inputs = opened, numbers;
    MOCK.clicks = click and { [click] = true } or {};
    window.draw(s, { rows={}, context={} }, app.callbacks);
    if click then assert(not MOCK.clicks[click], 'The transition uses a reachable control: ' .. click); end;
    assert(not inputs or next(inputs) == nil, 'Every requested manual control was edited.');
    assert(#MOCK.font_stack == 0);
end;
local function action(tab, category, label, opened, numbers)
    local before, count = value(), #app.state.history;
    frame(tab, category, label, opened, numbers);
    local after = value();
    assert(not equal(before, after) and #app.state.history == count + 1, 'One user action records one settings transaction.');
    assert(app.callbacks.undo() and equal(value(), before), 'Undo restores the exact complete settings state before the transition.');
    assert(app.callbacks.redo() and equal(value(), after), 'Redo restores the exact complete settings state after the transition.');
    return after;
end;
for _, size in ipairs(expected) do
    for _, skin in ipairs({ 'Original FFXI', 'XI View', 'Mint' }) do
        local s = defaults.make();
        s.party_ui.locked, s.party_ui.groups[1].native_x, s.party_ui.groups[2].native_detached = true, -14, true;
        s.party_ui.groups[2].detached_x, s.party_ui.groups[2].detached_y = 317, 219;
        s.party_ui.effects.icon_size = 41;
        s.panels.self_buffs.x, s.panels.self_buffs.y, s.panels.self_buffs.locked = 701, 130, false;
        s.panels.self_buffs.exclude = { 33 };
        s.job_profiles, s.active_profile = { ['1']='Saved support' }, 'Saved support';
        app.state.settings = defaults.tidy(s);
        app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
        -- The skin and the size, each picked on the main page. A Size button at the size in use does nothing.
        frame('Home', nil, skin .. '##' .. skin, 'main_skin');
        local original = value();
        if size[3] == 1 then
            frame('Home', nil, size[2] .. '##main_size');
            assert(equal(value(), original), 'The size already in use changes nothing.');
        else
            action('Home', nil, size[2] .. '##main_size');
        end;
        s = app.state.settings;
        assert(s.style.scale == size[3], 'A Size button gives the size it names: ' .. size[1]);
        assert(s.party_ui.locked and s.party_ui.groups[1].native_x == -14 and s.party_ui.groups[2].native_detached
            and s.party_ui.groups[2].detached_x == 317 and s.party_ui.groups[2].detached_y == 219
            and not s.panels.self_buffs.locked, 'A Size button keeps the strip places and every lock.');
        assert(s.party_ui.effects.icon_size == 41, 'A Size button keeps the icon size in a panel of its own.');
        -- A Size button writes nothing that nothing reads.
        assert(s.party_ui.width == nil and s.party_ui.frame_layout == nil
            and s.party_ui.effects.icon_scale == nil and s.party_ui.style.font_size == nil,
            'A Size button writes no setting that nothing reads.');
        assert(equal(s.job_profiles, original.job_profiles) and s.active_profile == original.active_profile);
        -- The party list buffs wear the timer panels' look; their opacity is their own.
        action('Display', 'look', nil, nil, { ['##frame_Opacity']=0.5 });
        s = app.state.settings;
        assert(s.party_ui.style.opacity == 0.5 and s.style.scale == size[3], 'A manual strip opacity after a Size button keeps the size.');
        local path = MOCK_INSTALL_PATH .. '/config/addons/vantage/sizing-transition.json';
        assert(store.write(path, s));
        local loaded = defaults.tidy(assert(store.read(path)));
        local persisted, normalized = custom.history_value(loaded), custom.history_value(defaults.tidy(copy(s)));
        local changed = difference(persisted, normalized, 'settings');
        assert(changed == nil, 'A JSON reload preserves the complete normalized manual setup within encoded float precision: '
            .. tostring(changed));
        assert(loaded.party_ui.style.opacity == 0.5 and loaded.style.scale == size[3]
            and loaded.panels.self_buffs.exclude[33] == true, 'Saved sizes and filters survive the full transition chain.');
        app.state.settings, app.state.history, app.state.redo, app.state.transaction = loaded, {}, {}, nil;
        action('Home', nil, nil, nil, { ['##main_blink_seconds']=20 });
        assert(app.state.settings.party_ui.effects.blink_seconds == 20 and app.state.settings.party_ui.style.opacity == 0.5,
            'Editing after reload remains independent and undoable.');
    end;
end;
assert(#MOCK.commands == 0, 'Sizing, appearance, persistence and Undo never issue gameplay commands.');
return 'Shared size recipes and size-to-manual-to-save/reload transitions with exact real Undo.';
