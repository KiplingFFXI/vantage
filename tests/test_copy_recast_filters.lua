-- Copy this tab to on a recast panel's Filters gives the other kinds Show only names containing and Only recasts with a
-- known time. Its lists name recasts of its own kind, 10000 + spell, 20000 + ability and 30000 + item (core/recasts.lua
-- entry), so each other kind keeps its own Show only, Hide here, Pin first, renames and colors, and its rows.
local h = require('panel_fixture')();
local hud = require('ui.hud');
local custom = require('core.customization');
local defaults = require('ui.defaults');
local COPY = '##frame_Copy this tab to';
local LISTS = { 'include', 'exclude', 'pinned', 'labels', 'effect_colors' };

local function recast(kind, effect, name)
    return { domain = 'recast', kind = kind, effect = effect, name = name, present = true, status = 'known', deadline = 10, scope = 'self' };
end;
local view = { rows = { recast('ability', 20010, 'Provoke'), recast('item', 30005, 'Empress Band') }, context = { valid = true, party = {}, entities = {} } };
local function kept(id) return #hud.filter_rows(view, h.s.panels[id], id, h.s); end;
local function lists(id)
    local out = {};
    for _, key in ipairs(LISTS) do out[key] = defaults.copy(h.s.panels[id][key]); end;
    return out;
end;
-- Which of its own lists a panel lost, and what its Show only holds now.
local function lost(id, own)
    local out = {};
    for _, key in ipairs(LISTS) do
        if not custom.equal(h.s.panels[id][key], own[key]) then out[#out + 1] = key; end;
    end;
    local ids = {};
    for effect in pairs(h.s.panels[id].include) do ids[#ids + 1] = tostring(effect); end;
    table.sort(ids);
    return table.concat(out, ', '), table.concat(ids, ', ');
end;

h.fresh(function(s)
    s.recast_display = 'separate';
    for _, id in ipairs({ 'spell_recasts', 'ability_recasts', 'item_recasts' }) do s.panels[id].enabled = true; end;
    local spells = s.panels.spell_recasts;
    spells.include, spells.exclude, spells.pinned, spells.known_only, spells.filter = { [10057] = true }, { [10001] = true }, { [10057] = true }, true, 'e';
    spells.labels, spells.effect_colors = { [10057] = 'Fast' }, { [10057] = { 0, 1, 0, 1 } };
    local abilities = s.panels.ability_recasts;
    abilities.exclude, abilities.pinned, abilities.labels = { [20012] = true }, { [20010] = true }, { [20010] = 'Taunt' };
    abilities.effect_colors = { [20010] = { 1, 0, 0, 1 } };
    s.panels.item_recasts.labels = { [30005] = 'Ring' };
end);
assert(kept('ability_recasts') == 1 and kept('item_recasts') == 1, 'Fixture: each kind keeps its row before the copy.');
local own = { spell_recasts = lists('spell_recasts'), ability_recasts = lists('ability_recasts'), item_recasts = lists('item_recasts') };

-- To one kind.
h.on('spell_recasts', 'filters');
assert(h.called('BeginCombo', COPY), 'Fixture: a recast panel\'s Filters has Copy this tab to.');
h.pick(COPY, 'Ability recasts##frame_copy_ability_recasts');
local ability = h.s.panels.ability_recasts;
assert(ability.known_only == true and ability.filter == 'e', 'Ability recasts takes Only recasts with a known time and the words.');
assert(h.app.callbacks.history_status().undo_label == 'Copy Filters to Ability recasts', 'One named Undo step.');
local gone, holds = lost('ability_recasts', own.ability_recasts);
local shows = kept('ability_recasts');
assert(gone == '' and shows == 1, ('Copy Filters to Ability recasts left it showing %d of 1 rows: its own %s changed, and its Show only holds %s')
    :format(shows, gone, holds));

-- To every other one.
h.pick(COPY, 'Every other panel##frame_copy_all');
for _, id in ipairs({ 'ability_recasts', 'item_recasts' }) do
    gone, holds = lost(id, own[id]);
    shows = kept(id);
    assert(h.s.panels[id].known_only == true and h.s.panels[id].filter == 'e', id .. ' takes the tick and the words.');
    assert(gone == '' and shows == 1, ('Copy Filters to every other panel left %s showing %d of 1 rows: its own %s changed, and its Show only holds %s')
        :format(id, shows, gone, holds));
end;
gone = lost('spell_recasts', own.spell_recasts);
assert(gone == '', 'The panel copied from keeps its lists: ' .. gone);
h.draw('Undo');
h.draw();
assert(not h.s.panels.item_recasts.known_only and h.s.panels.item_recasts.filter == '', 'Undo takes the copy back.');
MOCK.fire('unload');
return 'A recast panel\'s Filters copy leaves each kind its own lists';
