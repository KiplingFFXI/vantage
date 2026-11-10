-- What the settings search finds: every control of every page and what else finds it, the topics, and what shows only
-- while a state is on. Loading this file builds it and brings in every display's rows, so nothing requires it until a
-- key is typed in the search box. Drawing a page while the box has text keeps it up to date.
local frame = require('ui.panel_frame')
local skin = require('ui.client_skin')
local theme = require('ui.theme')
local index = { controls = {}, order = {}, words = {}, hidden_by = {} }

-- What finds a control past its own name, by the page it is on.
local more_words = {
    Home = {
        ['No boxes or headings']='Frameless timer panels',
        ['How it looks']='Look and size Customize appearance Colors, themes, fonts and sizing',
        ['What to show']='Customize displays Choose visible displays',
        ['Party list buffs']='Party and alliance Show party list buffs Party list buff settings Customize party',
        ['Font']='change font Panel font Settings font menu font Fonts typeface Overhead font Phantom Roll font Pet display font',
        ['More look']='More customization Settings menus',
        ['Edit Self buffs']='Customize timers',
        ['Edit Recasts']='Customize recasts', ['Edit Hidden everywhere']='All hide rules Open filters',
        ['Starter profile']='Starter layouts role melee tank healer support crowd control pet preset presets',
        ['Skin']='Frameless skin theme look ' .. table.concat(theme.names, ' ') .. ' XI View',
        ['Text size']='Effect text size Panel font size', ['Size']='Timer scale Overall scale 1x 1.5x 2x',
        ['Icon size']='Timer icon size Status and recast icon size', ['Settings text size']='Menu text size',
        ['Heading size']='Panel title size', ['Opacity']='Background opacity', ['Background']='Panel backgrounds', ['Border']='Panel borders',
        ['Hold Shift to see through this window']='peek',
        ['Window frame']='Window style Timer window style Menu window style Original FFXI XI View',
        ['Show details when I point at a timer']='Hover details',
        ['Hide Vantage in cutscenes, on the map and when the game hides its menus']='Hide during events Hide on the map Hide with the game interface',
        ['Hide timer panels while I type']='Hide while typing',
        ['Bold countdowns']='Bold effect countdowns',
        ['Countdown shadow']='Countdown text shadow Effect countdown shadow', ['Countdown outline']='Countdown text outline Effect countdown outline',
        ['Countdown outline color']='Effect countdown outline color', ['Other text shadow']='Text shadow', ['Other text outline']='Text outline',
        ['Blink before an effect ends']='Blink expiring icons',
        ['Blink seconds left']='Icon blink starts at',
        ['Gauges']='Timer gauge artwork', ['Icons']='Timer buff icons', ['Alerts']='Alerts on Enable alert rules',
        ['Recast icons']='Recast icon artwork XI View Original FFXI', ['Moving']='Move and lock Move displays layout placement shift drag move resize wrap unlock lock',
        ['Unlock all']='displays move resize shift drag placement', ['Lock all']='displays protect position size layout placement',
        ['Grid and snapping']='Tick the displays that snap snap to grid',
        ['Grid mode']='snap to grid snapping',
        ['Show samples']='Sample displays', ['End samples']='End sample displays',
        ['Edit mode']='Start edit mode',
        ['Spell recasts']='Include spell recasts Show spell recasts', ['Ability recasts']='Include ability recasts Show ability recasts',
        ['Item recasts']='Include item recasts Show item recasts', ['Recasts']='Show combined recasts',
    },
    Profiles = {
        ['Import from clipboard']='Read the clipboard Import a profile Import a profile from the clipboard Paste a share string', ['Import from a file']='Open a file Open a profile file',
        ['Save it as']='Name for the imported profile', ['Clear the import']='Clear the share string Cancel the import',
        ['Export a saved profile']='Export to clipboard Share a saved profile', ['Export a saved profile to a file']='Save a saved profile to a file',
        ['Load this profile when I change to']='Use a profile for a job Choose current job',
        ['Share settings across my characters']='Share selected settings across characters other character another character',
        ['Put every display back where it started']='Reset Reset panel layouts', ['Unlink all jobs']='Reset job profile links',
        ['Export']='What to export Copy', ['Copy the export']='Copy a share string',
        ['Import and add']='Add from an export Add from a share string', ['Import and replace']='Replace from an export Replace from a share string',
        ['Confirm ']='Confirm overwrite Confirm delete',
    },
    Help = {
        ['What can be tracked']='Recast tracking coverage',
        ['Record recent events']='Record recent diagnostic events', ['Export report']='Export diagnostic report',
    },
}

