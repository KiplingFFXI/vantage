-- Settings window slips, by what a player would see: a tick that shuts the window, a box handed more text than its size, a
-- window that walks the whole save each frame, searches that go nowhere, words that say too much or too little.
local h = require('panel_fixture')();
local app, window, frame = h.app, h.window, h.panels;
local customization, defaults, hud = require('core.customization'), require('ui.defaults'), require('ui.hud');
local function command(text) local event = { command = text }; MOCK.fire('command', event); assert(event.blocked, text); end;

-- A rule that stops being a rule with conditions leaves the fold with its rows still to draw. The tick stays, and the
-- window stays open.
local catalog = { { id = 0, name = 'Ko' }, { id = 33, name = 'Haste' }, { id = 253, name = 'Signet' } };
window.main_helpers.catalog = function() return catalog; end;
h.fresh();
h.on('hidden', 'show');
h.type('##frame_Find an effect', 'Haste');
h.pick('##frame_Effect', 'Haste##33');
h.draw('Add a rule##frame');
h.draw();
h.draw('Use this rule##frame');
assert(not h.says('This rule hides every effect on every display while it is on.'), 'The rows on their way out say nothing of the rule.');
h.draw();
assert(h.s.effect_filters.rules[1].enabled, 'The tick stays.');
assert(not app.state.settings_stopped, 'The window stays.');
assert(not h.called('Checkbox', 'Use this rule##frame'), 'A rule that hides for everyone goes on the list, out of the fold.');
h.fresh(function(s) s.effect_filters.rules = { { enabled = true, effect = 33, kind = 'all', name = 'Fennel', job = 0, scope = 'all' } }; end);
h.on('hidden', 'show');
h.typed['##frame_Player name'] = '';
h.draw();
assert(h.s.effect_filters.rules[1].name == '' and not app.state.settings_stopped, 'So does clearing the last thing that made it a rule of its own.');

-- The box is handed its size and copies all it's given, so a saved list longer than it could type takes a bigger one.
local function box_size(thresholds)
    h.fresh(function(s)
        local rule = defaults.rule('probe');
        rule.id, rule.name, rule.effect, rule.event, rule.unit, rule.thresholds = 'r1', 'Probe', 33, 'remaining', 'seconds', thresholds;
        s.alerts.rules = { rule };
    end);
    h.on('notices', 'show');
    h.draw('Edit##alert');
    h.draw();
    local call = h.calls('InputText', '##thresholds')[1];
    assert(call, 'Fixture: the rule is open.');
    h.draw('Done##alert');
    return call[4], #table.concat(thresholds, ', ');
end;
assert(box_size({ 30, 10 }) == 81, 'A short list keeps the usual box.');
local long = {};
for number = 1, 200 do long[number] = 10000 + number; end;
local size, text = box_size(long);
assert(size == text + 1 and size > 81, 'A long list gets a box its size: ' .. tostring(size));

-- The window keeps a copy to put back if a page fails, and takes it only when the settings changed.
local keep, kept = customization.keep, 0;
customization.keep = function(...) kept = kept + 1; return keep(...); end;
local function present() kept = 0; h.s.window.open = true; MOCK.frame(1 / 60); return kept; end;
for _ = 1, 400 do MOCK.frame(0.05); if app.state.ready ~= false then break; end; end;
h.fresh();
h.on('self_buffs', 'show');
present(); present();
assert(present() == 0, 'A quiet frame walks nothing.');
h.bump();
assert(present() == 1, 'A change is kept.');
assert(present() == 0, 'Once.');
customization.keep = keep;

-- A display with nothing on keeps its search topics out of its way: they go to a timer panel.
for _, id in ipairs({ 'rolls', 'hidden', 'notices', 'party_ui', 'overhead' }) do
    h.fresh();
    h.on(id, 'show');
    local topic;
    for _, result in ipairs(window.search('which kinds of effects a panel shows')) do
        if result.topic then topic = result; break; end;
    end;
    assert(topic and topic.timers == 'status', 'Fixture: the topic names a status timer.');
    window.open_result(topic);
    h.draw(); h.draw();
    assert(frame.opened() == 'self_buffs', 'From ' .. id .. ' it opens a timer panel: ' .. tostring(frame.opened()));
end;

-- Words typed with what they sit next to.
h.fresh();
h.on('self_buffs', 'look');
local function first(query) local result = window.search(query)[1]; return result and result.label; end;
assert(first('bar shape,') == 'Bar shape' and first('(bar shape)') == 'Bar shape' and first('[bar shape]') == 'Bar shape', 'Punctuation at a word\'s edge is no part of it.');
assert(window.search('[') and window.search('%') and window.search('('), 'Punctuation alone is read as itself, not as a pattern.');

