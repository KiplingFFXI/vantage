local defaults,hud=require('ui.defaults'),require('ui.hud');
local custom,store=require('core.customization'),require('core.store');
local imgui,fonts,countdown=require('imgui'),require('ui.fonts'),require('ui.countdown_text');
local timers,gauges={},{ };
fonts.measure=function(_,text,size)return #text*size*.5;end;
fonts.draw=function()return false;end;
require('ui.icons').status=function(id)return 100000+id;end;
require('ui.recast_icons').draw=function(list,row,_,x,y,size)
    list:AddImage(100000+row.effect,{x,y},{x+size,y+size});return true;
end;
require('ui.client_skin').gauge=function(_,x,y,width,height,fraction,style,panel)
    gauges[#gauges+1]={x=x,y=y,width=width,height=height,fraction=fraction,fill=panel.fill_direction,font=style.font};return false;
end;
countdown.draw=function(_,font,text,x,y,size)
    timers[#timers+1]={font=font,text=text,x=x,y=y,size=size};
end;
MOCK.screen={1600,1000};
local function setup(mode,stack,key,face)
    local s=defaults.make();
    s.recast_display=key=='recasts' and 'combined' or 'separate';
    s.style.font,s.style.font_size,s.style.icon_size=face,12,24;
    s.style.scale,s.style.gap,s.style.bar_height=1,4,36;
    s.style.minimal=true;
    for id,p in pairs(s.panels)do p.enabled=id==key;end;
    local p=s.panels[key];
    p.mode,p.stack_direction,p.sort,p.item_width=mode,stack,'fixed',180;
    p.x,p.y,p.width=100,100,mode=='icons' and 160 or 640;
    p.auto_width,p.auto_height,p.height_limit,p.max_rows=false,false,mode=='icons' and 100 or mode=='expanded' and 240 or 180,32;
    p.wrap,p.locked,p.show_heading,p.show_target,p.show_source=true,true,false,false,false;
    p.fill_direction,p.direction='left','fill';
    local view={valid=true,context={id=1001,target={id=1001}},rows={}};
    s.watch_ids={1001};
    for index=1,7 do
        local id=index==3 and 269 or index+39;
        local row={key='row'..index,effect=id,name='Effect '..index,entity_id=1001,present=true,
            scope=key=='party' and 'party' or 'self',kind=key=='self_debuffs' and 'debuff' or 'buff',
            status=(index==3 or index==4) and 'unknown' or 'server'};
        if row.status~='unknown' then row.deadline,row.total=200+index,300;end;
        if defaults.recast_panels[key] then
            row.domain,row.scope,row.kind='recast','recast',defaults.recast_panels[key]=='all' and 'spell' or defaults.recast_panels[key];
        end;
        view.rows[index],p.order[index]=row,id;
    end;
    return s,p,view;
end;
local function draw(s,view,callbacks,now)
    MOCK.imgui_calls,timers,gauges={},{},{};
    hud.draw(view,s,now or 100,callbacks or {shift=false});
    local pictures,texts={},{};
    for _,call in ipairs(MOCK.imgui_calls)do
        local values=MOCK.drawn[call];
        if call[1]=='draw:AddImage' and type(call[2])=='number' and call[2]>=100000 then
            pictures[#pictures+1]={id=call[2]-100000,x=values[3][1],y=values[3][2],
                width=values[4][1]-values[3][1],height=values[4][2]-values[3][2]};
        elseif call[1]=='draw:AddText' then texts[call[6]]={x=values[4][1],y=values[4][2]};end;
    end;
    return pictures,store.copy(timers),store.copy(gauges),texts;
end;
local function close(a,b,message)assert(math.abs(a-b)<.001,message);end;
for _,mode in ipairs({'bars','expanded','icons'})do
    for _,stack in ipairs({'horizontal','vertical'})do
        for _,key in ipairs(defaults.panel_order)do
            for _,face in ipairs({'Original FFXI','XI View'})do
                local s,p,view=setup(mode,stack,key,face);
                local rows=store.copy(hud.filter_rows(view,p,key,s));
                local right,rt,rg,rtext=draw(s,view);
                p.growth='left';
                local saved=store.copy(s);
                local left,lt,lg,ltext=draw(s,view);
                assert(#right==7 and #left==7,mode..' '..stack..' '..key..' fits all seven effects in both growth directions');
                assert(custom.equal(s,saved) and custom.equal(rows,hud.filter_rows(view,p,key,s)),
                    'Changing growth never mutates settings, locks, sorting, filters, or tracker rows');
                assert(#rt==#lt and #rg==#lg,'Growth keeps the same text and gauge coverage');
                local cell_width=mode=='icons' and 24 or rg[1].width+29;
                for index,a in ipairs(right)do
                    local b=left[index];
                    assert(a.id==b.id and a.id==view.rows[index].effect,'The chosen effect order stays intact');
                    assert(b.width==24 and b.height==24 and b.y==a.y,'Icons retain their size and row when mirrored');
                    close(a.x+b.x,2*p.x+p.width-cell_width,'Cells mirror around the existing wrapping area');
                    assert(b.x>=p.x and b.x+b.width<=p.x+p.width and b.y>=p.y and b.y+b.height<=p.y+p.height_limit,
                        'Wrapped icons remain inside the panel');
                    if mode~='icons' then
                        close(lg[index].x-rg[index].x,b.x-a.x,'The gauge moves with the cell instead of reversing its fill');
                        close(lg[index].width,rg[index].width,'Mirroring keeps the same measured gauge width');
                        assert(lg[index].height==rg[index].height and lg[index].fraction==rg[index].fraction and lg[index].fill=='left'
                            and lg[index].font==face,'Gauge appearance and its independently selected fill direction stay intact');
                        local name='Effect '..index;
                        if rtext[name] and ltext[name] then
                            close(ltext[name].x-rtext[name].x,b.x-a.x,'Text remains in the same position within its own cell');
                        end;
                    end;
                end;
                for index,a in ipairs(rt)do
                    local b=lt[index];
                    assert(a.text==b.text and a.font==b.font and a.size==b.size and a.y==b.y,
                        'Countdown wording, font, size, and vertical position are unchanged');
                    assert(not b.text:find('?',1,true),'Unknown durations never receive question marks');
                end;
                if stack=='horizontal' then
                    assert(left[2].x<left[1].x and left[2].y==left[1].y,'Horizontal right-to-left fills toward the left');
                    assert(left[7].y>left[1].y,'A partial final horizontal row still wraps down');
                    local first_final;
                    for _,picture in ipairs(left)do if picture.y==left[7].y then first_final=picture;break;end;end;
                    assert(first_final.x==left[1].x,'A partial final row starts at the right edge');
                else
                    assert(left[2].x==left[1].x and left[2].y>left[1].y,'Vertical stacking still fills downward');
                    assert(left[7].x<left[1].x,'Further vertical columns grow toward the left');
                    local first_final;
                    for _,picture in ipairs(left)do if picture.x==left[7].x then first_final=picture;break;end;end;
                    assert(first_final.y==left[1].y,'A partial final column starts at the top');
                end;
                p.exclude[view.rows[2].effect]=true;
                local filtered=draw(s,view);
                assert(#filtered==6 and filtered[2].id==view.rows[3].effect,'Filtering still removes only selected effects');
                p.max_rows=2;
                assert(#draw(s,view)==2,'Growth keeps explicit visible-effect limits');
            end;
        end;
    end;
end;

for _,mode in ipairs({'bars','expanded','icons'})do
    for _,stack in ipairs({'horizontal','vertical'})do
        for _,automatic in ipairs({false,true})do
            local s,p,view=setup(mode,stack,'self_buffs','XI View');
            p.auto_width,p.auto_height=automatic,automatic;
            p.max_rows=32;
            local right=draw(s,view);
            p.growth='left';
            local left=draw(s,view);
            assert(#left==#right and #left>0,'Automatic sizing has identical capacity in both growth directions');
            for index,picture in ipairs(left)do assert(picture.id==right[index].id and picture.y==right[index].y);end;
        end;
    end;
end;

for _,mode in ipairs({'bars','expanded','icons'})do
    local s,p,view=setup(mode,'horizontal','self_buffs','XI View');p.growth='left';
    local pictures=draw(s,view);
    MOCK.mouse_x,MOCK.mouse_y=pictures[1].x+12,pictures[1].y+12;
    draw(s,view,nil,100);draw(s,view,nil,100.4);
    local found=false;
    for _,call in ipairs(MOCK.imgui_calls)do
        if call[1]=='TextUnformatted' and tostring(call[2]):find('Effect 1',1,true) then found=true;end;
    end;
    assert(found,'Hover details follow the effect at its mirrored cell position');
    MOCK.mouse_x,MOCK.mouse_y=-1,-1;
end;

local clicked=false;
imgui.IsItemHovered=function()return true;end;
imgui.IsMouseClicked=function()local result=clicked;clicked=false;return result;end;
for _,mode in ipairs({'bars','expanded','icons'})do
    for _,stack in ipairs({'horizontal','vertical'})do
        for _,locked in ipairs({true,false})do
            local s,p,view=setup(mode,stack,'self_buffs','XI View');p.growth,p.locked='left',locked;
            local original=store.copy(p);local saves=0;
            local cb={shift=true,changed=function()end,save=function()saves=saves+1;end};
            hud.cancel_gesture();
            MOCK.mouse_x,MOCK.mouse_y,MOCK.mouse_down,clicked=p.x+p.width-1,p.y+p.height_limit-1,true,true;
            draw(s,view,cb);MOCK.mouse_x,MOCK.mouse_y=MOCK.mouse_x+50,MOCK.mouse_y+60;draw(s,view,cb);
            MOCK.mouse_down=false;draw(s,view,cb);
            if locked then assert(custom.equal(p,original) and saves==0,'Shift cannot bypass a saved lock');
            else
                assert(p.width==original.width+50 and p.height_limit==original.height_limit+60 and saves==1,
                    'Unlocked Shift corner resize keeps both axes available');
                assert(p.growth=='left' and p.stack_direction==stack and p.wrap and s.style.icon_size==24,
                    'Resize keeps selected growth, stacking, icon size, and wrapping');
            end;
        end;
    end;
end;
MOCK.mouse_x,MOCK.mouse_y,MOCK.mouse_down=-1,-1,false;
imgui.IsItemHovered=function()return false;end;imgui.IsMouseClicked=function()return false;end;

local s=defaults.make();
for _,id in ipairs(defaults.panel_order)do assert(s.panels[id].growth=='right');s.panels[id].growth=nil;end;
s=defaults.tidy(s);
for _,id in ipairs(defaults.panel_order)do assert(s.panels[id].growth=='right','Legacy panels default to left-to-right');end;
s.panels.self_buffs.growth,s.panels.recasts.growth='left','left';
s.panels.self_debuffs.growth='invalid';s=defaults.tidy(s);
assert(s.panels.self_buffs.growth=='left' and s.panels.recasts.growth=='left' and s.panels.self_debuffs.growth=='right');
assert(custom.equal(defaults.tidy(store.copy(s)),s),'Growth normalization is stable across reloads');
local profiles=require('core.profiles').new(MOCK_INSTALL_PATH..'/config/addons/vantage/timer-growth');
assert(profiles:save_new('Growing left',s));
local receiver=defaults.make();assert(profiles:load('Growing left',receiver));
assert(receiver.panels.self_buffs.growth=='left' and receiver.panels.recasts.growth=='left','Named profiles retain panel growth');
assert(profiles:save_layout(s,'placement'));receiver=defaults.make();assert(profiles:load_layout(receiver,'placement'));
assert(receiver.panels.self_buffs.growth=='left' and receiver.panels.recasts.growth=='left','Shared placement includes growth');
custom.reset(receiver,'layouts');assert(receiver.panels.self_buffs.growth=='right' and receiver.panels.recasts.growth=='right');
custom.reset(s,'self_buffs');assert(s.panels.self_buffs.growth=='right' and s.panels.recasts.growth=='left','Panel reset stays scoped');

local window=require('ui.settings_window');
local panels=require('ui.panel_frame');
local editor=defaults.make();editor.window.open,editor.window.tab,editor.recast_display=true,'Display','combined';
imgui.BeginCombo=function(label)return label=='##frame_Fills';end;
local cb={changed=function()end,save=function()return true;end,now=function()return 100;end};
for _,id in ipairs({'self_buffs','recasts'})do
    local found=false;
    for _,result in ipairs(window.search('Growth direction'))do
        if result.tab=='Display' and result.label=='Fills' and result.panel==id then found=true;end;
    end;
    assert(found,'Growth direction is searchable before opening '..id);
    local p=editor.panels[id];
    p.fill_direction,p.direction,p.show_name,p.show_heading,p.stack_direction='left','fill',false,false,'vertical';
    p.field_labels.name,p.colors.track='My timer',{.1,.2,.3,.4};
    panels.open(id,'place');
    for _,growth in ipairs({'left','right'})do
        local before=store.copy(p);
        MOCK.clicks[growth=='left' and 'Down, then to the left##down_left' or 'Down, then to the right##down_right']=true;
        window.draw(editor,hud.sample(100),cb);before.growth=growth;
        assert(p.growth==growth and custom.equal(p,before),'The growth control preserves every other customization');
        assert(#MOCK.font_stack==0);
    end;
end;

package.loaded['core.client']={read=function()return {valid=true,id=1001,name='Tester',zone=102,job=1,job_name='WAR',
    self_known=true,self_effects={},party={},entities={}};end,load=function()end};
package.loaded['core.observer']={read=function()return {};end};
local app=dofile(ADDON_DIR..'/vantage.lua');MOCK.fire('load');app.refresh(1);
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
command('/vg set panels.self_buffs.growth left');assert(app.state.settings.panels.self_buffs.growth=='left');
command('/vg undo');assert(app.state.settings.panels.self_buffs.growth=='right','Undo restores growth');
command('/vg redo');assert(app.state.settings.panels.self_buffs.growth=='left','Redo restores growth');
assert(#MOCK.commands==0,'Growth controls never issue gameplay commands');
return 'Timer cells wrap toward either side while preserving order, appearance, placement locks, and saved customization';