-- What a page draws only while a state is on. While it is off the search leaves those controls out, so no result
-- opens onto a control that isn't there, and their names and more words find the controls that show them (shown_by, on
-- the page shown_on when the name is on other pages too) instead. While it is on, the search finds them as it finds
-- any other control. Each state is one character of the search cache's key. A state is read again when the settings
-- change, and one marked live each time, as it reads more than the settings: what a page keeps for itself, the view,
-- the callbacks or what was drawn.
local only_while = {
    -- Grid mode shows the main page's fold with the grid's controls. A display's name finds that display's own controls,
    -- not Grid mode.
    { on = function(s) return s.edit_mode.grid_mode == true end, shown_by = { 'Grid mode' },
        hides = { Home = { 'Grid and snapping', 'Grid size', 'Show the grid', 'Snap to the grid',
            'Snap to the screen center and edges', 'Snap to other displays', "Snap to the game's party list",
            'Snap to the chat log', 'Snap distance' } } },
    -- Blink's seconds show while any display blinks.
    { on = function(s) return require('ui.shared_look').blink(s) ~= false end, shown_by = { 'Blink before an effect ends' },
        hides = { Home = { 'Blink seconds left' } } },
}
-- The main page lists a display's tick while Grid mode is on and the display is on. A party list strip is on once it
-- was drawn, so its tick's state is live.
do
    local elements = require('ui.elements')
    for _, element in ipairs(elements.movable) do
        local id = element.id
        only_while[#only_while + 1] = { shown_by = {}, hides = { Home = { element.label .. ' for Grid mode' } },
            on = function(s) return s.edit_mode.grid_mode == true and elements.on(s, id) end, live = element.strip ~= nil }
    end
end
local shown_words = {}
-- The names a control on a page is found by, past its own, with the states in on.
function index.hidden_words(label, page, on)
    local list, words = shown_words[label], ''
    if not list then return words end
    for _, shows in ipairs(list) do
        if (shows.page or page) == page and on:sub(shows.state, shows.state) ~= '1' then words = words .. shows.words end
    end
    return words
end

