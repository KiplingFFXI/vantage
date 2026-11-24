-- The editor of the icons above heads in the game world (settings.overhead), as a display on the panel frame. Each kind of
-- unit has its own layout, limits, lights and filters, picked by Change the settings for on each tab that has them. Nothing
-- over heads is dragged, so there is no lock.
local conditions_ui = require('ui.condition_settings');
local frame = require('ui.panel_frame');
local overhead_defaults = require('ui.overhead_defaults');
local preview = require('ui.overhead_preview');
local rows = require('ui.panel_rows');
local status = require('ui.status_panel');
local page = {};
local ctx = frame.ctx;
local selection = { kind = 'mob', name = '' };

-- Who can get a block, and what each switch says. The target and subtarget get one whatever they are, but not a mob
-- the server keeps out of sight. The claimed, watched and debuffed ones are mobs.
local units = {
    { 'target', 'Your target', 'Your current target gets a block, unless it\'s a mob the game keeps out of sight. A player or pet uses its own kind\'s layout and filters.' },
    { 'subtarget', 'Your subtarget', 'The unit under the subtarget cursor, unless it\'s a mob the game keeps out of sight.' },
    { 'claimed', 'Mobs your party claimed', 'Mobs claimed by you, your party or your alliance.' },
    { 'watched', 'Watched mobs', 'The mobs on the list on Watched enemy timers.' },
    { 'debuffed', 'Mobs your party debuffed', 'Mobs with a debuff from you, your party, your alliance or a pet of yours or theirs.' },
    { 'party', 'Your party' },
    { 'alliance', 'Your alliance', 'Their effects are the ones Vantage saw land on them. The game sends buff icons for your own party only.' },
    { 'other', 'Other players', 'Off at first: the game can send up to 32 of them around you.' },
    { 'pet', 'Your pet' },
    { 'other_pet', 'Other players\' pets', 'Their pets.' },
    { 'self', 'You', 'Off at first, as the self timer panels show your own effects. It hides in first person.' },
};
local kind_labels = { mob = 'Mobs', party = 'Party', alliance = 'Alliance', other = 'Other players', pet = 'Your pet',
    other_pet = 'Other players\' pets', self = 'You' };
local layout_labels = { single = 'Single bar', lines = 'Two lines', split = 'Split' };
local kinds_labels = { all = 'Buffs and debuffs', buff = 'Buffs only', debuff = 'Debuffs only' };
-- What a player would type for the effect switches.
local switch_words = { ['Corsair rolls'] = 'rolls cor phantom roll double-up', ['Bard songs'] = 'songs bard minuet march',
    ['Protect and Shell'] = 'protect shell protectra shellra', Barspells = 'bar barfire barvirus', Stances = 'stance hasso seigan',
    ['Signet and similar'] = 'signet reraise sanction' };
local KIND_ROW = 'Change the settings for';
local SHOW_ROW = 'Show buffs or debuffs';

local function root(c) return c.p; end;
local function kind(c) return c.p.types[selection.kind]; end;
local function picks() return selection; end;
local function unit_switches(c) return c.p.units; end;
local function size(c) return c.p.size; end;
local function layout(c) return c.p.layout; end;
-- A side Show leaves out takes its rows with it, though Always show can put buffs on a kind on Debuffs only.
local function shows_buffs(c) return kind(c).kinds ~= 'debuff'; end;
local function shows_debuffs(c) return kind(c).kinds ~= 'buff'; end;
local function shows_both(c) return kind(c).kinds == 'all'; end;
local function always_ticked(c)
    for _, tick in ipairs(overhead_defaults.always) do
        if kind(c)[tick.key] then return true; end;
    end;
    return false;
end;
local function draws_buffs(c) return shows_buffs(c) or always_ticked(c); end;
local function draws_both(c) return shows_both(c) or shows_debuffs(c) and always_ticked(c); end;
local function laid_out(name, shows)
    return function(c) return kind(c).layout == name and shows(c); end;
