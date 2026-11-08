-- The editor of the recast panels, as one display on the panel frame: the three kinds, one at a time, or the one panel for
-- all of them, whichever is in use. Its Size and place, Look and Filters are the status panels', and the ready pulse lives here.
local conditions_ui = require('ui.condition_settings');
local defaults = require('ui.defaults');
local elements = require('ui.elements');
local frame = require('ui.panel_frame');
local status = require('ui.status_panel');
local page = {};
local ctx = frame.ctx;
local kinds = { 'spell_recasts', 'ability_recasts', 'item_recasts' };
local kind_names = {};
for _, id in ipairs(kinds) do kind_names[id] = elements.label(id); end;
-- Which of the three the tabs edit, while there is a panel for each. It lasts the session.
local editing = { id = kinds[1] };

local function separate(c) return c.s.recast_display ~= 'combined'; end;
local function style(c) return c.s.style; end;
local function tints(c) return c.s.recast_tints; end;
local function pulse(c) return c.s.ready_pulse; end;
local function pulse_on(c) return c.s.ready_pulse.enabled == true; end;
-- Whether a panel shows this kind of recast.
local function kind_on(c, kind)
    if separate(c) then return c.s.panels[kind .. '_recasts'].enabled; end;
    return c.s.panels.recasts.enabled and c.s.panels.recasts.recast_categories[kind];
end;
local function spells_on(c) return kind_on(c, 'spell'); end;
local function abilities_on(c) return kind_on(c, 'ability'); end;

-- Tints.

local tint_colors = require('core.recast_tints').make();

-- A mark shows on a row of its kind, so it goes while no panel shows those.
local function tint_line(text, key, color_name, help, alias, on)
    return frame.line(nil, nil, {
        frame.tick(text, key, help, { of = tints, alias = alias }),
        frame.color('Color', key .. '_color', nil, { tag = '_' .. key, find = color_name, of = tints, fallback = function() return tint_colors[key .. '_color']; end }),
    }, { only = on, shown_by = 'Show this display' });
end;

local tint_fold = frame.fold('Mark recasts I can\'t use right now', 'A mark shows while a recast row can\'t be used. It never covers the countdown.', {
    tint_line('Spells while my MP is too low', 'mp', 'MP mark color', 'A spell row tints while your MP is below the spell\'s cost. Manafont stops it. Gear that lowers the cost isn\'t counted.', 'Tint spells I can\'t afford', spells_on),
    tint_line('Spells while Silenced or Muted', 'spell_lock', 'Spell lock color', 'Spell rows turn grey with a lock and the lock\'s time left, when the game gives it.', 'Lock spells while Silenced or Muted', spells_on),
    tint_line('Abilities under Amnesia', 'ability_lock', 'Ability lock color', 'Ability rows turn grey with a lock and the lock\'s time left, when the game gives it.', 'Lock abilities under Amnesia', abilities_on),
    frame.note('In Salvage, Omerta locks spells and Impairment locks abilities too. In Nyzul Isle nothing is locked.'),
}, { key = 'Recast tints', alias = 'Recast marks tints', shown_by = 'Show this display', only = function(c) return spells_on(c) or abilities_on(c); end });

-- The ready pulse.

local pulse_defaults = require('core.ready_pulse').make();

local function ignore_recast(id)
    local c, s = ctx.c, ctx.s;
    if id ~= 0 then c.changed(function() s.ready_pulse.ignore[id] = true; end, true, 'Never pulse for ' .. c.effect_name(id, 'recast')); end;
end;

local function ignored_list(c)
    local out = {};
    for key in pairs(c.s.ready_pulse.ignore) do
        local id = tonumber(key) or key;
        out[#out + 1] = { id = id, key = key, line = status.plain_name(c.c, id, 'recast'), scope = 'pulse_ignore_' .. tostring(id) };
    end;
    table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id); end);
    return out;
end;

local ignored = { say = ignored_list, memo = {} };

