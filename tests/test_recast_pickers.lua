-- The recast pickers offer what exists on Phoenix, by data/actions.lua: no Trust and no Helix, and an ability timer only
-- if one of its abilities is listed. Job special and items stay. core/recasts.lua keeps every name, for live rows and
-- for what the settings name: one seen live joins the list while it's live, and a saved one shows by name on every list
-- that can hold it, and can be taken out there. With no client names nothing is marked, and a live row then has only a
-- word and a number for a name, so it is left out. So is a catalog row named that way, and a saved one reads in words.
local store = require('core.store');
local SNAP = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(SNAP); end };
package.loaded['core.observer'] = { read = function() return {}; end, wear_off = 'Observed wearoff' };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, status = function() return { active = false }; end };
local imgui = require('imgui');
local defaults = require('ui.defaults');

local spells = { [57] = 'Haste', [278] = 'Geohelix', [896] = 'Shantotto' };
-- By action id: name, timer, type. Timer 3 has one ability on the list and one off it, and timer 186 none.
local abilities = { [16] = { 'Mighty Strikes', 0, 1 }, [20] = { 'Berserk', 1, 2 }, [22] = { 'Defender', 3, 2 }, [191] = { 'Curing Waltz II', 3, 2 },
    [190] = { 'Curing Waltz', 186, 2 }, [195] = { 'Divine Waltz', 186, 2 } };
local named = true;
AshitaCore.GetResourceManager = function() return {
    GetString = function() return nil; end,
    GetSpellById = function(_, id) return named and spells[id] and { Name = { spells[id] } } or nil; end,
    GetAbilityById = function(_, id)
        local ability = named and abilities[id - 0x200];
        return ability and { Name = { ability[1] }, RecastTimerId = ability[2], Type = ability[3], Id = id } or nil;
    end,
}; end;
local app = dofile(ADDON_DIR .. '/vantage.lua');
local window = require('ui.settings_window');
local panels = require('ui.panel_frame');
MOCK.fire('load'); app.refresh(0);

local HASTE, HELIX, TRUST = 10057, 10278, 10896;
local SHARED, WALTZES = 'Curing Waltz II / Defender (shared)', 'Curing Waltz / Divine Waltz (shared)';
local combo, typed, previews = nil, nil, {};
imgui.BeginCombo = function(label, preview) previews[label] = preview; return label == combo; end;
local input = imgui.InputText;
imgui.InputText = function(label, value, ...)
    if typed and typed[1] == label then value[1], typed = typed[2], nil; return true; end
    return input(label, value, ...);
end;
local view = { rows = {}, context = { valid = true, job = 3, entities = {} } };
local function frame(step)
    step = step or {};
    combo, typed, previews, MOCK.imgui_calls = step.combo, step.typed, {}, {};
    if step.click then MOCK.clicks[step.click] = true; end
    window.draw(app.state.settings, view, app.callbacks);
    assert(not step.click or not MOCK.clicks[step.click], 'The control is on the page: ' .. tostring(step.click));
    assert(not typed, 'The box is on the page: ' .. tostring(step.typed and step.typed[1]));
    MOCK.clicks = {};
end;
local function drew(kind, label)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == kind and call[2] == label then return true; end end
    return false;
end;
local function begin(tab, setup)
    local s = defaults.tidy(defaults.make());
    s.window.open, s.window.tab = true, tab;
    if setup then setup(s); end
    app.state.settings = defaults.tidy(s);
    app.state.settings_revision = app.state.settings_revision + 1;
    frame();
    return app.state.settings;
end;
-- A recast panel's Filters tab, with the list open.
local function filters(panel, setup)
    panels.open(panel, 'filters');
    local s = begin('Display', setup);
    frame({ combo = '##frame_Recast' });
    return s;
end;
-- The Recasts panel's Show tab, with the pulse on so its list shows.
local function general(setup)
    panels.open('recasts', 'show');
    return begin('Display', function(s)
        s.ready_pulse.enabled = true;
        if setup then setup(s); end;
    end);
end;
local function listed(name, id) return drew('Selectable', name .. '##' .. id); end;
local function recast_rule(s, id)
    local rule = defaults.rule('alert_1');
    rule.name, rule.domain, rule.event, rule.scope, rule.effect = 'Saved recast', 'recast', 'ready', 'self', id;
    s.alerts.rules = { rule };
end;

-- core/recasts.lua keeps them all, and marks what the pickers leave out.
local recasts = require('core.recasts');
local marks = {};
for _, kind in ipairs({ 'spell', 'ability' }) do
    for _, row in ipairs(recasts.catalog(kind)) do marks[row.name] = row.unlisted == true; end;
end;
assert(marks.Haste == false and marks.Geohelix == true and marks.Shantotto == true, 'Spells go by data/actions.lua, and stay in the catalog.');
assert(marks.Berserk == false and marks[SHARED] == false and marks[WALTZES] == true, 'A timer stays if one of its abilities is listed.');
assert(marks['Job special (shared)'] == false, 'Job special always stays.');

