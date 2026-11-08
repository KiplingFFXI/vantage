-- Overhead icons, drawn: each unit's buffs and debuffs in its block above the head, at the spot and size
-- core/overhead.lua's plan gives, on ImGui's background draw list. There is no window or item and nothing reads
-- the mouse, so the icons are click-through. The effects are the tracker rows the panels show, filtered with the
-- panels' filter tools and the shared hide rules. Layouts, limits and order: docs/OVERHEAD.md. Every table here is
-- made once and refilled, so a frame makes nothing.
local draw = {};
local icons = require('ui.icons');
local countdown = require('ui.countdown_text');
local effect_blink = require('ui.effect_blink');
local metrics = require('ui.text_metrics');
local theme = require('ui.theme');
local effect_filters = require('core.effect_filters');
local dispel = require('core.dispel');
local recast_icons = require('ui.recast_icons');
local overhead = require('core.overhead');
-- The cooldown list's icons, loaded the first time a cooldown line draws.
local cooldown_list;
local floor, ceil, max, min, huge = math.floor, math.ceil, math.max, math.min, math.huge;

-- Units in a plan and effects looked at for one unit.
local UNITS, CANDIDATES = 24, 96;
-- The priority from which a debuff is crowd control (data/catalog.lua: Sleep, Silence, Petrification, Stun, Charm,
-- Amnesia, Terror, Lullaby at 80, Doom 100).
local CONTROL = 80;
local DISPELABLE = dispel.buffs;
-- The hide rule scope of each unit type; the party and the alliance take theirs from the roster.
local SCOPES = { mob = 'enemy', other = 'other', pet = 'pet', other_pet = 'pet', party = 'party', alliance = 'alliance',
    self = 'self' };
local OWN_SCOPE = { mob = true, other = true, pet = true, other_pet = true };

-- One unit's block. Icon i: its effect, place (left and top, from the block's anchor), size, whether it is lit, and
-- its countdown (text, place and font size; '' for none). left, top, right and bottom bound the block from the anchor.
local slots = {};
for index = 1, UNITS do
    slots[index] = { count = 0, effect = {}, x = {}, y = {}, size = {}, lit = {}, cooldown = {}, text = {}, text_x = {}, text_y = {},
        text_size = {}, left = 0, top = 0, right = 0, bottom = 0, name = nil, lower = '',
        subject = { id = 0, name = '', is_self = false, player = false, scope = 'enemy' } };
end
-- The effects a unit can show, sorted, with each one's tier and light.
local picked, tiers, lights = {}, {}, {};
-- Which picked effects each line of a layout takes.
local chosen = {};
-- Whether the plan being drawn puts its blocks above the name.
local above = true;

local function clamp(value, low, high) return value < low and low or value > high and high or value; end

-- Countdown text, made once for each value it can show: whole seconds under a minute, then minutes, then hours. The
-- seconds and minutes are made at load, so a timer ticking down makes nothing.
local texts, text_count = { [0] = countdown.time(0) }, 0;
for second = 1, 60 do texts[second] = countdown.time(second - 0.5); end
for minute = 1, 59 do texts[10000 + minute] = countdown.time(minute * 60); end
local function time_text(effect)
    if effect.effect == 269 and effect.domain ~= 'recast' then return ''; end
    -- A duration override that counts up (core/durations.lua) shows the time since the effect landed.
    local left = effect.count_up == true and effect.elapsed or effect.remaining;
    if type(left) ~= 'number' or left ~= left or left < 0 or left == huge then return ''; end
    local key = left >= 3600 and 20000 + floor(left / 3600) or left >= 60 and 10000 + floor(left / 60) or ceil(left);
    local text = texts[key];
    if not text then
        text = countdown.time(left);
        if text_count < 8192 then texts[key], text_count = text, text_count + 1; end
    end
    return text;
end

-- Countdown sizes, by font size and text, kept until the font, its measuring or the countdown look changes.
local widths, heights, measured = {}, {}, { font = nil, token = nil, bold = nil, shadow = nil, outline = nil };
local function measuring(font, config)
    local token = metrics.token(font, 16);
    if measured.font == font and measured.token == token and measured.bold == config.countdown_bold
        and measured.shadow == config.countdown_shadow and measured.outline == config.countdown_outline then return; end
    for key in pairs(widths) do widths[key], heights[key] = nil, nil; end
    measured.font, measured.token, measured.bold = font, token, config.countdown_bold;
    measured.shadow, measured.outline = config.countdown_shadow, config.countdown_outline;
