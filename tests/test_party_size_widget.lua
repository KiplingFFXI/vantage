-- The size control for the party list buffs (ui/party_size_widget.lua), drawn first in Party & alliance's member
-- effects and, while it has a control to show, in Home's Look and size on the same keys. The icons beside the rows fill
-- the step from one row to the next with no space between them, whatever icon size a save holds, so there is no room
-- to pick and no button for more room: Party & alliance says so with the size they draw at once the step is measured,
-- and the icon size is for a panel of its own, shown only while a shown group is in one. The strips draw icons only, so
-- there is no Bar height, Bar width or width of each icon and name. There is no line about the game's rows, no picture
-- and no line about the size the icons draw at. Nothing happens by itself, each change is one Undo step, and the lock
-- stays as it is. A strip moves by Shift + left-drag only.
local defaults, store, party_defaults = require('ui.defaults'), require('core.store'), require('ui.party_defaults');
local imgui, elements, overlay = require('imgui'), require('ui.elements'), require('ui.native_party_hud');
local widget = require('ui.party_size_widget');
-- A 1920x1080 screen, where the game's rows are 14 px tall and 20 px apart.
MOCK.screen = { 1920, 1080 };

-- The game's party list: for each group { row height, step between rows or nil, members }.
local function geometry(groups)
    local out = { available = true, groups = {} };
    for group, spec in pairs(groups) do
        local rows = {};
        for slot = 1, spec[3] or 3 do rows[slot] = { height = spec[1] }; end;
        out.groups[group] = { rows = rows, row_height = spec[1], pitch = spec[2], measured_by = spec[2] and 'rows' or 'none' };
    end;
    return out;
end;
local function rooms(p, groups) return overlay.rooms(p, geometry(groups)); end;
local function plain(text)
    for _, word in ipairs({ '?', 'unknown', '+' }) do
        assert(not text:lower():find(word, 1, true), 'The player never reads ' .. word .. ': ' .. text);
    end;
    return text;
end;

-- No line about the game's rows: the line about the step and the sliders say what the player sets.
local p = party_defaults.make();
p.enabled, p.effects.icon_size = true, 37;
assert(widget.readout == nil, 'No line about the game\'s rows.');

-- The line about the icons beside the rows: they fill the step, with the size they draw at once the step is measured,
-- whatever icon size a save holds, and touch.
local STEP = "Beside the game's party list the icons fill the step from one row to the next (20 px here), with no space between them.";
local here = rooms(p, { { 14, 20 } });
for _, size in ipairs({ 12, 14, 20, 37, 128 }) do
    p.effects.icon_size = size;
    assert(plain(widget.step(p, rooms(p, { { 14, 20 } }))) == STEP, 'The same step for every save at ' .. size);
end;
p.effects.icon_size = 37;
assert(widget.step(p, {}) == "Beside the game's party list the icons fill the step from one row to the next, with no space between them.",
    'No number before the game\'s rows are read.');
assert(widget.step(p, rooms(p, { { 14, nil, 1 } }))
    == "Beside the game's party list the icons fill the step from one row to the next, with no space between them.",
    'Alone with nothing measured, no number.');
assert(widget.step(p, rooms(p, { { 14, 20 }, { 14, nil, 1 } }))
    == "Beside the game's party list the icons fill the step from one row to the next (20 px here), with no space between them.",
    'A group with no step measured adds no number.');
assert(widget.step(p, rooms(p, { { 18.666666666666668, 26.666666666666668 } }))
    == "Beside the game's party list the icons fill the step from one row to the next (27 px here), with no space between them.",
    'A step between whole pixels gives the size that draws, rounded up.');
assert(widget.step(p, rooms(p, { { 14, 20 }, { 16, 22 } }))
    == "Beside the game's party list the icons fill the step from one row to the next (20 to 22 px here), with no space between them.",
    'Groups that differ give both.');
assert(widget.step(p, rooms(p, { { 22, 22 } }))
    == "Beside the game's party list the icons fill the step from one row to the next (22 px here), with no space between them.",
    'Rows that touch, the row.');

-- What the chosen size draws at: the slider shows the size in a panel of its own, so there is no line for it.
assert(widget.result == nil, 'No result line.');

