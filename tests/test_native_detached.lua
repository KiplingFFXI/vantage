local overlay, defaults = require('ui.native_party_hud'), require('ui.party_defaults');
local hud, layout, imgui = require('ui.party_hud'), require('ui.party_layout'), require('imgui');
local copy, equal = require('core.store').copy, require('core.customization').equal;
local p, roster, subjects, geometry, callbacks, starts, ends, saves;
local mx,my,pressed,down,active,item,cursor = -1,-1,false,false,nil,nil,{};
local position,dimensions,window,windows,flags = {},{},nil,{},{};
imgui.GetMousePos=function() return mx,my; end;
imgui.IsMouseDown=function() return down; end;
imgui.SetCursorScreenPos=function(value) cursor=value; end;
imgui.InvisibleButton=function(id,size)
    item=id;
    if pressed and mx>=cursor[1] and mx<cursor[1]+size[1] and my>=cursor[2] and my<cursor[2]+size[2] then active=id; end;
end;
imgui.IsItemActivated=function() return pressed and item==active; end;
imgui.IsItemActive=function() return down and item==active; end;
imgui.SetNextWindowPos=function(value) position=value; end;
imgui.SetNextWindowSize=function(value) dimensions=value; end;
imgui.Begin=function(id,_,options)
    window=id; flags[id]=options;
    windows[id]={x=position[1],y=position[2],width=dimensions[1],height=dimensions[2]}; return true;
end;
imgui.GetScrollY=function() return 0; end;
local function fresh(detached)
    overlay.cancel_layout_gesture();
    p=defaults.make(); p.enabled,p.locked,p.native.snap=true,false,false;
    roster,subjects=hud.sample(18,100);
    geometry={available=true,groups={}};
    for group=1,3 do
        local frame={x=1000,y=60+(group-1)*180,width=116,height=132,rows={}};
        for _,member in ipairs(roster.members) do if member.group==group then
            frame.rows[member.slot]={x=frame.x,y=frame.y+(member.slot%6)*22,width=116,height=22,slot=member.slot};
        end; end;
        geometry.groups[group]=frame;
    end;
    p.groups[1].native_detached=detached;
    p.groups[1].detached_x,p.groups[1].detached_y,p.groups[1].detached_width,p.groups[1].detached_height=200,150,300,240;
    starts,ends,saves=0,0,0;
    callbacks={shift=true,native_geometry=geometry,begin_edit=function() starts=starts+1; end,
        end_edit=function() ends=ends+1; end,changed=function() saves=saves+1; end,
        target=function() error('Native buff panels never target or own native game windows'); end};
    mx,my,pressed,down,active,item=-1,-1,false,false,nil,nil;
    MOCK.screen={1600,900};
    return p.groups[1];
end;
local function plans() return overlay.plan(roster,subjects,p,geometry,1600,900); end;
local function draw() return overlay.draw(roster,subjects,p,100,callbacks); end;
local function start(edge)
    local rect=plans()[1];
    mx=edge:find('left',1,true) and rect.x+1 or edge:find('right',1,true) and rect.x+rect.width-1 or rect.x+rect.width/2;
    my=edge:find('top',1,true) and rect.y+1 or edge:find('bottom',1,true) and rect.y+rect.height-1 or rect.y+rect.height/2;
    down,pressed=true,true; draw(); pressed=false; return rect;
end;
local function release() down,pressed=false,false; draw(); end;

