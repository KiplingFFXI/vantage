-- When to show: when a display shows (core/conditions.lua), by jobs, level, Level Sync, zones, party, engaged and pet. These
-- are the rows of every display's When to show tab.
local conditions = require('core.conditions');
local elements = require('ui.elements');
local frame = require('ui.panel_frame');
local page = {};
local ctx = frame.ctx;
local sync_names = { any = 'Either', yes = 'Only while synced', no = 'Only while not synced' };
local fight_names = { any = 'Either', yes = 'Only while engaged', no = 'Only while not engaged' };
local pet_names = { any = 'Either', yes = 'Only with a pet out', no = 'Only with no pet out' };
local zone_help = {
    town = 'Towns, from the Phoenix zone data.', field = 'Fields, including the airships and the pirate ferries.',
    dungeon = 'Dungeons, from the Phoenix zone data.',
    battlefield = 'While you have the Battlefield status: from registering for a battlefield until you leave it.',
    dynamis = 'The Dynamis zones.', limbus = 'Temenos and Apollyon.', assault = 'The five Assault zones.',
    salvage = 'The four Remnants zones.', nyzul = 'Nyzul Isle.', ashu_talif = 'The Ashu Talif.',
    mog_house = 'Inside a Mog House, from the zone you entered. After a reload in one, Vantage knows at the next zone.',
    other = 'Zones with no kind of their own, such as the ferries to Selbina and Mhaura and the battlefield arenas.',
};

-- What still shows a display its conditions hide: edit mode doesn't place overhead icons, and the pulse has no samples.
local anyway = { overhead = 'Samples show it anyway.', pulse = 'A test pulse and edit mode show it anyway.' };

-- The rows for one display's conditions. fixed is its id, if it isn't the display the rows are drawn for, and tag tells
-- its rows from those of the display beside it.
local function build(fixed, tag)
    local function id_of() return fixed or ctx.id; end;
    local function value() return elements.conditions(ctx.s, id_of()); end;
    local suffix = tag or '';
    local function jobs(text, key, side, help)
        local rows = {};
        for job, name in ipairs(conditions.jobs) do
            rows[job] = frame.tick(name, nil, help, { tag = '_' .. side .. suffix,
                read = function() return value()[key][job] == true; end,
                write = function(_, on) value()[key][job] = on or nil; end });
        end;
        return frame.line(text, 'Leave every job unticked for any job.', rows, { below = true, every = 6, tag = '_' .. side .. '_line' .. suffix });
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
            return 'Always, unless you choose something here. Every condition you set must hold; one with several picks holds for any of them. They hide only the display: tracking and alerts go on. '
                .. (anyway[id_of()] or 'Samples and edit mode show it anyway.');
        end),
        frame.note(function() return elements.label(id_of()) .. ': ' .. table.concat(conditions.describe(value()), ' '); end),
        jobs('Main job', 'main_jobs', 'main', 'Show it while this is your main job.'),
        jobs('Support job', 'sub_jobs', 'sub', 'Show it while this is your support job.'),
        frame.line('Level', 'Your main job\'s level as the game shows it, lowered under Level Sync or a level cap.', {
            frame.number('From', 'level_min', 1, 99, 'It shows from this level.', { tag = '_min' .. suffix, find = 'Lowest level', width = 110, of = value,
                format = 'From %.0f', write = function(_, chosen)
                    local kept = value();
                    kept.level_min = chosen;
                    if kept.level_max < chosen then kept.level_max = chosen; end;
                end }),
            frame.number('To', 'level_max', 1, 99, 'It shows up to this level.', { tag = '_max' .. suffix, find = 'Highest level', width = 110, of = value,
                format = 'To %.0f', write = function(_, chosen)
                    local kept = value();
                    kept.level_max = chosen;
                    if kept.level_min > chosen then kept.level_min = chosen; end;
                end }),
        }, { tag = '_level' .. suffix }),
        frame.radio('Level Sync', 'level_sync', conditions.states, sync_names, 'Whether you are Level Synced.', { tag = '_sync' .. suffix, of = value }),
        frame.line('Where', 'Leave every kind unticked for any zone.', zones, { tag = '_where' .. suffix, alias = 'Zones zone kinds', below = true, every = 4 }),
        frame.line('Party', 'Solo, party or alliance as the game\'s party list shows it. Leave them unticked for any.', groups, { tag = '_party' .. suffix, alias = 'Party and fight' }),
        frame.radio('Fighting', 'engaged', conditions.states, fight_names, 'Whether you are engaged.', { tag = '_fight' .. suffix, alias = 'Engaged combat', of = value }),
        frame.radio('Pet', 'pet', conditions.states, pet_names, 'Whether you have a pet out.', { tag = '_pet' .. suffix, of = value }),
        frame.note(function()
            local id = id_of();
            if not conditions.any(value()) then return conditions.where(); end;
            return (conditions.shown(id) and 'Right now it shows. ' or 'Right now its conditions hide it. ') .. conditions.where();
        end, { live = true }),
        frame.button('Clear these conditions', 'It always shows again.', function(c)
            local id = id_of();
            c.changed(function() elements.config(ctx.s, id)[elements.by_id[id].conditions] = conditions.make(); end, true,
                'Clear the When to show choices of ' .. elements.label(id));
        end, { tag = '_when' .. suffix, alias = 'Reset conditions when to show always' }),
    };
end;

page.rows = build();
-- The ready pulse has conditions of its own, in a fold of the Recasts panel's When to show.
page.pulse_rows = build('pulse', '_pulse');

return page;
