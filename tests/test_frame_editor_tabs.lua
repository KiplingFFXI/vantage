local h = require('panel_fixture')();
local custom = require('core.customization');
local imgui, equal = h.imgui, custom.equal;
local tables, ended = 0, 0;
local original_table, original_end = imgui.BeginTable, imgui.EndTable;
imgui.BeginTable = function(...) tables = tables + 1; return original_table(...); end;
imgui.EndTable = function(...) ended = ended + 1; return original_end(...); end;
local function on(tab)
    h.on('party_ui', tab);
    assert(tables == ended, 'Responsive controls balance their layout state.');
    return h.drawn();
end;
-- Each row is on one tab. The party list buffs wear the timer panels' look, so Look has their icons and opacity.
local party_routes = {
    show = { 'Countdowns', 'Your own row', 'Most per member', 'Sort' },
    look = { 'Party buff icons', 'Opacity', 'Member names' },
    filters = { 'Edit the list', 'Find an effect', 'Show only' },
    place = { 'Icon size in a panel of its own', 'Longest row', 'Buff side', "Snap back beside the game's list when released", "Gap from the game's list", 'Icons fill', 'Group to order' },
};
do
    -- The icon size is for a panel of its own, so the party is in one here.
    local settings = h.fresh(function(s) s.party_ui.groups[1].native_detached = true; end);
    local before = custom.history_value(settings);
    for tab, expected in pairs(party_routes) do
        local observed = on(tab);
        for _, label in ipairs(expected) do assert(observed[label], tab .. ' exposes ' .. label); end;
        for other, unrelated in pairs(party_routes) do
            if other ~= tab then
                for _, label in ipairs(unrelated) do assert(not observed[label], 'Unrelated controls do not leak between tabs: ' .. label); end;
            end;
        end;
        assert(equal(custom.history_value(h.s), before) and #h.app.state.history == 0, 'Browsing tabs preserves every saved setting and lock.');
    end;
end;

local settings = h.fresh(function(s)
    local p = s.party_ui;
    p.locked = true;
    p.groups[2].native_x, p.groups[2].detached_x = -81, 481;
    p.effects.include = { 33 };
end);
local before = custom.history_value(settings);
on('filters');
h.draw('Edit the list##frame');
assert(h.panels.context() == 'hidden/show' and equal(custom.history_value(h.s), before), 'Edit the list opens Hidden everywhere and changes nothing.');

for _, width in ipairs({ 1100, 180, 820 }) do
    MOCK.content_width = width;
    local labels = on('place');
    assert(labels['Buff side'] and labels['Longest row'] and equal(custom.history_value(h.s), before),
        'Every width shows the party list layout without changing saved values.');
    -- With no group in a panel of its own, what only such a panel uses doesn't show.
    assert(not labels["Snap back beside the game's list when released"] and not labels['Put party buffs back beside the party list']
        and not on('look')['Member names'], 'Panel-only controls wait for a panel of its own.');
end;
local labels = on('look');
assert(labels['Party buff icons'] and labels['Opacity'] and equal(custom.history_value(h.s), before), 'The party list buffs keep their icon and opacity choices without mutation.');
MOCK.content_width = nil;
-- When to show says what still shows each display: edit mode doesn't place overhead icons, and the pulse has no samples.
do
    local header = imgui.CollapsingHeader;
    imgui.CollapsingHeader = function() return true; end;
    h.fresh();
    h.on('self_buffs', 'when');
    assert(h.says('Always, unless you choose something here.') and h.says('Samples and edit mode show it anyway.'), 'A panel shows in both.');
    h.on('overhead', 'when');
    assert(h.says('Always, unless you choose something here.') and h.says('Samples show it anyway.') and not h.says('edit mode'), 'Overhead icons have no edit mode.');
    h.s.ready_pulse.enabled = true;
    h.on('spell_recasts', 'when');
    assert(h.says('A test pulse and edit mode show it anyway.'), 'The pulse has a test one in place of samples.');
    imgui.CollapsingHeader = header;
end;
assert(#MOCK.commands == 0, 'Editing and browsing cannot issue gameplay commands.');
return 'Consistent party list tabs, saved settings and locks';
