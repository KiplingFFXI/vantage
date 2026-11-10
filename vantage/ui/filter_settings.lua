-- Hidden everywhere (settings.effect_filters): the effects hidden on every display and the hide rules for some players or
-- jobs. It is no display on the screen, so it is a plain page of the panel frame, with no tabs.
local filters = require('core.effect_filters');
local effects = require('ui.effect_settings');
local frame = require('ui.panel_frame');
local status = require('ui.status_panel');
local page = {};
local ctx = frame.ctx;
local catalog_source, catalog_snapshot, catalog_entries, catalog_revision, catalog_count;
local jobs = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM',
    'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP' };
local job_ids, job_labels = { 0 }, { [0] = 'Any main job' };
for id, name in ipairs(jobs) do
    job_labels[id] = name;
    job_ids[#job_ids + 1] = id;
end;
local scopes = { 'all', 'self', 'party', 'alliance', 'alliance1', 'alliance2', 'enemy', 'other', 'pet' };
local scope_labels = { all = 'Everyone', self = 'Only me', party = 'My party, including me',
    alliance = 'Both alliance parties', alliance1 = 'Alliance 1', alliance2 = 'Alliance 2', enemy = 'Enemies',
    other = 'Other players', pet = 'Pets' };
local kinds = { 'all', 'buff', 'debuff', 'neutral' };
local kind_labels = { all = 'All effect types', buff = 'Buffs', debuff = 'Debuffs', neutral = 'Other effects' };
-- What the two finders hold, and the rule picked in the fold: the rule itself, and its place in the rules when last seen.
-- None of it is saved.
local finder, rule_finder, picks = { query = '' }, { query = '' }, { place = 1 };
-- The picker reads Choose an effect until the player types or picks.
local picker_labels = setmetatable({ [''] = 'Choose an effect' }, { __index = function(_, id) return finder.labels[id]; end });

local global_rule, listed = filters.global_rule, filters.listed;

-- The first rule that hides this effect for everyone.
function page.global_index(rules, effect)
    for position, rule in ipairs(rules) do if global_rule(rule, effect) then return position; end; end;
end;

-- Hides an effect everywhere: turns its rule back on, or adds one. The caller owns Undo.
-- Returns the rule's place, or nil when the list is full.
function page.hide(rules, effect)
    local index = page.global_index(rules, effect);
    if index then rules[index].enabled = true; return index; end;
    if #rules >= 128 then return nil; end;
    local rule = filters.rule();
    rule.effect = effect;
    rules[#rules + 1] = rule;
    return #rules;
end;

-- revision, when given, is the window's catalog revision, which changes whenever the entries do, so they aren't walked
-- each frame to find out. Without one they are compared with what they were.
local function status_catalog(entries, revision)
    local same = catalog_source == entries;
    if same and revision ~= nil then same = catalog_revision == revision and catalog_count == #entries;
    elseif same then same = effects.same_catalog(entries, catalog_snapshot); end;
    if not same then
        catalog_source, catalog_revision, catalog_count = entries, revision, #entries;
        catalog_snapshot, catalog_entries = revision == nil and effects.catalog_snapshot(entries) or nil, {};
        for _, entry in ipairs(entries) do
            -- Zero is Any effect in hide rules, not the client's KO entry.
            if entry.id > 0 and entry.id <= 1023 then catalog_entries[#catalog_entries + 1] = entry; end;
        end;
    end;
    return catalog_entries;
end;
page.status_catalog = status_catalog;

local function rules_of(c) return c.s.effect_filters.rules; end;
local function paused(c) return not c.s.effect_filters.enabled; end;
local function running(c) return c.s.effect_filters.enabled; end;
local function has_rules(c) return #rules_of(c) > 0; end;
local function full(c) return #rules_of(c) >= 128; end;

local function any_listed(c)
    for _, rule in ipairs(rules_of(c)) do
        if listed(rule) then return true; end;
    end;
    return false;
end;

local function found() return finder.effect ~= nil; end;
local function not_found() return finder.effect == nil; end;

-- Nothing is chosen until the player types or picks, so one click can't hide an effect by surprise.
local function ready() return finder.effect ~= nil and (finder.query ~= '' or finder.picked == true); end;

-- A full list adds nothing: its line says so.
local function hide(c, effect)
    local rules = rules_of(ctx);
    local index = page.global_index(rules, effect);
    if not index and #rules >= 128 then return; end;
    if not (index and rules[index].enabled) then
        c.changed(function() page.hide(rules, effect); end, true, 'Hide effect everywhere');
    end;
end;

local function refresh_finder()
    local revision = status.named_revision(ctx);
    effects.selection(status_catalog(status.named(ctx), revision), finder, revision);
end;

local hidden_list = status.list_line('Hidden everywhere', 'Remove takes it off the list, and it shows again.', any_listed, function(c)
    local out = {};
    for position, rule in ipairs(rules_of(c)) do
        if listed(rule) then
            out[#out + 1] = { id = rule.effect, position = position, line = status.plain_name(c.c, rule.effect, 'status'), scope = 'hidden_' .. position };
        end;
    end;
    return out;
end, function(_, entry) table.remove(rules_of(ctx), entry.position); end, { alias = 'Effect visibility Shared hide rules' });

-- The place of the rule picked in the fold, so a change to the list leaves the same rule picked while it is still in the
-- fold. Undo and a load put copies in place of the rules. Then it is the copy like it, the one at its old place first, or
-- else whichever rule took that place, or else the first in the fold.
local function picked_place(c)
    local rules = rules_of(c);
    local chosen, found = rules[picks.place], nil;
    if chosen ~= nil and chosen == picks.rule and not listed(chosen) then return picks.place; end;
    if picks.rule then
        for position, rule in ipairs(rules) do
            if rule == picks.rule and not listed(rule) then found = position; break; end;
        end;
        local equal = require('core.customization').equal;
        if not found and chosen and not listed(chosen) and equal(chosen, picks.rule) then found = picks.place; end;
        if not found then
            for position, rule in ipairs(rules) do
                if not listed(rule) and equal(rule, picks.rule) then found = position; break; end;
            end;
        end;
    end;
    if not found and chosen and not listed(chosen) then found = picks.place; end;
    if not found then
        for position, rule in ipairs(rules) do
            if not listed(rule) then found = position; break; end;
        end;
    end;
    if found then picks.place = found; end;
    picks.rule = found and rules[found];
    return found;
end;

-- What the rows still being drawn read on the frame a change takes the last rule out of the fold. Those rows are gone on
-- the next frame.
local blank_rule = filters.rule();

local function rule_of(c)
    local place = picked_place(c);
    return place and rules_of(c)[place] or blank_rule;
end;

local function rule_open(c) return picked_place(c) ~= nil; end;

-- Enemies and pets have no player name or main job to match.
local playerless = { enemy = true, pet = true };
local function names_players(c) return not playerless[rule_of(c).scope]; end;

-- The effect's name, for a rule that names one.
local effect_names = setmetatable({ [0] = 'Any effect' }, { __index = function(_, id)
    return rule_finder.labels and rule_finder.labels[id] or status.plain_name(ctx.c, id, 'status');
end });

-- The rules in the fold and what each is called, worked out when the settings change.
local rule_memo = { memo = {}, say = function(c)
    local places, names = {}, {};
    for position, rule in ipairs(rules_of(c)) do
        if not listed(rule) then
            local parts = { rule.enabled and '' or '[Off] ', effect_names[rule.effect] };
            if rule.name ~= '' then parts[#parts + 1] = ' / ' .. rule.name; end;
            if rule.job > 0 then parts[#parts + 1] = ' / ' .. job_labels[rule.job]; end;
            if rule.scope ~= 'all' then parts[#parts + 1] = ' / ' .. scope_labels[rule.scope]; end;
            places[#places + 1], names[position] = position, table.concat(parts);
        end;
    end;
    return { places = places, names = names };
end };

local function refresh_rule_finder()
    local revision = status.named_revision(ctx);
    effects.selection(status_catalog(status.named(ctx), revision), rule_finder, revision);
end;

-- Any effect, then what the finder above it found. It is built only while its menu is open.
local function effect_choices()
    local choices = { 0 };
    for _, id in ipairs(rule_finder.ids) do choices[#choices + 1] = id; end;
    return choices;
end;

local function hides_everything(c)
    local rule = rule_of(c);
    return rule ~= blank_rule and rule.effect == 0 and rule.kind == 'all' and rule.scope == 'all' and rule.name:match('^%s*$') ~= nil and rule.job == 0;
end;

local fold_rows = {
    frame.button('Add a rule', 'Adds a rule, turned off, for the effect chosen above, or for Any effect when none is chosen. Choose who it is for, then tick Use this rule.', function(c)
        local rules = rules_of(ctx);
        if #rules >= 128 then return; end;
        local effect = ready() and finder.effect or 0;
        c.changed(function()
            local rule = filters.rule();
            rule.enabled, rule.effect = false, effect;
            rules[#rules + 1] = rule;
        end, true, 'Add hide rule');
        picks.rule, picks.place, rule_finder.query = rules[#rules], #rules, '';
    end, { alias = 'Add conditional hide rule' }),
    frame.group({
        frame.pick('Rule', nil, nil, nil, 'Picking a rule changes nothing.', { transient = true, alias = 'Hide rule to edit',
            read = picked_place,
            write = function(c, value) picks.rule, picks.place = rules_of(c)[value], value; end,
            choices_of = function() return frame.said(rule_memo).places; end,
            names_of = function() return frame.said(rule_memo).names; end }),
        frame.tick('Use this rule', 'enabled', 'Off, it keeps what you set and hides nothing.', { of = rule_of, alias = 'Hide rule enabled' }),
        { kind = 'custom', draw = refresh_rule_finder },
        frame.text('Find an effect', 'query', 'Narrows the Effect list below. Any effect hides every effect of the kind you pick.', { tag = '_rule', find = 'Find a rule effect', of = function() return rule_finder; end, transient = true, alias = 'Find rule effect' }),
        frame.pick('Effect', 'effect', nil, effect_names, 'What this rule hides.', { tag = '_rule', find = 'Rule effect', of = rule_of, choices_of = effect_choices }),
        frame.pick('Buffs or debuffs', 'kind', kinds, kind_labels, 'Narrows the rule to effects of this kind.', { of = rule_of, alias = 'Rule effect type' }),
        frame.pick('Who', 'scope', scopes, scope_labels,
            'My party includes you and its other five slots. Alliance means the other two parties. Enemies, Other players and Pets match those units wherever they show, overhead icons too. This follows the affected member on every display.', {
            of = rule_of, alias = 'Affected group',
            write = function(c, value)
                local rule = rule_of(c);
                rule.scope = value;
                if playerless[value] then rule.name, rule.job = '', 0; end;
            end }),
        frame.text('Player name', 'name', 'Optional exact character name, ignoring case and surrounding spaces. This matches the player with the effect, not its caster. Leave blank for anyone.', {
            of = rule_of, length = 32, alias = 'Affected player name Filter by character recipient name not caster', only = names_players, shown_by = 'Who' }),
        frame.pick('Main job', 'job', job_ids, job_labels, 'Uses the affected player\'s known main job, not your own job or their support job. A player whose job Vantage has not read does not match a job rule.', {
            tag = '_rule', find = 'Rule main job', of = rule_of, alias = 'Affected main job Filter by recipient job WAR WHM not my job subjob', only = names_players, shown_by = 'Who' }),
        frame.note('Everything in this rule must match. Any rule that is on and matches hides the effect. A blank name and Any main job mean anyone.'),
        frame.note('This rule hides every effect while it is on.', { only = hides_everything }),
        frame.button('Remove', 'Removes only this rule. Undo restores it.', function(c)
            local rules, place = rules_of(ctx), picked_place(ctx);
            c.changed(function() table.remove(rules, place); end, true, 'Remove hide rule');
        end, { tag = '_rule', find = 'Remove this rule', alias = 'Remove selected hide rule' }),
    }, { only = rule_open, shown_by = 'Add a rule' }),
};

local show_rows = {
    frame.note('Effects on this list are hidden on the timer panels, party list buffs, overhead icons and Pet. Tracking and alerts go on.'),
    frame.group({
        frame.note('This list is paused, so nothing on it is hidden now.'),
        frame.button('Use it again', 'Puts your hide rules back to work.', function(c)
            local config = ctx.s.effect_filters;
            c.changed(function() config.enabled = true; end, true, 'Use the Hidden everywhere list');
        end, { shown_by = 'Pause this list', alias = 'Enable shared hide rules' }),
    }, { only = paused }),
    { kind = 'custom', draw = refresh_finder },
    frame.text('Find an effect', 'query', 'Type part of a name, then pick from the list below. Nothing is hidden until you click Hide it everywhere.', {
        of = function() return finder; end, transient = true, alias = 'Find an effect to hide Effect visibility' }),
    frame.pick('Effect', 'effect', nil, nil, 'What Hide it everywhere hides.', { of = function() return finder; end, transient = true, only = found, shown_by = 'Find an effect',
        alias = 'Effect to hide', read = function() return ready() and finder.effect or ''; end,
        write = function(_, value) finder.effect, finder.picked = value, true; end,
        names_of = function() return picker_labels; end, choices_of = function() return finder.ids; end }),
    frame.note('No matching effects. Try another name.', { only = not_found }),
    frame.button('Hide it everywhere', 'Adds this effect to the list. Filters on each display stay as they are.', function(c)
        if ready() then hide(c, finder.effect); end;
    end, { only = found, shown_by = 'Find an effect', locks = function() return not ready(); end, alias = 'Hide selected effect everywhere Hide Signet everywhere' }),
    hidden_list,
    frame.note('Remove a rule before adding another.', { only = full }),
    frame.fold('Hide only for some players or jobs', 'Limit a hide rule by the player\'s name, their known main job, or a party or alliance group.', fold_rows, { key = 'Conditional hide rules' }),
    frame.button('Pause this list', 'Nothing on it is hidden until you use it again. The main page says so. Filters on each display go on.', function(c)
        local config = ctx.s.effect_filters;
        c.changed(function() config.enabled = false; end, true, 'Pause the Hidden everywhere list');
    end, { only = running, shown_by = 'Use it again', alias = 'Enable shared hide rules' }),
    frame.button('Clear the list', 'Takes every effect off the list, and every rule under Hide only for some players or jobs. Filters on each display stay as they are. Undo restores them.', function(c)
        local config = ctx.s.effect_filters;
        c.changed(function() config.rules = {}; end, true, 'Clear the Hidden everywhere list');
    end, { only = has_rules, shown_by = 'Find an effect', alias = 'Clear shared hide rules' }),
};

frame.register({ id = 'hidden', name = 'Hidden everywhere', fold_page = 'Filters', plain = true, tabs = { show = show_rows }, header = {} });

return page;
