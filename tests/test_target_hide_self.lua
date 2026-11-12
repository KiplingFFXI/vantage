-- Target timers' Hide while I target myself (panels.target.hide_self). Targeting yourself fills Target timers with
-- your own effects, which Self buffs and Self debuffs already show. With the tick on, the panel isn't drawn while
-- your target is you: no rows, no heading and no empty box. Samples and edit mode still show it, as they do a panel
-- its When to show hides. It starts off, only Target timers has it, and the page says so while it hides the panel.
package.loaded['ui.icons'] = { status = function(id) return 1000 + id; end };
local defaults, hud, tracker = require('ui.defaults'), require('ui.hud'), require('core.tracker');
local window, panels = require('ui.settings_window'), require('ui.panel_frame');
local store, custom, imgui = require('core.store'), require('core.customization'), require('imgui');
local copy, equal = store.copy, custom.equal;

-- It starts off, on Target timers alone, and a save can only hold true or false for it.
local settings = defaults.make();
for id, panel in pairs(settings.panels) do
    if id == 'target' then assert(panel.hide_self == false, 'Hide while I target myself starts off.');
    else assert(panel.hide_self == nil, id .. ' has no such setting.'); end
end
for _, junk in ipairs({ 'yes', 1, 0, {}, 'true' }) do
    local saved = defaults.make();
    saved.panels.target.hide_self = junk;
    assert(defaults.tidy(saved).panels.target.hide_self == false, 'A save that holds something else for it reads as off.');
end
local kept = defaults.make();
kept.panels.target.hide_self = true;
assert(defaults.tidy(kept).panels.target.hide_self == true, 'A save keeps it on.');
local missing = defaults.make();
missing.panels.target.hide_self = nil;
assert(defaults.tidy(missing).panels.target.hide_self == false, 'A save from before it reads as off.');

-- When it hides the panel: the tick is on and the target is you.
local me = { id = 1001, target = { id = 1001 } };
assert(not defaults.hides_own_target(settings, me), 'Off, it hides nothing.');
settings.panels.target.hide_self = true;
assert(defaults.hides_own_target(settings, me) == true, 'On, a target that is you hides the panel.');
assert(not defaults.hides_own_target(settings, { id = 1001, target = { id = 2002 } }), 'Another target doesn\'t.');
assert(not defaults.hides_own_target(settings, { id = 1001 }), 'Nor does no target.');
assert(not defaults.hides_own_target(settings, { id = 1001, target = {} }), 'Nor a target with no id.');
assert(not defaults.hides_own_target(settings, { target = {} }), 'Nor a client that knows neither.');
assert(not defaults.hides_own_target(settings, nil) and not defaults.hides_own_target(settings, {}), 'Nor no client at all.');
settings.panels.target.hide_self = false;

-- The panels, drawn by the real tracker and hud.
settings.style.font, settings.style.font_size, settings.style.scale = 'Ashita', 14, 1;
settings.window.open = true;
for id, panel in pairs(settings.panels) do
    panel.enabled = id == 'self_buffs' or id == 'self_debuffs' or id == 'target';
    panel.show_heading, panel.width, panel.max_rows = false, 240, 32;
end
MOCK.screen, MOCK.content_width = { 1600, 1000 }, 1200;
local SELF, OTHER = { id = 1001, kind = 'player', name = 'Self' }, { id = 2002, kind = 'player', name = 'Other player' };
local snapshot = { valid = true, id = 1001, name = 'Self', zone = 102, self_known = true, party = {}, entities = {},
    target = SELF, self_effects = { { effect = 33, slot = 0, deadline = 400 }, { effect = 13, slot = 1, deadline = 500 } } };