end
local function measure(font, text, size, config)
    local by_width = widths[size];
    if not by_width then by_width = {}; widths[size], heights[size] = by_width, {}; end
    local width = by_width[text];
    if not width then
        local height;
        width, height = countdown.measure(font, text, size, config, true);
        by_width[text], heights[size][text] = width, height;
    end
    return width, heights[size][text];
end

-- The countdown font size below an icon of size px: half the icon, 9 to 16 px at 1080p.
local function below_size(size, ui) return clamp(floor(size * 0.5 + 0.5), floor(9 * ui + 0.5), floor(16 * ui + 0.5)); end

-- Whether a goes before b in a list: by tier, then oldest first, so icons keep their places as timers tick.
local function before(a, a_tier, b, b_tier)
    if a_tier ~= b_tier then return a_tier < b_tier; end
    local first, second = a.first_seen or huge, b.first_seen or huge;
    if first ~= second then return first < second; end
    first, second = a.first_sequence or huge, b.first_sequence or huge;
    if first ~= second then return first < second; end
    return false;
end

-- The tier of an effect on a unit (docs/OVERHEAD.md): on mobs crowd control, lit buffs and what Always show has ticked,
-- your debuffs, other debuffs, other buffs; on everyone else crowd control, other debuffs, what Always show has ticked,
-- your buffs, other buffs.
local function tier(effect, mob, lit, ticked)
    local debuff = effect.kind == 'debuff';
    if debuff and (effect.priority or 0) >= CONTROL then return 1; end
    if mob then
        if debuff then return (effect.mine or effect.by_pet) and 3 or 4; end
        return (lit or ticked) and 2 or 5;
    end
    if debuff then return 2; end
    if ticked then return 3; end
    return (effect.mine or effect.by_pet) and 4 or 5;
end

-- The hide rule subject of a unit: the roster's, when it has one, with the unit's own type deciding enemy, other and
-- pet. Its lowercase name is made only when the name changes.
local function rule_subject(slot, unit, recipients)
    local subject, known = slot.subject, recipients and recipients[unit.id];
    if slot.name ~= unit.name then slot.name, slot.lower = unit.name, unit.name:lower(); end
    subject.id, subject.is_self = unit.id, unit.kind == 'self';
    if known then
        subject.name, subject.job, subject.group, subject.player = known.name, known.job, known.group, known.player;
        subject.scope = known.scope;
    else
        subject.name, subject.job, subject.group, subject.player = slot.lower, nil, nil, unit.player == true;
        subject.scope = SCOPES[unit.kind];
    end
    if OWN_SCOPE[unit.kind] then subject.scope = SCOPES[unit.kind]; end
    return subject;
end

-- Fills picked with the effects of one unit its type shows, sorted: those its own filters keep
-- (core/overhead.lua) and the shared hide rules leave. Returns how many.
local function pick(subject, unit, kind, compiled, subject_rules, ready, light, removable)
    local count, mob = 0, unit.kind == 'mob';
    local effects = subject and subject.effects;
    if type(effects) ~= 'table' then return 0; end
    local rules = kind.shared_rules and compiled.active;
    for index = 1, #effects do
        local effect = effects[index];
        local wanted = count < CANDIDATES and overhead.keeps(kind, effect)
            and not (rules and effect_filters.hide(compiled, effect, subject_rules));
        if wanted then
            local lit = light and mob and effect.kind ~= 'debuff' and ready and DISPELABLE[effect.effect] == true;
            local rank = tier(effect, mob, lit, overhead.ticked(kind, effect.effect));
            -- A debuff you can remove lights once its tier is known, so it keeps its place.
            if removable and removable[effect.effect] then lit = true; end
            -- Insertion sort; ties keep the order the tracker gave.
            local at = count + 1;
            while at > 1 and before(effect, rank, picked[at - 1], tiers[at - 1]) do
                picked[at], tiers[at], lights[at] = picked[at - 1], tiers[at - 1], lights[at - 1];
                at = at - 1;
            end
            picked[at], tiers[at], lights[at], count = effect, rank, lit, count + 1;
        end
    end
    for index = count + 1, #picked do picked[index], tiers[index], lights[index] = nil, nil, nil; end
    return count;
end

