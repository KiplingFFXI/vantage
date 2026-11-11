local durations = require('core.durations');
local effect_editor = require('ui.effect_settings');
-- The Timer durations page: duration overrides and the times learned from your casts (settings.durations).
local page = {};
-- What the pickers hold. rule is the override picked to edit, and place where it was last seen in the list. None of it is
-- saved.
local pick = { kind = 'spell', query = '', name = '', place = 1 };
-- What the override list calls each rule, and the learned lines: made again when the settings change. Without a revision
-- to go by, each draw makes them.
local listed, learned = {}, {};
local kind_labels = { spell = 'A spell', ability = 'A job ability', effect = 'An effect' };
local mode_labels = { fixed = 'A fixed time', add = 'Add or take away seconds', percent = 'A percent of the estimate',
    count_up = 'Count up from when it landed' };
local learned_kinds = { skill = 'A monster skill', pact = 'A pet skill' };
-- The game has no name for some, and a number says nothing to a player.
local no_name = { Spell = 'A spell with no name', Ability = 'An ability with no name' };
local function plain_name(name) return no_name[name:match('^(%a+) %d+$')] or name; end

-- pcall(index_of, object, key) guards a lookup without making a closure for it.
local function index_of(object, key) return object[key]; end
local function field(object, key)
    if object == nil then return nil; end
    local ok, value = pcall(index_of, object, key);
    if ok then return value; end
end
local function resource_name(resource)
    local value = field(field(resource, 'Name'), 1);
    if type(value) ~= 'string' then return nil; end
    value = value:gsub('%c', ''):match('^%s*(.-)%s*$');
    if value ~= '' and value ~= '.' then return value:sub(1, 60); end
end
local function resource(kind, id)
    local ok, resources = pcall(function() return AshitaCore:GetResourceManager(); end);
    if not ok or resources == nil then return nil; end
    -- A job ability's resource id is its action id plus 0x200, as ui/recast_icons.lua reads it.
    local method = kind == 'spell' and 'GetSpellById' or 'GetAbilityById';
    local fn = field(resources, method);
    if type(fn) ~= 'function' then return nil; end
    local found, value = pcall(fn, resources, kind == 'spell' and id or id + 0x200);
    if found then return value; end
end

-- The name of a spell, ability or effect, from the client.
local names = { spell = {}, ability = {} };
local function action_name(kind, id, catalog)
    if kind == 'effect' then
        for _, entry in ipairs(catalog or {}) do if entry.id == id then return entry.name; end end
        return require('core.catalog').get(id).name;
    end
    if names[kind] and names[kind][id] == nil then names[kind][id] = resource_name(resource(kind, id)) or false; end
    return names[kind] and names[kind][id] or (kind == 'spell' and 'Spell ' or kind == 'ability' and 'Ability ' or 'Action ') .. id;
end

