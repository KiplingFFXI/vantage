-- One finder on Filters serves every per-effect setting of a panel: Show only, Hide here, Pin first, My order, Rename it and
-- its color. Each list line shows while it has entries, says the effect's name, and takes it off again. What they write is
-- what the panel draws by.
local h = require('panel_fixture')();
local hud = require('ui.hud');
local FIND, EFFECT, RENAME = '##frame_Find an effect', '##frame_Effect', '##frame_Rename it';
local function find(name, id)
    h.type(FIND, name);
    h.pick(EFFECT, name .. '##' .. id);
end;

h.fresh(function(s) s.panels.self_buffs.mode = 'bars'; end);
h.on('self_buffs', 'filters');
local p = h.s.panels.self_buffs;
h.type(FIND, 'no such effect');
assert(not h.called('Button', 'Add to My order##frame') and not h.called('Checkbox', 'Pin first##frame') and not h.called('InputText', RENAME),
    'With nothing found there is nothing to tick.');
assert(h.says('No matching effects. Try a different name.'), 'It says so.');
for _, line in ipairs({ 'Hidden here', 'Pinned first', 'My order', 'Renamed', 'Colored' }) do
    assert(not h.says(line), 'A list line shows only while it has entries: ' .. line);
end;

-- My order: Add puts it on the end and turns the sort on, once. Up, Down and Remove go by the line they are on.
find('Haste', 33);
h.draw('Add to My order##frame');
h.draw();
p = h.s.panels.self_buffs;
assert(#p.order == 1 and p.order[1] == 33 and p.sort == 'fixed', 'Add to My order lists it and sorts by it.');
assert(h.says('My order') and h.says('Haste'), 'The line lists it by name.');
h.draw('Add to My order##frame');
h.draw();
assert(#h.s.panels.self_buffs.order == 1, 'An effect is on the list once.');
find('Protect', 40);
h.draw('Add to My order##frame');
h.draw();
find('Regen', 42);
h.draw('Add to My order##frame');
h.draw();
p = h.s.panels.self_buffs;
assert(table.concat(p.order, ',') == '33,40,42', 'Each goes on the end.');
assert(#h.calls('Button', 'Up##order') == 3 and #h.calls('Button', 'Down##order') == 3, 'Each line has its Up and Down.');
-- The mock clicks the first Up it meets, which has no way up, and the first Down, which moves that line down.
h.draw('Down##order');
h.draw();
assert(table.concat(h.s.panels.self_buffs.order, ',') == '40,33,42', 'Down moves its line down.');
h.draw('Undo');
h.draw();
assert(table.concat(h.s.panels.self_buffs.order, ',') == '33,40,42', 'A move is one Undo step.');

-- What the panel draws goes by that order, past the names.
local panel = h.s.panels.self_buffs;
local view = { context = {}, rows = {} };
for _, row in ipairs({ { 33, 'Haste' }, { 40, 'Protect' }, { 42, 'Regen' }, { 41, 'Shell' } }) do
    view.rows[#view.rows + 1] = { effect = row[1], name = row[2], scope = 'self', kind = 'buff', domain = 'status', key = row[2] };
end;
local function order()
    local names = {};
    for _, row in ipairs(hud.filter_rows(view, panel, 'self_buffs', h.s)) do names[#names + 1] = row.name; end;
    return table.concat(names, ',');
end;
panel.order = { 42, 33 };
assert(order() == 'Regen,Haste,Protect,Shell', 'My order comes first, and what it leaves out follows by name: ' .. order());
panel.order = { 33, 40, 42 };

-- Remove takes the line's own entry off.
local removed = false;
local real_button = h.imgui.Button;
local count = 0;
h.imgui.Button = function(label, ...)
    if label == 'Remove##effect' then
        count = count + 1;
        if count == 2 then MOCK.clicks[label] = true; removed = true; end;
    end;
    return real_button(label, ...);
end;
h.draw();
h.imgui.Button = real_button;
h.draw();
assert(removed and table.concat(h.s.panels.self_buffs.order, ',') == '33,42', 'Remove goes by its line.');

-- Rename: the panel calls it that, the line says both names, and blank goes back to the game's name.
find('Haste', 33);
h.type(RENAME, 'Speed');
p = h.s.panels.self_buffs;
assert(p.labels[33] == 'Speed' and h.says('Haste as Speed'), 'Renamed lists it with both names.');
local row = { effect = 33, name = 'Haste', domain = 'status', status = 'known' };
local shown = {};
for _, entry in ipairs(hud.entries(row, p, h.s.style, 0)) do shown[#shown + 1] = tostring(entry.text); end;
assert(table.concat(shown, ' '):find('Speed', 1, true), 'The panel draws the new name: ' .. table.concat(shown, ' '));
assert(row.name == 'Haste', 'The effect itself does not change.');
h.type(RENAME, '');
assert(h.s.panels.self_buffs.labels[33] == nil and not h.says('Haste as Speed'), 'Blank uses the game name.');
h.type(RENAME, 'Speed');
h.type(RENAME, 'Speed##x');
assert(h.s.panels.self_buffs.labels[33] == 'Speedx', 'A name holds no id marks.');
h.type(RENAME, '');

-- The ticks and their lines.
find('Haste', 33);
h.draw('Show only##frame_effect');
h.draw();
assert(h.s.panels.self_buffs.include[33] == true or h.s.panels.self_buffs.include['33'] == true, 'Show only lists it.');
assert(h.says('While this list has effects, only those show.') or h.says('Show only'), 'The line is there.');
h.draw('Hide here##frame');
h.draw('Pin first##frame');
h.draw();
assert(h.says('Hidden here') and h.says('Pinned first'), 'Each has its line.');
h.draw("Clear this display's filters##frame");
h.draw();
p = h.s.panels.self_buffs;
assert(next(p.include) == nil and next(p.exclude) == nil and p.filter == '', 'Clear takes off what filters the panel.');

-- A recast panel's list is of recasts, and a kept id the game has no name for says so in words.
h.fresh(function(s)
    local panel_kept = s.panels.self_buffs;
    panel_kept.order = { 60000 };
    panel_kept.labels[60000] = 'Mine';
end);
h.on('self_buffs', 'filters');
assert(h.says('An effect with no name') and h.says('An effect with no name as Mine'), 'An effect with no name goes by those words.');
for _, call in ipairs(MOCK.imgui_calls) do
    assert(not tostring(call[2]):find('Status 60000', 1, true) and not tostring(call[2]):find('Effect 60000', 1, true), 'No id is on show.');
end;
h.on('spell_recasts', 'filters');
h.type(FIND, 'Cure');
assert(h.says('No recasts are known yet.'), 'The finder of a recast panel goes by the recasts known.');
MOCK.fire('unload');
return 'My order, Rename and the effect lists write what the panel draws by, by name';
