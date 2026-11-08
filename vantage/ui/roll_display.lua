-- The Phantom Roll display (settings.rolls): for each roll core/rolls.lua shows, the roll's icon, name and total, the
-- time left to Double-Up or on a bust, then what it gives, its lucky and unlucky numbers with the chance that one more
-- Double-Up busts, and the party members, those who didn't get it dimmed. It uses the timer panels' look, and its
-- countdown text follows More look on the main page. Rolls past the limit or the room are left out with nothing in their place.
-- It moves and resizes like the party cooldown list (ui/element_box.lua) and takes no clicks otherwise.
local display = {};
local theme = require('ui.theme');
local fonts = require('ui.fonts');
local metrics = require('ui.text_metrics');
local countdown = require('ui.countdown_text');
local icons = require('ui.icons');
local catalog = require('core.catalog');
local rolls = require('core.rolls');
local box = require('ui.element_box');
local conditions = require('core.conditions');
local floor, max, min = math.floor, math.max, math.min;
local LABEL = 'Phantom Roll';
local frame = box.new(LABEL, '##vantage_rolls', 'Phantom Roll layout', 'rolls');
local empty = {};
local look = { font = 'Agave' };
local corner, far, UV0, UV1, WHITE = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 1, 1 }, { 1, 1, 1, 1 };

function display.cancel_gesture() frame:cancel(); end

-- The lines one roll takes after its first: what it gives, its numbers, its members.
local function extra_lines(entry, config)
    local count = 0;
    if config.show_effect and entry.gives then count = count + 1; end
    if config.show_numbers and not entry.bust or config.show_odds and entry.odds then count = count + 1; end
    if config.show_members and #entry.members > 0 then count = count + 1; end
    return count;
end

