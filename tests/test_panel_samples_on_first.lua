-- Show samples turns samples on only for a display that is on. On Party list buffs, Overhead icons, Party cooldowns and
-- Phantom Roll, a tick while it is off leaves everything as it is and says why, with no Undo step. Show off ends them.
-- Party cooldowns' samples show in its list, so the list has to be on as well.
local h = require('panel_fixture')();
local defaults = require('ui.defaults');

local function config(s, id)
    if id == 'party_ui' then return s.party_ui; end;
    if id == 'overhead' then return s.overhead; end;
    if id == 'cooldown_list' then return s.party_cooldowns; end;
    return s.rolls;
end;
local ROWS = {
    { 'party_ui', 'Turn a display on first. Samples show only on displays that are on.' },
    { 'overhead', 'Turn a display on first. Samples show only on displays that are on.' },
    { 'cooldown_list', 'Samples show in the list. Turn the display on and tick In a list first.' },
    { 'rolls', 'Turn a display on first. Samples show only on displays that are on.' },
};
for _, row in ipairs(ROWS) do
    local id, note = row[1], row[2];
    local s = h.fresh();
    local p = config(s, id);
    h.on(id, 'show');
    local before = defaults.copy(s);
    h.draw('Show samples##frame');
    h.draw();
    assert(p.preview == false and p.enabled == false, id .. ': samples turn nothing on.');
    assert(#h.app.state.history == 0, id .. ': a refused tick is no Undo step.');
    assert(h.says(note), id .. ': the tick says why.');
    before.window, s.window = nil, nil;
    assert(require('core.customization').equal(s, before), id .. ': and nothing else changes.');
end;

-- On, the tick works, and Show off ends the samples. The main page's End samples still reaches them.
for _, row in ipairs(ROWS) do
    local id = row[1];
    local s = h.fresh();
    local p = config(s, id);
    p.enabled = true;
    if id == 'cooldown_list' then s.party_cooldowns.list.enabled = true; end;
    h.bump();
    h.on(id, 'show');
    h.draw('Show samples##frame');
    assert(p.preview == true and #h.app.state.history == 1, id .. ': on, samples show, as one Undo step.');
    h.draw('On##frame_display');
    assert(p.enabled == false and p.preview == false and #h.app.state.history == 2, id .. ': Show off ends them, as one step.');
end;

-- The watch on with the list off has nowhere for samples to show.
local s = h.fresh(function(saved) saved.party_cooldowns.enabled, saved.party_cooldowns.list.enabled = true, false; end);
h.on('cooldown_list', 'show');
h.draw('Show samples##frame');
assert(s.party_cooldowns.preview == false and #h.app.state.history == 0, 'With the list off, samples stay off.');
MOCK.fire('unload');
return 'Show samples on the four turns on only what is on, and says so when it can\'t';
