local defaults,hud,imgui=require('ui.defaults'),require('ui.hud'),require('imgui')
local s,view=defaults.make(),hud.sample(100)
local p=s.panels.self_buffs
p.mode,p.stack_direction='bars','vertical'
for _,panel in pairs(s.panels) do panel.enabled=false end
p.enabled,p.locked=true,false
local function position()
    for _,call in ipairs(MOCK.imgui_calls) do if call[1]=='SetNextWindowPos' then return call[2][1],call[2][2] end end
end
local function width()
    for _,call in ipairs(MOCK.imgui_calls) do if call[1]=='SetNextWindowSize' then return call[2][1] end end
end
local function draw(now,cb) MOCK.imgui_calls={};hud.draw(view,s,now or 100,cb or {});return position() end
p.auto_width,p.min_width,p.max_width=true,180,550
draw();local narrow=width();assert(narrow>=180 and narrow<=550)
p.labels[33]='Haste with a substantially longer custom label'
draw();assert(width()>narrow and width()<=550)
p.auto_width,p.width=false,300
p.anchor.to,p.anchor.side,p.dock_match_width='chat','above',true
view.context.chat={x=500,y=600,width=450,height=200}
local x,y=draw();assert(x==500 and y<600 and width()==450)
view.context.chat.y=10
x,y=draw();assert(x==p.x and y==p.y)
p.anchor.to='none';view.context.chat=nil
local saves,clicked=0,false
local cb={shift=true,changed=function() end,save=function() saves=saves+1 end}
imgui.IsItemHovered=function() return true end
imgui.IsMouseClicked=function() local result=clicked;clicked=false;return result end
s.panels.self_debuffs.enabled=true
s.panels.self_debuffs.x,s.panels.self_debuffs.y=500,300
p.anchor.to,p.anchor.element,p.anchor.side,p.anchor.align='element','self_debuffs','below','start'
x,y=draw();assert(x==500 and y>300)
local move_bounds=hud.bounds(p,s.style,6,1600,900)
MOCK.mouse_x,MOCK.mouse_y,MOCK.mouse_down,clicked=x+width()/2,y+move_bounds.height/2,true,true
draw(100,cb)
MOCK.mouse_x,MOCK.mouse_y=MOCK.mouse_x+30,MOCK.mouse_y+20
draw(100.1,cb)
assert(p.anchor.to=='none' and p.x==x+30 and p.y==y+20,'Dragging detaches at the actual displayed position.')
MOCK.mouse_down=false;draw(100.2,cb);assert(saves==1)
s.panels.self_debuffs.enabled=false
s.window.open,s.window.peek=true,true
s.window.x,s.window.y,s.window.width,s.window.height=0,0,1600,900
move_bounds=hud.bounds(p,s.style,6,1600,900)
MOCK.mouse_x,MOCK.mouse_y,MOCK.mouse_down,clicked=p.x+move_bounds.width/2,p.y+move_bounds.height/2,true,true
draw(100.3,cb)
local oldx=p.x
MOCK.mouse_x=MOCK.mouse_x+25;draw(100.4,cb)
assert(p.x==oldx+25,'Peek allows Shift placement beneath the configuration window.')
s.visibility.hide_typing,view.context.chat_open=true,true
draw(100.5,cb);assert(saves==2,'Typing finishes the placement transaction before hiding the panel.')
MOCK.mouse_down=false;view.context.chat_open=false;s.window.open=false
p.height_limit=80
draw(100.6)
local copied=hud.copy_text(view,s,'self_buffs',false,100.6)
local copied_lines=select(2,copied:gsub('\n',''))+1
local listed=#hud.filter_rows(view,p,'self_buffs',s)
assert(copied_lines>1 and copied_lines-1<listed and not copied:find('more',1,true),'Copy shown respects the rendered height limit and adds no count.')
s=defaults.make();p=s.panels.self_buffs
p.mode,p.stack_direction='bars','vertical'
for key,panel in pairs(s.panels) do panel.enabled=key=='self_buffs' end
s.style.background,s.style.border,p.show_heading,p.show_fill,p.show_text=false,false,false,false,false
view=hud.sample(100)
view.notices={{key=view.rows[1].key,instance=view.rows[1].instance,visual=false,emphasis=true,ends=101,flash=true,flash_ends=110,flash_color={1,0,1,1}}}
local function outlines(now)
    draw(now)
    local count=0
    for _,call in ipairs(MOCK.imgui_calls) do if call[1]=='draw:AddRect' then count=count+1 end end
    return count
end
assert(outlines(104)==1 and outlines(104.3)==0,'A retained flash alternates after its text notice expires.')
assert(outlines(111)==0,'Flash stops at its own deadline.')
s=defaults.make(); p=s.panels.self_buffs;
p.mode,p.stack_direction='bars','vertical';
for key,panel in pairs(s.panels) do panel.enabled=key=='self_buffs'; end
s.preview=true;
view.context.chat_open=false;
MOCK.mouse_down,MOCK.key_shift,MOCK.mouse_x,MOCK.mouse_y=false,false,p.x+50,p.y+40;
hud.cancel_gesture(); draw(200); draw(200.5);
local tooltip=false;
for _,call in ipairs(MOCK.imgui_calls) do if call[1]=='BeginTooltip' then tooltip=true; end end
assert(tooltip,'Samples keep the hover delay.');
