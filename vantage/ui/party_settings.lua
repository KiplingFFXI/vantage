-- The editor of the party list buffs, as a display on the panel frame: buffs and debuffs beside the game's party list, or
-- in panels of their own.
local conditions_ui = require('ui.condition_settings');
local cooldowns = require('core.party_cooldowns');
local frame = require('ui.panel_frame');
local hud = require('ui.native_party_hud');
local icons = require('ui.icons');
local overhead_defaults = require('ui.overhead_defaults');
local party_defaults = require('ui.party_defaults');
local rows = require('ui.panel_rows');
local status = require('ui.status_panel');
local widget = require('ui.party_size_widget');
local page = {};
local ctx = frame.ctx;
local labels, group_names = widget.labels, widget.group_names;
-- The panel and the group the rows under them change. They last the session.
local selection = { panel = 1, group = 1 };
-- What shows the rows only a panel of its own uses: each group's switch on Size and place.
local panel_switches = {};
for group, name in ipairs(group_names) do panel_switches[group] = name .. ' in a panel of its own'; end;

local function effects(c) return c.p.effects; end;
local function native(c) return c.p.native; end;
local function look(c) return c.p.style; end;
local function picks() return selection; end;
-- None shows no effects, so the rows that only shape them go with it.
local function effects_shown(c) return c.p.effects.kind ~= 'none'; end;
local function timers(c) return c.p.effects.timers == true and effects_shown(c); end;
local function in_panels(c) return widget.in_panels(c.p); end;
local function any_group(c) return hud.shown(c.p, 1) or hud.shown(c.p, 2) or hud.shown(c.p, 3); end;
-- What goes by the game's list goes while every group that shows is in a panel of its own.
local function any_beside(c)
    for group = 1, 3 do
        if hud.shown(c.p, group) and not c.p.groups[group].native_detached then return true; end;
    end;
    return false;
end;
local function timers_in_panels(c) return timers(c) and in_panels(c); end;

-- Header.

local header = {
    frame.line(nil, nil, {
        frame.tick('On', 'enabled', 'Shows the groups ticked on Show beside the game\'s party list. Turning it off ends its samples.', {
            tag = '_display', find = 'Show this display', alias = 'Show party list buffs Show this panel display',
            write = function(c, on) party_defaults.switch(c.p, on); end }),
        rows.samples('Sample effects beside the real game rows you have now, to arrange them with nothing happening. They make no members or windows, and never make real alerts.',
            function(c) return c.p.enabled; end, { alias = 'Sample displays Sample party sample members' }),
        frame.tick('Locked', nil, 'Locked, the groups stay where they are, even while Shift is held. Unlock first, then hold Shift and drag a group to move it. A group in a panel of its own also resizes from its edges and corners.', {
            alias = 'Lock position and size lock unlock move resize shift left drag edges corners protect', read = frame.lock_row.read, write = frame.lock_row.write }),
    }),
};

local under = {
    frame.note(function(c) return widget.panel_line(c.p); end, { only = in_panels }),
    frame.button(labels.back, 'Puts every group in a panel of its own back beside the game\'s party list, where the icons fill the step from one row to the next. Groups you moved keep their place, and each panel keeps its size and place for next time. One Undo step puts them back in their panels. It works while Locked.', function(c)
        local p = ctx.p;
        c.changed(function() widget.back(p); end, true, labels.back);
    end, { only = in_panels, shown_by = panel_switches, alias = 'Reattach panels of their own Reattach buff panels native detached attach snap move resize wrap width height game windows' }),
};

-- Show.

local strip_ticks = {};
for index, strip in ipairs({ { 'party', 'Show the buffs beside your party\'s window.' }, { 'alliance1', 'Show the buffs beside alliance party 1.' },
    { 'alliance2', 'Show the buffs beside alliance party 2.' } }) do
    local key = strip[1];
    strip_ticks[index] = frame.tick(group_names[index], nil, strip[2], { tag = '_strip',
        read = function(c) return c.p.strips[key] == true; end,
        write = function(c, on)
            c.p.strips[key] = on;
            if on then c.p.enabled = true; end;
        end });
end;

