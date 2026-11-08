-- Help says what the recast panels draw: the coverage note names the choices of Icons show, and on Text the Row text list
-- shows the name and countdown it always draws, without a tick that does nothing.
local imgui = require('imgui')
local defaults, hud = require('ui.defaults'), require('ui.hud')
local window, panels = require('ui.settings_window'), require('ui.panel_frame')
local recast_icons = require('ui.recast_icons')
local copy, equal = defaults.copy, require('core.customization').equal
MOCK.screen = { 1600, 900 }
local now = 100
local callbacks = { changed = function() end, save = function() return true end, now = function() return now end }
local function draw(editor, panel, tab)
    panels.open(panel, tab)
    MOCK.imgui_calls = {}
    window.draw(editor, hud.sample(now), callbacks)
    assert(#MOCK.font_stack == 0, 'The settings window balances fonts.')
    local out = {}
    for _, call in ipairs(MOCK.imgui_calls) do
        out[call[1]] = out[call[1]] or {}
        if type(call[2]) == 'string' then table.insert(out[call[1]], call[2]) end
    end
    return out
end
local function has(list, text) for _, value in ipairs(list or {}) do if value:find(text, 1, true) then return value end end end
local function editor_for(display)
    local editor = defaults.make()
    editor.window.open, editor.window.tab = true, 'Display'
    editor.recast_display = display
    return editor, display == 'combined' and 'recasts' or 'spell_recasts'
end

-- The coverage note names both choices of Icons show, as the Show tab labels them.
local open
imgui.BeginCombo = function(label) return label == open end
for _, display in ipairs({ 'separate', 'combined' }) do
    local editor, panel = editor_for(display)
    assert(recast_icons.status_art(editor.style) ~= nil, 'Fixture: fresh recasts draw buff and debuff icons.')
    open = '##frame_Icons show'
    local shown = draw(editor, panel, 'show')
    open = nil
    local effect = has(shown.Selectable, '##effect'):match('^(.-)##')
    local action = has(shown.Selectable, '##action'):match('^(.-)##')
    assert(effect == 'The effect it gives' and action == 'The spell or ability', 'Fixture: the recast icon choices.')
    editor.window.tab = 'Help'
    local note = has(draw(editor, panel, 'show').TextWrapped, 'Item recasts cover')
    assert(note, 'Help shows the recast coverage note: ' .. display)
    assert(note:find(effect, 1, true) and note:find(action, 1, true),
        'The coverage note says which recasts show buff and debuff icons and which keep action pictures: ' .. display)
    assert(note:find('Icons show', 1, true), 'The coverage note names the setting it depends on: ' .. display)
end

-- Text: Row text lists the name and countdown as shown and the other parts as hidden, whatever the bar layouts saved, and has
-- no Show tick. The saved choices stay as they were.
local fields = { name = 'Name', target = 'Who it is on', source = 'Who cast it', elapsed = 'Time elapsed', total = 'Full length', time = 'Countdown' }
for _, display in ipairs({ 'separate', 'combined' }) do
    local editor, panel = editor_for(display)
    local p = editor.panels[panel]
    -- A recast panel never lists who it is on or who cast it, whatever is saved.
    p.mode, p.show_name, p.show_target, p.show_source, p.show_elapsed, p.show_time = 'text', false, true, false, true, true
    local saved = copy(p)
    local shown = draw(editor, panel, 'look')
    for key, name in pairs(fields) do
        local plain, hidden = false, false
        for _, label in ipairs(shown.Selectable or {}) do
            if label == name then plain = true end
            if label == name .. ' (hidden)' then hidden = true end
        end
        local visible = key == 'name' or key == 'time'
        if key == 'target' or key == 'source' then
            assert(not plain and not hidden, ('A recast panel does not list %s: %s'):format(name, display))
        else
            assert(plain == visible and hidden == not visible, ('Text lists %s as %s: %s'):format(name, visible and 'shown' or 'hidden', display))
        end
    end
    assert(has(shown.TextWrapped, 'Text always shows the name and countdown'), 'The editor says why parts cannot be shown or hidden: ' .. display)
    for _, choice in ipairs({ 'Time elapsed (hidden)', 'Name' }) do
        MOCK.clicks = { [choice] = true }
        shown = draw(editor, panel, 'look')
        assert(not MOCK.clicks[choice], 'Fixture: the part was chosen: ' .. choice)
        shown = draw(editor, panel, 'look')
        assert(has(shown.Checkbox, 'Start a new line'), 'Fixture: the chosen part is open: ' .. choice)
        assert(not has(shown.Checkbox, 'Show##frame_part'), 'Text has no Show tick: ' .. choice .. ' ' .. display)
    end
    assert(equal(p, saved), 'The editor leaves the saved fields as they were: ' .. display)

    -- The bar layouts keep the tick and list the saved parts.
    p.mode = 'bars'
    MOCK.clicks = { ['Time elapsed'] = true }
    draw(editor, panel, 'look')
    shown = draw(editor, panel, 'look')
    assert(has(shown.Selectable, 'Name (hidden)') and not has(shown.Selectable, 'Time elapsed (hidden)'), 'Bar layouts list the saved parts: ' .. display)
    assert(has(shown.Checkbox, 'Show##frame_part'), 'Bar layouts keep the Show tick: ' .. display)
    MOCK.clicks = { ['Show##frame_part'] = true }
    draw(editor, panel, 'look')
    assert(p.show_elapsed == false, 'The Show tick still works in the bar layouts: ' .. display)
    assert(p.show_target == true, 'The saved part stays as it was: ' .. display)
    shown = draw(editor, panel, 'look')
    local listed = false
    for _, label in ipairs(shown.Selectable or {}) do listed = listed or label == 'Who it is on' or label == 'Who it is on (hidden)' end
    assert(not listed, 'Saved on, a recast panel still lists no Who it is on: ' .. display)
end
return 'The coverage note on Help and the Row text list match what the recast panels draw'
