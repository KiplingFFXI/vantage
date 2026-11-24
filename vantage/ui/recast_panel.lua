-- The editor of the recast panels, as one display on the panel frame: the three kinds, one at a time, or the one panel for
-- all of them, whichever is in use. Its Size and place, Look and Filters are the status panels', and it links to the ready
-- pulse's own editor (ui/pulse_settings.lua).
local conditions_ui = require('ui.condition_settings');
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
-- Whether a panel shows this kind of recast.
local function kind_on(c, kind)
    if separate(c) then return c.s.panels[kind .. '_recasts'].enabled; end;
    return c.s.panels.recasts.enabled and c.s.panels.recasts.recast_categories[kind];
end;
local function spells_on(c) return kind_on(c, 'spell'); end;
local function abilities_on(c) return kind_on(c, 'ability'); end;

-- Tints.

local tint_colors = require('core.recast_tints').make();

-- A mark shows on a row of its kind, so it goes while no panel shows those. The tints are one for every recast panel, so
-- Reset this tab leaves them as Reset all of this display does.
local function tint_line(text, key, color_name, help, alias, on)
    return frame.line(nil, nil, {
        frame.tick(text, key, help, { of = tints, alias = alias, own = true }),
        frame.color('Color', key .. '_color', nil, { tag = '_' .. key, find = color_name, of = tints, own = true, fallback = function() return tint_colors[key .. '_color']; end }),
    }, { only = on, shown_by = 'Show this display' });
end;

local tint_fold = frame.fold('Tint recasts I can\'t use right now', 'A tint shows while a recast row can\'t be used. It never covers the countdown.', {
    tint_line('Spells while my MP is too low', 'mp', 'MP tint color', 'A spell row tints while your MP is below the spell\'s cost. Manafont stops it. Gear that lowers the cost isn\'t counted.', 'Tint spells I can\'t afford', spells_on),
    tint_line('Spells while Silenced or Muted', 'spell_lock', 'Spell lock color', 'Spell rows turn grey with a lock and the lock\'s time left, when the game gives it.', 'Lock spells while Silenced or Muted', spells_on),
    tint_line('Abilities under Amnesia', 'ability_lock', 'Ability lock color', 'Ability rows turn grey with a lock and the lock\'s time left, when the game gives it.', 'Lock abilities under Amnesia', abilities_on),
    frame.note('In Salvage, Omerta locks spells and Impairment locks abilities too. In Nyzul Isle nothing is locked.'),
}, { key = 'Recast tints', alias = 'Recast marks tints Mark recasts I can\'t use right now', shown_by = 'Show this display', only = function(c) return spells_on(c) or abilities_on(c); end });

-- Show.

local icon_note, text_note = status.part_notes('Icons always shows the icon and its countdown.', 'Text always shows each name and its countdown.');

local show_rows = {
    -- Show as, and Icons show below, are one for every recast panel, so Reset this tab leaves them as Reset all of this
    -- display does.
    frame.radio('Show as', 'recast_display', { 'separate', 'combined' }, { separate = 'A panel for each kind', combined = 'One panel for all' },
        'Each way keeps its own size, place, look and filters.', { of = status.root, own = true, alias = 'Recast display Separate panels One combined panel Combined' }),
    -- Item recasts are off when Ashita's item data library can't load on this client.
    frame.note(function(c)
        local items = c.callbacks and c.callbacks.recast_item_status and c.callbacks.recast_item_status();
        return items and items.available == false and items.reason or nil;
    end, { live = true }),
    status.layout_row(),
    frame.pick('Sort', 'sort', { 'remaining', 'name', 'fixed' }, { remaining = 'Ready soonest', name = 'Name', fixed = 'My order' }, 'Pinned rows stay first. Add rows to My order on the Filters tab.', { alias = 'Sort cooldowns' }),
    status.empty_order,
    status.order_line,
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
        'A spell or ability that gives a buff or debuff shows that status icon. Others, shared timers and items keep their own picture.',
        { of = style, own = true, alias = 'Recast icons show Buff and debuff icons Action icons' }),
    tint_fold,
    frame.button('Make an alert for a recast', 'Opens Alerts with a new rule for a recast: choose the recast, when it goes off and how it tells you.', function(c)
        require('ui.alert_panel').new_rule(c, { name = 'Recast ready', domain = 'recast', event = 'ready', scope = 'self' });
        c.open_page('Display', 'notices', 'show');
    end, { alias = 'Add recast alert' }),
    status.copy_line,
    frame.button('Edit the ready pulse', 'A short pulse when a long recast is ready. It has an editor of its own.', function(c)
        c.open_page('Display', 'pulse', 'show');
    end, { alias = 'Ready pulse settings' }),
};

-- Copy this tab to goes to the other two kinds, while each has a panel.
local look_rows = status.look_rows('Ready soon', 'Rows with no countdown show an empty track.');
local others, none = {}, {};
for _, id in ipairs(kinds) do
    others[id] = {};
    for _, other in ipairs(kinds) do if other ~= id then others[id][#others[id] + 1] = other; end; end;
end;

frame.register({
    id = 'recasts', name = 'Recasts', fold_page = 'Recasts', panels = kinds,
    tabs = {
        show = show_rows, look = look_rows,
        filters = status.filter_rows(true), place = status.place_rows(), when = conditions_ui.rows,
    },
    header = status.header_rows(),
    -- Which of the three the tabs change, above them so it shows on every tab.
    under = { frame.pick('Editing', 'id', kinds, kind_names, 'Which of the three panels the tabs change.', { only = separate, shown_by = 'Show as',
        transient = true, buttons = true, of = function() return editing; end, write = function(_, id) frame.open(id); end }) },
    tab_reset = { filters = status.filter_reset.filters, look = frame.reset_keys({ 'title', unpack(status.copy_lists(look_rows).look) }) },
    copy = status.copy_lists(look_rows, true), copy_to = function(c) return separate(c) and others[c.id] or none; end,
    fill = function(c) c.id = separate(c) and editing.id or 'recasts'; end,
    pick = function(id) if kind_names[id] then editing.id = id; end; end,
    title_of = function(c) return separate(c) and 'Recasts: ' .. kind_names[c.id] or elements.label('recasts'); end,
    name_of = function(c) return elements.label(c.id); end,
    reset_note = function() return ' Recast tints and the ready pulse stay as they are.'; end,
});

return page;