local own_list = { 'always', 'party', 'never' };
local own_names = { always = 'Always', party = 'Only in a party', never = 'Never' };
local sort_names = { longest = 'Longest remaining', oldest = 'Oldest first', remaining = 'Ending soonest', name = 'Name' };

local function cooldowns_here(c)
    local watch = c.s.party_cooldowns;
    return watch.enabled and watch.strips and cooldowns.beside_list(c.s);
end;
local function cooldowns_row(c) return cooldowns_here(c) or not effects_shown(c); end;
local function cooldowns_line(c)
    if not cooldowns_here(c) then return 'No effects show, and Party cooldowns don\'t show here either.'; end;
    return effects_shown(c) and 'Party cooldowns show here too.' or 'Only Party cooldowns show here.';
end;

local show_rows = {
    frame.line('Groups', 'Which of the game\'s party windows get buffs beside them.', strip_ticks, { find = 'Which groups show', alias = 'Show party strip Show alliance strip 1 Show alliance strip 2' }),
    frame.note(party_defaults.strip_help, { only = function(c) return effects_shown(c) and (hud.shown(c.p, 2) or hud.shown(c.p, 3)); end }),
    frame.radio('Show', 'kind', { 'all', 'buff', 'debuff', 'none' }, { all = 'Buffs and debuffs', buff = 'Buffs only', debuff = 'Debuffs only', none = 'None' }, party_defaults.kind_help, {
        tag = '_kinds', find = 'Show buffs or debuffs', of = effects, alias = 'Effect types Party buffs and debuffs Party buffs only Party debuffs only Only party cooldowns' }),
    frame.tick('Light up debuffs you can remove', 'cleanse_light', 'A debuff lights up when your job and level can take it off now and you\'ve learned the spell. Erase doesn\'t reach alliance parties. It uses Glow around lit icons and Light color from Overhead icons, on its Look tab, so there\'s nothing else to set.', {
        of = effects, only = effects_shown, shown_by = 'Show buffs or debuffs', alias = 'cleanse erase poisona paralyna blindna silena cursna viruna stona' }),
    frame.tick('Countdowns', 'timers', party_defaults.timers_help, { of = effects, only = effects_shown, shown_by = 'Show buffs or debuffs', alias = 'Show effect countdowns' }),
    frame.pick('Your own row', nil, own_list, own_names, 'Only in a party hides the party list buffs while you are solo.', {
        alias = 'Show my own row Show when solo',
        read = function(c)
            if not c.p.include_self then return 'never'; end;
            return c.p.show_solo and 'always' or 'party';
        end,
        write = function(c, value)
            c.p.include_self = value ~= 'never';
            if value ~= 'never' then c.p.show_solo = value == 'always'; end;
        end }),
    frame.number('Most per member', 'max', 0, 32, 'All that fit shows every known effect that passes your filters. A panel of its own wraps them; beside the game\'s list they still have to fit the row.', {
        of = effects, only = effects_shown, shown_by = 'Show buffs or debuffs', special = { [0] = 'All that fit' }, alias = 'Show all matching effects Effects per member',
        read = function(c) return c.p.effects.fit_all and 0 or c.p.effects.max; end,
        write = function(c, value)
            local e = c.p.effects;
            e.fit_all = value == 0;
            if value > 0 then e.max = value; end;
        end }),
    frame.pick('Sort', 'sort', { 'longest', 'oldest', 'remaining', 'name' }, sort_names,
        'Longest remaining sorts 4h, 3m, then 57s. Effects without a countdown go last. Icons fill, on Size and place, chooses the starting edge. Oldest first goes by when each was first seen. Pinned effects come first.',
        { of = effects, only = effects_shown, shown_by = 'Show buffs or debuffs', alias = 'Effect sorting' }),
    frame.note(cooldowns_line, { only = cooldowns_row }),
    frame.button('Change on Party cooldowns', 'Opens Party cooldowns.', function(c) c.open_page('Display', 'cooldown_list'); end, { only = cooldowns_row, beside = true }),
};

-- Look. The party list buffs wear the timer panels' look; only their icon art and opacity are their own.

local name_names = { full = 'Full name', short = 'Short name', job = 'Job', job_icon = 'Job', icon = 'Job' };

