local party = {};
-- The strips beside the game's party list, each with its own switch, and their names.
party.strips = { 'party', 'alliance1', 'alliance2' };
party.strip_help = 'Alliance rows show the effects Vantage sees land on alliance members. The game sends buff icons for your own party only.';
-- Buffs and debuffs, Buffs only, Debuffs only and None, four picks over effects.kind. An effect that is neither a buff
-- nor a debuff shows only under the first, and None matches no effect (ui/party_layout.lua layout.effects).
party.kind_help = 'Which of the party\'s effects show. Level Sync and others that are neither a buff nor a debuff show only under Buffs and debuffs. None shows no effects.';
-- Countdowns, the switch over effects.timers on Party list.
party.timers_help = 'Shows the time left on each party buff icon. It is off unless you turn it on. Beside the game\'s party rows the time sits inside the icon. A stack or a panel of its own puts it where Countdown position says.';
-- Show the distance to each member, Warning color past and Distance size, over distance, distance_warn and distance_size
-- (core/party_distance.lua, ui/native_party_hud.lua).
party.distance_help = 'Shows how far each member is from you in yalms, counting height as Phoenix checks range. Your own row and members the game isn\'t showing have none.';
party.warn_help = 'Past this, the number turns your Ending soon and alerts color. Spell range is Cure\'s, about 21 yalms. 10 is songs, 8 Phantom Roll and 16 Phantom Roll with Luzaf\'s Ring.';
party.size_help = 'How big the numbers are beside the game\'s party list. Medium, Large and Largest fill up to 70, 80 and 90% of each row, or of the icons in a stack. In a panel of its own they match the name.';

-- Turns Party list on or off. Turning it off ends its samples.
function party.switch(value, on)
    value.enabled = on;
    if on then party.ensure_strip(value); else value.preview = false; end;
end;

-- Turning Party list on with every strip off shows the Party strip.
function party.ensure_strip(value)
    for _, key in ipairs(party.strips) do if value.strips[key] then return; end; end;
    value.strips.party = true;
end;

-- Party list shows its effects, the distance and Party cooldowns beside the game's party list: what is effects,
-- distance or cooldowns. Turned on while Party list is off, one of them shows there alone, and with none of them left
-- Party list goes off. Effects turned off with nothing else there keep their Show pick for the next time.
function party.show_beside(settings, what, on)
    local p, watch = settings.party_ui, settings.party_cooldowns;
    if on and not p.enabled then
        if what ~= 'effects' then p.effects.kind = 'none'; end;
        if what ~= 'distance' then p.distance = false; end;
        if what ~= 'cooldowns' then watch.strips = false; end;
    end;
    if what == 'effects' then
        if on then
            if p.effects.kind == 'none' then p.effects.kind = 'all'; end;
        elseif p.distance or watch.enabled and watch.strips then p.effects.kind = 'none';
        else party.switch(p, false); return; end;
    elseif what == 'distance' then p.distance = on;
    else require('core.party_cooldowns').place(settings, 'strips', on); end;
    if on then party.switch(p, true);
    elseif p.enabled and p.effects.kind == 'none' and not p.distance and not (watch.enabled and watch.strips) then party.switch(p, false); end;
end;

local copy = require('core.tables').copy;

function party.make()
    return {
        enabled = false, preview = false,
        -- gap is the space between the game's party list and the nearest icon, or the distance while it's on. icon_size
        -- is Icon size beside the game's list, 0 to fill each row (ui/native_party_hud.lua).
        native = { side = 'left', gap = 26, width = 420, snap = true, icon_size = 0 },
        strips = { party = true, alliance1 = true, alliance2 = true },
        -- When the strips show (core/conditions.lua).
        conditions = require('core.conditions').make(),
        include_self = true, locked = true, show_solo = true,
        -- How far each member is from you, the pick its warning color starts past (core/party_distance.lua), and how big
        -- the numbers are beside the game's list (ui/native_party_hud.lua).
        distance = false, distance_warn = 'spell', distance_size = 'small',
        groups = {
            { native_x = 0, native_y = 0, native_side = 'default', native_detached = false, detached_x = 40, detached_y = 160, detached_width = 420, detached_height = 240, order = { 0, 1, 2, 3, 4, 5 } },
            { native_x = 0, native_y = 0, native_side = 'default', native_detached = false, detached_x = 286, detached_y = 160, detached_width = 420, detached_height = 240, order = { 0, 1, 2, 3, 4, 5 } },
            { native_x = 0, native_y = 0, native_side = 'default', native_detached = false, detached_x = 532, detached_y = 160, detached_width = 420, detached_height = 240, order = { 0, 1, 2, 3, 4, 5 } },
        },
        name_display = 'full', name_length = 8,
        -- Party list wears the timer panels' look (settings.style) with its own icon_art and opacity.
        style = { icon_art = 'Original FFXI', opacity = 1 },
        effects = { fit_all = true, kind = 'all', growth = 'right',
            include = {}, exclude = {}, pinned = {}, order = {}, sort = 'longest', icon_size = 32,
            max = 12, timers = false,
            icon_countdown_position = 'below', icon_countdown_size = 0, icon_countdown_gap = 0,
            countdown_bold = false, countdown_shadow = true, countdown_outline = true, countdown_outline_color = { 0, 0, 0, 1 },
            blink_icons = true, blink_seconds = 15, separate = false, cleanse_light = false, dispel_glow = true, dispel_color = copy(require('ui.defaults').dispel_color),
            show_copy_image = true, show_third_eye = true, abilities_only = false },
    };