local function draw_ignored(imgui, c, item)
    c.effect_picker(item.text, 0, ignore_recast, false, 'recast', 'Choose a recast');
    frame.lit(c, item);
    local list = frame.said(ignored);
    local kept = ctx.s.ready_pulse.ignore;
    for index = 1, #list do
        local entry = list[index];
        imgui.PushID(entry.scope);
        imgui.TextUnformatted(entry.line);
        imgui.SameLine();
        if imgui.Button('Pulse again') then c.changed(function() kept[entry.key] = nil; end, true, 'Pulse again for ' .. entry.line); end;
        c.tip('Take this recast off the list, so it pulses again.');
        imgui.PopID();
    end;
end;

local pulse_fold = frame.fold('Ready pulse', 'A short pulse when a long recast becomes ready. It only draws; nothing is used or sent.', {
    frame.tick('Pulse when a long recast is ready', 'enabled', 'A short pulse when a long recast is ready.', { of = pulse }),
    frame.problem(function(c) return defaults.pulse_has_no_row(c.s); end, 'No recast panel is on, so the pulse has no row to play on.', 'Use a spot of its own',
        'Sets Pulse spot to A spot of its own, which plays whether or not a panel shows the recast.', 'Pulse when a long recast is ready', function(s) s.ready_pulse.spot = 'screen'; end),
    frame.group({
        frame.number('Only recasts of at least', 'min_seconds', 0, 7200, 'Seconds. A recast is as long as its full cooldown when Vantage saw it start, else the most it saw left.', { of = pulse, top = 1200, alias = 'Shortest recast that pulses', format = '%.0f seconds' }),
        frame.number('Start early', 'early', 0, 600, 'Seconds before ready. Zero pulses when it is ready.', { of = pulse, alias = 'Pulse early by', format = '%.0f seconds' }),
        frame.number('Pulse for', 'length', 0.2, 5, 'How long it plays.', { of = pulse, whole = false, alias = 'Pulse length', format = '%.1f seconds' }),
        frame.number('Pulse size', 'size', 16, 256, 'How big the icon grows, in pixels at Size 1x, and 512 at most on screen. On a row it never goes under the row\'s own icon.', { of = pulse }),
        frame.color('Pulse color', 'color', nil, { of = pulse, fallback = function() return pulse_defaults.color; end }),
        frame.pick('Pulse spot', 'spot', require('core.ready_pulse').spots, { row = 'On its row', screen = 'A spot of its own' },
            'On its row pulses where a recast panel last drew that recast. A spot of its own pulses there, whether or not a panel shows the recast. Its spot is on Size and place.', { of = pulse }),
        frame.button('Show a test pulse', 'Plays one pulse now with a sample icon: on a recast row a panel shows, or at the spot.', function(c) c.call('test_pulse'); end),
        frame.custom('Never pulse for', 'Recasts that never pulse.', draw_ignored, { alias = 'ignore list recasts that never pulse Pulse again' }),
    }, { only = pulse_on, shown_by = 'Pulse when a long recast is ready' }),
}, { key = 'Ready pulse' });

-- Show.

local icon_note, text_note = status.part_notes('Icons always shows the icon and its countdown.', 'Text always shows each name and its countdown.');

