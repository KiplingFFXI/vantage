-- The main page, where the window opens: what to show, in groups, how it looks and moving things. It draws
-- from the row tables below, made once at load, with plain imgui calls: a frame makes no closures and no value boxes, and
-- a click makes what it needs. The lines that name displays are worked out when the settings change, not each frame.
-- Edit on a row opens that display's own page.
local appearance = require('ui.appearance');
local controls = require('ui.controls');
local copy = require('core.store').copy;
local steady = require('core.steady');
local cooldowns = require('core.party_cooldowns');
local defaults = require('ui.defaults');
local elements = require('ui.elements');
local fonts = require('ui.fonts');
local frame = require('ui.panel_frame');
local game_buffs = require('core.game_buffs');
local icons = require('ui.icons');
local party_defaults = require('ui.party_defaults');
local shared_look = require('ui.shared_look');
local skin = require('ui.client_skin');
local snap = require('ui.snap');
local starters = require('core.starters');
local theme = require('ui.theme');
local bit = require('bit');
local page = {};

-- Every label the page draws, with its help, for the search index.
page.labels = {};
local function listed(row)
    page.labels[#page.labels + 1] = { row.search or row.text, row.help };
    row.caption = row.label and row.label:match('^(.-)##') or row.text;
    row.shown = row.label and row.caption .. '###' .. row.label;
    if row.edit then
        row.edit_search = 'Edit ' .. row.text;
        page.labels[#page.labels + 1] = { row.edit_search, row.edit_help };
    end;
    return row;
end;

-- A row of What to show. get and set read and write its switch; set runs inside one Undo step.
local function display(text, id, help, get, set, target, panel, place)
    return listed({ text = text, label = text .. '##main_' .. id, bare = '##main_' .. id, value = { false }, help = help, get = get, set = set,
        edit = 'Edit##main_' .. id, edit_help = 'Open the full editor for ' .. text .. '.', page = target, panel = panel, place = place });
end;

-- A tick that isn't a display's own switch.
local function option(text, id, help, search)
    return listed({ text = text, label = text .. '##main_' .. id, bare = '##main_' .. id, value = { false }, help = help, search = search });
end;

-- Turning a timer panel off ends its own samples, as a display's switch does.
local function timer(text, id, help)
    return display(text, id, (help and help .. ' ' or '') .. 'Empty timer panels stay hidden.',
        function(s) return s.enabled and s.panels[id].enabled; end,
        function(s, on) s.panels[id].enabled = on; if on then s.enabled = true; else s.panels[id].preview = false; end; end, 'Display', id);
end;

-- A display with a sample of its own: turning it off ends the sample.
local function element(text, id, help, target, panel)
    return display(text, id, help, function(s) return s[id].enabled; end,
        function(s, on) s[id].enabled = on; if not on then s[id].preview = false; end; end, target, panel);
end;

local recast_row = listed({ text = 'Recasts', edit = 'Edit##main_recasts', edit_help = 'Open the full editor for Recasts.',
    help = 'Which recasts show. Each kind has its own panel, or they share one, as Show as under Edit chooses.' });
local recast_kinds = {};
for index, kind in ipairs({ { 'spell', 'Spells', 'spell_recasts', 'Spell recasts' }, { 'ability', 'Abilities', 'ability_recasts', 'Ability recasts' },
    { 'item', 'Items', 'item_recasts', 'Item recasts' } }) do
    local row = option(kind[2], 'recast_' .. kind[1], 'Show this kind of recast.', kind[4]);
    row.key, row.panel = kind[1], kind[3];
    recast_kinds[index] = row;
end;
local pulse_row = display('Ready pulse', 'pulse', 'A short pulse when a long recast is ready.',
    function(s) return s.ready_pulse.enabled; end, function(s, on) s.ready_pulse.enabled = on; end, 'Display', 'pulse');
-- Party buffs and Party cooldowns: a tick for each place they show, on one line, and the Edit of the display that sets
-- them up. Beside the party list is Party list's, which shows the distance too, on a tick of its own.
local function place(text, id, search, help, read, write)
    local row = option(text, id, help, search);
    row.read, row.write = read, write;
    return row;
end;
local buffs_line = listed({ text = 'Party buffs', help = 'Your party\'s and alliance\'s buffs and debuffs, and where they show. Edit opens Party list, which links to the other two.',
    edit = 'Edit##main_party_ui', edit_help = 'Open the full editor for Party list.', page = 'Display', panel = 'party_ui', places = {
    place('In a list', 'party', 'Party members\' timers', 'Party members\' timers: a timer panel, with the time left when Vantage knows it.',
        function(s) return s.enabled and s.panels.party.enabled; end,
        function(s, on) s.panels.party.enabled = on; if on then s.enabled = true; else s.panels.party.preview = false; end; end),
    place('Beside the party list', 'party_ui', 'Party list', 'Party list: their icons beside the game\'s party list.',
        function(s) return s.party_ui.effects.kind ~= 'none' and cooldowns.beside_list(s); end,
        function(s, on) party_defaults.show_beside(s, 'effects', on); end),
    place('Over heads', 'party_heads', 'Party buffs over heads', 'Overhead icons, over your party\'s and alliance\'s heads. Turned on while Overhead icons is off, they show there alone.',
        function(s) return cooldowns.over_heads(s); end,
        function(s, on) require('ui.overhead_defaults').show_party(s.overhead, on); end),
} });
local cooldowns_line = listed({ text = 'Party cooldowns', help = 'When your party and alliance can use their two-hours, key abilities and Utsusemi again, counted from when Vantage saw them used.',
    edit = 'Edit##main_party_cooldowns', edit_help = 'Open the full editor for Party cooldowns.', page = 'Display', panel = 'cooldown_list', places = {
    place('In a list', 'cooldowns_list', 'Party cooldowns in a list', 'The Party cooldowns list: one row for each, with its member and time left.',
        function(s) return s.party_cooldowns.enabled and s.party_cooldowns.list.enabled; end,
        function(s, on) cooldowns.place(s, 'list', on); end),
    place('Beside the party list', 'cooldowns_strips', 'Party cooldowns beside the party list', 'Each member\'s times first on their row beside the game\'s party list. It turns Party list on too.',
        function(s) return s.party_cooldowns.enabled and s.party_cooldowns.strips and cooldowns.beside_list(s); end,
        function(s, on) party_defaults.show_beside(s, 'cooldowns', on); end),
    place('Over heads', 'cooldowns_heads', 'Party cooldowns over heads', 'Each member\'s times in a line on their overhead block. It turns Overhead icons on for your party too.',
        function(s) return s.party_cooldowns.enabled and s.party_cooldowns.overhead and cooldowns.over_heads(s); end,
        function(s, on) cooldowns.place(s, 'overhead', on); end),
} });
local distance_row = place('Show the distance to each member', 'distance', nil, 'How far each member is, beside the game\'s party list. It turns Party list on, alone there if Party list was off.',
    function(s) return s.party_ui.enabled and s.party_ui.distance == true; end,
    function(s, on) party_defaults.show_beside(s, 'distance', on); end);

local alerts_row = display('Alerts', 'alerts', 'Runs the rules you configured. Each rule keeps its own notices, sounds and chat.',
    function(s) return s.alerts.enabled; end, function(s, on) s.alerts.enabled = on; end, 'Display', 'notices');
local unmute = listed({ text = 'Unmute', label = 'Unmute##main_unmute', help = 'Notices and sounds come back. Old warnings are not replayed. /vg mute mutes them.' });

-- What to show, in groups under their captions. Recasts and Alerts draw rows of their own, and the rest are display rows.
local function group(text, help, rows) return { caption = help and listed({ text = text, help = help }) or { text = text }, rows = rows }; end;
local groups = {
    group('On you', 'Your own buffs and debuffs, your recasts and your pet.', {
        timer('Self buffs', 'self_buffs'), timer('Self debuffs', 'self_debuffs'), recast_row, pulse_row,
        element('Pet', 'pet', 'While you have a pet: its HP, MP and TP, its effects, your pet command recasts, a charm\'s estimated time, a jug\'s time left and a PUP\'s maneuvers.', 'Display', 'pet'),
    }),
    group('Target and enemies', 'Your target, the enemies you watch and the icons over heads.', {
        timer('Target timers', 'target', 'A timer panel for your target.'),
        timer('Watched enemy timers', 'watch', 'Timers for enemies you watch. Also list enemies I debuff, on its Show tab, adds the ones you debuff.'),
        element('Overhead icons', 'overhead', 'Shows buffs and debuffs above heads in the game world.', 'Display', 'overhead'),
    }),
    group('Party', 'Your party and alliance: their buffs, their cooldowns, how far they are and Phantom Roll.', {
        buffs_line, cooldowns_line, distance_row,
        element('Phantom Roll', 'rolls', 'While you or a party member rolls: the total, what it gives, lucky and unlucky numbers, the bust chance and who got it.', 'Display', 'rolls'),
    }),
    -- Its one row is Alerts too, so the search knows it by that row.
    group('Alerts', nil, { alerts_row }),
};

-- While playing: what every display does as you play.
local playing_row = listed({ text = 'While playing', help = 'What every display does as you play.' });
local hide_game_row = option('Hide Vantage in cutscenes, on the map and when the game hides its menus', 'hide_game',
    'Hides every display and this window at those times. Tracking goes on. Party list and Overhead icons hide then either way.');
local hide_typing_row = option('Hide timer panels while I type', 'hide_typing', 'Hides the timer panels while the chat line is open.');
local hover_row = option('Show details when I point at a timer', 'hover', 'Point at an effect for a moment to see its timing and full details. Clicks still pass through.');
local typing_and_hover = hide_typing_row.text .. hover_row.text;
-- It sets what "my target" is in core/client.lua. Overhead icons reads both target slots itself (core/overhead.lua).
local follow_row = option('Follow the cursor while I am choosing a target', 'follow_subtarget',
    'On, while you pick a target with the cursor, "my target" is the unit under it, for Target timers, alerts on your current target, the Pet display\'s Fighting line, Watch my target and Use my target\'s name. Off, it stays the target you had. Overhead icons shows both either way, as Your target and Your subtarget.');
local replace_row = option('Replace the game\'s buff icons', 'replace_buffs',
    'Hides the game\'s buff and debuff icons, so Self buffs and Self debuffs, both needed on, are the only ones. Vantage changes the game\'s memory for it, and puts it back when off.');
local pet_bar_row = option('Replace the game\'s pet bar', 'replace_pet_bar', 'Hides the game\'s pet name, HP and TP above the party list. It needs Pet on with Show HP, MP and TP. Vantage changes the game\'s memory for it, and puts it back when off.');
local both_replace = replace_row.text .. pet_bar_row.text;
local hide_keys = { 'hide_events', 'hide_map', 'hide_ui' };

local resume = listed({ text = 'Resume', label = 'Resume##main_resume', help = 'Restore the timer panels already chosen below.' });
local use_list = listed({ text = 'Use it again', label = 'Use it again##main_use_list', help = 'Puts your hide rules back to work.' });
local cooldown_list = listed({ text = 'Show them in a list', label = 'Show them in a list##main_cooldowns', help = 'Turns on the Party cooldowns list.' });
local pulse_spot = listed({ text = 'Use a spot of its own', label = 'Use a spot of its own##main_pulse',
    help = 'Sets Pulse spot to A spot of its own, which plays whether or not a panel shows the recast.' });
local show_displays = listed({ text = 'Show', label = 'Show##main_show', help = 'Show the Vantage displays again. Nothing is saved.' });
local end_edit = listed({ text = 'Done arranging', label = 'Done arranging##main_edit_end', help = 'Ends Arrange on screen. Every display stays where it is.' });

-- Quick setup for a role, whose picks and labels live here until the job changes.
local starter_row = listed({ text = 'Quick setup for a role', id = '##main_starter',
    help = 'Turns the displays a role wants on and the rest off. Your skin, fonts, colors, sizes, positions, locks, hide rules and saved profiles stay.' });
local starter_apply = listed({ text = 'Apply quick setup', label = 'Apply##main_starter',
    help = 'Sets up this role in one Undo step, with samples on its displays. Any alert rules it has are added, with Alerts on. Yours stay.' });
local starter_pick, starter_job, starter_note, starter_note_at;

-- How it looks.
local skin_labels = appearance.labels;
local skin_row = listed({ text = 'Skin', id = '##main_skin', choices = appearance.names, names = skin_labels,
    help = 'Applies this skin with its fonts and artwork to every display and this window. Sizes, positions, filters, locks, colors you set for one effect and row text colors are kept.' });
local font_row = listed({ text = 'Font', id = '##main_font', names = fonts.labels,
    help = 'The font for every display and this window. Text sizes stay as they are. Original FFXI and XI View use the game\'s English letters. Reload after changing font files.' });
local size_note = 'Ctrl-click the slider to type a value.';
local function slider(text, id, key, low, high, help, whole, extra)
    local row = listed({ text = text, id = '##main_' .. id, key = key, low = low, high = high, value = { low }, help = help, tip = help .. ' ' .. size_note,
        format = whole and '%.0f' or '%.2f', whole = whole });
    if extra then for name, value in pairs(extra) do row[name] = value; end; end;
    return row;
end;
local text_size = slider('Text size', 'text_size', 'font_size', 8, 48, 'Size of effect names and countdowns.', true);
local scale_row = slider('Size', 'scale', 'scale', 0.5, 2.5, 'The size of every display: text, icons, rows and spacing. 1x, 1.5x and 2x also move displays still where Vantage put them, clear of the game\'s windows. The slider doesn\'t.', false);
local sizes = { { text = '1x', label = '1x##main_size', scale = 1 }, { text = '1.5x', label = '1.5x##main_size', scale = 1.5 },
    { text = '2x', label = '2x##main_size', scale = 2 } };

-- Vantage's lines in the chat log, by the game's own color numbers, under While playing. 10 and 13 end a chat line, so
-- the sliders step past them.
local chat_fold = listed({ text = 'Chat line colors', help = 'The colors of Vantage\'s own lines in the chat log, as the game\'s color numbers. Print a sample line to see them.' });
local chat_rows = {
    slider('Chat bracket color', 'chat_brackets', 'tag_brackets', 1, 255, 'The color number of the brackets around Vantage at the start of its lines.', true),
    slider('Chat name color', 'chat_name', 'tag_word', 1, 255, 'The color number of the word Vantage at the start of its lines.', true),
    slider('Chat message color', 'chat_message', 'replies', 1, 255, 'The color number of what Vantage says.', true),
};
local chat_sample = listed({ text = 'Print a sample line', label = 'Print a sample line##main_chat_sample', help = 'Prints a line in your chat log with these colors. Only you see it.' });

-- How it looks's folds, in the order they draw: a pick, a number or a tick on the shared style.
local function art(text, id, key, choices, help) return listed({ kind = 'pick', text = text, id = '##main_' .. id, key = key, choices = choices, help = help }); end;
local function shared_slider(...) local row = slider(...); row.kind = 'number'; return row; end;
local function shared_tick(text, id, key, help) local row = option(text, id, help); row.kind, row.key = 'tick', key; return row; end;
local art_rows = {
    art('Icons', 'icon_art', 'icon_art', { 'Original FFXI', 'XI View' },
        'Original FFXI and XI View read their installed packs. Your own icon sets, from the icons folder in Vantage\'s settings folder, come after them. It doesn\'t follow the font or gauges, and picking a skin puts the skin\'s icons back. Party list picks its own on its Look tab.'),
    art('Recast icons', 'recast_icon_art', 'recast_icon_art', { 'Original FFXI', 'XI View' },
        'The artwork for recasts that show their spell or ability. Recasts that show the effect they give use Icons, and item pictures come from the client.'),
    art('Gauges', 'gauge_art', 'gauge_art', { 'Original FFXI', 'XI View' },
        'The bar artwork, independent of the font. Applies to Original FFXI timer bars; custom gradients keep their own drawing. Missing XI View artwork falls back to the stock gauges.'),
};
local reload_icons = listed({ text = 'Reload icons', label = 'Reload icons##main_reload_icons', help = require('ui.icon_packs').reload_help });
local open_icons = listed({ text = 'Open icons folder', help = require('ui.icon_packs').open_help });
local window_row = listed({ text = 'Window frame', id = '##main_window_type', key = 'window_type', choices = theme.window_types, names = theme.window_type_labels,
    help = 'The eight window types from the client, for every display and this window. Colors stay as they are.' });
-- Icon size goes up beside Text size while every timer panel is on Icons, and Sizes leaves it out.
local icon_size = shared_slider('Icon size', 'icon_size', 'icon_size', 12, 64, 'The size of timer panel icons, and rows grow to fit them. Party list\'s icons size themselves: beside the game\'s list they fill its rows unless Party list sets a size there, and a panel of its own sets its own.', true);
local size_rows = {
    icon_size,
    shared_slider('Row height', 'bar_height', 'bar_height', 18, 64, 'The least height of each compact bar. Text and icon sizes may need more room.', true),
    shared_slider('Space between rows', 'gap', 'gap', 0, 16, 'Adds space between neighboring effects.', true),
    shared_slider('Heading size', 'title_size', 'title_size', 0, 48, 'Size of the headings above the panels. 0 is the same as Text size.', true, { format = '%.0f', special = 'Same as Text size' }),
};
local box_rows = {
    shared_slider('Opacity', 'opacity', 'opacity', 0.05, 1, 'Panel and bar backgrounds. Text stays readable.', false),
    shared_slider('Corner rounding', 'rounding', 'rounding', 0, 24, 'Zero gives square corners. Original FFXI uses the corners in its client artwork.', true),
    shared_tick('Background', 'background', 'background', 'Draw a backdrop behind timer panels and party buffs in a panel of their own. A panel with its own Box keeps its own choice.'),
    shared_tick('Border', 'border', 'border', 'Draw an outline around each panel. A panel with its own Box keeps its own choice.'),
    shared_tick('No boxes or headings', 'minimal', 'minimal', 'Hides the boxes, headings and empty messages around the timer panels, party buffs in a panel of their own, Party cooldowns, Phantom Roll and Pet. What they show stays.'),
};
local bold_row = option('Bold', 'countdown_bold', 'Thickens only countdown text, on every display but the Party cooldowns list.', 'Bold countdowns');
local shadow_row = option('Shadow', 'countdown_shadow', 'Adds a dark shadow to countdown text, on every display but the Party cooldowns list.', 'Countdown shadow');
local outline_row = listed({ text = 'Outline', id = '##main_countdown_outline', search = 'Countdown outline', choices = shared_look.outlines, names = shared_look.outline_labels,
    help = 'Usual for each display outlines the timer panels and Party list and leaves the rest plain. The Party cooldowns list stays plain either way.' });
local outline_color = listed({ text = 'Outline color', label = 'Outline color##main_countdown_color', search = 'Countdown outline color', value = { 0, 0, 0, 1 },
    help = 'The outline around countdown text, on every display but the Party cooldowns list.' });
local text_shadow = option('Shadow', 'text_shadow', 'Adds a small dark shadow behind names, headings and other text. Countdowns have their own above.', 'Other text shadow');
local text_outline = option('Outline', 'text_outline', 'Outlines names, headings and other text. Countdowns have their own above.', 'Other text outline');
local text_color = listed({ text = 'Outline color', label = 'Outline color##main_text_color', search = 'Other text outline color', value = { 0, 0, 0, 1 },
    help = 'The outline around names, headings and other text.' });
local blink_row = option('Blink before an effect ends, starting at', 'blink', 'Dims and brightens an effect\'s icon starting at the seconds you set before it ends, on the timer panels, Party list, Overhead icons and Pet, countdown shown or not.', 'Blink before an effect ends');
-- The same tick while no display blinks, when no seconds follow it.
local blink_off = { text = 'Blink before an effect ends', label = 'Blink before an effect ends##main_blink', bare = '##main_blink', value = blink_row.value,
    help = blink_row.help, search = blink_row.search };
local blink_seconds = listed({ text = 'Blink seconds left', id = '##main_blink_seconds', value = { 15 },
    help = 'Seconds left when icons begin to blink. Ending-soon colors and countdown styling keep their own settings.' });
local sure_row = option('Color each countdown by how sure Vantage is of its time', 'status_time_color', 'Countdowns take the color of how Vantage knows the time.');
local window_text = slider('Settings text size', 'window_text', 'font_size', 8, 36, 'Size of text in this window.', true);
local colors_row = listed({ text = 'Colors', help = 'The colors of every display. Original FFXI colors tint the client artwork, and white keeps the artwork\'s own colors.' });
local colors_reset = listed({ text = 'Back to the skin\'s colors', label = 'Back to the skin\'s colors##main_colors_reset',
    help = 'Puts the skin\'s colors back. Fonts, layout and filters stay. Undo brings your colors back.' });
-- Where each color shows. The window's own parts take these colors too, so a swatch says where they show in it.
local color_help = {
    background_color = 'Behind the panels and boxes, as Opacity sets, and behind this window.',
    text_color = 'Text on every display, and in this window.',
    title_color = 'The headings over the panels and boxes, and headings and ticks in this window.',
    border_color = 'The outline around the panels and boxes, and around this window\'s lists and boxes.',
    track_color = 'The empty part of a timer bar, and this window\'s buttons and title bar.',
    buff_color = 'Buff bars on the timer panels.',
    debuff_color = 'Debuff bars on the timer panels.',
    estimate_color = 'Bars on the timer panels whose time is an estimate, and this window\'s pressed buttons.',
    warning_color = 'Timers about to end, alert notices, and lines in this window that need a hand.',
    label_color = 'Effect names on the displays.',
    value_color = 'Countdowns on the displays.',
    detail_color = 'The other parts of a row, like who cast it.',
    accent_color = 'The outlines and resize marks while you arrange the displays, and the lines a display snaps to.',
};
-- Lit icons: their color and glow on every display that lights them, Mixed while they differ.
local lit_color = listed({ text = 'Lit icons', label = 'Lit icons##main_lit_color', value = { 0, 0, 0, 1 }, search = 'Lit icon color',
    help = 'The color an icon lights up in when you can take it off, on every display that lights icons. Each display\'s Look tab has its own too.' });
local lit_glow = option('Glow around them', 'lit_glow', 'A glow behind each lit icon, on every display that lights icons.', 'Glow around lit icons');
local color_rows = {};
for _, field in ipairs(theme.fields) do
    if not field.no_control then
        color_rows[#color_rows + 1] = listed({ text = field[2], label = field[2] .. '##main_color', key = field[1], value = { 0, 0, 0, 1 }, help = color_help[field[1]] });
    end;
end;

-- Moving.
local unlock_all = listed({ text = 'Unlock all', label = 'Unlock all##main', help = 'Applies to every display. Each display also has its own lock. Unlock displays to move and resize them, then lock them again.' });
local lock_all = listed({ text = 'Lock all', label = 'Lock all##main', help = 'Applies to every display. Each display also has its own lock.' });
local edit_mode_row = listed({ text = 'Arrange on screen', label = 'Arrange on screen##main',
    help = 'Outlines every display to pick and move, locked or not: hold Shift and drag, or use the arrow keys, 10 pixels with Shift. Esc or Done ends it, and everything stays put.' });
local show_samples = listed({ text = 'Show samples', label = 'Show samples##main', help = 'Sample effects on every display that is on, to arrange it with nothing happening. It turns nothing on.' });
local end_samples = listed({ text = 'End samples', label = 'End samples##main', help = 'Returns every display to live information without hiding it.' });
local peek_row = option('Hold Shift to see through this window', 'peek', 'Hides this window while Shift is held, to place displays under it. Shift and drag its title bar to move it, or an edge to resize it. Not while typing.');
-- Snap while moving, the same tick as the one in Arrange on screen's bar, where the rest of snapping is.
local grid_row = option('Snap while moving', 'grid_mode', 'A display you move or resize lines up with the grid, the screen\'s edges and the other displays. Arrange on screen\'s bar picks which ones snap and to what.');
-- Headings and folds the search finds as well as their rows.
listed({ text = 'What to show', help = 'Tick what you want. Edit changes how it looks and works.' });
listed({ text = 'How it looks', help = 'Skin, font and text effects reach every display and this window.' });
-- How it looks keeps the rest in small folds.
local artwork_fold = listed({ text = 'Artwork', help = 'The icon and gauge artwork, and the window frame.' });
local sizes_fold = listed({ text = 'Sizes', help = 'Icon size, row height, the space between rows and the heading size.' });
local boxes_fold = listed({ text = 'Boxes', help = 'Opacity, corners, backgrounds and borders.' });
local effects_fold = listed({ text = 'Text effects', help = 'Bold, shadows and outlines on countdowns and other text.' });
listed({ text = 'Moving', help = 'Unlock displays to move and resize them, then lock them again.' });
local window_caption = listed({ text = 'This window', help = 'Its text size, and seeing through it while you place displays under it.' });

-- Each display's lock, with the name the page gives it and its id in ui/elements.lua.
local function each_lock(settings, fn)
    for _, id in ipairs(defaults.panel_order) do fn(settings.panels[id], 'locked', shared_look.names[id], id); end;
    fn(settings.party_ui, 'locked', 'Party list', 'party_ui'); fn(settings.alerts, 'notice_locked', 'Alerts', 'notices');
    fn(settings.party_cooldowns.list, 'locked', 'Party cooldowns list', 'cooldown_list'); fn(settings.ready_pulse, 'locked', 'Ready pulse', 'pulse');
    fn(settings.rolls, 'locked', 'Phantom Roll', 'rolls'); fn(settings.pet, 'locked', 'Pet', 'pet');
end;

-- What the settings say in words: made again when they change. The header's Undo can swap the settings mid-draw, so the
-- table counts too. Without a revision to go by, each draw works them out. A drag changes the settings every frame, so
-- while the mouse is held they wait for it to come up.
local said = { owner = nil, revision = nil };

-- Whether every timer panel that shows is on Icons, which go by Icon size and Space between rows alone.
local function all_icons(settings)
    local any = false;
    for _, id in ipairs(defaults.panel_order) do
        if defaults.panel_enabled(settings, id) then
            if settings.panels[id].mode ~= 'icons' then return false; end;
            any = true;
        end;
    end;
    return any;
end;

-- Only the displays that are on count, each by its own switch, so the line holds from frame to frame. Its second value,
-- whether one is unlocked, makes Unlock all Lock all, and either still sets every display's lock.
local function locks_line(settings)
    local unlocked, total = {}, 0;
    each_lock(settings, function(object, key, name, id)
        if not elements.on(settings, id) then return; end;
        total = total + 1;
        if not object[key] then unlocked[#unlocked + 1] = name; end;
    end);
    if #unlocked > 0 then return 'Unlocked: ' .. table.concat(unlocked, ', ') .. '. Hold Shift and drag one to move it.', true; end;
    return total > 0 and 'Every display is locked.' or nil, false;
end;

function page.any_unlocked(settings)
    local _, unlocked = locks_line(settings);
    return unlocked;
end;

-- The timer panels that are on and set something for themselves, in a line that says so, or nil when none does.
local function own_line(settings, test, one, many)
    local names = {};
    for _, id in ipairs(defaults.panel_order) do
        local p = settings.panels[id];
        if p.enabled and test(p) then names[#names + 1] = defaults.panel_names[id]; end;
    end;
    if #names == 0 then return nil; end;
    if #names == 1 then return names[1] .. ' has' .. one; end;
    return table.concat(names, ', ', 1, #names - 1) .. ' and ' .. names[#names] .. ' have' .. many;
end;

local function refresh(imgui, settings, callbacks)
    local revision = callbacks.settings_revision and callbacks.settings_revision();
    if said.owner == settings and revision ~= nil and (said.revision == revision or imgui.IsMouseDown(ImGuiMouseButton_Left or 0)) then return; end;
    said.owner, said.revision = settings, revision;
    local sampled = defaults.samples_on_displays(settings);
    said.samples = #sampled == 1 and 'Samples show on ' .. sampled[1] .. '.' or #sampled > 1 and 'Samples show on ' .. #sampled .. ' displays.' or nil;
    said.no_pulse_row, said.all_icons = defaults.pulse_has_no_row(settings), all_icons(settings);
    said.no_cooldowns = settings.party_cooldowns.enabled and not cooldowns.shown(settings);
    said.own_boxes = own_line(settings, function(p) return p.box ~= 'shared'; end, ' a box of its own, so Background and Border don\'t change it.',
        ' boxes of their own, so Background and Border don\'t change them.');
    said.own_colors = own_line(settings, function(p) return next(p.colors) ~= nil; end, ' colors of its own, so these don\'t change it. Its Look tab can put them back.',
        ' colors of their own, so these don\'t change them. Their Look tabs can put them back.');
    said.skin_changed = theme.current(settings) == 'Custom';
    said.locks, said.unlocked = locks_line(settings);
    local used = starters.matching(settings);
    local labels = said.starters or {};
    for _, entry in ipairs(starters.list) do labels[entry.id] = entry.name .. (entry.id == used and ' (in use)' or ''); end;
    said.starters = labels;
end;

local function mark(c, label, help)
    if c.search[1] ~= '' then c.mark(label, help); end;
end;

local shaded, caption = frame.shaded, frame.caption;

-- A group's caption, in the headings' color.
local function group_caption(imgui, c, row)
    local color = c.look and c.look.headings;
    if color then imgui.PushStyleColor(ImGuiCol_Text, color); end;
    imgui.TextUnformatted(row.text);
    if color then imgui.PopStyleColor(); end;
    if row.help then mark(c, row.text, row.help); c.tip(row.help); end;
end;

-- A tick. Its row keeps the value box. A label too long for the page wraps beside its box.
local function tick(imgui, c, row, on)
    local value = row.value;
    value[1] = on == true;
    local clicked;
    if imgui.CalcTextSize(row.text) + imgui.GetFrameHeight() + 10 > imgui.GetContentRegionAvail() then
        clicked = controls.checkbox(imgui, c.look, row.bare, value);
        imgui.SameLine();
        imgui.TextWrapped(row.text);
    else
        clicked = controls.checkbox(imgui, c.look, row.label, value);
    end;
    mark(c, row.search or row.text, row.help);
    c.tip(row.help);
    return clicked;
end;

-- A tick that stands for several values that differ: drawn partly ticked, as nothing is one way or the other yet. The
-- square's corners are filled in for each tick, so a frame makes no table.
local partly_from, partly_to = { 0, 0 }, { 0, 0 };
local function partly(imgui, c)
    if not imgui.GetItemRectMin then return; end;
    local x, y = imgui.GetItemRectMin();
    local size = imgui.GetFrameHeight();
    local inset = math.floor(size / 4);
    local ink = c.look and c.look.text or { 1, 1, 1, 1 };
    partly_from[1], partly_from[2], partly_to[1], partly_to[2] = x + inset, y + inset, x + size - inset, y + size - inset;
    imgui.GetWindowDrawList():AddRectFilled(partly_from, partly_to, theme.u32(ink), 0);
end;

-- A button with no room left on its line starts the next one, and a caption wider than the page wraps.
local function button(imgui, c, row)
    local size = imgui.CalcTextSize(row.caption) + 20;
    if size > imgui.GetContentRegionAvail() and imgui.GetCursorPosX() > imgui.GetFontSize() then imgui.NewLine(); end;
    local available = imgui.GetContentRegionAvail();
    local label = row.shown;
    if size > available then
        label = table.concat(require('ui.text_wrap').lines(row.caption, math.max(1, available - 20), imgui.CalcTextSize), '\n') .. '###' .. row.label;
    end;
    local clicked = imgui.Button(label);
    mark(c, row.search or row.text, row.help);
    c.tip(row.help);
    return clicked;
end;

-- The same with a folder drawn before its caption (ui/controls.lua). Its caption is short enough never to wrap.
local function folder_button(imgui, c, row, id)
    if controls.folder_width(imgui, row.text) > imgui.GetContentRegionAvail() and imgui.GetCursorPosX() > imgui.GetFontSize() then imgui.NewLine(); end;
    local clicked = controls.folder_button(imgui, c.look, row.text, id);
    mark(c, row.text, row.help);
    c.tip(row.help);
    return clicked;
end;

-- The row's Edit at the right of the page. left and width are where the row began and how wide the page is.
local function edit_button(imgui, c, row, left, width)
    local size = imgui.CalcTextSize('Edit') + 24;
    local gap = left + width - size - imgui.GetItemRectMax();
    if gap >= 8 then imgui.SameLine(0, gap); end;
    local clicked = imgui.Button(row.edit);
    mark(c, row.edit_search, row.edit_help);
    c.tip(row.edit_help);
    if clicked then c.open_page(row.page, row.panel, row.place); end;
end;

-- A line that needs a hand, with its one fix at the right when it fits. Returns whether the fix was clicked.
local function attention(imgui, c, text, row)
    local x, available = imgui.GetCursorPosX(), imgui.GetContentRegionAvail();
    local size = imgui.CalcTextSize(row.text) + 24;
    local fits = imgui.CalcTextSize(text) + size + 16 <= available;
    local color = c.look and c.look.problem_messages;
    if color then imgui.PushStyleColor(ImGuiCol_Text, color); end;
    if fits then
        if imgui.AlignTextToFramePadding then imgui.AlignTextToFramePadding(); end;
        imgui.TextUnformatted(text);
    else imgui.TextWrapped(text); end;
    if color then imgui.PopStyleColor(); end;
    if fits then imgui.SameLine(x + available - size); end;
    return button(imgui, c, row);
end;

-- A list, its label on the left of the row. Returns the value picked this frame, if any.
local function pick(imgui, c, row, shown, current, choices, names)
    controls.label(imgui, row.text);
    c.tip(row.help);
    imgui.SetNextItemWidth(-1);
    skin.prepare_menu(imgui, c.look);
    local chosen;
    if imgui.BeginCombo(row.id, shown) then
        skin.menu(imgui, c.look, 'popup');
        for index, value in ipairs(choices or row.choices) do
            local name = names or row.names;
            local text = name and name[value] or tostring(value);
            -- ImGui shows a label up to its first ## and starts its ID again at ###. A font file or an icon folder can
            -- have a # in its name, so a # gets a space after it where it would join another, and the ID is the place.
            local label = text:find('#', 1, true) and text:gsub('#(#)', '# %1'):gsub('#(#)', '# %1'):gsub('#$', '# ') .. '###' .. index
                or text .. '##' .. tostring(value);
            if imgui.Selectable(label, current == value) then chosen = value; end;
        end;
        imgui.EndCombo();
    end;
    mark(c, row.search or row.text, row.help);
    c.tip(row.help);
    return chosen;
end;

-- A slider, its label on the left of the row. Returns the number it moved to this frame, if any.
local function number(imgui, c, row, current)
    controls.label(imgui, row.text);
    c.tip(row.tip);
    local value = row.value;
    value[1] = tonumber(current) or row.low;
    imgui.SetNextItemWidth(-1);
    local moved = imgui.SliderFloat(row.id, value, row.low, row.high, row.special and value[1] == 0 and row.special or row.format);
    mark(c, row.search or row.text, row.help);
    c.tip(row.tip);
    if not moved then return nil; end;
    local chosen = tonumber(value[1]);
    if not chosen or chosen ~= chosen or math.abs(chosen) == math.huge then return nil; end;
    chosen = math.max(row.low, math.min(row.high, chosen));
    return row.whole and math.floor(chosen + 0.5) or chosen;
end;

local color_flags;
-- A color swatch. Returns a copy of the color picked this frame, if any.
local function swatch(imgui, c, row, source)
    color_flags = color_flags or bit.bor(ImGuiColorEditFlags_NoInputs or 0, ImGuiColorEditFlags_AlphaBar or 0);
    local value = row.value;
    for index = 1, 4 do value[index] = source[index]; end;
    local moved = imgui.ColorEdit4(row.label, value, color_flags);
    mark(c, row.search or row.text, row.help);
    c.tip(row.help);
    if moved then return { value[1], value[2], value[3], value[4] }; end;
end;

local function edit(c, label, fn) c.changed(fn, true, label); end;

-- What to show.

-- What the recast ticks say, in the layout in use. The combined panel's own switch is read only in that layout.
local function recast_on(settings, kind)
    if settings.recast_display == 'combined' then
        local panel = settings.panels.recasts;
        return settings.enabled and panel.enabled and panel.recast_categories[kind.key] == true;
    end;
    return settings.enabled and settings.panels[kind.panel].enabled;
end;

local function recast_write(settings, kind, on)
    if settings.recast_display == 'combined' then
        local panel = settings.panels.recasts;
        -- The other kinds stay as they are, so ticking one on a panel that was off doesn't bring the others with it.
        -- While the timer panels are paused they keep what they had, as separate panels do.
        local shown = {};
        for _, other in ipairs(recast_kinds) do shown[other.key] = panel.enabled and panel.recast_categories[other.key] == true; end;
        shown[kind.key] = on;
        local any = false;
        for key, value in pairs(shown) do panel.recast_categories[key] = value; any = any or value; end;
        panel.enabled = any;
        if not any then panel.preview = false; end;
    else
        settings.panels[kind.panel].enabled = on;
        if not on then settings.panels[kind.panel].preview = false; end;
    end;
    if on then settings.enabled = true; end;
end;

local function display_row(imgui, settings, c, row)
    local left, width = imgui.GetCursorScreenPos(), imgui.GetContentRegionAvail();
    if tick(imgui, c, row, row.get(settings)) then
        local on = row.value[1];
        edit(c, row.text, function() row.set(settings, on); end);
    end;
    edit_button(imgui, c, row, left, width);
end;

-- A caption with a tick for each place on its line, each going under the one before when the line is full, and the
-- row's Edit at the right.
local function places_rows(imgui, settings, c, row)
    local left, width = imgui.GetCursorScreenPos(), imgui.GetContentRegionAvail();
    caption(imgui, row.text);
    mark(c, row.text, row.help);
    c.tip(row.help);
    for _, place_row in ipairs(row.places) do
        if left + width - imgui.GetItemRectMax() - 8 >= imgui.CalcTextSize(place_row.text) + imgui.GetFrameHeight() + 16 then imgui.SameLine(); end;
        if tick(imgui, c, place_row, place_row.read(settings)) then
            local on = place_row.value[1];
            edit(c, place_row.search, function() place_row.write(settings, on); end);
        end;
    end;
    edit_button(imgui, c, row, left, width);
end;

-- A tick that reads and writes through its row.
local function tick_row(imgui, settings, c, row)
    if tick(imgui, c, row, row.read(settings)) then
        local on = row.value[1];
        edit(c, row.text, function() row.write(settings, on); end);
    end;
end;

local function recast_rows(imgui, settings, c)
    local left, width = imgui.GetCursorScreenPos(), imgui.GetContentRegionAvail();
    caption(imgui, recast_row.text);
    mark(c, recast_row.text, recast_row.help);
    c.tip(recast_row.help);
    -- Each kind goes under the one before when the line is full, as places_rows does.
    for _, kind in ipairs(recast_kinds) do
        if left + width - imgui.GetItemRectMax() - 8 >= imgui.CalcTextSize(kind.text) + imgui.GetFrameHeight() + 16 then imgui.SameLine(); end;
        if tick(imgui, c, kind, recast_on(settings, kind)) then
            local on = kind.value[1];
            edit(c, kind.search, function() recast_write(settings, kind, on); end);
        end;
    end;
    local size = imgui.CalcTextSize('Edit') + 24;
    local gap = left + width - size - imgui.GetItemRectMax();
    if gap >= 8 then imgui.SameLine(0, gap); end;
    local clicked = imgui.Button(recast_row.edit);
    mark(c, recast_row.edit_search, recast_row.edit_help);
    c.tip(recast_row.edit_help);
    if clicked then c.open_page('Display', 'recasts'); end;
end;

local function alerts_rows(imgui, settings, c)
    local left, width = imgui.GetCursorScreenPos(), imgui.GetContentRegionAvail();
    local alerts = settings.alerts;
    if tick(imgui, c, alerts_row, alerts.enabled) then
        local on = alerts_row.value[1];
        edit(c, 'Alerts', function() alerts.enabled = on; end);
    end;
    if alerts.muted then
        imgui.SameLine();
        imgui.TextUnformatted('Muted');
        imgui.SameLine();
        if button(imgui, c, unmute) then edit(c, 'Unmute alerts', function() alerts.muted = false; end); end;
    end;
    edit_button(imgui, c, alerts_row, left, width);
end;

local function starter_rows(imgui, settings, view, c)
    local job = view and view.context and view.context.job;
    if job and job ~= starter_job then starter_job, starter_pick = job, nil; end;
    local chosen = starter_pick or starters.for_job(starter_job);
    local entry = starters.by_id[chosen];
    controls.label(imgui, starter_row.text);
    c.tip(starter_row.help);
    local reserve = imgui.CalcTextSize('Apply') + 28;
    local beside = imgui.GetContentRegionAvail() - reserve - 8 >= imgui.CalcTextSize('Crowd control (in use)') + imgui.GetFrameHeight() + 16;
    imgui.SetNextItemWidth(beside and -(reserve + 8) or -1);
    skin.prepare_menu(imgui, c.look);
    if imgui.BeginCombo(starter_row.id, said.starters[chosen]) then
        skin.menu(imgui, c.look, 'popup');
        for _, value in ipairs(starters.ids) do
            if imgui.Selectable(said.starters[value] .. '##' .. value, chosen == value) then starter_pick = value; end;
            c.tip(starters.by_id[value].about);
        end;
        imgui.EndCombo();
    end;
    mark(c, starter_row.text, starter_row.help);
    c.tip(entry.about);
    if beside then imgui.SameLine(); end;
    if button(imgui, c, starter_apply) and c.profile.apply_starter(entry) then
        starter_note, starter_note_at = 'Its displays show samples until you press End samples, at the top of this page.', steady();
    end;
    if starter_note then
        if steady() - starter_note_at < 8 then shaded(imgui, c, starter_note, 'done_messages'); else starter_note = nil; end;
    end;
end;

-- A group: a little room over its caption when another group is above it, the caption, then its rows.
local function group_rows(imgui, settings, c, entry, below)
    if below then imgui.Spacing(); end;
    group_caption(imgui, c, entry.caption);
    for _, row in ipairs(entry.rows) do
        if row == recast_row then recast_rows(imgui, settings, c);
        elseif row == alerts_row then alerts_rows(imgui, settings, c);
        elseif row.places then places_rows(imgui, settings, c, row);
        elseif row.read then tick_row(imgui, settings, c, row);
        else display_row(imgui, settings, c, row); end;
    end;
end;

-- A pick over displays that differ asks first and names the ones it changes; a pick over one shared value just writes.
-- id names the confirm_line that asks: Blink's is under While playing, the rest under Text effects.
local function write_shared(c, mixed, label, what, changing, fn, id)
    if not mixed then return edit(c, label, fn); end;
    c.ask(id or 'main_shared', 'This changes ' .. what .. ' on: ' .. changing .. '.', function() edit(c, label, fn); end);
end;

local function blink_rows(imgui, settings, c)
    local left, width = imgui.GetCursorScreenPos(), imgui.GetContentRegionAvail();
    local blink = shared_look.blink(settings);
    local seconds = shared_look.blink_seconds(settings);
    if tick(imgui, c, blink == false and blink_off or blink_row, blink) then
        local on = blink_row.value[1];
        write_shared(c, blink == nil, 'Blink before an effect ends', 'blinking', shared_look.changes_blink(settings, on),
            function() shared_look.set_blink(settings, on); end, 'main_blink');
    elseif blink == nil then partly(imgui, c); end;
    if blink == false then return; end;
    -- The slider goes under the tick when the line has no room for it.
    local wide = imgui.CalcTextSize('300 seconds left') + 24;
    if left + width - imgui.GetItemRectMax() - 8 >= wide then imgui.SameLine(); end;
    local value = blink_seconds.value;
    value[1] = seconds or shared_look.first_blink_seconds(settings);
    imgui.SetNextItemWidth(wide);
    local moved = imgui.SliderFloat(blink_seconds.id, value, 1, 300, seconds and '%.0f seconds left' or 'Mixed');
    mark(c, blink_seconds.text, blink_seconds.help);
    c.tip(blink_seconds.help);
    local typed = moved and (tonumber(value[1]) or 15);
    -- A typed nan is no number of seconds. Saved, it would stop every save after it.
    if typed and typed == typed then
        local chosen = math.floor(math.max(1, math.min(300, typed)) + 0.5);
        if seconds == nil then
            write_shared(c, true, 'Blink seconds left', 'when blinking starts', shared_look.changes_blink_seconds(settings, chosen),
                function() shared_look.set_blink_seconds(settings, chosen); end, 'main_blink');
        else
            c.changed(function() shared_look.set_blink_seconds(settings, chosen); end, false, 'Blink seconds left');
        end;
    end;
end;

local function style_tick(imgui, settings, c, row, key)
    local style = settings.style;
    if tick(imgui, c, row, style[key]) then
        local on = row.value[1];
        edit(c, row.search or row.text, function() style[key] = on; end);
    end;
end;

-- Two columns while each holds the Recasts row, the widest one, with its Edit.
-- Short ticks share a line when the window has the room for them all: two, or as many as count says.
local function beside(imgui, labels, count)
    count = count or 2;
    if imgui.CalcTextSize(labels) + count * (imgui.GetFrameHeight() + 20) <= imgui.GetContentRegionAvail() then imgui.SameLine(); end;
end;

local function two_columns(imgui)
    local recasts = imgui.CalcTextSize('Recasts Spells Abilities Items Edit') + 3 * imgui.GetFrameHeight() + 64;
    return imgui.GetContentRegionAvail() >= 2 * recasts and imgui.BeginTable('##main_show', 2, ImGuiTableFlags_SizingStretchSame or 0);
end;

local function what_to_show(imgui, settings, view, c)
    c.heading('What to show', 'Tick what you want. Edit changes how it looks and works.', true);
    mark(c, 'What to show', 'Tick what you want. Edit changes how it looks and works.');
    if c.profile then starter_rows(imgui, settings, view, c); end;
    -- In two columns On you sits beside Target and enemies, with Alerts under that, and Party takes the whole width
    -- under both, so each of its rows has its places on one line.
    if two_columns(imgui) then
        imgui.TableNextColumn();
        group_rows(imgui, settings, c, groups[1], false);
        imgui.TableNextColumn();
        group_rows(imgui, settings, c, groups[2], false);
        group_rows(imgui, settings, c, groups[4], true);
        imgui.EndTable();
        group_rows(imgui, settings, c, groups[3], true);
    else
        for index, entry in ipairs(groups) do group_rows(imgui, settings, c, entry, index > 1); end;
    end;
    imgui.Spacing();
    group_caption(imgui, c, playing_row);
    local visibility = settings.visibility;
    local game = visibility.hide_events;
    local mixed = visibility.hide_map ~= game or visibility.hide_ui ~= game;
    if tick(imgui, c, hide_game_row, game and not mixed) then
        local on = hide_game_row.value[1];
        edit(c, 'Hide Vantage with the game', function() for _, key in ipairs(hide_keys) do visibility[key] = on; end; end);
    elseif mixed then partly(imgui, c); end;
    if tick(imgui, c, hide_typing_row, visibility.hide_typing) then
        local on = hide_typing_row.value[1];
        edit(c, hide_typing_row.text, function() visibility.hide_typing = on; end);
    end;
    beside(imgui, typing_and_hover);
    if tick(imgui, c, hover_row, settings.style.hover) then
        local on = hover_row.value[1];
        edit(c, hover_row.text, function() settings.style.hover = on; end);
    end;
    if tick(imgui, c, follow_row, settings.tracking.follow_subtarget) then
        local on = follow_row.value[1];
        edit(c, follow_row.text, function() settings.tracking.follow_subtarget = on; end);
    end;
    blink_rows(imgui, settings, c);
    c.confirm_line('main_blink');
    style_tick(imgui, settings, c, sure_row, 'status_time_color');
    if tick(imgui, c, replace_row, settings.replace_game_buffs) then
        local on = replace_row.value[1];
        edit(c, replace_row.text, function() settings.replace_game_buffs = on; end);
    end;
    beside(imgui, both_replace);
    if tick(imgui, c, pet_bar_row, settings.replace_game_pet_bar) then
        local on = pet_bar_row.value[1];
        edit(c, pet_bar_row.text, function() settings.replace_game_pet_bar = on; end);
    end;
    -- Ticked but not in effect: a line says why, from the settings first, then from the game client.
    if settings.replace_game_buffs then
        local asked, why = defaults.game_buffs_replaced(settings);
        if asked then why = game_buffs.problem(); end;
        if why then shaded(imgui, c, why, 'problem_messages'); end;
    end;
    if settings.replace_game_pet_bar then
        local asked, why = defaults.game_pet_bar_replaced(settings);
        if asked then why = require('core.game_pet_bar').problem(); end;
        if why then shaded(imgui, c, why, 'problem_messages'); end;
    end;
    if c.section(chat_fold.text, chat_fold.help) then
        local colors = settings.chat_colors;
        for _, row in ipairs(chat_rows) do
            local current = colors[row.key];
            local chosen = number(imgui, c, row, current);
            if chosen == 10 or chosen == 13 then chosen = chosen + ((tonumber(current) or 0) < chosen and 1 or -1); end;
            if chosen and chosen ~= current then c.changed(function() colors[row.key] = chosen; end, false, row.text); end;
        end;
        if button(imgui, c, chat_sample) then c.call('chat_sample'); end;
    end;
end;

-- How it looks.

local function pick_skin(settings, c, value)
    local function options() return { matching = true, window_type = settings.style.window_type }; end;
    local function apply()
        edit(c, 'Skin: ' .. (skin_labels[value] or value), function() appearance.apply(settings, value, options()); end);
    end;
    local result = copy(settings);
    appearance.apply(result, value, options());
    c.confirm_look('main_skin', apply, result, skin_labels[value] or value);
end;

-- The buttons set the size and move the displays still where Vantage put them, so nothing lands on the game's windows.
local function pick_size(imgui, settings, c, size)
    if c.cancel_party_gestures then c.cancel_party_gestures(); end;
    local screen = imgui.GetIO().DisplaySize;
    local chat = c.chat_area and c.chat_area() or nil;
    edit(c, 'Size ' .. size.text, function()
        local old = copy(settings);
        settings.style.scale = size.scale;
        require('ui.setup_defaults').respace(old, settings, { width = screen.x, height = screen.y, chat = chat });
    end);
    if c.note then c.note('Size ' .. size.text .. '. Undo puts it back.'); end;
end;

local function size_rows_draw(imgui, settings, c)
    local style = settings.style;
    controls.label(imgui, scale_row.text);
    c.tip(scale_row.tip);
    for _, size in ipairs(sizes) do
        local current = style.scale == size.scale;
        if current and c.look then imgui.PushStyleColor(ImGuiCol_Button, c.look.buttons_pressed); end;
        local clicked = imgui.Button(size.label);
        if current and c.look then imgui.PopStyleColor(); end;
        c.tip(scale_row.help);
        imgui.SameLine();
        if clicked and not current then pick_size(imgui, settings, c, size); end;
    end;
    local value = scale_row.value;
    value[1] = tonumber(style.scale) or 1;
    imgui.SetNextItemWidth(-1);
    local moved = imgui.SliderFloat(scale_row.id, value, scale_row.low, scale_row.high, scale_row.format);
    mark(c, scale_row.text, scale_row.help);
    c.tip(scale_row.tip);
    local chosen = moved and tonumber(value[1]);
    if chosen and chosen == chosen and math.abs(chosen) ~= math.huge then
        chosen = math.max(scale_row.low, math.min(scale_row.high, chosen));
        c.changed(function() style.scale = chosen; end, false, 'Size');
    end;
end;

local function countdown_rows(imgui, settings, c)
    local bold, shadow = shared_look.bold(settings), shared_look.shadow(settings);
    caption(imgui, 'Countdowns');
    imgui.SameLine();
    if tick(imgui, c, bold_row, bold) then
        local on = bold_row.value[1];
        write_shared(c, bold == nil, 'Bold countdowns', 'bold countdowns', shared_look.changes_bold(settings, on),
            function() shared_look.set_bold(settings, on); end);
    elseif bold == nil then partly(imgui, c); end;
    imgui.SameLine();
    if tick(imgui, c, shadow_row, shadow) then
        local on = shadow_row.value[1];
        write_shared(c, shadow == nil, 'Countdown shadow', 'countdown shadows', shared_look.changes_shadow(settings, on),
            function() shared_look.set_shadow(settings, on); end);
    elseif shadow == nil then partly(imgui, c); end;
    local outline = shared_look.outline(settings);
    local chosen = pick(imgui, c, outline_row, shared_look.outline_labels[outline], outline);
    if chosen and chosen ~= outline then
        write_shared(c, outline == 'mixed', 'Countdown outline: ' .. shared_look.outline_labels[chosen], 'countdown outlines',
            shared_look.changes_outline(settings, chosen), function() shared_look.set_outline(settings, chosen); end);
    end;
    if outline == 'none' then return; end;
    local color = shared_look.outline_color(settings);
    local picked = swatch(imgui, c, outline_color, color or shared_look.first_outline_color(settings));
    if color == nil then
        imgui.SameLine();
        imgui.TextUnformatted('Mixed');
    end;
    if picked then
        if color == nil then
            write_shared(c, true, 'Countdown outline color', 'countdown outline colors', shared_look.changes_outline_color(settings, picked),
                function() shared_look.set_outline_color(settings, picked); end);
        else
            c.changed(function() shared_look.set_outline_color(settings, picked); end, false, 'Countdown outline color');
        end;
    end;
end;

-- A working bitmap font has its shadow in its letters, so Other text's Shadow has nothing to add.
function page.baked_shadow(style) return fonts.is_bitmap(style.font) and not fonts.failed(style.font); end;

local function artwork(imgui, settings, c)
    local style = settings.style;
    for _, row in ipairs(art_rows) do
        if row.key == 'icon_art' then
            -- Your own sets are listed after the built-in choices, and one that isn't there says so.
            local list, names = icons.choices(style.icon_art);
            local chosen = pick(imgui, c, row, names[style.icon_art] or tostring(style.icon_art), style.icon_art, list, names);
            if chosen then edit(c, row.text, function() style.icon_art = chosen; end); end;
            local icon_reason = icons.reason(style.icon_art);
            if icon_reason then shaded(imgui, c, icon_reason); end;
            local folder_warning = icons.folder_warning();
            if folder_warning then shaded(imgui, c, folder_warning, 'problem_messages'); end;
            if button(imgui, c, reload_icons) and c.note then c.note(icons.reload_sets()); end;
            imgui.SameLine();
            if folder_button(imgui, c, open_icons, 'Open icons folder##main_open_icons') and c.note then c.note(icons.open_folder()); end;
        elseif row.key ~= 'gauge_art' or skin.active(style) then
            local chosen = pick(imgui, c, row, tostring(style[row.key]), style[row.key]);
            if chosen then edit(c, row.text, function() style[row.key] = chosen; end); end;
        end;
    end;
    if skin.active(style) then
        local chosen = pick(imgui, c, window_row, theme.window_type_labels[style.window_type] or tostring(style.window_type), style.window_type);
        if chosen then edit(c, 'Window frame', function() style.window_type = chosen; end); end;
        local why = skin.reason(style.window_type, style.gauge_art);
        if why then shaded(imgui, c, 'Some Original FFXI artwork is unavailable: ' .. why .. ' Regular drawing is being used for the missing pieces.'); end;
        local gauge_why = skin.gauge_reason(style);
        if gauge_why then shaded(imgui, c, gauge_why); end;
    end;
end;

-- A slider on the shared style, or a tick on it.
local function style_row(imgui, settings, c, row)
    local style = settings.style;
    if row.kind == 'tick' then return style_tick(imgui, settings, c, row, row.key); end;
    local chosen = number(imgui, c, row, style[row.key]);
    if chosen then c.changed(function() style[row.key] = chosen; end, false, row.text); end;
end;

local function size_fold(imgui, settings, c)
    for _, row in ipairs(size_rows) do
        if row ~= icon_size or not said.all_icons then style_row(imgui, settings, c, row); end;
    end;
    if said.all_icons then shaded(imgui, c, 'Your timer panels are all on Icons, so of these only Space between rows changes them.'); end;
end;

local function box_fold(imgui, settings, c)
    for _, row in ipairs(box_rows) do
        -- No boxes or headings draws neither of these two.
        if row.kind ~= 'tick' or not settings.style.minimal or row.key == 'minimal' then style_row(imgui, settings, c, row); end;
    end;
    if said.own_boxes then shaded(imgui, c, said.own_boxes); end;
    if settings.party_ui.enabled then shaded(imgui, c, 'Opacity and corner rounding don\'t change Party list. It has its own opacity, on its Look tab.'); end;
end;

local function text_effects(imgui, settings, c)
    local style = settings.style;
    countdown_rows(imgui, settings, c);
    caption(imgui, 'Other text');
    imgui.SameLine();
    if not page.baked_shadow(style) then
        style_tick(imgui, settings, c, text_shadow, 'text_shadow');
        imgui.SameLine();
    end;
    style_tick(imgui, settings, c, text_outline, 'text_outline');
    if style.text_outline then
        local picked = swatch(imgui, c, text_color, style.outline_color);
        if picked then c.changed(function() style.outline_color = picked; end, false, 'Other text outline color'); end;
    end;
    c.confirm_line('main_shared');
end;

local function colors(imgui, settings, c)
    local style = settings.style;
    for _, row in ipairs(color_rows) do
        local picked = swatch(imgui, c, row, style[row.key]);
        if picked then c.changed(function() style[row.key] = picked; end, false, row.text .. ' color'); end;
        if row.key == 'value_color' and style.status_time_color then
            shaded(imgui, c, 'While Color each countdown by how sure Vantage is of its time is on, timer panels don\'t use this.');
        end;
    end;
    local light, first = shared_look.light(settings, 'dispel_color');
    local picked = swatch(imgui, c, lit_color, light or first);
    if picked then c.changed(function() shared_look.set_light(settings, 'dispel_color', picked); end, false, 'Lit icons color'); end;
    imgui.SameLine();
    local glow = shared_look.light(settings, 'dispel_glow');
    if tick(imgui, c, lit_glow, glow == true) then
        local on = lit_glow.value[1];
        edit(c, 'Glow around lit icons', function() shared_look.set_light(settings, 'dispel_glow', on); end);
    elseif glow == nil then partly(imgui, c); end;
    if said.own_colors then shaded(imgui, c, said.own_colors); end;
    if button(imgui, c, colors_reset) then
        edit(c, 'Back to the skin\'s colors', function() theme.apply(settings, style.theme); end);
    end;
end;

local function how_it_looks(imgui, settings, c)
    local style = settings.style;
    c.heading('How it looks', nil, true);
    mark(c, 'How it looks', 'Skin, font and text effects reach every display and this window.');
    local current = appearance.candidate(settings);
    local chosen = pick(imgui, c, skin_row, (skin_labels[current] or current) .. (said.skin_changed and ' (changed)' or ''), current);
    if chosen then pick_skin(settings, c, chosen); end;
    c.confirm_line('main_skin');
    chosen = pick(imgui, c, font_row, fonts.labels[style.font] or style.font, style.font, fonts.names());
    if chosen then edit(c, 'Font', function() style.font = chosen; end); end;
    if fonts.failed(style.font) then shaded(imgui, c, fonts.reason(style.font) or 'That font is unavailable.');
    elseif fonts.window_failed(style.font) then shaded(imgui, c, 'This window can\'t use this font, so it uses its plain font.'); end;
    chosen = number(imgui, c, text_size, style.font_size);
    if chosen then c.changed(function() style.font_size = chosen; end, false, text_size.text); end;
    -- Timer panels all on Icons go by Icon size, so it is here rather than under Sizes.
    if said.all_icons then style_row(imgui, settings, c, icon_size); end;
    size_rows_draw(imgui, settings, c);
    if c.section(artwork_fold.text, artwork_fold.help) then artwork(imgui, settings, c); end;
    if c.section(sizes_fold.text, sizes_fold.help) then size_fold(imgui, settings, c); end;
    if c.section(boxes_fold.text, boxes_fold.help) then box_fold(imgui, settings, c); end;
    if c.section(effects_fold.text, effects_fold.help) then text_effects(imgui, settings, c); end;
    if c.section(colors_row.text, colors_row.help) then colors(imgui, settings, c); end;
end;

-- Moving.

local function moving(imgui, settings, callbacks, c)
    c.heading('Moving', nil, true);
    mark(c, 'Moving', 'Unlock displays to move and resize them, then lock them again.');
    if said.locks then imgui.TextWrapped(said.locks); end;
    local locking = said.unlocked;
    local lock_row = locking and lock_all or unlock_all;
    if button(imgui, c, lock_row) then
        edit(c, lock_row.text, function() each_lock(settings, function(object, key) object[key] = locking; end); end);
    end;
    imgui.SameLine();
    if button(imgui, c, edit_mode_row) and callbacks.edit_mode then callbacks.edit_mode(not require('ui.edit_mode').active()); end;
    -- While samples show, End samples is at the top of the page.
    if not said.samples then
        imgui.SameLine();
        if button(imgui, c, show_samples) then
            local shown = false;
            edit(c, 'Show samples', function() shown = defaults.samples_on(settings); end);
            if not shown and c.note then c.note(defaults.no_samples); end;
        end;
    end;
    if tick(imgui, c, grid_row, settings.edit_mode.grid_mode) then
        local on = grid_row.value[1];
        edit(c, grid_row.text, function() snap.switch(settings, on); end);
    end;
    imgui.Spacing();
    group_caption(imgui, c, window_caption);
    if tick(imgui, c, peek_row, settings.window.peek) then
        local on = peek_row.value[1];
        edit(c, peek_row.text, function() settings.window.peek = on; end);
    end;
    local menu = settings.window_style;
    local chosen = number(imgui, c, window_text, menu.font_size);
    if chosen then c.changed(function() menu.font_size = chosen; end, false, window_text.text); end;
end;

function page.draw(imgui, settings, view, callbacks, c)
    callbacks = callbacks or {};
    refresh(imgui, settings, callbacks);
    if not settings.enabled and attention(imgui, c, 'Timer panels are paused.', resume) then
        edit(c, 'Resume timer panels', function() settings.enabled = true; end);
    end;
    if not settings.effect_filters.enabled and attention(imgui, c, 'The Hide list is paused.', use_list) then
        edit(c, 'Use the Hide list', function() settings.effect_filters.enabled = true; end);
    end;
    if said.no_cooldowns and attention(imgui, c, 'Party cooldowns has nowhere to show.', cooldown_list) then
        edit(c, 'Show them in a list', function() settings.party_cooldowns.list.enabled = true; end);
    end;
    if said.no_pulse_row and attention(imgui, c, 'No recast panel is on, so the ready pulse has no row to play on.', pulse_spot) then
        edit(c, 'Use a spot of its own', function() settings.ready_pulse.spot = 'screen'; end);
    end;
    if said.samples and attention(imgui, c, said.samples, end_samples) then
        edit(c, 'End samples', function() defaults.samples_off(settings); end);
    end;
    if require('ui.edit_mode').active() and attention(imgui, c, 'Arrange on screen is on.', end_edit) and callbacks.edit_mode then callbacks.edit_mode(false); end;
    if callbacks.displays_hidden and callbacks.displays_hidden() and attention(imgui, c, 'Vantage displays are hidden (/vg hide).', show_displays)
        and callbacks.show_displays then callbacks.show_displays(); end;
    what_to_show(imgui, settings, view, c);
    how_it_looks(imgui, settings, c);
    moving(imgui, settings, callbacks, c);
end;

return page;
