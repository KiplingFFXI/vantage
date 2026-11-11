-- Where the party list buffs draw and how big: the step they fill beside the game's rows, and a panel of its own for a
-- group, with the words the Party list buffs panel says about them.
local hud = require('ui.native_party_hud');
local countdown = require('ui.countdown_text');
local elements = require('ui.elements');
local party_theme = require('ui.party_theme');
local widget = {};

widget.labels = { size = 'Icon size in a panel of its own', back = 'Put party buffs back beside the party list' };
widget.group_names = { 'Your party', 'Alliance 1', 'Alliance 2' };

local function clamp(value, low, high) return math.max(low, math.min(high, value)); end

-- A size in pixels as the player reads it: whole numbers plain, anything else to one decimal.
local function px(value)
    if value == math.floor(value) then return string.format('%d', value); end;
    return (string.format('%.1f', value):gsub('%.0$', ''));
end

-- "14" when the rooms of every measured step are the same, "14 to 18" when they differ, nil when none is measured.
local function span(rooms)
    local low, high;
    for _, entry in ipairs(rooms) do
        if entry.pitch then low, high = math.min(low or entry.room, entry.room), math.max(high or entry.room, entry.room); end;
    end;
    if not low then return nil; end;
    return low == high and px(low) or px(low) .. ' to ' .. px(high);
end

-- For each shown strip the game's party list has, the room its members' icons get (ui/native_party_hud.lua), in a
-- list kept from call to call. Empty until the game's party list has been read.
local kept_rooms = {};
function widget.rooms(settings, callbacks)
    local status = callbacks and callbacks.party_native_status and callbacks.party_native_status();
    return hud.rooms(settings.party_ui, type(status) == 'table' and status.geometry or nil, kept_rooms);
end

-- The line about the icons beside the game's rows, with the size they draw at once the game's step from one row to the
-- next is measured.
function widget.step(p, rooms)
    local numbers = span(rooms);
    return "Beside the game's party list the icons fill the step from one row to the next"
        .. (numbers and ' (' .. numbers .. ' px here)' or '') .. ', with no space between them.';
end

-- Whether any group whose strip is shown is in a panel of its own.
function widget.in_panels(p)
    for group = 1, 3 do if hud.shown(p, group) and p.groups[group].native_detached then return true; end; end;
    return false;
end

