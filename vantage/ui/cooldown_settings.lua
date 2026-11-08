-- The editor of party cooldowns (settings.party_cooldowns), as a display on the panel frame: what the watch counts and where
-- it shows, and the list display's size, sorting, filters and place. The frame goes by the list's id, so ctx.p is the list.
local conditions_ui = require('ui.condition_settings');
local cooldowns = require('core.party_cooldowns');
local frame = require('ui.panel_frame');
local party_defaults = require('ui.party_defaults');
local rows = require('ui.panel_rows');
local page = {};
local ctx = frame.ctx;
local jobs = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP' };
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
        frame.tick('On', 'enabled', 'Counts the abilities ticked on Show when a member uses them, and shows them where Show them says. Off, nothing is kept.', {
            tag = '_display', find = 'Show this display', alias = 'Watch party cooldowns Show this panel display', of = watch,
            write = function(c, on) cooldowns.switch(c.s, on); end }),
        rows.samples('Sample estimates in the list, to arrange it with nothing happening.', list_on, {
            of = watch, alias = 'Sample displays', off_note = 'Samples show in the list. Turn the display on and tick In a list first.' }),
        frame.tick('Locked', nil, frame.lock_row.help, { alias = frame.lock_row.alias, only = list_on, shown_by = 'In a list',
            read = frame.lock_row.read, write = frame.lock_row.write }),
    }),
};

-- Show.

-- A job's name on the left of its ticks, which start in one column down the fold.
local function job_line(name, entries)
    local ticks = {};
    for index, info in ipairs(entries) do
        ticks[index] = frame.tick(info.name, nil, (info.special and 'Two-hour. ' or '') .. 'Recast ' .. require('ui.countdown_text').time(info.recast) .. '.', {
            tag = '_watch_' .. info.id, beside = index > 1,
            read = function(c) return not c.s.party_cooldowns.ignore[info.id]; end,
            write = function(c, on) c.s.party_cooldowns.ignore[info.id] = not on or nil; end });
    end;
    return { kind = 'custom', rows = ticks, draw = function(imgui, c)
        if imgui.AlignTextToFramePadding then imgui.AlignTextToFramePadding(); end;
        imgui.TextUnformatted(name);
        imgui.SameLine(0, 3 * imgui.GetFontSize() - imgui.CalcTextSize(name));
        frame.draw_rows(imgui, c, ticks);
    end };
end;