local show_rows = {
    frame.radio('Show as', 'recast_display', { 'separate', 'combined' }, { separate = 'A panel for each kind', combined = 'One panel for all' },
        'Each way keeps its own size, place, look and filters.', { of = status.root, alias = 'Recast display Separate panels One combined panel Combined' }),
    frame.pick('Editing', 'id', kinds, kind_names, 'Which of the three panels the tabs change.', { only = separate, shown_by = 'Show as', transient = true,
        of = function() return editing; end, write = function(_, id) frame.open(id); end }),
    -- Item recasts are off when Ashita's item data library can't load on this client.
    frame.note(function(c)
        local items = c.callbacks and c.callbacks.recast_item_status and c.callbacks.recast_item_status();
        return items and items.available == false and items.reason or nil;
    end, { live = true }),
    status.layout_row(),
    frame.pick('Sort', 'sort', { 'remaining', 'name', 'fixed' }, { remaining = 'Ready soonest', name = 'Name', fixed = 'My order' }, 'Pinned rows stay first. My order is on Filters.', { alias = 'Sort cooldowns' }),
    status.empty_order,
    frame.pick('Group rows', 'group_by', { 'none', 'group' }, { none = 'Together', group = 'By cooldown group' }, 'Keeps related rows together before sorting within them.', {
        only = function(c) return not separate(c); end, shown_by = 'Show as' }),
    status.most_row('Recasts past this are not shown.'),
    status.empty_row(),
    frame.line('Each row shows', 'Which parts of a row show. Row text under Look places them.', {
        status.part_tick('Icon', 'icon'), status.part_tick('Name', 'name'),
        status.part_tick('Countdown', 'time'),
        status.part_tick('Time elapsed', 'elapsed'),
        status.part_tick('Full length', 'total', nil, { alias = 'Full duration' }),
    }, { only = status.bars, shown_by = 'Layout', alias = 'Visible fields fields' }),
    icon_note, text_note, status.no_text_note,
    frame.pick('Icons show', 'recast_icon_source', { 'effect', 'action' }, { effect = 'The effect it gives', action = 'The spell or ability' },
        'A spell or ability that gives a buff or debuff shows that status icon, in the buff icon artwork. Others, shared timers that could be several actions, and items keep their own picture.',
        { of = style, alias = 'Recast icons show Buff and debuff icons Action icons' }),
    tint_fold,
    frame.button('Make an alert for a recast', 'Opens Alerts with a new rule for a recast: choose the recast, when it goes off and how it tells you.', function(c)
        require('ui.alert_panel').new_rule(c, { name = 'Recast ready', domain = 'recast', event = 'ready', scope = 'self' });
        c.open_page('Display', 'notices', 'show');
    end, { alias = 'Add recast alert' }),
    pulse_fold,
};

-- Size and place: the panel's, and the pulse's own spot while it has one.

local function pulse_locked(c) return c.s.ready_pulse.locked ~= false; end;

local function place_rows()
    local rows = status.place_rows();
    local spot = frame.place_rows('pulse', nil, 'Pulse spot ', pulse_locked);
    table.insert(spot, 1, frame.note('Unlock it to move it.', { only = pulse_locked }));
    table.insert(spot, 1, frame.tick('Locked', 'locked', 'Locked, the spot stays fixed, including while Shift is held. Unlock it, then hold Shift and drag the spot.', {
        tag = '_pulse', find = 'Lock pulse spot', of = pulse }));
    table.insert(spot, 1, frame.heading('Pulse spot', 'Where the ready pulse plays, as A spot of its own.', { find = 'Pulse spot place' }));
    rows[#rows + 1] = frame.group(spot, { only = function(c) return pulse_on(c) and c.s.ready_pulse.spot == 'screen'; end, shown_by = 'Pulse spot' });
    return rows;
end;

-- When to show: the panel's, and the pulse's own conditions.

local function when_rows()
    local rows = {};
    for index, item in ipairs(conditions_ui.rows) do rows[index] = item; end;
    rows[#rows + 1] = frame.fold('When the pulse plays', 'The ready pulse has conditions of its own.', conditions_ui.pulse_rows, { alias = 'Ready pulse conditions',
        only = pulse_on, shown_by = 'Pulse when a long recast is ready' });
    return rows;
end;

frame.register({
    id = 'recasts', name = 'Recasts', fold_page = 'Recasts', panels = kinds,
    tabs = {
        show = show_rows,
        look = status.look_rows('Ready soon', 'Rows with no countdown show an empty track.'),
        filters = status.filter_rows(true), place = place_rows(), when = when_rows(),
    },
    header = status.header_rows(),
    fill = function(c) c.id = separate(c) and editing.id or 'recasts'; end,
    pick = function(id) if kind_names[id] then editing.id = id; end; end,
    title_of = function(c) return separate(c) and 'Recasts: ' .. kind_names[c.id] or elements.label('recasts'); end,
    name_of = function(c) return elements.label(c.id); end,
    reset_note = function() return ' Recast marks and the ready pulse stay as they are.'; end,
});

return page;
