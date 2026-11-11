-- Overhead icons: the settings and their ranges. Off by default. Nothing here is dragged, so there are no locks.
-- The sizes, heights and limits come from Phoenix hitboxes and era fights (docs/OVERHEAD.md); the ones marked
-- there as guesses are settings, so calibrating in game needs no code change.
local overhead = {};
local numbers = require('ui.numbers');

-- The unit types each block is laid out for, and who can get one, in the order of the settings.
overhead.types = { 'mob', 'party', 'alliance', 'other', 'pet', 'other_pet', 'self' };
overhead.units = { 'target', 'subtarget', 'claimed', 'watched', 'debuffed', 'party', 'pet', 'alliance', 'other', 'other_pet', 'self' };
overhead.layouts = { 'single', 'lines', 'split' };
-- Single bar limit, then two lines (debuffs, buffs), then split (buffs, debuffs), for each type.
local limits = {
    mob = { 8, 8, 4, 4, 6 }, party = { 8, 6, 8, 6, 6 }, self = { 8, 6, 8, 6, 6 }, alliance = { 6, 6, 4, 6, 6 },
    other = { 6, 6, 4, 6, 6 }, pet = { 6, 6, 4, 4, 4 }, other_pet = { 6, 6, 4, 4, 4 },
};
-- Standing head heights for races 1 to 8: Hume M and F, Elvaan M and F, Tarutaru M and F, Mithra, Galka.
overhead.race_heights = { 1.80, 1.70, 2.05, 1.95, 1.00, 1.00, 1.55, 2.05 };
overhead.kinds = { 'all', 'buff', 'debuff' };
-- The groups of effects a type can turn off, in the order of the settings, by their Phoenix data/status_effects.yaml
-- ids. usual marks the long effects other players leave out at first.
overhead.switches = {
    { key = 'show_rolls', label = 'Corsair rolls', help = 'All 18 rolls and Double-Up Chance. Bust stays, as it\'s a penalty.',
        ids = { 308, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327 } },
    { key = 'show_songs', label = 'Bard songs',
        help = 'Every song that helps you, such as Minuet and March. Requiem, Elegy and Threnody stay, as they\'re debuffs.',
        ids = { 195, 196, 197, 198, 199, 200, 201, 202, 203, 205, 206, 207, 209, 210, 214, 215, 216, 218, 219, 220, 221 } },
    { key = 'show_protect_shell', label = 'Protect and Shell', help = 'Protect and Shell, from Protectra and Shellra too.',
        ids = { 40, 41 }, usual = true },
    { key = 'show_food', label = 'Food', help = 'The effect of food you have eaten.', ids = { 251 }, usual = true },
    { key = 'show_barspells', label = 'Barspells', help = 'All 13, from Barfire to Barvirus.',
        ids = { 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112 } },
    { key = 'show_stances', label = 'Stances',
        help = 'Hasso, Seigan, Counterstance, Defender, Berserk, Aggressor, Souleater and Last Resort.',
        ids = { 353, 354, 61, 57, 56, 58, 63, 64 } },
    { key = 'show_signet', label = 'Signet and similar',
        help = 'Signet, Sanction, Level Sync, Level Restriction, Reraise, Mounted and Battlefield.',
        ids = { 253, 256, 269, 143, 113, 252, 254 }, usual = true },
};
-- Effects with a tick of their own under Always show, here and on Party list buffs. Ticked beats Show and who cast it,
-- as players cast these on themselves. Only your party's buffs reach the client, and Vantage counts a mob's or an
-- alliance member's shadows and follows their Third Eye itself (core/observer.lua). A stranger's would never change, so
-- other players have no tick, nor do pets, and treat these effects like any other.
overhead.always = {
    { key = 'show_copy_image', label = 'Copy Image', help = 'Utsusemi\'s shadows. Its icon shows how many are left.', ids = { 66 },
        words = 'utsusemi shadows' },
    { key = 'show_third_eye', label = 'Third Eye', help = 'The Samurai ability.', ids = { 67 }, words = 'sam samurai' },
};
overhead.always_for = { mob = true, party = true, alliance = true, self = true };
-- What each type shows at first: mobs every debuff from you, your party or alliance and their own buffs; the
-- alliance debuffs only, as Vantage only sees what lands on them; you every debuff and buff; everyone else every
-- debuff and the buffs you cast. Other players leave out the usual long effects; your own block keeps them, so it
-- shows all you have on, and so does a mob, as you can take its Protect and Shell off.
local filters = {
    mob = { kinds = 'all', buffs_mine_only = false, debuffs_party_only = true, usual = true },
    alliance = { kinds = 'debuff', buffs_mine_only = false, debuffs_party_only = false, usual = false },
    self = { kinds = 'all', buffs_mine_only = false, debuffs_party_only = false, usual = true },
};
local PLAYER_FILTER = { kinds = 'all', buffs_mine_only = true, debuffs_party_only = false, usual = false };
-- How far above the head the middle of the game's name sits, in yalms: half a yalm for players, whose heads come
-- from their race, and none for mobs and pets, whose heads come from their hitbox.
local NO_LIFT = { mob = true, pet = true, other_pet = true };