end;
local function nobody_watched(c) return c.p.units.watched and #c.s.watch_ids == 0; end;
-- Only effects I cast already holds what the two narrower ticks would ask for.
local function mine_only(c) return kind(c).mine_only; end;
-- ui/overhead_icons.lua reads these two only on Split, and the crowd control icon only for mobs.
local function crowd_icon(c)
    local mob = c.p.types.mob;
    return mob.layout == 'split' and mob.cc_slot and mob.kinds ~= 'buff';
end;
local function any_layout(c, name)
    for _, key in ipairs(overhead_defaults.types) do
        if c.p.types[key].layout == name then return true; end;
    end;
    return false;
end;
local function any_split(c) return any_layout(c, 'split'); end;
-- The gap above Two lines' first line, and above a member's line of party cooldowns.
local function any_lines(c)
    local watch = c.s.party_cooldowns;
    return any_layout(c, 'lines') or watch.enabled and watch.overhead;
end;
-- An icon under 14 pixels has no countdown, so one that can't grow to that has none.
local function countdown_fits(c) return c.p.size.max_px >= 14; end;
-- What lights an icon: the mob light or a kind's.
local function any_light(c)
    if c.p.dispel_light then return true; end;
    for _, key in ipairs(overhead_defaults.types) do
        if c.p.types[key].cleanse_light then return true; end;
    end;
    return false;
end;

-- A unit name as the head offsets keep one: 1 to 40 characters with no control characters.
local function unit_name(text)
    local name = tostring(text or ''):match('^%s*(.-)%s*$');
    if name == '' or #name > 40 or name:find('[%c]') then return nil; end;
    return name;
end;

-- The light the kind picked offers: Mobs light buffs, Party, Alliance and You light debuffs, and the other kinds have none.
local function light(c)
    if selection.kind == 'mob' then return 'buff'; end;
    if kind(c).cleanse_light ~= nil then return 'debuff'; end;
end;

-- The samples are laid out as the kind picked, while this panel is open.
local function follow_pick()
    if not ctx.p.types[selection.kind] then selection.kind = 'mob'; end;
    preview.show(selection.kind);
end;

-- Above the tabs, so it shows on each. Where a tab's rows for the kind start, a line says which kind they are for.
local kind_row = frame.pick(KIND_ROW, 'kind', overhead_defaults.types, kind_labels,
    'Your target, subtarget and the claimed, watched and debuffed mobs share Mobs; a player you target uses its own kind. Show samples shows this kind.', {
    of = picks, transient = true, buttons = true, alias = 'Unit type Unit type to edit Unit type picked Layout, limits, size, lights and filters for each type of unit' });
local kind_for = {};
for _, key in ipairs(overhead_defaults.types) do kind_for[key] = 'For ' .. kind_labels[key] .. ', as picked above:'; end;
local kind_line = frame.note(function() return kind_for[selection.kind]; end, { live = true });

-- Header.

local header = {
    { kind = 'custom', draw = follow_pick },
    frame.line(nil, nil, {
        frame.tick('On', 'enabled', 'Shows buffs and debuffs above heads in the game world. Turning it off ends its samples.', {
            tag = '_display', find = 'Show this display', alias = 'Show overhead icons Show this panel display',
            write = function(c, on)
                c.p.enabled = on;
                if not on then c.p.preview = false; end;
            end }),
        rows.samples('Sample icons above your head, laid out as the kind picked under Change the settings for, or near the middle of the screen when you aren\'t on it. They never make real alerts.',
            function(c) return c.p.enabled; end, { alias = 'Sample displays' }),
    }),
};

-- Show.

local unit_ticks = {};
for index, unit in ipairs(units) do unit_ticks[index] = frame.tick(unit[2], unit[1], unit[3], { of = unit_switches }); end;

