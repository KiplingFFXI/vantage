-- The party list buffs: Your party, Alliance 1 and Alliance 2 each have their own tick, and Show sets each as one Undo
-- step. Party list buffs says once and plainly where alliance effects come from, and offers only what the
-- strips use.
local defaults, party = require('ui.defaults'), require('ui.party_defaults');
local equal = require('core.customization').equal;
local fresh = defaults.make();
assert(equal(fresh.party_ui.strips, { party = true, alliance1 = true, alliance2 = true }), 'A fresh install has every strip on.');
assert(equal(defaults.tidy(defaults.copy(fresh)).party_ui.strips, fresh.party_ui.strips), 'Saved switches are kept.');
local off = defaults.copy(fresh.party_ui); for _, key in ipairs(party.strips) do off.strips[key] = false; end;
party.ensure_strip(off); assert(off.strips.party and not off.strips.alliance1, 'Turning the strips on with all three off shows the party strip.');
for _, word in ipairs({ 'unknown', '?' }) do assert(not party.strip_help:lower():find(word, 1, true), 'The help never says ' .. word); end;

-- The panel.
local h = require('panel_fixture')();
local custom = require('core.customization');
local settings = h.fresh(function(s) s.party_ui.enabled = true; end);
local before = custom.history_value(settings);
local labels = h.every_tab('party_ui');
assert(equal(custom.history_value(h.s), before) and #h.app.state.history == 0, 'Opening every tab changes nothing.');
for _, label in ipairs({ 'Buff side', 'Longest row', 'Countdowns', 'Party buff icons', 'Opacity', 'Find an effect' }) do
    assert(labels[label], 'The panel has ' .. label);
end;
-- The group ticks, what kind of effects show and the light are on Show.
h.on('party_ui', 'show');
for _, label in ipairs({ 'Your party##frame_strip', 'Alliance 1##frame_strip', 'Alliance 2##frame_strip', 'Light up debuffs you can remove##frame' }) do
    assert(h.called('Checkbox', label), 'Show has ' .. label);
end;
assert(h.called('RadioButton', 'Buffs only##frame_Show_kinds_buff'), 'Show has the kinds.');
for _, label in ipairs({ 'Show party strip', 'Show alliance strip 1', 'Show alliance strip 2', 'Effect types' }) do
    assert(not labels[label], 'Not a row of its own: ' .. label);
end;
-- The party list buffs always show every effect, grow with their buffs and keep each row next to the game's row, so the
-- panel has no control for any of that.
for _, label in ipairs({ 'Include effects without known timers', 'Show estimated timers', 'Member effect filters', 'Strip width',
    'Snap effects beside frame' }) do
    assert(not labels[label], 'Not on the panel: ' .. label);
end;
-- What only a panel of its own uses shows while a shown group is in one, and every name for it is "panel of its own".
-- Panels of their own, the switch that makes one, always shows.
local panel_only = { "Snap back beside the game's list when released", 'Put party buffs back beside the party list', 'Member order', 'Member names', 'Group to order' };
local other_names = { 'Snap buff panels to game windows', 'Reattach buff panels', 'Detached panel members', 'Snap panels of their own to game windows',
    'Reattach panels of their own', 'Member name display', 'Party group to edit' };
local function draw_with(change)
    h.fresh(function(s) s.party_ui.enabled = true; change(s.party_ui); end);
    return h.every_tab('party_ui');
end;
local shown = draw_with(function() end);
for _, label in ipairs(panel_only) do assert(not shown[label], 'With no group in a panel of its own, no ' .. label); end;
for _, label in ipairs(other_names) do assert(not shown[label], 'Nor ' .. label); end;
assert(shown['Panels of their own'] and shown['Your party in a panel of its own'], 'Panels of their own always shows.');
-- A line in the header names them, so with none there is no line.
local function panel_line()
    for name in pairs(h.drawn()) do
        if name:find(' in a panel of its own.', 1, true) or name:find(' in panels of their own.', 1, true) then return name; end;
    end;
end;
assert(not panel_line(), 'Nor a line that names them.');
-- A group whose row is hidden counts as no panel.
shown = draw_with(function(p) p.groups[1].native_detached, p.strips.party = true, false; end);
for _, label in ipairs(panel_only) do assert(not shown[label], 'With the only panel\'s group hidden, no ' .. label); end;
shown = draw_with(function(p) p.groups[1].native_detached = true; end);
for _, label in ipairs(panel_only) do assert(shown[label], 'With the party in a panel of its own: ' .. label); end;
assert(panel_line() == 'Your party is in a panel of its own.', 'The line names the group: ' .. tostring(panel_line()));
draw_with(function(p) p.groups[1].native_detached, p.groups[2].native_detached = true, true; end);
assert(panel_line() == 'Your party and Alliance 1 are in panels of their own.', 'Two groups: ' .. tostring(panel_line()));
draw_with(function(p) for group = 1, 3 do p.groups[group].native_detached = true; end; end);
assert(panel_line() == 'Your party, Alliance 1 and Alliance 2 are in panels of their own.', 'Three groups: ' .. tostring(panel_line()));
labels = draw_with(function() end);
-- Show is the one switch over the party list buffs.
assert(not labels['Show member effects'], 'Not on the panel: Show member effects.');
-- The strips draw icons only, in the timer panels' look and the one time format, so the panel has no look of their own
-- and no other effect display.
for _, label in ipairs({ 'Party skin', 'Party appearance', 'Individual group appearance', 'Separate group appearance',
    'Match timer panel appearance', 'Effect display', 'Show effect names', 'Show effect countdowns', 'Effect time format',
    'Ending soon threshold', 'Party effect color', 'Party effect label', 'Advanced effect layout' }) do
    assert(not labels[label], 'Not on the panel: ' .. label);
end;
for _, label in ipairs({ 'Party display', 'Members to display', 'Game windows to replace', 'Click a member to target', 'Party frame layout',
    'Selection indicator', 'Show HP', 'Party layout', 'Hide party windows during events' }) do
    assert(not labels[label], 'Not on the panel: ' .. label);
end;
local said = 0;
h.on('party_ui', 'show');
for _, call in ipairs(h.calls('TextWrapped')) do if call[2] == party.strip_help then said = said + 1; end; end;
for _, display in ipairs(h.panels._displays) do
    if display.id == 'party_ui' then
        for _, entry in ipairs(display.entries) do
            local help = tostring(entry.row.help);
            if help:find('Vantage sees', 1, true) or help:lower():find('alliance observation', 1, true) then said = said + 1; end;
        end;
    end;
end;
assert(said == 1, 'The panel says once where alliance effects come from, in its wrapped line and in no help.');
settings = h.fresh(function(s) s.party_ui.enabled = true; end);
before = defaults.copy(settings.party_ui);
h.on('party_ui', 'show');
h.draw('Alliance 1##frame_strip');
local history = h.app.state.history;
assert(not settings.party_ui.strips.alliance1 and #history == 1 and history[1].label == 'Alliance 1', 'A group tick is one Undo step.');
before.strips.alliance1 = false;
assert(equal(settings.party_ui, before), 'Switching a group off writes nothing else.');
assert(require('ui.search_index').controls.Display['Alliance 1']:find('Show the buffs beside alliance party 1.', 1, true), 'The tick says what it shows.');
h.draw('Light up debuffs you can remove##frame');
assert(settings.party_ui.effects.cleanse_light == true and #history == 2 and history[2].label == 'Light up debuffs you can remove', 'Light up writes its key as one Undo step.');
return true;