local function unit_type(id)
    local limit = limits[id];
    local filter = filters[id] or PLAYER_FILTER;
    local result = { layout = 'single', limit = limit[1], line_debuffs = limit[2], line_buffs = limit[3],
        split_buffs = limit[4], split_debuffs = limit[5], swap_lines = false, swap_sides = false,
        world_offset = 0, name_lift = NO_LIFT[id] and 0 or 0.5, screen_x = 0, screen_y = 0, size_scale = 1, countdown = true,
        kinds = filter.kinds, mine_only = false, buffs_mine_only = filter.buffs_mine_only,
        debuffs_party_only = filter.debuffs_party_only, include = {}, exclude = {}, shared_rules = true };
    for _, switch in ipairs(overhead.switches) do result[switch.key] = filter.usual or not switch.usual; end
    if overhead.always_for[id] then
        for _, tick in ipairs(overhead.always) do result[tick.key] = filter.usual; end
    end
    -- The larger crowd control slot is for mobs only.
    if id == 'mob' then result.cc_slot = true; end
    -- Debuffs you can remove light up on you and your allies, in the glow and color of a mob's lit buffs.
    if id == 'party' or id == 'alliance' or id == 'self' then result.cleanse_light = true; end
    return result;
end

function overhead.make()
    local units, types = {}, {};
    for _, id in ipairs(overhead.units) do units[id] = id ~= 'other' and id ~= 'other_pet' and id ~= 'self'; end
    for _, id in ipairs(overhead.types) do types[id] = unit_type(id); end
    local heights = {};
    for race, height in ipairs(overhead.race_heights) do heights[race] = height; end
    return {
        -- preview draws sample icons (ui/overhead_preview.lua) while overhead icons are on.
        enabled = false, preview = false, units = units, types = types,
        max_units = 10, distance_cap = 30, fade_start = 20, fade_alpha = 0.5,
        hide_in_cities = true,
        -- Read at the 2nd BeginScene, as a camera read at Present makes the icons shake in game.
        camera = { capture = 'scene', scene_index = 2, hold_ms = 250, max_distance = 60 },
        size = { base = 22, ref_depth = 10, alpha = 0.5, ref_hitbox = 1.5, beta = 0.5, s_min = 0.85, s_max = 1.6,
            min_px = 14, max_px = 40, target_scale = 1.2 },
        head = { heights = {}, offsets = {}, sizes = {}, race_heights = heights, default_height = 1.80,
            mounted_base = 1.35, mounted_factor = 0.55, sit_factor = 0.6, chair_factor = 0.75,
            mob_height_base = 0.6, mob_height_per_hitbox = 1.0, mob_height_min = 1.2, mob_height_max = 8.0, default_hitbox = 1.5 },
        -- The game's names and target cursor as Vantage leaves room for them: a name 0.33 yalms tall in the world and
        -- at most 24 px on a display 1080 high, the cursor over it 0.4 yalms and at most 16 px.
        layout = { placement = 'above_name', name_height = 0.33, name_cap = 24, target_height = 0.4, target_cap = 16, gap = 3,
            line_gap = 2, icon_gap = 0, split_gap = 6, cc_scale = 1.4 },
        countdown_bold = false, countdown_shadow = true, countdown_outline = false,
        countdown_outline_color = { 0, 0, 0, 1 }, small_icon_inside_px = 18,
        countdown_color = { 1, 1, 1, 1 }, blink_icons = true, blink_seconds = 15,
        dispel_light = true, dispel_glow = true, dispel_color = { 1, 0.82, 0.25, 1 },
    };