local show_rows = {
    rows.columns('##overhead_units', 'Show icons over', 'Each kind of unit has its own switch. The most important get a block first, nearest first.', unit_ticks, { alias = 'Who gets icons' }),
    frame.note('No mobs are watched now.', { only = nobody_watched }),
    frame.button('Watch my target', 'Adds your target to Watched mobs, and to the list on Watched enemy timers, and turns that panel on. It shows on screen once it has a timer to show. The list clears when you change zones.', status.watch_target, { only = nobody_watched, shown_by = 'Watched mobs', beside = true }),
    frame.number('Most units at once', 'max_units', 1, 24, 'Your target, subtarget, claimed, watched and debuffed mobs come first, then the party, your pet, the alliance and everyone else.'),
    frame.number('Farthest away', 'distance_cap', 5, 50, 'Yalms from you. The game sends actions within 30 yalms of whoever acts; Vantage can keep what it saw up to 50.', {
        alias = 'Distance cap', format = '%.0f yalms',
        write = function(c, value)
            local o = c.p;
            o.distance_cap, o.fade_start = value, math.min(o.fade_start, value);
        end }),
    frame.number('Fade starts at', 'fade_start', 0, 50, 'Yalms from you. Past this a block fades until Farthest away. Your target never fades.', {
        format = '%.0f yalms', high_of = function(c) return c.p.distance_cap; end }),
    frame.number('Faded opacity', 'fade_alpha', 0, 1, 'How faint a block is at Farthest away.', { whole = false, shown_by = 'Fade starts at',
        only = function(c) return c.p.fade_start < c.p.distance_cap; end }),
    frame.tick('Only your target and party in towns', 'hide_in_cities', 'In towns, only your target, subtarget and party get blocks. Sealion\'s Den isn\'t counted as a town.'),
    kind_line,
    frame.pick('Layout', 'layout', overhead_defaults.layouts, layout_labels,
        'Single bar puts debuffs, then buffs, in one row. Two lines puts debuffs nearest the name and buffs above. Split puts buffs left and debuffs right. Icons past a limit are left out.', { of = kind }),
    frame.number('Debuffs shown', 'line_debuffs', 1, 32, nil, { tag = '_lines', of = kind, only = laid_out('lines', shows_debuffs), shown_by = { 'Layout', SHOW_ROW } }),
    frame.number('Buffs shown', 'line_buffs', 1, 32, nil, { tag = '_lines', of = kind, only = laid_out('lines', draws_buffs), shown_by = { 'Layout', SHOW_ROW } }),
    frame.tick('Swap the lines', 'swap_lines', 'Puts the buff line nearest the name.', { of = kind, only = laid_out('lines', draws_both), shown_by = { 'Layout', SHOW_ROW } }),
    frame.number('Buffs shown', 'split_buffs', 1, 32, nil, { tag = '_split', of = kind, only = laid_out('split', draws_buffs), shown_by = { 'Layout', SHOW_ROW } }),
    frame.number('Debuffs shown', 'split_debuffs', 1, 32, nil, { tag = '_split', of = kind, only = laid_out('split', shows_debuffs), shown_by = { 'Layout', SHOW_ROW } }),
    frame.tick('Swap the sides', 'swap_sides', 'Puts debuffs on the left and buffs on the right.', { of = kind, only = laid_out('split', draws_both), shown_by = { 'Layout', SHOW_ROW } }),
    frame.tick('Crowd control icon on its own', 'cc_slot', 'Draws the strongest crowd control debuff, such as Sleep, Stun or Doom, larger near the middle, always with its countdown. It counts against the debuff limit.', {
        of = kind, shown_by = { 'Layout', KIND_ROW, SHOW_ROW }, alias = 'Crowd control slot',
        only = function(c) return selection.kind == 'mob' and kind(c).layout == 'split' and shows_debuffs(c); end }),
    frame.number('Icons shown', 'limit', 1, 32, 'Debuffs come first, then buffs, by importance and then oldest first.', { of = kind, shown_by = 'Layout',
        only = function(c) return kind(c).layout ~= 'lines' and kind(c).layout ~= 'split'; end }),
    frame.tick('Countdowns', 'countdown', 'Effects with no known time show no countdown.', { of = kind, only = countdown_fits, shown_by = 'Largest', alias = 'Show countdowns' }),
    frame.radio('Show', 'kinds', overhead_defaults.kinds, kinds_labels, 'Which of this kind\'s effects show.', { tag = '_kinds', find = SHOW_ROW, of = kind, alias = 'Effect types' }),
    frame.tick('Light up buffs you can remove', 'dispel_light', 'A mob\'s buff lights up when your job and level can take it off now: Dispel, Magic Finale, Blank Gaze or Dark Shot, learned or set.', {
        of = root, own = true, shown_by = { KIND_ROW, SHOW_ROW }, only = function(c) return light(c) == 'buff' and draws_buffs(c); end, alias = 'dispel dispellable lit light up mob buffs Magic Finale Blank Gaze Dark Shot' }),
    frame.tick('Light up debuffs you can remove', 'cleanse_light', 'A debuff lights up when your job and level can take it off now with a spell you\'ve learned: Poisona, Paralyna, Blindna, Silena, Cursna, Viruna, Stona or Erase. Erase doesn\'t reach the alliance.', {
        of = kind, shown_by = { KIND_ROW, SHOW_ROW }, only = function(c) return light(c) == 'debuff' and shows_debuffs(c); end, alias = 'cleanse erase poisona paralyna blindna silena cursna viruna stona' }),
};

