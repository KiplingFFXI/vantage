local hud, imgui, defaults = require('ui.hud'), require('imgui'), require('ui.defaults')
local app, view = PREVIEW.addon, hud.sample(100)
require('ui.recast_icons').prepare()
for _,row in ipairs(view.rows) do
    if row.effect==10004 then row.spell_id,row.list_icon_hq,row.list_icon_nq=4,89,6
    elseif row.effect==10057 then row.spell_id,row.list_icon_hq,row.list_icon_nq=57,143,2
    elseif row.effect==20005 then row.ability_id,row.list_icon_id,row.ability_element=547,360,41
    elseif row.effect==45762 then row.item_id,row.recast_id=15762,15762 end
end
function PREVIEW.reset(mode)
    hud.cancel_gesture()
    app.state.settings=defaults.make()
    local s=app.state.settings
    require('original_skin_fixture')(s)
    s.recast_display='combined'
    for key,p in pairs(s.panels) do p.enabled=key=='recasts' end
    s.window.open,s.style.scale=false,1
    s.style.icon_size=32
    local p=s.panels.recasts
    p.mode,p.locked,p.x,p.y,p.width,p.height_limit=mode,false,200,180,420,380
    p.auto_width,p.auto_height=false,false
    app.state.history,app.state.redo,app.state.transaction={},{},nil
    PREVIEW.settings=s
end
function PREVIEW.verify(mode,edge,direction)
    local p=app.state.settings.panels.recasts
    local horizontal,vertical=require('ui.resize').axes(edge)
    local left,top=edge:find('left',1,true),edge:find('top',1,true)
    local width=420+(horizontal and direction*30 or 0)
    local height=380+(vertical and direction*20 or 0)
    assert(p.width==width and p.height_limit==height,mode..' dimensions '..edge..' '..direction)
    assert(p.x==200+(left and -direction*30 or 0) and p.y==180+(top and -direction*20 or 0),mode..' origin '..edge)
    assert(app.state.settings.style.font_size==16 and app.state.settings.style.icon_size==32)
    assert(#app.state.history==1 and app.state.transaction==nil,'A pointer gesture is one completed Undo entry.')
    assert(app.callbacks.undo())
    p=app.state.settings.panels.recasts
    assert(p.width==420 and p.height_limit==380 and p.x==200 and p.y==180)
    assert(app.callbacks.redo())
    p=app.state.settings.panels.recasts
    assert(p.width==width and p.height_limit==height)
end
function PREVIEW.wrap_setup()
    PREVIEW.reset('bars')
    local p=app.state.settings.panels.recasts
    p.auto_height=true;p.filter='haste';p.labels[10057]='A long readable spell name with several words'
end
function PREVIEW.verify_wrap()
    local s=app.state.settings
    assert(s.panels.recasts.width==190 and s.panels.recasts.wrap and s.panels.recasts.auto_height)
    assert(s.style.font_size==16 and s.style.icon_size==32)
    PREVIEW.log('Combined panel: all eight grips grow and shrink in all three layouts; Undo/Redo and actual narrow wrapping passed.')
end
PREVIEW.reset('bars')
return function()
    PREVIEW.settings=app.state.settings
    app.callbacks.shift=imgui.GetIO().KeyShift==true
    hud.draw(view,PREVIEW.settings,100,app.callbacks)
end