end

-- Saved numbers keep this rounding: numeric text counts, and whole-number keys round down.
local numbers = require('ui.numbers');
local function number(value, low, high, fallback, integer)
    return (integer and numbers.clamp_floor or numbers.clamp)(tonumber(value), low, high, fallback);
end

local choice = numbers.choice;

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
local copy_image = require('data.shared_ids').copy_image;

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

-- What older Vantage builds saved in the strips' style before they took the main look. A save loses those and keeps the rest.
local retired_style = { theme = true, window_type = true, window_art = true, gauge_art = true, font = true, font_size = true,
    rounding = true, border = true, background = true, minimal = true, colors = true };

local function style(value)
    value = merge(type(value) == 'table' and value or {}, party.make().style);
    local icon_art = require('ui.icon_packs').valid_name(value.icon_art) and value.icon_art
        or choice(value.icon_art, { 'Original FFXI', 'XI View' }, 'Original FFXI');
    return require('core.store').keep_unknown({ icon_art = icon_art,
        opacity = number(value.opacity, 0.05, 1, 1) }, value, retired_style);
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
    for _, key in ipairs({ 'enabled', 'preview', 'include_self', 'locked', 'show_solo', 'distance' }) do value[key] = value[key] == true; end
    value.distance_warn = choice(value.distance_warn, { 'spell', 'ten', 'eight', 'sixteen', 'none' }, 'spell');
    value.distance_size = choice(value.distance_size, { 'small', 'medium', 'large', 'largest' }, 'small');
    value.native.side = choice(value.native.side, { 'left', 'right' }, 'left');
    value.native.gap = number(value.native.gap, 0, 40, 26, true);
    value.native.width = number(value.native.width, 40, 900, 420, true);
    value.native.snap = value.native.snap == true;
    value.native.icon_size = number(value.native.icon_size, 0, 128, 0, true);
    if value.native.icon_size > 0 then value.native.icon_size = math.max(12, value.native.icon_size); end;
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
    effects.sort = choice(effects.sort, { 'longest', 'oldest', 'name', 'remaining', 'fixed' }, 'longest');
    effects.icon_countdown_position = choice(effects.icon_countdown_position, { 'below', 'inside' }, 'below');
    effects.icon_countdown_size = math.floor(number(effects.icon_countdown_size, 0, 64, 0) + 0.5);
    if effects.icon_countdown_size > 0 then effects.icon_countdown_size = math.max(6, effects.icon_countdown_size); end;
    effects.icon_countdown_gap = math.floor(number(effects.icon_countdown_gap, 0, 16, 0) + 0.5);
    for _, key in ipairs({ 'fit_all', 'timers', 'separate',
        'countdown_bold', 'countdown_shadow', 'countdown_outline', 'blink_icons', 'cleanse_light', 'show_copy_image', 'show_third_eye',
        'abilities_only' }) do
        effects[key] = effects[key] == true;
    end
    effects.countdown_outline_color = color(effects.countdown_outline_color) or copy(fresh.effects.countdown_outline_color);
    -- A save from before Party list had a light look of its own takes Overhead icons', which it went by (ui/defaults.lua).
    effects.dispel_color = color(effects.dispel_color) or copy(fresh.effects.dispel_color);
    for _, key in ipairs({ 'include', 'exclude', 'pinned', 'order' }) do effects[key] = id_list(effects[key]); end
    for key, bounds in pairs({ icon_size = { 12, 128 }, max = { 1, 32 }, blink_seconds = { 1, 300 } }) do
        effects[key] = number(effects[key], bounds[1], bounds[2], fresh.effects[key], true);
    end
    return value;
end

return party;
