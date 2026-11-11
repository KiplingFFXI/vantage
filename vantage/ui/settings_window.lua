local defaults = require('ui.defaults')
local theme = require('ui.theme')
local fonts = require('ui.fonts')
local skin = require('ui.client_skin')
local resize = require('ui.resize')
local frame = require('ui.panel_frame')
local window = {}
local search, effect_search = { '' }, { '' }
local message, message_at, pending = nil, 0, false
local callbacks, imgui, settings, live_view
local catalog_cache, catalog_seen = nil, {}
-- Goes up whenever the status catalog changes: when it's made, when a row is added, and when the client names a row in it.
local catalog_changes, catalog_renamed = 0, nil
local recast_catalog_cache, empty_catalog, recast_view_signature = {}, {}, ''
local recast_signature_frame, draw_frame, saved_revision, recast_list_frame = -1, 0, -1, -1
-- A look pick waiting for Apply or Cancel: { id, owner, text, action }.
local look_confirm
local escape_busy = false
local matches_this_frame, selected_match, scroll_match = 0, 1, false
local control_revision, search_cache = 0, {}
local jump_section
local previous_matches, previous_query, search_page = 0, '', nil
local in_page = false
local menu_look
local resize_gesture, window_bounds, window_geometry
local message_kind = 'notes'
local tabs = { 'Home', 'Display', 'Durations', 'Profiles', 'Help' }
-- What a page is called in its top line and in search results.
local page_labels = { Home='Main page', Display='Timers and recasts', Durations='Timer durations', Profiles='Profiles and sharing' }
-- The page of the panel frame, and the names a command opens a display on it by. Which display and tab they open is
-- the frame's to say.
local frame_pages = { Display=true, Recasts=true, ['Party & alliance']=true, Filters=true }

local function note(text, kind)
    message, message_at, message_kind = text, os.clock(), kind or 'notes'
end

-- geometry marks a change that moves or resizes this window, which Undo then puts back.
local function changed(fn, save, label, geometry)
    if callbacks.changed then callbacks.changed('before', label or 'Settings change', nil, geometry) end
    fn()
    if callbacks.changed then callbacks.changed('after') end
    pending = true
    if save and callbacks.save then callbacks.save(); pending = false end
end

-- Which page or section is open: the app saves it later, or now when save is set.
local function editor_changed(fn, save)
    if not callbacks.editor_changed then return changed(fn, save, 'Settings navigation') end
    fn()
    callbacks.editor_changed(save)
end

local function call(name, ...)
    local handler = callbacks[name]
    if not handler then note('That action is not available right now.'); return false end
    local ok, problem = handler(...)
    if ok == false or problem then note(problem or 'That action could not finish.', 'problem_messages') end
    return ok
end

local function open_page(page, panel, destination)
    if frame_pages[page] then page, destination = 'Display', frame.route(page, panel, destination) end
    jump_section = destination
    editor_changed(function() settings.window.tab = page end)
    search[1], selected_match, scroll_match = '', 1, false
end

-- The tool pages, on the top bar. Each opens from a function made once, so a frame makes none.
local function tool_page(text, page, help) return { text = text, help = help, open = function() open_page(page) end } end
local tool_pages = {
    tool_page('Profiles', 'Profiles', 'Save these settings as a profile, load one, or share one.'),
    tool_page('Timer durations', 'Durations', 'Your own times for spells, abilities and effects, and the times learned from your casts.'),
    tool_page('Help', 'Help', 'What Vantage can track, and how to move and read things.'),
}

-- A word of four letters or more ending in s also finds a word that ends without the s, so samples finds Sample displays.
function window.matches(query, value)
    value = tostring(value or ''):lower()
    for word in tostring(query or ''):lower():gmatch('%S+') do
        -- A label's brackets and commas come along when it is typed out.
        local bare = word:gsub('^%p+', ''):gsub('%p+$', '')
        if bare ~= '' then word = bare end
        if not value:find(word, 1, true) then
            if #word < 4 or word:sub(-1) ~= 's' then return false end
            local stem = word:sub(1, -2):gsub('%p', '%%%0')
            if not value:find('%f[%w]' .. stem .. '%f[%W]') then return false end
        end
    end
    return true
end

