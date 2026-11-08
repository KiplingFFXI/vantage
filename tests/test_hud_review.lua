local defaults,hud,fields,layout,theme = require('ui.defaults'),require('ui.hud'),require('ui.fields'),require('ui.layout'),require('ui.theme')
local s,view=defaults.make(),hud.sample(100)
local p=s.panels.self_buffs
p.mode,p.width,p.stack_direction='icons',1200,'horizontal'
assert(hud.bounds(p,s.style,20,190,700).columns==5, 'Compact icon columns use the actual viewport width.')
p.row_height=200
assert(hud.bounds(p,s.style,1,190,700).row_height==s.style.icon_size and p.row_height==200,
    'Icons only ignores stored bar heights while retaining them for switching back.')
p=defaults.make().panels.self_buffs
p.mode,p.stack_direction='bars','vertical'
p.field_colors.name,p.field_colors.time={1,0,0,1},{0,1,0,1}
local entries=hud.entries(view.rows[1],p,s.style,100)
assert(entries[1].color[1]==1 and entries[2].color[2]==1)
local unit=function(text,size) return #text*size end
local lines=fields.lines(entries,110,{wrap=true,separator=' '},unit)
local found_red,found_green=false,false
for _,line in ipairs(lines) do for _,entry in ipairs(line) do for _,run in ipairs(entry.runs or {entry}) do
    found_red=found_red or run.color[1]==1
    found_green=found_green or run.color[2]==1
end end end
assert(found_red and found_green,'Wrapping keeps the color of each field.')
local unavailable=defaults.tidy({panels={self_buffs={anchor={to='chat',side='above'}}}})
local boxes={self_buffs={x=10,y=10,width=100,height=40},target={x=300,y=300,width=80,height=20}}
layout.resolve(unavailable.panels,boxes,{},800,600,unavailable)
assert(boxes.self_buffs.x==10 and boxes.self_buffs.y==10,'With no chat to move with, a panel stays at its own spot.')
s=defaults.make();p=s.panels.self_buffs
p.mode,p.stack_direction='bars','vertical'
for key,panel in pairs(s.panels) do panel.enabled=key=='self_buffs' end
view=hud.sample(100);view.rows={view.rows[1]};view.rows[1].deadline=105
s.style.background,s.style.border,p.show_icon,p.show_heading,p.show_text=false,false,false,false,false
p.gradient,p.warning_enabled,p.bar_style=true,true,'full'
p.colors.fill_start,p.colors.fill_end={0,1,0,1},{0,0,1,1}
p.colors.warning,p.effect_colors[33]={1,1,0,1},{1,0,0,1}
local function gradient(now)
    MOCK.imgui_calls={};hud.draw(view,s,now,{})
    for _,call in ipairs(MOCK.imgui_calls) do if call[1]=='draw:AddRectFilledMultiColor' then return call end end
end
local painted=gradient(100)
assert(painted[4]==theme.u32(p.colors.warning,.3*s.style.opacity) and painted[4]==painted[5],'Ending-soon color overrides a custom gradient.')
painted=gradient(0)
assert(painted[4]==theme.u32(p.effect_colors[33],.3*s.style.opacity) and painted[4]==painted[5],'Per-effect colors override the general panel fill.')
view.notices={{visual=true,message='Live timer alert',ends=110}}
MOCK.imgui_calls={};hud.draw_notices(view,s,100)
local notice=false
for _,call in ipairs(MOCK.imgui_calls) do if call[1]=='Begin' and call[2]=='##vantage_notices' then notice=true end end
assert(notice,'Live alert notices show without samples.')
s.preview=true
MOCK.imgui_calls={};hud.draw_notices(view,s,100)
notice=false
for _,call in ipairs(MOCK.imgui_calls) do if call[1]=='Begin' and call[2]=='##vantage_notices' then notice=true end end
assert(notice,'Samples leave a live notice up, as its chat line and sound still go out.')
local auto_widths={}
for _,direction in ipairs({'horizontal','vertical'}) do
    s=defaults.make();p=s.panels.self_buffs;p.mode,p.auto_width,p.max_width,p.min_width='icons',true,700,24
    p.stack_direction,p.width=direction,1200
    for key,panel in pairs(s.panels) do panel.enabled=key=='self_buffs' end
    MOCK.imgui_calls={};hud.draw(hud.sample(100),s,100,{})
    for _,call in ipairs(MOCK.imgui_calls) do if call[1]=='SetNextWindowSize' then
        auto_widths[direction]=call[2][1]
        assert(call[2][1]>=24 and call[2][1]<=700 and p.width==1200,'Icon auto-width fits contents without changing saved width.')
    end end
end
assert(auto_widths.horizontal>auto_widths.vertical,'Horizontal auto-width makes room for a row; vertical keeps a narrow stack.')
s=defaults.make();p=s.panels.self_buffs
p.mode,p.stack_direction='bars','vertical'
p.show_icon,p.priority_overflow=false,true
p.field_priority.name,p.field_priority.time=0,100
for _,id in ipairs({33,41,40,214,251}) do p.labels[id]='A deliberately long custom effect label' end
local function line_count(text) return select(2,text:gsub('\n',''))+1 end
-- Six more of every sample row, for more than the panel shows.
local crowded=hud.sample(100)
local originals=#crowded.rows
for i=1,6 do
    for index=1,originals do
        local extra=defaults.copy(crowded.rows[index])
        extra.key,extra.instance='sample_extra_'..i..'_'..index,100*i+index
        crowded.rows[#crowded.rows+1]=extra
    end
end
local listed=#hud.filter_rows(crowded,p,'self_buffs',s)
p.auto_width,p.auto_height,p.width,p.wrap,p.height_limit=false,false,170,true,250
hud.draw(crowded,s,100,{})
local copied=hud.copy_text(crowded,s,'self_buffs',false,100)
assert(line_count(copied)-1<listed and not copied:find('more',1,true) and not copied:find('%+%d'),
    'Copy lists only the rows its height shows, with nothing for the rest.')
assert(copied:find('deliberately',1,true),'A narrow panel wraps the enabled label instead of hiding it by priority.')
p.height_limit=700
hud.draw(crowded,s,100,{})
local taller=hud.copy_text(crowded,s,'self_buffs',false,100)
assert(line_count(taller)>line_count(copied) and not taller:find('more',1,true),'A taller panel and its copied contents show more wrapped rows.')
assert(#MOCK.font_stack==0,'Drawing balances its font stack.')
