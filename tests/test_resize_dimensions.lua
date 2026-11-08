local resize,imgui=require('ui.resize'),require('imgui');
local copy,equal=require('core.store').copy,require('core.customization').equal;
local function check(rect,label,expected)
    local before=copy(rect);
    MOCK.imgui_calls={};
    resize.label(imgui.GetWindowDrawList(),rect,label,{font='Agave',font_size=16});
    local names,dimensions,clips,background=0,0,0,nil;
    for _,call in ipairs(MOCK.imgui_calls)do
        if call[1]=='draw:AddText' then
            if call[6]==label then names=names+1;end;
            if call[6]==expected then dimensions=dimensions+1;end;
        elseif call[1]=='draw:PushClipRect' then clips=clips+1;
        elseif call[1]=='draw:PopClipRect' then clips=clips-1;
        elseif call[1]=='draw:AddRectFilled' then background=call;
        end;
        assert(call[1]~='InvisibleButton' and call[1]~='Begin' and call[1]~='Dummy','Size labels cannot capture input or change layout.');
    end;
    assert(names==1 and dimensions==1,'The identity and live dimensions must both remain readable: '..label..' / '..expected);
    assert(clips==0 and #MOCK.font_stack==0 and equal(rect,before));
    assert(background and background[2][1]>=0 and background[2][2]>=0
        and background[3][1]<=MOCK.screen[1] and background[3][2]<=MOCK.screen[2],'The badge stays inside the viewport.');
end;
MOCK.screen={1600,1000};
check({x=200,y=200,width=320,height=80},'Self buffs','320 x 80 px');
check({x=200,y=200,width=320,height=120},'Self buffs','320 x 120 px');
check({x=200,y=200,width=320,height=80},'Self buffs','320 x 80 px');
check({x=0,y=0,width=100.49,height=90.5},'Target frame','100 x 91 px');
check({x=1500,y=975,width=24,height=24},'Self debuffs','24 x 24 px');
for _,label in ipairs({'Target timers','Party timers','Watched enemy timers','Spell recasts','Ability recasts','Item recasts',
    'Combined recasts','Party frame','Alliance 1 frame','Alliance 2 frame','Party + alliance frames','Alliance 1 strip',
    'Alerts','Vantage settings'})do
    check({x=200,y=200,width=320,height=80},label,'320 x 80 px');
end;
for _,edge in ipairs({'left','right','top','bottom','top_left','top_right','bottom_left','bottom_right'})do
    local r=resize.rect({x=200,y=200,width=320,height=80},edge,20,10,{screen_width=1600,screen_height=1000});
    local w=edge:find('left',1,true) and 300 or edge:find('right',1,true) and 340 or 320;
    local h=edge:find('top',1,true) and 70 or edge:find('bottom',1,true) and 90 or 80;
    check(r,'Self buffs',('%d x %d px'):format(w,h));
end;
check({x=200,y=200,width=640,height=160},'Target frame','640 x 160 px');
check({x=200,y=200,width=240,height=60},'Target frame','240 x 60 px');
MOCK.imgui_calls={};
resize.label(imgui.GetWindowDrawList(),{x=1700,y=0,width=320,height=80},'Self buffs',{});
for _,call in ipairs(MOCK.imgui_calls)do
    assert(not call[1]:find('draw:',1,true) and call[1]~='PushFont','Offscreen displays do not leave floating dimensions.');
end;