function window.move(values, from, destination)
    if not values[from] then return false end
    destination = math.max(1, math.min(#values, destination))
    if from == destination then return false end
    local value = table.remove(values, from)
    table.insert(values, destination, value)
    return true
end

function window.can_escape(was_busy, active, popup, focused, pressed)
    return not was_busy and not active and not popup and focused and pressed
end

-- The search's light on the item just drawn, if text is what finds it. named is what it is called, while a match by name
-- is wanted.
function window.light(text, named)
    local memo = window.search_memo
    if memo.query ~= search[1] then memo.query, memo.verdicts = search[1], {} end
    local hit = memo.verdicts[text]
    if hit == nil then hit = window.matches(search[1], text); memo.verdicts[text] = hit end
    if not hit then return end
    matches_this_frame = matches_this_frame + 1
    if named and memo.pick and not memo.named and window.matches(search[1], named) then memo.named = matches_this_frame end
    if imgui.GetItemRectMin and imgui.GetWindowDrawList then
        local x1, y1 = imgui.GetItemRectMin()
        local x2, y2 = imgui.GetItemRectMax()
        local color = theme.u32(settings.style.warning_color)
        imgui.GetWindowDrawList():AddRect({x1, y1}, {x2, y2}, color, 2, 0, matches_this_frame == selected_match and 2 or 1)
    end
    if scroll_match and matches_this_frame == selected_match and imgui.SetScrollHereY then
        imgui.SetScrollHereY(0.35)
        scroll_match = false
    end
end

-- What the page draws while the box has text keeps the index up to date. An empty box does nothing here, as this runs for
-- every control on every frame.
local function mark(label, help)
    if search[1] == '' or not in_page then return end
    -- What follows ## is only an ImGui ID, so the index holds the words the player sees.
    label = label:match('^(.-)##') or label
    if label == '' then return end
    local index, page = require('ui.search_index'), search_page or settings.window.tab
    index.controls[page] = index.controls[page] or {}
    local labels = index.controls[page]
    if labels[label] == nil then index.order[page] = nil end
    local words = index.words[page]
    local indexed = label .. ' ' .. (help or '') .. ' ' .. (words and words[label] or '')
    local known = labels[label]
    if known ~= indexed then
        labels[label] = indexed
        -- A label drawn twice with different help changes back every frame, which is no reason to search again.
        local flipped, key = window.search_memo.flipped, page .. '/' .. label
        if flipped[key] ~= indexed then control_revision = control_revision + 1 end
        flipped[key] = known
    end
    -- A switch that shows hidden controls is lit by their names too while they are hidden, as the search found it.
    window.light(indexed .. index.hidden_words(label, page, search_cache.on or ''), indexed)
end

-- flags are ImGui's for what counts as hovered: a greyed row asks to be hovered while disabled.
local function tip(text, flags)
    if text and imgui.IsItemHovered(flags or 0) then
        skin.prepare_menu(imgui, menu_look)
        imgui.BeginTooltip()
        skin.menu(imgui, menu_look, 'tooltip')
        imgui.PushTextWrapPos(380)
        imgui.TextUnformatted(text)
        imgui.PopTextWrapPos()
        imgui.EndTooltip()
    end
end

-- A control's label, in the row ui/controls.lua lays out, with the control's help on hover.
local row_controls = require('ui.controls')
local function row_label(text, help)
    row_controls.label(imgui, text)
    tip(help)
end

-- A heading is a search target too. A title that changes with a pick isn't, so it passes unindexed.
local function heading(label, description, unindexed)
    imgui.Spacing()
    local palette = menu_look or theme.window and theme.window(settings)
    imgui.TextColored(palette and palette.headings or settings.style.title_color, label)
    if not unindexed then mark(label, description) end
    if jump_section == label and imgui.SetScrollHereY then imgui.SetScrollHereY(0); jump_section = nil end
    imgui.Separator()
    if description then
        if palette then imgui.PushStyleColor(ImGuiCol_Text, palette.notes) end
        imgui.TextWrapped(description)
        if palette then imgui.PopStyleColor() end
    end
end

-- page, from the panel frame, starts the key of the saved open state, and the frame lights the section itself.
local function section(label, description, opened, page)
    settings.window.sections = settings.window.sections or {}
    -- What follows ## in a label is the key of its saved open state.
    local key = (page or in_page and search_page or settings.window.tab) .. '/' .. (label:match('##(.+)$') or label)
    local saved = settings.window.sections[key]
    if saved == nil then saved = opened == true end
    imgui.Spacing()
    imgui.SetNextItemOpen(search[1] ~= '' or jump_section == label or saved, ImGuiCond_Always)
    local visible = imgui.CollapsingHeader(label)
    if jump_section == label and imgui.SetScrollHereY then imgui.SetScrollHereY(0); jump_section = nil end
    if not page then mark(label, description) end
    if search[1] == '' and visible ~= saved then editor_changed(function() settings.window.sections[key] = visible end) end
    tip(description)
    return visible
end

-- The value boxes the controls below hand ImGui, one for each kind, filled for each control. ImGui writes a change
-- into it during the call, and the control reads it straight after, before the next one draws.
local check_value, text_value, number_value = { false }, { '' }, { 0 }

local function check(label, object, key, help, setter)
    local value = check_value
    value[1] = object[key] == true
    local label_width = imgui.CalcTextSize(label:match('^(.-)##') or label)
    if label_width + imgui.GetFrameHeight() + 10 > imgui.GetContentRegionAvail()
        and imgui.GetCursorPosX() > imgui.GetFontSize() then imgui.NewLine() end
    local wrap = label_width + imgui.GetFrameHeight() + 10 > imgui.GetContentRegionAvail()
    if row_controls.checkbox(imgui, menu_look, wrap and '##' .. label or label, value) then
        if setter then setter(value[1]) else changed(function() object[key] = value[1] end, true, label) end
    end
    if wrap then imgui.SameLine(); imgui.TextWrapped(label:match('^(.-)##') or label) end
    mark(label, help)
    tip(help)
end

local function text(label, object, key, help, length, transient)
    row_label(label, help)
    local value = text_value
    value[1] = object[key] or ''
    imgui.SetNextItemWidth(-1)
    if imgui.InputText('##' .. label, value, (length or 80) + 1) then
        local function apply() object[key] = value[1]:gsub('[%c]', ''):gsub('##', '') end
        if transient then apply() else changed(apply, false, label) end
    end
    mark(label, help)
    tip(help)
end

-- options.slider ends the slider short of high, such as at an hour for Fixed time, and options.slider_low short of low.
-- Ctrl-click typing still reaches both.
local function number(label, object, key, low, high, help, integer, setter, options)
    local hint = (help or '') .. ' Ctrl-click the slider to type a value.'
    row_label(label, hint)
    local value = number_value
    value[1] = tonumber(object[key]) or low
    local top = options and options.slider and math.max(low, math.min(high, options.slider)) or high
    local bottom = options and options.slider_low and math.max(low, math.min(top, options.slider_low)) or low
    imgui.SetNextItemWidth(-1)
    if imgui.SliderFloat('##' .. label, value, bottom, top, integer == false and '%.2f' or '%.0f') then
        local chosen = tonumber(value[1])
        if chosen and chosen == chosen and math.abs(chosen) ~= math.huge then
            chosen = math.max(low, math.min(high, chosen))
            chosen = integer == false and chosen or math.floor(chosen + 0.5)
            changed(function() if setter then setter(chosen) else object[key] = chosen end end, false, label)
        end
    end
    mark(label, help)
    tip(hint)
end

-- How far a position or height slider reaches: the screen's edge, or 40 before the first frame knows the screen.
local function screen_edge(axis)
    local screen = imgui.GetIO().DisplaySize
    return math.max(40, axis == 'x' and screen.x or screen.y)
end

-- leaves names a button drawn beside it, and it stops short to leave that room.
local function combo(label, object, key, choices, labels, help, setter, transient, leaves)
    row_label(label, help)
    imgui.SetNextItemWidth(leaves and -(imgui.CalcTextSize(leaves) + 28) or -1)
    local selected = object[key]
    if selected == nil and labels and labels[''] then selected = '' end
    skin.prepare_menu(imgui, menu_look)
    if imgui.BeginCombo('##' .. label, labels and labels[selected] or tostring(selected or '')) then
        skin.menu(imgui, menu_look, 'popup')
        for _, value in ipairs(choices) do
            local shown = labels and labels[value] or tostring(value)
            if imgui.Selectable(shown .. '##' .. tostring(value), selected == value) then
                local function apply() if setter then setter(value) else object[key] = value end end
                if transient then apply() else changed(apply, true, label) end
            end
        end
        imgui.EndCombo()
    end
    mark(label, help)
    tip(help)
end

local function choice(label, object, key, choices, labels, help, setter, leaves)
    combo(label, object, key, choices, labels, help, setter, true, leaves)
end

local function query(label, object, key, help, length)
    text(label, object, key, help, length, true)
end

-- search names the button in the index when its caption alone says too little; false leaves it out.
local function button(label, action, help, display_label, search)
    local caption = display_label or label:match('^(.-)##') or label
    local label_width = imgui.CalcTextSize(caption)
    if label_width + 20 > imgui.GetContentRegionAvail() and imgui.GetCursorPosX() > imgui.GetFontSize() then imgui.NewLine() end
    local available = imgui.GetContentRegionAvail()
    local shown = caption
    if label_width + 20 > available then
        local lines = require('ui.text_wrap').lines(caption, math.max(1, available - 20), imgui.CalcTextSize)
        -- Keep the same button ID when its caption wraps.
        shown = table.concat(lines, '\n')
    end
    if imgui.Button(shown .. '###' .. label) then action() end
    if search ~= false then mark(search or label, help) end
    tip(help)
end

-- A skin pick asks first when it would replace a display's own look, and names those displays.
-- result is the settings the pick would make; label names the pick in the question.
local function confirm_look(id, action, result, label)
    local differences = require('ui.appearance').replaced(settings, result)
    if #differences == 0 then look_confirm = nil; return action() end
    local names = {}
    for index, entry in ipairs(differences) do names[index] = entry.label end
    local function list(values)
        return #values == 1 and values[1] or table.concat(values, ', ', 1, #values - 1) .. ' and ' .. values[#values]
    end
    look_confirm = { id = id, owner = settings, action = action,
        text = (label and label .. ' replaces' or 'Replaces') .. ' the custom look on: ' .. list(names) .. '.'
            .. ' Colors you set for one effect and row text colors stay.' }
end

local function pending_look(id)
    if look_confirm and look_confirm.owner ~= settings then look_confirm = nil end
    return look_confirm and look_confirm.id == id and look_confirm or nil
end

-- The question for one pick, drawn where that pick was made.
local function confirm_line(id)
    local pending = pending_look(id)
    if not pending then return end
    imgui.TextWrapped(pending.text)
    button((pending.apply or 'Apply') .. '##look_' .. id, function() look_confirm = nil; pending.action() end,
        pending.apply_help or 'Apply it and replace those looks. Undo brings them back.')
    imgui.SameLine()
    button('Cancel##look_' .. id, function() look_confirm = nil end, pending.cancel_help or 'Keep every look as it is.')
end

-- A page, or a display's tab, opens at its top. A search keeps its place on what it found.
local top_of
local function start_at_top()
    local page = settings.window.tab
    local context = page == 'Display' and frame.context() or page
    if top_of ~= context then
        if search[1] == '' and imgui.SetScrollY then imgui.SetScrollY(0) end
        top_of = context
    end
end

-- Every effect id the settings name, for visit. One the pickers don't offer joins them, so a list or rule saved with it
-- can still be read and taken out.
local function saved_effects(visit)
    local function keys(values) for id in pairs(values or {}) do visit(tonumber(id)) end end
    local function list(values) for _, id in ipairs(values or {}) do visit(id) end end
    for _, p in pairs(settings.panels) do
        keys(p.include); keys(p.exclude); keys(p.pinned); keys(p.labels); keys(p.effect_colors); list(p.order)
    end
    for _, t in pairs(settings.overhead and settings.overhead.types or {}) do list(t.include); list(t.exclude) end
    for _, owner in ipairs({ settings.party_ui and settings.party_ui.effects or {}, settings.pet or {} }) do
        list(owner.include); list(owner.exclude); list(owner.pinned); list(owner.order)
    end
    for _, rule in ipairs(settings.effect_filters and settings.effect_filters.rules or {}) do visit(rule.effect) end
    for _, rule in ipairs(settings.alerts and settings.alerts.rules or {}) do visit(rule.effect) end
    for _, rule in ipairs(settings.durations and settings.durations.overrides or {}) do
        if rule.kind == 'effect' then visit(rule.id) end
    end
end

-- Lists sort without regard to case, as the client names debuffs in lowercase.
function window.by_name(a, b)
    local first, second = a.name:lower(), b.name:lower()
    return first == second and a.id < b.id or first < second
end

-- The recast ids the settings name, and a key that changes when they do. Walks the settings once a change. Undo and
-- Redo swap the table in the middle of a draw, so what was walked counts as well as the revision.
function window.saved_recasts()
    local revision = callbacks and callbacks.settings_revision and callbacks.settings_revision() or draw_frame
    local saved = window.recasts_saved
    if saved and saved.revision == revision and saved.settings == settings then return saved end
    local ids, list = {}, {}
    -- A search can run before the first draw has any settings.
    if settings then
        saved_effects(function(id)
            if id and id >= 10000 and not ids[id] then ids[id], list[#list + 1] = true, id end
        end)
    end
    table.sort(list)
    saved = { revision = revision, settings = settings, ids = ids, key = table.concat(list, ',') }
    window.recasts_saved = saved
    return saved
end

-- What core/recasts.lua calls a recast the client has no name for: a word and its number, which says nothing to a
-- player. The pickers leave those out.
local unnamed_recasts = { '^Spell %d+$', '^Ability timer %d+$', '^Item %d+$' }
local function named_recast(name)
    if type(name) ~= 'string' or name == '' then return false end
    for _, pattern in ipairs(unnamed_recasts) do if name:find(pattern) then return false end end
    return true
end

local function catalog(domain, kind)
    if domain == 'recast' then
        recast_list_frame = draw_frame
        if recast_signature_frame ~= draw_frame then
            local keys = {}
            for _, row in ipairs(live_view and live_view.rows or {}) do
                if row.domain == 'recast' then keys[#keys + 1] = tostring(row.effect) .. ':' .. tostring(row.name) .. ':' .. tostring(row.kind) end
            end
            recast_view_signature, recast_signature_frame = table.concat(keys, '|'), draw_frame
        end
        if kind == 'all' then kind = nil end
        local ok, recasts = pcall(require, 'core.recasts')
        local available = callbacks and callbacks.recast_catalog and callbacks.recast_catalog(kind)
            or ok and recasts.catalog and recasts.catalog(kind) or empty_catalog
        local cached, version, saved = recast_catalog_cache[kind or 'all'], live_view and live_view.recast_version, window.saved_recasts()
        if cached and cached.source == available and cached.version == version and cached.signature == recast_view_signature and cached.saved == saved.key then return cached.entries, cached.names end
        local entries, seen, names = {}, {}, {}
        for _, row in ipairs(available or {}) do
            if not kind or row.kind == kind then
                -- One that doesn't exist on Phoenix is on offer only if the settings name it, and always has its name.
                names[row.id] = row.name
                if (not row.unlisted or saved.ids[row.id]) and named_recast(row.name) then entries[#entries + 1], seen[row.id] = row, true end
            end
        end
        for _, row in ipairs(live_view and live_view.rows or {}) do
            if row.domain == 'recast' and row.effect and not seen[row.effect] and named_recast(row.name) and (not kind or row.kind == kind) then
                entries[#entries + 1] = { id = row.effect, name = row.name, kind = row.kind, group = row.group }
                seen[row.effect] = true
            end
        end
        table.sort(entries, window.by_name)
        for _, row in ipairs(entries) do names[row.id] = row.name end
        recast_catalog_cache[kind or 'all'] = { source = available, version = version, signature = recast_view_signature, saved = saved.key, entries = entries, names = names }
        return entries, names
    end
    if not catalog_cache then
        local ok, data = pcall(require, 'core.catalog')
        catalog_cache = ok and data.list() or {}
        for _, row in ipairs(catalog_cache) do catalog_seen[row.id] = true end
        catalog_changes = catalog_changes + 1
    end
    local added = false
    for _, row in ipairs(live_view and live_view.rows or {}) do
        if row.domain ~= 'recast' and row.effect and not catalog_seen[row.effect] then
            catalog_cache[#catalog_cache + 1] = { id = row.effect, name = row.name, group = row.group }
            catalog_seen[row.effect], added = true, true
        end
    end
    -- Only a change can bring in one the list lacks, so this walks the settings once a change, not every frame.
    local revision = callbacks and callbacks.settings_revision and callbacks.settings_revision() or draw_frame
    if saved_revision ~= revision then
        saved_revision = revision
        local source = require('core.catalog')
        saved_effects(function(id)
            if id and id > 0 and id <= 1023 and not catalog_seen[id] and not source.get(id).unnamed then
                catalog_cache[#catalog_cache + 1], catalog_seen[id], added = source.get(id), true, true
            end
        end)
    end
    if added then
        table.sort(catalog_cache, window.by_name)
        catalog_changes = catalog_changes + 1
    end
    return catalog_cache
end

-- What the finders and live lists compare, so they needn't walk the status catalog each frame to see if it changed.
local function catalog_revision()
    local renamed = require('core.catalog').revision()
    if renamed ~= catalog_renamed then catalog_renamed, catalog_changes = renamed, catalog_changes + 1 end
    return catalog_changes
end

local function effect_name(id, domain)
    if id == 0 then return domain == 'recast' and 'All recasts' or 'All effects' end
    domain = domain or (id >= 10000 and 'recast' or 'status')
    if domain == 'recast' then
        local _, names = catalog(domain)
        return names[id] or ('Recast ' .. tostring(id))
    end
    for _, row in ipairs(catalog(domain)) do if row.id == id then return row.name end end
    return require('core.catalog').get(id).name
end

-- The draw each picker's list was last open in. One find box serves them all, as one list is open at a time, and a list
-- that opens starts with it empty.
local picker_open = {}

-- shown, when given, is what the closed picker reads instead of the selected effect's name.
local function effect_picker(label, selected, setter, all, domain, shown)
    row_label(label)
    imgui.SetNextItemWidth(-1)
    skin.prepare_menu(imgui, menu_look)
    if imgui.BeginCombo('##' .. label, shown or effect_name(selected, domain)) then
        if picker_open[label] ~= draw_frame - 1 then effect_search[1] = '' end
        picker_open[label] = draw_frame
        skin.menu(imgui, menu_look, 'popup')
        imgui.SetNextItemWidth(-1)
        imgui.InputTextWithHint('##effect_search_' .. label, 'Find an effect by name', effect_search, 81)
        local query = effect_search[1]:lower()
        if all and imgui.Selectable((domain == 'recast' and 'All recasts' or 'All effects') .. '##all', selected == 0) then setter(0) end
        -- The choices scroll in a child window of the list, and ImGui doesn't close the list for a pick made in one.
        if imgui.BeginChild('##effect_choices_' .. label, { 0, 250 }, 0) then
            for _, row in ipairs(catalog(domain)) do
                if query == '' or row.name:lower():find(query, 1, true) or tostring(row.id) == query then
                    if imgui.Selectable(row.name .. '##effect_' .. row.id, selected == row.id) then
                        setter(row.id)
                        imgui.CloseCurrentPopup()
                    end
                end
            end
        end
        imgui.EndChild()
        imgui.EndCombo()
    end
end

-- What the Help page's buttons do, made once.
local function export_report() call('export_report') end
local function copy_shown() call('copy_shown', frame.panel(settings), false) end
local function copy_details() call('copy_shown', frame.panel(settings), true) end

local function show_help()
    button('Export report', export_report, 'Reports include current observations, available client data and a bounded recent event history. They do not send messages or upload files.')
    imgui.SameLine(); button('Copy shown timers', copy_shown)
    imgui.SameLine(); button('Copy timer details', copy_details)
    check('Record recent events', settings.diagnostics, 'record', 'Keeps a bounded recent history for local troubleshooting.')
    if section('Getting started', nil, true) then
        imgui.TextWrapped('Start on the main page. Tick what you want under What to show, and Edit opens that display. How it looks sets the skin, font and size, and More look holds the rest. Moving unlocks the displays. Hidden everywhere holds the effects hidden on every display, and each timer and recast panel has its own Filters tab.')
    end
    if section('Reading a timer') then
        imgui.TextWrapped('A countdown shows the time left and nothing else. An effect with no known time keeps its icon and shows no countdown. Level Sync shows only its icon. Point at an effect to see where its time came from and how sure Vantage is.')
        imgui.Spacing()
        imgui.TextWrapped('Sometimes the game gives only the time left, not the full length. Then the details say what time the bar covers, and percent alerts can\'t run for that effect.')
    end
    if section('What can be tracked') then
        imgui.TextWrapped('Your own buffs and debuffs are the surest, as the game sends the full list. Party icons show that an effect is there, but not how long it has left. Effects on your target and watched enemies come from what your client sees land and wear off, so a missed message, another player\'s gear or a resist can leave the time or the effect itself unsure.')
        imgui.Spacing()
        imgui.TextWrapped('The game sends an action only to players within 30 yalms of whoever acts, so a party ability or roll farther off is not seen. A wear-off message goes only to its caster, so debuffs others put on a mob run on an estimate.')
        imgui.Spacing()
        imgui.TextWrapped('Recasts: with Icons show set to The effect it gives, a spell or ability that gives a buff or debuff shows that status icon. Other recasts, and every recast with The spell or ability, use the client\'s spell, ability and item pictures. Shared ability timers can stand for several actions. Item recasts cover equipped enchanted items the client has shown, not consumables or items in other bags. A timer the client does not show has no countdown.')
        imgui.Spacing()
        imgui.TextWrapped('Party cooldowns: each time is estimated from the ability\'s base recast. Merits can make some of them end sooner, and Vantage can\'t see a member\'s merits. Pets\' moves are not counted.')
        imgui.Spacing()
        imgui.TextWrapped('Phantom Roll: it shows only what the game sent. A roll reaches party members within 8 yalms of the Corsair, 16 with Luzaf\'s Ring. Another Corsair\'s Double-Up time is estimated from their roll. A job bonus is added only for a job Vantage sees in the party; gear can also add it at random.')
        imgui.Spacing()
        imgui.TextWrapped('Pet: the game sends no list of a pet\'s effects, so these are the ones Vantage saw land on it, and most of their times are estimates. MP shows once the game gives the pet some. A charm\'s time is estimated from Phoenix\'s formula: your CHR, your level, the mob\'s level from a /check before the charm, and charm time gear. Ready isn\'t in this era, so Sic shows on its own.')
    end
    if section('Alerts') then
        imgui.TextWrapped('An alert fires when something changes or crosses a threshold. Old warnings don\'t replay after a reload, death or zone change. An estimate reaching zero never counts as the effect wearing off. A rule plays a sound only if you pick one, and warnings that fire together are limited so they don\'t pile up.')
    end
    if section('Move and customize') then
        imgui.TextWrapped('Unlock a panel, party list group or notice, then hold Shift and left-drag inside to move it. Shift + left-drag any edge or corner to resize; a group beside the game\'s party list only moves. This window moves and resizes the same way, and keeps its normal corner grip. With Hold Shift to see through this window on, drag the title bar to move it; the rest of the window stays see-through. With Grid mode on, a display you ticked for it snaps to the grid and the lines around it as you move it, and a resize snaps the edge you pull, as Grid and snapping under Moving on the main page sets. The line it snapped to shows while you drag, and the grid too while Show the grid is on. Every other display goes exactly where you drag it. A group\'s panel of its own moved beside its game window goes back beside it when Snap back beside the game\'s list when released is on. Typing prevents Shift dragging. Use sample effects to arrange empty panels. Each panel keeps its own filters, labels and ordering.')
        imgui.TextWrapped('The party cooldown list, the ready pulse spot and the Phantom Roll and pet displays move the same way. /vg edit, or Edit mode on the main page, outlines every display at once: pick one, then hold Shift and drag it or nudge it with the arrow keys. Size and place in the bar opens that tab, where you can type its spot or pick what it moves with.')
        imgui.TextWrapped('No boxes or headings under More look hides outer panel headings, backgrounds, borders, and empty messages while keeping your timers, icons, and fields. Use /vg minimal to toggle it, or /vg minimal on or off. Turning it off restores your previous appearance choices. The Frameless skin turns it on, and any other skin turns it off.')
        imgui.TextWrapped('On the main page, choose Original FFXI or XI View as the Skin, with all eight client window skins under Window frame in More look. Skin reaches this window too. Font is one choice for every display and this window; if this window can\'t use it, it uses its plain font and a line under Font says so. Icon and gauge choices are in More look, and missing assets are reported there. Classic FFXI is colors only.')
    end
    if section('Files and behavior') then
        imgui.TextWrapped('Vantage only reads what the game client has and the packets it receives. It never sends anything, casts spells, uses items or changes targets. Settings, profiles and custom sounds stay in ' .. require('core.identity').relative('') .. '. You can replace the addon folder without touching those files.')
    end
end

-- Which of the states are on, a 1 or a 0 each, in their order. It runs only while the search box has text. A state that
-- reads only the settings is read again when they change, and a live one each time. Without a revision to go by, each
-- is read each time. Before the window is first drawn there are no settings to go by, and it counts as a fresh save.
window.search_memo = { flipped = {}, on = {} }
local function states_on(states)
    window.fresh = settings or window.fresh or defaults.make()
    local memo, on = window.search_memo, window.search_memo.on
    local revision = callbacks and callbacks.settings_revision and callbacks.settings_revision()
    local again = memo.on_settings ~= window.fresh or revision == nil or memo.on_revision ~= revision
    memo.on_settings, memo.on_revision = window.fresh, revision
    for number, state in ipairs(states) do
        if again or state.live then on[number] = state.on(window.fresh, live_view, callbacks) and '1' or '0' end
    end
    return table.concat(on)
end

local no_results = {}
function window.search(query)
    query = (query or ''):lower()
    -- The index loads with the first key typed. An empty box asks nothing of it, and the next search starts over.
    if query == '' then search_cache.query = nil; return no_results end
    local index = require('ui.search_index')
    local on, where = states_on(index.states), frame.search_key(callbacks)
    if search_cache.query == query and search_cache.revision == control_revision and search_cache.on == on and search_cache.where == where then return search_cache.results end
    local out, seen = {}, {}
    search_cache = { query=query, revision=control_revision, on=on, where=where, results=out }
    for _, row in ipairs(index.entries) do
        if window.matches(query, row[1] .. ' ' .. row[2] .. ' ' .. row[3]) then
            out[#out + 1] = { tab = row[1], label = row[2], destination = row[4], panel = row[5], timers = row[6], topic = true, where = row[5] and frame.display_name(row[5]) }; seen[row[1] .. '/' .. row[2]] = true
        end
    end
    for _, page in ipairs(tabs) do
        if page == 'Display' then frame.find(query, window.matches, settings or window.fresh, callbacks, out, seen)
        else
            local labels, controls, more = index.order[page], index.controls[page], index.more_words[page] or {}
            if not labels then
                labels = {}; for label in pairs(controls) do labels[#labels + 1] = label end; table.sort(labels)
                index.order[page] = labels
            end
            local hidden = index.hidden_by[page]
            for _, label in ipairs(labels) do
                local state, text = hidden and hidden[label], controls[label] .. index.hidden_words(label, page, on)
                if window.matches(query, text) and not seen[page .. '/' .. label]
                    and (not state or on:sub(state, state) == '1') then out[#out + 1] = { tab = page, label = label, alias = more[label] and window.matches(query, more[label]) } end
            end
        end
    end
    -- What is called exactly what was typed comes first, then results named by every query word, then a row's other
    -- names; those found only by their keywords or help follow. Each keeps the order above.
    local rank = {}
    for number, result in ipairs(out) do
        local named = result.label:lower() == query and -1 or window.matches(query, result.label) and 0 or result.alias and 1 or 2
        rank[result] = named * #out + number
    end
    table.sort(out, function(a, b) return rank[a] < rank[b] end)
    return out
end

-- Goes where a search result points. A topic that names a place opens it as a link does, so it stays open once the search
-- is cleared. A row of the panel frame opens its display, its tab and its fold.
function window.open_result(result)
    if result.destination or result.tab == 'Display' and not result.place then
        return open_page(result.tab, result.timers and frame.timer_panel(result.timers == 'status') or result.panel, result.destination)
    end
    if result.place then frame.go(result, settings, window.main_helpers) end
    editor_changed(function() settings.window.tab = result.tab end)
    selected_match, scroll_match, window.opened_topic = 1, true, result.topic
    window.search_memo.pick = true
end

local function geometry_copy(rect)
    return { x = rect.x, y = rect.y, width = rect.width, height = rect.height }
end

local function same_geometry(a, b)
    return a and b and a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height
end

local function contains_point(rect, x, y)
    return x >= rect.x and y >= rect.y and x <= rect.x + rect.width and y <= rect.y + rect.height
end

local window_title_height = 24
local function title_point(rect, x, y)
    return contains_point(rect, x, y) and y <= rect.y + window_title_height
end

-- Where the open window is: its place this frame, or its saved one before it's drawn. The edit mode bar keeps clear of it.
function window.area(s)
    if not s or not s.window.open then return nil end
    return settings == s and window_bounds or s.window
end

-- Whether the last draw listed your recasts. The next refresh then reads every kind, so the list has them all.
function window.lists_recasts(s)
    return s ~= nil and s.window.open == true and recast_list_frame == draw_frame
end

function window.blocks_input(s, x, y, shift, typing)
    if not s or not s.window.open then return false end
    if resize_gesture and resize_gesture.settings == s then return true end
    local bounds = settings == s and window_bounds or s.window
    if not bounds or not contains_point(bounds, x, y) then return false end
    if not s.window.peek or not shift or typing then return true end
    -- A drag that began under the see-through window goes on over its title and edges.
    if window.peek_held then return false end
    return resize.grip(bounds, x, y) ~= nil or title_point(bounds, x, y)
end

function window.cancel_resize()
    local gesture = resize_gesture
    resize_gesture = nil
    if not gesture or gesture.settings ~= settings or gesture.window ~= settings.window or same_geometry(gesture.start, gesture.rect) then return end
    changed(function()
        for key, value in pairs(gesture.rect) do gesture.window[key] = value end
    end, true, 'Settings window layout', true)
    window_bounds, window_geometry = geometry_copy(gesture.rect), geometry_copy(gesture.window)
end

-- Above the page: a display's header, or a tool page's top line. The main page, where Back goes, has neither.
local function display_controls()
    local page = settings.window.tab
    if page == 'Display' then frame.header(imgui, settings, live_view, callbacks, window.main_helpers)
    elseif page ~= 'Home' then
        frame.top_line(imgui, window.main_helpers, page_labels[page] or page)
        imgui.Separator()
    end
end

-- What the main page draws with, made once so a frame makes none of it. look is set as the page draws.
window.main_helpers = {
    changed = changed, open_page = open_page, note = note, mark = mark, tip = tip, heading = heading, section = section,
    confirm_look = confirm_look, confirm_line = confirm_line, search = search, light = window.light, matches = window.matches, call = call, editor_changed = editor_changed,
    catalog = catalog, catalog_revision = catalog_revision, effect_name = effect_name, effect_picker = effect_picker, move = window.move, screen_edge = screen_edge,
    -- A tab of the panel frame opened, with what a search had picked on the last one gone.
    reselect = function() selected_match, scroll_match, window.search_memo.pick = 1, true, true end,
    -- A pick that waits for its confirm_line.
    ask = function(id, text, action, apply, apply_help, cancel_help)
        look_confirm = { id = id, owner = settings, action = action, text = text, apply = apply or 'Change',
            apply_help = apply_help or 'Make this change. Undo puts it back.', cancel_help = cancel_help or 'Leave every display as it is.' }
    end,
    chat_area = function() return callbacks.chat_area and callbacks.chat_area() end,
    cancel_party_gestures = function() require('ui.native_party_hud').cancel_layout_gesture() end,
    button = button, check = check, choice = choice, row_label = row_label,
    -- Takes away this line, or whichever line is showing.
    forget_note = function(line) if line == nil or message == line then message = nil end end,
    -- Apply shows what's on as samples.
    profile = { apply_starter = function(entry) return call('starter', entry.id, true) ~= false end },
}

-- What the Timer durations page draws with, made once like the main page's.
local duration_helpers = {
    changed = changed, check = check, text = text, query = query, number = number, combo = combo, choice = choice,
    button = button, section = section, catalog = catalog, catalog_revision = catalog_revision, note = note,
}
local function reset_durations() call('reset', 'durations') end

local function draw_current_page()
    local s = settings
    if s.window.tab == 'Home' then
        require('ui.main_page').draw(imgui, s, live_view, callbacks, window.main_helpers)
    elseif s.window.tab == 'Display' then frame.body(imgui, s, live_view, callbacks, window.main_helpers)
    elseif s.window.tab == 'Durations' then
        require('ui.duration_settings').draw(imgui, s, live_view, callbacks, duration_helpers)
        button('Reset this page', reset_durations, 'Puts this page back as it started. Undo brings your settings back.')
    elseif s.window.tab == 'Profiles' then require('ui.profiles_page').draw(imgui, s, live_view, callbacks, window.main_helpers)
    else show_help() end
end

-- What a frame hands ImGui and keeps for the mouse checks, filled in place. ImGui reads them during the call only, and
-- a gesture takes copies.
local limits = { min_width = 560, min_height = 400, max_width = 2400, max_height = 1800 }
local bounded, kept_bounds, kept_geometry, open = {}, {}, {}, { true }
local window_pos, window_size, smallest, largest = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }
local layout_pos, layout_size, cursor_pos = { 0, 0 }, { 0, 0 }, { 0, 0 }
local results_size, content_size, page_size = { 0, 0 }, { 0, 0 }, { 0, 0 }
local function fill(rect, x, y, width, height)
    rect.x, rect.y, rect.width, rect.height = x, y, width, height
    return rect
end
local function undo() call('undo') end
local function redo() call('redo') end

local function draw_open(s, view, cb)
    imgui, settings, live_view, callbacks = require('imgui'), s, view, cb or {}
    draw_frame = draw_frame + 1
    in_page = false
    if s.window.tab ~= 'Display' and frame_pages[s.window.tab] then open_page(s.window.tab) end
    local screen = imgui.GetIO().DisplaySize
    local shift = callbacks.shift
    if shift == nil then shift = imgui.GetIO().KeyShift == true end
    shift = shift and callbacks.focused ~= false
    local typing = (view.context or {}).chat_open or imgui.GetIO().WantTextInput == true
    local mouse_down = imgui.IsMouseDown(ImGuiMouseButton_Left or 0)
    local mx, my = imgui.GetMousePos()
    limits.screen_width, limits.screen_height = screen.x, screen.y
    if resize_gesture and resize_gesture.window == s.window and shift and not typing then
        local g = resize_gesture
        local dx, dy = mx - g.mx, my - g.my
        if g.edge == 'move' then
            g.rect = geometry_copy(g.start)
            g.rect.x, g.rect.y = math.max(0, math.min(g.start.x + dx, screen.x - g.start.width)), math.max(0, math.min(g.start.y + dy, screen.y - g.start.height))
        else
            g.active_edge = resize.active_edge(g.edge, dx, dy, g.active_edge)
            g.rect = resize.rect(g.start, g.active_edge, dx, dy, limits)
        end
    end
    if resize_gesture and (resize_gesture.window ~= s.window or not shift or typing or not mouse_down) then window.cancel_resize() end
    local width, height = math.min(s.window.width, screen.x), math.min(s.window.height, screen.y)
    local x, y = math.max(0, math.min(s.window.x, screen.x - width)), math.max(0, math.min(s.window.y, screen.y - height))
    local geometry_changed = not same_geometry(window_geometry, s.window)
    if geometry_changed then window_bounds = fill(kept_bounds, x, y, width, height) end
    local bounds = resize_gesture and resize_gesture.rect or window_bounds or { x = x, y = y, width = width, height = height }
    bounded.width = math.max(math.min(560, screen.x), math.min(bounds.width, 2400, screen.x))
    bounded.height = math.max(math.min(400, screen.y), math.min(bounds.height, 1800, screen.y))
    bounded.x, bounded.y = math.max(0, math.min(bounds.x, screen.x - bounded.width)), math.max(0, math.min(bounds.y, screen.y - bounded.height))
    local viewport_changed = not same_geometry(bounds, bounded)
    if viewport_changed then bounds = bounded end
    local edge = shift and not typing and resize.grip(bounds, mx, my) or nil
    local condition = (resize_gesture or geometry_changed or viewport_changed) and ImGuiCond_Always or ImGuiCond_Appearing
    window_pos[1], window_pos[2] = bounds.x, bounds.y
    imgui.SetNextWindowPos(window_pos, condition)
    window_size[1], window_size[2] = bounds.width, bounds.height
    imgui.SetNextWindowSize(window_size, condition)
    smallest[1], smallest[2], largest[1], largest[2] = math.min(560, screen.x), math.min(400, screen.y), math.min(2400, screen.x), math.min(1800, screen.y)
    imgui.SetNextWindowSizeConstraints(smallest, largest)
    local look = theme.window(s, callbacks.settings_revision and callbacks.settings_revision())
    local colors = theme.push(s, look)
    menu_look = look
    window.main_helpers.look = look
    fonts.push_window(look.font, look.font_size)
    window_title_height = imgui.GetFrameHeight()
    open[1] = true
    local popup = imgui.IsPopupOpen and imgui.IsPopupOpen('', ImGuiPopupFlags_AnyPopup or 0) or false
    local header = shift and not typing and title_point(bounds, mx, my)
    -- See-through with the button down, it stays so for that whole press: what's under it is being dragged. That still
    -- counts as active on the frame the button comes up, as this window draws first.
    local held = window.peek_held and mouse_down
    local capture = shift and not typing and not popup and (resize_gesture or window.peek_held or not imgui.IsAnyItemActive())
    local peeking = s.window.peek and capture and (held or not edge and not header) and not resize_gesture
    local window_open = open
    if shift and not typing then window_open = nil end
    -- The settings window never docks into another window, nor takes one in.
    local flags = require('bit').bor(ImGuiWindowFlags_NoSavedSettings or 0, ImGuiWindowFlags_NoDocking or 0)
    if callbacks.focused == false then flags = require('bit').bor(flags, ImGuiWindowFlags_NoInputs or 0) end
    if peeking then flags = require('bit').bor(flags, ImGuiWindowFlags_NoInputs or 0, ImGuiWindowFlags_NoBackground or 0, ImGuiWindowFlags_NoDecoration or ImGuiWindowFlags_NoTitleBar or 0) end
    if shift or resize_gesture then flags = require('bit').bor(flags, ImGuiWindowFlags_NoResize or 0, ImGuiWindowFlags_NoMove or 0,
        ImGuiWindowFlags_NoCollapse or 0, ImGuiWindowFlags_NoScrollbar or 0, ImGuiWindowFlags_NoScrollWithMouse or 0) end
    if not peeking then skin.prepare_menu(imgui, look) end
    if imgui.Begin('Vantage##settings', window_open, flags) and not peeking then
        skin.menu(imgui, look, 'window')
        local focused = imgui.IsWindowFocused and imgui.IsWindowFocused(ImGuiFocusedFlags_RootAndChildWindows or 0) or false
        local escape = imgui.IsKeyPressed and ImGuiKey_Escape and imgui.IsKeyPressed(ImGuiKey_Escape, false) or false
        if callbacks.focused ~= false and window.can_escape(escape_busy, imgui.IsAnyItemActive(), popup, focused, escape) then
            if not require('ui.profiles_page').cancel() then open[1] = false end
        end
        local wx, wy = imgui.GetWindowPos()
        local ww, wh = imgui.GetWindowSize()
        window_bounds = fill(kept_bounds, wx, wy, ww, wh)
        width, height = ww, wh
        edge = shift and not typing and resize.grip(window_bounds, mx, my) or nil
        local hovered = imgui.IsWindowHovered(ImGuiHoveredFlags_RootAndChildWindows or 0)
        if (edge or header) and s.window.peek and not imgui.IsWindowHovered(ImGuiHoveredFlags_AnyWindow or 0) then hovered = true end
        if capture and hovered and contains_point(window_bounds, mx, my) and imgui.IsMouseClicked(ImGuiMouseButton_Left or 0) and not resize_gesture then
            resize_gesture = { settings = s, window = s.window, start = geometry_copy(window_bounds), rect = geometry_copy(window_bounds), edge = edge or 'move', mx = mx, my = my }
        end
        if resize_gesture or shift and not typing and hovered and not popup then
            local cursor_edge = resize_gesture and resize_gesture.edge or edge
            resize.hint(imgui.GetWindowDrawList(), window_bounds, theme.u32(look.headings or s.style.title_color), cursor_edge, 'Vantage settings', look)
            if not cursor_edge or cursor_edge == 'move' then
                if imgui.SetMouseCursor and ImGuiMouseCursor_ResizeAll then imgui.SetMouseCursor(ImGuiMouseCursor_ResizeAll) end
            else resize.cursor(imgui, cursor_edge) end
        end
        if not resize_gesture and not mouse_down and not same_geometry(window_bounds, s.window) then
            local resized = ww ~= s.window.width or wh ~= s.window.height
            changed(function() s.window.x, s.window.y, s.window.width, s.window.height = wx, wy, ww, wh end, true,
                resized and 'Settings window size' or 'Settings window position', resized)
        end
        window_geometry = fill(kept_geometry, s.window.x, s.window.y, s.window.width, s.window.height)
        if capture then
            cursor_pos[1], cursor_pos[2] = imgui.GetCursorScreenPos()
            layout_pos[1], layout_pos[2], layout_size[1], layout_size[2] = wx, wy, ww, wh
            imgui.SetCursorScreenPos(layout_pos)
            imgui.InvisibleButton('##settings_shift_layout', layout_size)
            imgui.SetCursorScreenPos(cursor_pos)
            if imgui.BeginDisabled then imgui.BeginDisabled(true) end
            open[1] = true
        end
        local history = callbacks.history_status and callbacks.history_status() or { undo = 0, redo = 0 }
        if imgui.BeginDisabled then imgui.BeginDisabled((history.undo or 0) == 0) end
        button('Undo', undo, history.undo_label or 'Restore the previous settings change.')
        if imgui.EndDisabled then imgui.EndDisabled() end
        imgui.SameLine()
        if imgui.BeginDisabled then imgui.BeginDisabled((history.redo or 0) == 0) end
        button('Redo', redo, history.redo_label or 'Restore the change most recently undone.')
        if imgui.EndDisabled then imgui.EndDisabled() end
        imgui.SameLine()
        local tools_width = 0
        for _, tool in ipairs(tool_pages) do tools_width = tools_width + imgui.CalcTextSize(tool.text) + 32 end
        -- With no room for both, the box has the line and the buttons start the next.
        local beside = imgui.GetContentRegionAvail() - tools_width >= 10 * imgui.GetFontSize()
        imgui.SetNextItemWidth(beside and -tools_width or -1)
        imgui.InputTextWithHint('##find_settings', 'Find a setting', search, 81)
        for index, tool in ipairs(tool_pages) do
            if beside or index > 1 then imgui.SameLine() end
            button(tool.text, tool.open, tool.help)
        end
        if search[1] ~= previous_query then selected_match, scroll_match, previous_query = 1, true, search[1]; window.search_memo.pick = true end
        local found = window.search(search[1])
        if search[1] ~= '' then
            button('Clear search', function() search[1] = ''; selected_match = 1 end)
            if previous_matches > 0 then
                imgui.SameLine(); button('Previous match', function() selected_match = math.max(1, selected_match - 1); scroll_match = true end)
                imgui.SameLine(); button('Next match', function() selected_match = math.min(previous_matches, selected_match + 1); scroll_match = true end)
                imgui.TextUnformatted(('%d of %d matching controls on this page'):format(selected_match, previous_matches))
            end
            if #found == 0 then imgui.TextUnformatted('No matching settings. Try one word, such as alert or font.') end
            results_size[2] = math.min(8, #found) * 23 + 6
            if imgui.BeginChild('##search_results', results_size, 0) then
                for _, result in ipairs(found) do
                    if imgui.Selectable(result.label .. '  /  ' .. (result.where or page_labels[result.tab] or result.tab)) then window.open_result(result) end
                end
            end
            imgui.EndChild()
        end
        imgui.Separator()
        if message and os.clock() - message_at < 8 then
            if look[message_kind] then imgui.PushStyleColor(ImGuiCol_Text, look[message_kind]) end
            imgui.TextWrapped(message)
            if look[message_kind] then imgui.PopStyleColor() end
        end
        -- ImGui's resize corners are squares about a line of text tall at the bottom corners, and they take a click
        -- before anything under them. The page ends above them, so nothing on it sits there.
        local _, available_height = imgui.GetContentRegionAvail()
        local _, page_top = imgui.GetCursorScreenPos()
        content_size[2] = math.max(120, math.min(available_height, wy + wh - imgui.GetFontSize() - page_top))
        local content_visible = imgui.BeginChild('##settings_content', content_size, 0, ImGuiWindowFlags_NoSavedSettings or 0)
        if content_visible then
        if search_page ~= s.window.tab then selected_match, scroll_match, search_page = 1, true, s.window.tab; window.search_memo.pick = true end
        matches_this_frame, in_page = 0, true
        local _, controls_height = imgui.GetContentRegionAvail()
        local scroll_controls = controls_height < (s.window.tab == 'Display' and 6 or 4) * imgui.GetFrameHeight() + 100
        if not scroll_controls then display_controls() end
        if imgui.BeginChild('##settings_page', page_size, 0, ImGuiWindowFlags_NoSavedSettings or 0) then
            start_at_top()
            if scroll_controls then display_controls() end
            draw_current_page()
        end
        imgui.EndChild()
        previous_matches, in_page = matches_this_frame, false
        local memo = window.search_memo
        if memo.pick then
            if memo.named then selected_match, scroll_match = memo.named, true end
            memo.pick, memo.named = false, nil
        end
        selected_match = math.min(selected_match, math.max(1, previous_matches))
        -- A topic only opens its page. With nothing there to light up, the search goes, as after a link.
        if window.opened_topic and previous_matches == 0 then search[1] = '' end
        window.opened_topic = nil
        end
        imgui.EndChild()
        if capture and imgui.EndDisabled then imgui.EndDisabled() end
    end
    escape_busy = imgui.IsAnyItemActive() or (imgui.IsPopupOpen and imgui.IsPopupOpen('', ImGuiPopupFlags_AnyPopup or 0) or false)
    window.peek_held = peeking and mouse_down
    imgui.End()
    fonts.pop()
    if theme.pop then theme.pop(colors) else if colors > 0 then imgui.PopStyleColor(colors) end end
    if not open[1] then window.cancel_resize(); editor_changed(function() s.window.open = false end, true) end
    if pending and not imgui.IsMouseDown(ImGuiMouseButton_Left or 0) and not imgui.IsAnyItemActive() then
        if callbacks.save then callbacks.save() end
        pending = false
    end
end

function window.draw(s, view, cb)
    if settings and settings ~= s then
        require('ui.profiles_page').cancel()
        resize_gesture, window_bounds, window_geometry = nil, nil, nil
    end
    if not s.window.open then window.cancel_resize(); escape_busy, window.peek_held = false, false; return end
    -- A page that fails leaves what it opened to ui/imgui_scopes.lua: the error goes on to the Present, which closes
    -- every scope opened since it began.
    draw_open(s, view, cb)
end

if VANTAGE_TEST_MODE then
    -- Tests check the search index against what each page marks when it is drawn.
    window._tabs = tabs
end

return window
