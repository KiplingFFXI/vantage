-- A plain theme draws a panel's outline on its window's edge, which ImGui clips by the window border size. So in
-- every plain theme a bar, expanded or text-only panel that draws an outline, from Shared with Panel borders on or
-- from its own pick, opens its window with no border size, and every other panel leaves the border size alone: no
-- outline drawn (Panel borders off, Background only, None), the Original FFXI and XI View art, icons-only panels and
-- Frameless timer panels. ImGui puts a window on whole pixels, cutting its position and size toward zero, so a box
-- opened with no border size is drawn on those pixels, at any size and place; every other box is drawn where it was.
local defaults, hud, appearance = require('ui.defaults'), require('ui.hud'), require('ui.appearance')
local skin, assets = require('ui.client_skin'), require('ui.client_assets')
local imgui = require('imgui')
local now, view = 100, hud.sample(100)
MOCK.screen = { 1600, 1000 }

-- The window art the client looks tile, by name, so they draw it here as in the game.
local art = {}
for _, name in ipairs({ 'newtex', 'corner', 'hfr1', 'vfr1' }) do
    art[name] = { id = 'art:' .. name, width = name == 'newtex' and 128 or 32, height = name == 'newtex' and 128 or 32 }
end
local texture = assets.texture
assets.texture = function(kind, name, window_type)
    if kind == 'window' then return art[name] end
    return texture(kind, name, window_type)
end

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
-- Whether that window drew a plain outline on its edge, and any client frame art. Also where the outline and the
-- plain backdrop went: on the whole pixels ImGui puts the window on (snapped) or on the rect it was given (given).
-- They are the same rect when the window is on whole pixels.
local function outline(name)
    local calls, rect = window_calls(name)
    if not rect then return nil end
    local x0, y0 = whole(rect.x), whole(rect.y)
    local cut = { { x0, y0 }, { x0 + whole(rect.width), y0 + whole(rect.height) } }
    local given = { { rect.x, rect.y }, { rect.x + rect.width, rect.y + rect.height } }
    local frame = false
    local found = { snapped = false, given = false, filled_snapped = false, filled_given = false }
    for _, call in ipairs(calls) do
        local kind = call[1] == 'draw:AddRect' and (call[7] or 1) == 1 and '' or call[1] == 'draw:AddRectFilled' and 'filled_'
        if kind then
            if same(call[2], cut[1]) and same(call[3], cut[2]) then found[kind .. 'snapped'] = true end
            if same(call[2], given[1]) and same(call[3], given[2]) then found[kind .. 'given'] = true end
        end
        if call[1] == 'draw:AddImage' and call[2] == 'art:hfr1' then frame = true end
    end
    return found.snapped or found.given, frame, found
end
-- The window border size the window was begun with (nil when none was pushed), and whether every push was popped.
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

-- What a pick draws as the outline and as the backdrop, from the shared Panel borders and Panel backgrounds for Shared.
local borders = { shared = nil, both = true, background = false, border = true, none = false }
local backgrounds = { shared = nil, both = true, background = true, border = false, none = false }
local panels = { { 'self_buffs', 'bars' }, { 'self_buffs', 'expanded' }, { 'self_buffs', 'icons' }, { 'spell_recasts', 'bars' },
    { 'spell_recasts', 'text' }, { 'spell_recasts', 'icons' } }
