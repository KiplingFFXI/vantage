local defaults = require('ui.defaults');
local customization = {};

function customization.equal(a, b)
    if type(a) ~= type(b) then return false; end
    if type(a) ~= 'table' then return a == b; end
    for key, value in pairs(a) do if not customization.equal(value, b[key]) then return false; end end
    for key in pairs(b) do if a[key] == nil then return false; end end
    return true;
end

-- What the navigation reset scope resets in settings.window.
local navigation = { 'peek' };
customization.navigation = navigation;

function customization.history_value(settings, include_window_geometry, include_navigation)
    local value = defaults.copy(settings);
    -- Navigating and moving the editor should not bury display changes in Undo. A step that moves the window
    -- keeps its place and size, and the resets that promise Undo keep its navigation.
    local window, kept = value.window or {}, nil;
    if include_window_geometry then kept = { x = window.x, y = window.y, width = window.width, height = window.height }; end
    if include_navigation then
        kept = kept or {};
        for _, key in ipairs(navigation) do kept[key] = window[key]; end
    end
    value.window = kept;
    return value;
end

-- A kept copy remembers the table it was taken from, so putting it back keeps every table in place.
local original = {};

local function mirror(kept, value)
    for key, child in pairs(value) do
        if type(child) == 'table' then
            local node = kept[key];
            if type(node) ~= 'table' or node[original] ~= child then node = { [original] = child }; kept[key] = node; end
            mirror(node, child);
        elseif kept[key] ~= child then kept[key] = child; end
    end
    for key in pairs(kept) do if key ~= original and value[key] == nil then kept[key] = nil; end end
end

-- Keeping the same settings again only walks them and copies what changed, so it makes no garbage
-- while nothing changes.
function customization.keep(kept, settings)
    if type(kept) ~= 'table' or kept[original] ~= settings then kept = { [original] = settings }; end
    mirror(kept, settings);
    return kept;
end

-- Puts kept settings back exactly, in the same tables, and returns the settings table.
function customization.restore(kept)
    local value = kept[original];
    for key in pairs(value) do if kept[key] == nil then value[key] = nil; end end
    for key, child in pairs(kept) do
        if key ~= original then value[key] = type(child) == 'table' and customization.restore(child) or child; end
    end
    return value;
end

local geometry = { 'x', 'y', 'width', 'height_limit', 'auto_width', 'auto_height', 'min_width', 'max_width',
    'stack_direction', 'growth', 'item_width', 'dock_match_width', 'anchor' };

local function panel_looks(settings, fresh)
    for _,id in ipairs(defaults.panel_order) do
        local panel=settings.panels[id];
        for _,key in ipairs({'colors','effect_colors','field_colors','show_fill','show_text','bar_style','fill_direction',
            'row_height','bar_thickness','gradient','warning_enabled','warning_mark',
            'icon_countdown_position','icon_countdown_size','icon_countdown_gap'}) do
            panel[key]=defaults.copy(fresh.panels[id][key]);
        end
    end
    require('ui.shared_look').restore(settings, fresh);
end

-- A party group's spot beside the list or in its own panel.
local group_spot = { 'native_x', 'native_y', 'native_side', 'detached_x', 'detached_y' };

-- Every display's first spot, what it moves with and its lock. Its size, what it shows and how it looks stay.
local function put_back_displays(settings, fresh)
    local elements = require('ui.elements');
    for _, element in ipairs(elements.movable) do
        local id = element.id;
        local config, start = elements.config(settings, id), elements.config(fresh, id);
        if element.strip then
            for _, key in ipairs(group_spot) do config[key] = start[key]; end
        else
            config[element.x], config[element.y], config[element.anchor] = start[element.x], start[element.y], start[element.anchor];
        end
        elements.lock_holder(settings, id)[element.lock] = elements.lock_holder(fresh, id)[element.lock];
    end
end

-- What Undo calls a reset, by what the player knows it as.
local reset_names = { rolls = 'Phantom Roll', pet = 'Pet', alerts = 'Alerts', party_ui = 'Party list buffs', party_cooldowns = 'Party cooldowns', overhead = 'Overhead icons' };

