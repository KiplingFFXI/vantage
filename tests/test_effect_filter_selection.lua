-- Choosing a party effect on Party list, Filters: one list, with its own box to find a name, and nothing is picked
-- until you choose one. Picking changes no setting, only a tick or button under it does. The names are kept while the
-- list they come from doesn't change, and a pick the list no longer has is let go.
local h = require('panel_fixture')();
local copy, equal = require('core.store').copy, require('core.customization').equal;
local status, editor = require('ui.status_panel'), require('ui.effect_settings');
local entries = { { id = 107, name = 'Barpoison' }, { id = 3, name = 'Poison' }, { id = 33, name = 'Haste' } };
local named = status.named;
status.named = function() return entries; end;
local PICK = '##Effect';
local s = h.fresh(function(saved)
    local e = saved.party_ui.effects;
    e.include, e.exclude, e.pinned = { 33 }, { 4 }, { 8 };
end);
local e = s.party_ui.effects;
local before = copy(e);
h.on('party_ui', 'filters');
-- What the list offers, by id.
local function choices()
    h.combo = PICK;
    h.draw();
    h.combo = nil;
    local offered = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        local id = call[1] == 'Selectable' and tostring(call[2]):match('##effect_(%d+)$');
        if id then offered[#offered + 1] = tonumber(id); end;
    end;
    h.draw();
    return offered;
end;

assert(h.previews[PICK] == 'Choose an effect' and not h.called('Checkbox', 'Show only##frame'),
    'Nothing is picked at first, so nothing under the list can change an effect.');
assert(#choices() == 3, 'The list offers every effect.');
h.choose('Poison', 3);
assert(h.previews[PICK] == 'Poison' and h.called('Checkbox', 'Show only##frame'), 'The pick shows by name, with the ticks under it.');
assert(equal(e, before) and #h.app.state.history == 0, 'Picking changes only what the list holds.');
-- The party list draws icons only, so a picked effect has no label or color to set.
local names = h.drawn();
assert(not names['Party effect label'] and not names['Party effect color'], 'The picked effect offers no label or color.');

local selection = {};
editor.selection(entries, selection);
local labels = selection.labels;
editor.selection(entries, selection);
assert(selection.labels == labels and labels[3] == 'Poison', 'An unchanged list keeps its names.');

h.draw('Show only##frame');
assert(e.include[1] == 33 and e.include[2] == 3 and #e.include == 2);
for _, key in ipairs({ 'exclude', 'pinned' }) do assert(equal(e[key], before[key]), 'Other saved lists remain unchanged.'); end;
-- The tab lists what its filters hold, each with a way to take it off.
h.draw();
assert(#h.calls('Button', 'Remove##effect') == 4, 'Two on Show only, and one each on Hidden and Pinned first.');
assert(#h.calls('Button', 'Move effect to front##frame') == 0, 'Pin first does that job.');
-- The reset does what its button says: it takes the effect off every list.
h.choose('Haste', 33);
h.draw('Reset selected effect##frame');
assert(#e.include == 1 and e.include[1] == 3, 'Party reset takes the effect off its lists.');
for _, key in ipairs({ 'exclude', 'pinned' }) do assert(equal(e[key], before[key])); end;

entries[#entries + 1] = { id = 17, name = 'Poison spikes' };
h.draw();
assert(#choices() == 4, 'An effect new to the list shows in it, though the list is the same table.');
entries = { { id = 4, name = 'Paralysis' } };
h.draw(); h.draw();
assert(h.previews[PICK] == 'Choose an effect' and not h.called('Checkbox', 'Show only##frame'),
    'A pick the new list doesn\'t have is let go.');
h.draw('Reset this tab##frame');
assert(#e.include == 0 and #e.exclude == 0 and #e.pinned == 0, 'Reset this tab is there with nothing picked.');
status.named = named;
return 'The party effect list picks nothing until asked and changes nothing until a tick is used';