-- What's picked on the page moves the search, with the settings still.
h.fresh();
h.on('target', 'filters');
local function finds(query, label)
    for _, result in ipairs(window.search(query)) do if result.label == label and result.panel == 'target' then return true; end; end;
    return false;
end;
h.type('##frame_Find an effect', 'Haste');
assert(finds('rename it', 'Rename it'), 'With one picked it is its own row.');
h.type('##frame_Find an effect', 'qqqqq');
assert(finds('rename it', 'Find an effect'), 'With none picked it goes by the box that picks one, though no setting changed.');

-- Recasts in one panel, shown with every kind ticked off, has rows to show.
h.fresh(function(s)
    s.recast_display = 'combined';
    s.panels.recasts.recast_categories.spell, s.panels.recasts.recast_categories.ability, s.panels.recasts.recast_categories.item = false, false, false;
    s.panels.recasts.enabled = false;
end);
h.on('recasts', 'show');
h.draw('On##frame_display');
local kinds = h.s.panels.recasts.recast_categories;
assert(h.s.panels.recasts.enabled and kinds.spell and kinds.ability and kinds.item, 'Show ticks them.');
h.fresh(function(s)
    s.recast_display = 'combined';
    s.panels.recasts.recast_categories.spell, s.panels.recasts.recast_categories.ability, s.panels.recasts.recast_categories.item = false, false, false;
    s.panels.recasts.enabled = false;
end);
command('/vg recasts show');
kinds = app.state.settings.panels.recasts.recast_categories;
assert(app.state.settings.panels.recasts.enabled and kinds.spell and kinds.ability and kinds.item, 'So does /vg recasts show.');

-- Reset this display says what it leaves.
local function question(id, words)
    h.fresh();
    h.on(id, 'show');
    h.draw('Reset this display##frame');
    h.draw();
    assert(h.says(words), id .. ' says: ' .. words);
end;
question('target', 'Follow the cursor stays as it is.');
question('spell_recasts', 'Recast marks and the ready pulse stay as they are.');

-- Ending soon shows on a countdown wherever nothing else says it, and over a Countdown color.
local WARN, OWN, ROW = { 1, 0, 0, 1 }, { 0, 1, 0, 1 }, { 0, 0, 1, 1 };
local function panel(change)
    local p = defaults.make().panels.self_buffs;
    p.warning_enabled, p.warning_seconds, p.colors = true, 10, { warning = WARN };
    if change then change(p); end;
    return p;
end;
local style = defaults.make().style;
style.scale = 1;
local soon, later = { effect = 33, name = 'Haste', deadline = 105, total = 300, kind = 'buff', status = 'exact' }, { effect = 33, name = 'Haste', deadline = 400, total = 300, kind = 'buff', status = 'exact' };
local function time_color(p, row)
    for _, entry in ipairs(hud.entries(row, p, style, 100)) do
        if entry.id == 'time' then return entry.color; end;
    end;
end;
local icons = panel(function(p) p.mode, p.colors.value = 'icons', OWN; end);
assert(time_color(icons, soon) == WARN, 'On Icons Ending soon wins over a Countdown color.');
assert(time_color(icons, later) == OWN, 'And the Countdown color has the rest of the time.');
icons.field_colors = { time = ROW };
assert(time_color(icons, later) == OWN, 'A Row text color saved for the other layouts has no say on Icons.');
local no_bar = panel(function(p) p.mode, p.show_fill, p.field_colors = 'bars', false, { time = ROW }; end);
assert(time_color(no_bar, soon) == WARN, 'A row with no bar says it on its countdown, over a Row text color.');
assert(time_color(no_bar, later) == ROW, 'And goes by the Row text color otherwise.');

-- Rename it reaches the words you get when you point at an icon, where the name shows.
local renamed = hud.details({ effect = 33, name = 'Haste', deadline = 400, total = 300, status = 'exact' }, 100, { horizon = 300, labels = { [33] = 'Hurry' } });
assert(renamed:find('Hurry', 1, true) and not renamed:find('Haste', 1, true), 'Pointing at it shows the name you gave it.');
assert(hud.details({ effect = 33, name = 'Haste', deadline = 400, total = 300, status = 'exact' }, 100, { horizon = 300, labels = { ['33'] = 'Hurry' } }):find('Hurry', 1, true), 'A name read back from a save too.');