-- Adds an effect to the slot as icon number n, at x, y and size px, with the countdown of timed (the effect, or the
-- clock of a party cooldown). Returns n.
local function put(slot, effect, lit, cooldown, timed, x, y, size, show_timer, ui, font, config)
    local n = slot.count + 1;
    slot.count, slot.effect[n], slot.x[n], slot.y[n], slot.size[n], slot.lit[n] = n, effect, x, y, size, lit;
    slot.cooldown[n] = cooldown;
    local text = show_timer and size >= 14 * ui and time_text(timed) or '';
    local text_size, text_x, text_y = 0, 0, 0;
    if text ~= '' then
        if size >= config.small_icon_inside_px * ui then
            text_size = below_size(size, ui);
            local width = measure(font, text, text_size, config);
            text_x, text_y = x + floor((size - width) / 2 + 0.5), y + size;
        else
            -- Inside the icon at its bottom, as small as 8 px to fit; past that no text.
            local floor_size, width, height = floor(8 * ui + 0.5), 0, 0;
            text_size = below_size(size, ui);
            width, height = measure(font, text, text_size, config);
            while text_size > floor_size and (width > size or height > size) do
                text_size = text_size - 1;
                width, height = measure(font, text, text_size, config);
            end
            if width > size or height > size then text = '';
            else text_x, text_y = x + floor((size - width) / 2 + 0.5), y + size - height; end
        end
    end
    slot.text[n], slot.text_size[n], slot.text_x[n], slot.text_y[n] = text, text_size, text_x, text_y;
    return n;
end

-- Adds picked[index] to the slot as icon number n, at x, y and size px, with its countdown. Returns n.
local function place(slot, index, x, y, size, show_timer, ui, font, config)
    local effect = picked[index];
    return put(slot, effect, lights[index] == true, false, effect, x, y, size, show_timer, ui, font, config);
end

-- The height a countdown takes under an icon of size px, 0 when it goes inside or there is none.
local function under(size, show_timer, ui, font, config)
    if not show_timer or size < 14 * ui or size < config.small_icon_inside_px * ui then return 0; end
    local _, height = measure(font, '0s', below_size(size, ui), config);
    return height;
end

-- A line of chosen[first] to chosen[last], centered on the anchor with its icons' tops at top.
local function line(slot, first, last, top, size, gap, show_timer, ui, font, config)
    if last < first then return; end
    local count = last - first + 1;
    local x = -floor((count * size + (count - 1) * gap) / 2);
    for at = first, last do
        place(slot, chosen[at], x, top, size, show_timer, ui, font, config);
        x = x + size + gap;
    end
end

-- Takes up to limit of the picked effects that are debuffs (want true) or buffs (want false) into chosen from at.
-- Returns where the next one goes.
local function take(count, want, limit, at)
    local taken = 0;
    for index = 1, count do
        if taken >= limit then break; end
        if (picked[index].kind == 'debuff') == want then chosen[at], at, taken = index, at + 1, taken + 1; end
    end
    return at;
end

