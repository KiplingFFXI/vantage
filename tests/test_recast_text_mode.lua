-- Text only shows each recast as one row with its name and countdown: no icon and no bar, with the panel's
-- font, colors, sort, filters, alerts and ready-soon color. Wrapping and resizing work as in the other layouts.
local defaults, hud, theme = require('ui.defaults'), require('ui.hud'), require('ui.theme')
local imgui, fonts, countdown = require('imgui'), require('ui.fonts'), require('ui.countdown_text')
local skin, pictures = require('ui.client_skin'), require('ui.recast_icons')
local copy, equal = defaults.copy, require('core.customization').equal
local now, view = 100, hud.sample(100)

-- The existing layouts stay the defaults, every panel takes Text, and saved fields stay as chosen.
-- The status panels' rows are checked after the recast panels'.
local fresh = defaults.make()
for id in pairs(defaults.recast_panels) do assert(fresh.panels[id].mode == 'bars', 'Recast panels still start as compact bars.') end
local saved = defaults.make()
for id in pairs(defaults.recast_panels) do saved.panels[id].mode = 'text' end
saved.panels.self_buffs.mode = 'text'
saved.panels.spell_recasts.show_target = true
saved = defaults.tidy(saved)
for id in pairs(defaults.recast_panels) do assert(saved.panels[id].mode == 'text', 'Text is kept for ' .. id) end
assert(saved.panels.self_buffs.mode == 'text', 'Status panels take Text too.')
assert(saved.panels.spell_recasts.show_target, 'Tidying keeps the saved fields.')

local position, dimensions, current, cursor, item = {}, {}, {}, {}, nil
local rects, names, clocks, drawn_pictures, gauges = {}, {}, {}, 0, 0
local mx, my, down, pressed = -1, -1, false, false
imgui.SetNextWindowPos = function(v) position = v end
imgui.SetNextWindowSize = function(v) dimensions = v end
imgui.Begin = function(name)
    current = { x = position[1], y = position[2], width = dimensions[1], height = dimensions[2] }
    rects[name] = current
    return true
