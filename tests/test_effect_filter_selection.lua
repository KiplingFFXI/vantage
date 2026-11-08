-- Finding a party effect on Party list buffs, Filters: the picker goes by what is typed, with an exact name first, and
-- nothing changes until a tick or button under it is used. The filtered list is kept while nothing it goes by changes.
local h = require('panel_fixture')();
local copy, equal = require('core.store').copy, require('core.customization').equal;
local status, editor = require('ui.status_panel'), require('ui.effect_settings');
local entries = { { id = 107, name = 'Barpoison' }, { id = 3, name = 'Poison' }, { id = 33, name = 'Haste' } };
local named = status.named;
status.named = function() return entries; end;
local FIND, PICK = '##frame_Find an effect', '##frame_Effect';
local s = h.fresh(function(saved)
    local e = saved.party_ui.effects;
    e.include, e.exclude, e.pinned = { 33 }, { 4 }, { 8 };
end);
local e = s.party_ui.effects;
local before = copy(e);
h.on('party_ui', 'filters');
-- What the picker offers, by id.
local function choices()
    h.combo = PICK;
    h.draw();
    h.combo = nil;
    local offered = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        local id = call[1] == 'Selectable' and tostring(call[2]):match('##(%d+)$');
        if id then offered[#offered + 1] = tonumber(id); end;
    end;
    h.draw();
    return offered;
end;

-- The pick stays while it is still listed, so it leaves Barpoison for Haste first.
h.type(FIND, 'Haste');
h.type(FIND, 'Poison');
assert(h.previews[PICK] == 'Poison' and #choices() == 2,
    'Filtering prefers the exact visible match instead of hidden Haste or an earlier Barpoison substring.');
assert(equal(e, before) and #h.app.state.history == 0, 'Searching changes only what the finder holds.');
-- The party list draws icons only, so a picked effect has no label or color to set.
local names = h.drawn();
assert(not names['Party effect label'] and not names['Party effect color'], 'The picked effect offers no label or color.');

local selection = { query = 'Poison' };
editor.selection(entries, selection);
local ids, labels = selection.ids, selection.labels;
editor.selection(entries, selection);
assert(selection.ids == ids and selection.labels == labels, 'An unchanged visible catalog reuses the filtered choices.');
selection.query = 'POISON';
editor.selection(entries, selection);
assert(selection.ids == ids, 'Case-only search changes reuse matching results.');

h.draw('Show only##frame');
assert(e.include[1] == 33 and e.include[2] == 3 and #e.include == 2);
for _, key in ipairs({ 'exclude', 'pinned' }) do assert(equal(e[key], before[key]), 'Other saved lists remain unchanged.'); end;
-- The tab lists what its filters hold, each with a way to take it off.
h.draw();
assert(#h.calls('Button', 'Remove##effect') == 4, 'Two on Show only, and one each on Hidden and Pinned first.');
assert(#h.calls('Button', 'Move effect to front##frame') == 0, 'Pin first does that job.');
-- The reset does what its button says: it takes the effect off every list.
h.type(FIND, 'Haste');
h.draw('Reset selected effect##frame');
assert(#e.include == 1 and e.include[1] == 3, 'Party reset takes the effect off its lists.');
for _, key in ipairs({ 'exclude', 'pinned' }) do assert(equal(e[key], before[key])); end;
before = copy(e);

h.type(FIND, 'not a client effect');
assert(not h.called('BeginCombo', PICK) and not h.called('Checkbox', 'Show only##frame') and equal(e, before),
    'No-match results expose no controls that could edit a hidden effect.');
assert(h.says('No matching effects. Try a different name.'), 'Empty searches explain why effect controls are unavailable.');
h.type(FIND, '33');
assert(h.previews[PICK] == 'Haste', 'Typing a number selects the effect, which shows by name.');

h.type(FIND, 'Poison');
entries[#entries + 1] = { id = 17, name = 'Poison spikes' };
h.draw();
assert(#choices() == 3, 'Newly observed catalog entries invalidate a cached query without replacing its catalog table.');
entries = { { id = 4, name = 'Paralysis' } };
h.draw();
assert(not h.called('BeginCombo', PICK), 'Replacing the catalog invalidates earlier results.');
h.type(FIND, '');
assert(h.previews[PICK] == 'Paralysis');
h.type(FIND, 'no match');
h.draw('Clear this display\'s filters##frame');
assert(#e.include == 0 and #e.exclude == 0 and #e.pinned == 0,
    'Clearing all filters remains available even when the search has no results.');
status.named = named;
return 'The party effect finder filters by name and changes nothing until asked';