local look_rows = {
    frame.pick('Party buff icons', 'icon_art', { 'Client', 'Original FFXI', 'XI View' }, { Client = 'Client', ['Original FFXI'] = 'Original FFXI', ['XI View'] = 'XI View' },
        'Client uses Ashita resources. Original FFXI and XI View read their installed packs directly, independent of the font.', { of = look }),
    frame.note(function(c) return icons.reason and icons.reason(c.p.style.icon_art); end, { live = true }),
    frame.number('Opacity', 'opacity', 0.05, 1, nil, { of = look, whole = false, alias = 'Party opacity' }),
    frame.pick('Member names', 'name_display', { 'full', 'short', 'job' }, name_names, 'The label above each member\'s effects in a panel of its own. A job that isn\'t known shows the member name.', {
        only = in_panels, shown_by = panel_switches, alias = 'Member name display full short abbreviated replace name job abbreviation' }),
    frame.number('Short name length', 'name_length', 3, 16, 'The most characters a short name shows, with the mark that says it is cut short.', {
        only = function(c) return in_panels(c) and c.p.name_display == 'short'; end, shown_by = 'Member names', alias = 'Abbreviated name length short shorten member player names characters abbreviation' }),
};

-- Filters.

local always_ticks = {};
for index, tick in ipairs(overhead_defaults.always) do
    always_ticks[index] = frame.tick(tick.label, tick.key, tick.help, { of = effects, alias = tick.words });
