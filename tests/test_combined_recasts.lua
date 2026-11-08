local defaults, hud = require('ui.defaults'), require('ui.hud')
local copy, equal = defaults.copy, require('core.customization').equal
local settings, view = defaults.make(), hud.sample(100)
local panel = settings.panels.recasts
assert(settings.recast_display == 'separate' and panel.enabled and not defaults.panel_enabled(settings, 'recasts'))
settings.recast_display = 'combined'
assert(defaults.panel_enabled(settings, 'recasts'))
local function rows() return hud.filter_rows(view, panel, 'recasts', settings) end
local original_view = copy(view)
assert(#rows() == 4, 'Combined recasts include all three cooldown categories, without status rows.')
for _, row in ipairs(rows()) do assert(row.domain == 'recast') end
panel.recast_categories.spell = false
assert(#rows() == 2)
panel.recast_categories.ability, panel.recast_categories.item = false, false
assert(#rows() == 0)
panel.recast_categories = {spell=true, ability=true, item=true}
panel.include = {[10057]=true, [20005]=true}
assert(#rows() == 2)
panel.exclude[10057] = true
assert(#rows() == 1 and rows()[1].effect == 20005, 'Exclusion still wins in a mixed panel.')
panel.include, panel.exclude, panel.filter = {}, {}, 'haste'
assert(#rows() == 1 and rows()[1].effect == 10057)
panel.filter, panel.groups = '', {item_recasts=true}
assert(#rows() == 1 and rows()[1].kind == 'item')
panel.groups, panel.sort = {}, 'name'
assert(rows()[1].name == 'Cure IV' and rows()[4].name == 'Provoke')
panel.sort = 'remaining'
for index = 2, #rows() do assert(rows()[index-1].deadline <= rows()[index].deadline) end
panel.sort, panel.order = 'fixed', {45762,20005,10057,10004}
assert(rows()[1].effect == 45762 and rows()[4].effect == 10004)
panel.pinned = {10004}
assert(rows()[1].effect == 10004, 'Pinning takes priority over cross-category custom order.')
assert(equal(view, original_view), 'Display filtering never changes cooldown observations.')

-- The selected layout is the only one drawn or included in Copy shown.
local imgui, fonts, pictures = require('imgui'), require('ui.fonts'), require('ui.recast_icons')
local position, dimensions, current, cursor, item = {}, {}, {}, {}, nil
local rects, captions, draws = {}, {}, {}
local mx, my, down, pressed = -1, -1, false, false
imgui.SetNextWindowPos = function(v) position=v end
imgui.SetNextWindowSize = function(v) dimensions=v end
imgui.Begin = function(name)
    current={x=position[1],y=position[2],width=dimensions[1],height=dimensions[2]}
    rects[name], draws[#draws+1] = current, name
    return true
end
imgui.GetMousePos = function() return mx,my end
imgui.IsMouseDown = function() return down end
imgui.IsMouseClicked = function() return pressed end
imgui.SetCursorPos = function(v) cursor={current.x+v[1],current.y+v[2]} end
imgui.InvisibleButton = function(_,size) item={x=cursor[1],y=cursor[2],width=size[1],height=size[2]} end
imgui.IsItemHovered = function() return item and mx>=item.x and mx<item.x+item.width and my>=item.y and my<item.y+item.height end
fonts.measure = function(_,text,size) return #text*size*.5 end
fonts.draw = function(_,_,text,x,y,size) captions[#captions+1]={text=text,x=x,y=y,size=size}; return true end
fonts.is_bitmap = function() return true end
fonts.failed = function() return false end
pictures.draw = function() return true end
MOCK.screen = {1600,1000}
settings=defaults.make()
for key,p in pairs(settings.panels) do p.enabled=defaults.recast_panels[key]~=nil end
hud.draw(view,settings,100,{})
assert(#draws == 3 and rects['##vantage_spell_recasts'] and not rects['##vantage_recasts'])
settings.recast_display='combined'; draws,rects={},{}
hud.draw(view,settings,100,{})
assert(#draws == 1 and rects['##vantage_recasts'])
local copied=hud.copy_text(view,settings,nil,false,100)
local _,count=copied:gsub('Cure IV','')
assert(count == 1, 'Copy shown does not duplicate rows from the inactive layout.')

local saves, edits, before, callbacks
local function fresh(mode)
    hud.cancel_gesture()
    settings=defaults.make(); settings.recast_display='combined'
    for key,p in pairs(settings.panels) do p.enabled=key=='recasts' end
    panel=settings.panels.recasts
    panel.mode,panel.locked,panel.x,panel.y=mode,false,200,180
    panel.width,panel.height_limit,panel.auto_width,panel.auto_height=420,380,false,false
    settings.style.font_size,settings.style.icon_size,settings.style.scale=16,32,1
    saves,edits,before=0,0,nil
    callbacks={shift=true,save=function()saves=saves+1 end,changed=function(stage)
        if stage=='before' then before=copy(settings) else edits=edits+1 end
    end}
    mx,my,down,pressed,item=-1,-1,false,false,nil
    captions,rects,draws={},{},{}
    hud.draw(view,settings,100,callbacks)
    return rects['##vantage_recasts']
end
local function render() hud.draw(view,settings,100,callbacks) end
local function start(edge)
    local r=rects['##vantage_recasts']
    mx=edge:find('left',1,true) and r.x+1 or edge:find('right',1,true) and r.x+r.width-1 or r.x+r.width/2
    my=edge:find('top',1,true) and r.y+1 or edge:find('bottom',1,true) and r.y+r.height-1 or r.y+r.height/2
    down,pressed=true,true; render(); pressed=false
    return r
end
local function release() down,pressed=false,false; render() end
for _,mode in ipairs({'bars','expanded','icons'}) do
    for _,edge in ipairs({'left','right','top','bottom','top_left','top_right','bottom_left','bottom_right'}) do
        for _,direction in ipairs({-1,1}) do
            fresh(mode); local initial=start(edge)
            local horizontal,vertical=require('ui.resize').axes(edge)
            mx=mx+(edge:find('left',1,true) and -30 or 30)*direction
            my=my+(edge:find('top',1,true) and -20 or 20)*direction
            render();release()
            local r=rects['##vantage_recasts']
            assert(r.width==initial.width+(horizontal and 30*direction or 0), mode..' '..edge..' horizontal resize')
            assert(r.height==initial.height+(vertical and 20*direction or 0), mode..' '..edge..' vertical resize')
            assert(r.x+r.width==initial.x+initial.width+(edge:find('right',1,true) and 30*direction or 0))
            assert(r.y+r.height==initial.y+initial.height+(edge:find('bottom',1,true) and 20*direction or 0))
            assert(saves==1 and before and edits>0, 'One combined-panel gesture is one saved edit.')
            assert(settings.style.font_size==16 and settings.style.icon_size==32, 'Resizing preserves selected font and icon sizes.')
        end
    end
    fresh(mode);local initial=start('center');mx,my=mx+34,my+27;render();release()
    assert(panel.x==initial.x+34 and panel.y==initial.y+27 and saves==1)
    fresh(mode);local original=copy(settings);start('top_left');release()
    assert(equal(original,settings) and saves==0 and not before, 'No-motion clicks do not create history.')
    for _,blocked in ipairs({'shift','typing','locked','settings'}) do
        fresh(mode)
        if blocked=='shift' then callbacks.shift=false
        elseif blocked=='typing' then view.context.chat_open=true
        elseif blocked=='locked' then panel.locked=true
        else settings.window.open,settings.window.peek=true,false;settings.window.x,settings.window.y,settings.window.width,settings.window.height=0,0,1600,1000 end
        original=copy(settings);start('right');mx=mx+40;render();release()
        assert(equal(settings,original) and saves==0, mode..' '..blocked..' protects placement')
        view.context.chat_open=false
    end
end
fresh('bars')
panel.filter,panel.labels[10057],panel.show_heading='haste','A long readable spell name with several words',false
panel.auto_height=true;render()
local wide_height=rects['##vantage_recasts'].height
start('right');mx=mx-230;render();release()
assert(panel.wrap and panel.width==190 and panel.auto_height, 'Horizontal resizing enables wrapping without disabling automatic height.')
assert(rects['##vantage_recasts'].height>wide_height, 'Wrapped text increases the combined panel height.')
captions={};render();local caption_text={};for _,c in ipairs(captions)do caption_text[#caption_text+1]=c.text end
local displayed=table.concat(caption_text,' ')
assert(displayed:find('readable',1,true) and displayed:find('several',1,true) and displayed:find('words',1,true), 'Wrapped names retain their words.')
assert(settings.style.font_size==16 and settings.style.icon_size==32)
hud.cancel_gesture();mx,my,down,pressed=-1,-1,false,false

-- Real command, history, profile and reader-demand integration.
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_effects={},party={},entities={}}
package.loaded['core.client']={load=function()end,read=function()return copy(snapshot)end}
package.loaded['core.observer']={read=function()return {}end}
local options
package.loaded['core.recasts']={catalog=function()return {}end,new=function()return {
    reset=function()end,update=function(_,_,_,o)options=o end,view=function()return {rows={},version=0}end,
    project=function()end,drain_events=function()return {}end,
}end}
local app=dofile(ADDON_DIR..'/vantage.lua')
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end
local function refresh()MOCK.now=MOCK.now+.2;app.refresh(MOCK.now)end
refresh()
local function state()return app.state.settings end
state().panels.spell_recasts.enabled=true
state().panels.spell_recasts.mode='icons';state().panels.spell_recasts.width=287
state().panels.ability_recasts.labels[20005]='My Provoke'
local separate={};for _,key in ipairs({'spell_recasts','ability_recasts','item_recasts'})do separate[key]=copy(state().panels[key])end
command('/vg recasts combine');assert(state().recast_display=='combined')
for key,p in pairs(separate)do assert(equal(state().panels[key],p))end
command('/vg undo');assert(state().recast_display=='separate')
command('/vg redo');assert(state().recast_display=='combined')
state().panels.recasts.recast_categories={spell=false,ability=true,item=false};refresh()
assert(options.enabled and not options.spells and options.abilities and not options.items, 'Only selected combined categories request sampling.')
command('/vg recasts hide');refresh();assert(not options.enabled)
for key,p in pairs(separate)do assert(equal(state().panels[key],p), 'Combined hide leaves separate settings untouched.')end
local rule=defaults.rule('hidden_item');rule.domain,rule.effect,rule.event='recast',45762,'ready'
state().alerts.rules={rule};refresh()
assert(options.items and not options.spells and not options.abilities, 'Hidden combined categories still permit requested alerts.')
state().alerts.rules={};command('/vg recasts show');refresh()
assert(options.abilities and not options.spells and not options.items)
state().window.open,state().window.tab=true,'Display';refresh()
assert(options.spells and options.abilities and options.items, 'An open recast catalog can request all categories.')
state().window.open=false
command('/vg recasts separate');refresh()
assert(state().recast_display=='separate' and options.spells and not options.abilities and not options.items)
for key,p in pairs(separate)do assert(equal(state().panels[key],p))end
command('/vantage recasts combine')
state().panels.recasts.width=377;state().panels.recasts.labels[20005]='Mixed Provoke'
command('/vg profile save "Combined recasts"')
command('/vg recasts separate');state().panels.recasts.width=599
command('/vg profile load "Combined recasts"')
assert(state().recast_display=='combined' and state().panels.recasts.width==377 and state().panels.recasts.recast_categories.ability)
assert(state().panels.recasts.labels[20005]=='Mixed Provoke' or state().panels.recasts.labels['20005']=='Mixed Provoke')
local profiles=require('core.profiles')
local placement=profiles.capture_layout(state(),'placement')
assert(placement.recast_display==nil and placement.recasts.width==377 and placement.recasts.recast_categories==nil)
local presentation=profiles.capture_layout(state(),'presentation').presentation
assert(presentation.recast_display=='combined' and presentation.panels.recasts.recast_categories.ability)
MOCK.fire('unload')
assert(#MOCK.commands==0, 'Combined recast display, commands and profiles send no gameplay commands.')
