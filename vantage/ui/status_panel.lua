-- The editor of the status timer panels: Self buffs, Self debuffs, Target timers, Party members' timers and Watched enemy
-- timers, each under its own name on the panel frame. The rows are made once and shared by the five; ui/recast_panel.lua
-- builds its own Size, Look and Filters from the same functions.
local conditions_ui = require('ui.condition_settings');
local controls = require('ui.controls');
local defaults = require('ui.defaults');
local effect_editor = require('ui.effect_settings');
local fields = require('ui.fields');
local frame = require('ui.panel_frame');
local page = {};
local ctx = frame.ctx;
local self_panels = { self_buffs = true, self_debuffs = true };

local function icons(c) return c.p.mode == 'icons'; end;
local function text_layout(c) return c.p.mode == 'text'; end;
local function not_icons(c) return c.p.mode ~= 'icons'; end;
local function bars(c) return c.p.mode == 'bars' or c.p.mode == 'expanded'; end;
local function root(c) return c.s; end;
local function only_on(id) return function(c) return c.id == id; end; end;
page.icons, page.bars, page.root = icons, bars, root;

-- What a row and its box draw, as ui/hud.lua and ui/fields.lua go by it. A row for one of them shows while it is drawn.
local function fill_on(c) return bars(c) and c.p.show_fill; end;
local function text_on(c) return text_layout(c) or bars(c) and c.p.show_text ~= false; end;
local function boxed(c) return not_icons(c) and not c.s.style.minimal; end;
local function headed(c) return boxed(c) and c.p.show_heading; end;
local function box_has(part)
    return function(c) return boxed(c) and (select(part, require('ui.hud').panel_box(c.p, c.s.style))); end;
end;
-- Ending soon shows on a bar or on a countdown.
local function soon_shows(c) return icons(c) or fill_on(c) or text_on(c); end;
-- A lit icon's glow goes behind its picture. A row with no picture lights its edge.
local function pictured(c) return icons(c) or bars(c) and c.p.show_icon; end;
-- An effect's color shows on a bar, or on a countdown while countdowns take the row's color.
local function tinted(c) return fill_on(c) or c.s.style.status_time_color and soon_shows(c); end;

-- A recast row is always your own, so a recast panel never offers who it is on or who cast it.
local function offered(c, key)
    return not (defaults.recast_panels[c.id] and (key == 'target' or key == 'source'));
end;

local function part_shown(c, key)
    if c.p.mode == 'text' then return key == 'name' or key == 'time'; end;
    return c.p['show_' .. key];
end;

-- Whether any of the row's text but the name and countdown shows.
local function detail_shown(c)
    for _, key in ipairs(defaults.field_ids) do
        if key ~= 'name' and key ~= 'time' and offered(c, key) and part_shown(c, key) then return true; end;
    end;
    return false;
end;

-- A table of the panel, by name, for the rows that write into it.
local panel_table = frame.panel_table;

-- An effect id's key can be a number or, after a save, text.
local function in_map(map, id) return map[id] == true or map[tostring(id)] == true; end;
local function set_map(map, id, on) map[id], map[tostring(id)] = on or nil, nil; end;

-- The name a player reads for an effect the settings hold. The game has no name for some recasts, and what they fall
-- back to is a word and a number.
local no_name = { '^Recast %d+$', '^Spell %d+$', '^Ability timer %d+$', '^Item %d+$' };
local function plain_name(c, id, domain)
    local name = c.effect_name(id, domain);
    for _, pattern in ipairs(no_name) do
        if name:find(pattern) then return 'A recast with no name'; end;
    end;
    return name;
end;
page.plain_name = plain_name;

-- A line above a list, with the search's light on it.
local function caption(imgui, c, item)
    if imgui.AlignTextToFramePadding then imgui.AlignTextToFramePadding(); end;
    imgui.TextUnformatted(item.text);
    frame.lit(c, item);
    c.tip(item.help);
end;
page.caption = caption;

-- Puts the next item beside the last one while it fits. Returns how much of the line is used.
local function flow(imgui, used, width, available)
    if used > 0 and used + width <= available then
        imgui.SameLine();
        return used + width;
    end;
    return width;
end;

-- Show.

local mode_names = { bars = 'Bars', expanded = 'Expanded bars', icons = 'Icons', text = 'Text' };
local mode_list = { 'bars', 'expanded', 'icons', 'text' };
local mode_help = 'Icons shows each icon and its countdown, with no frame, name or bar. Text shows each name and countdown. Your bar settings stay saved either way.';
local empty_names = { hide = 'Hide', show = 'Keep the empty panel' };

function page.layout_row()
    return frame.pick('Layout', 'mode', mode_list, mode_names, mode_help, { alias = 'Compact bars Expanded bars Icons only Text only' });
end;

function page.empty_row()
    return frame.pick('When empty', 'empty', { 'hide', 'show' }, empty_names, 'Samples and unlocked Shift placement still show the panel.', { only = boxed, shown_by = 'Layout' });
end;

function page.most_row(help)
    return frame.number('Most shown', 'max_rows', 1, 64, help, {
        alias = 'Maximum visible effects Maximum visible cooldowns rows limit' });
end;

-- Why a layout has no ticks for the parts of a row. Pointing at a row says the rest, while that's on.
function page.part_notes(icon_text, text_text)
    local function say(text, point)
        return function(c) return c.s.style.hover and text .. ' Point at ' .. point .. ' for the rest.' or text; end;
    end;
    return frame.note(say(icon_text, 'one'), { only = icons }), frame.note(say(text_text, 'a row'), { only = text_layout });
end;

