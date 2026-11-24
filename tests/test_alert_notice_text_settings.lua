-- The notice text options in the settings and what carries them. Alerts has a Look tab with Notice text size and
-- Notice text color, and each rule has Notice color beside its other notice settings. They are saved, reset with
-- Alerts, shared with the shared look, and travel in the Alerts export and in an exported rule. A layout, which is
-- only where things are, leaves them out.
local h = require('panel_fixture')();
local defaults, custom, share, store = require('ui.defaults'), require('core.customization'), require('core.share'), require('core.store');
local profiles = require('core.profiles');
local alerts = require('ui.alert_panel');
local imgui = h.imgui;
local SIZE, COLOR, RULE_COLOR = '##frame_Notice text size', 'Notice text color##frame', 'Notice color##frame';
local RED, GREEN = { 1, 0, 0, 1 }, { 0, 1, 0, 1 };

-- A color picked on the frame's next draw, by its row.
local pick_color;
local color_edit = imgui.ColorEdit4;
imgui.ColorEdit4 = function(label, value, ...)
    color_edit(label, value, ...);
    if pick_color and pick_color[1] == label then
        for index = 1, 4 do value[index] = pick_color[2][index]; end
        pick_color = nil;
        return true;
    end
    return false;
end;
local function color(label, value)
    pick_color = { label, value };
    h.draw();
    assert(pick_color == nil, 'The color is on the page: ' .. label);
    h.draw();
end
-- The button that takes a color of its own off, by what the frame knows it as.
local function back_button(text) return 'frame_back_' .. text; end

-- Show has both rows, with the settings for every alert, and no other tab has them.
h.fresh();
for _, tab in ipairs({ 'place', 'when' }) do
    h.on('notices', tab);
    assert(not h.called('SliderFloat', SIZE) and not h.called('ColorEdit4', COLOR), 'The notice text rows are not on Alerts ' .. tab .. '.');