-- Only a shown group in a panel of its own counts as one, for the icon size, the way back and Home alike.
p.groups[2].native_detached, p.strips.alliance1 = true, false;
assert(not widget.in_panels(p), 'A hidden strip\'s panel doesn\'t count.');
p.strips.alliance1 = true;
assert(widget.in_panels(p), 'A shown one does.');
p.groups[2].native_detached = false;
assert(widget.more_room == nil and widget.labels.room == nil and widget.labels.use_touch == nil, 'No room to pick and no button for more.');
assert(widget.labels.bar_height == nil and widget.labels.bar_width == nil and widget.labels.name_width == nil,
    'No Bar height, Bar width or width of each icon and name.');
-- The control has something to set only while a shown group is in a panel of its own.
assert(not widget.in_panels(p), 'Every shown group beside the rows: nothing to set.');
p.groups[1].native_detached = true; assert(widget.in_panels(p), 'A panel gives its icon size and the way back.');
p.strips.party = false; assert(not widget.in_panels(p), 'Not for a hidden strip\'s panel.');
p.strips.party, p.groups[1].native_detached = true, false;

-- A panel of its own where the strip is drawn now. Before the strips were ever planned it is tall enough for one line
-- of effects per member: 6 px at the top, then per member a name in the timer panels' font, which the party list buffs
-- wear, 2 + 3 px, the icon with its countdown under it, and 8 px. Countdowns start off; a player can turn them on, as
-- here.
p.effects.timers = true;
local style = defaults.make().style;
local look = require('ui.party_theme').party(p, style);
local name = look.font_size;
local timer = math.ceil(require('ui.countdown_text').icon_metrics(look.font, '57', 37, p.effects).height);
assert(timer >= 19, 'Fixture: a countdown half the icon, or a little more with its outline.');
elements.record('strip_1', { x = 1375.6, y = 400.2, width = 420, height = 54 });
local locked = p.locked;
widget.place(p, 1, here, style);
local saved = p.groups[1];
assert(saved.native_detached and saved.detached_x == 1375 and saved.detached_y == 400 and saved.detached_width == 420
    and saved.detached_height == 6 + 3 * (name + 2 + 3 + 37 + timer + 8), 'The panel takes the strip\'s place and width.');
assert(p.locked == locked, 'The lock stays as it is.');
p.effects.timers = false;
widget.place(p, 1, here, style);
assert(saved.detached_height == 6 + 3 * (name + 2 + 3 + 37 + 8), 'Without countdowns the icons alone.');
p.include_self = false;
widget.place(p, 1, here, style);
assert(saved.detached_height == 6 + 2 * (name + 2 + 3 + 37 + 8), 'Without your own row, one member fewer.');
p.include_self, p.effects.timers = true, true;
-- Where the screen has no room under the strip, the panel goes up, and that is the place it saves.
elements.record('strip_1', { x = 1375.6, y = 977.2, width = 420, height = 54 });
widget.place(p, 1, here, style);
assert(saved.detached_y == 1080 - saved.detached_height and saved.detached_y < 977, 'The saved place is where it draws.');
-- A strip that grows with its buffs is narrower than it can be: the panel takes the width the strip can grow to and
-- keeps the strip's edge next to the game's list, on the left here.
assert(p.native.side == 'left', 'Fixture: fresh strips are on the left.');
elements.record('strip_1', { x = 1690, y = 400, width = 99, height = 54 });
widget.place(p, 1, here, style);
assert(saved.detached_width == 420 and saved.detached_x + saved.detached_width == 1690 + 99, 'Up to the widest the strip can be.');
p.native.width = 300;
widget.place(p, 1, here, style);
assert(saved.detached_width == 300 and saved.detached_x == 1789 - 300, 'Strip maximum width sets it.');
p.native.width = 420;
-- On the right of the game's list the panel starts where the strip does, within the screen.
p.groups[1].native_side = 'right';
elements.record('strip_1', { x = 1000, y = 400, width = 65, height = 54 });
widget.place(p, 1, here, style);
assert(saved.detached_x == 1000 and saved.detached_width == 420, 'On the right it grows away from the game\'s list.');
elements.record('strip_1', { x = 1700, y = 400, width = 65, height = 54 });
widget.place(p, 1, here, style);
assert(saved.detached_x == 1700 and saved.detached_width == 220, 'Only as wide as the screen beside the game\'s list.');
p.groups[1].native_side = 'default';
elements.record('strip_1', { x = 10, y = 20, width = 12, height = 14 });
widget.place(p, 1, here, style);
assert(saved.detached_width == 40 and saved.detached_x == 0, 'A panel is at least 40 px wide, on the screen.');
local alliance = p.groups[3];
alliance.detached_x, alliance.detached_y, alliance.detached_width, alliance.detached_height = 50, 60, 300, 222;
widget.place(p, 3, here, style);
assert(alliance.native_detached and alliance.detached_x == 50 and alliance.detached_y == 60 and alliance.detached_width == 300
    and alliance.detached_height == 222, 'A strip not drawn now and not in the game\'s list keeps the panel\'s saved place and size.');

