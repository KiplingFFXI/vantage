-- Copy this tab to gives another panel of the same kind the settings on Look, Filters or When to show, as one Undo step.
-- The heading stays each panel's own, a key the other panel doesn't have stays out, and the copies are copies.
local h = require('panel_fixture')();
local custom = require('core.customization');
local COPY = '##frame_Copy this tab to';

-- What a tab draws, by label: each tick's value, each slider's and each list's choice.
local function values()
    local out = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Checkbox' then out[call[2]] = tostring(call[3][1]);
        elseif call[1] == 'SliderFloat' or call[1] == 'SliderInt' then out[call[2]] = tostring(call[3][1]);
        elseif call[1] == 'BeginCombo' and call[2] ~= COPY and call[2] ~= '##frame_switch' then out[call[2]] = tostring(h.previews[call[2]]); end;
    end;
    return out;
end;

-- Look: the target draws what the source draws.
h.fresh(function(s)
    local p = s.panels.self_buffs;
    p.mode, p.bar_style, p.gradient, p.show_source, p.title, p.label_position = 'bars', 'rail', true, true, 'Mine', 'after';
    p.colors.fill_start, p.field_order = { 0.2, 0.4, 0.6, 1 }, { 'time', 'name', 'target', 'source', 'elapsed', 'total' };
    s.panels.self_debuffs.mode = 'bars';
end);
h.on('self_buffs', 'look');
assert(h.called('BeginCombo', COPY), 'Look has Copy this tab to.');
local source = values();
h.pick(COPY, 'Self debuffs##frame_copy_self_debuffs');
local from, into = h.s.panels.self_buffs, h.s.panels.self_debuffs;
assert(into.bar_style == 'rail' and into.gradient == true and into.show_source == true and into.label_position == 'after',
    'The other panel takes the Look settings.');
assert(custom.equal(into.colors, from.colors) and into.colors ~= from.colors and custom.equal(into.field_order, from.field_order)
    and into.field_order ~= from.field_order, 'Tables come over as copies.');
assert(into.title ~= 'Mine', 'Its heading stays its own.');
assert(#h.app.state.history == 1 and h.app.callbacks.history_status().undo_label == 'Copy Look to Self debuffs', 'One named Undo step.');
h.on('self_debuffs', 'look');
local copied = values();
for label, value in pairs(source) do
    if copied[label] ~= nil and label ~= '##frame_Heading' then
        assert(copied[label] == value, 'Self debuffs draws ' .. label .. ' as Self buffs did: ' .. copied[label] .. ' / ' .. value);
    end;
end;
h.draw('Undo');
h.draw();
assert(not h.s.panels.self_debuffs.gradient and h.s.panels.self_debuffs.label_position ~= 'after' and #h.app.state.history == 0, 'Undo takes it back.');

-- A key only some panels have stays out: the light of what you can take off is on Target timers, not Self buffs.
h.fresh(function(s) s.panels.target.dispel_glow = false; end);
h.on('target', 'look');
h.pick(COPY, 'Self buffs##frame_copy_self_buffs');
assert(h.s.panels.self_buffs.dispel_glow == nil, 'Self buffs takes no light it has no row for.');

-- Filters, to every other panel at once.
h.fresh(function(s) s.panels.target.include, s.panels.target.mine_only = { 33 }, true; end);
h.on('target', 'filters');
h.pick(COPY, 'Every other panel##frame_copy_all');
for _, id in ipairs({ 'self_buffs', 'self_debuffs', 'party', 'watch' }) do
    local p = h.s.panels[id];
    assert(p.include[1] == 33 and p.mine_only == true and p.include ~= h.s.panels.target.include, id .. ' takes the filters.');
end;
assert(h.app.callbacks.history_status().undo_label == 'Copy Filters to every other panel', 'One Undo step for them all.');

-- When to show copies the conditions.
h.fresh(function(s) s.panels.self_buffs.conditions.level_min = 30; end);
h.on('self_buffs', 'when');
h.pick(COPY, "Party members' timers##frame_copy_party");
assert(h.s.panels.party.conditions.level_min == 30 and h.s.panels.party.conditions ~= h.s.panels.self_buffs.conditions,
    'The conditions come over as a copy.');

-- Show and Size and place have none, and a recast panel copies to the other two kinds, while each has one.
h.on('self_buffs', 'show');
assert(not h.called('BeginCombo', COPY), 'Show has no Copy this tab to.');
h.on('self_buffs', 'place');
assert(not h.called('BeginCombo', COPY), 'Size and place has none.');
h.fresh(function(s) s.recast_display = 'separate'; s.panels.spell_recasts.gradient = true; end);
h.on('spell_recasts', 'look');
h.pick(COPY, 'Item recasts##frame_copy_item_recasts');
assert(h.s.panels.item_recasts.gradient == true and not h.s.panels.ability_recasts.gradient, 'A recast panel copies to the kind picked.');
h.fresh(function(s) s.recast_display = 'combined'; end);
h.on('recasts', 'look');
assert(not h.called('BeginCombo', COPY), 'One panel for all has nothing to copy to.');
MOCK.fire('unload');
return 'Copy this tab to gives another panel this tab\'s settings, as one Undo step';
