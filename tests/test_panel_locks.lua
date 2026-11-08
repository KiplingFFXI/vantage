-- While a display is locked, what moves it or changes its outer size is greyed, with one line that says how to get it
-- back. How rows fill inside it stays live, as that moves nothing. Locked is the same saved lock the edit bar has, and
-- nothing on a panel writes it but its own tick.
local h = require('panel_fixture')();
local defaults, elements = require('ui.defaults'), require('ui.elements');
local place = { '##frame_Across', '##frame_Down', '##frame_Moves with', 'Put it back where it started##frame' };
local outer = { '##frame_Width', '##frame_Tallest' };
local fit = { '##frame_Narrowest', '##frame_Widest' };

local function lock_ticked()
    return h.calls('Checkbox', 'Locked##frame')[1][3][1];
end;
local function all_greyed(list, greyed, when)
    local grey = h.greyed();
    for _, label in ipairs(list) do
        assert((grey[label] == true) == greyed, when .. ': ' .. label .. (greyed and ' is greyed.' or ' is live.'));
    end;
end;

-- Fresh, a panel is locked: Place and the outer size are greyed, with the line, and the rest is live.
h.fresh();
assert(h.s.panels.self_buffs.locked == true, 'Fixture: fresh displays are locked.');
h.on('self_buffs', 'place');
assert(lock_ticked() == true, 'Locked shows the saved lock.');
assert(h.says('Unlock it to move or resize it.') and not h.says('Unlocked:'), 'One line says how to get it back.');
all_greyed(place, true, 'Locked Place');
all_greyed({ '##frame_Fills', 'Locked##frame', 'On##frame_display', 'Reset this display##frame' }, false, 'Locked Place');
h.on('self_buffs', 'place');
all_greyed(outer, true, 'Locked Size');
all_greyed({ '##frame_Row height' }, false, 'Locked Size');
h.s.panels.self_buffs.auto_width = true;
h.bump();
h.on('self_buffs', 'place');
all_greyed(fit, true, 'Locked Size, fitted');

-- What every tab of a locked panel has that isn't the panel's spot or outer size stays live.
for _, tab in ipairs({ 'show', 'look', 'filters', 'when' }) do
    h.on('self_buffs', tab);
    local grey = h.greyed();
    grey.Undo, grey.Redo = nil, nil;
    assert(next(grey) == nil, 'Nothing on ' .. tab .. ' is greyed by a lock: ' .. tostring(next(grey)));
end;

-- Unticking is the way in: nothing is greyed, the header says how to move it, and that is the saved lock.
h.on('self_buffs', 'place');
h.draw('Locked##frame');
h.draw();
assert(h.s.panels.self_buffs.locked == false and elements.locked(h.s, 'self_buffs') == false, 'Locked writes the saved lock.');
assert(lock_ticked() == false and h.says('Unlocked: hold Shift and drag it to move it, or drag an edge to resize it.'), 'The header says how to move it.');
assert(not h.says('Unlock it to move or resize it.'), 'The line goes with the lock.');
all_greyed(place, false, 'Unlocked Place');
h.slide('##frame_Across', 321);
assert(h.s.panels.self_buffs.x == 321, 'Unlocked, Across moves it.');
h.draw('Undo');
h.draw();
assert(h.s.panels.self_buffs.x ~= 321, 'A move is one Undo step.');
h.draw('Undo');
h.draw();
assert(h.s.panels.self_buffs.locked == true, 'So is the lock.');

-- Each panel has its own lock: another display's stays as saved, and the recast panel's is the one being edited.
h.fresh(function(s) s.panels.target.locked = false; end);
h.on('self_buffs', 'place');
all_greyed(place, true, 'A display locked beside an unlocked one');
h.on('target', 'place');
all_greyed(place, false, 'The unlocked one');
h.on('spell_recasts', 'place');
all_greyed(place, true, 'A recast panel');
h.draw('Locked##frame');
assert(h.s.panels.spell_recasts.locked == false and h.s.panels.ability_recasts.locked == true, 'Locked writes the recast panel being edited.');

-- The pulse has a lock of its own: its rows grey by that, and the panel's lock doesn't reach them.
h.fresh(function(s) s.ready_pulse.enabled, s.ready_pulse.spot = true, 'screen'; s.panels.spell_recasts.locked = false; end);
h.on('spell_recasts', 'place');
local pulse = { '##frame_Across_pulse', '##frame_Down_pulse' };
assert(h.s.ready_pulse.locked == true and h.called('Checkbox', 'Locked##frame_pulse'), 'Fixture: the pulse is locked and has its tick.');
all_greyed(pulse, true, 'A locked pulse on an unlocked panel');
all_greyed(place, false, 'The unlocked panel over a locked pulse');
h.draw('Locked##frame_pulse');
h.draw();
assert(h.s.ready_pulse.locked == false and h.s.panels.spell_recasts.locked == false, 'The pulse tick writes the pulse lock only.');
all_greyed(pulse, false, 'An unlocked pulse');

-- Looking around writes no lock, on any display, on a save with its own locks.
local function locks(s)
    local kept = {};
    for _, element in ipairs(elements.list) do kept[element.id] = elements.locked(s, element.id); end;
    return kept;
end;
h.fresh(function(s)
    s.panels.self_buffs.locked, s.panels.watch.locked, s.ready_pulse.locked, s.rolls.locked = false, false, false, false;
end);
local before = locks(h.s);
for _, id in ipairs({ 'self_buffs', 'self_debuffs', 'target', 'party', 'watch', 'spell_recasts', 'ability_recasts', 'item_recasts' }) do
    for _, tab in ipairs({ 'show', 'place', 'look', 'filters', 'when' }) do h.on(id, tab); end;
end;
for id, locked in pairs(locks(h.s)) do assert(locked == before[id], 'Looking around leaves the lock of ' .. id); end;
assert(defaults.make().panels.self_buffs.locked == true, 'Fresh stays locked.');
MOCK.fire('unload');
return 'A lock greys Place and the outer size only, and only its own tick writes it';
