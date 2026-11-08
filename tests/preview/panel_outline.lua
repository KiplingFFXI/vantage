-- Plain theme outlines on the window's edge, in real ImGui: Self buffs as compact bars and Spell recasts as Text
-- only, both on Shared, over one flat color so a pixel the panels leave alone reads as that color. PREVIEW.cfg (set
-- with --exec): look (a theme, default Phoenix), border and background (the shared Panel borders and Panel
-- backgrounds), minimal (Frameless timer panels), box (every panel's Panel box, default shared), scale (the Scale
-- slider), expanded (Self debuffs as expanded bars too).
-- On the last frame it logs 'field r g b' and 'rect <window> x y w h' for each window, from the window calls.
local imgui, defaults, hud = require('imgui'), require('ui.defaults'), require('ui.hud')
local theme = require('ui.theme')
local cfg = PREVIEW.cfg or {}
local now = 100
local settings = defaults.make()
assert(theme.apply(settings, cfg.look or 'Phoenix'), 'The theme applies')
local s = settings.style
s.border, s.background, s.minimal = cfg.border ~= false, cfg.background ~= false, cfg.minimal == true
if cfg.scale then s.scale = cfg.scale end
settings.recast_display = 'separate'
local layout = { self_buffs = { 'bars', 40, 60, 300 }, spell_recasts = { 'text', 400, 60, 260 } }
if cfg.expanded then layout.self_debuffs = { 'expanded', 720, 60, 260 } end
for id, panel in pairs(settings.panels) do
    local place = layout[id]
    panel.enabled = place ~= nil
    if place then
        panel.mode, panel.x, panel.y, panel.width, panel.auto_height = place[1], place[2], place[3], place[4], true
        panel.box = cfg.box or 'shared'
    end
end
local view = hud.sample(now)
-- The rect each window is begun with.
local pos, size, rects = nil, nil, {}
local set_pos, set_size, begin = imgui.SetNextWindowPos, imgui.SetNextWindowSize, imgui.Begin
local FIELD = 0xFF305A20
return function()
    local screen = imgui.GetIO().DisplaySize
    imgui.GetBackgroundDrawList():AddRectFilled({ 0, 0 }, { screen.x, screen.y }, FIELD)
    imgui.SetNextWindowPos = function(value, ...) pos = { value[1], value[2] }; return set_pos(value, ...) end
    imgui.SetNextWindowSize = function(value, ...) size = { value[1], value[2] }; return set_size(value, ...) end
    imgui.Begin = function(name, ...)
        rects[name] = { pos[1], pos[2], size[1], size[2] }
        return begin(name, ...)
    end
    local ok, why = pcall(function() hud.draw(view, settings, now, {}) end)
    imgui.SetNextWindowPos, imgui.SetNextWindowSize, imgui.Begin = set_pos, set_size, begin
    if not ok then error(why, 0) end
    if PREVIEW.frame == PREVIEW.last_frame then
        PREVIEW.log(string.format('field %d %d %d', FIELD % 256, math.floor(FIELD / 256) % 256, math.floor(FIELD / 65536) % 256))
        for _, name in ipairs({ '##vantage_self_buffs', '##vantage_spell_recasts', '##vantage_self_debuffs' }) do
            local rect = rects[name]
            assert(rect or name == '##vantage_self_debuffs' and not cfg.expanded, 'Drawn: ' .. name)
            if rect then PREVIEW.log(string.format('rect %s %.3f %.3f %.3f %.3f', name, rect[1], rect[2], rect[3], rect[4])) end
        end
    end
end