end;
local filter_rows = {
    frame.note('Effects on the Hidden everywhere list are hidden here too.', { only = status.list_used }),
    frame.button('Edit the list', 'Open the Hidden everywhere list.', function(c) c.open_page('Filters'); end, { alias = 'Shared effect filters' }),
    status.list_paused(),
    frame.tick('Only effects from job abilities', 'abilities_only', status.abilities_help, {
        of = effects, only = effects_shown, shown_by = 'Show buffs or debuffs', alias = status.abilities_words }),
    frame.line('Always show', 'Ticked shows it even with Debuffs only or Only effects from job abilities on. Unticked hides it unless it\'s on Show only, where the other settings decide as they do for any effect.', always_ticks, { only = effects_shown, shown_by = 'Show buffs or debuffs' }),
};
for _, item in ipairs(rows.effect_lists({
    of = effects, find = 'Find an effect', effect = 'Effect', show = 'Show only', hide = 'Hide here', pin = 'Pin first',
    reset = 'Reset selected effect', clear = 'Clear this display\'s filters',
    listed = { include = 'Show only', exclude = 'Hidden here', pinned = 'Pinned first' },
    alias = { find = 'Find a party effect Effect filters Effect filters and labels', effect = 'Party effect', show = 'Include effect', hide = 'Exclude effect', pin = 'Pin effect first', clear = 'Clear all party effect filters' },
})) do filter_rows[#filter_rows + 1] = item; end;

-- Size and place.

local function panel_group(c) return c.p.groups[selection.panel]; end;

-- The groups in a panel of their own that show. A group not shown has no panel.
local function panel_list(c)
    local panels = {};
    for group = 1, 3 do if hud.shown(c.p, group) and c.p.groups[group].native_detached then panels[#panels + 1] = group; end; end;
    return panels;
end;

-- The panel and the group picked are ones of those.
local function keep_pick(key)
    return function()
        local panels = panel_list(ctx);
        for _, group in ipairs(panels) do if group == selection[key] then return; end; end;
        selection[key] = panels[1] or selection[key];
    end;
end;

-- Each group's switch places its panel where the group is drawn now. Locked doesn't stop it; dragging still needs an unlock.
local function panel_tick(group, old)
    return frame.tick(group_names[group] .. ' in a panel of its own', nil, 'Puts this group\'s buffs in a panel of its own, where the group is drawn now. It works while Locked. Turn it off to put them back beside the game\'s list.', {
        alias = old .. ' in a panel of its own', only = function(c) return hud.shown(c.p, group); end, shown_by = 'Which groups show',
        read = function(c) return c.p.groups[group].native_detached == true; end,
        write = function(c, on)
            if on then widget.place(c.p, group, widget.rooms(c.s, c.callbacks), c.s.style); else c.p.groups[group].native_detached = false; end;
        end });
end;

local slot_names, slot_ids = {}, {};
for slot = 0, 5 do slot_names[slot], slot_ids[slot + 1] = 'Slot ' .. (slot + 1), 'party_slot_' .. (slot + 1); end;

-- A row of Up and Down per slot would fill the search with results that are all the same, so they stay out of it.
local function draw_slots(imgui, c)
    local order = ctx.p.groups[selection.group].order;
    -- A move waits for the list to be drawn. Made in the loop, Down would draw the slot again further on and leave out
    -- the one it changed places with.
    local from, to;
    for index = 1, #order do
        imgui.PushID(slot_ids[index]);
        imgui.TextUnformatted(slot_names[order[index]]);
        if index > 1 then
            imgui.SameLine();
            if imgui.Button('Up##party_slot') then from, to = index, index - 1; end;
        end;
        if index < #order then
            imgui.SameLine();
            if imgui.Button('Down##party_slot') then from, to = index, index + 1; end;
        end;
        imgui.PopID();
    end;
    if from then c.changed(function() order[from], order[to] = order[to], order[from]; end, true, 'Member order'); end;
end;

local place_rows = {
    frame.note(function(c) return widget.step(c.p, widget.rooms(c.s, c.callbacks)); end, { live = true, only = any_beside }),
    frame.number(labels.size, 'icon_size', 12, 128, 'How big each icon is in a group\'s panel of its own. Beside the game\'s party list the icons always fill the step from one row to the next.', {
        of = effects, only = in_panels, shown_by = panel_switches, alias = 'Buff and debuff icon size Party icon size' }),
    frame.locked_line,
    frame.line('Row width', 'Each group\'s row beside the game\'s party list grows with its buffs up to this width, and always has room for one whole icon. Panels of their own keep their own size.', {
        frame.number('Longest row', 'width', 40, 900, 'The most a row grows to.', { of = native, locks = true, width = 200, format = 'Longest row %.0f', alias = 'Strip maximum width room gap next row icon room Touching the next row' }),
    }, { only = any_beside, shown_by = panel_switches }),
    frame.number('Countdown size', 'icon_countdown_size', 0, 64, '0 scales the countdown with the icon. Choose 6 to 64 pixels for a fixed size. Inside an icon it shrinks to fit.', {
        of = effects, only = timers, shown_by = 'Countdowns', special = { [0] = 'Automatic' }, alias = 'Icon countdown size',
        write = function(c, value) c.p.effects.icon_countdown_size = value > 0 and math.max(6, value) or 0; end }),
    -- Beside the game's list the time sits inside the icon, so position and gap show only for a panel of its own.
    frame.pick('Countdown position', 'icon_countdown_position', { 'below', 'inside' }, { below = 'Below icon', inside = 'Inside icon' },
        'Center the countdown below the icon or inside its lower edge, in a panel of its own. Effects without a time show no countdown.', {
        of = effects, only = timers_in_panels, shown_by = { 'Countdowns', panel_switches[1], panel_switches[2], panel_switches[3] }, alias = 'Icon countdown position' }),
    frame.number('Countdown gap', 'icon_countdown_gap', 0, 16, 'Pixels between the icon and the countdown below it.', {
        of = effects, shown_by = { 'Countdown position', 'Countdowns' }, alias = 'Icon countdown gap',
        only = function(c) return timers_in_panels(c) and c.p.effects.icon_countdown_position == 'below'; end }),
    frame.pick('Buff side', 'side', { 'left', 'right' }, { left = 'Left', right = 'Right' }, 'Which side of the game\'s party list the buffs go on.', { of = native, locks = true,
        only = any_beside, shown_by = panel_switches,
        write = function(c, value)
            c.p.native.side = value;
            for _, group in ipairs(c.p.groups) do group.native_side = 'default'; end;
        end }),
    frame.note('There\'s no room on that side of the game\'s list, so these buffs aren\'t showing.', { only = function() return hud.no_room == true; end }),
    frame.number('Gap from the game\'s list', 'gap', 0, 40, 'The space between the game\'s party list and the nearest icon.', { of = native, locks = true, alias = 'Strip gap Strip placement',
        only = any_beside, shown_by = panel_switches }),
    -- How icons fill doesn't move anything, so it stays live, as Fills does on a timer panel.
    frame.pick('Icons fill', 'growth', { 'right', 'left' }, { right = 'Left to right', left = 'Right to left' }, 'Each row fills in this direction, then wraps below. Buff side and Sort stay separate.', { of = effects, only = effects_shown, shown_by = 'Show buffs or debuffs', alias = 'Buff growth direction' }),
    frame.button('Put moved groups back', 'Any group you moved goes back beside the game\'s party list, on the Buff side. A panel of its own keeps its size and place.', function(c)
        local groups = ctx.p.groups;
        c.changed(function()
            for _, group in ipairs(groups) do group.native_side, group.native_x, group.native_y = 'default', 0, 0; end;
        end, true, 'Put moved groups back');
    end, { locks = true, alias = 'Reset strip offsets Reattach panels of their own Reattach buff panels', only = any_beside, shown_by = panel_switches }),
    frame.fold('Panels of their own', 'A framed panel for one group\'s buffs, at Icon size in a panel of its own, with its own size and place.', {
        panel_tick(1, 'Party'), panel_tick(2, 'Alliance 1'), panel_tick(3, 'Alliance 2'),
        frame.group({
            { kind = 'custom', draw = keep_pick('panel') },
            frame.pick('Panel to edit', 'panel', nil, group_names, 'Which panel the numbers below change.', { of = picks, transient = true, choices_of = panel_list }),
            frame.number('Panel width', 'detached_width', 40, 900, nil, { of = panel_group, locks = true }),
            frame.number('Panel height', 'detached_height', 40, 16000, 'Effects past this height scroll.', { of = panel_group, locks = true, edge = 'y' }),
            frame.number('Across the screen', 'detached_x', 0, 16384, 'The panel\'s left edge, in pixels from the left of the screen.', { of = panel_group, locks = true, edge = 'x', room_of = function(c) return panel_group(c).detached_width; end }),
            frame.number('Down the screen', 'detached_y', 0, 16384, 'The panel\'s top edge, in pixels from the top of the screen.', { of = panel_group, locks = true, edge = 'y', room_of = function(c) return panel_group(c).detached_height; end }),
        }, { only = in_panels, shown_by = panel_switches }),
        frame.tick('Snap back beside the game\'s list when released', 'snap', 'Let go of a panel of its own near either side of its group\'s game window to put the buffs back beside it. Turn this off to keep panels of their own where you leave them.', {
            of = native, locks = true, only = in_panels, shown_by = panel_switches, alias = 'Snap panels of their own to game windows Snap buff panels to game windows native detached attach snap move resize wrap width height game windows' }),
    }, { opened = true, only = any_group, shown_by = 'Which groups show' }),
    frame.fold('Member order', 'How a panel of its own orders its members.', {
        { kind = 'custom', draw = keep_pick('group') },
        frame.pick('Group to order', 'group', nil, group_names, 'Which group the slots below belong to.', { of = picks, transient = true, alias = 'Party group to edit', choices_of = panel_list }),
        frame.note('Members go by their slot in the game\'s party list. Reorder the slots here without changing the party itself.'),
        { kind = 'custom', draw = draw_slots },
    }, { key = 'Detached panel members', only = in_panels, shown_by = panel_switches, alias = 'Members in a panel of its own Detached panel members' }),
    frame.note(function(c)
        local native = c.callbacks and c.callbacks.party_native_status and c.callbacks.party_native_status();
        return native and native.geometry and native.geometry.reason or nil;
    end, { live = true }),
};

-- When to show, with what else can hide them.

local when_rows = {};
for index, item in ipairs(conditions_ui.rows) do when_rows[index] = item; end;
table.insert(when_rows, 3, frame.note('Party list buffs pause while the Treasure Pool is open.'));
table.insert(when_rows, 3, frame.note('Your own row, on Show, can hide the party list buffs while you are solo too.'));

frame.register({
    id = 'party_ui', name = 'Party list buffs', fold_page = 'Party & alliance',
    tabs = { show = show_rows, look = look_rows, filters = filter_rows, place = place_rows, when = when_rows },
    header = header, under = under,
    unlocked = function(c)
        return widget.in_panels(c.p) and 'Unlocked: hold Shift and drag a group to move it, or drag a panel\'s edge to resize it.' or 'Unlocked: hold Shift and drag a group to move it.';
    end,
});

return page;
