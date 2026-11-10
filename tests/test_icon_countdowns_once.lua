-- An icon panel that sizes itself to its countdowns works them out once a frame, as one of a set width does: its width
-- and its height take the same ones. Another frame works them out again, at the same time too.
local defaults, hud = require('ui.defaults'), require('ui.hud')
local s = defaults.make()
local p = s.panels.self_buffs
p.mode = 'icons'
local view = hud.sample(100)
local timer_text, calls = hud.timer_text, 0
hud.timer_text = function(...) calls = calls + 1; return timer_text(...) end
local function frame(auto)
    p.auto_width = auto
    calls = 0
    hud.draw(view, s, 100, {})
    return calls
end
frame(true); frame(false)
local fixed, auto = frame(false), frame(true)
assert(fixed > 0 and auto == fixed, 'Sizing itself adds no countdown work: ' .. fixed .. ' and ' .. auto)
assert(frame(true) == auto, 'and the next frame does the same work.')
hud.timer_text = timer_text
