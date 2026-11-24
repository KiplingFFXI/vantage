-- The editor of party cooldowns (settings.party_cooldowns), as a display on the panel frame: what the watch counts and where
-- it shows, and the list display's size, sorting, filters and place. The frame goes by the list's id, so ctx.p is the list.
local conditions_ui = require('ui.condition_settings');
local cooldowns = require('core.party_cooldowns');
local frame = require('ui.panel_frame');
local party_defaults = require('ui.party_defaults');
local rows = require('ui.panel_rows');
local page = {};
local ctx = frame.ctx;
local jobs = require('data.shared_ids').jobs;
local sort_labels = { remaining = 'Ready soonest', name = 'Member name' };

local function watch(c) return c.s.party_cooldowns; end;
-- The list shows only while the watch is on.
local function list_on(c) return c.s.party_cooldowns.enabled and c.p.enabled; end;
-- Beside the party list and Over heads draw on other displays, so with those off, or not set to show the party, nothing
-- shows there.
local function wanted(c, place)
    local value = c.s.party_cooldowns;
    return value.enabled and value[place];
end;
-- Only the list has a place, a lock and filters of its own.
local function list_only(tab_rows) return frame.group(tab_rows, { only = list_on, shown_by = 'In a list' }); end;
local function strip_off(c) return wanted(c, 'strips') and not c.s.party_ui.enabled; end;
local function strip_unset(c) return wanted(c, 'strips') and c.s.party_ui.enabled and not cooldowns.beside_list(c.s); end;
local function heads_off(c) return wanted(c, 'overhead') and not c.s.overhead.enabled; end;
local function heads_unset(c) return wanted(c, 'overhead') and c.s.overhead.enabled and not cooldowns.over_heads(c.s); end;

-- Header.

local header = {
    frame.line(nil, nil, {
        frame.tick('On', 'enabled', 'Counts the abilities and spells ticked on Filters when a member uses them, and shows them where Show them says. Off, nothing is kept.', {
            tag = '_display', find = 'Show this display', alias = 'Watch party cooldowns Show this panel display', of = watch,
            write = function(c, on) cooldowns.switch(c.s, on); end }),
        rows.samples('Sample estimates in the list, to arrange it with nothing happening.', list_on, {
            of = watch, alias = 'Sample displays', off_note = 'Samples show in the list. Turn the display on and tick In a list first.' }),
        frame.tick('Locked', nil, frame.lock_row.help, { alias = frame.lock_row.alias, only = list_on, shown_by = 'In a list',
            read = frame.lock_row.read, write = frame.lock_row.write }),
    }),
};

-- Show.

-- A job's name on the left of its ticks, which start in one column down the fold. A tick with no room left on its line
-- starts the next one in that column.
local function job_line(name, entries)
    local ticks, each = {}, {};
    for index, info in ipairs(entries) do
        local recast = require('ui.countdown_text').time(info.recast);
        local help = info.spell and 'Spell. Base recast ' .. recast .. '. The game sends the real one with each cast.'
            or (info.special and 'Two-hour. ' or '') .. 'Recast ' .. recast .. '.';
        ticks[index] = frame.tick(info.name, nil, help, {
            tag = '_watch_' .. info.id, of = function(c) return c.s.party_cooldowns; end, resets = { 'ignore' },
            read = function(c) return not c.s.party_cooldowns.ignore[info.id]; end,
            write = function(c, on) c.s.party_cooldowns.ignore[info.id] = not on or nil; end });
        each[index] = { ticks[index] };
    end;
    return { kind = 'custom', rows = ticks, draw = function(imgui, c)
        if imgui.AlignTextToFramePadding then imgui.AlignTextToFramePadding(); end;
        imgui.TextUnformatted(name);
        imgui.SameLine(0, 3 * imgui.GetFontSize() - imgui.CalcTextSize(name));
        local column = imgui.GetCursorPosX();
        for index = 1, #ticks do
            if index > 1 then
                imgui.SameLine();
                if imgui.CalcTextSize(ticks[index].text) + imgui.GetFrameHeight() + 20 > imgui.GetContentRegionAvail() then
                    imgui.NewLine();
                    imgui.SetCursorPosX(column);
                end;
            end;
            frame.draw_rows(imgui, c, each[index]);
        end;
    end };
end;

