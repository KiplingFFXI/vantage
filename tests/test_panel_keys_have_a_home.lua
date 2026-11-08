-- Every key of a timer or recast panel, of the recast tints, the ready pulse, When to show and Moves with, of Party
-- list buffs, Overhead icons, Party cooldowns, Phantom Roll, Pet, Alerts and its rules and Hidden everywhere and its
-- rules is written by a row of a panel, by a named control, or is on a kept list with its reason. So is every other key
-- of a save, on the main page, Timer durations, Profiles and sharing or Help. A key that loses its control fails here,
-- and so does a new key with no line.
local h = require('panel_fixture')();
local defaults = require('ui.defaults');
local panels, window = h.panels, h.window;

-- The keys the rows of every display write by name.
local written = {};
local function walk(rows)
    for _, item in ipairs(rows) do
        if type(item.key) == 'string' and item.kind ~= 'fold' then written[item.key] = true; end;
        if item.rows then walk(item.rows); end;
    end;
end;
panels.index({});
assert(#panels._displays >= 13, 'Fixture: the thirteen displays are on the frame.');
for _, display in ipairs(panels._displays) do
    for _, rows in pairs(display.tabs) do walk(rows); end;
    walk(display.header);
    walk(display.under or {});
end;

-- Keys a row writes through a table or by hand, by the row's search name.
local by_row = {
    enabled = 'Show this display', x = 'Across', y = 'Down', stack_direction = 'Fills', growth = 'Fills', anchor = 'Moves with',
    conditions = 'Main job', colors = 'Background color', effect_colors = 'Effect color', labels = 'Rename it', order = 'Add to My order',
    include = 'Show this effect only', exclude = 'Hide here', pinned = 'Pin first', groups = 'Kinds of effects', members = 'Members',
    field_order = 'Parts of a row', field_labels = 'Part label',
    field_colors = 'Part color', field_alignments = 'Part line up', field_dividers = 'Divider before it', field_newlines = 'Start a new line',
    field_priority = 'Priority when space is short', ignore = 'Never pulse for', locked = 'Locked',
    -- A condition's parts, and Moves with's.
    main_jobs = 'Main job', sub_jobs = 'Support job', zones = 'Where', group = 'Party', to = 'Moves with', element = 'Moves with',
    -- Party list buffs, Overhead icons and Party cooldowns.
    effects = 'Countdowns', native = 'Longest row', style = 'Party buff icons', include_self = 'Your own row', show_solo = 'Your own row',
    fit_all = 'Most per member', head = 'Head height offset', offsets = 'Add head offset',
    types = 'Change the settings for', mob = 'Change the settings for', units = 'Your target', list = 'In a list', jobs = 'WHM', abilities = 'Clear list filters',
    native_x = 'Put moved groups back', native_y = 'Put moved groups back', native_side = 'Put moved groups back',
    native_detached = 'Your party in a panel of its own', alliance1 = 'Alliance 1', alliance2 = 'Alliance 2',
    -- Pet, Alerts and Hidden everywhere.
    show_effects = 'Effects', kinds = 'Effects', notice_x = 'Across', notice_y = 'Down', notice_locked = 'Locked', notice_anchor = 'Moves with',
    notice_conditions = 'Main job', rules = 'Your alerts', thresholds = 'Thresholds, separated by commas',
};
-- Keys one control on the main page writes on every display.
local on_main_page = {
    countdown_bold = 'Bold countdowns', countdown_shadow = 'Countdown shadow', countdown_outline = 'Countdown outline', countdown_outline_color = 'Countdown outline color',
    blink_icons = 'Blink before an effect ends', blink_seconds = 'Blink seconds left', recast_categories = 'Recasts',
    muted = 'Unmute',
};
-- Keys with no control, and why they stay.
local kept = {
    horizon = 'How much a bar spans when the full length was not seen.',
};
-- The same for the four displays below, whose keys sit in tables of their own.
local kept_inside = { camera = 'How the camera is read.',
    separate = 'How a party row packs its icons.',
    name_lift = 'Only the guess reads it, and /vg set reaches it.',
    name_cap = 'As name_lift.', name_height = 'As name_lift.', target_cap = 'As name_lift.', target_height = 'As name_lift.',
    ref_depth = 'What a medium unit at 10 yalms means.', ref_hitbox = 'As ref_depth.', s_max = 'As ref_depth.', s_min = 'As ref_depth.',
    heights = 'The guess of a head\'s height, which Head height offset and the offsets by name move.', sizes = 'As heights.',
    race_heights = 'As heights.', default_height = 'As heights.', default_hitbox = 'As heights.', chair_factor = 'As heights.', sit_factor = 'As heights.',
    mob_height_base = 'As heights.', mob_height_max = 'As heights.', mob_height_min = 'As heights.', mob_height_per_hitbox = 'As heights.',
    mounted_base = 'As heights.', mounted_factor = 'As heights.',
};

local function home(key, where)
    if written[key] then return; end;
    if by_row[key] then
        assert(require('ui.search_index').controls.Display[by_row[key]], where .. key .. ' has a row: ' .. by_row[key]);
        return;
    end;
    if on_main_page[key] then
        assert(require('ui.search_index').controls.Home[on_main_page[key]], where .. key .. ' has its control on the main page: ' .. on_main_page[key]);
        return;
    end;
    assert(kept[key] or kept_inside[key], where .. key .. ' has lost its control.');
end;

local fresh = defaults.make();
for _, id in ipairs(defaults.panel_order) do
    for key in pairs(fresh.panels[id]) do home(key, id .. '.'); end;
    for key in pairs(fresh.panels[id].conditions) do home(key, id .. '.conditions.'); end;
    for key in pairs(fresh.panels[id].anchor) do home(key, id .. '.anchor.'); end;
end;
for key in pairs(fresh.ready_pulse) do home(key, 'ready_pulse.'); end;
for key in pairs(fresh.recast_tints) do home(key, 'recast_tints.'); end;
-- What's in a kept table goes with it, and a table of ids or names holds no keys of ours.
local function every(value, where)
    for key, item in pairs(value) do
        if type(key) == 'string' then home(key, where); end;
        if type(item) == 'table' and not kept_inside[key] then every(item, where .. tostring(key) .. '.'); end;
    end;
end;
for _, id in ipairs({ 'party_ui', 'overhead', 'party_cooldowns', 'rolls', 'pet', 'alerts', 'effect_filters' }) do every(fresh[id], id .. '.'); end;
every(defaults.tidy(defaults.make()).alerts, 'alerts.');
every(defaults.rule('alert_1'), 'An alert rule: ');
every(require('core.effect_filters').rule(), 'A hide rule: ');
assert(require('ui.search_index').controls.Display['Hidden everywhere'], 'effect_filters.rules has its list.');

-- The rest of a save: where a player sets each key, as a page and the control's name in the search.
local HIDE_WITH_GAME = 'Home/Hide Vantage in cutscenes, on the map and when the game hides its menus';
local homes = {
    enabled = 'Home/Resume', preview = 'Home/Show samples', active_profile = 'Profiles/Load profile', job_profiles = 'Profiles/Load this profile when I change to',
    shared_layout = 'Profiles/Share settings across my characters', shared_scope = 'Profiles/What to share across characters',
    watch_ids = 'Display/Watching', recast_display = 'Display/Show as',
    ['tracking.follow_subtarget'] = 'Display/Follow the cursor while I am choosing a target',
    ['diagnostics.record'] = 'Help/Record recent events',
    ['durations.overrides'] = 'Durations/Add duration override', ['durations.learn'] = 'Durations/Learn from my casts',
    ['durations.learn_samples'] = 'Durations/Casts before a learned time is used', ['durations.learned'] = 'Durations/Clear learned durations',
    ['visibility.hide_events'] = HIDE_WITH_GAME, ['visibility.hide_map'] = HIDE_WITH_GAME, ['visibility.hide_ui'] = HIDE_WITH_GAME,
    ['visibility.hide_typing'] = 'Home/Hide timer panels while I type',
    ['window.peek'] = 'Home/Hold Shift to see through this window', ['window_style.font_size'] = 'Home/Settings text size',
    ['edit_mode.grid_mode'] = 'Home/Grid mode', ['edit_mode.grid_displays'] = 'Home/Self buffs for Grid mode', ['edit_mode.grid'] = 'Home/Grid size',
    ['edit_mode.show_grid'] = 'Home/Show the grid', ['edit_mode.snap_grid'] = 'Home/Snap to the grid', ['edit_mode.snap_screen'] = 'Home/Snap to the screen center and edges',
    ['edit_mode.snap_elements'] = 'Home/Snap to other displays', ['edit_mode.snap_party'] = "Home/Snap to the game's party list",
    ['edit_mode.snap_chat'] = 'Home/Snap to the chat log', ['edit_mode.snap_distance'] = 'Home/Snap distance',
    ['style.theme'] = 'Home/Skin', ['style.font'] = 'Home/Font', ['style.font_size'] = 'Home/Text size', ['style.scale'] = 'Home/Size',
    ['style.icon_art'] = 'Home/Icons', ['style.recast_icon_art'] = 'Home/Recast icons', ['style.gauge_art'] = 'Home/Gauges', ['style.window_type'] = 'Home/Window frame',
    ['style.recast_icon_source'] = 'Display/Icons show',
    ['style.icon_size'] = 'Home/Icon size', ['style.bar_height'] = 'Home/Row height', ['style.gap'] = 'Home/Space between rows', ['style.title_size'] = 'Home/Heading size',
    ['style.opacity'] = 'Home/Opacity', ['style.rounding'] = 'Home/Corner rounding', ['style.background'] = 'Home/Background', ['style.border'] = 'Home/Border',
    ['style.minimal'] = 'Home/No boxes or headings', ['style.hover'] = 'Home/Show details when I point at a timer',
    ['style.text_shadow'] = 'Home/Other text shadow', ['style.text_outline'] = 'Home/Other text outline', ['style.outline_color'] = 'Home/Other text outline color',
    ['style.status_time_color'] = 'Home/Color each countdown by how sure Vantage is of its time',
};
-- Each shared color is a row under Colors, by the name the theme gives it.
for _, field in ipairs(require('ui.theme').fields) do
    if not field.no_control then homes['style.' .. field[1]] = homes['style.' .. field[1]] or 'Home/' .. field[2]; end;
end;
-- Keys with no control on those pages, and why they stay. A whole table's reason covers its keys.
local kept_keys = {
    chat_colors = 'They have no row in the window: /vg set, /vg chatsample and /vg reset chat_colors reach them.',
    ['window.open'] = 'Whether the window is open.', ['window.tab'] = 'The page it opens on.', ['window.sections'] = 'Which folds are open.',
    ['window.x'] = 'Where the window is, which moving it sets.', ['window.y'] = 'As window.x.', ['window.width'] = 'As window.x.', ['window.height'] = 'As window.x.',
    ['style.unknown_color'] = 'The skin sets it, and the window\'s faded text reads it.',
    ['tracking.stale_seconds'] = 'How long an unseen subject stays.', ['tracking.max_entities'] = 'As stale_seconds.',
    ['diagnostics.max_entries'] = 'How much the record keeps.',
};
local on_the_displays = { panels = true, ready_pulse = true, recast_tints = true, party_ui = true, overhead = true, party_cooldowns = true, rolls = true, pet = true,
    alerts = true, effect_filters = true };
local index = require('ui.search_index');
for path, spot in pairs(homes) do
    local page, label = spot:match('^(%a+)/(.+)$');
    assert(index.controls[page][label], path .. ' has its control: ' .. spot);
    local top, inner = path:match('^([^.]+)%.?(.*)$');
    assert(inner == '' and fresh[top] ~= nil or inner ~= '' and fresh[top][inner] ~= nil, 'A home is for a key of a fresh save: ' .. path);
end;
for path in pairs(kept_keys) do
    local top, inner = path:match('^([^.]+)%.?(.*)$');
    assert(inner == '' and fresh[top] ~= nil or inner ~= '' and fresh[top][inner] ~= nil, 'Kept means still in a fresh save: ' .. path);
end;
for key, value in pairs(fresh) do
    if not on_the_displays[key] and not homes[key] and not kept_keys[key] then
        assert(type(value) == 'table', key .. ' has lost its control.');
        for inner in pairs(value) do
            assert(homes[key .. '.' .. inner] or kept_keys[key .. '.' .. inner], key .. '.' .. inner .. ' has lost its control.');
        end;
    end;
end;
assert(written.recast_display, 'Show as writes recast_display.');
for _, key in ipairs({ 'dispel_light', 'dispel_color', 'dispel_glow', 'follow_subtarget', 'preview', 'list_debuffed',
    'dock_match_width', 'warning_enabled', 'warning_seconds', 'warning_mark', 'item_width', 'fill_direction', 'row_height', 'show_text' }) do
    assert(written[key], key .. ' has its row.');
end;

-- The kept keys stay in a fresh save, and a saved value of one comes through tidy, on a panel that has no row for it.
local s = defaults.make();
s.panels.self_buffs.horizon = 600;
s = defaults.tidy(s);
assert(s.panels.self_buffs.horizon == 600, 'A kept key keeps its saved value.');
for key in pairs(kept) do
    assert(fresh.panels.self_buffs[key] ~= nil or fresh.panels.spell_recasts[key] ~= nil, 'Kept means still in a fresh save: ' .. key);
end;
local o = fresh.overhead;
for key in pairs(kept_inside) do
    assert(fresh.party_ui.effects[key] ~= nil or o[key] ~= nil or o.head[key] ~= nil or o.layout[key] ~= nil or o.size[key] ~= nil or o.types.mob[key] ~= nil,
        'Kept means still in a fresh save: ' .. key);
end;
-- These have no control, and a saved value of each keeps working, as a saved accent color does. The main page's paused
-- line has Resume.
local saved = defaults.make();
saved.style.accent_color = { 0.1, 0.2, 0.3, 1 };
saved.tracking.stale_seconds, saved.tracking.max_entities, saved.diagnostics.max_entries = 60, 16, 77;
saved = defaults.tidy(saved);
assert(saved.style.accent_color[2] == 0.2 and saved.tracking.stale_seconds == 60 and saved.tracking.max_entities == 16
    and saved.diagnostics.max_entries == 77, 'A saved value of a key with no control keeps working.');
assert(require('ui.search_index').controls.Home.Resume, 'The main page has Resume.');
for _, label in ipairs({ 'Keep stale external observations', 'Maximum tracked subjects', 'Compact page selector', 'Maximum diagnostic entries' }) do
    for page, labels in pairs(require('ui.search_index').controls) do assert(not labels[label], label .. ' is no control, but it is on ' .. tostring(page)); end;
end;
MOCK.fire('unload');
return 'Every key of a display on the frame has a home or a reason';