-- End to end: the panel the switch makes is drawn where the strip was, with the icons at the full size.
local hud = require('ui.party_hud');
local function party(count)
    local roster, subjects = hud.sample(6, 100);
    for index = #roster.members, count + 1, -1 do table.remove(roster.members, index); end;
    local first = 1037 - (count - 1) * 20;
    local frame = { x = 1795, y = first, width = 106, height = (count - 1) * 20 + 14, rows = {}, row_height = 14, pitch = 20,
        measured_by = 'rows' };
    for _, member in ipairs(roster.members) do
        frame.rows[member.slot] = { x = 1795, y = first + member.slot * 20, width = 106, height = 14, slot = member.slot };
        local subject = subjects[member.id];
        subject.effects, subject.known = {}, true;
        for effect = 1, 6 do
            subject.effects[effect] = { effect = effect, name = 'Effect ' .. effect, kind = 'buff', remaining = 30, total = 60, status = 'estimated' };
        end;
    end;
    return roster, subjects, { available = true, groups = { frame } };
end;
local q = party_defaults.make();
q.enabled, q.effects.icon_size = true, 37;
local roster, subjects, game = party(4);
local strip = store.copy(overlay.plan(roster, subjects, q, game, 1920, 1080, nil, style)[1]);
assert(not strip.detached and strip.rows[1].options.icon_size == 20, 'Fixture: beside the rows at 20 px.');
elements.record('strip_1', strip);
widget.place(q, 1, overlay.rooms(q, game), style);
local panel = overlay.plan(roster, subjects, q, game, 1920, 1080, nil, style)[1];
-- A panel taller than the room under the strip goes up to stay on the screen, and saves that place.
assert(panel.detached and panel.width == q.native.width and panel.x + panel.width == strip.x + strip.width
    and panel.y == math.min(math.floor(strip.y), 1080 - panel.height) and panel.y + panel.height == 1080
    and panel.x == q.groups[1].detached_x and panel.y == q.groups[1].detached_y,
    'The panel is drawn where the strip was, kept on the screen, at its saved place.');
for _, item in ipairs(panel.rows) do assert(item.options.icon_size == 37, 'In a panel of its own the icons draw at 37 px.'); end;
assert(panel.height == q.groups[1].detached_height and panel.content_height == panel.height, 'Its height is what its members need.');