-- Spell recasts, Ability recasts and Combined recasts.
filters('spell_recasts');
assert(listed('Haste', HASTE), 'Fixture: the spell list has Haste.');
assert(not listed('Geohelix', HELIX) and not listed('Shantotto', TRUST), 'Spell recasts offer no Helix and no Trust.');
filters('ability_recasts');
assert(listed('Berserk', 20001) and listed(SHARED, 20003) and listed('Job special (shared)', 20000), 'Ability recasts offer what exists on Phoenix.');
assert(not listed(WALTZES, 20186), 'Ability recasts offer no timer with nothing on the list.');
filters('recasts', function(s) s.recast_display = 'combined'; end);
assert(listed('Haste', HASTE) and listed('Berserk', 20001), 'Fixture: the combined list has both kinds.');
assert(not listed('Shantotto', TRUST) and not listed(WALTZES, 20186), 'Combined recasts leave out the same.');

-- A recast alert rule and Never pulse for.
require('ui.alert_panel').edit('alert_1');
panels.open('notices', 'show');
begin('Display', function(s) recast_rule(s, 0); end);
frame({ combo = '##Recast' });
assert(drew('Selectable', 'Haste##effect_' .. HASTE) and drew('Selectable', 'Berserk##effect_20001'), 'Fixture: an alert rule offers both kinds.');
assert(not drew('Selectable', 'Shantotto##effect_' .. TRUST) and not drew('Selectable', 'Geohelix##effect_' .. HELIX), 'An alert rule offers no Trust and no Helix.');
assert(not drew('Selectable', WALTZES .. '##effect_20186'), 'An alert rule offers no timer with nothing on the list.');
general();
frame({ combo = '##Never pulse for' });
assert(drew('Selectable', 'Haste##effect_' .. HASTE) and not drew('Selectable', 'Shantotto##effect_' .. TRUST), 'Never pulse for offers no Trust.');

-- One seen live joins the list while it's live.
view.rows = { { domain = 'recast', effect = TRUST, name = 'Shantotto', kind = 'spell', group = 'spell_recasts' } };
filters('spell_recasts');
assert(listed('Shantotto', TRUST), 'A recast seen live joins the list.');
view.rows = {};
frame({ combo = '##frame_Recast' });
assert(not listed('Shantotto', TRUST), 'It leaves with the row.');

-- A row with no mark stays listed, as an item is.
local catalog_of = app.callbacks.recast_catalog;
app.callbacks.recast_catalog = function() return { { id = 30123, name = 'Warp Ring', kind = 'item', group = 'item_recasts' } }; end;
filters('item_recasts');
assert(listed('Warp Ring', 30123), 'A row with no mark stays listed.');
app.callbacks.recast_catalog = catalog_of;

