-- Panel box draws one timer or recast panel's backdrop and border as its pick says, in the client art
-- of Original FFXI and in a plain theme, for bars, expanded and text-only panels. Shared follows the shared
-- switches, Frameless timer panels still hides every box and icons-only panels never draw one. A plain theme's
-- outline lies on the window's edge, so a panel that draws one, from its
-- pick or from Shared with Panel borders on, opens its window with no ImGui border size, which would clip that edge.
local defaults, hud, theme = require('ui.defaults'), require('ui.hud'), require('ui.theme')
local skin, fonts, assets = require('ui.client_skin'), require('ui.fonts'), require('ui.client_assets')
local imgui = require('imgui')
local now, view = 100, hud.sample(100)
-- The five Panel box choices.
local choices = { 'shared', 'both', 'background', 'border', 'none' }

-- The window art Original FFXI tiles, by name. Every other texture comes from the real module.
local art = {}
for _, name in ipairs({ 'newtex', 'corner', 'hfr1', 'vfr1' }) do
    art[name] = { id = 'art:' .. name, width = name == 'newtex' and 128 or 32, height = name == 'newtex' and 128 or 32 }
end
local texture = assets.texture
assets.texture = function(kind, name, window_type)
    if kind == 'window' then return art[name] end
    return texture(kind, name, window_type)