-- "Your party and Alliance 1" from a list of names.
function widget.named(names)
    if #names < 2 then return names[1] or ''; end;
    return table.concat(names, ', ', 1, #names - 1) .. ' and ' .. names[#names];
end

-- Which shown groups are in panels of their own, by name, or nil when none is.
function widget.panel_line(p)
    local names = {};
    for group = 1, 3 do
        if hud.shown(p, group) and p.groups[group].native_detached then names[#names + 1] = widget.group_names[group]; end;
    end;
    if #names == 0 then return nil; end;
    return widget.named(names) .. (#names == 1 and ' is in a panel of its own.' or ' are in panels of their own.');
end

-- Puts every group in a panel of its own back beside the game's rows. The strips' saved offsets stay as they are,
-- and so does each panel's saved size and place, for the next time. The lock is left as it is.
function widget.back(p)
    for group = 1, 3 do p.groups[group].native_detached = false; end;
end

-- A panel's height for members, one line of effects each: the panel's top padding, then per member a name line, its
-- gap, the icons with a countdown under each, and the space under them (ui/native_party_hud.lua detached_rows).
-- global_style is the timer panels' look, which the party list buffs wear.
local function panel_height(p, saved, members, global_style)
    local e = p.effects;
    local look = party_theme.party(p, global_style);
    local cell = tonumber(e.icon_size) or 32;
    if e.timers and e.icon_countdown_position ~= 'inside' then
        local timer = countdown.icon_metrics(look.font, '57', cell, e);
        cell = cell + timer.gap + math.ceil(timer.height);
    end;
    return 6 + members * (look.font_size + 2 + 3 + cell + 8);
end

-- How many members a group's panel lists: its rows in the game's list, less your own when it is hidden. nil when the
-- game's list doesn't have the group.
local function members(p, group, rooms)
    for _, entry in ipairs(rooms or {}) do
        if entry.group == group then return math.max(1, entry.members - (group == 1 and p.include_self == false and 1 or 0)); end;
    end;
    return nil;
end

local function overlap(a, b)
    return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height;
end

-- The first of up to three places, by group or in a list, that rect covers.
local function covered(rect, places)
    for index = 1, 3 do if places[index] and overlap(rect, places[index]) then return places[index]; end; end;
    return nil;
end

-- Puts a group's buffs in a panel of its own where its strip is drawn now. The panel is as wide as the strip can grow
-- (Longest row), within the screen on the strip's side of the game's list, and keeps the strip's edge
-- next to that list. It is as tall as its members' effects shown now need at that width, and never less than a line
-- each. Where the screen has no room under it, it goes up, so its saved place is where it draws. A strip not drawn now
-- keeps the panel's saved place and width, and a group the game's list doesn't have keeps its saved height. The lock
-- is left as it is. global_style is the timer panels' style, which the party list buffs wear.
-- A panel over another shown group's strip or panel moves sideways away from the game's list past it, the strip gap
-- clear, and stays on the screen. With no room sideways it goes back beside the list and up past what it covers. With no
-- room above either, the panels there share the height the strips there leave, the first lowest as in the game's
-- list, each above any strip it would cover and still at least a line per member. Another group's panel keeps its
-- height when it is less.
function widget.place(p, group, rooms, global_style)
    local screen = require('imgui').GetIO().DisplaySize;
    local screen_width, screen_height = math.max(40, screen.x), math.max(40, screen.y);
    -- Where each other shown group is drawn now, strip or panel.
    local spots = {};
    for other = 1, 3 do
        local at = other ~= group and hud.shown(p, other) and elements.drawn('strip_' .. other);
        if at then
            spots[other] = { group = other, panel = p.groups[other].native_detached, x = at.x, y = at.y, width = at.width, height = at.height };
        end;
    end;
    local saved = p.groups[group];
    local drawn = elements.drawn('strip_' .. group);
    local left = saved.native_side == 'left' or saved.native_side ~= 'right' and p.native.side == 'left';
    if drawn then
        local beside = left and drawn.x + drawn.width or screen_width - drawn.x;
        saved.detached_width = clamp(math.floor(math.min(p.native.width, beside, screen_width)), 40, 900);
    end;
    local count = members(p, group, rooms);
    if count then
        -- The panel's own layout says the width it settles on, at least its smallest, and its contents' height.
        local width, content = hud.panel_size(p, group, saved.detached_width, screen_width, screen_height, global_style);
        if width then saved.detached_width = clamp(math.floor(width), 40, 900); end;
        saved.detached_height = clamp(math.max(math.ceil(content or 0), panel_height(p, saved, count, global_style)), 40,
            math.max(40, math.min(16000, screen_height)));
    end;
    if drawn then
        local x = left and drawn.x + drawn.width - saved.detached_width or drawn.x;
        local spot = { group = group, panel = true, width = saved.detached_width, height = saved.detached_height,
            x = clamp(math.floor(x), 0, math.max(0, screen_width - saved.detached_width)),
            y = clamp(math.floor(drawn.y), 0, math.max(0, screen_height - saved.detached_height)) };
        local home, top, gap, over = spot.x, spot.y, p.native.gap, nil;
        repeat
            over = covered(spot, spots);
            if over then spot.x = left and math.floor(over.x - gap - spot.width) or math.ceil(over.x + over.width + gap); end;
        until not over or spot.x < 0 or spot.x + spot.width > screen_width;
        if over then
            -- No room sideways: back beside the list, and up past what it covers while the screen has room.
            spot.x = home;
            repeat
                over = covered(spot, spots);
                if over then spot.y = math.floor(over.y - gap - spot.height); end;
            until not over or spot.y < 0;
        end;
        if over then
            -- No room above either: the panels beside the list, this one too, share the height the strips there
            -- leave, stacked up from the bottom of the screen and over those strips.
            spot.y = top;
            local column, strips, room = {}, {}, screen_height;
            for other = 1, 3 do
                local item = other == group and spot or spots[other];
                if item and item.x < spot.x + spot.width and spot.x < item.x + item.width then
                    if item.panel then column[#column + 1] = item; else strips[#strips + 1], room = item, room - item.height - gap; end;
                end;
            end;
            if #column > 1 or #strips > 0 then
                local share, bottom = math.floor((room - (#column - 1) * gap) / #column), screen_height;
                for _, item in ipairs(column) do
                    local least = members(p, item.group, rooms);
                    least = least and panel_height(p, p.groups[item.group], least, global_style) or 40;
                    if item.group ~= group then least = math.min(least, item.height); end;
                    item.height = clamp(math.max(least, math.min(item.height, share)), 40, math.max(40, math.min(16000, screen_height)));
                    item.y = bottom - item.height;
                    repeat
                        local strip = covered(item, strips);
                        if strip then item.y = math.floor(strip.y - gap - item.height); end;
                    until not strip or item.y < 0;
                    item.y = math.max(0, item.y);
                    bottom = item.y - gap;
                    p.groups[item.group].detached_y, p.groups[item.group].detached_height = item.y, item.height;
                end;
            end;
        end;
        saved.detached_x, saved.detached_y = spot.x, spot.y;
    end;
    saved.native_detached = true;
end

return widget;