-- Saved in a recast panel: its lists, its label and color and My order.
local s = filters('spell_recasts', function(s)
    local p = s.panels.spell_recasts;
    p.include[HELIX], p.exclude[HELIX], p.pinned[HELIX], p.labels[HELIX], p.effect_colors[HELIX], p.order = true, true, true, 'Mine', { 1, 0, 0, 1 }, { HELIX };
end);
assert(listed('Geohelix', HELIX), 'A saved recast is in its panel\'s list, under the game\'s name.');
assert(not listed('Shantotto', TRUST), 'Saving one brings back no other.');
assert(drew('TextUnformatted', 'Geohelix') and drew('TextUnformatted', 'Geohelix as Mine'), 'The lists name a saved recast.');
for _ = 1, 6 do frame({ click = 'Remove##effect' }); end;
local p = app.state.settings.panels.spell_recasts;
assert(next(p.include) == nil and next(p.exclude) == nil and next(p.pinned) == nil and next(p.labels) == nil and next(p.effect_colors) == nil
    and #p.order == 0, 'A saved recast can be taken out of each of them.');
frame({ combo = '##frame_Recast' });
assert(not listed('Geohelix', HELIX), 'Taken out of the last one, it leaves the list.');

-- One saved in another panel is on the list of its own kind and no other.
filters('ability_recasts', function(s) s.panels.ability_recasts.exclude[20186] = true; end);
assert(listed(WALTZES, 20186), 'A saved ability timer is in its panel\'s list.');
frame({ click = 'Remove##effect' });
assert(next(app.state.settings.panels.ability_recasts.exclude) == nil, 'A saved ability timer can be taken out.');
filters('spell_recasts', function(s) s.panels.ability_recasts.exclude[20186] = true; end);
assert(not listed(WALTZES, 20186), 'A spell list holds no ability.');

-- Saved in an alert rule.
panels.open('notices', 'show');
s = begin('Display', function(s) recast_rule(s, TRUST); end);
assert(previews['##Recast'] == 'Shantotto', 'An alert rule names a saved recast.');
frame({ combo = '##Recast' });
assert(drew('Selectable', 'Shantotto##effect_' .. TRUST), 'An alert rule\'s picker offers a saved recast.');
frame({ combo = '##Recast', click = 'All recasts##all' });
assert(app.state.settings.alerts.rules[1].effect == 0, 'An alert rule can leave a saved recast.');
frame();
frame({ combo = '##Recast' });
assert(not drew('Selectable', 'Shantotto##effect_' .. TRUST), 'Left, it is offered no more.');

-- Saved in Never pulse for.
general(function(s) s.ready_pulse.ignore[TRUST] = true; end);
assert(drew('TextUnformatted', 'Shantotto'), 'Never pulse for names a saved recast.');
frame({ click = 'Pulse again' });
assert(next(app.state.settings.ready_pulse.ignore) == nil, 'Never pulse for can take a saved recast out.');

-- A frame with no change walks nothing, a change that saves no recast sorts nothing, and one that saves a recast does.
filters('spell_recasts');
local kept = window.saved_recasts();
frame({ combo = '##frame_Recast' });
assert(window.saved_recasts() == kept, 'Frames with no change don\'t walk the settings.');
local sort, sorts = table.sort, 0;
table.sort = function(values, ...)
    if type(values[1]) == 'table' and values[1].kind and debug.getinfo(2, 'S').source:find('settings_window', 1, true) then sorts = sorts + 1; end;
    return sort(values, ...);
end;
app.state.settings_revision = app.state.settings_revision + 1;
frame();
assert(window.saved_recasts() ~= kept and sorts == 0, 'A change that saves no recast doesn\'t rebuild the list.');
app.state.settings.panels.spell_recasts.exclude[HELIX] = true;
app.state.settings_revision = app.state.settings_revision + 1;
frame({ combo = '##frame_Recast' });
table.sort = sort;
assert(sorts > 0 and listed('Geohelix', HELIX), 'A change that saves one does.');

-- Undo and Redo on the header swap the settings in the middle of a draw, and the list follows them.
filters('spell_recasts', function(s) s.panels.spell_recasts.exclude[HELIX] = true; end);
app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
app.callbacks.changed('before', 'Take it out');
app.state.settings.panels.spell_recasts.exclude[HELIX] = nil;
app.callbacks.changed('after');
frame({ combo = '##frame_Recast' });
assert(not listed('Geohelix', HELIX), 'Fixture: taken out, it leaves the list.');
frame({ click = 'Undo' });
frame({ combo = '##frame_Recast' });
assert(listed('Geohelix', HELIX), 'Undo puts a saved recast back on the list.');
frame({ click = 'Redo' });
frame({ combo = '##frame_Recast' });
assert(not listed('Geohelix', HELIX), 'Redo takes it off again.');

-- With no client names nothing is marked, nothing names a saved id, and a live row, named by a word and a number, is
-- left out.
named = false;
package.loaded['core.recasts'] = nil;
local bare = require('core.recasts');
assert(#bare.catalog('spell') == 0, 'No client names, no spells.');
for _, row in ipairs(bare.catalog('ability')) do assert(not row.unlisted and row.id == 20000, 'No client names, only Job special.'); end;
app.callbacks.recast_catalog = bare.catalog;
view.rows = { { domain = 'recast', effect = TRUST, name = 'Spell 896', kind = 'spell', group = 'spell_recasts' },
    { domain = 'recast', effect = HASTE, name = 'Haste', kind = 'spell', group = 'spell_recasts' } };
filters('spell_recasts', function(s) s.panels.spell_recasts.exclude[HELIX] = true; end);
assert(listed('Haste', HASTE), 'Fixture: a live row with a name joins the open list.');
assert(not listed('Spell 896', TRUST), 'A live row with no name stays out of the list.');
assert(not listed('Geohelix', HELIX), 'Nothing names a saved id.');

-- A catalog row the client has no name for, a spell, an ability timer or an item, is left out of every list, and a saved
-- one reads in words.
view.rows = {};
app.callbacks.recast_catalog = function() return { { id = TRUST, name = 'Spell 896', kind = 'spell', group = 'spell_recasts' },
    { id = 20186, name = 'Ability timer 186', kind = 'ability', group = 'ability_recasts' },
    { id = 30123, name = 'Item 123', kind = 'item', group = 'item_recasts' }, { id = 30124, name = 'Warp Ring', kind = 'item', group = 'item_recasts' } }; end;
filters('item_recasts');
assert(listed('Warp Ring', 30124), 'Fixture: an item with a name is listed.');
assert(not listed('Item 123', 30123), 'An item with no name is left out.');
filters('ability_recasts');
assert(not listed('Ability timer 186', 20186), 'An ability timer with no name is left out.');
panels.open('notices', 'show');
begin('Display', function(s) recast_rule(s, TRUST); end);
assert(previews['##Recast'] == 'A recast with no name', 'A saved one reads in words: ' .. tostring(previews['##Recast']));
frame({ combo = '##Recast' });
assert(drew('Selectable', 'Warp Ring##effect_30124'), 'Fixture: the alert rule list is open.');
assert(not drew('Selectable', 'Spell 896##effect_' .. TRUST) and not drew('Selectable', 'Item 123##effect_30123')
    and not drew('Selectable', 'Ability timer 186##effect_20186'), 'An alert rule offers none of them.');
app.callbacks.recast_catalog = bare.catalog;