local tracked = tracker.new();
local view;
local function refresh(target)
    snapshot.target = target;
    tracked:reconcile(snapshot, 100);
    view = tracked:view(100, settings, snapshot);
    assert(#view.rows == 2, 'Fixture: a buff and a debuff of your own.');
end
local begun, said = {}, {};
local begin = imgui.Begin;
imgui.Begin = function(name, ...) begun[name] = true; return begin(name, ...); end;
for _, name in ipairs({ 'TextWrapped', 'TextUnformatted', 'Text', 'TextDisabled' }) do
    local draw = imgui[name];
    imgui[name] = function(text, ...) if type(text) == 'string' then said[text] = true; end; return draw(text, ...); end;
end
-- Whether Target timers is drawn this frame. The self panels always are.
local function target_drawn(callbacks)
    begun = {};
    local before = copy(view);
    MOCK.imgui_calls = {};
    hud.draw(view, settings, 100, callbacks or {});
    assert(begun['##vantage_self_buffs'] and begun['##vantage_self_debuffs'], 'The self panels show your effects either way.');
    assert(equal(view, before), 'Drawing changes nothing the tracker holds.');
    assert(#MOCK.font_stack == 0);
    return begun['##vantage_target'] == true;
end
local target = settings.panels.target;
for _, mode in ipairs({ 'bars', 'icons' }) do
    for _, id in ipairs({ 'self_buffs', 'self_debuffs', 'target' }) do settings.panels[id].mode = mode; end
    target.hide_self, target.empty = false, 'hide';
    refresh(SELF);
    assert(#hud.filter_rows(view, target, 'target', settings) == 2 and target_drawn(), mode .. ': off, targeting yourself shows your effects on Target timers.');
    target.hide_self = true;
    assert(not target_drawn(), mode .. ': on, Target timers isn\'t drawn while your target is you.');
    assert(#hud.filter_rows(view, target, 'target', settings) == 2, 'Its rows are still yours: the panel is hidden, not filtered.');
    -- Not even as an empty box, which a panel set to show when empty draws.
    target.empty = 'show';
    assert(not target_drawn(), mode .. ': it draws no empty box either.');
    refresh(OTHER);
    assert(target_drawn(), mode .. ': another target has its panel, here an empty one.');
    refresh(nil);
    assert(target_drawn(), mode .. ': so does no target.');
    target.empty = 'hide';
    assert(not target_drawn(), 'Fixture: an empty panel set to hide when empty isn\'t drawn.');
    -- Samples and edit mode show it, as they do a panel its When to show hides.
    refresh(SELF);
    assert(not target_drawn());
    assert(target_drawn({ editing = true }), mode .. ': edit mode shows it, so it can be placed.');
    settings.preview = true;
    assert(target_drawn(), mode .. ': samples show it.');
    settings.preview = false;
    assert(not target_drawn(), mode .. ': and it hides again after them.');
    -- The panel's own switch still decides first.
    target.hide_self, target.enabled = false, false;
    assert(not target_drawn(), 'Fixture: a panel that is off isn\'t drawn.');
    target.enabled = true;
    assert(target_drawn());
end

-- The page: the tick is on Target timers' Show tab alone, a click is one Undo step, and a line says when it hides.
local controls, changes = {}, {};
local checkbox = imgui.Checkbox;
imgui.Checkbox = function(label, ...) controls[label] = (controls[label] or 0) + 1; return checkbox(label, ...); end;
imgui.BeginCombo = function() return false; end;
local callbacks = { editor_changed = function() end, save = function() return true; end,
    changed = function(phase, label) changes[#changes + 1] = { phase = phase, label = label }; end };
local TICK, LINE = 'Hide while I target myself##frame', 'Hidden now, because you\'re targeting yourself.';
local function page(panel, click)
    settings.window.tab = 'Display';
    controls, changes, said, MOCK.clicks = {}, {}, {}, {};
    panels.open(panel, 'show');
    if click then MOCK.clicks[click] = true; end
    window.draw(settings, view, callbacks);
    assert(not click or not MOCK.clicks[click], 'Fixture: the tick was there to click.');
    assert(#MOCK.font_stack == 0);
end
target.hide_self = false;
refresh(SELF);
for _, id in ipairs({ 'self_buffs', 'self_debuffs', 'party', 'watch', 'ability_recasts' }) do
    settings.panels[id].enabled = true;
    page(id);
    assert(controls[TICK] == nil and not said[LINE], id .. ' has no such tick.');
end
page('target');
assert(controls[TICK] == 1 and not said[LINE], 'Target timers has the tick once, and no line while it is off.');
local expected = custom.history_value(settings);
expected.panels.target.hide_self = true;
page('target', TICK);
assert(equal(custom.history_value(settings), expected), 'A click turns it on and changes nothing else.');
assert(#changes == 2 and changes[1].phase == 'before' and changes[2].phase == 'after', 'The click is one Undo step.');
page('target');
assert(said[LINE], 'While it hides the panel, the page says so.');
for _, id in ipairs({ 'self_buffs', 'self_debuffs', 'party', 'watch', 'ability_recasts' }) do
    page(id);
    assert(controls[TICK] == nil and not said[LINE], id .. ' doesn\'t say it, as it isn\'t the hidden panel.');
end
refresh(OTHER);
page('target');
assert(controls[TICK] == 1 and not said[LINE], 'With another target the line goes.');
refresh(SELF);
expected.panels.target.hide_self = false;
page('target', TICK);
assert(equal(custom.history_value(settings), expected) and #changes == 2, 'A second click turns it off again.');
page('target');
assert(not said[LINE]);

-- /vg set reaches it, an export of the display carries it, and a reset of the panel or of everything puts it back.
local set = assert(custom.set(settings, 'panels.target.hide_self', 'true'));
assert(set.panels.target.hide_self == true and target.hide_self == false, '/vg set turns it on.');
assert(not custom.set(settings, 'panels.self_buffs.hide_self', 'true'), 'No other panel takes it.');
local share = require('core.share');
local read = assert(share.read(assert(share.export(set, 'element', 'target'))));
assert(read.kind == 'element' and read.element == 'target' and read.data.hide_self == true, 'An export of Target timers holds it.');
assert(custom.reset(copy(set), 'all').panels.target.hide_self == false, 'Resetting everything turns it off.');
local one = copy(set);
custom.reset(one, 'target');
assert(one.panels.target.hide_self == false, 'So does resetting Target timers.');
-- A starter profile leaves it as you set it, like your other hide rules, and it is no part of what a starter is.
local starters = require('core.starters');
for _, entry in ipairs(starters.list) do
    local on, off = assert(starters.apply(set, entry.id)), assert(starters.apply(settings, entry.id));
    assert(on.panels.target.hide_self == true and off.panels.target.hide_self == false, entry.name .. ' leaves it as it was.');
    assert(starters.matching(on) == entry.id and starters.matching(off) == entry.id, entry.name .. ' is still that starter with it on.');
end
return 'Target timers can stay away while your target is you';