-- End samples shows only for a display that can show them.
h.fresh(function(s)
    s.preview = true;
    for _, p in pairs(s.panels) do p.enabled = false; end;
end);
h.s.window.tab = 'Home';
h.draw(); h.draw();
assert(not h.called('Button', 'End samples##main'), 'With every timer panel off there are no samples to end.');
h.fresh(function(s) s.party_ui.enabled, s.party_ui.preview = true, true; end);
command('/vg party hide');
assert(not app.state.settings.party_ui.enabled and not app.state.settings.party_ui.preview, '/vg party hide ends the samples.');

-- /vg reset appearance reads Usual and blink back on every display.
h.fresh(function(s)
    for _, p in pairs(s.panels) do p.countdown_outline, p.countdown_bold, p.blink_icons = false, true, false; end;
    s.party_ui.effects.countdown_outline, s.overhead.countdown_outline, s.rolls.countdown_outline, s.pet.countdown_outline = false, true, true, true;
    s.party_ui.effects.blink_icons, s.overhead.blink_icons, s.pet.blink_icons = false, false, false;
end);
command('/vg reset appearance');
local s, usual = app.state.settings, defaults.make();
for _, id in ipairs(defaults.panel_order) do
    assert(s.panels[id].countdown_outline == usual.panels[id].countdown_outline and s.panels[id].countdown_bold == usual.panels[id].countdown_bold, 'Its countdown text is back: ' .. id);
end;
assert(s.party_ui.effects.countdown_outline == usual.party_ui.effects.countdown_outline and s.overhead.countdown_outline == usual.overhead.countdown_outline
    and s.rolls.countdown_outline == usual.rolls.countdown_outline and s.pet.countdown_outline == usual.pet.countdown_outline, 'And on the displays outside the panels.');
assert(s.panels.self_buffs.blink_icons == usual.panels.self_buffs.blink_icons and s.overhead.blink_icons == usual.overhead.blink_icons and s.pet.blink_icons == usual.pet.blink_icons,
    'Blink comes back with them.');

-- Undo says each step by the name the player knows.
for section, label in pairs({ self_buffs = 'Reset Self buffs', rolls = 'Reset Phantom Roll', pet = 'Reset Pet', alerts = 'Reset Alerts', party_ui = 'Reset Party list buffs',
    party_cooldowns = 'Reset Party cooldowns', overhead = 'Reset Overhead icons', job_profiles = 'Unlink all jobs', watch_list = 'Reset watch list' }) do
    assert(customization.reset_label(section) == label, 'Undo says ' .. label .. ': ' .. customization.reset_label(section));
end;
assert(customization.reset_label() == 'Reset all' and customization.reset_label('all') == 'Reset all', 'Everything is Reset all.');
h.fresh();
assert(app.callbacks.profile_save('Healer', false), 'Fixture: a profile saved.');
assert(app.callbacks.profile_link(3, 'Healer'));
assert(app.callbacks.history_status().undo_label == 'Link a job to Healer', 'Linking says to what.');
assert(app.callbacks.profile_link(3, ''));
assert(app.callbacks.history_status().undo_label == 'Unlink a job', 'Unlinking says so.');
assert(app.callbacks.profile_load('Healer'));
assert(app.callbacks.history_status().undo_label == 'Load Healer', 'Loading says which.');

-- A reset that can't work says what can.
local ok, why = app.callbacks.reset('nonsense');
assert(not ok and why:find('window_style', 1, true) and why:find('visibility', 1, true) and why:find('tracking', 1, true), 'The list of what can be reset is whole: ' .. tostring(why));
-- Publishing placement over a shared file: a cleared Moves with stays cleared.
local store, profiles = require('core.store'), require('core.profiles');
local saved = profiles.new((app.state.path:gsub('Tester_1001/settings.json$', '')));
local shared = defaults.make();
shared.panels.self_buffs.anchor.to, shared.panels.self_buffs.anchor.element = 'element', 'self_debuffs';
assert(store.write(saved.layout_path, { scope = 'presentation', presentation = shared }), 'Fixture: a shared file.');
local mine = defaults.tidy(defaults.make());
mine.shared_scope = 'placement';
assert(saved:publish_layout(mine), 'Fixture: published.');
local kept = store.read(saved.layout_path).presentation.panels.self_buffs;
assert(kept.anchor.to ~= 'element', 'What this character cleared stays clear.');
os.remove(saved.layout_path);
return 'The settings window stays fixed';