function customization.reset_label(section)
    section = section or 'all';
    if section == 'job_profiles' then return 'Unlink all jobs'; end
    return 'Reset ' .. (reset_names[section] or defaults.panel_names[section] or section:gsub('_', ' '));
end

function customization.reset(settings, section)
    section = section or 'all';
    local fresh = defaults.make();
    if section == 'appearance' or section == 'style' then
        settings.style = fresh.style;
        settings.window_style = fresh.window_style;
        panel_looks(settings, fresh);
    elseif section == 'navigation' then
        for _, key in ipairs(navigation) do settings.window[key] = fresh.window[key]; end
    elseif section == 'panels' or section == 'layouts' then
        for _,id in ipairs(defaults.panel_order) do
            local panel=settings.panels[id];
            for _, key in ipairs(geometry) do panel[key] = fresh.panels[id][key]; end
        end
    elseif section == 'displays' then
        put_back_displays(settings, fresh);
    elseif section == 'effects' then
        for _,id in ipairs(defaults.panel_order) do
            local panel=settings.panels[id];
            for _, key in ipairs({ 'include', 'exclude', 'pinned', 'order', 'labels', 'groups', 'members', 'effect_colors' }) do panel[key] = {}; end
            panel.filter, panel.mine_only = '', false;
        end
        settings.panels.watch.list_debuffed = false;
        settings.panels.party.abilities_only = false;
    elseif section == 'party_ui' then
        settings.party_ui = fresh.party_ui;
    elseif section == 'overhead' then
        settings.overhead = fresh.overhead;
    elseif section == 'recast_tints' or section == 'ready_pulse' or section == 'party_cooldowns' or section == 'rolls' or section == 'pet'
        or section == 'edit_mode' then
        settings[section] = fresh[section];
    elseif section == 'conditions' then
        -- Every display's When to show, and nothing else.
        local elements = require('ui.elements');
        for _, element in ipairs(elements.list) do
            local config, fresh_config = elements.config(settings, element.id), elements.config(fresh, element.id);
            if element.conditions and type(config) == 'table' and fresh_config then config[element.conditions] = fresh_config[element.conditions]; end
        end
    elseif section == 'moves_with' or section == 'layout' then
        -- Every display's anchor: each goes back to its own spot. The layout scope takes the grid too.
        if section == 'layout' then settings.edit_mode = fresh.edit_mode; end
        local elements = require('ui.elements');
        for _, element in ipairs(elements.list) do
            local config, fresh_config = elements.config(settings, element.id), elements.config(fresh, element.id);
            if element.anchor and type(config) == 'table' and fresh_config then config[element.anchor] = fresh_config[element.anchor]; end
        end
    elseif section == 'durations' then
        -- The times learned from your casts aren't settings; Clear learned durations takes them.
        fresh.durations.learned = type(settings.durations) == 'table' and settings.durations.learned or {};
        settings.durations = fresh.durations;
    elseif section == 'preview' then
        settings.preview = fresh.preview;
    elseif section == 'all' then
        fresh.window.open = settings.window.open;
        fresh.job_profiles = settings.job_profiles;
        fresh.watch_ids = settings.watch_ids;
        fresh.durations.learned = type(settings.durations) == 'table' and settings.durations.learned or {};
        return fresh;
    elseif fresh.panels[section] then
        settings.panels[section] = fresh.panels[section];
    elseif ({window=true,window_style=true,job_profiles=true,alerts=true,effect_filters=true,tracking=true,visibility=true,chat_colors=true,diagnostics=true})[section] then
        settings[section] = fresh[section];
        if section == 'window' then settings.window.open = true; end
    else
        return nil, 'That reset scope was not found. Choose appearance, panels, displays, party_ui, overhead, durations, recast_tints, ready_pulse, party_cooldowns, rolls, pet, edit_mode, moves_with, layout, conditions, effects, alerts, window, window_style, visibility, tracking, preview, navigation, chat_colors, job_profiles or all.';
    end
    return settings;
end

local editable = {enabled=true,recast_display=true,style=true,panels=true,party_ui=true,effect_filters=true,visibility=true,tracking=true,alerts=true,
    window=true,window_style=true,preview=true,shared_layout=true,shared_scope=true,
    chat_colors=true,diagnostics=true,overhead=true,durations=true,recast_tints=true,ready_pulse=true,party_cooldowns=true,rolls=true,pet=true,
    edit_mode=true};

