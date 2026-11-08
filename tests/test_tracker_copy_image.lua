-- Utsusemi on Phoenix: one Copy Image effect (66), its icon the shadows left (446, 445, 444, then 66), and
-- the 0x028 names 66 (enhancing_ninjutsu.lua). A shadow taken changes the icon of the same effect on the same
-- timer (battleutils.cpp SetIcon): no removal, no gain, the row keeps its key and caster. A recast replaces
-- the copy: one refresh. Out of the tracker a row or an event reads as Copy Image (66) at any count, with its icon.
local tracker,alerts;
local SELF,BOB=1001,2002;
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(revision,timers,effects,bob,brev)
    return {valid=true,id=SELF,name='Tester',zone=102,job=13,self_known=true,self_revision=revision,
        self_timer_revision=timers,self_effects=effects,
        party={{id=BOB,name='Bob',scope='party',group=1,slot=1,zone=102,valid=true,revision=brev or 1,effects=bob or {}}},
        entities={[BOB]={id=BOB,name='Bob',kind='player'}}};
end;
local rules={{id='removed',enabled=true,event='removed',effect=0,scope='all',cooldown=0,duration=30,visual=true},
    {id='gain',enabled=true,event='gain',effect=0,scope='all',cooldown=0,duration=30,visual=true},
    {id='missing',enabled=true,event='missing',effect=66,scope='self',cooldown=0,duration=30,visual=true}};
