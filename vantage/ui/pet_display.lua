-- The pet display (settings.pet): your pet's name and, for a pet you charmed, the charm's estimated time left, or for a
-- jug the time until it leaves; its HP, MP once the client has given some, and TP as bars, with an automaton's HP as a
-- number when Show automaton HP as a number is on; the buffs and debuffs Vantage
-- saw on it, through the display's own filters and the shared hide rules, with their countdowns, as icons that wrap and
-- blink near their end or as a list with names; for a PUP your maneuvers and overload risk; and the recasts of your pet
-- commands, soonest first. It uses the timer panels' look, and its countdown text follows More look on the main page. What doesn't fit, or is
-- past a limit, is left out with nothing in its place. It moves and resizes like the party cooldown list
-- (ui/element_box.lua) and takes no clicks otherwise.
local display = {};
local theme = require('ui.theme');
local fonts = require('ui.fonts');
local metrics = require('ui.text_metrics');
local countdown = require('ui.countdown_text');
local icons = require('ui.icons');
local recast_icons = require('ui.recast_icons');
-- The cooldown list's icons, loaded the first time a pet ability's recast draws.
local cooldown_list;
local effect_filters = require('core.effect_filters');
local pet = require('core.pet');
local box = require('ui.element_box');
local blink = require('ui.effect_blink');
local conditions = require('core.conditions');
local floor, max, min, huge = math.floor, math.max, math.min, math.huge;
local LABEL = 'Pet';
local frame = box.new(LABEL, '##vantage_pet', 'Pet display layout', 'pet');
local look = { font = 'Agave' };
local corner, far, UV0, UV1, WHITE = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 1, 1 }, { 1, 1, 1, 1 };
local hovered = { kind = nil, item = nil };
-- The effects shown, sorted, each one's countdown and width as an icon, and the hide rule subject of the pet, refilled.
local picked, MAX_PICKED = {}, 32;
local cell_text, cell_width = {}, {};
local subject = { id = 0, name = '', is_self = false, player = false, scope = 'pet' };
local lower_name, lower_of = '', '';

function display.cancel_gesture() frame:cancel(); end

-- Whether a sorted list of effect ids holds id.
local function listed(values, id)
    local low, high = 1, #values;
    while low <= high do
        local middle = floor((low + high) / 2);
        local value = values[middle];
        if value == id then return true; end
        if value < id then low = middle + 1; else high = middle - 1; end
    end
    return false;
end

-- Debuffs first, then buffs, each oldest first, so icons keep their places as timers tick.
local function before(a, b)
    local first, second = a.kind == 'debuff', b.kind == 'debuff';
    if first ~= second then return first; end
    local seen, other = a.first_seen or huge, b.first_seen or huge;
    if seen ~= other then return seen < other; end
    return (a.instance or 0) < (b.instance or 0);
end