-- Size and place.

-- The sizes Icon size and the scaling give, in pixels on this screen, before Icon size for this kind. A medium unit at
-- the distance Icon size is for, at half and at twice it, then the smallest and largest players there (core/overhead.lua).
-- The scale goes by the screen's height and Size, as overhead.update works it out, but that runs only while the icons are
-- on, so it's worked out here too. The line asks each frame and makes new words only when the settings or the screen's
-- height change.
local pixels_said = {};
local function pixels(c)
    local overhead, height = require('core.overhead'), require('imgui').GetIO().DisplaySize.y;
    local memo = pixels_said;
    if memo.owner == c.s and c.revision ~= nil and memo.revision == c.revision and memo.height == height then return memo.text; end;
    local ui, near = height / 1080 * (c.s.style.scale or 1), c.p.size.ref_depth;
    local function px(player, race, depth) return math.floor(overhead.icon_size(player, race, c.p.size.ref_hitbox, '', depth, false, c.p, ui) + 0.5); end;
    memo.owner, memo.revision, memo.height = c.s, c.revision, height;
    memo.text = ('%g yalms from the camera, a medium unit gets %d px icons, a Tarutaru %d px and a Galka %d px. A medium unit gets %d px at %g yalms and %d px at %g.')
        :format(near, px(false, 0, near), px(true, 5, near), px(true, 8, near), px(false, 0, near / 2), near / 2, px(false, 0, near * 2), near * 2);
    return memo.text;
end;