-- Fresh settings: the strip grows with its buffs, so it is narrow at 20 px. The panel still takes the width the strip
-- can grow to, keeps the strip's edge by the game's list, and is tall enough that nothing scrolls.
for _, count in ipairs({ 4, 6 }) do
    local fresh_party = party_defaults.make();
    fresh_party.enabled, fresh_party.effects.icon_size = true, 37;
    roster, subjects, game = party(count);
    strip = store.copy(overlay.plan(roster, subjects, fresh_party, game, 1920, 1080, nil, style)[1]);
    assert(strip.width == 6 * 20, 'Fixture: six touching 20 px icons wide.');
    elements.record('strip_1', strip);
    widget.place(fresh_party, 1, overlay.rooms(fresh_party, game), style);
    panel = overlay.plan(roster, subjects, fresh_party, game, 1920, 1080, nil, style)[1];
    assert(panel.detached and panel.width == 420 and panel.x + panel.width == strip.x + strip.width
        and panel.y == fresh_party.groups[1].detached_y, count .. ' members: as wide as the strip can grow, beside the game\'s list.');
    assert(panel.content_height <= panel.height and panel.height == fresh_party.groups[1].detached_height,
        count .. ' members: every member\'s buffs show without scrolling.');
    for _, item in ipairs(panel.rows) do
        local cells = require('ui.party_layout').effect_cells(item.effects, item.options, item.area);
        assert(#cells == 6 and cells[6].y == cells[1].y, count .. ' members: six 37 px icons on one line.');
    end;
end;

-- The strips as last planned: three members with six buffs each, as the game's list on the pages below has.
roster, subjects, game = party(3);
overlay.plan(roster, subjects, party_defaults.make(), game, 1920, 1080);

-- The pages, in the real settings window.
local snapshot ={ valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {},
    party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window, panels = require('ui.settings_window'), require('ui.panel_frame');
local game_rows;
local status = app.callbacks.party_native_status;
app.callbacks.party_native_status = function()
    local value = status();
    value.geometry = game_rows;
    return value;
end;
local sliders, typed, radios, chosen, texts = {}, {}, {}, {}, {};
local slider_float, radio, wrapped, unformatted = imgui.SliderFloat, imgui.RadioButton, imgui.TextWrapped, imgui.TextUnformatted;
imgui.SliderFloat = function(label, value, low, high)
    sliders[label] = { low = low, high = high, value = value[1] };
    if typed[label] ~= nil then value[1], typed[label] = typed[label], nil; return true; end;
    return false;
end;
imgui.RadioButton = function(label, active)
    local id = label:match('###(.*)$') or label;
    radios[id] = { caption = label:match('^(.-)###') or label, active = active };
    MOCK.imgui_calls[#MOCK.imgui_calls + 1] = { 'RadioButton', id };
    if chosen[id] then chosen[id] = nil; return true; end;
    return false;
end;
imgui.TextWrapped = function(value, ...) if value ~= nil then texts[value] = true; end; return wrapped(value, ...); end;
imgui.TextUnformatted = function(value, ...) if value ~= nil then texts[value] = true; end; return unformatted(value, ...); end;
local function buttons()
    local out = {};
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Button' then out[call[2]:match('###(.*)$') or call[2]] = true; end; end;
    return out;
end;
local function lines()
    local count = 0;
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'draw:AddLine' then count = count + 1; end; end;
    return count;
end;
local view = { rows = {}, context = { valid = true, job = 3 } };
local function draw(page, tab, clicks)
    local s = app.state.settings;
    s.window.open, s.window.tab = true, page;
    if tab then panels.open('party_ui', tab); end;
    sliders, radios, texts, MOCK.imgui_calls = {}, {}, {}, {};
    for label in pairs(clicks or {}) do MOCK.clicks[label] = true; end;
    window.draw(s, view, app.callbacks);
    assert(not next(MOCK.clicks), 'The control is on the page: ' .. tostring(next(MOCK.clicks)));
    assert(not next(typed) and not next(chosen), 'The slider or choice is on the page.');
    MOCK.clicks = {};
    assert(#MOCK.font_stack == 0);
end;
local function history() app.callbacks.save(); return app.callbacks.history_status(); end;
local function fresh(change)
    local s = defaults.tidy(defaults.make());
    s.party_ui.enabled, s.party_ui.effects.icon_size = true, 37;
    for _, name in ipairs({ 'Look and size', 'What to show' }) do s.window.sections['Home/' .. name] = true; end;
    if change then change(s); end;
    app.state.settings, app.state.history, app.state.redo, app.state.transaction = s, {}, {}, nil;
    app.state.settings_revision = app.state.settings_revision + 1;
    return s;
end;

-- Party list buffs with the game's rows 14 px tall and 20 px apart, and the icon size at 37 px.
local SIZE, BACK = '##frame_Icon size in a panel of its own', 'Put party buffs back beside the party list##frame';
game_rows = geometry({ { 14, 20 } });
local s = fresh();
local e = s.party_ui.effects;
draw('Display', 'place');
assert(texts[STEP] and not texts["Your game's party rows are 14 px tall and 20 px apart."], 'The line about the step, no line about the rows.');
assert(not next(radios) and not texts["Room for each member's icons"], 'There is no room to pick.');
assert(not sliders[SIZE] and not sliders['##frame_Party icon size'] and not texts['In a panel of its own: 37 px.'],
    'With every group beside the rows there is no icon size and no result line.');
local shown = buttons();
assert(not shown['Use all the room up to the next row##frame'] and not shown[BACK], 'Icons are never over the room.');
-- Opening the page changes nothing.
assert(history().undo == 0, 'Drawing writes nothing.');
-- Every save draws the same: whatever size it holds, the line about the step and no icon size.
for _, size in ipairs({ 12, 20, 37 }) do
    s = fresh(function(value) value.party_ui.effects.icon_size = size; end);
    draw('Display', 'place');
    shown = buttons();
    assert(texts[STEP] and not sliders[SIZE] and not next(radios) and not shown['Use all the room up to the next row##frame'],
        'The same for every save at ' .. size);
end;

-- With a group in a panel of its own the icon size shows, for the panel: the whole range with no mark, and the slider
-- says the panel's size, so there is no result line. Typing a size saves it, as one Undo step.
s = fresh(function(value) value.party_ui.groups[1].native_detached = true; end);
e = s.party_ui.effects;
draw('Display', 'place');
assert(sliders[SIZE].low == 12 and sliders[SIZE].high == 128 and sliders[SIZE].value == 37 and lines() == 0,
    'In a panel: the icon size, the whole range, no mark.');
assert(texts[STEP] and not texts['In a panel of its own: 37 px.'], 'The line about the step, and no result line.');
shown = buttons();
assert(shown[BACK], 'The way back.');
typed[SIZE] = 60;
draw('Display', 'place');
local steps = history();
assert(e.icon_size == 60 and e.icon_scale == nil and steps.undo == 1 and steps.undo_label == 'Icon size in a panel of its own',
    'A typed size is kept for the panel, as one Undo step.');
draw('Display', 'place');
assert(sliders[SIZE].value == 60 and not texts['In a panel of its own: 60 px.'], 'The slider follows.');

-- Party in a panel of its own, while Locked: one Undo step, the lock unchanged, the panel where the strip is.
s = fresh();
s.party_ui.locked = true;
app.state.history = {};
elements.record('strip_1', { x = 1375, y = 977, width = 420, height = 54 });
draw('Display', 'place', { ['Your party in a panel of its own##frame'] = true });
local group = s.party_ui.groups[1];
steps = history();
assert(group.native_detached and group.detached_x == 1375 and group.detached_width == 420
    and group.detached_height >= 6 + 3 * (name + 2 + 3 + 37 + 8) and group.detached_y == 1080 - group.detached_height,
    'The party strip is in a panel where it was drawn, moved up to stay on the screen.');
panel = overlay.plan(roster, subjects, s.party_ui, game, 1920, 1080, nil, s.style)[1];
assert(panel.detached and panel.x == 1375 and panel.y == group.detached_y and panel.content_height <= panel.height,
    'Drawn at its saved place, with every member\'s buffs in view.');
assert(not s.party_ui.groups[2].native_detached and not s.party_ui.groups[3].native_detached, 'The other groups stay.');
assert(s.party_ui.locked == true and steps.undo == 1 and steps.undo_label == 'Your party in a panel of its own',
    'One Undo step, and the lock stays on.');
draw('Display', 'place');
shown = buttons();
assert(shown[BACK], 'The way back.');
app.callbacks.undo();
assert(not app.state.settings.party_ui.groups[1].native_detached and app.state.settings.party_ui.locked == true, 'Undo puts the strip back.');

-- Before the game's list is read: no numbers, no stop, no picture.
game_rows = nil;
s = fresh();
draw('Display', 'place');
assert(not texts["Shown once the game's party list is on screen."]
    and texts["Beside the game's party list the icons fill the step from one row to the next, with no space between them."], 'No numbers yet.');
assert(not sliders[SIZE] and not next(radios));
assert(not texts["Beside the game's rows (example rows 14 px tall and 20 px apart)"], 'No example picture.');
s = fresh(function(value) value.party_ui.groups[1].native_detached = true; end);
draw('Display', 'place');
assert(sliders[SIZE].high == 128 and not texts['In a panel of its own: 37 px.'], 'In a panel the icon size shows before the rows are read too.');

-- Party list buffs is the one place for this control: the main page draws none of it, whatever the groups do.
game_rows = geometry({ { 14, 20 } });
s = fresh(function(value) value.party_ui.groups[1].native_detached = true; end);
draw('Home');
assert(not texts[STEP] and not sliders[SIZE] and not buttons()[BACK],
    'The main page has no party size control.');
draw('Display', 'place');
assert(sliders[SIZE].high == 128 and buttons()[BACK], 'Party list buffs has it, with the way back.');
typed[SIZE] = 40;
draw('Display', 'place');
assert(s.party_ui.effects.icon_size == 40 and s.party_ui.effects.icon_scale == nil
    and history().undo_label == 'Icon size in a panel of its own');

-- Place: each group's switch, then the panel's size and place. The panel keeps the strip's edge next to the game's
-- list and takes the width the strip can grow to; Alliance 1 isn't in the game's list here, so it keeps its height.
s = fresh(function(value) value.party_ui.locked = false; end);
app.state.history = {};
elements.record('strip_2', { x = 1200, y = 700, width = 300, height = 40 });
draw('Display', 'place', { ['Alliance 1 in a panel of its own##frame'] = true });
steps = history();
assert(s.party_ui.groups[2].native_detached and s.party_ui.groups[2].detached_x == 1080 and s.party_ui.groups[2].detached_width == 420
    and s.party_ui.groups[2].detached_y == 700 and s.party_ui.groups[2].detached_height == 240
    and steps.undo == 1 and steps.undo_label == 'Alliance 1 in a panel of its own', 'The switch places the panel as one step.');
draw('Display', 'place');
assert(sliders['##frame_Panel width'] and sliders['##frame_Panel height'] and sliders['##frame_Across the screen'] and sliders['##frame_Down the screen'],
    'A panel of its own has its size and place.');
typed['##frame_Across the screen'] = 333;
draw('Display', 'place');
assert(s.party_ui.groups[2].detached_x == 333 and s.party_ui.groups[2].native_x == 0, 'Across the screen is the panel\'s own place.');
draw('Display', 'place', { ['Alliance 1 in a panel of its own##frame'] = true });
assert(not s.party_ui.groups[2].native_detached and s.party_ui.groups[2].detached_x == 333, 'Off puts the strip back and keeps the panel.');
draw('Display', 'place');
assert(not sliders['##frame_Panel width'] and not sliders['##frame_Across the screen'], 'No panel, no panel fields.');

-- A group moves by Shift + left-drag only: no typed offsets, and the panel says how. Place keeps the gap and the way to
-- put back what a drag saved.
s = fresh(function(value) value.party_ui.locked = false; end);
draw('Display', 'place');
assert(not sliders['##frame_Move across'] and not sliders['##frame_Move down'], 'No Move across or Move down.');
assert(sliders["##frame_Gap from the game's list"] and buttons()['Put moved groups back##frame'], 'The gap and the way back stay.');
assert(texts['Unlocked: hold Shift and drag a group to move it.'], 'The panel says a group moves by Shift and a drag.');

-- A row beside the game's list grows with its buffs up to Longest row, so there is no fixed width.
local begin_combo, combos = imgui.BeginCombo, {};
imgui.BeginCombo = function(label) combos[label] = true; return false; end;
s = fresh();
draw('Display', 'place');
assert(combos['##frame_Buff side'], 'Buff side stays.');
draw('Display', 'place');
assert(not combos['##frame_Row width'] and sliders['##frame_Longest row'], 'No fixed width; Longest row stays.');
imgui.BeginCombo = begin_combo;

imgui.SliderFloat, imgui.RadioButton, imgui.TextWrapped, imgui.TextUnformatted = slider_float, radio, wrapped, unformatted;
MOCK.fire('unload');
return 'The party size control says the step and keeps the icon size for panels of their own';
