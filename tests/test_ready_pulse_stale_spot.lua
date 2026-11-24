-- A ready pulse On its row plays where a panel drew the row as the recast became ready. A row the panel stopped drawing
-- long before, because its When to show hid it, Most shown cut it or the panel was turned off, isn't on screen, so its
-- pulse plays nowhere, as while the panels are hidden for typing. A row on screen when you started typing, or when the
-- map hid every display, was where the panel left it, so the rest of a pulse that began meanwhile still plays there.
-- With Only recasts with a known time ticked, the row hides a few frames before the ready (its deadline passes before
-- the sample that reads 0), and its pulse still plays there for its whole length.
local pulse, defaults, hud = require('core.ready_pulse'), require('ui.defaults'), require('ui.hud');
local conditions = require('core.conditions');
local recasts = require('core.recasts').new();
local function fresh() return defaults.tidy(defaults.make()); end
local function recast(id, remaining, total)
    return { key = 'recast:1001:spell:' .. id, instance = 1, domain = 'recast', kind = 'spell', group = 'spell_recasts',
        effect = 10000 + id, recast_id = id, spell_id = id, name = 'Spell ' .. id, remaining = remaining, total = total };
end
local function ready(row, now)
    local event = {};
    for key, value in pairs(row) do event[key] = value; end
    event.category, event.kind, event.time, event.remaining = row.kind, 'ready', now, 0;
    return event;
end
local function frame(view, settings, now)
    MOCK.imgui_calls = {};
    hud.draw(view, settings, now, {});
