-- The pickers offer only what can exist on Phoenix, and a save that names something else isn't stranded: an effect or
-- spell they don't offer still shows, under the game's name, in every list and rule that names it, and can be taken out
-- there. Each is driven through the real settings window. A fresh save offers none of it. The Timer durations picker
-- has no Helix or Waltz; a saved override for one keeps its line and goes on working.
local store = require('core.store');
local SNAP = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(SNAP); end };
package.loaded['core.observer'] = { read = function() return {}; end, wear_off = 'Observed wearoff' };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, status = function() return { active = false }; end };
local imgui = require('imgui');
local defaults = require('ui.defaults');
local durations = require('core.durations');
local filters = require('core.effect_filters');
local panels = require('ui.panel_frame');
local page = require('ui.overhead_settings');

local GONE, NAME = 280, 'Enstone II';
local spells = { [57] = 'Haste', [278] = 'Geohelix', [285] = 'Luminohelix' };
local abilities = { [16] = 'Mighty Strikes', [190] = 'Curing Waltz', [195] = 'Divine Waltz' };
AshitaCore.GetResourceManager = function() return {
    GetString = function(_, _, id) return ({ [GONE] = NAME, [279] = 'Enstone' })[id]; end,
    GetSpellById = function(_, id) return { Name = { spells[id] } }; end,
    GetAbilityById = function(_, id) return { Name = { abilities[id - 0x200] } }; end,
}; end;
local app = dofile(ADDON_DIR .. '/vantage.lua');
local window = require('ui.settings_window');
MOCK.fire('load'); app.refresh(0);

local combo, typed, previews = nil, nil, {};
imgui.BeginCombo = function(label, preview) previews[label] = preview; return label == combo; end;
local input, input_with_hint = imgui.InputText, imgui.InputTextWithHint;
local function typing(label, value)
    if typed and typed[1] == label then value[1], typed = typed[2], nil; return true; end
    return false;
end;
imgui.InputText = function(label, value, ...) if typing(label, value) then return true; end return input(label, value, ...); end;
imgui.InputTextWithHint = function(label, hint, value, ...) if typing(label, value) then return true; end return input_with_hint(label, hint, value, ...); end;
local view = { rows = {}, context = { valid = true, job = 3, entities = {} } };
local function frame(step)
    step = step or {};
    combo, typed, previews, MOCK.imgui_calls = step.combo, step.typed, {}, {};
    if step.click then MOCK.clicks[step.click] = true; end
    window.draw(app.state.settings, view, app.callbacks);
    assert(not step.click or not MOCK.clicks[step.click], 'The control is on the page: ' .. tostring(step.click));
    assert(not typed, 'The box is on the page: ' .. tostring(step.typed and step.typed[1]));
    MOCK.clicks = {};
end;
-- Whether the frame drew a control of this kind with this label.
local function drew(kind, label)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == kind and call[2] == label then return true; end end
    return false;
end;
local function begin(tab, setup, editor)
    local s = defaults.tidy(defaults.make());
    s.window.open, s.window.tab = true, tab;
    page._selection.kind = 'mob';
    if setup then setup(s); end
    app.state.settings = defaults.tidy(s);
    app.state.settings_revision = app.state.settings_revision + 1;
    if editor then panels.open(editor, 'filters'); end
    frame();
    return s;
end;
local CHOICE = NAME .. '##280';

-- A fresh save offers none of it: not in the three filter editors, the panel's list or the alert rule's picker.
begin('Display', nil, 'overhead');
frame({ typed = { '##frame_Find an effect', tostring(GONE) } });
frame({ combo = '##frame_Effect' });
assert(not drew('Selectable', CHOICE), 'Overhead offers no effect that can\'t exist.');
frame({ typed = { '##frame_Find an effect', '' } });
begin('Display', nil, 'party_ui');
frame({ typed = { '##frame_Find an effect', tostring(GONE) } });
frame({ combo = '##frame_Effect' });
assert(not drew('Selectable', CHOICE), 'The party list offers no effect that can\'t exist.');
frame({ typed = { '##frame_Find an effect', '' } });
begin('Display', nil, 'pet');
frame({ typed = { '##frame_Find an effect', tostring(GONE) } });
frame({ combo = '##frame_Effect' });
assert(not drew('Selectable', CHOICE), 'The pet display offers no effect that can\'t exist.');
frame({ typed = { '##frame_Find an effect', '' } });
panels.open('self_buffs', 'filters');
begin('Display');
frame({ typed = { '##frame_Find an effect', tostring(GONE) } });
frame({ combo = '##frame_Effect' });
assert(not drew('Selectable', CHOICE), 'A panel offers no effect that can\'t exist.');
frame({ typed = { '##frame_Find an effect', '' } });

