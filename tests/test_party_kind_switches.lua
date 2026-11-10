-- Buffs and debuffs, Buffs only, Debuffs only and None for the party list buffs: four picks over effects.kind on their
-- Show tab, each change one Undo step. An effect that is neither a buff nor a debuff, such as Level Sync, shows only under
-- Buffs and debuffs, and the tooltip says so. None shows no effect, and the rows that only shape effects go with it. The
-- sample displays follow the choice, and the whole-setup code and a skin keep it.
local defaults, store, party_defaults = require('ui.defaults'), require('core.store'), require('ui.party_defaults');
local imgui, layout = require('imgui'), require('ui.party_layout');
MOCK.screen = { 1920, 1080 };

-- What each choice keeps. Effects with no kind, or one that is neither, count as neutral.
local subject = { effects = {
    { effect = 40, name = 'Protect', kind = 'buff', present = true, key = 'a' },
    { effect = 4, name = 'Paralysis', kind = 'debuff', present = true, key = 'b' },
    { effect = 269, name = 'Level Sync', kind = 'neutral', present = true, key = 'c' },
    { effect = 127, name = 'Costume', present = true, key = 'd' },
} };
local function names(kind)
    local out = {};
    for _, effect in ipairs(layout.effects(subject, { kind = kind })) do out[#out + 1] = effect.name; end;
    table.sort(out);
    return table.concat(out, ', ');
end;
assert(names('all') == 'Costume, Level Sync, Paralysis, Protect', 'Buffs and debuffs: every kind.');
assert(names('buff') == 'Protect', 'Buffs only: no debuffs, and nothing that is neither.');
assert(names('debuff') == 'Paralysis', 'Debuffs only: no buffs, and nothing that is neither.');
assert(names('none') == '', 'None: no effect of any kind.');

-- The sample displays follow the choice: the sample party's Protect and Haste are buffs and its Paralysis a debuff.
local overlay, party_hud = require('ui.native_party_hud'), require('ui.party_hud');
local roster = party_hud.sample(6, 100);
local frame = { x = 900, y = 40, width = 116, height = 132, rows = {} };
for _, member in ipairs(roster.members) do
    frame.rows[member.slot] = { x = 900, y = 40 + member.slot * 22, width = 116, height = 22, slot = member.slot };
end;
local p = party_defaults.make();
p.enabled, p.preview, p.locked = true, true, true;
local planned;
local plan = overlay.plan;
overlay.plan = function(...) planned = plan(...); return planned; end;
local function samples(kind)
    p.effects.kind = kind;
    overlay.draw(roster, {}, p, 100, { native_geometry = { available = true, groups = { frame } } });
    local out = {};
    for _, item in ipairs(planned[1].rows) do
        for _, effect in ipairs(item.effects) do out[effect.kind] = (out[effect.kind] or 0) + 1; end;
    end;
    return out;
end;
local counts = samples('all');
assert(counts.buff == 15 and counts.debuff == 6, 'Samples, Buffs and debuffs: two buffs and a debuff for each of six members, the two Always show effects and a Berserk.');
counts = samples('buff');
assert(counts.buff == 15 and not counts.debuff, 'Samples, Buffs only: the buffs.');
counts = samples('debuff');
assert(counts.debuff == 6 and counts.buff == 2, 'Samples, Debuffs only: the debuffs, and the two Always show effects.');
p.effects.show_copy_image, p.effects.show_third_eye = false, false;
counts = samples('debuff');
assert(counts.debuff == 6 and not counts.buff, 'Samples, Debuffs only with Always show unticked: the debuffs.');
counts = samples('all');
assert(counts.buff == 13 and counts.debuff == 6, 'Samples, Buffs and debuffs with Always show unticked: they go.');
p.effects.show_copy_image, p.effects.show_third_eye = true, true;
assert(next(samples('none')) == nil, 'Samples, None: no effects.');
overlay.plan = plan;

-- The whole-setup code keeps the choice at every size and skin, and so does a skin alone.
local presets = require('setup_fixture');
for _, kind in ipairs({ 'buff', 'debuff', 'none', 'all' }) do
    for _, size in ipairs({ 'minimal', 'minimal_1_5x', 'minimal_2x' }) do
        for _, skin in ipairs({ 'keep', 'Original FFXI', 'XI View', 'Phoenix', 'Minimal' }) do
            local s = defaults.tidy(defaults.make());
            s.party_ui.effects.kind = kind;
            assert(presets.apply(s, { skin = skin, size = size, matching = true, window_type = 1, screen_width = 1920, screen_height = 1080 }),
                'Fixture: ' .. skin .. ' at ' .. size .. ' applies.');
            assert(s.party_ui.effects.kind == kind, 'Apply ' .. skin .. ' at ' .. size .. ' keeps ' .. kind .. '.');
        end;
    end;
    local s = defaults.tidy(defaults.make());
    s.party_ui.effects.kind = kind;
    presets.apply_skin(s, { skin = 'XI View', matching = true, window_type = 1 });
    assert(s.party_ui.effects.kind == kind, 'A skin keeps ' .. kind .. '.');
    assert(defaults.tidy(s).party_ui.effects.kind == kind, 'A save keeps ' .. kind .. '.');
end;

-- The pages, in the real settings window.
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {},
    party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window, panels = require('ui.settings_window'), require('ui.panel_frame');
local view = { rows = {}, context = { valid = true, job = 3 } };
local combo;
local begin_combo = imgui.BeginCombo;
imgui.BeginCombo = function(label, ...) begin_combo(label, ...); return label == combo; end;
local function draw(page, tab, clicks, opened)
    local s = app.state.settings;
    s.window.open, s.window.tab = true, page;
    if tab then panels.open('party_ui', tab); end;
    MOCK.imgui_calls, combo = {}, opened;
    for label in pairs(clicks or {}) do MOCK.clicks[label] = true; end;
    window.draw(s, view, app.callbacks);
    assert(not next(MOCK.clicks), 'The control is on the page: ' .. tostring(next(MOCK.clicks)));
    MOCK.clicks = {};
    assert(#MOCK.font_stack == 0);
end;
-- Each pick drawn, in order, and the one picked.
local function picks()
    local order, picked = {}, nil;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'RadioButton' then
            order[#order + 1] = call[2];
            if call[3] then assert(not picked, 'One pick at a time.'); picked = call[2]; end;
        end;
    end;
    return order, picked;
end;
local function history() app.callbacks.save(); return app.callbacks.history_status(); end;
local function fresh()
    local s = defaults.tidy(defaults.make());
    s.party_ui.enabled = true;
    app.state.settings, app.state.history, app.state.redo, app.state.transaction = s, {}, {}, nil;
    return s;
end;
local ALL, BUFFS, DEBUFFS, NONE = 'Buffs and debuffs##frame_Show_kinds_all', 'Buffs only##frame_Show_kinds_buff', 'Debuffs only##frame_Show_kinds_debuff',
    'None##frame_Show_kinds_none';

-- The four picks, every kind at first.
local s = fresh();
draw('Display', 'show');
local order, picked = picks();
assert(table.concat(order, '|') == ALL .. '|' .. BUFFS .. '|' .. DEBUFFS .. '|' .. NONE, 'The four picks, in order: ' .. table.concat(order, '|'));
assert(picked == ALL and s.party_ui.effects.kind == 'all', 'Buffs and debuffs is picked at first: every kind.');
draw('Display', 'show', { [BUFFS] = true });
local steps = history();
assert(s.party_ui.effects.kind == 'buff' and steps.undo == 1 and steps.undo_label == 'Show buffs or debuffs', 'Buffs only: one Undo step.');
draw('Display', 'show', { [DEBUFFS] = true });
steps = history();
assert(s.party_ui.effects.kind == 'debuff' and steps.undo == 2, 'Debuffs only: one step.');
draw('Display', 'show');
order, picked = picks();
assert(picked == DEBUFFS, 'Picking Debuffs only moved the pick.');
draw('Display', 'show', { [ALL] = true });
steps = history();
assert(s.party_ui.effects.kind == 'all' and steps.undo == 3, 'Buffs and debuffs: every kind.');
app.callbacks.undo();
assert(app.state.settings.party_ui.effects.kind == 'debuff', 'Undo brings Debuffs only back.');

-- Search finds them by every old name, and the tooltip says what happens to the rest.
local party = require('ui.search_index').controls.Display;
assert(party['Show buffs or debuffs']:find('such as Level Sync, show only under Buffs and debuffs', 1, true), 'The tooltip says what happens to the rest.');
for _, name in ipairs({ 'Party buffs only', 'Party debuffs only', 'Party buffs and debuffs', 'Effect types' }) do
    local found = false;
    for _, result in ipairs(window.search(name)) do found = found or result.label == 'Show buffs or debuffs'; end;
    assert(found, name .. ' finds the picks.');
end;

-- None: the rows that only shape effects leave both tabs, and search leads to the pick that brings them back. Your own
-- row stays, as it decides whether your row shows at all.
local function on_page(label)
    for _, call in ipairs(MOCK.imgui_calls) do if call[2] == label then return true; end; end;
    return false;
end;
local effect_rows = { show = { 'Light up debuffs you can remove##frame', 'Countdowns##frame', '##frame_Most per member', '##frame_Sort', party_defaults.strip_help },
    place = { '##frame_Countdown size', '##frame_Icons fill' } };
local function effect_rows_are(shown)
    for tab, labels in pairs(effect_rows) do
        draw('Display', tab);
        for _, label in ipairs(labels) do assert(on_page(label) == shown, label .. (shown and ' shows.' or ' goes with None.')); end;
    end;
end;
s = fresh();
s.party_ui.effects.timers = true;
effect_rows_are(true);
draw('Display', 'show', { [NONE] = true });
steps = history();
assert(s.party_ui.effects.kind == 'none' and steps.undo == 1 and steps.undo_label == 'Show buffs or debuffs', 'None: one Undo step.');
effect_rows_are(false);
draw('Display', 'show');
assert(on_page('##frame_Your own row'), 'Your own row stays with None.');
for _, name in ipairs({ 'Countdowns', 'Countdown size', 'Most per member', 'Effect sorting', 'Icons fill', 'Light up debuffs you can remove' }) do
    local led = false;
    for _, result in ipairs(window.search(name)) do led = led or result.label == 'Show buffs or debuffs'; end;
    assert(led, 'Search leads ' .. name .. ' to the picks while None hides it.');
end;
assert(s.party_ui.effects.timers == true, 'None leaves Countdowns as it was.');
app.callbacks.undo();
effect_rows_are(true);

-- The line under the rows says what the party cooldowns do here, and a None with none here says nothing shows.
local here_too, only_here, nothing = 'Party cooldowns show here too.', 'Only Party cooldowns show here.', 'No effects show, and Party cooldowns don\'t show here either.';
for _, case in ipairs({ { 'all', false, true }, { 'all', true, false }, { 'all', true, true, here_too }, { 'none', true, true, only_here },
    { 'none', false, true, nothing }, { 'none', true, false, nothing } }) do
    s = fresh();
    s.party_ui.effects.kind, s.party_cooldowns.enabled, s.party_cooldowns.strips = case[1], case[2], case[3];
    draw('Display', 'show');
    for _, line in ipairs({ here_too, only_here, nothing }) do
        assert(on_page(line) == (line == case[4]), table.concat({ case[1], tostring(case[2]), tostring(case[3]) }, ' ') .. ': ' .. line);
    end;
    assert(on_page('Change on Party cooldowns##frame') == (case[4] ~= nil), 'The way to Party cooldowns goes with its line.');
end;
-- With this display off or no group ticked they have nowhere to draw, so no line says they show here.
for _, setup in ipairs({ function(p) p.enabled = false; end, function(p) p.strips.party, p.strips.alliance1, p.strips.alliance2 = false, false, false; end }) do
    s = fresh();
    s.party_cooldowns.enabled = true;
    setup(s.party_ui);
    draw('Display', 'show');
    assert(not on_page(here_too) and not on_page('Change on Party cooldowns##frame'), 'Nothing claims they show here.');
end;

-- Countdowns sits above Your own row, alone on its line.
s = fresh();
draw('Display', 'show');
local countdown_switch, step;
for index, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'Checkbox' and call[2] == 'Countdowns##frame' then countdown_switch = index; end;
    if call[1] == 'TextUnformatted' and call[2] == 'Your own row' then step = index; end;
end;
assert(countdown_switch and step and countdown_switch < step, 'Countdowns above Your own row.');
for index = countdown_switch + 1, step do
    assert(MOCK.imgui_calls[index][1] ~= 'SameLine', 'Countdowns has its line to itself.');
end;
-- Countdowns says what it does in plain words.
local timers_help = 'Shows the time left on each party buff icon. It is off unless you turn it on. Beside the game\'s party'
    .. ' list the time sits inside the icon.';
assert((party['Countdowns'] or ''):find(timers_help, 1, true), 'The Countdowns tooltip.');
assert(require('ui.search_index').controls.Home['Party countdowns'] == nil, 'The main page has no copy of it.');
assert(#MOCK.commands == 0, 'Nothing is sent to the game.');

imgui.BeginCombo = begin_combo;
MOCK.fire('unload');
return 'Buffs only and Debuffs only set the party effect kind, one at a time, and leave the rest out plainly';
