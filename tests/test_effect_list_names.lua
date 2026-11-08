-- The client names debuffs in lowercase and gives ids 119 to 125 the names of 80 to 86, as ROM/180/102.DAT has them. So
-- every list a player picks from sorts without regard to case, on its id when two read the same, and no two rows of an
-- effect list share a name. Each sort runs only when its list is rebuilt.
local store = require('core.store');
local SNAP = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(SNAP); end };
package.loaded['core.observer'] = { read = function() return {}; end, wear_off = 'Observed wearoff' };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, status = function() return { active = false }; end };
local imgui = require('imgui');
local defaults = require('ui.defaults');

local client = { [2] = 'sleep', [3] = 'poison', [13] = 'slow', [33] = 'Haste', [40] = 'Protect', [90] = 'Accuracy Boost',
    [80] = 'STR Boost', [81] = 'DEX Boost', [82] = 'VIT Boost', [83] = 'AGI Boost', [84] = 'INT Boost', [85] = 'MND Boost', [86] = 'CHR Boost',
    [119] = 'STR Boost', [120] = 'DEX Boost', [121] = 'VIT Boost', [122] = 'AGI Boost', [123] = 'INT Boost', [124] = 'MND Boost', [125] = 'CHR Boost' };
local spells = { [1] = 'cure', [2] = 'Cure II', [57] = 'Haste', [3] = 'Cure III', [108] = 'regen' };
local abilities = { [20] = { 'berserk', 1, 2 }, [21] = { 'Aggressor', 4, 2 }, [24] = { 'Warcry', 2, 2 } };
AshitaCore.GetResourceManager = function() return {
    GetString = function(_, _, id) return client[id]; end,
    GetSpellById = function(_, id) return spells[id] and { Name = { spells[id] } } or nil; end,
    GetAbilityById = function(_, id)
        local ability = abilities[id - 0x200];
        return ability and { Name = { ability[1] }, RecastTimerId = ability[2], Type = ability[3], Id = id } or nil;
    end,
}; end;
local app = dofile(ADDON_DIR .. '/vantage.lua');
local window = require('ui.settings_window');
MOCK.fire('load'); app.refresh(0);

local combo, previews = nil, {};
imgui.BeginCombo = function(label, preview) previews[label] = preview; return label == combo; end;
local view = { rows = {}, context = { valid = true, job = 3, entities = {} } };
local function frame(step)
    step = step or {};
    combo, previews, MOCK.imgui_calls = step.combo, {}, {};
    if step.click then MOCK.clicks[step.click] = true; end
    window.draw(app.state.settings, view, app.callbacks);
    assert(not step.click or not MOCK.clicks[step.click], 'The control is on the page: ' .. tostring(step.click));
    MOCK.clicks = {};
end;
local function begin(tab, setup)
    local s = defaults.tidy(defaults.make());
    s.window.open, s.window.tab = true, tab;
    if setup then setup(s); end
    app.state.settings = defaults.tidy(s);
    app.state.settings_revision = app.state.settings_revision + 1;
    frame();
end;
local panels = require('ui.panel_frame');
local function alerts(setup)
    panels.open('notices', 'show');
    begin('Display', setup);