local place_rows = {
    frame.note('Icons follow how big the unit is on screen: its distance from the camera, and its size from Phoenix hitboxes. Size on the main page scales them too.'),
    frame.number('Icon size', 'base', 12, 48, 'The size of a medium unit 10 yalms from the camera.', { of = size, alias = 'Overhead icon size' }),
    frame.number('Smallest', 'min_px', 10, 64, 'Countdowns need 14 or more.', { of = size, alias = 'Smallest icon',
        write = function(c, value)
            local kept = c.p.size;
            kept.min_px, kept.max_px = value, math.max(kept.max_px, value);
        end }),
    frame.number('Largest', 'max_px', 10, 64, 'The most an icon grows to.', { of = size, alias = 'Largest icon',
        write = function(c, value)
            local kept = c.p.size;
            kept.max_px, kept.min_px = value, math.min(kept.min_px, value);
        end }),
    frame.number('Bigger on your target', 'target_scale', 1, 1.6, 'Times the size on your current target.', { of = size, whole = false, alias = 'Target emphasis' }),
    frame.fold('Fine-tune scaling', 'How icons grow and shrink with the distance and the unit\'s size, and the sizes in pixels that gives.', {
        frame.number('Shrink with distance', 'alpha', 0, 1, '0 keeps one size at every distance. 1 shrinks icons as the unit shrinks on screen.', { of = size, whole = false, alias = 'Scale with distance' }),
        frame.number('Bigger units get bigger icons', 'beta', 0, 1, '0 draws every unit\'s icons at one size. Higher draws dragons and Galka larger than goblins and Tarutaru.', { of = size, whole = false, alias = 'Scale with unit size' }),
        frame.note(pixels, { live = true }),
    }, { alias = 'Icon size in pixels px' }),
    frame.number('Crowd control icon size', 'cc_scale', 1, 2, 'Times the icon size, for Crowd control icon on its own. It is the same for every kind.', { of = layout, whole = false, only = crowd_icon, shown_by = 'Crowd control icon on its own' }),
    frame.number('Countdowns go inside icons under', 'small_icon_inside_px', 0, 64, 'From this icon size up, a countdown goes under its icon. Smaller icons, down to 14 pixels, hold it inside, and under 14 there is none. Every kind shares it.', {
        alias = 'Countdown text', only = countdown_fits, shown_by = 'Largest' }),
    kind_line,
    frame.number('Icon size for this kind', 'size_scale', 0.5, 2, 'Times Icon size above.', { of = kind, whole = false, alias = 'Icon size for this type' }),
};

-- Look.

local look_rows = {
    -- Overhead icons draw with the main page's icon artwork and have no choice of their own, so this says where it is. With
    -- this line, Look always has something to show.
    frame.line('Its icons are the main page\'s Icons', 'Overhead icons use the artwork Icons picks on the main page: Original FFXI, XI View or a set of your own. A party cooldown over a head draws its icon as the recast panels do.', {
        frame.button('Open Icons', 'Opens Artwork on the main page, where Icons is.', function(c) c.open_page('Home', nil, 'Artwork'); end),
    }, { alias = 'Icon artwork icon set change icons Original FFXI XI View Recast icons' }),
    frame.color('Countdown color', 'countdown_color', nil, { only = countdown_fits, shown_by = 'Largest', fallback = function() return { 1, 1, 1, 1 }; end }),
    frame.fold('Lit icons', 'How an icon looks when it lights up. These are the same for every kind.', {
        frame.tick('Glow around lit icons', 'dispel_glow', 'Lit icons, on the main page, sets this on every display at once.', { alias = 'Glow around lit buffs' }),
        frame.color('Light color', 'dispel_color', 'Lit icons, on the main page, sets this on every display at once.', { fallback = function() return require('ui.defaults').dispel_color; end }),
    }, { only = any_light, shown_by = { 'Light up buffs you can remove', 'Light up debuffs you can remove' } }),
};

-- Filters.

local switch_ticks = {};
for index, switch in ipairs(overhead_defaults.switches) do
    switch_ticks[index] = frame.tick(switch.label, switch.key, switch.help, { of = kind, alias = switch_words[switch.label], shown_by = SHOW_ROW,
        only = shows_buffs });
end;
local always_ticks = {};
for index, tick in ipairs(overhead_defaults.always) do
    always_ticks[index] = frame.tick(tick.label, tick.key, tick.help, { of = kind, alias = tick.words });
end;