-- The table that holds path's setting and its key, or nothing.
local function locate(settings, path)
    if type(path) ~= 'string' or #path > 180 or not path:match('^[%w_%.]+$') or path:find('..', 1, true) then return nil; end
    local parts = {}; for part in path:gmatch('[^.]+') do parts[#parts+1] = tonumber(part) or part; end
    if not editable[parts[1]] then return nil; end
    local parent = settings;
    for index = 1, #parts-1 do parent = type(parent) == 'table' and parent[parts[index]] or nil; end
    local key = parts[#parts];
    if type(parent) ~= 'table' or parent[key] == nil then return nil; end
    return parent, key;
end

function customization.get(settings, path)
    local parent, key = locate(settings, path);
    if not parent then return nil, 'That setting was not found. Use a full path such as style.font_size.'; end
    return defaults.copy(parent[key]);
end

function customization.set(settings, path, text)
    local parent, key = locate(settings, path);
    if not parent then return nil, 'That setting was not found. Set sparse maps as a complete JSON object.'; end
    text = tostring(text or '');
    local kind, value = type(parent[key]), nil;
    if kind == 'boolean' then
        local word = text:lower();
        if word == 'true' or word == 'on' or word == '1' then value = true;
        elseif word == 'false' or word == 'off' or word == '0' then value = false; end
    elseif kind == 'number' then value = tonumber(text);
    elseif kind == 'string' then value = text;
    elseif kind == 'table' then
        local hex = text:match('^#?(%x%x%x%x%x%x%x?%x?)$');
        if hex and (#hex == 6 or #hex == 8) and #parent[key] == 4 and type(parent[key][1]) == 'number' then
            value = {}; for index=1,3 do value[index] = tonumber(hex:sub(index*2-1,index*2),16)/255; end
            value[4] = #hex == 8 and tonumber(hex:sub(7,8),16)/255 or 1;
        else
            local ok, parsed = pcall(require('core.json').decode, text);
            if ok and type(parsed) == 'table' then value = parsed; end
        end
    end
    if type(value) ~= kind or kind == 'number' and (value ~= value or math.abs(value) == math.huge) then
        return nil, 'Use a valid '..kind..' value. Tables accept JSON; colors also accept RRGGBB or RRGGBBAA.';
    end
    local candidate = defaults.copy(settings);
    local object, field = locate(candidate, path); object[field] = value;
    -- The overhead samples turn the icons on, as /vg overhead preview does, and the party cooldown samples the list.
    if path == 'overhead.preview' and value then candidate.overhead.enabled = true; end
    if path == 'party_cooldowns.preview' and value then candidate.party_cooldowns.enabled, candidate.party_cooldowns.list.enabled = true, true; end
    -- And the Phantom Roll and pet samples their displays.
    if (path == 'rolls.preview' or path == 'pet.preview') and value then candidate[path:match('^(%w+)')].enabled = true; end
    if path == 'style.theme' then
        if not require('ui.theme').apply(candidate,value) then return nil,'That theme was not found.'; end
    end
    -- A display can't move with one that moves with it back, as the Size and place tab never offers that, so a loop is
    -- refused here rather than tidied away.
    local read, loop = pcall(require('ui.elements').loop, candidate);
    if read and loop then
        return nil, loop .. ' would move with a display that moves with it. Change what one of them moves with first. No settings changed.';
    end
    local ok, tidy = pcall(defaults.tidy, candidate);
    if not ok then return nil, 'That value is not valid for this setting.'; end
    object, field = locate(tidy, path);
    -- Tidy keeps the Grid mode ticks in the displays' order, each once, so a display set as one of them is taken
    -- while the list holds it, wherever that puts it.
    if path:match('^edit_mode%.grid_displays%.') then
        for _, id in ipairs(tidy.edit_mode.grid_displays) do if id == value then return tidy; end end
        return nil, 'That value is outside the allowed choices or range. No settings changed.';
    end
    -- Normalization can repair maps, but scalar typos and out-of-range values are rejected.
    if not object or kind ~= 'table' and not customization.equal(value, object[field]) then
        return nil, 'That value is outside the allowed choices or range. No settings changed.';
    end
    return tidy;
end

return customization;
