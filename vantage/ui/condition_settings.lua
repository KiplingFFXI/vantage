-- When to show: when a display shows (core/conditions.lua), by jobs, level, Level Sync, zones, party, engaged and pet. These
-- are the rows of every display's When to show tab. The jobs and the zones each fold to a line that says what they pick.
local conditions = require('core.conditions');
local elements = require('ui.elements');
local frame = require('ui.panel_frame');
local page = {};
local ctx = frame.ctx;
local sync_names = { any = 'Either', yes = 'Only while synced', no = 'Only while not synced' };
local fight_names = { any = 'Either', yes = 'Only while engaged', no = 'Only while not engaged' };
local pet_names = { any = 'Either', yes = 'Only with a pet out', no = 'Only with no pet out' };
local list_names = { only = 'Only these', except = 'All but these' };
local zone_help = {
    town = 'Towns, from the Phoenix zone data.', field = 'Fields, including the airships and the pirate ferries.',
    dungeon = 'Dungeons, from the Phoenix zone data.',
    battlefield = 'While you have the Battlefield status: from registering for a battlefield until you leave it.',
    dynamis = 'The Dynamis zones.', limbus = 'Temenos and Apollyon.', assault = 'The five Assault zones.',
    salvage = 'The four Remnants zones.', nyzul = 'Nyzul Isle.', ashu_talif = 'The Ashu Talif.',
    mog_house = 'Inside a Mog House, from the zone you entered. After a reload in one, Vantage knows at the next zone.',
    other = 'Zones with no kind of their own, such as the ferries to Selbina and Mhaura and the battlefield arenas.',
};

-- Phoenix's level cap. Levels go up to it, and it stands for no top, kept as the 99 a fresh condition has.
local TOP = 75;

-- What still shows a display its conditions hide: edit mode doesn't place overhead icons, and the pulse has no samples.
local anyway = { overhead = 'Samples show it anyway.', pulse = 'A test pulse and Arrange on screen show it anyway.' };

-- The rows of the display the frame has open.
local function build()
    local function id_of() return ctx.id; end;
    local function value() return elements.conditions(ctx.s, id_of()); end;
    local suffix = '';
    -- A fold of ticks, titled with what they pick, with Only these or All but these over them.
    local function listed(text, key, except, side, ticks, every, help)
        local mode = frame.radio(side == 'where' and 'Show it in' or 'Show it for', nil, { 'only', 'except' }, list_names, 'Only these shows it for what is ticked. All but these shows it for everything else.', {
            tag = '_' .. side .. '_list' .. suffix, find = text .. ': only these or all but these', alias = 'except exclude every all but not',
            read = function() return value()[except] and 'except' or 'only'; end,
            write = function(_, chosen) value()[except] = chosen == 'except'; end });
        return frame.fold(text, help, { mode, frame.line(nil, nil, ticks, { every = every }) }, {
            key = text, tag = '_' .. side .. '_fold' .. suffix, title = function() return text .. ': ' .. conditions.picks(value(), key); end });
    end;
    local function jobs(text, key, except, side, help)
        local rows = {};
        for job, name in ipairs(conditions.jobs) do
            rows[job] = frame.tick(name, nil, help, { tag = '_' .. side .. suffix,
                read = function() return value()[key][job] == true; end,
                write = function(_, on) value()[key][job] = on or nil; end });
        end;
        return listed(text, key, except, side, rows, 6, 'Leave every job unticked for any job.');
    end;
    local zones = {};
    for index, kind in ipairs(conditions.zone_kinds) do
        zones[index] = frame.tick(conditions.zone_names[kind], nil, zone_help[kind], { tag = '_zone' .. suffix,
            read = function() return value().zones[kind] == true; end,
            write = function(_, on) value().zones[kind] = on or nil; end });
    end;
    local groups = {};
    for index, kind in ipairs(conditions.groups) do
        groups[index] = frame.tick(conditions.group_names[kind], nil, nil, { tag = '_group' .. suffix,
            read = function() return value().group[kind] == true; end,
            write = function(_, on) value().group[kind] = on or nil; end });
    end;
    return {
        frame.note(function()
            local id = id_of();
            return 'Always, unless you choose something here. Every condition you set must hold; one with several picks holds for any of them. '
                .. (id == 'notices' and 'While they hide Alerts, no alert plays, in chat or as a sound. Tracking goes on. '
                    or 'They hide only the display: tracking and alerts go on. ')
                .. (anyway[id] or 'Samples and Arrange on screen show it anyway.');
        end),
        frame.note(function() return elements.label(id_of()) .. ': ' .. table.concat(conditions.describe(value()), ' '); end),
        jobs('Main job', 'main_jobs', 'main_except', 'main', 'Show it while this is your main job.'),
        jobs('Support job', 'sub_jobs', 'sub_except', 'sub', 'Show it while this is your support job.'),
        frame.line('Level', 'Your main job\'s level as the game shows it, lowered under Level Sync or a level cap.', {
            frame.number('From', 'level_min', 1, TOP, 'It shows from this level.', { tag = '_min' .. suffix, find = 'Lowest level', width = 110, of = value,
                format = 'From %.0f', read = function() return math.min(value().level_min, TOP); end, write = function(_, chosen)
                    local kept = value();
                    kept.level_min = chosen;
                    if kept.level_max < chosen then kept.level_max = chosen >= TOP and 99 or chosen; end;
                end }),
            frame.number('To', 'level_max', 1, TOP, 'It shows up to this level. ' .. TOP .. ' leaves no top.', { tag = '_max' .. suffix, find = 'Highest level', width = 110, of = value,
                format = 'To %.0f', read = function() return math.min(value().level_max, TOP); end, write = function(_, chosen)
                    local kept = value();
                    kept.level_max = chosen >= TOP and 99 or chosen;
                    if kept.level_min > chosen then kept.level_min = chosen; end;
                end }),
        }, { tag = '_level' .. suffix }),
        frame.radio('Level Sync', 'level_sync', conditions.states, sync_names, 'Whether you are Level Synced.', { tag = '_sync' .. suffix, of = value }),
        listed('Where', 'zones', 'zones_except', 'where', zones, 4, 'Leave every kind unticked for any zone.'),
        frame.line('Party', 'Solo, party or alliance as the game\'s party list shows it. Leave them unticked for any.', groups, { tag = '_party' .. suffix, alias = 'Party and fight' }),
        frame.radio('Fighting', 'engaged', conditions.states, fight_names, 'Whether you are engaged.', { tag = '_fight' .. suffix, alias = 'Engaged combat', of = value }),
        -- The Pet display shows only with a pet out, so it has the row only to take off a pick saved before.
        frame.radio('Pet', 'pet', conditions.states, pet_names, 'Whether you have a pet out.', { tag = '_pet' .. suffix, of = value,
            only = function() return id_of() ~= 'pet' or value().pet ~= 'any'; end }),
        frame.note(function()
            local id = id_of();
            if not conditions.any(value()) then return conditions.where(); end;
            return (conditions.shown(id) and 'Right now it shows. ' or 'Right now its conditions hide it. ') .. conditions.where();
        end, { live = true }),
    };
end;

page.rows = build();

return page;
