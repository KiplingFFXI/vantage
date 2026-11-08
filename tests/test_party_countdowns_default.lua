-- Party buffs start as icons only, with no countdown under them (ui/party_defaults.lua). No place that makes default or
-- preset party settings turns the countdowns on: fresh settings and a fresh install, a save missing the key, Apply
-- setup and Apply size at every size and skin, a skin, Reset all and the party reset, the starters, exports made
-- from fresh settings, and the samples. A save keeps its own choice, through Apply setup, Apply size and a skin too,
-- and Countdowns on Party & alliance still turns them on, as one Undo step. There is no
-- display choice or names switch: the strips draw icons only.
local defaults, store, party_defaults = require('ui.defaults'), require('core.store'), require('ui.party_defaults');
local customization, presets = require('core.customization'), require('setup_fixture');
local appearance, share = require('ui.appearance'), require('core.share');
MOCK.screen = { 1920, 1080 };

-- Fresh settings, and a fresh install's load.
local p = party_defaults.make();
assert(p.effects.timers == false and p.effects.mode == nil and p.effects.names == nil, 'Fresh: icons only, no countdown.');
assert(defaults.make().party_ui.effects.timers == false);
assert(defaults.tidy({}).party_ui.effects.timers == false and defaults.tidy(nil).party_ui.effects.timers == false, 'A fresh install.');

-- A save keeps its own choice. A save without the key takes the default.
for _, saved in ipairs({ true, false }) do
    local value = defaults.make();
    value.party_ui.effects.timers = saved;
    assert(defaults.tidy(store.copy(value)).party_ui.effects.timers == saved, 'A saved ' .. tostring(saved) .. ' is kept.');
    assert(party_defaults.tidy(store.copy(value.party_ui)).effects.timers == saved);
end;
local old = defaults.make();
old.party_ui.effects.timers = nil;
assert(defaults.tidy(old).party_ui.effects.timers == false, 'A save without the key: no countdown.');

-- Apply setup and Apply size, at every size, with the current skin and each skin; a skin alone too. Each keeps the
-- player's own choice: off stays off, and on stays on.
local sizes = { 'minimal', 'minimal_1_5x', 'minimal_2x' };
for _, start in ipairs({ false, true }) do
    for _, size in ipairs(sizes) do
        for _, skin in ipairs({ 'keep', 'Original FFXI', 'XI View', 'Phoenix', 'Minimal' }) do
            local s = defaults.tidy(defaults.make());
            s.party_ui.effects.timers = start;
            assert(presets.apply(s, { skin = skin, size = size, matching = true, window_type = 1, screen_width = 1920, screen_height = 1080 }),
                'Fixture: ' .. skin .. ' at ' .. size .. ' applies.');
            assert(s.party_ui.effects.timers == start, 'Apply setup ' .. skin .. ' at ' .. size .. ' keeps ' .. tostring(start) .. '.');
        end;
    end;
    for _, skin in ipairs(appearance.names) do
        local s = defaults.tidy(defaults.make());
        s.party_ui.effects.timers = start;
        presets.apply_skin(s, { skin = skin, matching = true, window_type = 1 });
        assert(s.party_ui.effects.timers == start, 'Skin ' .. skin .. ' keeps ' .. tostring(start) .. '.');
    end;
end;
-- Reset all, the party reset and the starters.
for _, scope in ipairs({ 'all', 'party_ui' }) do
    local s = defaults.tidy(defaults.make());
    s.party_ui.effects.timers = true;
    local reset = customization.reset(s, scope);
    assert(reset.party_ui.effects.timers == false, 'Reset ' .. scope .. ': no countdown.');
end;
for _, name in ipairs(require('core.starters').ids) do
    assert(require('core.starters').apply(defaults.tidy(defaults.make()), name).party_ui.effects.timers == false, 'Starter ' .. name);
end;

-- Exports made from fresh settings hold no countdown, and taking one in, Add or Replace, adds none.
for _, kind in ipairs({ 'element', 'profile' }) do
    local text = assert(share.export(defaults.tidy(defaults.make()), kind, kind == 'element' and 'party_ui' or nil));
    local payload = assert(share.read(text));
    local data = kind == 'element' and payload.data or payload.data.party_ui;
    assert(data.effects.timers == false, 'A ' .. kind .. ' string from fresh settings: no countdown.');
    for _, mode in ipairs({ 'add', 'replace' }) do
        local candidate = assert(share.candidate(defaults.tidy(defaults.make()), payload, mode));
        assert(candidate.party_ui.effects.timers == false, kind .. ' ' .. mode .. ': no countdown.');
    end;
end;

-- The sample displays draw no countdown with fresh settings, and one under each timed icon once it is on.
local overlay, party_hud, layout = require('ui.native_party_hud'), require('ui.party_hud'), require('ui.party_layout');
local roster, subjects = party_hud.sample(6, 100);
local frame = { x = 900, y = 40, width = 116, height = 132, rows = {} };
for _, member in ipairs(roster.members) do
    frame.rows[member.slot] = { x = 900, y = 40 + member.slot * 22, width = 116, height = 22, slot = member.slot };
end;
local function countdowns(config)
    local count = 0;
    for _, item in ipairs(overlay.plan(roster, subjects, config, { available = true, groups = { frame } }, 1920, 1080)[1].rows) do
        for _, cell in ipairs(layout.effect_cells(item.effects, item.options, item.area)) do
            if cell.countdown then count = count + 1; end;
        end;
    end;
    return count;
end;
local config = party_defaults.make();
config.enabled, config.preview = true, true;
assert(countdowns(config) == 0, 'Samples with fresh settings: icons only.');
config.effects.timers = true;
assert(countdowns(config) > 0, 'Samples with countdowns turned on: they show.');

-- Countdowns on Party & alliance still turns them on.
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {},
    party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
assert(app.state.settings.party_ui.effects.timers == false, 'The app starts without party countdowns.');
local window, panels = require('ui.settings_window'), require('ui.panel_frame');
local view = { rows = {}, context = { valid = true, job = 3 } };
local function fresh()
    local s = defaults.tidy(defaults.make());
    s.party_ui.enabled = true;
    app.state.settings, app.state.history, app.state.redo, app.state.transaction = s, {}, {}, nil;
    return s;
end;
local function draw(page, tab, click)
    local s = app.state.settings;
    s.window.open, s.window.tab = true, page;
    if tab then panels.open('party_ui', tab); end;
    MOCK.clicks[click] = true;
    window.draw(s, view, app.callbacks);
    assert(not MOCK.clicks[click], 'The control is on the page: ' .. click);
    MOCK.clicks = {};
end;
local s = fresh();
draw('Display', 'show', 'Countdowns##frame');
app.callbacks.save();
local steps = app.callbacks.history_status();
assert(s.party_ui.effects.timers == true and steps.undo == 1 and steps.undo_label == 'Countdowns', 'Countdowns on, one Undo step.');
MOCK.fire('unload');
return 'Party buffs start without countdowns, nothing but the player turns them on, and Apply keeps the choice';