-- Works out one unit's block: which icons, where, and how big, from its anchor.
local function layout(slot, unit, count, kind, config, ui, font)
    slot.count = 0;
    if count == 0 then slot.left, slot.top, slot.right, slot.bottom = 0, 0, 0, 0; return; end
    local size, settings = unit.size, config.layout;
    local gap = settings.icon_gap > 0 and floor(settings.icon_gap * ui + 0.5) or max(1, floor(size * 0.08 + 0.5));
    local show_timer = kind.countdown;
    local height = size + under(size, show_timer, ui, font, config);
    if kind.layout == 'lines' then
        local debuffs = take(count, true, kind.line_debuffs, 1) - 1;
        local last = take(count, false, kind.line_buffs, debuffs + 1) - 1;
        -- The debuff line sits nearest the name, unless swapped; a line with nothing takes no room.
        local low_first, low_last, high_first, high_last = 1, debuffs, debuffs + 1, last;
        if kind.swap_lines then low_first, low_last, high_first, high_last = debuffs + 1, last, 1, debuffs; end
        local top = -height;
        line(slot, low_first, low_last, top, size, gap, show_timer, ui, font, config);
        if low_last >= low_first then top = top - floor(settings.line_gap * ui + 0.5) - height; end
        line(slot, high_first, high_last, top, size, gap, show_timer, ui, font, config);
    elseif kind.layout == 'split' then
        local buffs = take(count, false, kind.split_buffs, 1) - 1;
        local last = take(count, true, kind.split_debuffs, buffs + 1) - 1;
        -- The crowd control slot takes the highest priority debuff of CONTROL or more, oldest first among equals, to
        -- the center; it counts against the debuff limit.
        local control;
        if kind.cc_slot and unit.kind == 'mob' then
            for at = buffs + 1, last do
                local effect = picked[chosen[at]];
                if (effect.priority or 0) >= CONTROL and (not control or effect.priority > picked[chosen[control]].priority) then control = at; end
            end
        end
        if control then
            local moved = chosen[control];
            for at = control, buffs + 2, -1 do chosen[at] = chosen[at - 1]; end
            chosen[buffs + 1] = moved;
        end
        local big = control and floor(size * settings.cc_scale + 0.5) or size;
        local base = -max(under(size, show_timer, ui, font, config), control and under(big, true, ui, font, config) or 0);
        local middle = floor(settings.split_gap * ui + 0.5);
        local half = floor(middle / 2);
        local side = kind.swap_sides and -1 or 1;
        -- Buffs grow out from the left of the gap, debuffs from its right, or the other way when swapped.
        local edge = -half;
        for at = 1, buffs do
            local x = side > 0 and edge - size or -edge;
            place(slot, chosen[at], x, base - size, size, show_timer, ui, font, config);
            edge = edge - size - gap;
        end
        edge = middle - half;
        for at = buffs + 1, last do
            local wide = at == buffs + 1 and big or size;
            local x = side > 0 and edge or -edge - wide;
            place(slot, chosen[at], x, base - wide, wide, show_timer or at == buffs + 1 and control ~= nil, ui, font, config);
            edge = edge + wide + gap;
        end
    else
        -- Single bar: the first limit picked, its debuffs then its buffs, in one row.
        local taken, at = min(count, kind.limit), 0;
        for want = 1, 2 do
            for index = 1, taken do
                if (picked[index].kind == 'debuff') == (want == 1) then at = at + 1; chosen[at] = index; end
            end
        end
        line(slot, 1, at, -height, size, gap, show_timer, ui, font, config);
    end
    local left, top, right = 0, 0, 0;
    for n = 1, slot.count do
        local x, y, wide = slot.x[n], slot.y[n], slot.size[n];
        if n == 1 or x < left then left = x; end
        if n == 1 or x + wide > right then right = x + wide; end
        if n == 1 or y < top then top = y; end
    end
    slot.left, slot.top, slot.right, slot.bottom = left, top, right, 0;
    -- Below the name the block hangs from its anchor instead of standing on it.
    if not above and slot.count > 0 then
        for n = 1, slot.count do slot.y[n], slot.text_y[n] = slot.y[n] - top, slot.text_y[n] - top; end
        slot.top, slot.bottom = 0, -top;
    end
end

-- A party or alliance member's party cooldowns (core/party_cooldowns.lua), when they go over heads: one line of up to
-- six of their abilities' icons, soonest ready first, on the far side of the block from the name, each with its
-- estimated time left. clock holds the time left of the one being placed.
local COOLDOWNS, clock = 6, { effect = 0, remaining = 0 };
local function cooldown_line(slot, entries, unit, kind, config, ui, font, now)
    local count = min(#entries, COOLDOWNS);
    if count == 0 then return; end
    local size, settings = unit.size, config.layout;
    local gap = settings.icon_gap > 0 and floor(settings.icon_gap * ui + 0.5) or max(1, floor(size * 0.08 + 0.5));
    local show_timer = kind.countdown;
    local height = size + under(size, show_timer, ui, font, config);
    local spacing = floor(settings.line_gap * ui + 0.5);
    local top;
    if slot.count == 0 then top = above and -height or 0;
    elseif above then top = slot.top - spacing - height;
    else top = slot.bottom + spacing; end
    local x = -floor((count * size + (count - 1) * gap) / 2);
    for index = 1, count do
        local entry = entries[index];
        clock.remaining = entry.deadline - now;
        put(slot, entry, false, true, clock, x, top, size, show_timer, ui, font, config);
        x = x + size + gap;
    end
    local left, top_edge, right, bottom = slot.left, slot.top, slot.right, slot.bottom;
    local first = slot.count - count + 1;
    for n = first, slot.count do
        local nx, ny, wide = slot.x[n], slot.y[n], slot.size[n];
        if n == 1 or nx < left then left = nx; end
        if n == 1 or nx + wide > right then right = nx + wide; end
        if n == 1 or ny < top_edge then top_edge = ny; end
        if not above and ny + height > bottom then bottom = ny + height; end
    end
    slot.left, slot.top, slot.right, slot.bottom = left, top_edge, right, bottom;
end

-- The binding copies a vector when it is called and keeps none, so these are refilled for every draw.
local corner, far, glow_corner, glow_far, point, UV0, UV1 = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 1, 1 };
local inks = { white = { 1, 1, 1, 1 }, glow = { 0, 0, 0, 0 } };

