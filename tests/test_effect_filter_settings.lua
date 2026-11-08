local defaults, filters = require('ui.defaults'), require('core.effect_filters');
local copy, equal = require('core.store').copy, require('core.customization').equal;
local custom, profiles = require('core.customization'), require('core.profiles');
local fresh = defaults.make();
assert(fresh.effect_filters.enabled and #fresh.effect_filters.rules == 0, 'No effects are hidden by default.');
local plain = copy(fresh); plain.effect_filters = nil;
local restored = defaults.tidy(plain);
assert(equal(restored.effect_filters, filters.make()), 'A save without them gets an empty rule set.');
local source = defaults.make();
source.effect_filters.rules = {
    {enabled=true,effect=253,kind='all',name='',job=0,scope='all'},
    {enabled=true,effect=33,kind='buff',name='  Rowan  ',job=3,scope='alliance1'},
};
source = defaults.tidy(source);
assert(equal(source.effect_filters, filters.tidy(copy(source.effect_filters))));
for _, scope in ipairs({'appearance','layouts','self_buffs','party_ui','effects'}) do
    local settings = copy(source);
    custom.reset(settings, scope);
    assert(equal(settings.effect_filters, source.effect_filters), 'Local reset keeps shared rules: '..scope);
end;
for _, size in ipairs({'minimal','minimal_2x'}) do
    local settings = copy(source);
    assert(require('setup_fixture').apply(settings, { size = size, skin = 'keep' }));
    assert(equal(settings.effect_filters, source.effect_filters));
end;
local saved = profiles.new(MOCK_INSTALL_PATH .. '/config/addons/vantage');
assert(saved:save_new('Effect visibility', source));
local target = defaults.make();
assert(saved:load('Effect visibility', target));
assert(equal(target.effect_filters, source.effect_filters));
assert(equal(profiles.capture(source).effect_filters, source.effect_filters));
assert(profiles.capture_layout(source, 'placement').effect_filters == nil);
assert(equal(profiles.capture_layout(source, 'presentation').presentation.effect_filters, source.effect_filters));
for _, scope in ipairs({'placement','presentation'}) do
    assert(saved:save_layout(source, scope));
    target = defaults.make();
    local local_rules = filters.make(); local rule = filters.rule(); rule.effect = 269;
    local_rules.rules[1] = rule; target.effect_filters = copy(local_rules);
    assert(saved:load_layout(target, scope));
    assert(equal(target.effect_filters, scope == 'placement' and local_rules or source.effect_filters));
end;
target = copy(source);
target = assert(custom.set(target, 'effect_filters.enabled', 'false'));
assert(target.effect_filters.enabled == false and #target.effect_filters.rules == 2);
assert(custom.reset(target, 'effect_filters'));
assert(equal(target.effect_filters, filters.make()));

-- Hidden everywhere, as a player uses it.
local h = require('panel_fixture')();
local app = h.app;
local catalog = {{id=0,name='Ko'},{id=33,name='Haste'},{id=253,name='Signet'},{id=269,name='Level Sync'}};
h.window.main_helpers.catalog = function() return catalog; end;
h.imgui.CollapsingHeader = function() return true; end;
local FIND, PICK, HIDE, ADD = '##frame_Find an effect', '##frame_Effect', 'Hide it everywhere##frame', 'Add a rule##frame';
local function rules() return h.s.effect_filters.rules; end;
local function steps() return #app.state.history; end;
local function value() return custom.history_value(h.s); end;
h.fresh(function(s) s.panels.self_buffs.include = {[33]=true}; s.party_ui.effects.exclude = {6}; end);
local blank = value();
h.on('hidden', 'show');
local original = copy(h.s);
assert(equal(value(), blank) and steps() == 0, 'Opening Hidden everywhere does not mutate settings.');

-- With nothing typed or picked, the picker reads Choose an effect, there is nothing to hide yet, and a new rule starts on
-- Any effect, not on an effect the picker doesn't show.
assert(h.previews[PICK] == 'Choose an effect', 'The empty picker says so: ' .. tostring(h.previews[PICK]));
h.draw(HIDE);
assert(#rules() == 0 and steps() == 0, 'Hide it everywhere waits for a choice.');
h.draw(ADD);
assert(#rules() == 1 and rules()[1].effect == 0 and not rules()[1].enabled, 'With nothing chosen the new rule starts on Any effect, turned off.');
assert(app.callbacks.undo());
h.draw();
assert(#rules() == 0, 'Fixture: back to no rules.');
app.state.history, app.state.redo = {}, {};
blank = value();

h.type(FIND, 'Ko');
assert(not h.drawn()['Hide it everywhere'] and h.says('No matching effects.'), 'The client KO entry cannot accidentally create an Any effect rule.');
h.type(FIND, 'Signet');
h.pick(PICK, 'Signet##253');
assert(equal(value(), blank) and steps() == 0, 'Effect search and selection are transient.');
assert(h.previews[PICK] == 'Signet', 'A picked effect shows in the picker.');
assert(not h.says('Signet'), 'Fixture: nothing reads Signet until it is on the list.');
h.draw(HIDE);
assert(#rules() == 1 and rules()[1].effect == 253 and steps() == 1);
h.draw();
assert(h.says('Signet') and h.called('Button', 'Remove##effect'), 'The list shows Signet with its Remove.');
assert(app.callbacks.undo() and equal(custom.history_value(app.state.settings), blank), 'Quick hiding is one undoable change.');
assert(app.callbacks.redo());
h.draw();
h.draw(HIDE);
assert(#rules() == 1 and steps() == 1, 'Quick hides do not duplicate an existing rule.');
h.type(FIND, 'Level Sync');
h.pick(PICK, 'Level Sync##269');
h.draw(HIDE);
assert(#rules() == 2 and rules()[2].effect == 269, 'Level Sync is hidden the way any effect is.');
h.draw();
rules()[2].enabled = false;
h.bump(); h.draw();
h.draw(HIDE);
assert(#rules() == 2 and rules()[2].enabled, 'Quick hide re-enables its existing rule.');
h.type(FIND, 'Signet');
h.pick(PICK, 'Signet##253');

-- The fold: a new rule waits for its settings, and starts on the effect picked above.
h.draw(ADD);
h.draw();
assert(#rules() == 3 and not rules()[3].enabled, 'A new conditional rule waits for configuration before it can hide effects.');
assert(rules()[3].effect == 253, 'The next rule starts on the picked effect.');
h.pick('##frame_Effect_rule', 'Any effect##0');
h.pick('##frame_Buffs or debuffs', 'Debuffs##debuff');
h.pick('##frame_Who', 'Alliance 2##alliance2');
h.type('##frame_Player name', 'Fennel');
h.pick('##frame_Main job_rule', 'WHM##3');
h.draw('Use this rule##frame');
local conditional = rules()[3];
assert(conditional.effect == 0 and conditional.kind == 'debuff' and conditional.scope == 'alliance2'
    and conditional.name == 'Fennel' and conditional.job == 3 and conditional.enabled);
rules()[2].enabled = false;
h.bump(); h.draw();
local before, count = value(), steps();
h.pick('##frame_Rule', '[Off] Level Sync##2');
h.type('##frame_Find an effect_rule', 'Level Sync');
assert(equal(value(), before) and steps() == count, 'Rule selection and catalog searching are transient.');
assert(h.previews['##frame_Effect_rule'] == 'Level Sync', 'The picked rule shows in the fold.');
h.type('##frame_Find an effect_rule', '');
rules()[2].enabled = true;
h.bump(); h.draw();

h.draw('Pause this list##frame');
assert(not h.s.effect_filters.enabled and #rules() == 3);
h.draw();
assert(h.says('This list is paused') and not h.called('Button', 'Pause this list##frame'), 'A paused list says so, and offers the way back.');
h.type(FIND, 'Haste');
h.pick(PICK, 'Haste##33');
h.draw(HIDE);
assert(#rules() == 4 and not h.s.effect_filters.enabled, 'Adding rules does not override a deliberate pause.');
h.draw('Use it again##frame');
assert(h.s.effect_filters.enabled, 'Use it again puts the list back to work.');
h.draw();
h.draw('Remove##frame_rule');
assert(#rules() == 3 and rules()[3].effect == 33, 'Remove takes the rule in the fold.');
h.draw();
h.draw('Remove##effect');
assert(#rules() == 2 and rules()[1].effect == 269, 'Remove takes that effect off the list.');
h.draw();
before = value();
h.draw('Clear the list##frame');
assert(#rules() == 0);
assert(app.callbacks.undo() and equal(custom.history_value(app.state.settings), before), 'Clearing shared rules is undoable.');
assert(app.callbacks.redo());
h.draw();
assert(not h.called('Button', 'Clear the list##frame'), 'An empty list has nothing to clear.');
assert(equal(h.s.panels, original.panels) and equal(h.s.party_ui, original.party_ui)
    and equal(h.s.alerts, original.alerts), 'Shared editing preserves every local filter, lock and alert.');

-- The rule cap is shared by quick and conditional actions.
h.fresh(function(s) for index = 1, 128 do local rule = filters.rule(); rule.effect = 33; s.effect_filters.rules[index] = rule; end; end);
h.on('hidden', 'show');
h.type(FIND, 'Signet');
h.pick(PICK, 'Signet##253');
h.draw(HIDE); h.draw(ADD);
assert(#rules() == 128 and steps() == 0);
assert(h.says('Remove a rule before adding another.'), 'A full list says what to do.');
assert(#MOCK.commands == 0);

-- Shared status rules have the one place, Hidden everywhere, and no other panel offers them.
for _, query in ipairs({'Hide Signet everywhere','Affected player name','Affected main job'}) do
    local found = {};
    for _, result in ipairs(h.window.search(query)) do if result.tab == 'Display' and result.place then found[result.panel] = true; end; end;
    assert(found.hidden and next(found, 'hidden') == nil and next(found) == 'hidden', 'Shared status rules have one searchable place: '..query);
end;

-- The rule picked in the fold stays picked when the list above it changes, and when Undo puts copies in place.
h.fresh(function(s)
    local function rule(effect, name)
        local made = filters.rule();
        made.effect, made.name = effect, name;
        return made;
    end;
    s.effect_filters.rules = { rule(253, ''), rule(33, ''), rule(33, 'Rowan'), rule(269, 'Fennel') };
end);
h.on('hidden', 'show');
h.pick('##frame_Rule', 'Level Sync / Fennel##4');
assert(h.previews['##frame_Rule'] == 'Level Sync / Fennel', 'Fixture: Fennel\'s rule is picked.');
h.draw('Remove##effect');
h.draw();
assert(#rules() == 3 and rules()[1].effect == 33, 'Fixture: Signet is off the list.');
assert(h.previews['##frame_Rule'] == 'Level Sync / Fennel', 'The same rule stays picked: ' .. tostring(h.previews['##frame_Rule']));
assert(app.callbacks.undo());
h.draw();
assert(#rules() == 4 and h.previews['##frame_Rule'] == 'Level Sync / Fennel', 'Undo leaves it picked too.');
MOCK.fire('unload');