local ability_rows = {};
for job, name in ipairs(jobs) do
    local entries = {};
    for _, info in ipairs(cooldowns.list) do if info.job == job then entries[#entries + 1] = info; end; end;
    if #entries > 0 then ability_rows[#ability_rows + 1] = job_line(name, entries); end;
end;
ability_rows[#ability_rows + 1] = frame.button('Watch every ability', 'Ticks every ability above again.', function(c)
    local config = ctx.s.party_cooldowns;
    c.changed(function() config.ignore = {}; end, true, 'Watch every ability');
end);

-- Beside the party list and Over heads read as In a list does: off with the watch, and ticking one turns the watch on.
local function place_tick(text, key, help, alias)
    return frame.tick(text, key, help .. ' Turning it on turns this display on too.', { alias = alias,
        read = function(c) return wanted(c, key); end,
        write = function(c, on)
            local value = c.s.party_cooldowns;
            value[key] = on;
            if on then value.enabled = true; end;
        end });
end;

local show_rows = {
    frame.line('Show them', 'Where the estimates show. The times are estimates.', {
        frame.tick('In a list', 'enabled', 'The list display: one row for each estimate, with its member, ability and time left. Turning it on turns this display on too.', {
            tag = '_list', alias = 'Show party cooldown list Cooldown list', read = list_on,
            write = function(c, on)
                c.p.enabled = on;
                if on then c.s.party_cooldowns.enabled = true; else c.s.party_cooldowns.preview = false; end;
            end }),
        place_tick('Beside the party list', 'strips', 'Each member\'s estimates go first on their row beside the game\'s party list, nearest the game\'s window.', 'Show on party list strips'),
        place_tick('Over heads', 'overhead', 'Each member\'s estimates go in a line on their overhead block.', 'Show over heads'),
    }),
    frame.problem(strip_off, 'Party list buffs is off, so nothing shows beside the party list.', 'Turn on Party list buffs',
        'To show only the cooldowns beside the party list, pick None on the Show tab of Party list buffs.', 'Beside the party list',
        function(s) party_defaults.switch(s.party_ui, true); end),
    frame.problem(strip_unset, 'Party list buffs has no group ticked, so nothing shows beside the party list.', 'Show beside your party\'s window',
        'Ticks Your party on the Show tab of Party list buffs.', 'Beside the party list', function(s) s.party_ui.strips.party = true; end),
    frame.problem(heads_off, 'Overhead icons is off, so nothing shows over heads.', 'Turn on Overhead icons',
        'Buffs and debuffs show above heads too, as set on Overhead icons.', 'Over heads', function(s) s.overhead.enabled = true; end),
    frame.problem(heads_unset, 'Overhead icons isn\'t set to show party or alliance members.', 'Show party members over heads',
        'Ticks Party members on the Show tab of Overhead icons.', 'Over heads', function(s) s.overhead.units.party = true; end),
    frame.fold('Abilities to watch', 'Untick an ability to stop counting it everywhere.', ability_rows, { opened = true }),
    rows.heading('Show the list\'s title.', list_on, 'In a list'),
    frame.pick('Sort', 'sort', cooldowns.sorts, sort_labels, 'Ready soonest puts the shortest time left first.', { only = list_on, shown_by = 'In a list', alias = 'Sort cooldowns' }),
    frame.number('Most shown', 'max_rows', 1, 64, 'Rows past this limit, or past the list\'s height, are not shown.', { only = list_on, shown_by = 'In a list', alias = 'Maximum visible cooldowns' }),
};

-- Filters.

local job_ticks = {};
for job, name in ipairs(jobs) do
    job_ticks[job] = frame.tick(name, nil, 'Show abilities of this job.', { tag = '_list_job',
        read = function(c) return c.p.jobs[job] == true or c.p.jobs[tostring(job)] == true; end,
        write = function(c, on)
            local kept = c.p.jobs;
            kept[job], kept[tostring(job)] = on or nil, nil;
        end });
end;

local filter_rows = {
    frame.note('Leave every box unticked to show every job. Beside the party list and over heads show every watched ability.'),
    frame.line(nil, nil, job_ticks, { every = 6 }),
    frame.button('Clear list filters', 'Show every job and ability in the list again.', function(c)
        local list = ctx.p;
        c.changed(function() list.jobs, list.abilities = {}, {}; end, true, 'Clear list filters');
    end, { alias = 'List filters' }),
};

-- Size and place.

local place_rows = {
    frame.locked_line,
    frame.number('Width', 'width', 160, 1400, 'The list\'s width.', { locks = true, alias = 'List width' }),
    frame.number('Tallest', 'height', 0, 16000, 'Fit follows its rows. A fixed height is at least 60 pixels.', { locks = true, edge = 'y', special = { [0] = 'Fit' }, alias = 'Maximum list height Automatic',
        write = function(c, value) c.p.height = value == 0 and 0 or math.max(60, value); end }),
};
for _, item in ipairs(frame.place_rows()) do place_rows[#place_rows + 1] = item; end;
place_rows[#place_rows + 1] = frame.put_back;

frame.register({
    id = 'cooldown_list', name = 'Party cooldowns', fold_page = 'Cooldowns', reset_scope = 'party_cooldowns',
    tabs = { show = show_rows, filters = { list_only(filter_rows) }, place = { list_only(place_rows) }, when = { list_only(conditions_ui.rows) } },
    tab_on = { filters = list_on, place = list_on, when = list_on }, lock_on = list_on,
    header = header,
});

return page;