end
h.on('notices', 'show');
assert(h.called('SliderFloat', SIZE) and h.called('ColorEdit4', COLOR), 'Alerts Show has the notice text size and color.');
-- At 0 the slider says what it follows.
local shown = false;
for _, value in ipairs(h.calls('SliderFloat', SIZE)[1]) do if value == 'Same as Text size' then shown = true; end end
assert(shown and h.s.alerts.notice_text_size == 0, 'It starts as Same as Text size.');
-- The size: saved as slid, never between 0 and 8.
h.slide(SIZE, 30);
assert(h.s.alerts.notice_text_size == 30, 'Sliding it sets the size: ' .. tostring(h.s.alerts.notice_text_size));
h.slide(SIZE, 3);
assert(h.s.alerts.notice_text_size == 8, 'A size under the smallest text is the smallest: ' .. tostring(h.s.alerts.notice_text_size));
h.slide(SIZE, 0);
assert(h.s.alerts.notice_text_size == 0, 'And 0 is the shared size again.');
h.slide(SIZE, 30);
local steps = #h.app.state.history;
h.draw('Undo');
h.draw();
assert(h.s.alerts.notice_text_size == 0 and #h.app.state.history == steps - 1, 'A size change is one Undo step.');
-- The color: none of its own at first, set by a pick, and put back with its button.
assert(h.s.alerts.notice_colors.text == nil and h.says('From the main page') and not h.called('Button', back_button('Notice text color')),
    'With no color of its own it reads From the main page.');
color(COLOR, RED);
assert(h.s.alerts.notice_colors.text and h.s.alerts.notice_colors.text[1] == 1 and h.s.alerts.notice_colors.text[2] == 0, 'A pick gives Alerts its own text color.');
assert(h.called('Button', back_button('Notice text color')), 'Then it can go back to the shared one.');
h.draw(back_button('Notice text color'));
h.draw();
assert(h.s.alerts.notice_colors.text == nil, 'Use the main page\'s color takes it off again.');

-- A rule's notice color: beside Show a notice, and only while the rule shows one.
local function open(change)
    h.fresh(function(s)
        local rule = defaults.rule('r1');
        rule.name, rule.effect, rule.event = 'Probe', 2, 'gain';
        if change then change(rule, s); end
        s.alerts.rules = { rule };
    end);
    alerts.edit('r1');
    h.on('notices', 'show');
end
local function rule() return h.s.alerts.rules[1]; end
open();
assert(h.called('ColorEdit4', RULE_COLOR), 'A rule that shows a notice has its Notice color.');
assert(rule().notice_colors.text == nil, 'Fixture: none of its own yet.');
color(RULE_COLOR, GREEN);
assert(rule().notice_colors.text and rule().notice_colors.text[2] == 1 and rule().notice_colors.text[1] == 0, 'A pick gives the rule its own notice color.');
assert(h.s.alerts.notice_colors.text == nil, 'And leaves the Alerts color alone.');
h.draw(back_button('Notice color'));
h.draw();
assert(rule().notice_colors.text == nil, 'Use Alerts\' color takes the rule\'s own off.');
open(function(made) made.visual = false; end);
assert(not h.called('ColorEdit4', RULE_COLOR), 'A rule that shows no notice has no notice color to set.');
-- With none of its own, the rule's swatch shows the color its notice will have: the Alerts one, else the shared one.
local swatch;
imgui.ColorEdit4 = function(label, value, ...)
    if label == RULE_COLOR then swatch = { value[1], value[2], value[3], value[4] }; end
    return color_edit(label, value, ...) and false;
end;
open(function(_, s) s.alerts.notice_colors.text = { 0.25, 0.5, 0.75, 1 }; end);
assert(swatch and swatch[1] == 0.25 and swatch[2] == 0.5 and swatch[3] == 0.75, 'The swatch shows the Alerts color.');
open();
local shared = h.s.style.text_color;
assert(swatch[1] == shared[1] and swatch[2] == shared[2] and swatch[3] == shared[3], 'And the shared text color when Alerts has none.');
imgui.ColorEdit4 = color_edit;

-- Search finds them by what they are for.
local function found(text, label)
    for _, entry in ipairs(h.window.search(text)) do
        if entry.panel == 'notices' and entry.label == label then return true; end
    end
    return false;
end
assert(found('notice text size', 'Notice text size') and found('alert text bigger', 'Notice text size'), 'Search finds the size.');
assert(found('alert color', 'Notice text color') and found('notice color', 'Notice color'), 'And both colors.');

-- Reset Alerts puts both back, with the rest of Alerts.
local s = defaults.tidy(defaults.make());
s.alerts.notice_text_size, s.alerts.notice_colors.text = 30, RED;
s = custom.reset(s, 'alerts');
assert(s.alerts.notice_text_size == 0 and next(s.alerts.notice_colors) == nil, 'Reset all of this display puts the notice text back.');

-- The shared look carries them, both ways.
local mine, theirs = defaults.tidy(defaults.make()), defaults.tidy(defaults.make());
mine.alerts.notice_text_size, mine.alerts.notice_colors.text = 28, RED;
local look = profiles.capture_layout(mine, 'presentation');
assert(look.presentation.alerts.notice_text_size == 28 and look.presentation.alerts.notice_colors.text[1] == 1, 'A shared look holds the notice text.');
assert(profiles.apply_layout(theirs, store.copy(look), 'presentation'), 'Fixture: the look applies.');
assert(theirs.alerts.notice_text_size == 28 and theirs.alerts.notice_colors.text and theirs.alerts.notice_colors.text[1] == 1, 'Another character takes it.');
mine.alerts.notice_text_size, mine.alerts.notice_colors = 0, {};
assert(profiles.apply_layout(theirs, profiles.capture_layout(mine, 'presentation'), 'presentation'), 'Fixture: the look applies again.');
assert(theirs.alerts.notice_text_size == 0 and theirs.alerts.notice_colors.text == nil, 'And takes it off again when the look has none.');
-- Placement alone leaves it be.
mine.alerts.notice_text_size = 28;
theirs.alerts.notice_text_size = 12;
assert(profiles.apply_layout(theirs, profiles.capture_layout(mine, 'placement'), 'placement'), 'Fixture: the placement applies.');
assert(theirs.alerts.notice_text_size == 12, 'Sharing only where things are leaves the notice text alone.');

-- Exports: the Alerts display's string and a named profile hold them, a rule holds its color, a layout holds neither.
local out = defaults.tidy(defaults.make());
out.alerts.notice_text_size, out.alerts.notice_colors.text = 28, RED;
local made = defaults.rule('r1');
made.name, made.effect, made.notice_colors = 'Sleep on me', 2, { text = GREEN };
out.alerts.rules = { made };
out = defaults.tidy(out);
local function read(kind, id) return assert(share.read(assert(share.export(out, kind, id, 'Tester')))); end
local display = read('element', 'notices');
assert(display.data.notice_text_size == 28 and display.data.notice_colors.text[1] == 1, 'The Alerts display\'s string holds the notice text.');
local rules = read('alerts');
assert(rules.data.rules[1].notice_colors.text[2] == 1, 'An exported rule keeps its notice color.');
local layout = read('layout');
assert(layout.data.notices.notice_text_size == nil and layout.data.notices.notice_colors == nil and layout.data.notices.notice_width == 440,
    'A layout is where things are, and holds no notice text.');
local profile = read('profile');
assert(profile.data.alerts.notice_text_size == 28 and profile.data.alerts.notice_colors.text[1] == 1, 'A profile holds it.');
-- Importing the Alerts display's string sets them, and the summary counts them.
local taker = defaults.tidy(defaults.make());
local candidate = assert(share.candidate(taker, display, 'replace'));
assert(candidate.alerts.notice_text_size == 28 and candidate.alerts.notice_colors.text and candidate.alerts.notice_colors.text[1] == 1,
    'An import of the Alerts display takes the notice text.');
local lines = table.concat(share.changes(taker, candidate), ' | ');
assert(lines == 'Alerts: 2 settings change.', 'The import says the two Alerts settings change: ' .. lines);
local same = assert(share.candidate(candidate, display, 'replace'));
assert(table.concat(share.changes(candidate, same), ' | ') == 'Nothing changes.', 'Importing it twice changes nothing more.');

-- A skin pick sets the Alerts color back to the shared text color, as it sets every display's own colors back, and
-- asks first, naming Alerts. A rule's own Notice color is a color set for one effect, so it stays.
local appearance = require('ui.appearance');
local function names(list)
    local out = {};
    for index, entry in ipairs(list) do out[index] = entry.label; end
    return table.concat(out, ', ');
end
local skinned = defaults.tidy(defaults.make());
assert(#appearance.replaced(skinned) == 0, 'Fixture: with no color of its own, Alerts has no look of its own.');
skinned.alerts.notice_colors.text = RED;
assert(names(appearance.replaced(skinned)) == 'Alerts', 'Its own text color is a look of its own: ' .. names(appearance.replaced(skinned)));
local mint = store.copy(skinned);
assert(appearance.apply(mint, 'Mint', { matching = true }), 'Fixture: the skin applies.');
assert(next(mint.alerts.notice_colors) == nil, 'A skin sets it back.');
assert(names(appearance.replaced(skinned, mint)) == 'Alerts', 'And a skin pick names Alerts.');
-- On the main page the pick waits for Apply, which sets it back in one step and keeps the rule's own color.
h.fresh(function(s)
    s.alerts.notice_colors.text = RED;
    local probe = defaults.rule('r1');
    probe.name, probe.effect, probe.event, probe.notice_colors = 'Probe', 2, 'gain', { text = GREEN };
    s.alerts.rules = { probe };
end);
h.draw();
h.pick('##main_skin', 'Mint##Mint');
assert(h.says('Mint replaces the custom look on: Alerts. Colors you set for one effect and row text colors stay.')
    and h.s.alerts.notice_colors.text and #h.app.state.history == 0, 'The pick names Alerts and waits.');
h.draw('Apply##look_main_skin');
h.draw();
assert(next(h.s.alerts.notice_colors) == nil and h.s.alerts.rules[1].notice_colors.text[2] == 1 and #h.app.state.history == 1,
    'Apply sets the Alerts color back in one step and keeps the rule\'s own.');
assert(h.app.callbacks.undo() and h.app.state.settings.alerts.notice_colors.text[1] == 1, 'Undo brings it back.');
return 'The notice text options are in the settings and travel with the look';
