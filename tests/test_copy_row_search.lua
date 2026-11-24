-- The search finds Copy this tab to on every panel with another of its kind to copy to, whichever tab the panel is open on.
-- Each display starts a session on Show, which has no copy, and Size and place has none either. One panel for all has
-- nothing to copy to, so it has none to find.
local h = require('panel_fixture')();
local EVERY = 'party/look self_buffs/look self_debuffs/look spell_recasts/look target/look watch/look';

local function found(query)
    local list = {};
    for _, result in ipairs(h.window.search(query)) do
        if result.tab == 'Display' and result.label == 'Copy this tab to' then list[#list + 1] = result.panel .. '/' .. tostring(result.place); end;
    end;
    table.sort(list);
    return table.concat(list, ' ');
end;

-- A new session: every panel is on Show.
h.fresh();
h.draw();
local on_show = { found('Copy this tab to'), found('Same look'), found('Copy to all panels') };
for _, id in ipairs({ 'self_buffs', 'self_debuffs', 'target', 'party', 'watch', 'recasts' }) do h.on(id, 'place'); end;
local on_place = found('Copy this tab to');
assert(on_show[1] == EVERY and on_show[2] == EVERY and on_show[3] == EVERY and on_place == EVERY,
    ('With every panel on Show the search finds Copy this tab to on [%s], by Same look on [%s], by Copy to all panels on [%s]; on Size and place on [%s]')
        :format(on_show[1], on_show[2], on_show[3], on_place));

-- The box lists it, and the result opens the panel's Look with the row on it.
h.on('self_buffs', 'show');
h.typed['##find_settings'] = 'Copy this tab to';
h.draw();
assert(h.called('Selectable', 'Copy this tab to  /  Self buffs, Look'), 'The search box lists it.');
h.draw('Copy this tab to  /  Self buffs, Look');
h.draw();
assert(h.panels.context() == 'self_buffs/look' and h.called('BeginCombo', '##frame_Copy this tab to'), 'The result opens Look, where it is: ' .. h.panels.context());

-- Show still doesn't draw it, and One panel for all has nothing to find.
h.typed['##find_settings'] = '';
h.on('self_buffs', 'show');
assert(not h.called('BeginCombo', '##frame_Copy this tab to'), 'Show has no Copy this tab to.');
h.fresh(function(s) s.recast_display = 'combined'; end);
h.on('recasts', 'look');
assert(not found('Copy this tab to'):find('recasts', 1, true), 'One panel for all has none to find: ' .. found('Copy this tab to'));
MOCK.fire('unload');
return 'The search finds Copy this tab to from any tab';