local function paint(list, slot, unit, config, style, now, font)
    local alpha = unit.alpha;
    local ax, ay = unit.anchor_x, unit.anchor_y;
    local white = theme.u32(inks.white, alpha);
    local text_ink, lit_ink, glow_ink = theme.u32(config.countdown_color, alpha), theme.u32(config.dispel_color, alpha);
    if config.dispel_glow then
        local glow, color = inks.glow, config.dispel_color;
        glow[1], glow[2], glow[3], glow[4] = color[1], color[2], color[3], color[4] * 0.35;
        glow_ink = theme.u32(glow, alpha);
    end
    for n = 1, slot.count do
        local effect, size = slot.effect[n], slot.size[n];
        local x, y = ax + slot.x[n], ay + slot.y[n];
        corner[1], corner[2], far[1], far[2] = x, y, x + size, y + size;
        local lit = slot.lit[n];
        if lit and glow_ink then
            local reach = max(2, floor(size / 8 + 0.5));
            glow_corner[1], glow_corner[2], glow_far[1], glow_far[2] = x - reach, y - reach, x + size + reach, y + size + reach;
            list:AddRectFilled(glow_corner, glow_far, glow_ink, reach);
        end
        local picture = not slot.cooldown[n] and icons.status(effect.icon or effect.effect, style.icon_art);
        if slot.cooldown[n] then
            cooldown_list = cooldown_list or require('ui.cooldown_list');
            recast_icons.draw(list, cooldown_list.icon(effect.ability), style.recast_icon_art, x, y, size, alpha,
                recast_icons.status_art(style));
        elseif picture then
            list:AddImage(picture, corner, far, UV0, UV1, effect_blink.tint(effect, config, now, white));
        end
        if lit then
            local thickness = max(1, floor(size / 12 + 0.5));
            glow_corner[1], glow_corner[2], glow_far[1], glow_far[2] = x - thickness * 0.5, y - thickness * 0.5,
                x + size + thickness * 0.5, y + size + thickness * 0.5;
            list:AddRect(glow_corner, glow_far, lit_ink, 0, 0, thickness);
        end
        local text = slot.text[n];
        if text ~= '' then
            countdown.draw(list, font, text, ax + slot.text_x[n], ay + slot.text_y[n], slot.text_size[n], text_ink, config, true, point);
        end
    end
end

local last_drawn = 0;

-- Draws the plan's blocks in plan.order. subjects are the tracker's rows by unit id (state.party_subjects); compiled
-- and recipients are this frame's shared hide rules and who they apply to. sample marks the preview's plan
-- (ui/overhead_preview.lua): what can be removed lights whenever the light is on, /vg report still counts the
-- real icons, and it goes on the foreground draw list, over the settings window it is turned on from. Returns how
-- many icons it drew.
function draw.draw(plan, subjects, settings, now, compiled, recipients, sample)
    local count = plan.valid and plan.count or 0;
    if not sample then last_drawn = 0; end
    if count == 0 or type(subjects) ~= 'table' then return 0; end
    local imgui = require('imgui');
    local list;
    if sample then list = imgui.GetForegroundDrawList(); else list = imgui.GetBackgroundDrawList(); end
    if not list then return 0; end
    local config, style, units, ui = settings.overhead, settings.style, plan.units, plan.ui;
    compiled = effect_filters.compile(compiled or settings.effect_filters);
    local font = style.font;
    local light = config.dispel_light;
    local ready = light and (sample or dispel.ready(now));
    local near, far = dispel.cleansable(now, sample);
    above = plan.above ~= false;
    measuring(font, config);
    local watch = settings.party_cooldowns;
    local cooldowns = type(watch) == 'table' and watch.enabled and watch.overhead;
    for index = 1, count do
        local unit, slot = units[index], slots[index];
        local kind = config.types[unit.kind];
        local subject = subjects[unit.id];
        local removable = kind.cleanse_light and (unit.kind == 'alliance' and far or near);
        local found = pick(subject, unit, kind, compiled, rule_subject(slot, unit, recipients), ready, light, removable);
        layout(slot, unit, found, kind, config, ui, font);
        if cooldowns and (unit.kind == 'party' or unit.kind == 'alliance') and subject and subject.cooldowns then
            cooldown_line(slot, subject.cooldowns, unit, kind, config, ui, font, now);
        end
    end
    local order, drawn = plan.order, 0;
    for at = 1, count do
        local index = order[at];
        local slot = slots[index];
        if slot.count > 0 then
            paint(list, slot, units[index], config, style, now, font);
            drawn = drawn + slot.count;
        end
    end
    if not sample then last_drawn = drawn; end
    return drawn;
end

-- Icons drawn in the last frame, for /vg report.
function draw.drawn() return last_drawn; end

if VANTAGE_TEST_MODE then
    draw._slots = slots;
end

return draw;