local numbers_text = {};
-- 'Lucky 4  Unlucky 8  Bust chance 33%', made once for each roll and chance.
local function numbers_line(entry, config)
    local key = (config.show_numbers and not entry.bust and entry.ability or 0) * 1000 + (config.show_odds and entry.odds and entry.odds + 1 or 0);
    local text = numbers_text[key];
    if not text then
        local parts = {};
        if config.show_numbers and not entry.bust then parts[#parts + 1] = 'Lucky ' .. entry.info.lucky .. '  Unlucky ' .. entry.info.unlucky; end
        if config.show_odds and entry.odds then parts[#parts + 1] = 'Bust chance ' .. entry.odds .. '%'; end
        text = table.concat(parts, '  ');
        numbers_text[key] = text;
    end
    return text;
end

-- Each total's text, and the heading with the samples on, made once.
local TOTALS = {};
for total = 1, 11 do TOTALS[total] = tostring(total); end
local SAMPLE_LABEL = LABEL .. '  /  Sample';
local function totals(entry)
    return entry.bust and 'Bust' or TOTALS[entry.total] or tostring(entry.total);
end

-- Draws the display and returns the roll under the mouse, for its tooltip. moving holds what hud.draw worked out.
function display.draw(view, settings, now, callbacks, moving)
    local config = settings.rolls;
    if type(config) ~= 'table' or not config.enabled then frame:cancel(); return nil; end
    -- When to show hides it, unless samples or edit mode show it.
    if not config.preview and not moving.editing and not conditions.shown('rolls') then frame:cancel(); return nil; end
    local entries = config.preview and rolls.samples(now) or view and view.rolls or empty;
    local s = settings.style;
    local scale = s.scale;
    local font_size = s.font_size * scale;
    local total_size = floor(font_size * 1.35 + 0.5);
    local icon = floor(s.icon_size * 0.75 + 0.5) * scale;
    local first = max(icon, total_size + 4 * scale);
    local line = font_size + 4 * scale;
    local heading = config.show_heading and not s.minimal
        and ((s.title_size > 0 and s.title_size or s.font_size) + 10) * scale or 4 * scale;
    local count = min(#entries, config.max_rolls);
    local wanted = heading + 4 * scale;
    for index = 1, count do wanted = wanted + first + extra_lines(entries[index], config) * line + 6 * scale; end
    if count == 0 then wanted = wanted + first; end
    local rect, movable = frame:place(config, settings, callbacks, moving, wanted, count > 0, 200);
    if not rect then return nil; end
    look.font = s.font;
    fonts.push(look.font, font_size);
    local hovered;
    local list = frame:open(rect, movable, s, config.preview);
    if list then
        local x, y, width = rect.x, rect.y, rect.width;
        local bottom = y + rect.height + 0.001;
        if config.show_heading and not s.minimal then
            local size = (s.title_size > 0 and s.title_size or s.font_size) * scale;
            box.text(list, look, config.preview and SAMPLE_LABEL or LABEL, x + 8 * scale, y + 4 * scale, size, theme.u32(s.title_color), width - 16 * scale);
        end
        local text_ink, detail_ink, value_ink = theme.u32(s.label_color or s.text_color), theme.u32(s.detail_color or s.text_color), theme.u32(s.value_color or s.text_color);
        local missed_ink, white = theme.u32(config.missed_color), theme.u32(WHITE);
        local left, right = x + 6 * scale, x + width - 6 * scale;
        local top = y + heading;
        for index = 1, count do
            local entry = entries[index];
            local height = first + extra_lines(entry, config) * line;
            if top + height > bottom then break; end
            -- The roll's icon, its name and its total, and the time left at the right.
            corner[1], corner[2], far[1], far[2] = left, top + (first - icon) / 2, left + icon, top + (first - icon) / 2 + icon;
            local picture = icons.status(catalog.roll(entry.ability), s.icon_art);
            if picture then list:AddImage(picture, corner, far, UV0, UV1, white); end
            local name_x = left + icon + 6 * scale;
            local clock, label = '', '';
            if entry.window_deadline and entry.window_deadline > now then clock, label = box.time(entry.window_deadline - now), 'Double-Up';
            elseif entry.bust and entry.bust_deadline and entry.bust_deadline > now then clock, label = box.time(entry.bust_deadline - now), 'Bust'; end
            local clock_width = clock ~= '' and countdown.measure(look.font, clock, font_size, config) or 0;
            local label_width = label ~= '' and metrics.width(look.font, label, font_size, font_size) or 0;
            local timer_x = right - clock_width;
            local name_y = top + max(0, (first - font_size) / 2);
            if clock ~= '' then
                countdown.draw(list, look.font, clock, timer_x, name_y, font_size, value_ink, config, false, box.point);
                box.text(list, look, label, timer_x - label_width - 4 * scale, name_y, font_size, detail_ink, label_width + 2);
            end
            local room = (clock ~= '' and timer_x - label_width - 10 * scale or right) - name_x;
            local name = entry.info.name;
            local name_width = min(metrics.width(look.font, name, font_size, font_size), max(0, room - total_size * 2));
            box.text(list, look, name, name_x, name_y, font_size, text_ink, name_width + 1);
            local total_ink = entry.bust and theme.u32(config.unlucky_color) or entry.total == entry.info.lucky and theme.u32(config.lucky_color)
                or entry.total == entry.info.unlucky and theme.u32(config.unlucky_color) or theme.u32(s.title_color);
            box.text(list, look, totals(entry), name_x + name_width + 8 * scale, top + max(0, (first - total_size) / 2), total_size, total_ink,
                room - name_width - 8 * scale);
            if box.over(moving, movable, x, top, width, height) then hovered = entry; end
            local at = top + first;
            if config.show_effect and entry.gives then
                box.text(list, look, entry.gives, name_x, at + 2 * scale, font_size, detail_ink, right - name_x);
                at = at + line;
            end
            if config.show_numbers and not entry.bust or config.show_odds and entry.odds then
                box.text(list, look, numbers_line(entry, config), name_x, at + 2 * scale, font_size, detail_ink, right - name_x);
                at = at + line;
            end
            if config.show_members and #entry.members > 0 then
                -- Each member's name in turn, cut at the last one that fits.
                local member_x = name_x;
                for _, member in ipairs(entry.members) do
                    local member_width = metrics.width(look.font, member.name, font_size, font_size);
                    if member_x + member_width > right + 0.001 then break; end
                    box.text(list, look, member.name, member_x, at + 2 * scale, font_size, member.state == 'got' and text_ink or missed_ink, member_width + 1);
                    member_x = member_x + member_width + 8 * scale;
                end
            end
            top = top + height + 6 * scale;
        end
    end
    frame:close(list, rect, movable, s, config.preview, config);
    fonts.pop();
    return hovered;
end

return display;