-- Fills picked with the effects the display shows. Returns how many.
local function pick(shown, config, compiled)
    local count = 0;
    local rules = config.shared_rules and compiled and compiled.active;
    if rules then
        if lower_of ~= shown.name then lower_of, lower_name = shown.name, shown.name:lower(); end
        subject.id, subject.name = shown.id, lower_name;
    end
    local include = config.include;
    for _, effect in ipairs(shown.effects) do
        local id = effect.effect;
        local debuff = effect.kind == 'debuff';
        local wanted = count < MAX_PICKED and effect.present ~= false and effect.domain ~= 'recast' and type(id) == 'number'
            and not (config.kinds == 'buff' and debuff or config.kinds == 'debuff' and not debuff)
            and not listed(config.exclude, id) and (#include == 0 or listed(include, id))
            and not (rules and effect_filters.hide(compiled, effect, subject));
        if wanted then
            local at = count + 1;
            while at > 1 and before(effect, picked[at - 1]) do picked[at] = picked[at - 1]; at = at - 1; end
            picked[at], count = effect, count + 1;
        end
    end
    for index = count + 1, #picked do picked[index] = nil; end
    return count;
end

-- An effect's countdown, or nothing to show.
local function time_text(effect, config)
    local left = effect.count_up == true and effect.elapsed or effect.remaining;
    return config.show_countdowns and type(left) == 'number' and left == left and left >= 0 and left < huge
        and effect.effect ~= 269 and box.time(left) or '';
end

-- Each icon's countdown and width, each as wide as its icon or its countdown, and how many rows they wrap to in width.
local function lay_out(count, config, width, icon, gap, timer_size)
    local rows, x = 1, 0;
    for index = 1, count do
        local text = time_text(picked[index], config);
        local cell = max(icon, text ~= '' and countdown.measure(look.font, text, timer_size, config) or 0);
        cell_text[index], cell_width[index] = text, cell;
        if x > 0 and x + cell > width + 0.001 then rows, x = rows + 1, 0; end
        x = x + cell + gap;
    end
    return rows;
end

-- An effect's picture: its icon, tinted while it blinks. Copy Image draws the icon its shadows show.
local function picture(list, effect, x, y, size, s, config, now, white)
    corner[1], corner[2], far[1], far[2] = x, y, x + size, y + size;
    local art = icons.status(effect.icon or effect.effect, s.icon_art);
    if art then list:AddImage(art, corner, far, UV0, UV1, blink.tint(effect, config, now, white)); end
end

-- One bar: its track, its fill and its text over it.
local function bar(list, x, y, width, height, fraction, fill, s, text, ink)
    corner[1], corner[2], far[1], far[2] = x, y, x + width, y + height;
    list:AddRectFilled(corner, far, theme.u32(s.track_color, s.opacity), 2);
    if fraction > 0 then
        far[1] = x + width * min(1, fraction);
        list:AddRectFilled(corner, far, theme.u32(fill), 2);
    end
    box.text(list, look, text, x + 4, y + max(0, (height - look.size) / 2), look.size, ink, width - 6);
end

local vitals_text = { hp = {}, mp = {}, tp = {} };
-- 'HP 76%', 'MP 40%' and 'TP 1250', made once for each value.
local function vital(kind, value)
    local saved = vitals_text[kind];
    local text = saved[value];
    if not text then
        text = kind == 'tp' and 'TP ' .. tostring(value) or (kind == 'hp' and 'HP ' or 'MP ') .. tostring(value) .. '%';
        saved[value] = text;
    end
    return text;
end

local hp_texts, hp_most = {}, nil;
-- 'HP 812/1040', made once for each HP while the max HP stays the same.
local function hp_text(hp, most)
    if most ~= hp_most then hp_texts, hp_most = {}, most; end
    local text = hp_texts[hp];
    if not text then text = 'HP ' .. tostring(hp) .. '/' .. tostring(most); hp_texts[hp] = text; end
    return text;
end

local percents = {};
-- '23%', made once for each value.
local function percent_text(value)
    local text = percents[value];
    if not text then text = tostring(value) .. '%'; percents[value] = text; end
    return text;
end

-- Draws the display and returns what is under the mouse, for its tooltip: { kind = 'hp', 'effect', 'charm', 'jug',
-- 'maneuver' or 'recast', item }, or nil. moving holds what hud.draw worked out; callbacks.effect_filters is the frame's shared hide rules.
function display.draw(view, settings, now, callbacks, moving)
    local config = settings.pet;
    if type(config) ~= 'table' or not config.enabled then frame:cancel(); return nil; end
    -- Its show conditions hide it, unless samples or edit mode show it.
    if not config.preview and not moving.editing and not conditions.shown('pet') then frame:cancel(); return nil; end
    local shown = config.preview and pet.samples(now, view and view.context and view.context.job) or view and view.pet;
    local has = shown ~= nil and shown.valid == true;
    local s = settings.style;
    local scale = s.scale;
    local font_size = s.font_size * scale;
    local title = (s.title_size > 0 and s.title_size or s.font_size) * scale;
    local icon = floor(s.icon_size * 0.75 + 0.5) * scale;
    local line = font_size + 6 * scale;
    local timer_size = max(8 * scale, floor(font_size * 0.8 + 0.5));
    look.font, look.size = s.font, font_size;
    local found = min(has and config.show_effects and pick(shown, config, callbacks and callbacks.effect_filters) or 0, config.max_effects);
    local recasts = has and config.show_recasts and min(shown.recast_count or 0, config.max_recasts) or 0;
    local vitals = has and config.show_vitals and (shown.has_mp and 3 or 2) or 0;
    local lines = has and config.show_maneuvers and shown.maneuver_count or 0;
    local as_list, gap = config.effects_as == 'list', max(2, floor(icon * 0.12 + 0.5));
    -- Icons wrap to the width inside the box; a row is an icon and its countdown.
    local icon_row = icon + (config.show_countdowns and timer_size + 2 * scale or 0) + 4 * scale;
    local effects_height = as_list and found * (line + 2 * scale)
        or found > 0 and icon_row * lay_out(found, config, min(config.width, moving.screen_width) - 12 * scale, icon, gap, timer_size) or 0;
    local wanted = 4 * scale + title + 8 * scale + vitals * (line + 2 * scale) + effects_height + (lines + recasts) * (line + 2 * scale) + 4 * scale;
    local rect, movable = frame:place(config, settings, callbacks, moving, wanted, has, 160);
    if not rect then return nil; end
    fonts.push(look.font, font_size);
    hovered.kind, hovered.item = nil, nil;
    local list = frame:open(rect, movable, s, config.preview);
    if list and has then
        local x, y, width = rect.x, rect.y, rect.width;
        local bottom = y + rect.height + 0.001;
        local left, right = x + 6 * scale, x + width - 6 * scale;
        local text_ink, detail_ink, value_ink = theme.u32(s.label_color or s.text_color), theme.u32(s.detail_color or s.text_color), theme.u32(s.value_color or s.text_color);
        local top = y + 4 * scale;
        -- The name, and at the right a charm's time left, its estimate or no countdown when there is none, or the time
        -- until a jug leaves, in the warning color for its last minute.
        local charm = config.show_charm and shown.charm;
        local jug = config.show_charm and not charm and shown.jug;
        local ends = charm and charm.deadline or jug and jug.deadline;
        local clock = ends and ends > now and box.time(ends - now) or '';
        local clock_width = clock ~= '' and countdown.measure(look.font, clock, font_size, config) or 0;
        local label = charm and (clock ~= '' and 'Charm' or 'Charmed') or jug and clock ~= '' and 'Leaves in' or '';
        local label_width = label ~= '' and metrics.width(look.font, label, font_size, font_size) or 0;
        local name_y = top + max(0, (title + 4 * scale - font_size) / 2);
        if label ~= '' then
            local label_x = right - clock_width - (clock ~= '' and label_width + 4 * scale or label_width);
            box.text(list, look, label, label_x, name_y, font_size, detail_ink, label_width + 2);
            if clock ~= '' then
                countdown.draw(list, look.font, clock, right - clock_width, name_y, font_size, ends - now <= 60 and theme.u32(s.warning_color) or value_ink, config, false, box.point);
            end
            if box.over(moving, movable, label_x, top, right - label_x, title + 4 * scale) then hovered.kind, hovered.item = charm and 'charm' or 'jug', charm or jug; end
        end
        local name = config.preview and shown.title or shown.name;
        box.text(list, look, name, left, top + 2 * scale, title, theme.u32(s.title_color),
            right - left - (label ~= '' and clock_width + label_width + 10 * scale or 0));
        top = top + title + 8 * scale;
        if vitals > 0 then
            local bar_width = right - left;
            if top + line <= bottom then
                local number = config.exact_hp and shown.hp;
                bar(list, left, top, bar_width, line, (shown.hpp or 0) / 100, config.hp_color, s,
                    number and hp_text(shown.hp, shown.max_hp) or shown.hpp and vital('hp', shown.hpp) or 'HP', text_ink);
                if number and box.over(moving, movable, left, top, bar_width, line) then hovered.kind, hovered.item = 'hp', shown; end
                top = top + line + 2 * scale;
            end
            if shown.has_mp and top + line <= bottom then
                bar(list, left, top, bar_width, line, (shown.mpp or 0) / 100, config.mp_color, s, shown.mpp and vital('mp', shown.mpp) or 'MP', text_ink);
                top = top + line + 2 * scale;
            end
            if top + line <= bottom then
                bar(list, left, top, bar_width, line, (shown.tp or 0) / 3000, config.tp_color, s, shown.tp and vital('tp', shown.tp) or 'TP', text_ink);
                top = top + line + 2 * scale;
            end
        end
        local white, small = theme.u32(WHITE), line - 2 * scale;
        local accent = theme.u32(s.accent_color, 0.35);
        if found > 0 and as_list then
            -- Each effect: its icon, its name and its time left, over a fill of how much is left.
            for index = 1, found do
                if top + line > bottom then break; end
                local effect = picked[index];
                local left_time, total = effect.remaining, effect.total;
                local fraction = type(left_time) == 'number' and type(total) == 'number' and total > 0 and min(1, left_time / total) or 0;
                if fraction > 0 then
                    corner[1], corner[2], far[1], far[2] = left, top, left + (right - left) * fraction, top + line;
                    list:AddRectFilled(corner, far, accent, 2);
                end
                picture(list, effect, left + scale, top + scale, small, s, config, now, white);
                local clock_text = time_text(effect, config);
                local width_of = clock_text ~= '' and countdown.measure(look.font, clock_text, font_size, config) or 0;
                local text_y = top + max(0, (line - font_size) / 2);
                box.text(list, look, effect.name or '', left + small + 6 * scale, text_y, font_size, text_ink, right - left - small - width_of - 12 * scale);
                if clock_text ~= '' then countdown.draw(list, look.font, clock_text, right - width_of, text_y, font_size, value_ink, config, false, box.point); end
                if box.over(moving, movable, left, top, right - left, line) then hovered.kind, hovered.item = 'effect', effect; end
                top = top + line + 2 * scale;
            end
        elseif found > 0 then
            -- The effects in rows, as many as the limit and the height hold, each as wide as its icon or its countdown.
            local ix = left;
            for index = 1, found do
                local effect, text, cell = picked[index], cell_text[index], cell_width[index];
                if ix > left and ix + cell > right + 0.001 then ix, top = left, top + icon_row; end
                if top + icon_row - 4 * scale > bottom then break; end
                picture(list, effect, ix + floor((cell - icon) / 2 + 0.5), top, icon, s, config, now, white);
                if text ~= '' then
                    local text_width = countdown.measure(look.font, text, timer_size, config);
                    countdown.draw(list, look.font, text, ix + floor((cell - text_width) / 2 + 0.5), top + icon + scale, timer_size, value_ink, config, true, box.point);
                end
                if box.over(moving, movable, ix, top, cell, icon) then hovered.kind, hovered.item = 'effect', effect; end
                ix = ix + cell + gap;
            end
            top = top + icon_row;
        end
        -- Each element with maneuvers: its icon, its name, a square for each maneuver up, the overload risk and the time
        -- to the next one ending.
        for index = 1, lines do
            if top + line > bottom then break; end
            local entry = shown.maneuvers[index];
            picture(list, entry, left + scale, top + scale, small, s, config, now, white);
            local clock_text = entry.deadline and entry.deadline > now and box.time(entry.deadline - now) or '';
            local width_of = clock_text ~= '' and countdown.measure(look.font, clock_text, font_size, config) or 0;
            local risk = entry.percent and percent_text(entry.percent) or '';
            local risk_width = risk ~= '' and metrics.width(look.font, risk, font_size, font_size) or 0;
            local text_y = top + max(0, (line - font_size) / 2);
            local name_x = left + small + 6 * scale;
            box.text(list, look, entry.name, name_x, text_y, font_size, text_ink, right - name_x);
            local square = max(4, floor(font_size * 0.5 + 0.5));
            local sx, sy = name_x + metrics.width(look.font, entry.name, font_size, font_size) + 6 * scale, top + floor((line - square) / 2 + 0.5);
            for _ = 1, entry.count do
                corner[1], corner[2], far[1], far[2] = sx, sy, sx + square, sy + square;
                list:AddRectFilled(corner, far, value_ink, 1);
                sx = sx + square + 2 * scale;
            end
            if risk ~= '' then box.text(list, look, risk, right - width_of - risk_width - 8 * scale, text_y, font_size, detail_ink, risk_width + 2); end
            if clock_text ~= '' then countdown.draw(list, look.font, clock_text, right - width_of, text_y, font_size, value_ink, config, false, box.point); end
            if box.over(moving, movable, left, top, right - left, line) then hovered.kind, hovered.item = 'maneuver', entry; end
            top = top + line + 2 * scale;
        end
        if recasts > 0 then
            -- Each recast: its icon, its name and its time left, over a fill of how much is left.
            local art, status_art = s.recast_icon_art, recast_icons.status_art(s);
            for index = 1, recasts do
                if top + line > bottom then break; end
                local entry = shown.recasts[index];
                local row = entry.row;
                local left_time = row.remaining;
                local fraction = type(left_time) == 'number' and entry.full > 0 and min(1, left_time / entry.full) or 0;
                if fraction > 0 then
                    corner[1], corner[2], far[1], far[2] = left, top, left + (right - left) * fraction, top + line;
                    list:AddRectFilled(corner, far, accent, 2);
                end
                cooldown_list = cooldown_list or require('ui.cooldown_list');
                recast_icons.draw(list, cooldown_list.icon(entry.info.ability), art, left + scale, top + scale, small, 1, status_art);
                local clock_text = type(left_time) == 'number' and left_time > 0 and box.time(left_time) or '';
                local width_of = clock_text ~= '' and countdown.measure(look.font, clock_text, font_size, config) or 0;
                local text_y = top + max(0, (line - font_size) / 2);
                box.text(list, look, entry.info.name, left + small + 6 * scale, text_y, font_size, text_ink, right - left - small - width_of - 12 * scale);
                if clock_text ~= '' then countdown.draw(list, look.font, clock_text, right - width_of, text_y, font_size, value_ink, config, false, box.point); end
                if box.over(moving, movable, left, top, right - left, line) then hovered.kind, hovered.item = 'recast', entry; end
                top = top + line + 2 * scale;
            end
        end
    end
    frame:close(list, rect, movable, s, config.preview, config);
    fonts.pop();
    return hovered.kind and hovered or nil;
end

-- The tooltip of what display.draw returned. An effect's is a timer panel's, read as one at the panels' first span.
local SPAN = { horizon = 300 };
function display.details(found, now)
    if found.kind == 'hp' then return pet.hp_details(); end
    if found.kind == 'charm' then return pet.charm_details(found.item, now); end
    if found.kind == 'jug' then return pet.jug_details(found.item); end
    if found.kind == 'maneuver' then return pet.maneuver_details(found.item, now); end
    if found.kind == 'recast' then return pet.recast_details(found.item, now); end
    return require('ui.hud').details(found.item, now, SPAN);
end

return display;