end
imgui.GetMousePos = function() return mx, my end
imgui.IsMouseDown = function() return down end
imgui.IsMouseClicked = function() return pressed end
imgui.SetCursorPos = function(v) cursor = { current.x + v[1], current.y + v[2] } end
imgui.InvisibleButton = function(_, size) item = { x = cursor[1], y = cursor[2], width = size[1], height = size[2] } end
imgui.IsItemHovered = function() return item and mx >= item.x and mx < item.x + item.width and my >= item.y and my < item.y + item.height end
fonts.measure = function(_, text, size) return #text * size * .5 end
fonts.draw = function(_, _, text, x, y, size) names[#names + 1] = { text = text, x = x, y = y, size = size }; return true end
fonts.is_bitmap = function() return true end
fonts.failed = function() return false end
countdown.draw = function(_, _, text, x, y, size, color) clocks[#clocks + 1] = { text = text, x = x, y = y, color = color }; return true end
local draw_picture, gauge = pictures.draw, skin.gauge
pictures.draw = function(...) drawn_pictures = drawn_pictures + 1; return draw_picture(...) end
skin.gauge = function(...) gauges = gauges + 1; return gauge(...) end
MOCK.screen = { 1600, 1000 }

local settings, panel, key
local function setup(id, mode)
    hud.cancel_gesture()
    settings, key = defaults.make(), id
    -- The sample rows carry recast tints, which have their own test (test_recast_tints.lua); here they are off.
    settings.recast_tints.mp, settings.recast_tints.spell_lock, settings.recast_tints.ability_lock = false, false, false
    settings.recast_display = id == 'recasts' and 'combined' or 'separate'
    for other, p in pairs(settings.panels) do p.enabled = other == id end
    panel = settings.panels[id]
    panel.mode = mode or 'text'
    mx, my, down, pressed, item = -1, -1, false, false, nil
end
local function render(callbacks)
    rects, names, clocks, drawn_pictures, gauges, MOCK.imgui_calls = {}, {}, {}, 0, 0, {}
    hud.draw(view, settings, now, callbacks or {})
    assert(#MOCK.font_stack == 0, 'Every panel font push is popped.')
    return rects['##vantage_' .. key]
end
local function calls(kind)
    local result = {}
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == kind then result[#result + 1] = call end end
    return result
end
local function caption(text)
    for _, entry in ipairs(names) do if entry.text == text then return entry end end
end
-- The countdown drawn on the row's own line.
local function clock_for(row)
    local text, name = hud.timer_text(row, now), caption(panel.labels[row.effect] or row.name)
    for _, entry in ipairs(clocks) do
        if entry.text == text and name and entry.y >= name.y and entry.y < name.y + settings.style.font_size then return entry end
    end
end
local function rows() return hud.filter_rows(view, panel, key, settings) end
local function shown_order()
    local list = {}
    for _, row in ipairs(rows()) do
        local entry = caption(panel.labels[row.effect] or row.name)
        if entry then list[#list + 1] = entry end
    end
    table.sort(list, function(a, b) return a.y < b.y end)
    local result = {}
    for _, entry in ipairs(list) do result[#result + 1] = entry.text end
    return table.concat(result, '|')
end

-- Every status panel: each row its name and countdown on one line, with no icon and no bar.
for _, id in ipairs({ 'self_buffs', 'self_debuffs', 'target', 'party' }) do
    setup(id)
    local rect = render()
    assert(rect and #rows() > 0, id .. ' draws in Text only')
    local timed = 0
    for _, row in ipairs(rows()) do
        assert(caption(row.name), row.name .. ' shows its name in ' .. id)
        if hud.timer_text(row, now) ~= '' then timed = timed + 1 end
    end
    assert(timed > 0 and #clocks == timed, 'One countdown for each row with a time in ' .. id)
    -- Two rows can share a name, so each countdown goes by the name on its own line.
    for _, clock in ipairs(clocks) do
        local beside = false
        for _, entry in ipairs(names) do
            beside = beside or clock.x > entry.x and clock.y >= entry.y and clock.y < entry.y + settings.style.font_size
        end
        assert(beside, clock.text .. ' is on the line of a name in ' .. id)
    end
    assert(#calls('draw:AddImage') == 0 and drawn_pictures == 0 and gauges == 0, 'Text only draws no icon and no bar in ' .. id)
end

-- Every recast panel and the combined panel: name and countdown on one line, nothing else in the row.
for _, id in ipairs({ 'spell_recasts', 'ability_recasts', 'item_recasts', 'recasts' }) do
    setup(id)
    panel.show_name, panel.show_time = false, false
    panel.show_target, panel.show_source, panel.show_total, panel.show_elapsed = true, true, true, true
    local before = copy(panel)
    local rect = render()
    assert(rect and #rows() > 0, id .. ' draws in Text only')
    for _, row in ipairs(rows()) do
        local name, clock = caption(row.name), clock_for(row)
        assert(name and clock and clock.x > name.x, row.name .. ' shows its name and its countdown on one line in ' .. id)
    end
    local allowed = { [panel.title] = true, [tostring(#rows())] = true }
    for _, row in ipairs(rows()) do allowed[row.name] = true end
    for _, entry in ipairs(names) do assert(allowed[entry.text], 'Text only shows only names and countdowns, not ' .. entry.text) end
    assert(#clocks == #rows(), 'One countdown per recast in ' .. id)
    assert(#calls('draw:AddImage') == 0 and drawn_pictures == 0, 'Text only draws no icon in ' .. id)
    assert(not caption('?'), 'Text only draws no missing-picture box in ' .. id)
    local fills = calls('draw:AddRectFilled')
    assert(gauges == 0 and #fills == 1 and fills[1][2][1] == rect.x and fills[1][2][2] == rect.y,
        'Text only draws no bar, only the panel background, in ' .. id)
    assert(equal(panel, before), 'Drawing Text only leaves the saved panel settings untouched in ' .. id)
    local copied = hud.copy_text(view, settings, id, false, now)
    assert(copied:find(rows()[1].name, 1, true) and not copied:find('Total', 1, true), 'Copy shown follows Text only.')
    -- The bar layouts come back as they were.
    panel.mode = 'bars'
    render()
    assert(drawn_pictures > 0 and gauges > 0, 'Switching back to bars shows icons and bars again in ' .. id)
end

-- Sorting, labels and filters work as in the other layouts.
setup('recasts')
render()
assert(shown_order() == 'Haste|Cure IV|Provoke|Empress Band', 'Ready soonest sorts the text rows.')
panel.sort = 'name'; render()
assert(shown_order() == 'Cure IV|Empress Band|Haste|Provoke', 'Name sorts the text rows.')
panel.sort, panel.order = 'fixed', { 45762, 20005, 10057, 10004 }; render()
assert(shown_order() == 'Empress Band|Provoke|Haste|Cure IV', 'My order sorts the text rows.')
panel.sort, panel.labels[10057] = 'remaining', 'My Haste'; render()
assert(caption('My Haste') and not caption('Haste'), 'Custom labels name the text rows.')
panel.labels[10057], panel.filter = nil, 'haste'; render()
assert(caption('Haste') and not caption('Cure IV') and #clocks == 1, 'Text filters apply.')
panel.filter, panel.exclude = '', { 10057 }; render()
assert(not caption('Haste') and caption('Cure IV'), 'Excluded recasts stay hidden.')
panel.exclude, panel.recast_categories.ability = {}, false; render()
assert(not caption('Provoke') and caption('Empress Band'), 'The combined panel keeps its categories.')
panel.recast_categories.ability = true

-- Alerts and the ready-soon color.
local haste
for _, row in ipairs(rows()) do if row.effect == 10057 then haste = row end end
render()
local warning = theme.u32(settings.style.warning_color)
assert(clock_for(haste).color == warning, 'A recast ready soon uses the warning color.')
for _, row in ipairs(rows()) do
    if row ~= haste then assert(clock_for(row).color ~= warning, 'Recasts not ready soon keep their color.') end
end
panel.warning_enabled = false; render()
assert(clock_for(haste).color ~= warning, 'Turning the ready-soon color off applies to text rows.')
panel.warning_enabled = true
local outlines = #calls('draw:AddRect')
view.emphasis = { [haste.key] = true }
render()
local boxes = calls('draw:AddRect')
local name = caption('Haste')
local marked = false
for _, box in ipairs(boxes) do
    if box[4] == warning and box[2][2] <= name.y and box[3][2] >= name.y + settings.style.font_size then marked = true end
end
assert(#boxes == outlines + 1 and marked, 'An alert emphasis marks the text row.')
view.emphasis = nil

-- Rows size to their text, not to the bar height, and the row settings still apply.
local function spacing()
    local list = {}
    for _, row in ipairs(rows()) do list[#list + 1] = caption(row.name).y end
    table.sort(list)
    local gaps = {}
    for index = 2, #list do gaps[#gaps + 1] = list[index] - list[index - 1] end
    for index = 2, #gaps do assert(math.abs(gaps[index] - gaps[1]) < 1e-6, 'Text rows are evenly spaced.') end
    return gaps[1]
end
setup('recasts', 'bars')
settings.style.bar_height = 40
local bars = render()
local bar_gap = spacing()
panel.mode = 'text'
local text_rect = render()
local text_gap = spacing()
assert(bar_gap >= 40 and text_gap < 40 and text_gap >= settings.style.font_size, 'Text rows are not padded to the bar height.')
assert(text_rect.height < bars.height, 'A text panel is shorter than the same bars panel.')
panel.recast_categories.item = false
local three = render()
assert(math.abs(text_rect.height - three.height - text_gap) < 1e-6, 'Automatic height grows by one text row per recast.')
panel.recast_categories.item = true
panel.row_height = 50; render()
assert(math.abs(spacing() - (50 + settings.style.gap)) < 1e-6, 'Panel row height applies to text rows.')
panel.row_height, panel.auto_height, panel.height_limit = 0, false, 300
assert(render().height == 300, 'A fixed height applies to a text panel.')

-- Wrapping and resizing: an unlocked panel resizes with Shift. The lock and Shift checks don't depend on the
-- layout; test_combined_recasts.lua covers them.
local saves, edits, callbacks
local function begin(id)
    setup(id)
    panel.locked, panel.x, panel.y, panel.width, panel.auto_width = false, 200, 180, 420, false
    panel.labels[10057] = 'A long readable spell name with several words'
    saves, edits = 0, 0
    callbacks = { shift = true, save = function() saves = saves + 1 end, changed = function(stage) if stage == 'after' then edits = edits + 1 end end }
    return render(callbacks)
end
local function drag(rect, dx)
    mx, my = rect.x + rect.width - 1, rect.y + rect.height / 2
    down, pressed = true, true; render(callbacks); pressed = false
    mx = mx + dx; render(callbacks)
    down = false; return render(callbacks)
end
for _, id in ipairs({ 'spell_recasts', 'recasts' }) do
    local wide = begin(id)
    assert(caption('A long readable spell name with several words'), 'The long name fits on one line at full width.')
    local narrow = drag(wide, -230)
    assert(panel.wrap and panel.width == 190 and narrow.width == 190 and saves == 1 and edits > 0, 'Shift dragging resizes the text panel once.')
    assert(narrow.height > wide.height and not caption('A long readable spell name with several words'),
        'A narrow text panel wraps long names onto more lines.')
    local words = {}
    for _, entry in ipairs(names) do words[#words + 1] = entry.text end
    local joined = table.concat(words, ' ')
    assert(joined:find('readable', 1, true) and joined:find('several', 1, true) and joined:find('words', 1, true), 'Wrapped names keep their words.')
end
hud.cancel_gesture()
mx, my, down, pressed = -1, -1, false, false

-- An empty text panel hides, or shows its empty message when asked to.
setup('recasts')
panel.filter = 'nothing matches this'
assert(not render(), 'An empty text panel hides by default.')
panel.empty = 'show'
local empty = render()
assert(empty and caption('No matching effects') and #clocks == 0 and drawn_pictures == 0, 'A kept empty text panel shows its empty message.')

-- The Layout choice offers Text on every panel.
local window, panels = require('ui.settings_window'), require('ui.panel_frame')
local editor = defaults.make()
editor.window.open, editor.window.tab, editor.recast_display = true, 'Display', 'combined'
local choices, selectable = {}, imgui.Selectable
imgui.BeginCombo = function(label) return label == '##frame_Layout' end
imgui.Selectable = function(label, ...) choices[label] = true; return selectable(label, ...) end
local window_callbacks = { changed = function() end, save = function() return true end, now = function() return now end }
for _, id in ipairs({ 'recasts', 'self_buffs' }) do
    panels.open(id, 'show')
    choices = {}
    local p = editor.panels[id]
    local kept = copy(p)
    MOCK.clicks['Text##text'] = true
    window.draw(editor, hud.sample(now), window_callbacks)
    assert(choices['Bars##bars'] and choices['Icons##icons'], 'Layout keeps the existing choices on ' .. id)
    kept.mode = 'text'
    assert(choices['Text##text'] and equal(p, kept), 'Choosing Text keeps every other choice of the panel: ' .. id)
end
imgui.Selectable = selectable