local ability_rows = {};
for job, name in ipairs(jobs) do
    local entries = {};
    for _, info in ipairs(cooldowns.list) do if info.job == job then entries[#entries + 1] = info; end; end;
    if #entries > 0 then ability_rows[#ability_rows + 1] = job_line(name, entries); end;
end;
ability_rows[#ability_rows + 1] = frame.button('Watch every ability and spell', 'Ticks every one above again.', function(c)
    local config = ctx.s.party_cooldowns;
    c.changed(function() config.ignore = {}; end, true, 'Watch every ability and spell');
end);
-- The fold starts closed, so its title says how many are ticked. One title for each count, made once.
local watch_titles = {};
local watch_fold = frame.fold('Abilities and spells to watch', 'Untick one to stop counting it everywhere.', ability_rows, {
    title = function(c)
        local ignored, count = c.s.party_cooldowns.ignore, 0;
        for _, info in ipairs(cooldowns.list) do if not ignored[info.id] then count = count + 1; end; end;
        watch_titles[count] = watch_titles[count] or ('Abilities and spells to watch: %d of %d'):format(count, #cooldowns.list);
        return watch_titles[count];
    end });

-- Beside the party list and Over heads read as In a list does: off with the watch, and ticking one turns the watch on.
-- Beside the party list turns Party list on too, as the main page's tick does (ui/party_defaults.lua show_beside), and
-- Over heads shows your party on Overhead icons (core/party_cooldowns.lua place). Reset this tab puts the place back and
-- leaves the watch on or off, as On is above the tabs.
local function place_tick(text, key, help, alias)
    return frame.tick(text, key, help .. ' Turning it on turns this display on too.', { alias = alias, of = watch, resets = { key },
        read = function(c) return wanted(c, key); end,
        write = function(c, on)
            if key == 'strips' then party_defaults.show_beside(c.s, 'cooldowns', on); else cooldowns.place(c.s, key, on); end;
        end });
end;

local show_rows = {
    frame.line('Show them', 'Where the times show. An ability\'s is an estimate, and a spell\'s is the one the game sent.', {
        frame.tick('In a list', 'enabled', 'The list display: one row for each, with its member, ability or spell and time left. Turning it on turns this display on too.', {
            tag = '_list', alias = 'Show party cooldown list Cooldown list', read = list_on,
            write = function(c, on) cooldowns.place(c.s, 'list', on); end }),
        place_tick('Beside the party list', 'strips', 'Each member\'s times go first on their row beside the game\'s party list, nearest the game\'s window, after the distance while that\'s on.', 'Show on party list strips'),
        place_tick('Over heads', 'overhead', 'Each member\'s times go in a line on their overhead block.', 'Show over heads'),
    }),
    frame.problem(strip_off, 'Party list is off, so nothing shows beside the party list.', 'Turn on Party list',
        'To show only the cooldowns beside the party list, pick None on the Show tab of Party list.', 'Beside the party list',
        function(s) party_defaults.switch(s.party_ui, true); end),
    frame.problem(strip_unset, 'Party list has no group ticked, so nothing shows beside the party list.', 'Show beside your party\'s window',
        'Ticks Your party on the Show tab of Party list.', 'Beside the party list', function(s) s.party_ui.strips.party = true; end),
    frame.problem(heads_off, 'Overhead icons is off, so nothing shows over heads.', 'Turn on Overhead icons',
        'Buffs and debuffs show above heads too, as set on Overhead icons.', 'Over heads', function(s) s.overhead.enabled = true; end),
    frame.problem(heads_unset, 'Overhead icons isn\'t set to show your party or alliance.', 'Show your party over heads',
        'Ticks Your party on the Show tab of Overhead icons.', 'Over heads', function(s) s.overhead.units.party = true; end),
    rows.heading('Show the list\'s title.', list_on, 'In a list'),
    frame.pick('Sort', 'sort', cooldowns.sorts, sort_labels, 'Ready soonest puts the shortest time left first.', { only = list_on, shown_by = 'In a list', alias = 'Sort cooldowns' }),
    frame.number('Most shown', 'max_rows', 1, 64, 'Rows past this limit, or past the list\'s height, are not shown.', { only = list_on, shown_by = 'In a list', alias = 'Maximum visible cooldowns' }),
};

-- Filters. The watch list shows with the list off too, as it is what every place counts.

local job_ticks = {};
for job, name in ipairs(jobs) do
    job_ticks[job] = frame.tick(name, nil, 'Show abilities and spells of this job.', { tag = '_list_job', resets = { 'jobs' },
        read = function(c) return c.p.jobs[job] == true; end,
        write = function(c, on) c.p.jobs[job] = on or nil; end });
end;

local filter_rows = {
    frame.note('Leave every box unticked to show every job. Beside the party list and over heads show every watched ability and spell.'),
    frame.line(nil, nil, job_ticks, { every = 6 }),
};

-- Size and place.

local place_rows = rows.box_place(cooldowns.MIN_WIDTH, 'list', 'its rows');

frame.register({
    id = 'cooldown_list', name = 'Party cooldowns', fold_page = 'Cooldowns', reset_scope = 'party_cooldowns',
    tabs = { show = show_rows, filters = { list_only(filter_rows), watch_fold }, place = { list_only(place_rows) }, when = { list_only(conditions_ui.rows) } },
    tab_on = { place = list_on, when = list_on }, lock_on = list_on,
    -- Reset this tab on Show puts In a list back off, and the list's samples end with it, as they do when it is unticked.
    tab_reset = { show = function(c) if not list_on(c) then c.s.party_cooldowns.preview = false; end; end },
    header = header,
});

return page;