-- Every label of a page before it is opened. Drawing a page adds what its controls' help says.
local static_labels = {
    Profiles = [[Profiles|Saved profiles|Load profile|Overwrite profile|Rename profile|Delete profile|Confirm |Cancel profile change|Export a saved profile|Export a saved profile to a file|Profile name|Save as new|Load this profile when I change to|Link this job|Unlink this job|Unlink all jobs|Undo the last profile change|Across characters|Share settings across my characters|What to share across characters|Import and export|Export|Display to export|Copy the export|Import from clipboard|Import from a file|File to open|Import and add|Import and replace|Clear the import|Keep my own display positions|Save it as|Save as a new profile|Start over|Put every display back where it started|Reset all settings]],
    Help = [[Getting started|Reading a timer|What can be tracked|Alerts|Move and customize|Files and behavior|Record recent events|Export report|Copy shown timers|Copy timer details]],
    Durations = [[Duration overrides|Override applies to|Find what to override|What to override|Add duration override|Override to edit|Override enabled|Change the time to|Fixed time|Seconds to add or take away|Percent of the estimate|Only on a mob or player named|Use my target's name|Remove selected override|Clear duration overrides|Learned durations|Learn from my casts|Casts before a learned time is used|Clear learned durations|Reset this page]],
}
local controls = index.controls
for page, labels in pairs(static_labels) do
    controls[page] = {}
    for label in labels:gmatch('[^|]+') do controls[page][label] = label end
end
-- The rows of the panel frame.
controls.Display = frame.index({})
-- The main page lists its own labels, with their help.
controls.Home = {}
for _, entry in ipairs(require('ui.main_page').labels) do controls.Home[entry[1]] = entry[1] .. ' ' .. (entry[2] or '') end
-- More words are added after the keywords above, so neither replaces the other.
for page, names in pairs(more_words) do
    for label, alias in pairs(names) do controls[page][label] = (controls[page][label] or label) .. ' ' .. alias end
end

-- What a control is found by past its name and help. Drawing it keeps these words with the rest.
for page, labels in pairs(controls) do
    index.words[page] = {}
    for label, words in pairs(labels) do if words ~= label then index.words[page][label] = words end end
end

-- A fourth field names the place on that page a topic opens: a section, a display's tab or a row on it. A fifth names
-- the panel. A sixth sends the topic to the timer or recast panel that is open, or, as 'status', to a status panel only.
index.entries = {
    { 'Home', 'Skin, size, displays and moving', 'home setup start starter getting started overview enable disable show hide customize skin size extended minimal current mixed customized' },
    { 'Home', 'Skin and size', 'presets preset setup skin skins theme themes match matching fonts artwork client window skin apply theme everywhere one look extended minimal minimal1.5x 1.5x minimal2x 2x double small client party alliance buffs icons original ffxi xi view apply skin, size and customization', 'How it looks' },
    { 'Display', 'Shared buff and debuff visibility rules', 'global shared buff debuff hide filter filters Signet Level Sync recipient affected player name main job party alliance everywhere conditional rules', 'show', 'hidden' },
    { 'Display', 'Spell, ability, and item cooldowns', 'recast recasts spells abilities enchanted equipped items cooldown timers ready started wrap move resize customization fonts skins bars icons labels filters groups pinned alerts profiles combined separate together one panel', 'show', 'recasts' },
    { 'Display', 'Recast alerts', 'recast recasts spell ability cooldown started ready remaining alert notices chat sound flash emphasis domain', 'show', 'notices' },
    { 'Display', 'Party buff icons and opacity', 'party alliance original ffxi xi view xiview client buff icons icon pack artwork opacity', 'look', 'party_ui' },
    { 'Display', 'Buffs beside the game party list', 'Party & alliance roster members native game windows strips strip detached preview shift drag lock resize original ffxi xi view include exclude pin order effects icons icon pack left right beside side placement grow width', 'show', 'party_ui' },
    { 'Display', 'Buffs and debuffs above heads', 'overhead head heads above world mobs enemies monsters players nameplate floating target subtarget claimed watched debuffed party alliance pet single bar two lines split limit truncate dispel dispellable lit light glow crowd control distance cap fade towns size emphasis offset calibrate preview sample', 'show', 'overhead' },
    { 'Display', 'Party cooldowns: two-hours and key abilities', 'party alliance member members cooldown cooldowns two-hour two-hours 2-hour 2hr sp special ability abilities recast recasts estimated estimate watch list strips overhead heads Benediction Chainspell Manafont Invincible Soul Voice Convert Provoke Wild Card', 'show', 'cooldown_list' },
    { 'Display', 'Phantom Roll: totals, lucky numbers and bust chance', 'phantom roll rolls corsair cor double-up double up bust busted lucky unlucky total dice die snake eye chance odds window members party who got it effect gives bonus job luzaf', 'show', 'rolls' },
    { 'Display', 'Pet: HP, TP, effects, recasts and charm time', 'pet pets beastmaster bst summoner smn avatar dragoon drg wyvern puppetmaster pup automaton jug charm charmed familiar hp mp tp buffs debuffs effects recasts sic reward call beast blood pact rage ward call wyvern spirit link repair activate maneuver deploy estimate check', 'show', 'pet' },
    { 'Display', 'Recast marks and the ready pulse', 'tint tints MP mana cost afford silence silenced mute muted amnesia omerta impairment salvage lock locked grey gray pulse ready long recast early warning ignore screen spot test flash', 'Ready pulse', 'recasts' },
    { 'Durations', 'Duration overrides and learned durations', 'duration durations override overrides fixed time seconds add take away percent count up elapsed since landed learn learned learning casts samples mob name unit spell ability effect estimate estimated clear' },
    { 'Home', 'Edit mode: grid, snapping and nudging', 'edit mode layout move place drag shift arrow keys nudge pixel grid snap snapping snap to grid resize edge center edges line up coordinates x y lock unlock select pick outline', 'Moving' },
    { 'Display', 'What a display moves with', 'anchor anchors anchored attach follow corner edge screen party list chat log display fallback spot gap offset side align', 'Moves with' },
    { 'Display', 'When each display shows', 'show conditions when load hide job main sub level range level sync zone town field dungeon battlefield dynamis limbus assault salvage nyzul ashu talif mog house solo party alliance engaged combat pet', 'when' },
    { 'Profiles', 'Import and export settings', 'share string strings export import copy paste clipboard friend layout profile alert rules hide rules filters display add replace', 'Import and export' },
    { 'Display', 'Panel placement, locking and size', 'move drag shift left mouse unlock free resize edges corners width height position automatic fixed fit', 'place', nil, true },
    { 'Display', 'What each row shows and panel layout', 'icons only horizontal vertical stack direction wrapping bar width compact expanded name caster duration elapsed total countdown target source label wording divider separator format minutes seconds new line wrap alignment priority', 'show', nil, true },
    { 'Display', 'Panel look', 'gradient rail fill direction colors override thickness warning mark text height', 'look', nil, true },
    { 'Display', 'What a panel moves with', 'attachment attach dock chat width snap anchor follow', 'Moves with', nil, true },
    { 'Display', 'Sort, direction and ending-soon color', 'remaining name fixed fill drain threshold warning', 'show', nil, true },
    { 'Display', 'Party members', 'members party', 'show', 'party' },
    { 'Display', 'Watched enemies', 'enemy watch target', 'show', 'watch' },
    { 'Display', 'Watched enemies: list the ones you debuff', 'also enemy mob mobs debuff debuffs debuffed sleep crowd control without watching', 'Also list enemies I debuff', 'watch' },
    { 'Display', 'Mob buffs you can remove', 'target watched enemies mob enemy buffs dispel dispellable lit light up glow color Magic Finale Blank Gaze Dark Shot', 'show', 'target' },
    { 'Display', 'Debuffs you can remove', 'self party debuffs white mage whm cleanse erase lit light up glow color Poisona Paralyna Blindna Silena Cursna Viruna Stona', 'show', 'self_debuffs' },
    { 'Display', 'Effect filters, labels and pinned order', 'include exclude hide filter search custom customize label priority pin order category shown first last fill color', 'Filters', nil, true },
    { 'Display', 'Which kinds of effects a panel shows', 'group groups membership category', 'Show only some kinds of effects', nil, 'status' },
    { 'Display', 'Create and edit alert rules', 'gain missing removed worn off expiry threshold percent seconds reminder silence haste sleep', 'show', 'notices' },
    { 'Display', 'Alert sounds and notices', 'sound wav mp3 volume play test visual chat emphasize cooldown repeat mute', 'show', 'notices' },
    { 'Display', 'Notice position and resizing', 'notice visual lock unlock move resize shift left mouse drag edges corners automatic fixed width height maximum placement and size', 'place', 'notices' },
    { 'Display', 'Rule scope and conditions', 'self party target watch all job combat estimates', 'show', 'notices' },
    { 'Home', 'Colors, themes, fonts and sizing', 'minimal frameless timers skin font text size scale opacity background border rounding colors theme colorblind window palette outline shadow accent label value detail' },
    { 'Home', 'Settings menus', 'settings menus menu font text size window style theme colors reset window appearance', 'How it looks' },
    { 'Home', 'Settings window size and see-through', 'settings menus move resize shift left mouse drag inside center title header edges corners width height peek' },
    { 'Home', 'Hiding displays at game moments', 'cutscene events map game ui hide typing chat' },
    { 'Profiles', 'Save profiles and choose job profiles', 'save new overwrite rename recover modified source load delete profile job missing share character scope presentation layout undo reset' },
    { 'Help', 'Local diagnostic report', 'copy export report diagnostics record events recent bounded' },
    { 'Display', 'Flash and sound volume', 'flash volume inherit', 'show', 'notices' },
    { 'Help', 'Understand timing evidence and limits', 'server estimated untimed original duration packets read only passive help' },
}

-- Everything else a page draws only while a state is on. These read what the pages keep for themselves, so they sit
-- down here. A control in two states goes by the later one: the wider state comes first, and its switch finds the
-- control while that state is off, then the narrower state's switch does. Names are split by |. A list with no entries
-- yet is shown by its Add button.
do
    local function list(names)
        local out = {}
        for name in names:gmatch('[^|]+') do out[#out + 1] = name end
        return out
    end
    -- pages is a page or a list of them. shown_on is where shown_by is, when that isn't each of them.
    local function only(pages, shown_by, labels, on, shown_on)
        local hides = {}
        for _, page in ipairs(type(pages) == 'table' and pages or { pages }) do hides[page] = list(labels) end
        only_while[#only_while + 1] = { on = on, shown_by = list(shown_by), hides = hides,
            shown_on = shown_on or type(pages) == 'string' and pages or nil }
    end
    -- The same for a state that reads more than the settings, so it is read each time.
    local function live(...)
        only(...)
        only_while[#only_while].live = true
    end
    local function target_named(view)
        local target = view and view.context and view.context.target
        return target and type(target.name) == 'string' and target.name ~= ''
    end

    -- Timer durations: an override, then what its mode shows.
    local function override(s) return require('ui.duration_settings').override(s) end
    live('Durations', 'Add duration override', "Override to edit|Override enabled|Change the time to|Fixed time|Seconds to add or take away"
        .. "|Percent of the estimate|Only on a mob or player named|Use my target's name|Remove selected override|Clear duration overrides", override)
    for mode, label in pairs({ fixed = 'Fixed time', add = 'Seconds to add or take away', percent = 'Percent of the estimate' }) do
        live('Durations', 'Change the time to', label, function(s)
            local entry = override(s)
            return entry and entry.mode == mode
        end)
    end
    live('Durations', 'Only on a mob or player named', "Use my target's name", function(s, view) return override(s) and target_named(view) end)
    only('Durations', 'Learn from my casts', 'Clear learned durations', function(s) return next(s.durations.learned) end)
    only('Durations', 'Learn from my casts', 'Casts before a learned time is used', function(s) return s.durations.learn end)

    -- The main page.
    local main, defaults = require('ui.main_page'), require('ui.defaults')
    only('Home', 'Skin', 'Window frame|Gauges', function(s) return skin.active(s.style) end)
    only('Home', 'No boxes or headings', 'Background|Border', function(s) return not s.style.minimal end)
    live('Home', 'Font', 'Other text shadow', function(s) return not main.baked_shadow(s.style) end)
    only('Home', 'Countdown outline', 'Countdown outline color', function(s) return require('ui.shared_look').outline(s) ~= 'none' end)
    only('Home', 'Show the grid|Snap to the grid', 'Grid size', function(s)
        local e = s.edit_mode
        return e.grid_mode == true and (e.show_grid or e.snap_grid)
    end)
    -- One button for each pair, whichever of the two it is now.
    only('Home', 'Show samples', 'End samples', defaults.samples_showing)
    only('Home', 'End samples', 'Show samples', function(s) return not defaults.samples_showing(s) end)
    -- The page draws Lock all or Unlock all by its own line about the locks, made again when the settings change, and
    -- these go by the same.
    only('Home', 'Unlock all', 'Lock all', main.any_unlocked)
    only('Home', 'Lock all', 'Unlock all', function(s) return not main.any_unlocked(s) end)
    only('Home', 'Alerts', 'Unmute', function(s) return s.alerts.muted end)
    only('Home', 'Other text outline', 'Other text outline color', function(s) return s.style.text_outline end)
    only('Home', '', 'Resume', function(s) return not s.enabled end)
    only('Home', '', 'Use it again', function(s) return not s.effect_filters.enabled end)
    only('Home', '', 'Use a spot of its own', defaults.pulse_has_no_row)
    only('Home', '', 'Show them in a list', function(s) return s.party_cooldowns.enabled and not require('core.party_cooldowns').shown(s) end)
    live('Home', 'Edit mode', 'End edit mode', function() return require('ui.edit_mode').active() end)
    live('Home', '', 'Show', function(_, _, callbacks) return callbacks and callbacks.displays_hidden and callbacks.displays_hidden() end)

    -- Profiles and sharing.
    local function profiles() return require('ui.profiles_page') end
    live('Profiles', 'Overwrite profile|Delete profile', 'Confirm |Cancel profile change', function() return profiles().confirming() end)
    live('Profiles', '', 'Undo the last profile change', function() return profiles().seen.recover_available end)
    live('Profiles', 'Load this profile when I change to', 'Unlink this job', function(s, view) return profiles().job_linked(s, view) end)
    only('Profiles', 'Link this job', 'Unlink all jobs', function(s) return profiles().any_link(s) end)
    only('Profiles', 'Share settings across my characters', 'What to share across characters', function(s) return s.shared_layout end)
    live('Profiles', 'Import from clipboard|Import from a file', 'Import and add|Import and replace|Clear the import', function() return profiles().reading() end)
    live('Profiles', 'Import from clipboard|Import from a file', 'Save it as|Save as a new profile', function() return profiles().reading_profile() end)
    live('Profiles', 'Save it as', 'Keep my own display positions', function() return profiles().other_screen() end)
    live('Profiles', 'Import from a file', 'File to open', function() return profiles().listing() end)
    live('Profiles', 'Export', 'Display to export', function() return profiles().copying_display() end)
end
-- The state of each hidden control, by page, and for each control that shows them, that state and the names and more
-- words it is found by while they are hidden.
for number, state in ipairs(only_while) do
    local words, named = '', {}
    for page, labels in pairs(state.hides) do
        local hidden_by, more = index.hidden_by, more_words[page] or {}
        hidden_by[page] = hidden_by[page] or {}
        for _, label in ipairs(labels) do
            hidden_by[page][label] = number
            if not named[label] then named[label], words = true, words .. ' ' .. label .. ' ' .. (more[label] or '') end
        end
    end
    for _, shows in ipairs(state.shown_by) do
        shown_words[shows] = shown_words[shows] or {}
        table.insert(shown_words[shows], { state = number, words = words, page = state.shown_on })
    end
end

-- Each state's on(settings, view, callbacks) says if it is on. The view and callbacks are the window's, nil before its
-- first draw. live marks one the window reads each time, not only when the settings change.
index.states = only_while
index.more_words = more_words

return index
