local party = {};
-- The strips beside the game's party list, each with its own switch, and their names.
party.strips = { 'party', 'alliance1', 'alliance2' };
party.strip_help = 'Alliance rows show the effects Vantage sees land on alliance members. The game sends buff icons for your own party only.';
-- Buffs and debuffs, Buffs only, Debuffs only and None, four picks over effects.kind. An effect that is neither a buff
-- nor a debuff shows only under the first, and None matches no effect (ui/party_layout.lua layout.effects).
party.kind_help = 'Which of the party\'s effects show. Effects that are neither a buff nor a debuff, such as Level Sync, show only under Buffs and debuffs. None shows no effects, for when you only want Party cooldowns here.';
-- Countdowns, the switch over effects.timers on Party list buffs.
party.timers_help = 'Shows the time left on each party buff icon. It is off unless you turn it on. Beside the game\'s party list the time sits inside the icon.';

-- Turns the party list buffs on or off. Turning them off ends their samples.
function party.switch(value, on)
    value.enabled = on;
    if on then party.ensure_strip(value); else value.preview = false; end;
end;

-- Turning the party list buffs on with every strip off shows the Party strip.
function party.ensure_strip(value)
    for _, key in ipairs(party.strips) do if value.strips[key] then return; end; end;
    value.strips.party = true;
end;

local function copy(value)
    if type(value) ~= 'table' then return value; end
    local out = {};
    for key, item in pairs(value) do out[key] = copy(item); end
    return out;
end

function party.make()
    return {
        enabled = false, preview = false,
        -- gap is the space between the game's party list and the nearest icon.
        native = { side = 'left', gap = 26, width = 420, snap = true },
        strips = { party = true, alliance1 = true, alliance2 = true },
        -- When the strips show (core/conditions.lua).
        conditions = require('core.conditions').make(),
        include_self = true, locked = true, show_solo = true,
        groups = {
            { native_x = 0, native_y = 0, native_side = 'default', native_detached = false, detached_x = 40, detached_y = 160, detached_width = 420, detached_height = 240, order = { 0, 1, 2, 3, 4, 5 } },
            { native_x = 0, native_y = 0, native_side = 'default', native_detached = false, detached_x = 286, detached_y = 160, detached_width = 420, detached_height = 240, order = { 0, 1, 2, 3, 4, 5 } },
            { native_x = 0, native_y = 0, native_side = 'default', native_detached = false, detached_x = 532, detached_y = 160, detached_width = 420, detached_height = 240, order = { 0, 1, 2, 3, 4, 5 } },
        },
        name_display = 'full', name_length = 8,
        -- The party list buffs wear the timer panels' look (settings.style) with their own icon_art and opacity.
        style = { icon_art = 'Original FFXI', opacity = 1 },
        effects = { fit_all = true, kind = 'all', growth = 'right',
            include = {}, exclude = {}, pinned = {}, sort = 'longest', icon_size = 32,
            max = 12, timers = false,
            icon_countdown_position = 'below', icon_countdown_size = 0, icon_countdown_gap = 0,
            countdown_bold = false, countdown_shadow = true, countdown_outline = true, countdown_outline_color = { 0, 0, 0, 1 },
            blink_icons = true, blink_seconds = 15, separate = false, cleanse_light = false,
            show_copy_image = true, show_third_eye = true },
    };
end

-- Saved numbers keep this rounding: numeric text counts, and whole-number keys round down.
local numbers = require('ui.numbers');
local function number(value, low, high, fallback, integer)
    return (integer and numbers.clamp_floor or numbers.clamp)(tonumber(value), low, high, fallback);
end

local function choice(value, choices, fallback)
    for _, item in ipairs(choices) do if value == item then return value; end end
    return fallback;
end

local function merge(value, fresh)
    if type(value) ~= 'table' then return copy(fresh); end
    for key, default in pairs(fresh) do
        if type(default) == 'table' then value[key] = merge(value[key], default);
        elseif type(value[key]) ~= type(default) then value[key] = default; end
    end
    return value;
end

-- Copy Image (66) shows its shadows as icons 444, 445 and 446, and every copy leaves the tracker as 66, so an id one of
-- them names reads as 66 too, or it would never match.
local copy_image = { [444] = 66, [445] = 66, [446] = 66 };

