local imgui,hud,defaults=require('imgui'),require('ui.hud'),require('ui.defaults');
local countdown,fonts=require('ui.countdown_text'),require('ui.fonts');
local copy,equal=require('core.store').copy,require('core.customization').equal;
require('ui.icons').prepare();require('ui.recast_icons').prepare();
local sets,active={},nil;
for column,spec in ipairs({{'Original FFXI',false},{'Original FFXI',true},{'XI View',false},{'XI View',true}}) do
    for row,size in ipairs({16,24,32,24}) do
        local s=defaults.make();require('original_skin_fixture')(s);
        local key=spec[2] and 'recasts' or 'watch';
        s.enabled,s.preview,s.recast_display,s.watch_ids=true,false,'combined',{1001};
        s.style.font,s.style.icon_art,s.style.recast_icon_art=spec[1],spec[1],spec[1];
        s.style.icon_size,s.style.minimal,s.style.scale=size,true,1;
        for id,p in pairs(s.panels) do p.enabled=id==key;end;
        local p=s.panels[key];
        p.mode,p.x,p.y,p.width,p.height_limit='icons',20+(column-1)*290,80+(row-1)*125,270,94;
        p.stack_direction,p.wrap,p.show_heading,p.show_name,p.sort='horizontal',true,false,false,'fixed';
        p.icon_countdown_position,p.icon_countdown_size,p.icon_countdown_gap='below',row==4 and 14 or 0,row==4 and 3 or 0;
        p.countdown_bold,p.countdown_shadow,p.countdown_outline=row==2,true,row>=3;
        p.blink_icons=false;
        local effects=spec[2] and {
            {effect=10004,name='Cure IV',kind='spell',spell_id=4,list_icon_hq=89,list_icon_nq=6},
            {effect=10057,name='Haste',kind='spell',spell_id=57,list_icon_hq=143,list_icon_nq=2},
            {effect=20005,name='Provoke',kind='ability',ability_id=547,list_icon_id=360,ability_element=41},
            {effect=45762,name='Empress Band',kind='item',item_id=15762},
        } or {
            {effect=33,name='Haste',kind='buff'},{effect=40,name='Protect',kind='buff'},
            {effect=3,name='Poison',kind='debuff'},{effect=269,name='Level Sync',kind='other'},
        };
        for index,e in ipairs(effects) do
            local remaining=({720,540,59})[index];
            e.key,e.entity_id,e.scope,e.present='compact_'..index,1001,'self',true;
            e.status,e.remaining,e.deadline,e.total=remaining and 'server' or 'unknown',remaining,remaining and 100+remaining,remaining;
            if spec[2] then e.domain='recast';end;
            p.order[index]=e.effect;
        end;
        sets[#sets+1]={s=s,p=p,face=spec[1],domain=spec[2] and 'Recasts' or 'Status timers',size=size,
            label=row==4 and '24px / timer 14px / gap 3' or size..'px / auto timer / gap 0',
            view={valid=true,context={id=1001},rows=effects},before=copy(s)};
    end;
end;
local original_draw=countdown.draw;
local function near(a,b,message)
    local context=active and (active.face..' / '..active.domain..' / '..active.label..': ') or '';
    assert(math.abs(a-b)<0.001,context..message..' actual='..tostring(a)..' expected='..tostring(b));
end;
local recast_icons=require('ui.recast_icons');
local original_recast=recast_icons.draw;
recast_icons.draw=function(list,row,artwork,x,y,size,opacity)
    if not active then return original_recast(list,row,artwork,x,y,size,opacity);end;
    local first=#PREVIEW_PY.all_runs();
    local painted=original_recast(list,row,artwork,x,y,size,opacity);
    assert(painted,'The real recast artwork must be available: '..row.name);
    local parts=0;local runs=PREVIEW_PY.all_runs();
    for index=first+1,#runs do
        local part=runs[index];
        if part.kind=='image' then
            parts=parts+1;
            assert(part.x>=x-.001 and part.y>=y-.001 and part.x+part.width<=x+size+.001 and part.y+part.height<=y+size+.001,
                'Every recast artwork part stays inside its requested square.');
        end;
    end;
    assert(parts>0,'The production recast renderer emitted actual icon pixels.');
    active.last_icon={x=x,y=y,width=size,height=size};
    active.recast_count=active.recast_count+1;
    return painted;