local saved=fresh(true);
geometry.available=false;
assert(#plans()==1 and #plans()[1].rows==6,'Detached members do not depend on native geometry.');
local original=copy(p.effects);
p.effects.max=32;
for _,subject in pairs(subjects) do
    subject.effects={}; subject.known=true;
    for effect=1,32 do subject.effects[effect]={effect=effect,name='Effect '..effect,remaining=30,total=60,status='estimated',kind='buff'}; end;
end;
saved.detached_width=110;
local narrow=plans()[1]; saved.detached_width=700; local wide=plans()[1];
assert(narrow.content_height>wide.content_height,'Narrow panels create more wrapped rows.');
for index,row in ipairs(narrow.rows) do
    local effects=layout.effects(subjects[row.member.id],row.options);
    local cells,hidden=layout.effect_cells(effects,row.options,row.area);
    assert(#cells==32 and hidden==0,'All32 selected effects have layout space; viewport scrolls.');
    for _,cell in ipairs(cells) do assert(cell.y+cell.height<=row.area.y+row.area.height,'Cells stay inside their member row.'); end;
    if index>1 then assert(row.label_y>=narrow.rows[index-1].area.y+narrow.rows[index-1].area.height,'Member labels never overlap preceding effects.'); end;
end;
assert(p.effects.rows==nil and p.effects.wrap==nil,'Temporary wrapping writes no row limit into the saved settings.');
p.effects=original; p.include_self=false; assert(#plans()[1].rows==5);
p.include_self=true; roster.members[1].active=false; assert(#plans()[1].rows==5); roster.members[1].active=true;
p.strips.party=false; assert(#plans()==0); p.strips.party=true;
saved.detached_x,saved.detached_y=16000,16000;
local bounded=plans()[1]; assert(bounded.x+bounded.width<=1600 and bounded.y+bounded.height<=900);

for _,edge in ipairs({'left','right','top','bottom','top_left','top_right','bottom_left','bottom_right'}) do
    saved=fresh(true); local first=start(edge); local horizontal,vertical=require('ui.resize').axes(edge);
    mx=mx+(edge:find('left',1,true) and -30 or 30); my=my+(edge:find('top',1,true) and -20 or 20);
    draw(); release(); local last=plans()[1];
    assert(last.width==first.width+(horizontal and 30 or 0) and last.height==first.height+(vertical and 20 or 0),edge..' resizes only selected axes.');
    assert(last.x+last.width==first.x+first.width+(edge:find('right',1,true) and 30 or 0),edge..' preserves opposite X edge.');
    assert(last.y+last.height==first.y+first.height+(edge:find('bottom',1,true) and 20 or 0),edge..' preserves opposite Y edge.');
    assert(starts==1 and ends==1 and saves==1,'Each detached gesture is one saved history edit.');
end;
-- An attached strip only moves from its edges and corners: it never becomes a panel of its own or changes size there.
-- A panel of its own comes from its switch in the settings.
for _,edge in ipairs({'top','bottom','left','right','top_left','bottom_right'}) do
    saved=fresh(false); local kept=copy(saved); local first=start(edge); local dy=edge:find('top',1,true) and -20 or 20;
    mx,my=mx+30,my+dy; draw(); release(); local last=plans()[1];
    assert(not saved.native_detached and not last.detached and saved.native_x==30 and saved.native_y==dy and saves==1,
        'An attached '..edge..' Shift-drag moves the strip beside the game\'s rows.');
    assert(last.width==first.width and last.height==first.height and p.native.width==420,'It keeps its size: '..edge);
    for _,key in ipairs({'detached_x','detached_y','detached_width','detached_height'}) do
        assert(saved[key]==kept[key],'Its panel place and size stay as saved: '..edge);
    end;
end;
saved=fresh(false); local first=start('bottom_right'); mx=mx+30; draw(); release();
assert(not saved.native_detached and saved.native_x==30 and saved.native_y==0 and plans()[1].width==first.width,
    'Horizontal-only corner motion moves an attached strip sideways.');
saved=fresh(false);p.native.snap=true;start('center');mx,my=mx+10,my-10;draw();release();
assert(not saved.native_detached and saved.native_x==10 and saved.native_y==-10 and saves==1,
    'Already-attached strips retain small placement adjustments when snapping is enabled.');
for _,detached in ipairs({false,true}) do
    saved=fresh(detached); local before=copy(p); start('top_left'); draw(); release();
    assert(equal(p,before) and starts==0 and ends==0 and saves==0,'No-op edge clicks never detach, mutate or save.');
end;
saved=fresh(false); start('top'); mx=mx+40; draw(); release();
assert(not saved.native_detached and saved.native_x==40 and saved.native_y==0 and saves==1,'Sideways from the top edge moves an attached strip sideways.');
saved=fresh(true); start('center'); mx,my=mx+30,my+40; draw(); release();
assert(saved.detached_x==230 and saved.detached_y==190,'Detached center Shift-drag moves in screen pixels.');
-- A move keeps the saved size, though the screen draws the panel shorter; only a resize saves a size.
saved=fresh(true); saved.detached_height=2000; start('center'); mx=mx+30; draw(); release();
assert(saved.detached_x==230 and saved.detached_width==300 and saved.detached_height==2000 and saves==1,'A move saves no size.');
-- An attached strip's offsets save what is drawn: pushed past the screen's edge it saves no more than still moves it,
-- so a drag back moves it from the first pixel, and so does a drag from a save past the edge.
saved=fresh(false); start('center'); mx=mx+5000; draw(); release();
local pushed=plans()[1];
assert(pushed.x+pushed.width==1600 and saved.native_x==626 and saved.native_y==0,'Pushed to the edge, it saves what is drawn: '..saved.native_x);
start('center'); mx=mx-30; draw(); release();
assert(plans()[1].x==pushed.x-30 and saved.native_x==596,'A drag back moves it at once.');
saved=fresh(false); saved.native_x,saved.native_y=2000,-2000; local held=plans()[1];
start('center'); mx,my=mx-30,my+20; draw(); release();
local moved=plans()[1];
assert(moved.x==held.x-30 and moved.y==held.y+20 and saved.native_x==596 and saved.native_y==-40,
    'From a save past the edge, the first pixels of a drag move it.');
-- Edit mode moves an attached strip from the same offsets, and saves no more than still moves it.
local edit=require('ui.edit_mode');
saved=fresh(false); saved.native_x,saved.native_y=2000,-2000; draw();
local settings,screen={party_ui=p},{x=1600,y=900};
local from=edit._capture(settings,'strip_1',plans()[1],{});
assert(from.kind=='strip' and from.x==626 and from.y==-60,'Edit mode starts from the offsets the strip is drawn at.');
assert(edit._apply(settings,from,-30,20,screen) and saved.native_x==596 and saved.native_y==-40,'Its first pixels move it.');
from=edit._capture(settings,'strip_1',plans()[1],{});
assert(edit._apply(settings,from,5000,0,screen) and saved.native_x==626,'Past the screen\'s edge it saves what is drawn.');
assert(not edit._apply(settings,edit._capture(settings,'strip_1',plans()[1],{}),10,0,screen),'Further on, nothing changes.');
for _,block in ipairs({'lock','typing','input','shift'}) do
    saved=fresh(true);
    if block=='lock' then p.locked=true elseif block=='typing' then roster.typing=true elseif block=='input' then callbacks.input_blocked=true else callbacks.shift=false end;
    local before=copy(p); start('center'); mx=mx+40; draw(); release();
    assert(equal(p,before) and starts==0,'Blocked gesture remains inert: '..block);
end;
for _,reason in ipairs({'shift','disabled','typing','screen','config'}) do
    saved=fresh(true); start('center'); mx=mx+25; draw();
    if reason=='shift' then callbacks.shift=false elseif reason=='disabled' then p.enabled=false
    elseif reason=='typing' then roster.typing=true elseif reason=='screen' then MOCK.screen={1200,700}
    else p=copy(p) end;
    draw(); overlay.cancel_layout_gesture(); assert(saves==1 and starts==1 and ends==1,'Interrupted dirty gestures save exactly once: '..reason);
end;
saved=fresh(true); p.native.snap=true;
for _,side in ipairs({'left','right'}) do
    saved.native_detached=true;
    local frame=geometry.groups[1];
    local x=side=='left' and frame.x-p.native.gap-300 or frame.x+frame.width+p.native.gap;
    assert(overlay.snap(p,1,{x=x,y=frame.y,width=300,height=240},geometry));
    assert(not saved.native_detached and saved.native_side==side and saved.native_x==0 and saved.native_y==0,'Snap chooses the member group and side.');
end;
saved.native_detached=true; local before=copy(saved); geometry.available=false;
assert(not overlay.snap(p,1,{x=700,y=60,width=300},geometry) and equal(saved,before),'Unavailable geometry cannot reattach.');
geometry.available=true;p.native.snap=false;
assert(not overlay.snap(p,1,{x=694,y=60,width=300},geometry),'Snap can be disabled.');
saved=fresh(true);saved.detached_width=40;subjects[roster.members[1].id]=nil;
local readable=plans()[1];local unknown=readable.rows[1];
assert(unknown.area.width>=imgui.CalcTextSize('W'),'A detached narrow frame retains full-size glyph space.');
assert(unknown.unknown==nil and unknown.area.height==0,'Unavailable effect lists reserve no placeholder height.');
-- A strip beside the game's rows grows with its buffs up to Strip maximum width, whatever the game window's width.
saved=fresh(false);local grown=plans()[1];
assert(grown.width<p.native.width and grown.height==132,'An attached strip grows with its buffs and spans the game\'s rows.');
geometry.groups[1].width=160;assert(plans()[1].width==grown.width,'The game window\'s width never sizes the strip.');
p.native.width=40;assert(plans()[1].width==40,'Strip maximum width caps the strip.');
saved=fresh(true); callbacks.shift=false; p.preview=true; local _,shown=draw(); assert(not next(shown),'Detached preview never replaces or targets native windows.');
saved=fresh(true);saved.detached_width=40;p.effects.icon_size=128;
local large=plans()[1];
assert(large.min_width>=158 and large.rows[1].area.width>=128,'Detached panels reserve the selected fixed icon size plus padding and scrollbar space.');
for _,row in ipairs(large.rows) do
    local cells=layout.effect_cells(layout.effects(subjects[row.member.id],row.options),row.options,row.area);
    for _,cell in ipairs(cells) do assert(cell.width>=128 and cell.height>=128,'Narrow saved native viewports never shrink selected128px icons.'); end;
end;
assert(large.content_height>large.height and saved.detached_width==40,'The viewport scrolls and its constrained plan does not rewrite the saved width.');
for _,detached in ipairs({false,true}) do
    saved=fresh(detached);p.native.snap=true;start('center');mx=mx+25;draw();p.locked=true;
    local frozen=copy(p);mx,my=mx+90,my+90;draw();release();
    assert(equal(p,frozen) and saves==1 and starts==1 and ends==1,'Locking an active native drag freezes placement and prevents reattachment.');
    saved=fresh(detached);start('bottom_right');p.locked=true;
    frozen=copy(p);mx,my=mx+90,my+90;draw();release();
    assert(equal(p,frozen) and starts==0 and saves==0,'A native resize locked before movement cannot detach or mutate.');
end;
-- While Shift is held, a strip beside the game's rows shows its outline and name with no resize handles, since its
-- edges only move it. A panel of its own has them.
local resize=require('ui.resize');
local hint,hinted=resize.hint,{};
resize.hint=function(...) local args={...}; hinted[#hinted+1]=args[7]; return hint(...); end;
for _,detached in ipairs({false,true}) do
    saved=fresh(detached);p.strips.alliance1,p.strips.alliance2=false,false;hinted={};mx,my=-1,-1;draw();
    assert(#hinted==1 and hinted[1]==not detached,(detached and 'A panel shows' or 'A strip leaves out')..' its handles.');
end;
resize.hint=hint;
MOCK.imgui_calls={};
resize.hint(require('imgui').GetWindowDrawList(),{x=10,y=10,width=200,height=90},0xFF00FF00,nil,nil,nil,true);
local squares=0;
for _,call in ipairs(MOCK.imgui_calls) do if call[1]=='draw:AddRectFilled' then squares=squares+1; end; end;
assert(squares==0,'Move only draws no handle squares.');
MOCK.imgui_calls={};
resize.hint(require('imgui').GetWindowDrawList(),{x=10,y=10,width=200,height=90},0xFF00FF00,nil,nil,nil);
squares=0;
for _,call in ipairs(MOCK.imgui_calls) do if call[1]=='draw:AddRectFilled' then squares=squares+1; end; end;
assert(squares==8,'A display that resizes has its eight handles.');
-- The panel button and each group's switch work while Locked and leave the lock on; dragging the new panel, from its
-- middle or an edge, still needs an unlock.
local widget=require('ui.party_size_widget');
saved=fresh(false);p.locked=true;
require('ui.elements').record('strip_1',plans()[1]);
widget.place(p,1,overlay.rooms(p,geometry));
assert(saved.native_detached and p.locked==true and plans()[1].detached,'The group is in a panel of its own and still Locked.');
for _,edge in ipairs({'center','top_left','bottom_right','left'}) do
    local before=copy(p);start(edge);mx,my=mx+40,my+30;draw();release();
    assert(equal(p,before) and starts==0 and saves==0,'A Shift-drag on the new panel is refused while Locked: '..edge);
end;
assert(#MOCK.font_stack==0);
return 'Detached member buffers, viewport wrapping, 8-edge gestures, snap, constraints and lifecycle';