-- A rule's job picker ends at PUP.
local function hide_rule(s, effect)
    local rule = filters.rule();
    rule.effect, rule.enabled = effect, false;
    s.effect_filters.rules = { rule };
    return rule;
end;
panels.open('hidden', 'show');
begin('Display', function(s) hide_rule(s, 33); end);
frame({ combo = '##frame_Main job_rule' });
assert(drew('Selectable', 'WAR##1') and drew('Selectable', 'PUP##18') and not drew('Selectable', 'DNC##19') and not drew('Selectable', 'RUN##22'),
    'A hide rule offers the 18 jobs.');

-- Overhead icons: the type's lists.
local s = begin('Display', function(s) s.overhead.types.mob.exclude, s.overhead.types.mob.include = { GONE }, { GONE }; end, 'overhead');
frame({ typed = { '##frame_Find an effect', tostring(GONE) } });
frame({ combo = '##frame_Effect' });
assert(drew('Selectable', CHOICE), 'A saved overhead effect is in its picker, under the game\'s name.');
frame({ click = 'Hide here##frame' });
frame({ click = 'Show only##frame' });
local mob = app.state.settings.overhead.types.mob;
assert(#mob.exclude == 0 and #mob.include == 0, 'A saved overhead effect can be taken out of both lists.');
frame({ typed = { '##frame_Find an effect', '' } });

-- The walk over the settings waits for a change, so a frame with none finds nothing new, and the next change does.
begin('Display', nil, 'overhead');
frame();
app.state.settings.overhead.types.mob.exclude = { 279 };
frame({ typed = { '##frame_Find an effect', '279' } });
frame({ combo = '##frame_Effect' });
assert(not drew('Selectable', 'Enstone##279'), 'Frames with no change don\'t walk the settings.');
app.state.settings_revision = app.state.settings_revision + 1;
frame({ combo = '##frame_Effect' });
assert(drew('Selectable', 'Enstone##279'), 'A change brings in what it saved.');
app.state.settings.overhead.types.mob.exclude = {};
frame({ typed = { '##frame_Find an effect', '' } });

-- The party list's lists.
s = begin('Display', function(s)
    local e = s.party_ui.effects;
    e.include, e.exclude, e.pinned = { GONE }, { GONE }, { GONE };
end, 'party_ui');
frame({ typed = { '##frame_Find an effect', tostring(GONE) } });
frame({ combo = '##frame_Effect' });
assert(drew('Selectable', CHOICE), 'A saved party effect is in its picker, under the game\'s name.');
for _, label in ipairs({ 'Show only##frame', 'Hide here##frame', 'Pin first##frame' }) do frame({ click = label }); end
frame({ click = 'Reset selected effect##frame' });
local e = app.state.settings.party_ui.effects;
assert(#e.include == 0 and #e.exclude == 0 and #e.pinned == 0, 'A saved party effect can be taken out of every list.');
frame({ typed = { '##frame_Find an effect', '' } });

-- The pet display's lists.
s = begin('Display', function(s) s.pet.exclude, s.pet.include = { GONE }, { GONE }; end, 'pet');
frame({ typed = { '##frame_Find an effect', tostring(GONE) } });
frame({ combo = '##frame_Effect' });
assert(drew('Selectable', CHOICE), 'A saved pet effect is in its picker, under the game\'s name.');
frame({ click = 'Hide here##frame' });
frame({ click = 'Show only##frame' });
assert(#app.state.settings.pet.exclude == 0 and #app.state.settings.pet.include == 0, 'A saved pet effect can be taken out of both lists.');
frame({ typed = { '##frame_Find an effect', '' } });

-- A timer panel: its lists, its label and color and My order.
panels.open('self_buffs', 'filters');
s = begin('Display', function(s)
    local p = s.panels.self_buffs;
    p.include[GONE], p.exclude[GONE], p.pinned[GONE], p.labels[GONE], p.effect_colors[GONE], p.order = true, true, true, 'Mine', { 1, 0, 0, 1 }, { GONE };
end);
frame({ typed = { '##frame_Find an effect', tostring(GONE) } });
frame({ combo = '##frame_Effect' });
assert(drew('Selectable', CHOICE), 'A saved panel effect is in the panel\'s list, under the game\'s name.');
assert(drew('TextUnformatted', NAME) and drew('TextUnformatted', NAME .. ' as Mine'), 'The lists name a saved effect.');
frame({ typed = { '##frame_Find an effect', '' } });
for _ = 1, 6 do frame({ click = 'Remove##effect' }); end;
local p = app.state.settings.panels.self_buffs;
assert(next(p.include) == nil and next(p.exclude) == nil and next(p.pinned) == nil and next(p.labels) == nil and next(p.effect_colors) == nil
    and #p.order == 0, 'A saved panel effect can be taken out of each of them.');

-- A shared hide rule.
panels.open('hidden', 'show');
s = begin('Display', function(s) hide_rule(s, GONE); end);
assert(previews['##frame_Rule'] == '[Off] ' .. NAME and previews['##frame_Effect_rule'] == NAME, 'A shared rule names a saved effect.');
frame({ click = 'Remove##frame_rule' });
assert(#app.state.settings.effect_filters.rules == 0, 'A shared rule with a saved effect can be removed.');
s = begin('Display', function(s) hide_rule(s, GONE).enabled = true; end);
assert(drew('TextUnformatted', NAME), 'The list names a saved effect.');
frame({ click = 'Remove##effect' });
assert(#app.state.settings.effect_filters.rules == 0, 'A saved effect can be taken off the list.');

-- An alert rule.
panels.open('notices', 'show');
s = begin('Display');
frame({ click = 'New alert##frame' });
local rule = app.state.settings.alerts.rules[#app.state.settings.alerts.rules];
rule.effect = GONE;
frame();
assert(previews['##Effect'] == NAME, 'An alert rule names a saved effect.');
frame({ combo = '##Effect' });
assert(drew('Selectable', NAME .. '##effect_280'), 'An alert rule\'s picker offers a saved effect.');
assert(not drew('Checkbox', 'DNC##frame_alert') and not drew('Checkbox', 'RUN##frame_alert'), 'An alert rule offers no job past PUP.');
frame({ combo = '##Effect', click = 'All effects##all' });
assert(rule.effect == 0, 'An alert rule can leave a saved effect.');

-- Timer durations: no Helix and no Waltz to pick, and a saved override for one stays.
local function override(kind, id)
    local saved = durations.override();
    saved.kind, saved.id, saved.seconds = kind, id, 42;
    return saved;
end;
s = begin('Durations');
frame({ combo = '##Override applies to', click = 'A spell##spell' });
frame({ combo = '##What to override' });
assert(drew('Selectable', 'Haste##57'), 'Fixture: the spell picker lists a spell players have.');
assert(not drew('Selectable', 'Geohelix##278') and not drew('Selectable', 'Luminohelix##285'), 'The spell picker has no Helix.');
assert(not drew('Selectable', 'Spell 1##1'), 'A spell the client has no name for isn\'t offered.');
frame({ combo = '##Override applies to', click = 'A job ability##ability' });
frame({ combo = '##What to override' });
assert(drew('Selectable', 'Mighty Strikes##16'), 'Fixture: the ability picker lists an ability players have.');
assert(not drew('Selectable', 'Curing Waltz##190') and not drew('Selectable', 'Divine Waltz##195'), 'The ability picker has no Waltz.');
assert(not drew('Selectable', 'Ability 32##32'), 'An ability the client has no name for isn\'t offered.');
s = begin('Durations', function(s) s.durations.overrides = { override('spell', 278), override('ability', 190), override('effect', GONE) }; end);
-- It still fits what it was saved for.
local saved = app.state.settings.durations.overrides;
assert(durations.match(saved, { action_category = 4, spell = 278, effect = 33 }) == saved[1], 'A saved override for a spell off Phoenix still matches.');
frame({ combo = '##Override to edit' });
for _, label in ipairs({ '1. Geohelix / 42s##1', '2. Curing Waltz / 42s##2', '3. ' .. NAME .. ' / 42s##3' }) do
    assert(drew('Selectable', label), 'A saved override keeps its line: ' .. label);
end;
frame({ click = 'Remove selected override' });
assert(#app.state.settings.durations.overrides == 2, 'A saved override can be removed.');

-- The job link picker ends at PUP, whatever a save holds.
s = begin('Profiles');
frame({ combo = '##linked_job' });
assert(drew('Selectable', 'PUP') and not drew('Selectable', 'DNC'), 'The job link picker offers the 18 jobs.');
s = begin('Profiles', function(s) s.job_profiles[19] = 'Dancer'; end);
frame({ combo = '##linked_job' });
assert(not drew('Selectable', 'DNC') and not drew('Selectable', 'RUN'), 'A job link saved past PUP adds nothing to the picker.');
