local defaults = require('ui.defaults')
local hud = require('ui.hud')
local fields = require('ui.fields')
local layout = require('ui.layout')
local imgui = require('imgui')
local settings = defaults.make()
local p, style = settings.panels.self_buffs, settings.style
p.mode, p.stack_direction = 'bars', 'vertical'
local view = hud.sample(100)
local row = view.rows[1]
assert(style.snap == nil and not style.text_outline and p.show_text and p.show_fill)
-- Every countdown has the one time format, whatever format a caller still names.
assert(hud.time(3601, 'minutes') == '1h' and hud.time(61, 'seconds') == '1m')
assert(hud.timer_text({status='unknown'}, 100, 'seconds') == '')
local ranged = {status='estimated',start=80,deadline=200,duration_min=60,total=120}
assert(hud.timer_text(ranged, 100, 'seconds') == '40s - 1m')
p.show_source,p.show_total,p.show_elapsed,p.show_target = true,true,true,true
p.field_order = {'time','name','source','total','elapsed','target'}
p.field_labels.name,p.label_separator = 'Spell', ': '
local entries = hud.entries(row,p,style,100)
assert(entries[1].id == 'time' and entries[2].text == 'Spell: Haste')
p.label_position = 'after'
assert(hud.entries(row,p,style,100)[2].text == 'Haste: Spell')
p.label_position = 'hidden'
assert(hud.entries(row,p,style,100)[2].text == 'Haste')
p.field_colors.name = {1,0,0,1}
p.field_alignments.name = 'center'
entries = hud.entries(row,p,style,100)
assert(entries[2].color[1]==1 and entries[2].color[2]==0 and entries[2].alignment=='center')
-- A source or total that was never seen is left out.
local unknown = defaults.copy(row)
unknown.source_name,unknown.total,unknown.status,unknown.deadline = nil,nil,'unknown',nil
entries = hud.entries(unknown,p,style,100)
for _, entry in ipairs(entries) do assert(entry.id~='source' and entry.id~='total') end
p.show_text=false
assert(#hud.entries(row,p,style,100)==0)
local unit = function(text) return #text end
local example = {{id='name',text='long name',size=10,priority=20,alignment='left'}, {id='time',text='10s',size=10,priority=100,alignment='right'}}
assert(#fields.fit(example,5,' ',unit,true)==1 and fields.fit(example,5,' ',unit,true)[1].id=='time')
local lines = fields.lines(example,6,{wrap=true,separator=' '},unit)
assert(#lines==3 and lines[1][1].text=='long' and lines[2][1].text=='name')
local positioned = fields.positions(example,20,' ',unit)
assert(positioned[2].x==17 and positioned[1].width==9)
assert(fields.text({{text='A'},{text='B',divider=' / '},{text='C',newline=true}},' ')=='A / B\nC')
settings = defaults.make(); p,style=settings.panels.self_buffs,settings.style
p.mode, p.stack_direction = 'bars', 'vertical'
settings.panels.self_debuffs.known_only=true
assert(#hud.filter_rows(view,settings.panels.self_debuffs,'self_debuffs',settings)==1)
assert(hud.copy_text(view,settings,'self_buffs',false,100):find('Haste',1,true))
assert(hud.copy_text(view,settings,'self_buffs',true,100):find('(#33)',1,true))
local snap,elements=require('ui.snap'),require('ui.elements')
local placed=defaults.make()
local a,b=placed.panels.self_buffs,placed.panels.target
local boxes={self_buffs={x=10,y=10,width=100,height=40},target={x=300,y=300,width=80,height=20}}
b.anchor.to,b.anchor.element,b.anchor.gap,b.anchor.align='element','self_buffs',5,'end'
layout.resolve(placed.panels,boxes,{},800,600,placed)
assert(boxes.target.x==30 and boxes.target.y==55)
a.anchor.to,a.anchor.element,a.anchor.gap='element','target',0
assert(layout.resolve(placed.panels,boxes,{},800,600,placed).self_buffs.height==40, 'A circle of anchors is bounded.')
b.anchor.to,b.anchor.element,b.anchor.align='none','','start'
local chat={x=100,y=400,width=400,height=150,windows={{x=600,y=0,width=200,height=100}}}
elements.chat=chat
boxes={self_buffs={x=10,y=10,width=100,height=40}}
a.anchor.to,a.anchor.element,a.anchor.side,a.anchor.gap,a.anchor.offset='chat','','above',5,20
layout.resolve(placed.panels,boxes,{chat=chat},800,600,placed)
assert(boxes.self_buffs.x==120 and boxes.self_buffs.y==355 and elements.anchored('self_buffs'))
-- Pushed onto the chat log at the screen's edge, a panel is at its own spot, and Place says so. A gap below 0 asks for that.
chat.y=10
boxes.self_buffs={x=30,y=250,width=100,height=40}
layout.resolve(placed.panels,boxes,{chat=chat},800,600,placed)
assert(boxes.self_buffs.x==30 and boxes.self_buffs.y==250 and not elements.anchored('self_buffs'))
a.anchor.gap=-5
boxes.self_buffs={x=30,y=250,width=100,height=40}
layout.resolve(placed.panels,boxes,{chat=chat},800,600,placed)
assert(boxes.self_buffs.x==120 and boxes.self_buffs.y==0 and elements.anchored('self_buffs'),'Below 0 they overlap.')
a.anchor.gap=5
-- So is one that would land on another of the log's windows.
chat.y,chat.windows=400,{{x=100,y=330,width=400,height=60}}
boxes.self_buffs={x=30,y=250,width=100,height=40}
layout.resolve(placed.panels,boxes,{chat=chat},800,600,placed)
assert(boxes.self_buffs.x==30 and boxes.self_buffs.y==250 and not elements.anchored('self_buffs'))
elements.chat=nil
assert(layout.chat({chat={x=0,y=0,width=0,height=10}})==nil)
-- Self buffs moved to 103 snaps its middle to the middle of Self debuffs, 2 px off, before its left edge to theirs, 3 px off.
local placing=defaults.make()
for _,switch in ipairs({'snap_grid','snap_screen','snap_party','snap_chat'}) do placing.edit_mode[switch]=false end
placing.edit_mode.snap_distance=5
-- Grid mode on, with Self buffs ticked for it.
placing.edit_mode.grid_mode,placing.edit_mode.grid_displays=true,{'self_buffs'}
elements.frame();elements.frame()
elements.record('self_debuffs',{x=100,y=50,width=90,height=40})
local dx,dy=snap.move(placing,'self_buffs',103,200,80,40,800,600)
local guide
snap.guides({AddLine=function(_,from) guide=guide or from[1] end},0xFFFFFFFF,800,600,{x=103+dx,y=200,width=80,height=40})
assert(103+dx==105 and dy==0 and guide==145, 'The nearest matching edge or center wins.')
assert(layout.grip({x=0,y=0,width=100,height=50},98,25)=='width')
assert(layout.grip({x=0,y=0,width=100,height=50},25,48)=='height')
assert(layout.grip({x=0,y=0,width=100,height=50},98,48)=='both')
settings=defaults.make(); p,style=settings.panels.self_buffs,settings.style
p.mode, p.stack_direction = 'bars', 'vertical'
for key,panel in pairs(settings.panels) do panel.enabled=key=='self_buffs' end
p.show_icon,p.show_heading,style.background,style.border=false,false,false,false
p.gradient,p.warning_mark,p.fill_direction,p.bar_style=true,true,'left','rail'
p.colors.fill_start,p.colors.fill_end={1,0,0,1},{0,1,0,1}
style.text_outline=true
p.countdown_outline=true
MOCK.imgui_calls={}; hud.draw(view,settings,100,{})
local gradients,texts=0,0
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1]=='draw:AddRectFilledMultiColor' then gradients=gradients+1 end
    if call[1]=='draw:AddText' then texts=texts+1 end
end
assert(gradients==6 and texts>=60, 'Every row paints its gradient and outlined text.')
p.show_fill,p.show_text=false,false
MOCK.imgui_calls={}; hud.draw(view,settings,100,{})
for _,call in ipairs(MOCK.imgui_calls) do assert(call[1]~='draw:AddRectFilledMultiColor' and call[1]~='draw:AddText') end
settings.visibility.hide_typing=true;view.context.chat_open=true
MOCK.imgui_calls={};hud.draw(view,settings,100,{shift=true})
for _,call in ipairs(MOCK.imgui_calls) do assert(call[1]~='Begin') end
settings=defaults.tidy({style={font_size=48,title_size=0,scale=.5,opacity=.05,rounding=24},panels={self_buffs={field_order={'name','name','bad'},anchor={to='chat',side='above',offset=99999},field_colors={name={2,-1,0,1}},effect_colors={bad={1,1,1,1}}}}})
assert(settings.style.font_size==48 and settings.style.title_size==0 and settings.style.scale==.5 and settings.style.opacity==.05)
assert(#settings.panels.self_buffs.field_order==6 and settings.panels.self_buffs.anchor.offset==2000)
assert(settings.panels.self_buffs.field_colors.name[1]==1 and settings.panels.self_buffs.field_colors.name[2]==0 and not settings.panels.self_buffs.effect_colors.bad)