end;
countdown.draw=function(list,font,text,x,y,size,ink,options,compact)
    if not active then return original_draw(list,font,text,x,y,size,ink,options,compact);end;
    assert(compact and active.expected[text] and not active.seen[text],'Each known countdown is drawn once; unknown timers remain blank.');
    active.seen[text]=true;
    near(size,active.p.icon_countdown_size>0 and active.p.icon_countdown_size or active.size/2,'Timer size follows automatic or manual selection.');
    local previous=PREVIEW_PY.all_runs();local icon=active.domain=='Recasts' and active.last_icon or nil;
    if not icon then
        for index=#previous,1,-1 do
            if previous[index].texture then icon=previous[index];break;end;
        end;
    end;
    assert(icon,'The production renderer draws its icon before the timer.');
    near(icon.width,active.size,'The requested icon size is retained.');
    near(y,icon.y+icon.height+active.p.icon_countdown_gap,'Timer ink begins directly below its icon at the selected gap.');
    local result=original_draw(list,font,text,x,y,size,ink,options,compact);
    local runs=PREVIEW_PY.all_runs();local left,top,right,bottom;
    for index=#previous+1,#runs do
        local run=runs[index];
        assert(run.kind=='image','Native countdowns draw the selected bitmap glyphs.');
        left,top=math.min(left or run.x,run.x),math.min(top or run.y,run.y);
        right,bottom=math.max(right or run.x+run.width,run.x+run.width),math.max(bottom or run.y+run.height,run.y+run.height);
    end;
    local width,height=countdown.measure(font,text,size,options,true);
    near(left,math.floor(x+.5),'Actual glyph bounds start at the planned x.');
    near(top,math.floor(y+.5),'Actual glyph bounds have no transparent line-box gap.');
    near(right-left,width,'Actual styled glyph width matches the reserved width.');
    near(bottom-top,height,'Actual styled glyph height matches the reserved height.');
    assert(math.abs((left+right)/2-(icon.x+icon.width/2))<=.51,'Countdowns remain centered beneath their icons.');
    return result;
end;
local begin=imgui.Begin;
return function()
    for index,set in ipairs(sets) do
        assert(not fonts.failed(set.face),set.face..' must use its installed glyphs.');
        imgui.SetNextWindowPos({set.p.x,set.p.y-55},ImGuiCond_Always);
        imgui.SetNextWindowSize({280,52},ImGuiCond_Always);
        imgui.Begin('##compact_caption'..index,true,ImGuiWindowFlags_NoDecoration+ImGuiWindowFlags_NoInputs+ImGuiWindowFlags_NoBackground);
        imgui.TextUnformatted(set.face..' / '..set.domain);imgui.TextUnformatted(set.label);imgui.End();
        set.expected,set.seen={['12m']=true,['9m']=true,['59s']=true},{};
        set.recast_count,set.last_icon=0,nil;
        local first=#PREVIEW_PY.all_runs();
        active=set;imgui.Begin=function(name,...)return begin(name..'_compact_'..index,...);end;
        local ok,err=pcall(hud.draw,set.view,set.s,100,{shift=false});
        imgui.Begin,active=begin,nil;if not ok then error(err);end;
        assert(equal(set.seen,set.expected),'All three known timers remain visible.');
        local icons=0;local runs=PREVIEW_PY.all_runs();
        for at=first+1,#runs do
            local run=runs[at];
            if run.texture and run.width==set.size and run.height==set.size then icons=icons+1;end;
        end;
        assert((set.domain=='Recasts' and set.recast_count or icons)==4,
            'All four icons remain visible, including the effect or recast with an unknown duration.');
        assert(equal(set.s,set.before),'Rendering never changes frame settings, font choices, or locks.');
    end;
    PREVIEW.log('Compact production status and recast icons: both client fonts, 16/24/32px, exact ink gap, manual controls and unknown icons preserved.');
end;