end
-- The pulse rings drawn this frame, and whether the recast panel's window opened.
local function look()
    local inside, rings, panel = false, {}, false;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Begin' then
            inside = call[2] == '##vantage_pulse';
            if call[2] == '##vantage_recasts' then panel = true; end
        elseif call[1] == 'End' then inside = false;
        elseif inside and call[1] == 'draw:AddRect' then rings[#rings + 1] = MOCK.drawn[call]; end
    end
    return rings, panel;
end
local function view_of(rows, pulses) return { valid = true, rows = rows, context = { valid = true, id = 1001 }, pulses = pulses }; end
local snapshot = { valid = true, id = 1001, zone = 230, job = 1, level = 75, party = {}, self_effects = {}, combat = true };
local function setup()
    local s = fresh();
    s.ready_pulse.enabled = true;
    for _, panel in pairs(s.panels) do panel.enabled = false; end
    s.recast_display, s.panels.recasts.enabled, s.panels.recasts.mode = 'combined', true, 'icons';
    conditions.update(s, snapshot);
    return s;
end
require('ui.icons').status = function() return 'status'; end;

-- Control: the panel draws the row until the recast is ready, and the pulse plays there.
local s = setup();
local a = recast(57, 10, 180);
local watch = pulse.new();
watch:update({ a }, {}, s, 10);
frame(view_of({ a }), s, 10);
frame(view_of({}, watch:update({}, { ready(a, 11) }, s, 11)), s, 11.2);
local rings = look();
assert(#rings == 1, 'Fixture: the pulse plays on the row the panel drew.');

-- When to show: the panel shows only while engaged. It draws the row, the fight ends and the panel is hidden while the
-- recast counts down, and it ends while the panel is still hidden.
s.panels.recasts.conditions.engaged = 'yes';
conditions.update(s, snapshot);
local b = recast(58, 180, 180);
watch = pulse.new();
watch:update({ b }, {}, s, 20);
frame(view_of({ b }), s, 20);
local _, shown = look();
assert(shown, 'Fixture: engaged, the panel draws the row.');
snapshot.combat = false;
conditions.update(s, snapshot);
for t = 30, 190, 10 do
    b.remaining = 200 - t;
    watch:update({ b }, {}, s, t);
    frame(view_of({ b }), s, t);
    _, shown = look();
    assert(not shown, 'Fixture: not engaged, When to show hides the panel.');
end
local live = watch:update({}, { ready(b, 200) }, s, 200);
assert(#live == 1, 'Fixture: the recast ends and starts a pulse.');
frame(view_of({}, live), s, 200.2);
rings = look();
assert(#rings == 0, 'A pulse On its row doesn\'t play where a panel When to show hides drew the row 180 s before.');

-- The recast panel turned off, while recasts are still read for something else.
s = setup();
local c = recast(59, 170, 180);
watch = pulse.new();
watch:update({ c }, {}, s, 10);
frame(view_of({ c }), s, 10);
s.panels.recasts.enabled = false;
for t = 20, 170, 10 do
    c.remaining = 180 - t;
    watch:update({ c }, {}, s, t);
    frame(view_of({ c }), s, t);
end
frame(view_of({}, watch:update({}, { ready(c, 180) }, s, 180)), s, 180.2);
rings = look();
assert(#rings == 0, 'A pulse On its row doesn\'t play where a panel since turned off drew the row.');

-- Most shown 1, sorted by name: a recast that sorts first takes the one row, and the cut one's pulse doesn't play on it.
s = setup();
s.panels.recasts.sort, s.panels.recasts.max_rows = 'name', 1;
local late, first = recast(60, 170, 180), recast(10, 300, 300);
watch = pulse.new();
watch:update({ late }, {}, s, 10);
frame(view_of({ late }), s, 10);
for t = 20, 170, 10 do
    late.remaining, first.remaining = 180 - t, 310 - t;
    watch:update({ late, first }, {}, s, t);
    frame(view_of({ late, first }), s, t);
end
frame(view_of({ first }, watch:update({ first }, { ready(late, 180) }, s, 180)), s, 180.2);
rings, shown = look();
assert(shown and #rings == 0, 'A pulse On its row doesn\'t play for a row Most shown cut long before.');

-- Hide while typing: the panel draws the row, you type for 15 s, and the recast ends 0.5 s before you stop. The panels
-- come back with the pulse still going, and the rest of it plays on the row, as the row was on screen when they went.
s = setup();
s.visibility.hide_typing = true;
local typed = recast(61, 15, 180);
watch = pulse.new();
watch:update({ typed }, {}, s, 10);
frame(view_of({ typed }), s, 10);
local typing = view_of({ typed });
typing.context.chat_open = true;
for t = 10.5, 24.5, 0.5 do
    typed.remaining = 25 - t;
    watch:update({ typed }, {}, s, t);
    frame(typing, s, t);
    _, shown = look();
    assert(not shown, 'Fixture: typing hides the panel.');
end
live = watch:update({}, { ready(typed, 25) }, s, 25);
typing = view_of({}, live);
typing.context.chat_open = true;
frame(typing, s, 25);
rings = look();
assert(#rings == 0, 'Fixture: no pulse plays while typing hides the panels.');
frame(view_of({}, live), s, 25.5);
rings = look();
assert(#rings == 1, 'The rest of a pulse that began while you typed plays on its row once the panels are back.');

-- The map, an event or the hidden interface: the app doesn't draw at all then (vantage.lua). The panel draws the row,
-- the map is up for 15 s, and the recast ends 0.5 s before it closes. The rest of the pulse plays on the row.
s = setup();
local mapped = recast(62, 15, 180);
watch = pulse.new();
watch:update({ mapped }, {}, s, 10);
frame(view_of({ mapped }), s, 10);
for t = 10.5, 24.5, 0.5 do
    mapped.remaining = 25 - t;
    watch:update({ mapped }, {}, s, t);
end
frame(view_of({}, watch:update({}, { ready(mapped, 25) }, s, 25)), s, 25.5);
rings = look();
assert(#rings == 1, 'The rest of a pulse that began while the map hid every display plays on its row once they are back: '
    .. #rings .. ' rings.');

-- Only recasts with a known time: read at 11.0 with 0.05 s left, the row waits hidden as unknown once its deadline
-- passes, and the refresh at 11.1 reads 0 and sends the ready.
s = setup();
s.panels.recasts.known_only = true;
local row = { key = 'r57', instance = 1, domain = 'recast', kind = 'spell', group = 'spell_recasts', effect = 10057, recast_id = 57,
    spell_id = 57, name = 'Spell 57', remaining = 0.05, total = 180, deadline = 11.05, status = 'server', present = true };
local view = view_of({ row });
watch = pulse.new();
watch:update({ row }, {}, s, 11.0);
local hidden = 0;
for index = 0, 5 do
    recasts:project(view, 11.0 + index / 60);
    frame(view, s, 11.0 + index / 60);
    _, shown = look();
    if not shown then hidden = hidden + 1; end
end
assert(hidden > 0 and hidden < 6, 'Fixture: the row draws until its deadline, then waits hidden.');
view = view_of({}, watch:update({}, { ready(row, 11.1) }, s, 11.1));
frame(view, s, 11.1);
local at_first = #look();
for t = 11.2, 11.95, 0.1 do frame(view, s, t); end
assert(at_first == 1 and #look() == 1, 'With known times only, the pulse still plays on the row hidden a few frames before the ready, for its whole length.');
return 'A pulse On its row plays only where a panel drew the row as it became ready';