end
local texts = {}
local paint_text = fonts.paint
fonts.paint = function(gui, list, look, value, ...)
    texts[#texts + 1] = value
    return paint_text(gui, list, look, value, ...)
end
MOCK.screen = { 1600, 1000 }

local function same(a, b) return a[1] == b[1] and a[2] == b[2] end
-- The pixel ImGui puts a window's position or size on.
local function whole(value) return value < 0 and math.ceil(value) or math.floor(value) end

-- The draw calls made inside one window, and that window's rect.
local function window_calls(name)
    local pos, size, rect, inside, calls = nil, nil, nil, false, {}
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'SetNextWindowPos' then pos = MOCK.copy_vector(call[2])
        elseif call[1] == 'SetNextWindowSize' then size = MOCK.copy_vector(call[2])
        elseif call[1] == 'Begin' then
            inside = call[2] == name
            if inside then rect = { x = pos[1], y = pos[2], width = size[1], height = size[2] } end
        elseif call[1] == 'End' then inside = false
        elseif inside and call[1]:sub(1, 5) == 'draw:' then calls[#calls + 1] = MOCK.drawn[call] end
    end
    return calls, rect
end

-- What the box of that window drew: backdrop, border, and whether any plain rect was used. A window opened
-- with no border size (edge) has its backdrop and border on the whole pixels ImGui puts it on.
local function drawn_box(name, edge)
    local calls, rect = window_calls(name)
    if not rect then return nil, calls end
    local corner, finish = { rect.x, rect.y }, { rect.x + rect.width, rect.y + rect.height }
    local box_corner, box_finish = corner, finish
    if edge then
        box_corner = { whole(rect.x), whole(rect.y) }
        box_finish = { box_corner[1] + whole(rect.width), box_corner[2] + whole(rect.height) }
    end
    local found = { background = false, border = false, plain = false, art = {} }
    for _, call in ipairs(calls) do
        if call[1] == 'draw:AddImage' and type(call[2]) == 'string' and call[2]:sub(1, 4) == 'art:' then
            found.art[call[2]:sub(5)] = true
        elseif call[1] == 'draw:AddRectFilled' and same(call[2], box_corner) and same(call[3], box_finish) then
            found.background, found.plain = true, true
        elseif call[1] == 'draw:AddRect' and same(call[2], box_corner) and same(call[3], box_finish) then
            found.border, found.plain = true, true
        end
    end
    if found.art.newtex then found.background = true end
    if found.art.corner and found.art.hfr1 and found.art.vfr1 then found.border = true end
    return found, calls
end

-- The ImGui window border size that window was begun with (nil when none was pushed), and whether every style
-- push of the frame was popped once.
local function border_size(name)
    local stack, size, balanced = {}, nil, true
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'PushStyleVar' then
            stack[#stack + 1] = call[2] == ImGuiStyleVar_WindowBorderSize and call[3] or false
        elseif call[1] == 'PopStyleVar' then
            for _ = 1, call[2] or 1 do
                if #stack == 0 then balanced = false end
                stack[#stack] = nil
            end
        elseif call[1] == 'Begin' and call[2] == name then
            for index = #stack, 1, -1 do if stack[index] ~= false then size = stack[index]; break end end
        end
    end
    return size, balanced and #stack == 0
end

local settings, key
-- Whether the look took, so a case that draws the wrong look fails.
local function setup(look, id, mode)
    hud.cancel_gesture()
    settings, key = defaults.make(), id
    local applied = look == 'Original FFXI' or theme.apply(settings, look)
    settings.recast_display = 'separate'
    for other, p in pairs(settings.panels) do p.enabled = other == id end
    settings.panels[id].mode = mode
    return applied and skin.active(settings.style) == (look == 'Original FFXI')
end
local function render(edge)
    MOCK.imgui_calls, texts = {}, {}
    hud.draw(view, settings, now, {})
    return drawn_box('##vantage_' .. key, edge)
end
local function heading_drawn()
    for _, value in ipairs(texts) do if value == settings.panels[key].title then return true end end
    return false
end

local expected = {
    both = function() return true, true end,
    background = function() return true, false end,
    border = function() return false, true end,
    none = function() return false, false end,
    shared = function(s) return s.background, s.border end,
}
local panels = { { 'self_buffs', 'bars' }, { 'self_buffs', 'expanded' }, { 'spell_recasts', 'bars' }, { 'spell_recasts', 'text' } }

for _, look in ipairs({ 'Original FFXI', 'Phoenix' }) do
    for _, case in ipairs(panels) do
        local id, mode = case[1], case[2]
        assert(setup(look, id, mode), 'Fixture: ' .. look .. ' is the look being drawn.')
        local where = look .. ' ' .. id .. ' ' .. mode
        -- Every pick, with the shared switches each way.
        for _, shared in ipairs({ { true, true }, { true, false }, { false, true }, { false, false } }) do
            local s = settings.style
            s.background, s.border = shared[1], shared[2]
            for _, box in ipairs(choices) do
                settings.panels[id].box = box
                local background, border = expected[box](s)
                -- An expanded panel is a fractional height, so its box must be on its window's whole pixels.
                local found = render(look ~= 'Original FFXI' and border)
                local state = where .. ' ' .. box .. ' (shared ' .. tostring(shared[1]) .. '/' .. tostring(shared[2]) .. ')'
                assert(found and found.background == background, 'Backdrop as picked: ' .. state)
                assert(found and found.border == border, 'Border as picked: ' .. state)
                -- Original FFXI draws the box with its client art, never with a plain rect.
                assert(found and not (look == 'Original FFXI' and found.plain), 'Client art draws the box: ' .. state)
                -- Only a plain theme's outline, from the pick or from Shared with Panel borders on, gets a window
                -- without a border size; every other box keeps the window as it was.
                local size, popped = border_size('##vantage_' .. id)
                assert(type(ImGuiStyleVar_WindowBorderSize) == 'number'
                    and (size == 0) == (look ~= 'Original FFXI' and border) and (size == nil or size == 0),
                    'The window keeps its edge for a plain outline only: ' .. state)
                assert(popped, 'Every style the panel pushes is popped: ' .. state)
            end
        end
        -- None keeps the heading, which follows its own Panel heading switch.
        settings.panels[id].box = 'none'
        render()
        assert(heading_drawn(), 'None keeps the panel heading: ' .. where)
        settings.panels[id].show_heading = false
        render()
        assert(not heading_drawn(), 'Panel heading off hides it with None too: ' .. where)
        settings.panels[id].show_heading = true
        -- Frameless timer panels wins over every pick.
        settings.style.minimal = true
        for _, box in ipairs(choices) do
            settings.panels[id].box = box
            local found = render()
            assert(found and not found.background and not found.border and next(found.art) == nil,
                'Frameless timer panels hides the box: ' .. where .. ' ' .. box)
            assert(border_size('##vantage_' .. id) == nil, 'Frameless timer panels leaves the border alone: ' .. where .. ' ' .. box)
        end
        settings.style.minimal = false
    end
end

-- Icons-only panels draw no box, so every pick draws the same.
for _, look in ipairs({ 'Original FFXI', 'Phoenix' }) do
    for _, id in ipairs({ 'self_buffs', 'spell_recasts' }) do
        assert(setup(look, id, 'icons'), 'Fixture: ' .. look .. ' is the look being drawn for icons.')
        local first
        for _, box in ipairs(choices) do
            settings.panels[id].box = box
            local found, calls = render()
            local text = {}
            for index, call in ipairs(calls) do
                local parts = {}
                for at, value in ipairs(call) do parts[at] = type(value) == 'table' and table.concat(value, ',') or tostring(value) end
                text[index] = table.concat(parts, ' ')
            end
            text = table.concat(text, '\n')
            first = first or text
            assert(found and text == first and not found.background and not found.border,
                'Icons only draws no box with ' .. box .. ': ' .. look .. ' ' .. id)
            assert(border_size('##vantage_' .. id) == nil, 'Icons only leaves the border alone with ' .. box .. ': ' .. look .. ' ' .. id)
        end
    end
end

return 'Panel box draws or skips each panel box part as picked'
