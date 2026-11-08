local calls = {}
local time = require('ui.countdown_text').time
local icon_values = require('ui.countdown_text').icon_values
local function padding(options)
    local edge = options.countdown_outline and 1 or 0
    return edge, edge, (options.countdown_bold and 1 or 0) + math.max(edge, options.countdown_shadow and 1 or 0), math.max(edge, options.countdown_shadow and 1 or 0)
end
package.loaded['ui.countdown_text'] = {
    time = time,
    icon_values = icon_values,
    indefinite = function() return false end,
    padding = padding,
    measure = function(_, value, size, options)
        local left, top, right, bottom = padding(options)
        return #value * size / 2 + left + right, size + top + bottom
    end,
    draw = function(_, font, value, x, y, size, color, options)
        calls[#calls + 1] = { font = font, text = value, x = x, y = y, size = size, options = options }
        return true
    end,
}
local defaults, hud, fields = require('ui.defaults'), require('ui.hud'), require('ui.fields')
local custom = require('core.customization')
local s = defaults.make()
for _, id in ipairs(defaults.panel_order) do
    assert(s.panels[id].countdown_outline == not defaults.recast_panels[id], 'Status countdowns start outlined; recasts keep their own default.')
end
local previous = defaults.copy(s)
for _, id in ipairs(defaults.panel_order) do previous.panels[id].countdown_outline = false end
previous = defaults.tidy(require('json').decode(require('json').encode(previous)))
for _, id in ipairs(defaults.panel_order) do assert(not previous.panels[id].countdown_outline, 'An explicit saved off choice survives reload.') end
local missing = defaults.copy(s)
for _, id in ipairs(defaults.panel_order) do missing.panels[id].countdown_outline = nil end
missing = defaults.tidy(missing)
for _, id in ipairs(defaults.panel_order) do
    assert(missing.panels[id].countdown_outline == not defaults.recast_panels[id], 'Missing status choices use the default without changing recasts.')
end
local p = s.panels.self_buffs
p.mode, p.stack_direction = 'bars', 'vertical'
p.countdown_bold, p.countdown_shadow, p.countdown_outline = true, false, true
p.countdown_outline_color = { .2, .4, .6, .8 }
s.style.font = 'Original FFXI'
local before = defaults.copy(s)
local shared_look = require('ui.shared_look')
shared_look.set_bold(s, true)
shared_look.set_shadow(s, false)
shared_look.set_outline(s, 'every')
shared_look.set_outline_color(s, p.countdown_outline_color)
for _, id in ipairs(defaults.panel_order) do
    local panel = s.panels[id]
    assert(panel.countdown_bold and not panel.countdown_shadow and panel.countdown_outline)
    assert(custom.equal(panel.countdown_outline_color, p.countdown_outline_color))
    for key, value in pairs(before.panels[id]) do
        if not key:match('^countdown_') then assert(custom.equal(panel[key], value), key .. ' was not part of countdown styling.') end
    end
end
local strips = s.party_ui.effects
assert(strips.countdown_bold and not strips.countdown_shadow and strips.countdown_outline)
assert(strips.countdown_outline_color ~= p.countdown_outline_color, 'Shared edits do not alias saved color tables.')
assert(custom.equal(s.style, before.style) and s.party_ui.locked == before.party_ui.locked)
local persisted = defaults.tidy(require('json').decode(require('json').encode(s)))
assert(persisted.panels.self_buffs.countdown_bold and not persisted.panels.self_buffs.countdown_shadow)
assert(persisted.party_ui.effects.countdown_outline)
local set = assert(custom.set(s, 'panels.self_buffs.countdown_shadow', 'on'))
assert(set.panels.self_buffs.countdown_shadow and not s.panels.self_buffs.countdown_shadow)
local bad = defaults.copy(s)
bad.panels.self_buffs.countdown_bold = 'bad'
bad.panels.self_buffs.countdown_outline_color = { 2, -1, 0/0, 'bad' }
bad = defaults.tidy(bad)
assert(not bad.panels.self_buffs.countdown_bold and bad.panels.self_buffs.countdown_outline_color[1] == 1 and bad.panels.self_buffs.countdown_outline_color[2] == 0)
local view = hud.sample(100)
for id, panel in pairs(s.panels) do panel.enabled = id == 'self_buffs' end
p.show_icon, p.show_heading, p.wrap = false, false, true
local entries = hud.entries(view.rows[1], p, s.style, 100)
local seen = false
for _, entry in ipairs(entries) do
    if entry.id == 'time' then assert(entry.countdown and entry.countdown_bold and entry.countdown_outline); seen = true
    else assert(not entry.countdown, 'Names and labels keep their existing text style.') end
end
assert(seen)
local measured = function(value, size, run) return #value + (run and run.countdown and 3 or 0) end
local wrapped = fields.lines(entries, 8, p, measured)
for _, line in ipairs(wrapped) do
    for _, entry in ipairs(line) do
        assert(fields.width(entry, measured) <= 8, 'Wrapped countdown parts reserve their decorations.')
        for _, run in ipairs(entry.runs or { entry }) do if run.id == 'time' then assert(run.countdown_bold and run.countdown_outline) end end
    end
end
for _, font in ipairs({ 'Original FFXI', 'XI View', 'Tahoma' }) do
    s.style.font = font
    for _, mode in ipairs({ 'bars', 'expanded', 'icons' }) do
        p.mode, calls = mode, {}
        hud.draw(view, s, 100, {})
        assert(#calls > 0, font .. '/' .. mode)
        for _, call in ipairs(calls) do
            assert(call.font == font and call.options.countdown_bold and not call.options.countdown_shadow and call.options.countdown_outline)
            assert(not call.text:find('Haste', 1, true))
        end
    end
end
custom.reset(s, 'appearance')
assert(not s.panels.self_buffs.countdown_bold and s.panels.self_buffs.countdown_shadow and s.panels.self_buffs.countdown_outline)
