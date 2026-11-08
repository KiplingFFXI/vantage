local overlay,defaults=require('ui.native_party_hud'),require('ui.party_defaults');
local hud,layout,imgui=require('ui.party_hud'),require('ui.party_layout'),require('imgui');
local store=require('core.store');
local p,roster,subjects,geometry,callbacks,starts,ends,saves;
local mx,my,down,pressed,active,item,cursor=-1,-1,false,false,nil,nil,{};
imgui.GetMousePos=function() return mx,my;end;
imgui.IsMouseDown=function() return down;end;
imgui.SetCursorScreenPos=function(value) cursor=value;end;
imgui.InvisibleButton=function(id,size)
    item=id;
    if pressed and mx>=cursor[1] and mx<cursor[1]+size[1] and my>=cursor[2] and my<cursor[2]+size[2] then active=id;end;
end;
imgui.IsItemActivated=function() return pressed and item==active;end;
imgui.IsItemActive=function() return down and item==active;end;
local function fresh()
    overlay.cancel_layout_gesture();p=defaults.make();p.enabled=true;p.locked=false;p.effects.max=32;
    p.native.width,p.native.snap=420,false;
    roster,subjects=hud.sample(6,100);geometry={available=true,groups={}};
    local frame={x=700,y=100,width=116,height=132,rows={}};
    for _,member in ipairs(roster.members) do
        frame.rows[member.slot]={x=700,y=100+member.slot*22,width=116,height=22};
        subjects[member.id].effects={};subjects[member.id].known=true;
        for effect=1,32 do subjects[member.id].effects[effect]={effect=effect,name='A long effect caption '..effect,
            kind='buff',remaining=30,total=60,status='estimated'};end;
    end;
    geometry.groups[1]=frame;starts,ends,saves=0,0,0;
    callbacks={shift=true,native_geometry=geometry,begin_edit=function() starts=starts+1;end,
        end_edit=function() ends=ends+1;end,changed=function() saves=saves+1;end};
    mx,my,down,pressed,active,item=-1,-1,false,false,nil,nil;MOCK.screen={1600,900};
end;
local function plan() return overlay.plan(roster,subjects,p,geometry,1600,900)[1];end;
local function draw() return overlay.draw(roster,subjects,p,100,callbacks);end;
local function start(edge)
    local rect=plan();
    mx=edge:find('left',1,true) and rect.x+1 or edge:find('right',1,true) and rect.x+rect.width-1 or rect.x+rect.width/2;
    my=edge:find('top',1,true) and rect.y+1 or edge:find('bottom',1,true) and rect.y+rect.height-1 or rect.y+rect.height/2;
    down,pressed=true,true;draw();pressed=false;return rect;
end;
local function release() down=false;draw();end;
-- A panel of its own where the attached strip was drawn.
local function detach()
    local rect=plan();local group=p.groups[1];
    group.native_detached,group.detached_x,group.detached_y,group.detached_width,group.detached_height=true,rect.x,rect.y,rect.width,rect.height;
end;
for _,edge in ipairs({'left','right','top','bottom','top_left','top_right','bottom_left','bottom_right'}) do
    -- An attached strip's edge only moves it: it stays beside the game's rows, at its size.
    fresh();local native_before=store.copy(geometry);local options_before=store.copy(p.native);local first=start(edge);
    local horizontal,vertical=require('ui.resize').axes(edge);
    local dx,dy=horizontal and (edge:find('left',1,true) and -30 or 30) or 0,vertical and (edge:find('top',1,true) and -20 or 20) or 0;
    mx,my=mx+dx,my+dy;draw();release();
    local last=plan();
    assert(not last.detached and not p.groups[1].native_detached,'An attached edge drag never detaches: '..edge);
    assert(p.groups[1].native_x==dx and p.groups[1].native_y==dy and last.width==first.width and last.height==first.height,
        'An attached edge drag moves the strip at its size: '..edge);
    assert(starts==1 and ends==1 and saves==1,'A move produces one history/save gesture');
    assert(store.equal(geometry,native_before) and store.equal(p.native,options_before),
        'Native geometry and the saved attachment behavior stay unchanged');
    -- A panel of its own resizes from the same edge and wraps every selected effect.
    fresh();detach();native_before=store.copy(geometry);options_before=store.copy(p.native);first=start(edge);
    mx,my=mx+dx,my+dy;draw();release();
    last=plan();
    assert(last.detached and p.groups[1].native_detached,'A panel of its own stays one: '..edge);
    assert(last.width==first.width+(horizontal and 30 or 0) and last.height==first.height+(vertical and 20 or 0));
    assert(starts==1 and ends==1 and saves==1,'A resize produces one history/save gesture');
    assert(store.equal(geometry,native_before) and store.equal(p.native,options_before),
        'Native geometry and the saved attachment behavior stay unchanged');
    assert(not p.groups[2].native_detached and not p.groups[3].native_detached,'Only the selected member group is a panel');
    local row=last.rows[1];local effects=layout.effects(subjects[row.member.id],row.options);
    local cells,hidden=layout.effect_cells(effects,row.options,row.area);
    assert(#cells==32 and hidden==0 and cells[#cells].y>cells[1].y,'The resized panel wraps all selected effects');
end;
fresh();start('right');my=my+40;draw();release();
assert(not p.groups[1].native_detached and p.groups[1].native_x==0 and p.groups[1].native_y==40 and saves==1,
    'Down from the right edge moves an attached strip down.');
fresh();start('left');draw();release();assert(not p.groups[1].native_detached and starts==0 and saves==0);
fresh();start('center');mx,my=mx+10,my+15;draw();release();
assert(not p.groups[1].native_detached and p.groups[1].native_x==10 and p.groups[1].native_y==15 and saves==1);
for _,block in ipairs({'locked','typing','input','shift'}) do
    fresh();if block=='locked' then p.locked=true elseif block=='typing' then roster.typing=true
    elseif block=='input' then callbacks.input_blocked=true else callbacks.shift=false end;
    local before=store.copy(p);start('right');mx=mx+30;draw();release();
    assert(store.equal(p,before) and starts==0 and saves==0,'Blocked resizing stays inert: '..block);
end;
fresh();local first=start('right');local origin=mx;mx=mx+30;draw();mx=origin;draw();release();
assert(not p.groups[1].native_detached and p.groups[1].native_x==0 and plan().width==first.width and saves==1,
    'Reversing a move ends where it started, as one completed edit');
fresh();detach();first=start('right');origin=mx;mx=mx+30;draw();mx=origin;draw();release();
assert(p.groups[1].native_detached and plan().width==first.width and saves==1,'Reversing a resize preserves the one completed wrapping edit');
assert(#MOCK.font_stack==0 and #MOCK.commands==0);
