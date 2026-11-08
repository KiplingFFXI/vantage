local defaults,party=require('ui.defaults'),require('ui.party_defaults');
local hud,layout,ordering=require('ui.hud'),require('ui.party_layout'),require('core.effect_order');
local copy,equal=require('core.store').copy,require('core.customization').equal;
local panel_ids={'self_buffs','self_debuffs','party','target','watch'};

local function effect(id,name,remaining,first_seen)
    local known=type(remaining)=='number' and remaining==remaining and remaining>=0 and remaining<math.huge;
    return {effect=id,key='effect:'..id,name=name,remaining=remaining,deadline=known and 1000+remaining or nil,
        first_seen=first_seen or id,first_sequence=id,present=true,kind='buff',status=known and 'server' or 'unknown',
        entity_id=1001,entity_name='Tester',scope='self'};
end;
local function expect(rows,expected,message)
    assert(#rows==#expected,message..' (count)');
    for index,row in ipairs(rows) do assert(row==expected[index],message..' (position '..index..')');end;
end;
local signet,short,medium=effect(253,'Signet',14400,1),effect(41,'Shell',57,2),effect(40,'Protect',180,3);
local subject={known=true,effects={signet,short,medium}};
local expected={signet,medium,short};
local settings=defaults.make();
local view={valid=true,context={id=1001,target={id=1001}},rows=subject.effects};
local options=settings.party_ui.effects;
assert(options.sort=='longest');
expect(layout.effects(subject,options),expected,'The screenshot order becomes 4h, 3m, 57s.');
expect(layout.effects(subject,{}),expected,'An omitted sort uses the same longest-first default.');
for _,key in ipairs(panel_ids) do
    assert(settings.panels[key].sort=='longest','Every status panel defaults to most time remaining first.');
    for _,row in ipairs(view.rows) do row.scope=key=='party' and 'party' or 'self';row.kind=key=='self_debuffs' and 'debuff' or 'buff';end;
    settings.watch_ids={1001};
    expect(hud.filter_rows(view,settings.panels[key],key,settings),expected,'Every status panel orders known durations longest first.');
end;
for _,row in ipairs(view.rows) do row.scope,row.kind='self','buff';end;
for key in pairs(defaults.recast_panels) do assert(settings.panels[key].sort=='remaining','Cooldown ordering is unchanged.');end;

local strip=party.make().effects;
expect(layout.effects(subject,strip),expected,'The party list buffs share the duration order.');
strip.sort='oldest';
expect(layout.effects(subject,strip),{signet,short,medium},'Chronological oldest-first remains an independent choice.');
strip.sort='remaining';
expect(layout.effects(subject,strip),{short,medium,signet},'Ending-soonest sorting remains available.');

local invalid={effect(269,'Level sync',999999),effect(500,'Unknown',nil),effect(501,'Negative',-1),
    effect(502,'Infinity',math.huge),effect(503,'Not a number',0/0),effect(504,'Text','100'),effect(505,'Negative infinity',-math.huge)};
local zero=effect(506,'Zero',0);
for _,row in ipairs(invalid) do
    assert(ordering.longest(short,row)==true and ordering.longest(row,short)==false,
        'Unknown, invalid and Level Sync timers sort after known durations.');
    assert(ordering.longest(zero,row)==true,'Zero is still a known nonnegative duration.');
end;
assert(ordering.longest(invalid[1],invalid[2])==nil,'Level Sync receives no invented duration.');
assert(ordering.longest(short,effect(507,'Same time',57))==nil,'Equal times use the existing stable fallback.');
local unknown_subject={known=true,effects={invalid[1],short,invalid[2],medium,invalid[3],signet,invalid[4],invalid[5],invalid[6],invalid[7],zero}};
local chosen=layout.effects(unknown_subject,options);
assert(#chosen==11 and chosen[1]==signet and chosen[2]==medium and chosen[3]==short and chosen[4]==zero,
    'Invalid times never enter the known-duration portion of a party strip.');
view.rows=unknown_subject.effects;
chosen=hud.filter_rows(view,settings.panels.self_buffs,'self_buffs',settings);
assert(#chosen==11 and chosen[1]==signet and chosen[2]==medium and chosen[3]==short and chosen[4]==zero,
    'Invalid times never enter the known-duration portion of a status panel.');
local deadline_only=effect(508,'No known remaining time',nil);deadline_only.deadline=999999;
assert(ordering.longest(short,deadline_only),'The comparator does not infer a duration from a deadline without the current time.');

view.rows=subject.effects;
local source_before=copy(subject);
options.max,options.fit_all=2,false;
expect(layout.effects(subject,options),{signet,medium},'A count limit starts with the longest known timers.');
short.remaining,short.deadline=20000,21000;
expect(layout.effects(subject,options),{short,signet},'A refreshed timer outside the cached visible subset can move to the front.');
short.remaining,short.deadline=100,1100;
expect(layout.effects(subject,options),{signet,medium},'A shorter update restores the correct cached visible subset.');
options.max,options.fit_all=12,true;
expect(layout.effects(subject,options),{signet,medium,short},'Removing the limit restores every effect in duration order.');
medium.remaining,medium.deadline=50,1050;
expect(layout.effects(subject,options),{signet,short,medium},'A remaining-time-only change invalidates a stale cached order.');
expect(hud.filter_rows(view,settings.panels.self_buffs,'self_buffs',settings),{signet,short,medium},
    'Separate panels immediately reflect refreshed remaining times.');
short.remaining,short.deadline=57,1057;medium.remaining,medium.deadline=180,1180;
assert(equal(subject,source_before),'Selection never mutates effect metadata or the source array.');
options.pinned={41};expect(layout.effects(subject,options),{short,signet,medium},'Explicit pins retain priority.');
options.pinned={};options.exclude={253};
expect(layout.effects(subject,options),{medium,short},'Filtering preserves duration order.');
options.exclude={};
local panel=settings.panels.self_buffs;
panel.pinned={41};expect(hud.filter_rows(view,panel,'self_buffs',settings),{short,signet,medium},'Separate-panel pins retain priority.');
panel.pinned={};panel.sort='fixed';panel.order={40,41,253};
expect(hud.filter_rows(view,panel,'self_buffs',settings),{medium,short,signet},'Separate-panel custom ordering remains available.');
panel.sort='longest';panel.order={};

local rows={signet,medium,short,effect(42,'Twenty seconds',20),effect(43,'Ten seconds',10),
    effect(269,'Level sync',nil),effect(500,'Unknown duration',nil)};
subject.effects={rows[7],rows[3],rows[6],rows[4],rows[2],rows[5],rows[1]};
for _,side in ipairs({'left','right'}) do
    local config=party.make();
    config.effects.icon_size=24;
    local area={x=40,y=60,width=86,height=900,align_right=side=='left'};
    local selected=layout.effects(subject,config.effects);
    expect(selected,rows,'The side the strip sits on does not change duration sorting.');
    local positions={};
    for _,growth in ipairs({'right','left'}) do
        config.effects.growth=growth;
        local cells,hidden=layout.effect_cells(selected,config.effects,area);
        assert(#cells==7 and hidden==0 and cells[7].y>cells[1].y,'Both directions wrap all selected effects.');
        for index,cell in ipairs(cells) do
            assert(cell.effect==rows[index],'Following the chosen growth direction traverses longest to shortest.');
            if index>1 and cell.y==cells[index-1].y then
                assert(growth=='left' and cell.x<cells[index-1].x or growth=='right' and cell.x>cells[index-1].x);
            end;
        end;
        positions[growth]=cells;
    end;
    -- Each row keeps against the side nearest the game's rows, so a row mirrors within its own width.
    local first,last={},{};
    for _,cell in ipairs(positions.right) do
        first[cell.y],last[cell.y]=math.min(first[cell.y] or cell.x,cell.x),math.max(last[cell.y] or cell.x,cell.x+cell.width);
    end;
    for index,cell in ipairs(positions.right) do
        assert(cell.y==positions.left[index].y and math.abs(cell.x+positions.left[index].x+cell.width-(first[cell.y]+last[cell.y]))<.001,
            'Mirroring preserves the same longest-first traversal and wrapping.');
    end;
end;

local fonts=require('ui.fonts');
fonts.measure=function(_,text,size)return #text*size*.5;end;
fonts.draw=function()return false;end;
require('ui.icons').status=function(id)return 100000+id;end;
require('ui.recast_icons').draw=function(list,row,_,x,y,size)
    list:AddImage(100000+row.effect,{x,y},{x+size,y+size});return true;
end;
MOCK.screen={1600,1000};
view.rows=subject.effects;
for _,mode in ipairs({'bars','expanded','icons'}) do
    for _,stack in ipairs({'horizontal','vertical'}) do
        settings=defaults.make();
        settings.style.font,settings.style.font_size='Original FFXI',12;
        settings.style.scale,settings.style.gap,settings.style.bar_height,settings.style.icon_size=1,4,36,24;
        settings.style.minimal=true;
        for id,p in pairs(settings.panels) do p.enabled=id=='self_buffs';end;
        panel=settings.panels.self_buffs;
        panel.mode,panel.stack_direction,panel.item_width=mode,stack,180;
        panel.x,panel.y,panel.width=100,100,mode=='icons' and 160 or 640;
        panel.auto_width,panel.auto_height,panel.height_limit=false,false,mode=='icons' and 100 or mode=='expanded' and 240 or 180;
        panel.wrap,panel.locked,panel.show_heading,panel.show_target,panel.show_source=true,true,false,false,false;
        for _,growth in ipairs({'right','left'}) do
            panel.growth=growth;
            local saved=copy(settings);
            MOCK.imgui_calls={};
            hud.draw(view,settings,100,{shift=false});
            local pictures={};
            for _,call in ipairs(MOCK.imgui_calls) do
                if call[1]=='draw:AddImage' and type(call[2])=='number' and call[2]>=100000 then
                    local at=MOCK.drawn[call][3];
                    pictures[#pictures+1]={id=call[2]-100000,x=at[1],y=at[2]};
                end;
            end;
            assert(#pictures==7,'Every panel mode displays the full duration-sorted selection.');
            for index,picture in ipairs(pictures) do assert(picture.id==rows[index].effect,'Drawn status icons follow longest first.');end;
            if stack=='horizontal' then
                assert(pictures[7].y>pictures[1].y,'Horizontal panels wrap down.');
                assert(growth=='left' and pictures[2].x<pictures[1].x or growth=='right' and pictures[2].x>pictures[1].x);
            else
                assert(pictures[2].x==pictures[1].x and pictures[2].y>pictures[1].y,'Vertical panels fill downward in duration order.');
                assert(growth=='left' and pictures[7].x<pictures[1].x or growth=='right' and pictures[7].x>pictures[1].x,
                    'Additional columns follow the selected growth direction.');
            end;
            assert(equal(settings,saved),'Drawing preserves selected sizes, settings and locks.');
        end;
    end;
end;
assert(#MOCK.commands==0,'Sorting never sends gameplay commands.');
return 'Longest duration first across status panels and frames, with unknown timers last and correct mirrored wrapping';