-- The spells and job abilities players can have on Phoenix (data/actions.lua) that the client names, read once. With
-- no names to read, all of them.
local catalogs = {};
local function action_catalog(kind)
    if catalogs[kind] then return catalogs[kind]; end
    local list, data = {}, require('data.actions');
    local ids = kind == 'spell' and data.spells or data.abilities;
    for _, id in ipairs(ids) do
        local name = action_name(kind, id);
        if not name:match('^Spell %d+$') and not name:match('^Ability %d+$') then list[#list + 1] = { id = id, name = name }; end
    end
    if #list == 0 then
        for _, id in ipairs(ids) do list[#list + 1] = { id = id, name = action_name(kind, id) }; end
    end
    table.sort(list, function(a, b)
        local first, second = a.name:lower(), b.name:lower();
        return first == second and a.id < b.id or first < second;
    end);
    catalogs[kind] = list;
    return list;
end

local function rule_label(index, rule, catalog)
    local value = rule.mode == 'fixed' and rule.seconds .. 's'
        or rule.mode == 'add' and (rule.offset >= 0 and 'add ' .. rule.offset or 'take away ' .. -rule.offset) .. 's'
        or rule.mode == 'percent' and rule.percent .. '%' or 'count up';
    local label = string.format('%d. %s%s', index, rule.enabled and '' or '[Off] ',
        rule.id == 0 and 'Nothing chosen' or plain_name(action_name(rule.kind, rule.id, catalog)));
    if rule.name ~= '' then label = label .. ' / ' .. rule.name; end
    return label .. ' / ' .. value;
end

-- One learned time as the page lists it: what made it, the effect, the mob, the time and how many casts it is from.
local function learned_line(key, entry)
    local kind, id, effect = key:match('^(%l+):(%d+):(%d+):');
    id, effect = tonumber(id), tonumber(effect);
    local what = (kind == 'spell' or kind == 'ability') and plain_name(action_name(kind, id)) .. ': '
        or learned_kinds[kind] and learned_kinds[kind] .. ': ' or '';
    local seconds = durations.median(entry.samples) or 0;
    return string.format('%s%s%s, %ds from %d %s', what, plain_name(require('core.catalog').get(effect).name),
        entry.unit ~= '' and ' on ' .. entry.unit or '', math.floor(seconds + 0.5), #entry.samples, #entry.samples == 1 and 'cast' or 'casts');
end

-- The place of the override picked to edit, so a change to the list leaves the same rule picked. Undo and a load put
-- copies in place of the rules. Then it is the copy like it, the one at its old place first, or else whichever rule took
-- that place.
local function picked_place(overrides)
    if #overrides == 0 then return nil; end
    if pick.rule == nil or overrides[pick.place] ~= pick.rule then
        local found;
        if pick.rule then
            for place, rule in ipairs(overrides) do if rule == pick.rule then found = place; break; end end
            local equal = require('core.customization').equal;
            if not found and overrides[pick.place] and equal(overrides[pick.place], pick.rule) then found = pick.place; end
            if not found then
                for place, rule in ipairs(overrides) do if equal(rule, pick.rule) then found = place; break; end end
            end
        end
        pick.place = found or math.max(1, math.min(#overrides, pick.place or 1));
        pick.rule = overrides[pick.place];
    end
    return pick.place;
end

-- What the buttons act on, set as each draw starts, so a draw makes no function for them.
local now = {};
local function edit(fn, label) now.c.changed(fn, true, label); end;

local function add_override()
    local c, overrides = now.c, now.overrides;
    if not pick.effect then return; end;
    if #overrides >= 128 then if c.note then c.note('Remove a duration override before adding another.'); end; return; end;
    edit(function()
        local rule = durations.override();
        rule.kind, rule.id = pick.kind, pick.effect;
        overrides[#overrides + 1] = rule;
    end, 'Add duration override');
    pick.rule, pick.place = overrides[#overrides], #overrides;
end;

local function use_target_name()
    local rule, target = now.rule, now.target;
    edit(function() rule.name = durations.unit_name(target.name); end, 'Only on a mob or player named');
end;

local function remove_override()
    local overrides = now.overrides;
    edit(function() table.remove(overrides, pick.place); end, 'Remove duration override');
    -- The one that takes its place is picked next.
    pick.rule = nil;
end;

local function clear_overrides()
    local config = now.config;
    edit(function() config.overrides = {}; end, 'Clear duration overrides');
    pick.rule, pick.place = nil, 1;
end;

local function clear_learned()
    local config = now.config;
    edit(function() config.learned = {}; end, durations.CLEAR);
end;

function page.draw(imgui, settings, view, callbacks, c)
    local config = settings.durations;
    local overrides = config.overrides;
    now.c, now.config, now.overrides = c, config, overrides;
    imgui.TextWrapped('How long Vantage counts the effects it estimates: those on mobs, party members and other players. Your own effects follow the game\'s timers.');

    if c.section('Duration overrides', 'Your own time for a spell, ability or effect, on every mob and player or one by name.', true) then
        imgui.TextWrapped('A fixed time goes before a learned time, and adding, taking away or a percent change it. One for a spell or ability goes before one for its effect, and one with a name before one without.');
        (c.choice or c.combo)('Override applies to', pick, 'kind', durations.kinds, kind_labels, 'Spells and job abilities are matched by what was used, effects by what landed from anything.');
        local revision = c.catalog_revision and c.catalog_revision();
        local statuses = require('ui.filter_settings').status_catalog(c.catalog(), revision);
        local catalog = pick.kind == 'effect' and statuses or action_catalog(pick.kind);
        (c.query or c.text)('Find what to override', pick, 'query', 'Search by name. Searching changes nothing.', 60);
        -- The effects go by the window's catalog revision. A spell or ability list never changes once it's made.
        effect_editor.selection(catalog, pick, pick.kind == 'effect' and revision or 0);
        if pick.effect then
            (c.choice or c.combo)('What to override', pick, 'effect', pick.ids, pick.labels);
        else imgui.TextWrapped('Nothing matches. Try another name.'); end;
        c.button('Add duration override', add_override, 'Adds a fixed time of 60 seconds for the pick above. Change it below.');
        if #overrides == 0 then
            imgui.TextWrapped('No duration overrides yet.');
        else
            local revision = callbacks and callbacks.settings_revision and callbacks.settings_revision();
            if listed.settings ~= settings or revision == nil or listed.revision ~= revision or listed.overrides ~= overrides
                or listed.statuses ~= statuses then
                listed.ids, listed.labels = {}, {};
                -- Each rule is named by its own kind, whatever the pick above is on.
                for index, rule in ipairs(overrides) do listed.ids[index], listed.labels[index] = index, rule_label(index, rule, statuses); end;
                listed.settings, listed.revision, listed.overrides, listed.statuses = settings, revision, overrides, statuses;
            end;
            picked_place(overrides);
            (c.choice or c.combo)('Override to edit', pick, 'place', listed.ids, listed.labels, 'Picking one changes nothing.');
            -- Picking one moves the place, and the rule there is the one picked.
            local rule = overrides[pick.place];
            pick.rule = rule;
            c.check('Override enabled', rule, 'enabled');
            c.combo('Change the time to', rule, 'mode', durations.modes, mode_labels,
                'Count up shows the time since it landed instead of the time left.');
            if rule.mode == 'fixed' then
                c.number('Fixed time', rule, 'seconds', 1, 86400, 'Seconds from when it lands.', true, nil, { slider = 3600 });
            elseif rule.mode == 'add' then
                c.number('Seconds to add or take away', rule, 'offset', -3600, 3600, 'Added to the estimate. An effect with no estimate stays as it is. A time of its own is never under 1 second.', true, nil, { slider = 600, slider_low = -600 });
            elseif rule.mode == 'percent' then
                c.number('Percent of the estimate', rule, 'percent', 1, 1000, '100 is the estimate as it is. An effect with no estimate stays as it is.', true, nil, { slider = 300 });
            end;
            c.text('Only on a mob or player named', rule, 'name', 'The exact name as the game shows it. Leave it empty for every mob and player.', 40);
            local target = view and view.context and view.context.target;
            if target and type(target.name) == 'string' and target.name ~= '' then
                now.rule, now.target = rule, target;
                c.button('Use my target\'s name', use_target_name);
            end;
            c.button('Remove selected override', remove_override, 'Remove only this override. Undo restores it.');
            c.button('Clear duration overrides', clear_overrides, 'Remove every duration override. Undo restores them.');
        end;
    end;

    if c.section('Learned durations', 'Times from your own casts, from when Vantage saw them land to their wear-off.', true) then
        c.check('Learn from my casts', config, 'learn', 'Keeps the time from landing to wear-off of your own effects on others, by spell and by mob name, and counts your casts from their middle one once there are enough. A sleep broken by a hit or beside a damage tick, a removal and a death teach nothing.');
        if config.learn then c.number('Casts before a learned time is used', config, 'learn_samples', 1, 9, 'Up to nine times are kept for each spell on each mob name, the newest ones.', true); end;
        local revision = callbacks and callbacks.settings_revision and callbacks.settings_revision();
        if learned.settings ~= settings or revision == nil or learned.revision ~= revision or learned.from ~= config.learned then
            local keys = {};
            for key in pairs(config.learned) do keys[#keys + 1] = key; end;
            table.sort(keys);
            learned.lines = {};
            for index, key in ipairs(keys) do learned.lines[index] = learned_line(key, config.learned[key]); end;
            learned.count = #keys == 0 and 'Nothing learned yet.' or string.format('%d learned time%s:', #keys, #keys == 1 and '' or 's');
            learned.settings, learned.revision, learned.from = settings, revision, config.learned;
        end;
        local count = #learned.lines;
        imgui.TextWrapped(learned.count);
        for _, line in ipairs(learned.lines) do imgui.TextWrapped(line); end;
        if count > 0 and not config.learn then imgui.TextWrapped('With Learn from my casts off, these are kept but not used.'); end;
        if count > 0 then c.button('Clear learned durations', clear_learned, 'Forget every learned time. Undo brings them back.'); end;
    end;
end;

-- The override picked, if there are any.
function page.override(settings)
    local overrides = settings.durations.overrides;
    local place = picked_place(overrides);
    return place and overrides[place];
end;

if VANTAGE_TEST_MODE then
    page._pick = pick;
end

return page;