end

local function number(value, low, high, fallback, integer)
    return (integer and numbers.clamp_round or numbers.clamp)(value, low, high, fallback);
end

local function choice(value, choices, fallback)
    for _, item in ipairs(choices) do if value == item then return value; end end
    return fallback;
end

local function table_of(value) return type(value) == 'table' and value or {}; end

-- Copy Image (66) shows its shadows as icons 444, 445 and 446, and every copy leaves the tracker as 66, so an id one of
-- them names reads as 66 too, or it would never match.
local copy_image = { [444] = 66, [445] = 66, [446] = 66 };

-- Effect ids 1 to 1023 as a sorted list without repeats, from a list or from a set as the panels keep theirs, with
-- Copy Image's icons read as 66. At most 256 are kept.
local function effect_list(value)
    local seen, result = {}, {};
    value = table_of(value);
    local function add(id)
        id = tonumber(id);
        if numbers.finite(id) and id >= 1 and id <= 1023 and id == math.floor(id) then
            id = copy_image[id] or id;
            if not seen[id] then seen[id], result[#result + 1] = true, id; end
        end
    end
    for key, on in pairs(value) do if on == true then add(key); end end
    for _, id in ipairs(value) do add(id); end
    table.sort(result);
    for index = #result, 257, -1 do result[index] = nil; end
    return result;
end

local function rgba(value, fallback)
    local color, saved = {}, table_of(value);
    for i = 1, 4 do color[i] = number(saved[i] or saved[tostring(i)], 0, 1, fallback[i]); end
    return color;
end

-- A map from an exact unit name to a number. A name is 1 to 40 characters with no control characters; at most
-- 256 names are kept, the first in name order.
local function names(value, low, high)
    local keys, result = {}, {};
    for key, entry in pairs(table_of(value)) do
        if type(key) == 'string' and key ~= '' and #key <= 40 and not key:find('[%c]') and numbers.finite(entry) then
            keys[#keys + 1] = key;
        end
    end
    table.sort(keys);
    for index = 1, math.min(#keys, 256) do result[keys[index]] = number(value[keys[index]], low, high, 0); end
    return result;
end

-- Keys this doesn't know are kept, as the rest of the settings keep them.
function overhead.tidy(value)
    local fresh = overhead.make();
    value = table_of(value);
    -- The samples show only while the icons are on, so turning them off any way ends the samples.
    value.enabled = value.enabled == true;
    value.preview = value.enabled and value.preview == true;
    local units = table_of(value.units);
    for _, id in ipairs(overhead.units) do
        if type(units[id]) ~= 'boolean' then units[id] = fresh.units[id]; end
    end
    value.units = units;
    local types = table_of(value.types);
    for _, id in ipairs(overhead.types) do
        local base, t = fresh.types[id], table_of(types[id]);
        t.layout = choice(t.layout, overhead.layouts, 'single');
        for _, key in ipairs({ 'limit', 'line_debuffs', 'line_buffs', 'split_buffs', 'split_debuffs' }) do
            t[key] = number(t[key], 1, 32, base[key], true);
        end
        for _, key in ipairs({ 'swap_lines', 'swap_sides', 'countdown', 'cc_slot', 'mine_only', 'buffs_mine_only',
            'debuffs_party_only', 'show_rolls', 'show_songs', 'show_protect_shell', 'show_food', 'show_barspells',
            'show_stances', 'show_signet', 'show_copy_image', 'show_third_eye', 'shared_rules', 'cleanse_light' }) do
            if base[key] == nil then t[key] = nil; elseif type(t[key]) ~= 'boolean' then t[key] = base[key]; end
        end
        t.kinds = choice(t.kinds, overhead.kinds, base.kinds);
        t.include, t.exclude = effect_list(t.include), effect_list(t.exclude);
        t.world_offset = number(t.world_offset, -3, 5, 0);
        t.name_lift = number(t.name_lift, -2, 3, base.name_lift);
        t.screen_x, t.screen_y = number(t.screen_x, -200, 200, 0, true), number(t.screen_y, -200, 200, 0, true);
        t.size_scale = number(t.size_scale, 0.5, 2, 1);
        types[id] = t;
    end
    -- A type is a table, a newer Vantage's too. Anything else in the map goes, as the settings window reads each one.
    for id, t in pairs(types) do if type(t) ~= 'table' then types[id] = nil; end end
    value.types = types;
    value.max_units = number(value.max_units, 1, 24, 10, true);
    value.distance_cap = number(value.distance_cap, 5, 50, 30);
    value.fade_start = number(value.fade_start, 0, value.distance_cap, math.min(20, value.distance_cap));
    value.fade_alpha = number(value.fade_alpha, 0, 1, 0.5);
    value.hide_in_cities = value.hide_in_cities ~= false;
    local camera = table_of(value.camera);
    camera.capture = choice(camera.capture, { 'present', 'scene' }, 'scene');
    camera.scene_index = number(camera.scene_index, 1, 8, 2, true);
    camera.hold_ms = number(camera.hold_ms, 0, 2000, 250, true);
    camera.max_distance = number(camera.max_distance, 10, 500, 60);
    value.camera = camera;
    local size = table_of(value.size);
    for key, range in pairs({ base = { 12, 48 }, ref_depth = { 3, 30 }, alpha = { 0, 1 }, ref_hitbox = { 0.5, 5 },
        beta = { 0, 1 }, s_min = { 0.5, 1 }, s_max = { 1, 2.5 }, target_scale = { 1, 1.6 } }) do
        size[key] = number(size[key], range[1], range[2], fresh.size[key]);
    end
    size.min_px = number(size.min_px, 10, 64, 14, true);
    size.max_px = math.max(size.min_px, number(size.max_px, 10, 64, 40, true));
    value.size = size;
    local head = table_of(value.head);
    head.heights, head.offsets, head.sizes = names(head.heights, 0.2, 12), names(head.offsets, -3, 5), names(head.sizes, 0.5, 2);
    -- A new list of eight, from an object's "1" to "8" too (a hand edit, or /vg set).
    local races, saved = {}, table_of(head.race_heights);
    for race = 1, 8 do races[race] = number(saved[race] or saved[tostring(race)], 0.5, 4, overhead.race_heights[race]); end
    head.race_heights = races;
    for key, range in pairs({ default_height = { 0.5, 4 }, mounted_base = { 0, 4 }, mounted_factor = { 0, 1.5 },
        sit_factor = { 0.2, 1 }, chair_factor = { 0.2, 1 }, mob_height_base = { -1, 3 }, mob_height_per_hitbox = { 0.3, 2.5 },
        mob_height_min = { 0.2, 8 }, default_hitbox = { 0.3, 8 } }) do
        head[key] = number(head[key], range[1], range[2], fresh.head[key]);
    end
    head.mob_height_max = math.max(head.mob_height_min, number(head.mob_height_max, 1, 12, 8));
    value.head = head;
    local layout = table_of(value.layout);
    layout.placement = choice(layout.placement, { 'above_name', 'below_name' }, 'above_name');
    for key, range in pairs({ name_cap = { 6, 80 }, target_cap = { 0, 60 }, gap = { 0, 20 }, line_gap = { 0, 16 },
        icon_gap = { 0, 16 }, split_gap = { 0, 40 } }) do
        layout[key] = number(layout[key], range[1], range[2], fresh.layout[key], true);
    end
    layout.name_height = number(layout.name_height, 0.05, 1.5, fresh.layout.name_height);
    layout.target_height = number(layout.target_height, 0, 1.5, fresh.layout.target_height);
    layout.cc_scale = number(layout.cc_scale, 1, 2, 1.4);
    value.layout = layout;
    for _, key in ipairs({ 'countdown_bold', 'countdown_shadow', 'countdown_outline' }) do
        if type(value[key]) ~= 'boolean' then value[key] = fresh[key]; end
    end
    value.countdown_outline_color = rgba(value.countdown_outline_color, fresh.countdown_outline_color);
    value.small_icon_inside_px = number(value.small_icon_inside_px, 0, 64, 18, true);
    value.countdown_color = rgba(value.countdown_color, fresh.countdown_color);
    value.dispel_color = rgba(value.dispel_color, fresh.dispel_color);
    for _, key in ipairs({ 'blink_icons', 'dispel_light', 'dispel_glow' }) do
        if type(value[key]) ~= 'boolean' then value[key] = fresh[key]; end
    end
    value.blink_seconds = number(value.blink_seconds, 1, 300, 15, true);
    return value;
end

return overhead;