-- My order with nothing on it sorts by name.
page.empty_order = frame.note('Nothing is on My order yet, so rows go by name. Add them on the Filters tab.', {
    only = function(c) return c.p.sort == 'fixed' and #c.p.order == 0; end });

-- Why a bar row has no ticks for its text.
page.no_text_note = frame.note('Row text is off under Look, so only the icon can change here.', {
    only = function(c) return bars(c) and c.p.show_text == false; end });

local sort_list = { 'longest', 'oldest', 'remaining', 'name', 'fixed' };
local sort_names = { longest = 'Longest remaining', oldest = 'Oldest first', remaining = 'Ending soonest', name = 'Name', fixed = 'My order' };
local all_groups, one_unit_groups = { 'none', 'target', 'group' }, { 'none', 'group' };
local group_names = { none = 'Together', target = 'By who it is on', group = 'By kind of effect' };

local function part_tick(text, key, help, options)
    options = options or {};
    options.shown_by = key == 'icon' and 'Layout' or 'Show row text';
    -- Every part but the icon is row text.
    if key ~= 'icon' then
        local also = options.only;
        options.only = also and function(c) return text_on(c) and also(c); end or text_on;
    end;
    return frame.tick(text, 'show_' .. key, help or 'Show this part of the row when it is known.', options);
end;
page.part_tick = part_tick;

-- A self panel's rows are all on you, so it never offers this part.
local function not_self(c) return not self_panels[c.id]; end;

-- For a display the Hide list reaches, while that's paused.
local function list_used(c) return c.s.effect_filters.enabled; end;
page.list_used = list_used;

function page.list_paused()
    return frame.problem(function(c) return not list_used(c); end, 'The Hide list is paused, so it hides nothing now.', 'Use it again',
        'Puts your hide rules back to work.', 'Edit the list', function(s) s.effect_filters.enabled = true; end);
end;

local function has_target(c)
    local context = c.view and c.view.context;
    local target = context and context.target;
    return target and target.id and target.kind ~= 'player' and target;
end;

-- Watches your target, for a button that says so.
function page.watch_target(c)
    local target = has_target(ctx);
    if target then c.call('watch', target.id); else c.note('Target an enemy first.'); end;
end;

-- Members ticked by name from the party list. One ticked before who isn't in the party now has only the line that says so.
local member_seen = {};
local member_flag = { false };

local function member_tick(imgui, c, p, id, label)
    member_flag[1] = in_map(p.members, id);
    if controls.checkbox(imgui, c.look, label, member_flag) then
        local on = member_flag[1];
        c.changed(function() set_map(p.members, id, on); end, true, 'Members');
    end;
    c.tip('Ticking anyone shows only those ticked.');
end;

local function draw_members(imgui, c, item)
    local p = ctx.p;
    caption(imgui, c, item);
    for id in pairs(member_seen) do member_seen[id] = nil; end;
    local context = ctx.view and ctx.view.context;
    local used, available = imgui.CalcTextSize(item.text) + 8, imgui.GetContentRegionAvail();
    local listed = false;
    -- Include me puts your own rows on the panel, so you're on the list while it's on.
    if p.include_self and context and context.id then
        listed = true;
        member_seen[context.id] = true;
        local name = context.name or 'You';
        used = flow(imgui, used, imgui.CalcTextSize(name) + imgui.GetFrameHeight() + 20, available);
        member_tick(imgui, c, p, context.id, name .. '##member_' .. context.id);
    end;
    for _, member in ipairs(context and context.party or {}) do
        -- Alliance members never show on this panel, and ticking one would leave it empty.
        if member.scope == 'party' then
            listed = true;
            member_seen[member.id] = true;
            local name = member.name or 'A party member';
            used = flow(imgui, used, imgui.CalcTextSize(name) + imgui.GetFrameHeight() + 20, available);
            member_tick(imgui, c, p, member.id, name .. '##member_' .. member.id);
        end;
    end;
    -- Remove waits for the list to be drawn. Taking someone off adds a key to the table pairs is walking, and Lua doesn't
    -- say what the walk does then.
    local gone;
    for key, on in pairs(p.members) do
        local id = tonumber(key) or key;
        if on and not member_seen[id] then
            listed = true;
            imgui.PushID('member_' .. tostring(id));
            -- Your own tick, left on while Include me is off. It hides nobody then (ui/hud.lua filter_rows).
            if context and id == context.id then
                imgui.TextUnformatted((context.name and context.name .. ' is' or 'You are') .. ' ticked, but Include me is off');
            else
                imgui.TextUnformatted('Someone not in your party now');
            end;
            imgui.SameLine();
            if imgui.Button('Remove##member') then gone = id; end;
            imgui.PopID();
        end;
    end;
    if gone then c.changed(function() set_map(p.members, gone, false); end, true, 'Members'); end;
    if not listed then frame.shaded(imgui, c, 'Nobody in your party right now.'); end;
end;

-- Once the game has dropped an enemy, it goes by what Vantage saw of it.
local function watched_name(c, id)
    local context = ctx.view and ctx.view.context;
    local entity = context and context.entities and context.entities[id];
    local name = entity and entity.name or ctx.callbacks and ctx.callbacks.unit_name and ctx.callbacks.unit_name(id);
    if name then return name; end;
    for _, seen in ipairs(ctx.view and ctx.view.subjects or {}) do if seen.id == id then return seen.name; end; end;
    return nil;
end;

local function draw_watching(imgui, c, item)
    caption(imgui, c, item);
    for index, id in ipairs(ctx.s.watch_ids) do
        imgui.PushID('watch_' .. index);
        imgui.TextUnformatted(watched_name(c, id) or 'An enemy that is out of range now');
        imgui.SameLine();
        if imgui.Button('Stop watching##watch') then c.call('unwatch', id); end;
        imgui.PopID();
    end;
end;

-- This panel's timers as text on the clipboard, plain or with where each time came from.
local function copy_timers(c, details)
    if c.call('copy_shown', ctx.id, details) then c.note('Copied to the clipboard.', 'done_messages'); end;
end;
page.copy_line = frame.line(nil, nil, {
    frame.button('Copy shown timers', 'Copies the timers this panel shows now, as text you can paste anywhere.', function(c) copy_timers(c, false); end),
    frame.button('Copy timer details', 'Copies them with where each time came from and how sure Vantage is of it.', function(c) copy_timers(c, true); end),
});

local show_rows = {
    page.layout_row(),
    frame.pick('Sort', 'sort', sort_list, sort_names, 'Longest remaining sorts 4h, 3m, then 57s. Effects without a countdown go last. Oldest first goes by when each was first seen. Pinned rows and grouping come first.',
        { alias = 'Sort effects' }),
    page.empty_order,
    frame.pick('Group rows', 'group_by', nil, group_names, 'Keeps related rows together before sorting within them.',
        { choices_of = function(c) return (self_panels[c.id] or c.id == 'target') and one_unit_groups or all_groups; end, alias = 'By target By effect group' }),
    page.most_row('Rows past this are not shown.'),
    page.empty_row(),
    frame.line('Each row shows', 'Which parts of a row show. Row text under Look places them.', {
        part_tick('Icon', 'icon'), part_tick('Name', 'name', nil, { alias = 'Effect name' }),
        part_tick('Who it is on', 'target', nil, { alias = 'Target name', only = not_self }),
        part_tick('Countdown', 'time', nil, { alias = 'Time remaining' }),
        part_tick('Who cast it', 'source', nil, { alias = 'Caster' }),
        part_tick('Time elapsed', 'elapsed'),
        part_tick('Full length', 'total', nil, { alias = 'Full duration' }),
    }, { only = bars, shown_by = 'Layout', alias = 'Visible fields fields' }),
};
local icon_note, text_note = page.part_notes('Icons always shows the icon and its countdown.', 'Text always shows the name and its countdown.');
show_rows[#show_rows + 1], show_rows[#show_rows + 2], show_rows[#show_rows + 3] = icon_note, text_note, page.no_text_note;
for _, item in ipairs({
    frame.tick('Light up buffs you can remove', 'dispel_light', 'A mob\'s buff lights up when your job and level can take it off now: Dispel, Magic Finale, Blank Gaze or Dark Shot, learned or set. Debuffs never light.', {
        only = function(c) return c.id == 'target' or c.id == 'watch'; end, alias = 'Mob buffs dispel dispellable lit light up Magic Finale Blank Gaze Dark Shot' }),
    frame.tick('Light up debuffs you can remove', 'dispel_light', 'A debuff lights up when your job and level can take it off now with a spell you\'ve learned: Poisona, Paralyna, Blindna, Silena, Cursna, Viruna, Stona or Erase.', {
        only = function(c) return c.id == 'self_debuffs' or c.id == 'party'; end, alias = 'cleanse erase poisona paralyna blindna silena cursna viruna stona white mage whm lit' }),
    frame.tick('Hide while I target myself', 'hide_self', 'Your own effects already show on Self buffs and Self debuffs.', {
        only = only_on('target'), alias = 'Hide target timers when targeting myself self own target' }),
    frame.note('Hidden now, because you\'re targeting yourself.', {
        only = function(c) return c.id == 'target' and defaults.hides_own_target(c.s, c.view and c.view.context); end }),
    frame.tick('Include me', 'include_self', 'Adds your own buffs and debuffs to this panel under your name, with the game\'s own times. Self buffs and Self debuffs still show them.', {
        only = only_on('party'), alias = 'Add myself my own effects self me my row wheel' }),
    frame.custom('Members', 'Leave everyone unticked to show every member.', draw_members, { only = only_on('party'), alias = 'Selected members Show all members party members', resets = { 'members' } }),
    frame.tick('One row for a cast on several members', 'fold_casts', 'A Protectra shows as one Protect row that counts who has it. With Show details when I point at a timer on, point at the row for each member. A spell cast on one member at a time keeps a row each.', {
        only = only_on('party'), alias = 'Fold group combine merge collapse Protectra Shellra songs rolls party-wide area' }),
    frame.custom('Watching', 'Watch keeps what was seen on an enemy when you change targets. It does not show effects nobody saw land.', draw_watching, {
        only = only_on('watch'), alias = 'Watched enemies watch' }),
    frame.note('Nobody is watched now, so this panel stays empty. The list clears when you change zones.', {
        only = function(c) return c.id == 'watch' and #c.s.watch_ids == 0 and not c.p.list_debuffed; end }),
    frame.button('Watch my target', 'Adds your target to this list.', page.watch_target, { only = only_on('watch'), alias = 'Watch enemy mob' }),
    frame.tick('Also list enemies I debuff', 'list_debuffed', 'An enemy with a debuff you cast shows here without watching it, for as long as the debuff lasts.', {
        only = only_on('watch'), alias = 'enemy mob mobs debuff debuffs debuffed sleep crowd control without watching' }),
    page.copy_line,
}) do show_rows[#show_rows + 1] = item; end;

-- Size and place: the size rows, what page.place_rows adds, then the countdown rows under their heading.

-- Width is one pick. The chat log's width takes over from the others, as ui/hud.lua goes by it last, so Same as the
-- chat log is a choice while the panel moves with the chat log.
local width_list, width_chat = { 'fixed', 'fits' }, { 'fixed', 'fits', 'chat' };
local width_names = { fixed = 'Fixed', fits = 'Fits the rows', chat = 'Same as the chat log' };
local function width_of(c)
    if c.p.dock_match_width and c.p.anchor.to == 'chat' then return 'chat'; end;
    return c.p.auto_width and 'fits' or 'fixed';
end;
local function width_is(value) return function(c) return width_of(c) == value; end; end;
local function least_width(c) return c.p.mode == 'icons' and 24 or 160; end;
local function least_height(c) return c.p.mode == 'icons' and 24 or 80; end;
local function grows(c) return c.p.auto_height ~= false; end;
-- Column width shows while rows fill across, or once they don't all fit in the height, even with one column and the
-- rest left out (ui/hud.lua hud.split_columns).
local function in_columns(c) return c.p.mode ~= 'icons' and (c.p.stack_direction == 'horizontal' or require('ui.hud').split_columns(c.id) ~= nil); end;

local function size_rows()
    -- The note's words for the columns it last said, as it asks each frame.
    local split = { columns = nil, text = nil };
    return {
        frame.scale_line,
        frame.pick('Width', nil, nil, width_names, 'Fixed keeps your width. Fits the rows grows and shrinks with them, between Narrowest and Widest. Same as the chat log is there while it moves with the chat log.', {
            alias = 'Panel width Fit the width to what it shows Fit width to contents Same width as the chat log Match chat width automatic',
            choices_of = function(c) return c.p.anchor.to == 'chat' and width_chat or width_list; end, resets = { 'auto_width', 'dock_match_width' },
            read = width_of,
            write = function(c, value) c.p.auto_width, c.p.dock_match_width = value == 'fits', value == 'chat'; end }),
        frame.number('Fixed width', 'width', 160, 2400, nil, { alias = 'Panel width', shown_by = 'Width', low_of = least_width, only = width_is('fixed') }),
        frame.number('Narrowest', 'min_width', 160, 2400, 'The least it shrinks to.', { alias = 'Minimum automatic width', shown_by = 'Width',
            low_of = least_width, only = width_is('fits'),
            write = function(c, value) c.p.min_width, c.p.max_width = value, math.max(c.p.max_width, value); end }),
        frame.number('Widest', 'max_width', 160, 2400, 'The most it grows to.', { alias = 'Maximum automatic width', shown_by = 'Width',
            low_of = least_width, only = width_is('fits'),
            write = function(c, value) c.p.max_width, c.p.min_width = value, math.min(c.p.min_width, value); end }),
        frame.number('Column width', 'item_width', 80, 1400, 'Each column of rows is at least this wide, so a wider one makes fewer columns. The panel\'s width is the room they share.', {
            alias = 'Bar width', only = in_columns, shown_by = { 'Fills', 'Layout' } }),
        frame.note(function(c)
            local columns = require('ui.hud').split_columns(c.id);
            if not columns then return nil; end;
            if split.columns ~= columns then
                split.columns, split.text = columns, columns == 1
                    and 'The rows don\'t fit this panel\'s height, and there\'s room across for one column only, so the rest are left out. More height shows more, and so does room across for a second column.'
                    or ('The rows don\'t fit this panel\'s height, so they go down in %d columns that share its width. More height fits them in one, and a wider panel widens the columns. A Column width too wide makes fewer columns and leaves rows out.'):format(columns);
            end;
            return split.text;
        end, { live = true }),
        frame.pick('Height', nil, { 'grows', 'fixed' }, { grows = 'Grows with its rows', fixed = 'Fixed' }, 'Grows with its rows stops at Tallest. Fixed keeps the height you set, however few rows show.', {
            alias = 'Fit the height to what it shows Fit panel height to contents automatic fixed height', resets = { 'auto_height' },
            read = function(c) return grows(c) and 'grows' or 'fixed'; end,
            write = function(c, value) c.p.auto_height = value == 'grows'; end }),
        frame.number('Tallest', 'height_limit', 80, 16000, 'The most it grows to.', { alias = 'Maximum panel height', edge = 'y', low_of = least_height, only = grows, shown_by = 'Height' }),
        frame.number('Fixed height', 'height_limit', 80, 16000, nil, { alias = 'Panel height', edge = 'y', low_of = least_height, shown_by = 'Height',
            only = function(c) return not grows(c); end }),
        frame.note('Moving or resizing it on the screen stops it moving with anything. Resizing by a side sets Width to Fixed, and by the top or bottom, Height.', {
            find = 'What a resize changes', alias = 'resize edges corners Shift left drag' }),
        frame.number('Row height', 'row_height', 0, 100, 'Zero uses the shared row height. Rows never go under what their text needs.', { alias = 'Panel row height', only = not_icons, shown_by = 'Layout',
            shown = function(c, value)
                if value ~= 0 then return nil; end;
                return c.p.mode == 'text' and 'Fits its text' or ('From the main page (%.0f)'):format(c.s.style.bar_height);
            end }),
        frame.number('Bar thickness', 'bar_thickness', 1, 32, 'How thick a thin rail is.', { alias = 'Rail thickness', shown_by = 'Bar shape',
            only = function(c) return fill_on(c) and c.p.bar_style == 'rail'; end }),
    };
end;

local function countdown_rows()
    return {
        frame.heading('Countdowns on icons', 'Where the countdown sits on each icon.', { only = icons, shown_by = 'Layout', alias = 'Countdown text' }),
        frame.number('Countdown size', 'icon_countdown_size', 0, 64, '0 scales the countdown with the icon. Choose 6 to 64 pixels for a fixed size.', { tag = '_countdown', find = 'Icon countdown size', only = icons, shown_by = 'Layout',
            special = { [0] = 'Automatic' }, write = function(c, value) c.p.icon_countdown_size = value > 0 and math.max(6, value) or 0; end }),
        frame.pick('Countdown position', 'icon_countdown_position', { 'below', 'inside' }, { below = 'Below icon', inside = 'Inside icon' }, 'Center the countdown below the icon or inside its lower edge. Effects without a time show no countdown.',
            { tag = '_countdown', find = 'Icon countdown position', only = icons, shown_by = 'Layout' }),
        frame.number('Countdown gap', 'icon_countdown_gap', 0, 16, 'Pixels between the icon and the countdown below it.', { tag = '_countdown', find = 'Icon countdown gap', shown_by = 'Countdown position', alias = 'Space below the icon',
            only = function(c) return icons(c) and c.p.icon_countdown_position == 'below'; end }),
    };
end;

-- Look.

local box_names = { shared = 'From the main page', both = 'Background and border', background = 'Background only', border = 'Border only', none = 'None' };
local role_list = { { 'background', 'Background color' }, { 'border', 'Border color' }, { 'track', 'Bar track color' },
    { 'title', 'Title color' }, { 'label', 'Name color', 'Label color' }, { 'value', 'Countdown color', 'Value color' }, { 'detail', 'Detail text color' },
    { 'fill_start', 'Bar color', 'Bar fill start color', true }, { 'fill_end', 'Shaded bars end color', 'Bar fill end color', true } };

-- The line above Colors: what a panel sets for itself over the main page, its box while one is drawn and its colors.
local function own_box(c) return boxed(c) and c.p.box ~= 'shared'; end;
local function own_look(c) return own_box(c) or next(c.p.colors) ~= nil; end;
local function colors_line(warning)
    return function(c)
        local names = {};
        if own_box(c) then names[1] = 'Box'; end;
        for _, role in ipairs(role_list) do if c.p.colors[role[1]] then names[#names + 1] = role[2]; end; end;
        if c.p.colors.warning then names[#names + 1] = warning .. ' color'; end;
        return 'Has its own: ' .. table.concat(names, ', ') .. '.';
    end;
end;

-- Each color's row shows while what it colors is drawn, and the row that turns that on finds it. A bar with no color of
-- its own goes by its effect's kind, so its rows say By kind until one is picked.
local color_shown = {
    background = { box_has(1), 'Box' }, border = { box_has(2), 'Box' },
    track = { fill_on, 'Show the bar' }, fill_start = { fill_on, 'Show the bar' },
    fill_end = { function(c) return fill_on(c) and c.p.gradient; end, 'Shaded bars' },
    title = { headed, 'Show its heading' },
    label = { function(c) return text_on(c) and part_shown(c, 'name'); end, { 'Show row text', 'Name' } },
    value = { function(c) return icons(c) or text_on(c) and part_shown(c, 'time'); end, { 'Show row text', 'Countdown' } },
    -- It colors the heading's count and the empty panel's line too.
    detail = { function(c) return boxed(c) or text_on(c) and detail_shown(c); end, 'Layout' },
};

local function color_rows(soon)
    local rows = {};
    for _, role in ipairs(role_list) do
        local key = role[1];
        local only, shown_by = color_shown[key][1], color_shown[key][2];
        rows[#rows + 1] = frame.color(role[2], key, nil, { of = panel_table('colors'), back = true, only = only, shown_by = shown_by, alias = role[3],
            unset = role[4] and 'By kind', back_word = role[4] and 'Color by kind',
            fallback = function(c) return c.s.style[key .. '_color'] or c.s.style.buff_color; end });
    end;
    rows[#rows + 1] = frame.color(soon .. ' color', 'warning', nil, { of = panel_table('colors'), back = true, only = soon_shows, shown_by = { 'Show the bar', 'Show row text' },
        alias = 'Ending-soon color Ready-soon color warning color',
        fallback = function(c) return c.s.style.warning_color or c.s.style.buff_color; end });
    return rows;
end;

-- What each part of a row is called, and the part open in Row text. A recast's time since it started is the same part.
local part_id = {};
for _, key in ipairs(defaults.field_ids) do part_id[key] = 'part_' .. key; end;
local chosen_part = 'name';
local function part() return chosen_part; end;

-- Whether two shown parts meet: on a line and lined up the same, as ui/fields.lua places them, or with a break or wrapping
-- that goes by their order. Otherwise a divider has nothing to sit between and moving a part changes nothing. The Look
-- tab asks each frame, so the lanes seen go in one table.
local lanes = {};
local function parts_meet(c)
    if c.p.wrap then return true; end;
    require('table.clear')(lanes);
    for _, key in ipairs(defaults.field_ids) do
        if offered(c, key) and part_shown(c, key) then
            local lane = c.p.field_alignments[key] or (key == 'time' and 'right' or c.p.alignment);
            if lanes[lane] or c.p.field_newlines[key] then return true; end;
            lanes[lane] = true;
        end;
    end;
    return false;
end;

-- Whether a shown part has a label: Who cast it, Time elapsed and Full length start with one, and a blank label is none.
local function has_labels(c)
    for _, key in ipairs(defaults.field_ids) do
        local label = c.p.field_labels[key];
        if label == nil then label = fields.labels[key]; end;
        if label and label ~= '' and offered(c, key) and part_shown(c, key) then return true; end;
    end;
    return false;
end;

-- Priority decides only on a row that doesn't wrap.
local function no_wrap(c) return not c.p.wrap; end;

-- A part's blank says to go by the panel, so it isn't kept.
local function part_write(map)
    return function(c, value) c.p[map][chosen_part] = value ~= '' and value or nil; end;
end;

local part_rows = {
    frame.tick('Show', nil, 'Changes only this part, on this panel.', { tag = '_part', find = 'Show this part', alias = 'Show this field', only = function(c) return c.p.mode ~= 'text'; end,
        read = function(c) return c.p['show_' .. chosen_part]; end,
        write = function(c, on) c.p['show_' .. chosen_part] = on; end }),
    frame.text('Label', nil, 'Blank uses the normal wording. Labels change only what this panel says.', { tag = '_part', find = 'Part label', alias = 'Field label', of = panel_table('field_labels'), key_of = part,
        write = part_write('field_labels') }),
    -- A part with no color saved draws in the panel's own color for it, then the shared one, as ui/fields.lua colors it.
    frame.color('Color', nil, nil, { tag = '_part', find = 'Part color', alias = 'Field color Use normal field color', of = panel_table('field_colors'), key_of = part, back = true,
        fallback = function(c)
            local colors, style = c.p.colors, c.s.style;
            if chosen_part == 'time' then return colors.value or style.value_color or style.text_color; end;
            if chosen_part == 'name' then return colors.label or style.label_color or style.text_color; end;
            return colors.detail or style.detail_color or style.text_color;
        end }),
    -- While Color each countdown by how sure Vantage is of its time is on, a countdown takes its row's color unless the
    -- part or the panel has one for it. That changes from row to row, so no swatch can show it.
    frame.note('While Color each countdown by how sure Vantage is of its time is on under While playing, a countdown takes its row\'s color until you pick one here.', {
        only = function(c) return chosen_part == 'time' and c.s.style.status_time_color and not c.p.colors.value and not c.p.field_colors.time; end }),
    frame.pick('Line up', nil, { '', 'left', 'center', 'right' }, { [''] = 'As the row', left = 'Left', center = 'Center', right = 'Right' },
        'As the row follows Line up rows, but Countdown stays on the right until you pick here.', { tag = '_part', find = 'Part line up', alias = 'Field alignment',
        of = panel_table('field_alignments'), key_of = part, read = function(c) return c.p.field_alignments[chosen_part] or ''; end,
        write = part_write('field_alignments') }),
    frame.text('Divider before it', nil, 'Blank uses Between parts. The first part on a line has none.', { tag = '_part', length = 20, alias = 'Divider before this field', of = panel_table('field_dividers'), key_of = part,
        write = part_write('field_dividers'), only = parts_meet, shown_by = 'Parts of a row' }),
    frame.tick('Start a new line', nil, 'Puts this part on a line of its own, where the layout can wrap.', { tag = '_part', alias = 'Start on a new line', of = panel_table('field_newlines'), key_of = part }),
    -- A part with no priority saved goes by its own one in ui/fields.lua, so that's what shows.
    frame.number('Priority when space is short', nil, 0, 100, 'Higher stays longer when the row runs out of room.', { tag = '_part', alias = 'Field priority', of = panel_table('field_priority'), key_of = part,
        read = function(c) return c.p.field_priority[chosen_part] or fields.priorities[chosen_part] or 50; end,
        only = function(c) return no_wrap(c) and c.p.priority_overflow; end, shown_by = 'When space is short, keep the higher-priority parts' }),
};

-- The place of the next part the list shows above index (step -1) or below it (step 1), past the parts a recast panel
-- leaves out. Nil when there's none, so the move makes no Undo step.
local function next_listed(order, index, step)
    index = index + step;
    while order[index] and not (part_id[order[index]] and offered(ctx, order[index])) do index = index + step; end;
    return order[index] and index or nil;
end;

local function draw_parts(names)
    return function(imgui, c, item)
        caption(imgui, c, item);
        local order = ctx.p.field_order;
        -- A move waits for the list to be drawn. Made in the loop, Down would draw the part again further on and leave
        -- out the one it changed places with.
        local from, to;
        for index = 1, #order do
            local key = order[index];
            if key and part_id[key] and offered(ctx, key) then
                imgui.PushID(part_id[key]);
                if imgui.Selectable(part_shown(ctx, key) and names[key] or names.hidden[key], chosen_part == key) then chosen_part = key; end;
                if chosen_part == key then
                    if parts_meet(ctx) then
                        if imgui.Button('Up##part') then from, to = index, next_listed(order, index, -1); end;
                        imgui.SameLine();
                        if imgui.Button('Down##part') then from, to = index, next_listed(order, index, 1); end;
                    end;
                    frame.draw_rows(imgui, c, part_rows);
                end;
                imgui.PopID();
            end;
        end;
        if to then c.changed(function() c.move(order, from, to); end, true, 'Reorder row text'); end;
    end;
end;

local row_text_keys = { 'field_order', 'field_labels', 'field_colors', 'field_priority', 'field_alignments', 'field_dividers', 'field_newlines',
    'label_position', 'label_separator', 'separator', 'alignment', 'wrap', 'priority_overflow' };
-- What the parts' own rows keep, for Copy this tab to: their order, words, colors and places, and whether each shows.
local parts_copies = { 'field_order', 'field_labels', 'field_colors', 'field_priority', 'field_alignments', 'field_dividers', 'field_newlines' };
for _, key in ipairs(defaults.field_ids) do parts_copies[#parts_copies + 1] = 'show_' .. key; end;

local function row_text_fold()
    local names = { name = 'Name', target = 'Who it is on', source = 'Who cast it', elapsed = 'Time elapsed', total = 'Full length', time = 'Countdown', hidden = {} };
    for _, key in ipairs(defaults.field_ids) do names.hidden[key] = names[key] .. ' (hidden)'; end;
    return frame.fold('Row text', 'Each part of a row, in order: what it says, its color, where it lines up and what comes before it.', {
        frame.note('Text always shows the name and countdown, so parts can\'t be shown or hidden here. Labels, dividers and colors still apply.', { only = text_layout }),
        frame.custom('Parts of a row', 'Pick a part to edit it. Up and Down move it, while two parts share a line.', draw_parts(names), { rows = part_rows, find = 'Parts of a row', alias = 'Field layout and wording Field order fields', copies = parts_copies }),
        frame.pick('Label position', 'label_position', { 'before', 'after', 'hidden' }, { before = 'Before the value', after = 'After the value', hidden = 'Hidden' }, nil, { only = has_labels, shown_by = 'Parts of a row' }),
        frame.text('Between label and value', 'label_separator', 'Text between a label and its value.', { length = 20, alias = 'Label separator', shown_by = 'Label position',
            only = function(c) return has_labels(c) and c.p.label_position ~= 'hidden'; end }),
        frame.text('Between parts', 'separator', 'Text between one part and the next.', { length = 20, alias = 'Between fields', only = parts_meet, shown_by = 'Parts of a row' }),
        frame.pick('Line up rows', 'alignment', { 'left', 'center', 'right' }, { left = 'Left', center = 'Center', right = 'Right' }, nil, { alias = 'Row alignment' }),
        frame.tick('Wrap long rows', 'wrap', 'Wraps the parts within the panel\'s width. Resizing the panel with Shift turns this on.'),
        frame.tick('When space is short, keep the higher-priority parts', 'priority_overflow', 'Uses each part\'s priority when the whole row will not fit.', { alias = 'Keep higher-priority fields when narrow',
            only = no_wrap, shown_by = 'Wrap long rows' }),
        frame.button('Put the row text back as it started', 'Puts every part, label, color and divider of this panel back.', function(c)
            local p, id = ctx.p, ctx.id;
            local original = defaults.make().panels[id];
            c.changed(function()
                for _, key in ipairs(row_text_keys) do p[key] = defaults.copy(original[key]); end;
            end, true, 'Put the row text back as it started');
        end, { alias = 'Reset field layout' }),
    }, { key = 'Field layout and wording', only = text_on, shown_by = 'Show row text' });
end;

-- A row No boxes or headings hides goes by the line that says so.
local NO_BOX = 'Why there is no box or heading';
local boxed_by = { 'Layout', NO_BOX };

-- Recasts don't blink. Elsewhere Seconds left sets when a row blinks too, and says so while the blink starts elsewhere.
local function blinks(c) return not defaults.recast_panels[c.id]; end;
local function blink_apart(c, current)
    local p = c.p;
    if not (blinks(c) and p.blink_icons) or p.blink_seconds == current then return nil; end;
    return (current == 0 and 'Never early' or '%.0f seconds left') .. ', blinks at ' .. p.blink_seconds;
end;
local function set_soon(c, value)
    c.p.warning_seconds = value;
    if blinks(c) and value >= 1 then c.p.blink_seconds = value; end;
end;

-- soon is Ending soon or Ready soon, and runs_help is Bar runs' help.
function page.look_rows(soon, runs_help)
    return {
        frame.tick('Show its heading', 'show_heading', 'Shows the title above the panel, and how many rows are showing.', { alias = 'Panel heading', only = boxed, shown_by = boxed_by }),
        frame.text('Heading', 'title', 'Leave this blank to use the usual name.', { alias = 'Panel title', only = headed, shown_by = 'Show its heading', own = true }),
        frame.pick('Box', 'box', defaults.panel_boxes, box_names, 'From the main page follows Background and Border under Boxes there. The other choices set this panel\'s own background and border. Show its heading still shows or hides the title.', {
            alias = 'Panel box frameless background border box outline', only = boxed, shown_by = boxed_by }),
        frame.note('No boxes or headings is on, so this panel draws neither. Turn it off under Boxes on the main page to use them.', {
            find = NO_BOX, shown_by = 'Layout', only = function(c) return not_icons(c) and c.s.style.minimal; end }),
        frame.note('Icons has no heading or box. They stay saved for the other layouts.', { only = icons }),
        frame.tick('Show the bar', 'show_fill', nil, { alias = 'Show bar fill', only = bars, shown_by = 'Layout' }),
        frame.pick('Bar shape', 'bar_style', { 'full', 'rail' }, { full = 'Full bar', rail = 'Thin rail' }, nil, { only = fill_on, shown_by = 'Show the bar' }),
        frame.pick('Bar runs', 'direction', { 'drain', 'fill' }, { drain = 'Empties', fill = 'Fills' }, runs_help, { alias = 'Bar direction Drain toward zero', only = fill_on, shown_by = 'Show the bar' }),
        frame.pick('Fill from', 'fill_direction', { 'right', 'left' }, { right = 'Left edge', left = 'Right edge' }, nil, { only = fill_on, shown_by = 'Show the bar' }),
        frame.tick('Shaded bars', 'gradient', 'The fill fades along the bar, to Shaded bars end color under Colors or else to a darker shade. A shaded bar is drawn plain, without the Gauges art.', {
            alias = 'Gradient fill', only = fill_on, shown_by = 'Show the bar' }),
        frame.tick('Show row text', 'show_text', nil, { only = bars, shown_by = 'Layout' }),
        frame.line(soon, 'How a row shows its time running out.', {
            frame.tick('Color it at', 'warning_enabled', nil, { find = soon .. ': color it', alias = 'Ending-soon color enabled Ready-soon color enabled' }),
            frame.number('Seconds left', 'warning_seconds', 0, 300, 'Seconds left when the row takes the color, is marked and blinks. Zero never colors it early.', { find = soon .. ': seconds left', alias = 'Ending-soon color at Ready-soon color at',
                width = 150, format = '%.0f seconds left', special = { [0] = 'Never early' }, shown = blink_apart, write = set_soon, resets = { 'warning_seconds', 'blink_seconds' },
                copies = { 'blink_seconds' } }),
            frame.tick('Mark it too', 'warning_mark', 'Adds a marker, so the warning is not shown by color alone.', { find = soon .. ': mark it too', alias = 'Ending-soon marker Ready-soon marker', only = fill_on, shown_by = 'Show the bar' }),
            frame.tick('Blink', 'blink_icons', 'Dims and brightens its icon as its time runs out, from the seconds left here.', { find = soon .. ': blink',
                alias = 'Blink before an effect ends Blink expiring icons', only = blinks,
                write = function(c, on)
                    c.p.blink_icons = on;
                    if on and c.p.warning_seconds >= 1 then c.p.blink_seconds = c.p.warning_seconds; end;
                end }),
        }, { only = soon_shows, shown_by = { 'Show the bar', 'Show row text' } }),
        frame.color('Light color', 'dispel_color', nil, { shown_by = { 'Light up buffs you can remove', 'Light up debuffs you can remove' }, alias = 'lit light up color',
            only = function(c) return c.p.dispel_light; end, fallback = function() return defaults.dispel_color; end }),
        frame.tick('Glow around lit icons', 'dispel_glow', nil, { shown_by = { 'Light up buffs you can remove', 'Light up debuffs you can remove' }, alias = 'Glow around lit buffs',
            only = function(c) return c.p.dispel_light and pictured(c); end }),
        frame.note(colors_line(soon), { find = 'Own colors', alias = 'Clear panel color overrides Clear countdown color overrides Inherit Has its own',
            only = own_look, shown_by = 'Colors' }),
        frame.button('Use the main page\'s look', 'Clears the box and colors set on this panel, so it follows the main page. Undo brings them back.', function(c)
            local p = ctx.p;
            c.changed(function() p.colors, p.box = {}, 'shared'; end, true, 'Use the main page\'s look');
        end, { only = own_look, alias = 'Back to the skin\'s colors' }),
        frame.fold('Colors', 'The colors of this panel. Each one says where its color comes from until it is changed.', color_rows(soon), { key = 'Panel appearance overrides' }),
        row_text_fold(),
    };
end;

-- Filters.

-- What each finder has typed and picked, by what it looks through.
local finders = {};

local function domain_of(c) return defaults.recast_panels[c.id] and 'recast' or 'status'; end;

local function finder(c)
    local key = defaults.recast_panels[c.id] or 'status';
    local kept = finders[key];
    if not kept then kept = { query = '' }; finders[key] = kept; end;
    return kept;
end;

-- The catalog of the panel's kind, which leaves out what the game has no name for.
local function named(c)
    local kind = defaults.recast_panels[c.id];
    return c.c.catalog(kind and 'recast' or 'status', kind);
end;

page.named = named;

-- What changes when the catalog named(c) lists from changes, in place or not, so a finder needn't walk it each frame: the
-- window's status catalog revision, where it has one. A recast list has none and is walked.
local function named_revision(c)
    if domain_of(c) ~= 'status' or not c.c.catalog_revision then return nil; end;
    return c.c.catalog_revision();
end;
page.named_revision = named_revision;

-- One list finds and picks the effect the rows under it change, with a box at its top to find one by name. Nothing is
-- picked until you choose one. state_of(c) keeps the pick, in effect. options.read(c) and options.write(c, id), when
-- given, take a setting instead, options.all is the name of a choice for every effect, put first, and options.rows(c) is
-- what it lists, when that isn't the panel's own catalog.
-- What a pick goes to, set just before each list draws. The list calls back while it draws, so one callback serves
-- every list and a frame makes no closure.
local picking = {};
local function chose(chosen)
    if picking.write then picking.write(picking.c, chosen); else picking.state.effect = chosen; frame.touch(); end;
end;

function page.choose_row(text, state_of, options)
    options = options or {};
    local all, read, write, rows_of = options.all, options.read, options.write, options.rows;
    options.all, options.read, options.write, options.rows = nil, nil, nil, nil;
    local help = options.help or 'Pick one, or type part of its name in the box at the top of the list.';
    options.help = nil;
    return frame.custom(text, help, function(_, c, item)
        local domain, state, rows = domain_of(ctx), state_of(ctx), rows_of and rows_of(ctx) or page.named(ctx);
        local id = effect_editor.selection(rows, state, named_revision(ctx));
        if read then id = read(ctx); end;
        local shown = id == 0 and all or id ~= nil and (state.labels[id] or plain_name(c, id, domain))
            or (domain == 'recast' and 'Choose a recast' or 'Choose an effect');
        picking.write, picking.c, picking.state = write, c, state;
        c.effect_picker(item.tag and item.text .. '##' .. item.tag or item.text, id, chose, all, domain, shown, rows);
        c.tip(item.help);
        frame.lit(c, item);
    end, options);
end;

local function picked(c) return finder(c).effect ~= nil; end;
local function not_picked(c) return not picked(c); end;

local function map_tick(text, map, help, options)
    options.only = picked;
    options.read = function(c) return in_map(c.p[map], finder(c).effect); end;
    options.write = function(c, on) set_map(c.p[map], finder(c).effect, on); end;
    return frame.tick(text, nil, help, options);
end;

-- The lines under the finder, each as long as its list: the ids in a lasting order with the words each is listed by.
local function list_ids(p, map)
    local ids = {};
    for key, on in pairs(p[map]) do if on then ids[#ids + 1] = tonumber(key) or key; end; end;
    table.sort(ids, function(a, b) return tostring(a) < tostring(b); end);
    return ids;
end;

local function entries_of(c, ids, say)
    local out, domain = {}, domain_of(c);
    for index, id in ipairs(ids) do
        local name = plain_name(c.c, tonumber(id) or id, domain);
        out[index] = { id = id, line = say and say(name, id) or name, scope = 'effect_' .. index };
    end;
    return out;
end;
page.entries_of = entries_of;

local function any_on(map)
    for _, on in pairs(map) do if on then return true; end; end;
    return false;
end;

-- has(ctx) says if the list has entries, without their names: it also answers the search, before any page is drawn.
-- options.live is for a list whose table can change with no change of settings. With options.source(ctx), which gives that
-- table, the list is said again only when the table, the settings or the catalog's names change. The catalog's names count
-- only where the window keeps a revision of them, and a live list is said again each frame where it doesn't.
local function list_line(text, help, has, list, remove, options)
    options = options or {};
    local memo = { say = list, memo = {}, live = options.live };
    local source = options.live and options.source;
    if source then
        local kept = {};
        memo.say = function(c)
            local callbacks = c.callbacks;
            local from, names = source(c), c.c.catalog_revision and c.c.catalog_revision();
            local revision = callbacks and callbacks.settings_revision and callbacks.settings_revision();
            if names == nil or revision == nil or kept.from ~= from or kept.owner ~= c.s or kept.id ~= c.id
                or kept.revision ~= revision or kept.names ~= names then
                kept.from, kept.owner, kept.id, kept.revision, kept.names, kept.value = from, c.s, c.id, revision, names, list(c);
            end;
            return kept.value;
        end;
    end;
    options.only = has;
    return frame.custom(text, help, function(imgui, c, item)
        caption(imgui, c, item);
        local entries = frame.said(memo);
        -- Row 1 of two lists would be one button to ImGui, and only the first drawn would work.
        imgui.PushID(text);
        for index = 1, #entries do
            local entry = entries[index];
            imgui.PushID(entry.scope);
            -- A long line wraps where its buttons still fit beside it: Remove, and what options.room says the ones
            -- before it take.
            local room = imgui.CalcTextSize('Remove') + 24 + (options.room and options.room(imgui) or 0);
            imgui.PushTextWrapPos(imgui.GetCursorPosX() + math.max(6 * imgui.GetFontSize(), imgui.GetContentRegionAvail() - room));
            imgui.TextUnformatted(entry.line);
            imgui.PopTextWrapPos();
            imgui.SameLine();
            if options.extra then options.extra(imgui, c, entry, index); end;
            if imgui.Button('Remove##effect') then c.changed(function() remove(ctx.p, entry, index); end, true, 'Remove from ' .. item.text); end;
            imgui.PopID();
        end;
        imgui.PopID();
    end, options);
end;
page.list_line = list_line;

-- What Up and Down take beside a line of My order, and a color's swatch beside a line of Colored.
local function order_room(imgui) return imgui.CalcTextSize('Up') + imgui.CalcTextSize('Down') + 48; end;
local function color_room(imgui) return imgui.GetFrameHeight() + 8; end;
page.order_room = order_room;

-- Up and Down beside a line of My order, for the order in of(ctx), or the panel's own without of.
local function order_moves(of)
    return function(imgui, c, _, index)
        local order = (of and of(ctx) or ctx.p).order;
        if imgui.Button('Up##order') then c.changed(function() c.move(order, index, index - 1); end, true, 'Reorder My order'); end;
        imgui.SameLine();
        if imgui.Button('Down##order') then c.changed(function() c.move(order, index, index + 1); end, true, 'Reorder My order'); end;
        imgui.SameLine();
    end;
end;
page.order_moves = order_moves;

local function draw_effect_color(imgui, c, entry)
    local p = ctx.p;
    local chosen = frame.swatch(imgui, '##effect_color', p.effect_colors[entry.id]);
    if chosen then c.changed(function() p.effect_colors[entry.id] = chosen; end, false, 'Colored'); end;
    imgui.SameLine();
end;

local function sorted_keys(map)
    local ids = {};
    for key in pairs(map) do ids[#ids + 1] = key; end;
    table.sort(ids, function(a, b) return tostring(a) < tostring(b); end);
    return ids;
end;

-- noun is what a row of this panel is called.
local function list_rows(noun)
    return {
        list_line('Show only', 'While this list has ' .. noun .. 's, only those show.', function(c) return any_on(c.p.include); end,
            function(c) return entries_of(c, list_ids(c.p, 'include')); end, function(p, entry) set_map(p.include, entry.id, false); end, { tag = '_list', find = 'Show only list' }),
        list_line('Hidden here', 'Hidden wins over Show only. Tracking and alerts go on.', function(c) return any_on(c.p.exclude); end,
            function(c) return entries_of(c, list_ids(c.p, 'exclude')); end, function(p, entry) set_map(p.exclude, entry.id, false); end),
        list_line('Pinned first', 'These stay above the other rows.', function(c) return any_on(c.p.pinned); end,
            function(c) return entries_of(c, list_ids(c.p, 'pinned')); end, function(p, entry) set_map(p.pinned, entry.id, false); end),
        list_line('Renamed', 'What this panel calls them. Their identity does not change.', function(c) return next(c.p.labels) ~= nil; end, function(c)
            return entries_of(c, sorted_keys(c.p.labels), function(name, id) return name .. ' as ' .. c.p.labels[id]; end);
        end, function(p, entry) p.labels[entry.id] = nil; end),
        list_line('Colored', 'Their own bar color on this panel.', function(c) return next(c.p.effect_colors) ~= nil; end,
            function(c) return entries_of(c, sorted_keys(c.p.effect_colors)); end, function(p, entry) p.effect_colors[entry.id] = nil; end, { extra = draw_effect_color, room = color_room }),
    };
end;

-- The kinds of effect the catalog knows, in name order.
local function kind_list(c)
    local names, out = {}, {};
    for _, entry in ipairs(c.c.catalog('status')) do if entry.group then names[entry.group] = entry.group; end; end;
    for id, name in pairs(names) do out[#out + 1] = { id = id, name = name, label = name .. '##filter_' .. id }; end;
    table.sort(out, function(a, b)
        local first, second = a.name:lower(), b.name:lower();
        return first == second and a.id < b.id or first < second;
    end);
    return out;
end;

local kind_item = { say = kind_list, memo = {} };
local kind_flag = { false };

local function draw_kinds(imgui, c, item)
    caption(imgui, c, item);
    local p = ctx.p;
    local entries = frame.said(kind_item);
    local used, available = 0, imgui.GetContentRegionAvail();
    for index = 1, #entries do
        local entry = entries[index];
        local width = imgui.CalcTextSize(entry.name) + imgui.GetFrameHeight() + 20;
        if used > 0 and used + width <= available then imgui.SameLine(); else used = 0; end;
        kind_flag[1] = p.groups[entry.id] == true;
        if controls.checkbox(imgui, c.look, entry.label, kind_flag) then
            local on = kind_flag[1];
            c.changed(function() p.groups[entry.id] = on or nil; end, true, 'Show kind: ' .. entry.name);
        end;
        used = used + width;
    end;
end;

-- Only effects from job abilities, on Party members' timers and Party list (core/catalog.lua from_ability).
page.abilities_help = 'Shows only effects from job abilities, rolls, maneuvers and blood pacts included. An effect Vantage didn\'t see land shows if only job abilities give it.';
page.abilities_words = 'Only job abilities Abilities only two-hours rolls maneuvers blood pacts';

-- recast has no Only effects I cast, as every recast is your own, and no kinds of effect. Its rows say recast.
function page.filter_rows(recast)
    local rows = {};
    local function add(item) rows[#rows + 1] = item; end;
    local noun = recast and 'recast' or 'effect';
    local find = recast and 'Choose a recast' or 'Choose an effect';
    if recast then
        add(frame.note('The Hide list doesn\'t hide recasts. These filters change only this panel.'));
    else
        add(frame.note('Effects on the Hide list are hidden here too.', { only = list_used }));
        add(page.list_paused());
        add(frame.button('Edit the list', 'Open the Hide list.', function(c) c.open_page('Filters'); end, { alias = 'Shared effect filters' }));
        add(frame.tick('Only effects I cast', 'mine_only', 'Effects with no named caster do not count as yours.', { alias = 'Only effects I applied' }));
        add(frame.tick('Only effects from job abilities', 'abilities_only', page.abilities_help, {
            only = only_on('party'), alias = page.abilities_words }));
    end;
    add(frame.tick('Only ' .. noun .. 's with a known time', 'known_only', 'Hides rows without a countdown from this panel. It does not mean those ' .. (recast and 'recasts are ready.' or 'effects ended.'), { alias = 'Only timers with a known duration' }));
    add(frame.text('Show only names containing', 'filter', recast and 'Keeps only recasts with this in their name.' or 'Matches the effect, who it is on and who cast it.', { alias = 'Filter by text' }));
    add(page.choose_row(recast and 'Recast' or 'Effect', finder, { find = find, help = 'What the rows under it change, on this panel only. Type part of its name in the box at the top of the list to find it.',
        alias = 'Find an effect Find a recast Effect category Search by name Edit this display\'s filters' }));
    add(frame.note(function(c)
        if #named(c) > 0 then return nil; end;
        local kind = defaults.recast_panels[c.id];
        return kind == 'item' and 'No item recast has been seen yet. Recasts of equipped items show up here once the client has given them.' or 'No recasts are known yet.';
    end, { only = not_picked, live = true }));
    add(frame.line(nil, nil, {
        map_tick('Show only', 'include', 'If any ' .. noun .. 's are listed, the panel shows only those. An empty list shows all.', { tag = '_effect', find = 'Show this ' .. noun .. ' only', alias = 'Include in this panel', shown_by = find }),
        map_tick('Hide here', 'exclude', 'Hidden wins over Show only. Tracking and alerts go on.', { alias = 'Hide in this panel', shown_by = find }),
        map_tick('Pin first', 'pinned', 'Pinned rows stay above the others.', { alias = 'Pin above other ' .. noun .. 's', shown_by = find }),
    }));
    add(frame.button('Add to My order', 'Adds it to My order and sets Sort to My order.', function(c)
        local p, id, listed = ctx.p, finder(ctx).effect, false;
        for _, kept in ipairs(p.order) do if kept == id then listed = true; end; end;
        if listed and p.sort == 'fixed' then return; end;
        c.changed(function()
            if not listed then p.order[#p.order + 1] = id; end;
            p.sort = 'fixed';
        end, true, 'Add to My order');
    end, { only = picked, shown_by = find }));
    add(frame.text('Rename it', nil, 'Blank uses the game\'s name. The ' .. noun .. ' itself does not change.', { alias = 'Custom label', only = picked, shown_by = find, of = panel_table('labels'),
        key_of = function(c) return finder(c).effect; end,
        write = function(c, value) c.p.labels[finder(c).effect] = value ~= '' and value or nil; end }));
    add(frame.color('Color', nil, nil, { tag = '_effect', find = (recast and 'Recast' or 'Effect') .. ' color', alias = 'Effect fill color', only = function(c) return picked(c) and tinted(c); end, shown_by = find, of = panel_table('effect_colors'),
        key_of = function(c) return finder(c).effect; end, fallback = function(c) return c.s.style.buff_color; end }));
    add(frame.note('A color shows on a bar, or on a countdown while Color each countdown by how sure Vantage is of its time is on under While playing.', {
        only = function(c) return picked(c) and not tinted(c); end }));
    for _, item in ipairs(list_rows(noun)) do add(item); end;
    if not recast then
        add(frame.fold('Show only some kinds of effects', 'Leave every kind unticked to show them all.', {
            frame.custom('Kinds of effects', 'Tick the kinds to show.', draw_kinds, { alias = 'Groups shown by this panel Buffs Debuffs Food Other Protection Recovery Rolls Songs Travel' }),
        }, {}));
    end;
    return rows;
end;

-- My order sits under Sort on Show, and Add to My order on Filters fills it.
page.order_line = list_line('My order', 'Used while Sort is My order. Rows not listed here follow these.', function(c) return #c.p.order > 0; end,
    function(c) return entries_of(c, c.p.order); end, function(p, _, index) table.remove(p.order, index); end, { extra = order_moves(), room = order_room, resets = { 'order' } });
table.insert(show_rows, 4, page.order_line);

-- What Reset this tab puts back on Filters. A recast panel has no kinds and no Only effects I cast, so it skips those.
page.filter_keys = { 'include', 'exclude', 'pinned', 'labels', 'effect_colors', 'groups', 'filter', 'mine_only', 'known_only', 'abilities_only' };
page.filter_reset = { filters = frame.reset_keys(page.filter_keys) };

-- What Copy this tab to gives another panel: what the Look rows keep, the Filters keys and the When to show conditions.
-- A recast panel's lists name recasts of its own kind (core/recasts.lua entry), so another kind takes only Show only
-- names containing and Only recasts with a known time, and keeps its own lists.
function page.copy_lists(look, recast)
    return { look = frame.key_list(frame.tab_keys(look)), filters = recast and { 'filter', 'known_only' } or page.filter_keys, when = { 'conditions' } };
end;

local fills_names = { down_right = 'Down, then to the right', down_left = 'Down, then to the left', right_down = 'To the right, then down', left_down = 'To the left, then down' };
local fills_list = { 'down_right', 'down_left', 'right_down', 'left_down' };
local fills_pairs = { down_right = { 'vertical', 'right' }, down_left = { 'vertical', 'left' }, right_down = { 'horizontal', 'right' }, left_down = { 'horizontal', 'left' } };
local fills_of = { vertical = { right = 'down_right', left = 'down_left' }, horizontal = { right = 'right_down', left = 'left_down' } };

function page.fills_row()
    return frame.pick('Fills', nil, fills_list, fills_names, 'Which way rows fill inside the panel, and which way they wrap. Resize the unlocked panel to change where they wrap.', {
        alias = 'Stack direction Growth direction left to right right to left horizontal vertical stack wrap rows columns icons', resets = { 'stack_direction', 'growth' },
        read = function(c)
            local by_growth = fills_of[c.p.stack_direction];
            return by_growth and by_growth[c.p.growth];
        end,
        write = function(c, value)
            local pair = fills_pairs[value];
            c.p.stack_direction, c.p.growth = pair[1], pair[2];
        end });
end;

function page.place_rows()
    local rows = size_rows();
    for _, item in ipairs(frame.place_rows(nil, { page.fills_row() })) do rows[#rows + 1] = item; end;
    rows[#rows + 1] = frame.put_back;
    for _, item in ipairs(countdown_rows()) do rows[#rows + 1] = item; end;
    return rows;
end;

-- The header's On and samples, as every timer and recast panel has them.

function page.header_rows()
    return { frame.line(nil, nil, {
        frame.tick('On', nil, 'Shows or hides this display. Tracking and alerts go on.', {
            tag = '_display', find = 'Show this display', alias = 'Show this panel display',
            read = function(c) return c.s.enabled and c.p.enabled; end,
            write = function(c, on)
                c.p.enabled = on;
                if on then
                    c.s.enabled = true;
                    defaults.ensure_recast_kind(c.p);
                else c.p.preview = false; end;
            end }),
        frame.tick('Show samples', nil, 'Sample timers on this panel, to arrange it with nothing happening. It turns nothing on. Samples never make real alerts.', {
            alias = 'Sample displays',
            read = function(c) return defaults.sampled(c.s, c.id); end,
            write = function(c, on) defaults.sample_panel(c.s, c.id, on); end,
            refuse = function(c, on)
                if on and not (c.s.enabled and defaults.panel_enabled(c.s, c.id)) then
                    c.c.note('Turn a display on first. Samples show only on displays that are on.');
                    return true;
                end;
            end }),
        frame.lock_row,
    }) };
end;

local status_tabs = {
    show = show_rows,
    look = page.look_rows('Ending soon', 'Effects without a countdown show an empty track.'),
    filters = page.filter_rows(false), place = page.place_rows(), when = conditions_ui.rows,
};
local header = page.header_rows();

-- Copy this tab to goes to the other timer panels.
local status_ids = { 'self_buffs', 'self_debuffs', 'target', 'party', 'watch' };
local status_copy = page.copy_lists(status_tabs.look);
local others = {};
for _, id in ipairs(status_ids) do
    others[id] = {};
    for _, other in ipairs(status_ids) do if other ~= id then others[id][#others[id] + 1] = other; end; end;
end;
local function copy_to(c) return others[c.id]; end;
-- Who it is on starts on only for Party members' timers and Watched enemy timers, and a self panel has no tick for it on
-- Show, so a copy between Self buffs or Self debuffs and a panel that isn't one of them leaves it as each panel has it.
-- The two self panels still carry it, as it names you on both.
local function copy_skip(key, from, into) return key == 'show_target' and not self_panels[from] ~= not self_panels[into]; end;

-- Look's part rows change the part picked, so its reset puts back every part as well, and the heading, which Copy this tab
-- to leaves as each panel's own.
local status_reset = { filters = page.filter_reset.filters, look = frame.reset_keys({ 'title', unpack(status_copy.look) }) };
for _, id in ipairs(status_ids) do
    frame.register({ id = id, name = require('ui.elements').label(id), fold_page = 'Panels', tabs = status_tabs, header = header,
        tab_reset = status_reset, copy = status_copy, copy_to = copy_to, copy_skip = copy_skip });
end;

return page;