end;
-- The names a picker drew, in order, by the start of their labels' ids.
local function drawn(tag)
    local out = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Selectable' then
            local name = call[2]:match('^(.-)##' .. tag);
            if name then out[#out + 1] = name; end;
        end;
    end;
    return out;
end;
local function in_order(names, label)
    for index = 2, #names do
        assert(names[index - 1]:lower() <= names[index]:lower(), label .. ': ' .. names[index - 1] .. ' before ' .. names[index]);
    end;
end;
local function place(names, name)
    for index, value in ipairs(names) do if value == name then return index; end; end;
    error('Not in the list: ' .. name);
end;

-- Seven names read twice in the client, and each of the second seven now has its own.
local catalog = require('core.catalog');
for id, name in pairs({ [119] = 'STR Boost II', [120] = 'DEX Boost II', [121] = 'VIT Boost II', [122] = 'AGI Boost II', [123] = 'INT Boost II',
    [124] = 'MND Boost II', [125] = 'CHR Boost II' }) do
    assert(catalog.get(id).name == name, 'The client\'s name doesn\'t replace it: ' .. id);
    assert(catalog.get(id - 39).name == name:sub(1, -4), 'The first of the pair keeps the client\'s name: ' .. id - 39);
end;

-- catalog.list: every row once, by name, whatever the case.
local list, names = catalog.list(), {};
local seen = {};
for index, row in ipairs(list) do
    names[index] = row.name;
    assert(not seen[row.name], 'No two rows read the same: ' .. row.name);
    seen[row.name] = true;
end;
in_order(names, 'catalog.list');
assert(place(names, 'Accuracy Boost') < place(names, 'AGI Boost'), 'Case doesn\'t put AGI Boost first.');
assert(place(names, 'poison') < place(names, 'Protect') and place(names, 'sleep') < place(names, 'slow'), 'A lowercase debuff sits among the others.');
assert(place(names, 'Haste') < place(names, 'poison'), 'A lowercase debuff is not sorted past the capitals.');

-- A name in two cases, or twice, goes by id.
local recast_rows = require('core.recasts').catalog('spell');
local spell_names = {};
for index, row in ipairs(recast_rows) do spell_names[index] = row.name; end;
in_order(spell_names, 'recasts.catalog');
assert(table.concat(spell_names, '|') == 'cure|Cure II|Cure III|Haste|regen', 'Recast spells: ' .. table.concat(spell_names, '|'));

-- The pickers the settings draw: an alert rule's effects, and a recast rule's with what joined it.
local rule = defaults.rule('alert_1');
require('ui.alert_panel').edit('alert_1');
alerts(function(s) s.alerts.rules = { rule }; end);
frame({ combo = '##Effect' });
local effects = drawn('effect_');
assert(#effects == #list, 'The alert picker draws every row: ' .. #effects);
in_order(effects, 'An alert rule\'s effects');
local unique = {};
for _, name in ipairs(effects) do
    assert(not unique[name], 'An alert rule shows one row of each name: ' .. name);
    unique[name] = true;
end;
alerts(function(s)
    local recast = defaults.rule('alert_2');
    recast.domain, recast.event, recast.scope = 'recast', 'ready', 'self';
    s.alerts.rules = { recast };
    require('ui.alert_panel').edit('alert_2');
end);
view.rows = { { domain = 'recast', effect = 30123, name = 'warp ring', kind = 'item', group = 'item_recasts' } };
frame();
frame({ combo = '##Recast' });
local recasts_drawn = drawn('effect_');
in_order(recasts_drawn, 'A recast rule');
assert(place(recasts_drawn, 'Aggressor') < place(recasts_drawn, 'berserk') and place(recasts_drawn, 'berserk') < place(recasts_drawn, 'cure')
    and place(recasts_drawn, 'Warcry') < place(recasts_drawn, 'warp ring'), 'Recasts sort without regard to case: ' .. table.concat(recasts_drawn, '|'));
view.rows = {};

-- A live effect joining the list keeps the order, as does a saved one.
view.rows = { { domain = 'status', effect = 650, name = 'bebop', group = 'Other' } };
require('ui.alert_panel').edit('alert_1');
alerts(function(s) s.alerts.rules = { rule }; end);
frame({ combo = '##Effect' });
effects = drawn('effect_');
in_order(effects, 'With a live effect');
assert(place(effects, 'bebop') < place(effects, 'CHR Boost'), 'A live effect takes its place.');
view.rows = {};

-- Timer durations.
begin('Durations');
frame({ combo = '##Override applies to', click = 'A spell##spell' });
frame({ combo = '##What to override' });
local actions = {};
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'Selectable' and tostring(call[2]):find('##%d+$') then actions[#actions + 1] = call[2]:match('^(.-)##'); end;
end;
assert(#actions >= 4, 'Fixture: the spell picker has rows: ' .. #actions);
in_order(actions, 'Timer durations');

-- A panel's kinds of effects.
panels.open('self_buffs', 'filters');
begin('Display');
local groups = {};
for _, call in ipairs(MOCK.imgui_calls) do
    local name = call[1] == 'Checkbox' and call[2]:match('^(.-)##filter_');
    if name then groups[#groups + 1] = name; end;
end;
assert(#groups >= 3, 'Fixture: the groups are on the page.');
in_order(groups, 'Groups shown by this panel');

-- A settled frame sorts no list of names.
local sort, sorts = table.sort, 0;
table.sort = function(values, ...)
    if type(values[1]) == 'table' and values[1].name and debug.getinfo(2, 'S').source:find('settings_window', 1, true) then sorts = sorts + 1; end;
    return sort(values, ...);
end;
alerts(function(s) s.alerts.rules = { rule }; end);
sorts = 0;
for _ = 1, 3 do frame({ combo = '##Effect' }); end;
table.sort = sort;
assert(sorts == 0, 'A settled frame sorted a list ' .. sorts .. ' times.');
