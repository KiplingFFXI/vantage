local defaults = require('ui.defaults')
local hud = require('ui.hud')
local window = require('ui.settings_window')
local imgui = require('imgui')
local rendered_rect, begin = nil, imgui.Begin
imgui.Begin = function(name, ...)
    if name == '##vantage_self_buffs' then
        rendered_rect = { x=MOCK.next_pos[1], y=MOCK.next_pos[2], width=MOCK.next_size[1], height=MOCK.next_size[2] }
    end
    return begin(name, ...)
end
local s, view = defaults.make(), hud.sample(100)
s.panels.self_buffs.mode, s.panels.self_buffs.stack_direction = 'bars', 'vertical'
local changes, saves, tests = {}, 0, 0
local cb = {changed=function(stage) changes[#changes+1]=stage end,save=function() saves=saves+1; return true end,
    profile_list=function() return {} end,sound_files=function() return {'bell.wav'} end,now=function() return 100 end,
    test_alert=function(rule) assert(rule.effect == 33); tests=tests+1; return true end}
s.window.open = true
local frame = require('ui.panel_frame')
for _, page in ipairs({{'Display','self_buffs','show'},{'Display','self_buffs','filters'},{'Display','notices','show'},
    {'Home'},{'Profiles'},{'Help'}}) do
    s.window.tab = page[1]
    if page[2] then frame.open(page[2],page[3]) end
    window.draw(s,view,cb)
    assert(#MOCK.font_stack == 0, page[1] .. ' balances font stack.')
end
s.window.tab = 'Display'
frame.open('notices','show')
MOCK.clicks['Haste reminder##frame'] = true
window.draw(s,view,cb)
assert(#s.alerts.rules == 1 and s.alerts.rules[1].effect == 33 and s.alerts.rules[1].sound == '')
MOCK.clicks['Test this alert##frame'] = true
window.draw(s,view,cb)
assert(tests == 1)
local input, observed
imgui.InputText = function(label,value)
    if label == '##thresholds' then
        observed = value[1]
        if input then value[1],input = input,nil; return true end
    end
    return false
end
input = '30, '
window.draw(s,view,cb)
window.draw(s,view,cb)
assert(observed == '30, ', 'Typing a comma preserves the draft across frames.')
input = '30, 7'
window.draw(s,view,cb)
assert(s.alerts.rules[1].thresholds[2] == 7)
input = '-5, 7.5, 0, 10'
window.draw(s,view,cb)
assert(#s.alerts.rules[1].thresholds == 1 and s.alerts.rules[1].thresholds[1] == 10)
local old_saves = saves
MOCK.window_pos['Vantage##settings'] = {200,150}
window.draw(s,view,cb)
assert(s.window.x == 200 and s.window.y == 150 and saves > old_saves)
assert(changes[#changes-1] == 'before' and changes[#changes] == 'after')
s.window.tab = 'Home'
MOCK.clicks['Help'] = true
window.draw(s,view,cb)
assert(s.window.tab == 'Help')
MOCK.clicks['Title bar X'] = true
window.draw(s,view,cb)
assert(not s.window.open)
for _, panel in pairs(s.panels) do panel.enabled = false end
local p = s.panels.self_buffs
p.enabled,p.locked = true,true
imgui.IsItemHovered = function() return true end
local clicked = true
imgui.IsMouseClicked = function() local old=clicked; clicked=false; return old end
MOCK.mouse_down,MOCK.mouse_x,MOCK.mouse_y = true,60,130
cb.shift = true
hud.draw(view,s,100,cb)
MOCK.mouse_x,MOCK.mouse_y = 100,150
hud.draw(view,s,100.1,cb)
assert(p.x == 40 and p.y == 120, 'Locked panels cannot move.')
MOCK.mouse_down = false
hud.draw(view,s,100.2,cb)
p.locked = false
view.context.chat_open = true
clicked,MOCK.mouse_down,MOCK.mouse_x,MOCK.mouse_y = true,true,60,130
hud.draw(view,s,100.3,cb)
MOCK.mouse_x,MOCK.mouse_y = 100,150
hud.draw(view,s,100.4,cb)
assert(p.x == 40 and p.y == 120, 'Typing chat blocks Shift dragging.')
view.context.chat_open, cb.shift = false,false
hud.draw(view,s,100.5,cb)
assert(p.x == 40, 'Unlocked panels require Shift.')
local move_rect = assert(rendered_rect)
local move_x,move_y = move_rect.x+move_rect.width/2,move_rect.y+move_rect.height/2
cb.shift,clicked,MOCK.mouse_x,MOCK.mouse_y = true,true,move_x,move_y
hud.draw(view,s,100.6,cb)
MOCK.mouse_x,MOCK.mouse_y = move_x+40,move_y+20
hud.draw(view,s,100.7,cb)
assert(p.x == 80 and p.y == 140, 'Shift drag tracks the mouse delta.')
old_saves,MOCK.mouse_down = saves,false
hud.draw(view,s,100.8,cb)
assert(saves == old_saves + 1, 'Gesture saves once when released.')
-- Drag the visible corner after text wrapping and gauge spacing have been measured.
local rect = assert(rendered_rect)
clicked,MOCK.mouse_down = true,true
MOCK.mouse_x,MOCK.mouse_y = rect.x+rect.width-2,rect.y+rect.height-2
hud.draw(view,s,101,cb)
MOCK.mouse_x,MOCK.mouse_y = MOCK.mouse_x+100,MOCK.mouse_y+60
hud.draw(view,s,101.1,cb)
assert(p.width == 400 and p.height_limit == rect.height+60, 'Corner drag resizes: '..p.width..'x'..p.height_limit..' vs 400x'..(rect.height+60))
MOCK.mouse_down = false
hud.draw(view,s,101.2,cb)
view.notices = {{key=view.rows[1].key,instance=view.rows[1].instance,message='Haste has 10 seconds left.',visual=true,emphasis=true,ends=110,time=100}}
s.enabled = false
MOCK.imgui_calls = {}
hud.draw(view,s,102,cb)
local notice, panel = false,false
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'Begin' then notice=notice or call[2]=='##vantage_notices'; panel=panel or call[2]=='##vantage_self_buffs' end
end
assert(notice and not panel, 'Hiding panels keeps local alerts visible.')
MOCK.imgui_calls = {}
hud.draw(view,s,111,cb)
for _, call in ipairs(MOCK.imgui_calls) do assert(call[1] ~= 'Begin', 'Expired notices are hidden.') end
s.enabled,s.preview = true,true
MOCK.imgui_calls = {}
hud.draw({rows={},context={},valid=false},s,200,cb)
local sample = false
for _, call in ipairs(MOCK.imgui_calls) do if call[1]=='draw:AddText' and tostring(call[6]):find('Sample',1,true) then sample=true end end
assert(sample, 'Sample mode renders invented data without live client rows.')
local old_x,old_y = p.x,p.y
clicked,MOCK.mouse_down,MOCK.mouse_x,MOCK.mouse_y = true,true,p.x+20,p.y+10
view.context.chat_open = true
hud.draw(view,s,201,cb)
MOCK.mouse_x,MOCK.mouse_y = MOCK.mouse_x+100,MOCK.mouse_y+50
hud.draw(view,s,201.1,cb)
assert(p.x==old_x and p.y==old_y, 'Sample preview keeps the real chat input guard.')
assert(#MOCK.commands == 0, 'UI never queues game commands.')