local notices;
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    local view,events=tracker:view(now,{},snap),tracker:drain_events();
    alerts:update(view,events,rules,now,{});
    notices={};for _,n in ipairs(alerts:drain(now)) do notices[#notices+1]=n.message;end;
    return view,events;
end;
local function mine(view,id)
    local out={};for _,r in ipairs(view.rows) do if r.entity_id==(id or SELF) then out[#out+1]=r;end;end;return out;
end;
local function cast(count) return {kind='apply',entity_id=SELF,effect=66,scope='self',source=SELF,spell=339,timer_revision=count}; end;
tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
frame(snapshot(1,0,{status(40,0,1800,108000)}),0);
-- Utsusemi: Ni, four shadows.
local view,events=frame(snapshot(3,1,{status(40,0,1790,108000),status(446,1,900,54000)}),10,{cast(0)});
local row=mine(view)[2];
assert(row and row.effect==66 and row.icon==446 and row.name=='Copy Image' and row.source==SELF and row.mine and row.spell==339
    and row.total==890,'The player\'s Utsusemi is credited to the player, as Copy Image with the icon of four shadows.');
local key=row.key;
for step,icon in ipairs({445,444,66}) do
    view,events=frame(snapshot(3+2*step,1+step,{status(40,0,1790,108000),status(icon,1,900,54000+60*(step%2))}),10+5*step);
    row=mine(view)[2];
    assert(#events==0 and #notices==0,'A shadow taken is no removal and no gain.');
    assert(row.effect==66 and (row.icon or row.effect)==icon and row.key==key and row.source==SELF and row.mine,
        'The row follows the icon, with its key and caster.');
end;
-- A recast over one shadow lists the old copy beside the new one for that tick: one refresh.
view,events=frame(snapshot(11,5,{status(40,0,1790,108000),status(66,1,900,54000),status(446,2,1040,62400)}),40,{cast(4)});
assert(#events==1 and events[1].kind=='refresh' and #notices==0,'Utsusemi cast again over a shadow is one refresh.');
view,events=frame(snapshot(13,6,{status(40,0,1790,108000),status(446,1,1040,62400)}),40.4);
assert(#events==0 and #notices==0 and #mine(view)==2 and mine(view)[2].icon==446 and mine(view)[2].source==SELF,
    'The old copy leaves quietly; the row shows four shadows again.');
-- The last shadow's wear-off names the icon it had.
local _,worn=frame(snapshot(13,6,{status(40,0,1790,108000),status(446,1,1040,62400)}),60,
    {{kind='remove',entity_id=SELF,effect=446,scope='self',reason='Observed wearoff',timer_revision=6}});
view,events=frame(snapshot(15,7,{status(40,0,1790,108000)}),60.4);
local removed,gone=0,nil;
for _,list in ipairs({worn,events}) do for _,e in ipairs(list) do if e.kind=='removed' then removed,gone=removed+1,e;end;end;end;
assert(#mine(view)==1 and removed==1 and gone.effect==66 and gone.icon==446,'Its wear-off is one removal, of Copy Image at its icon.');

-- A party member's Utsusemi: the 0x028 names 66, the 0x076 their icons.
tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
frame(snapshot(1,0,{}),0);
view,events=frame(snapshot(1,0,{},{{effect=446,slot=0}},2),10,
    {{kind='apply',entity_id=BOB,effect=66,scope='party',source=BOB,spell=339,duration=900}});
row=mine(view,BOB)[1];
assert(row and row.source==BOB,'Fixture: Bob\'s Utsusemi is on Bob.');
key=row.key;
for step,icon in ipairs({445,444,66}) do
    view,events=frame(snapshot(1,0,{},{{effect=icon,slot=0}},2+step),10+step);
    row=mine(view,BOB)[1];
    assert(#events==0 and #notices==0 and #mine(view,BOB)==1 and row.key==key and row.effect==66 and (row.icon or row.effect)==icon
        and row.source==BOB,
        'A shadow Bob loses is no removal and no gain.');
end;

-- Bob recasts with three shadows left: a caster's 0x076 lists the old copy beside the new one once more.
frame(snapshot(1,0,{},{{effect=445,slot=0}},6),19);
view,events=frame(snapshot(1,0,{},{{effect=445,slot=0},{effect=446,slot=1}},7),20,
    {{kind='apply',entity_id=BOB,effect=66,scope='party',source=BOB,spell=339,duration=900}});
assert(#notices==0 and #mine(view,BOB)==1,'A recast listed beside the old copy is no gain.');
view,events=frame(snapshot(1,0,{},{{effect=446,slot=0}},8),20.4);
assert(#events==0 and #notices==0 and #mine(view,BOB)==1 and mine(view,BOB)[1].icon==446 and mine(view,BOB)[1].key==key,
    'Once the old copy is gone, the row shows four shadows, with no removal.');

-- A Copy Image rule matches every shadow icon.
tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
frame(snapshot(3,1,{status(446,0,900,54000)}),0,{cast(0)});
for t=1,6 do frame(snapshot(3,1,{status(446,0,900,54000)}),t); assert(#notices==0,'Copy Image is not missing while four shadows are up.'); end;

-- A shadow taken whose 0x037 lands an update before its 0x063: that listing has no timers yet. Still no
-- removal and no gain, and the row keeps its key and caster through both.
tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
frame(snapshot(1,0,{status(40,0,1800,108000)}),0);
view,events=frame(snapshot(3,1,{status(40,0,1790,108000),status(446,1,900,54000)}),10,{cast(0)});
key=mine(view)[2].key;
for step,icon in ipairs({445,444}) do
    local split=snapshot(3+2*step,step,{status(40,0,nil,nil),status(icon,1,nil,nil)});
    split.self_timers_pending=true;
    view,events=frame(split,10+5*step);
    row=mine(view)[2];
    assert(#events==0 and #notices==0 and row.key==key and row.effect==66 and row.icon==icon and row.source==SELF and row.mine,
        'A shadow taken in a split send is no removal and no gain at its 0x037.');
    view,events=frame(snapshot(4+2*step,1+step,{status(40,0,1790,108000),status(icon,1,900,54000)}),10.4+5*step);
    row=mine(view)[2];
    assert(#events==0 and #notices==0 and row.key==key and row.effect==66 and row.icon==icon and row.source==SELF and row.spell==339,
        'Nor at its 0x063, and the row keeps its key and caster.');
end;