local filter_rows = {
    kind_line,
    frame.tick('Use the Hide list', 'shared_rules', 'The Hide list applies here too. Its Enemies, Other players and Pets groups match these units.', { of = kind, alias = 'Use shared hide rules' }),
    frame.button('Edit the list', 'Open the Hide list.', function(c) c.open_page('Filters'); end, { alias = 'Shared effect filters' }),
    status.list_paused(),
    frame.tick('Only effects I cast', 'mine_only', 'Effects with no named caster do not count as yours.', { of = kind, alias = 'Only effects I applied Filters for this type' }),
    frame.tick('Only buffs I cast', 'buffs_mine_only', 'Debuffs still show.', { of = kind, locks = mine_only, only = shows_buffs, shown_by = SHOW_ROW }),
    frame.tick('Only debuffs from my party', 'debuffs_party_only', 'From you, your party, your alliance or a pet of yours or theirs. A debuff whose caster wasn\'t seen stays.', { of = kind, locks = mine_only, only = shows_debuffs, shown_by = SHOW_ROW }),
    -- While a kind shows debuffs only they keep their values, aren't listed and decide nothing (core/overhead.lua).
    rows.columns('##overhead_switches', 'Show these effects:', 'Ticked shows, unticked hides. Effects on Show only show either way. The other filters still apply.', switch_ticks, {
        shown_by = SHOW_ROW, alias = 'Leave out the usual long effects', only = shows_buffs }),
    frame.line('Always show', 'Ticked, it shows whoever cast it, even with Only buffs I cast or Debuffs only on. Unticked, it hides unless it\'s on Show only, where the other filters still apply.', always_ticks, {
        shown_by = KIND_ROW, only = function() return overhead_defaults.always_for[selection.kind]; end }),
};
-- What Reset this tab puts back on Filters: the settings of the type chosen, as the tab shows one at a time.
local filter_keys = { 'shared_rules', 'mine_only', 'buffs_mine_only', 'debuffs_party_only', 'include', 'exclude' };
for _, switch in ipairs(overhead_defaults.switches) do filter_keys[#filter_keys + 1] = switch.key; end;
for _, tick in ipairs(overhead_defaults.always) do filter_keys[#filter_keys + 1] = tick.key; end;
local function filter_paths(id)
    local paths = {};
    for index, key in ipairs(filter_keys) do paths[index] = 'types.' .. id .. '.' .. key; end;
    return paths;
end;
for _, item in ipairs(rows.effect_lists({
    of = kind, sorted = true, live = true, show = 'Show only', hide = 'Hide here',
    listed = { include = 'Show only', exclude = 'Hidden here' },
    alias = { find = 'Find an effect Find an overhead effect Overhead effect', show = 'Include for this type', hide = 'Hide for this type' },
})) do filter_rows[#filter_rows + 1] = item; end;

-- If icons sit too high or too low.

local head_memo = { say = function(c)
    local names = {};
    for name in pairs(c.p.head.offsets) do names[#names + 1] = name; end;
    table.sort(names);
    return names;
end, memo = {} };
-- The name the rows of the list are drawn for.
local offset_name = '';

local function has_offsets(c) return next(c.p.head.offsets) ~= nil; end;

-- Reset this tab clears every name's offset at once (tab_reset below), so the row for one name puts back nothing itself.
local offset_rows = {
    frame.number('Offset in yalms', nil, -3, 5, 'Added to this unit\'s head height. Positive raises its block.', { whole = false, only = has_offsets, shown_by = 'Add head offset',
        of = function(c) return c.p.head.offsets; end, key_of = function() return offset_name; end, own = true }),
    frame.button('Remove head offset', nil, function(c)
        local offsets, name = ctx.p.head.offsets, offset_name;
        c.changed(function() offsets[name] = nil; end, true, 'Remove head offset');
    end, { only = has_offsets, shown_by = 'Add head offset' }),
};

local function draw_offsets(imgui, c)
    local names = frame.said(head_memo);
    for index = 1, #names do
        offset_name = names[index];
        imgui.PushID('head_offset_' .. offset_name);
        imgui.TextUnformatted(offset_name);
        frame.draw_rows(imgui, c, offset_rows);
        imgui.PopID();
    end;
    if #names == 0 then frame.shaded(imgui, c, 'No head offsets yet.'); end;
end;

local function target_name(c)
    local target = c.view and c.view.context and c.view.context.target;
    return target and type(target.name) == 'string' and target.name ~= '' and target.name or nil;
end;

for _, item in ipairs({
    frame.pick('Where the icons sit', 'placement', { 'above_name', 'below_name' }, { above_name = 'Above the name', below_name = 'Under the head' },
        'Above the name puts each block just over the game\'s name, and over your target\'s cursor. Under the head is for players who turn names off.', { of = layout, alias = 'Block placement Placement and spacing' }),
    frame.number('Gap above the name', 'gap', 0, 20, 'Pixels between the block and the name, or the target cursor when it is higher.', { of = layout }),
    frame.number('Space between icons', 'icon_gap', 0, 16, nil, { of = layout, special = { [0] = 'Automatic' } }),
    frame.number('Space between lines', 'line_gap', 0, 16, nil, { of = layout, only = any_lines, shown_by = 'Layout' }),
    frame.number('Space between the two sides', 'split_gap', 0, 40, nil, { of = layout, alias = 'Split middle gap', only = any_split, shown_by = 'Layout' }),
    frame.fold('If icons sit too high or too low', 'Move the block for the kind picked above, or over one unit by its exact name.', {
        frame.number('Head height offset', 'world_offset', -3, 5, 'Yalms added above the head before the block is placed. A head offset below sets one unit.', { of = kind, whole = false }),
        frame.number('Across', 'screen_x', -200, 200, 'Pixels after the block is placed. Positive moves it right.', { of = kind, alias = 'Horizontal offset' }),
        frame.number('Down', 'screen_y', -200, 200, 'Pixels after the block is placed. Positive moves it down.', { of = kind, alias = 'Vertical offset' }),
        frame.note('For one unit, by its exact name. /vg overhead calibrate prints your target\'s head height and where it comes from.'),
        frame.text('Unit name', 'name', 'The exact name, as the game shows it.', { of = picks, transient = true, length = 40 }),
        frame.button('Use my target\'s name', 'Fills in Unit name.', function() selection.name = target_name(ctx); end, { only = target_name, shown_by = 'Unit name' }),
        frame.button('Add head offset', 'Adds the name with no offset. Set it with its slider.', function(c)
            local name, offsets = unit_name(selection.name), ctx.p.head.offsets;
            if not name then c.note('Enter a name of 1 to 40 characters first.'); return; end;
            if offsets[name] ~= nil then c.note(name .. ' already has a head offset.'); return; end;
            local count = 0;
            for _ in pairs(offsets) do count = count + 1; end;
            if count >= 256 then c.note('Remove a head offset before adding another.'); return; end;
            c.changed(function() offsets[name] = 0; end, true, 'Add head offset');
            selection.name = '';
        end),
        { kind = 'custom', draw = draw_offsets, rows = offset_rows },
    }, { key = 'Head offsets by name', alias = 'Head offsets by name' }),
}) do place_rows[#place_rows + 1] = item; end;

frame.register({
    id = 'overhead', name = 'Overhead icons', fold_page = 'Overhead',
    tabs = { show = show_rows, look = look_rows, filters = filter_rows, place = place_rows, when = conditions_ui.rows },
    -- The Mobs light is a Mobs row on Show, so it goes back only with Mobs picked.
    tab_reset = { filters = function(c, fresh) frame.reset_keys(filter_paths(selection.kind))(c, fresh); end, place = frame.reset_keys({ 'head.offsets' }),
        show = function(c, fresh) if selection.kind == 'mob' then c.p.dispel_light = fresh.dispel_light; end; end },
    header = header, under = { kind_row }, under_box = true,
});

if VANTAGE_TEST_MODE then
    page._selection = selection;
end

return page;