-- Every look, and Frameless timer panels over a plain theme and over the client art.
local looks = {}
for _, name in ipairs(appearance.names) do looks[#looks + 1] = { name, false } end
looks[#looks + 1] = { 'Phoenix', true }
looks[#looks + 1] = { 'Original FFXI', true }

local counts = { plain = 0, client = 0, shared_on = 0, shared_off = 0, icons = 0, frameless = 0 }
for _, look in ipairs(looks) do
    for _, case in ipairs(panels) do
        local id, mode = case[1], case[2]
        hud.cancel_gesture()
        local settings = defaults.make()
        assert(appearance.apply(settings, look[1], { matching = true }), 'Fixture: the look applies: ' .. look[1])
        settings.recast_display = 'separate'
        for other, p in pairs(settings.panels) do p.enabled = other == id end
        settings.panels[id].mode = mode
        local s = settings.style
        if look[2] then s.minimal = true end
        local client, frameless = skin.active(s), s.minimal == true
        assert(client == (look[1] == 'Original FFXI' or look[1] == 'XI View'), 'Fixture: only the client looks draw client art: ' .. look[1])
        for _, shared in ipairs({ true, false }) do
            for _, backdrop in ipairs({ true, false }) do
                s.border, s.background = shared, backdrop
                for _, box in ipairs(defaults.panel_boxes) do
                    settings.panels[id].box = box
                    MOCK.imgui_calls = {}
                    hud.draw(view, settings, now, {})
                    local name = '##vantage_' .. id
                    local wanted = borders[box]
                    if box == 'shared' then wanted = shared end
                    -- The panel draws a plain outline exactly when its box has a border in a plain theme.
                    local expected = wanted and not client and not frameless and mode ~= 'icons'
                    local state = look[1] .. (look[2] and ' frameless' or '') .. ' ' .. id .. ' ' .. mode .. ' ' .. box
                        .. ' (borders ' .. tostring(shared) .. ', backgrounds ' .. tostring(backdrop) .. ')'
                    local plain, frame, where = outline(name)
                    local size, popped = border_size(name)
                    assert(plain ~= nil, 'Fixture: the panel is drawn: ' .. state)
                    assert(plain == expected, 'The panel draws a plain outline only when it has one in a plain theme: ' .. state)
                    -- An expanded panel is a fractional height here, so this tells the two rects apart.
                    assert(not expected or where.snapped, 'A plain outline lies on the whole pixels ImGui puts its window on: ' .. state)
                    local fill = backgrounds[box]
                    if box == 'shared' then fill = backdrop end
                    fill = fill and not client and not frameless and mode ~= 'icons'
                    assert((where.filled_snapped or where.filled_given) == fill
                        and (not fill or expected and where.filled_snapped or not expected and where.filled_given),
                        'The plain backdrop is drawn as picked, on the outline\'s pixels with an outline and where it was without: ' .. state)
                    assert(frame == (wanted and client and not frameless and mode ~= 'icons'), 'The client art frame shows as it should: ' .. state)
                    assert(type(ImGuiStyleVar_WindowBorderSize) == 'number' and (size == 0) == expected and (size == nil or size == 0),
                        'The window has no border size exactly when a plain outline lies on its edge: ' .. state)
                    assert(popped, 'Every style the panel pushes is popped: ' .. state)
                    if expected then counts.plain = counts.plain + 1 else counts.client = counts.client + (client and 1 or 0) end
                    if box == 'shared' and not client and not frameless and mode ~= 'icons' then
                        if shared then counts.shared_on = counts.shared_on + 1 else counts.shared_off = counts.shared_off + 1 end
                    end
                    if mode == 'icons' then counts.icons = counts.icons + 1 end
                    if frameless then counts.frameless = counts.frameless + 1 end
                end
            end
        end
    end
end
assert(counts.plain > 0 and counts.client > 0 and counts.shared_on > 0 and counts.shared_off > 0 and counts.icons > 0 and counts.frameless > 0,
    'Fixture: every kind of case ran.')

-- Off whole pixels: the panel placed at 30.5, 40.75 with the Scale slider at 1.5. Its window is still opened where the
-- layout puts it, and its box goes on the window's whole pixels when the window has no border size and where it was
-- otherwise; the two rects differ, so the box is on exactly one of them.
local fractional = { { 'Phoenix', false }, { 'High contrast', false }, { 'Ember', false }, { 'Original FFXI', false }, { 'XI View', false },
    { 'Phoenix', true } }
for _, look in ipairs(fractional) do
    for _, case in ipairs(panels) do
        local id, mode = case[1], case[2]
        hud.cancel_gesture()
        local settings = defaults.make()
        assert(appearance.apply(settings, look[1], { matching = true }), 'Fixture: the look applies off whole pixels: ' .. look[1])
        settings.recast_display = 'separate'
        for other, p in pairs(settings.panels) do p.enabled = other == id end
        local p, s = settings.panels[id], settings.style
        p.mode, p.x, p.y, s.scale = mode, 30.5, 40.75, 1.5
        if look[2] then s.minimal = true end
        local client, frameless = skin.active(s), s.minimal == true
        for _, box in ipairs(defaults.panel_boxes) do
            for _, shared in ipairs({ true, false }) do
                s.border, s.background, p.box = shared, true, box
                MOCK.imgui_calls = {}
                hud.draw(view, settings, now, {})
                local name = '##vantage_' .. id
                local _, rect = window_calls(name)
                local wanted, fill = borders[box], backgrounds[box]
                if box == 'shared' then wanted, fill = shared, true end
                local expected = wanted and not client and not frameless and mode ~= 'icons'
                fill = fill and not client and not frameless and mode ~= 'icons'
                local plain, frame, where = outline(name)
                local state = look[1] .. (look[2] and ' frameless' or '') .. ' ' .. id .. ' ' .. mode .. ' ' .. box .. ' (borders ' .. tostring(shared) .. ')'
                assert(rect and rect.x == 30.5 and rect.y == 40.75, 'Fixture: the window is opened where the panel was placed: ' .. state)
                assert(plain == expected and (not expected or where.snapped and not where.given),
                    'Off whole pixels a plain outline lies on its window\'s whole pixels only: ' .. state)
                assert(not fill or expected and where.filled_snapped and not where.filled_given or not expected and where.filled_given and not where.filled_snapped,
                    'Off whole pixels the backdrop sits on the outline\'s pixels with an outline and where it was without: ' .. state)
                assert(frame == (wanted and client and not frameless and mode ~= 'icons'), 'Off whole pixels the client art frame shows as it should: ' .. state)
            end
        end
    end
end

return 'A plain theme panel that draws an outline opens its window with no border size'
