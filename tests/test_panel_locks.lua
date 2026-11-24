-- A lock only stops a Shift drag: while a display is locked, every row on its tabs stays live, the numbers on Size and
-- place move it all the same, and no line asks to unlock it. Locked is the same saved lock the edit bar has, and nothing on
-- a panel writes it but its own tick.
local h = require('panel_fixture')();
local defaults, elements = require('ui.defaults'), require('ui.elements');
local place = { '##frame_Across', '##frame_Down', '##frame_Moves with', 'Put it back where it started##frame' };
local outer = { '##frame_Width', '##frame_Tallest' };
local fit = { '##frame_Narrowest', '##frame_Widest' };

local function lock_ticked()
    return h.calls('Checkbox', 'Locked##frame')[1][3][1];
end;
local function all_live(list, when)
    local grey = h.greyed();
    for _, label in ipairs(list) do assert(grey[label] ~= true, when .. ': ' .. label .. ' is live.'); end;
end;

-- Fresh, a panel is locked, and Place and the outer size are live, with no line about the lock.
h.fresh();
assert(h.s.panels.self_buffs.locked == true, 'Fixture: fresh displays are locked.');
h.on('self_buffs', 'place');
assert(lock_ticked() == true, 'Locked shows the saved lock.');
assert(not h.says('Unlock it') and not h.says('Unlocked:'), 'No line asks to unlock it.');
all_live(place, 'Locked Place');
all_live(outer, 'Locked Size');
h.s.panels.self_buffs.auto_width = true;
h.bump();
h.on('self_buffs', 'place');
all_live(fit, 'Locked Size, fitted');
h.s.panels.self_buffs.auto_width = false;
h.bump();

-- Nothing on any tab of a locked panel is greyed by its lock.
for _, tab in ipairs({ 'show', 'look', 'filters', 'when', 'place' }) do
    h.on('self_buffs', tab);
    local grey = h.greyed();
    grey.Undo, grey.Redo = nil, nil;
    assert(next(grey) == nil, 'Nothing on ' .. tab .. ' is greyed by a lock: ' .. tostring(next(grey)));
end;

-- Locked, Across still moves it, as one Undo step that leaves the lock.
h.on('self_buffs', 'place');
h.slide('##frame_Across', 321);
assert(h.s.panels.self_buffs.x == 321 and h.s.panels.self_buffs.locked == true, 'Locked, Across moves it.');
h.draw('Undo');
h.draw();
assert(h.s.panels.self_buffs.x ~= 321 and h.s.panels.self_buffs.locked == true, 'A move is one Undo step.');

-- Unticking writes the saved lock, and the header says how to drag it.
h.draw('Locked##frame');
h.draw();
assert(h.s.panels.self_buffs.locked == false and elements.locked(h.s, 'self_buffs') == false, 'Locked writes the saved lock.');
assert(lock_ticked() == false and h.says('Unlocked: hold Shift and drag it to move it, or drag an edge to resize it.'), 'The header says how to move it.');
h.draw('Undo');
h.draw();
assert(h.s.panels.self_buffs.locked == true, 'The lock is one Undo step too.');

-- Each panel has its own lock, and the recast panel's is the one being edited.
h.fresh(function(s) s.panels.target.locked = false; end);
h.on('spell_recasts', 'place');
all_live(place, 'A recast panel');
h.draw('Locked##frame');
assert(h.s.panels.spell_recasts.locked == false and h.s.panels.ability_recasts.locked == true, 'Locked writes the recast panel being edited.');

-- The pulse has a lock of its own, and a recast panel's lock doesn't reach it.
h.fresh(function(s) s.ready_pulse.enabled, s.ready_pulse.spot = true, 'screen'; s.panels.spell_recasts.locked = false; end);
h.on('pulse', 'place');
local pulse = { '##frame_Across_pulse', '##frame_Down_pulse' };
assert(h.s.ready_pulse.locked == true and h.called('Checkbox', 'Locked##frame'), 'Fixture: the pulse is locked and has its tick.');
all_live(pulse, 'A locked pulse');
h.draw('Locked##frame');
h.draw();
assert(h.s.ready_pulse.locked == false and h.s.panels.spell_recasts.locked == false, 'The pulse tick writes the pulse lock only.');

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
for _, id in ipairs({ 'self_buffs', 'self_debuffs', 'target', 'party', 'watch', 'spell_recasts', 'ability_recasts', 'item_recasts', 'pulse' }) do
    for _, tab in ipairs({ 'show', 'place', 'look', 'filters', 'when' }) do h.on(id, tab); end;
end;
for id, locked in pairs(locks(h.s)) do assert(locked == before[id], 'Looking around leaves the lock of ' .. id); end;
assert(defaults.make().panels.self_buffs.locked == true, 'Fresh stays locked.');
MOCK.fire('unload');
return 'A lock stops only a drag: every row stays live, and only its own tick writes it';