local function id_list(value)
    local out, used = {}, {};
    if type(value) ~= 'table' then return out; end
    for _, id in ipairs(value) do
        id = tonumber(id);
        if id and id == math.floor(id) and id > 0 and id < 1024 and id ~= 255 then
            id = copy_image[id] or id;
            if not used[id] then
                out[#out + 1], used[id] = id, true;
                if #out == 512 then break; end
            end
        end
    end
    return out;
end

local function color(value)
    if type(value) ~= 'table' then return nil; end
    local out = {};
    for i = 1, 4 do
        if type(value[i]) ~= 'number' or value[i] ~= value[i] then return nil; end
        out[i] = number(value[i], 0, 1, 1);
    end
    return out;
end

local function style(value)
    value = merge(type(value) == 'table' and value or {}, party.make().style);
    return { icon_art = choice(value.icon_art, { 'Client', 'Original FFXI', 'XI View' }, 'Original FFXI'),
        opacity = number(value.opacity, 0.05, 1, 1) };
end

function party.tidy(value)
    local fresh = party.make();
    -- The groups become a new list of three, from an object's "1" to "3" too (a hand edit, or /vg set), so a
    -- save never meets keys of both kinds.
    if type(value) == 'table' and type(value.groups) == 'table' then
        local groups = {};
        for i = 1, 3 do groups[i] = value.groups[tostring(i)] or value.groups[i]; end;
        value.groups = groups;
    end;
    value = merge(value, fresh);
    for _, key in ipairs(party.strips) do value.strips[key] = value.strips[key] == true; end
    for _, key in ipairs({ 'enabled', 'preview', 'include_self', 'locked', 'show_solo' }) do value[key] = value[key] == true; end
    value.native.side = choice(value.native.side, { 'left', 'right' }, 'left');
    value.native.gap = number(value.native.gap, 0, 40, 26, true);
    value.native.width = number(value.native.width, 40, 900, 420, true);
    value.native.snap = value.native.snap == true;
    value.name_display = choice(value.name_display, { 'full', 'short', 'job', 'job_icon', 'icon' }, 'full');
    value.name_length = number(value.name_length, 3, 16, 8, true);
    value.style = style(value.style);
    for i = 1, 3 do
        local group = merge(value.groups[i], fresh.groups[i]);
        group.native_x = number(group.native_x, -2000, 2000, 0, true);
        group.native_y = number(group.native_y, -2000, 2000, 0, true);
        group.native_side = choice(group.native_side, { 'default', 'left', 'right' }, 'default');
        group.native_detached = group.native_detached == true;
        group.detached_x = number(group.detached_x, 0, 16384, fresh.groups[i].detached_x, true);
        group.detached_y = number(group.detached_y, 0, 16384, fresh.groups[i].detached_y, true);
        group.detached_width = number(group.detached_width, 40, 900, 420, true);
        group.detached_height = number(group.detached_height, 40, 16000, 240, true);
        local order, seen = {}, {};
        for _, slot in ipairs(group.order) do
            if type(slot) == 'number' and slot >= 0 and slot <= 5 and slot == math.floor(slot) and not seen[slot] then
                order[#order + 1], seen[slot] = slot, true;
            end
        end
        for slot = 0, 5 do if not seen[slot] then order[#order + 1] = slot; end end
        group.order = order;
        value.groups[i] = group;
    end
    for i = #value.groups, 4, -1 do value.groups[i] = nil; end
    local effects = value.effects;
    effects.growth = choice(effects.growth, { 'right', 'left' }, 'right');
    effects.kind = choice(effects.kind, { 'all', 'buff', 'debuff', 'none' }, 'all');
    effects.sort = choice(effects.sort, { 'longest', 'oldest', 'name', 'remaining' }, 'longest');
    effects.icon_countdown_position = choice(effects.icon_countdown_position, { 'below', 'inside' }, 'below');
    effects.icon_countdown_size = math.floor(number(effects.icon_countdown_size, 0, 64, 0) + 0.5);
    if effects.icon_countdown_size > 0 then effects.icon_countdown_size = math.max(6, effects.icon_countdown_size); end;
    effects.icon_countdown_gap = math.floor(number(effects.icon_countdown_gap, 0, 16, 0) + 0.5);
    for _, key in ipairs({ 'fit_all', 'timers', 'separate',
        'countdown_bold', 'countdown_shadow', 'countdown_outline', 'blink_icons', 'cleanse_light', 'show_copy_image', 'show_third_eye' }) do
        effects[key] = effects[key] == true;
    end
    effects.countdown_outline_color = color(effects.countdown_outline_color) or copy(fresh.effects.countdown_outline_color);
    for _, key in ipairs({ 'include', 'exclude', 'pinned' }) do effects[key] = id_list(effects[key]); end
    for key, bounds in pairs({ icon_size = { 12, 128 }, max = { 1, 32 }, blink_seconds = { 1, 300 } }) do
        effects[key] = number(effects[key], bounds[1], bounds[2], fresh.effects[key], true);
    end
    return value;
end

return party;
