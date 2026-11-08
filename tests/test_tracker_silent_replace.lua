-- Phoenix replaces songs with no message (status_effect_container.cpp ApplyBardEffect). A song of the same ID
-- and tier, whoever sings it, takes that copy's slot. Over the singer's cap their own song that ends first
-- is replaced in its slot. When the new timer lands within a restamp step of the old one, the listing reads
-- as a restamp. A complete listing whose timers agree, read after a 0x063 that came after the application,
-- shows that the application no row took replaced a copy: the one of its tier, else the singer's own.
local tracker;
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(revision,timers,effects)
    return {valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_revision=revision,
        self_timer_revision=timers,self_effects=effects,party={},entities={}};
end;
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    return tracker:view(now,{},snap),tracker:drain_events();
end;
local function rows(view,effect)
    local out={};
    for _,row in ipairs(view.rows) do if row.effect==effect and row.present then out[#out+1]=row; end; end;
    return out;
end;
local function cast(effect,spell,source,count)
    return {kind='apply',entity_id=1001,effect=effect,scope='self',source=source,spell=spell,timer_revision=count};
end;

-- 2003 has 395 and a 214 song up, 395 ending first; it sings 394 1.6 s after 395, over its cap, so 394
-- takes 395's slot. The new timer is one restamp step on, or the same.
for _,raw in ipairs({7860,7800}) do
    tracker=require('core.tracker').new();
    frame(snapshot(1,0,{}),0);
    frame(snapshot(2,1,{status(198,0,130,7800)}),10,{cast(198,395,2003,0)});
    local view=frame(snapshot(3,2,{status(198,0,130,7800),status(214,1,140.4,8424)}),10.4,{cast(214,420,2003,1)});
    local key=rows(view,198)[1].key;
    local events;
    view,events=frame(snapshot(4,2,{status(198,0,130,7800),status(214,1,140.4,8424)}),11.6,{cast(198,394,2003,2)});
    assert(#events==0 and rows(view,198)[1].spell==395,'Before its 0x063 the application shows nothing.');
    view,events=frame(snapshot(6,3,{status(198,0,131,raw),status(214,1,140.4,8424)}),11.9);
    local row=rows(view,198)[1];
    assert(row.key==key and row.spell==394 and row.source==2003 and row.instance==2 and row.start==11.6
        and row.total==131-11.6,'The row is the new song, a new instance.');
    assert(#events==1 and events[1].kind=='refresh' and events[1].spell==394 and events[1].source==2003
        and rows(view,214)[1].spell==420 and rows(view,214)[1].instance==1,
        'It is reported as a renewal, like one that moved the timer, and the other song is untouched.');
end;

-- 2004's 395 lasts 240 s. 2002 sings 394, then 2003 sings 394 half a second later: the same tier, so it
-- takes 2002's copy whatever the timers say. (Credited to the copy that ends last, 2004's 395 got it.)
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(198,0,240,14400)}),0.5,{cast(198,395,2004,0)});
local view,events=frame(snapshot(3,2,{status(198,0,240,14400),status(198,1,220,13200)}),100,{cast(198,394,2002,1)});
view,events=frame(snapshot(4,3,{status(198,0,240,14400),status(198,1,220.5,13260)}),100.9,{cast(198,394,2003,2)});
local by={};
for _,row in ipairs(rows(view,198)) do by[row.slot]=row; end;
assert(by[1].spell==394 and by[1].source==2003 and by[1].mine==false and by[1].instance==2 and by[1].start==100.9,
    'The copy of that tier is the other bard\'s now.');
assert(by[0].spell==395 and by[0].source==2004 and by[0].instance==1,'The longer song keeps its own caster.');
assert(#events==1 and events[1].kind=='refresh' and events[1].spell==394 and events[1].source==2003,'One renewal, for 394.');

-- The same with equal durations: two songs sung 0.4 s apart read one raw timer, and 2003 sings 394 0.4 s
-- on. The copy of that tier is 2003's, though the other is in the later slot.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(198,0,220,13200)}),100,{cast(198,394,2002,0)});
frame(snapshot(3,2,{status(198,0,220,13200),status(198,1,220.4,13200)}),100.4,{cast(198,395,2004,1)});
view,events=frame(snapshot(4,3,{status(198,0,220.8,13200),status(198,1,220.4,13200)}),100.8,{cast(198,394,2003,2)});
by={};
for _,row in ipairs(rows(view,198)) do by[row.slot]=row; end;
assert(by[0].spell==394 and by[0].source==2003 and by[0].start==100.8,'2003\'s 394 is the copy of that tier.');
assert(by[1].spell==395 and by[1].source==2004 and by[1].instance==1,'The 395 in the later slot is still 2004\'s.');

-- Over 2002's cap: 394 ends first among 2002's songs, 2002 sings 396, and 396 takes 394's slot a second
-- after 394 was recast; 2003's 395 stays.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(198,0,100,6000)}),1,{cast(198,394,2002,0)});
frame(snapshot(3,2,{status(198,0,100,6000),status(198,1,120,7200)}),30,{cast(198,395,2003,1)});
frame(snapshot(4,3,{status(198,0,100,6000),status(198,1,120,7200),status(214,2,170,10200)}),35,{cast(214,419,2002,2)});
view,events=frame(snapshot(5,4,{status(198,0,159,9540),status(198,1,120,7200),status(214,2,170,10200)}),39,{cast(198,394,2002,3)});
assert(#events==1 and events[1].kind=='refresh' and events[1].spell==394,'The recast moves 394.');
view,events=frame(snapshot(6,5,{status(198,0,160,9600),status(198,1,120,7200),status(214,2,170,10200)}),40.2,{cast(198,396,2002,4)});
by={};
for _,row in ipairs(rows(view,198)) do by[row.spell]=row; end;
assert(by[396] and by[396].source==2002 and by[396].instance==3 and by[396].slot==0 and by[396].start==40.2,
    'The singer\'s copy that ended first is the new song, in its slot.');
assert(by[395] and by[395].source==2003 and by[395].instance==1 and by[395].slot==1,'Another bard\'s song is never the one replaced.');
assert(#events==1 and events[1].kind=='refresh' and events[1].spell==396,'One renewal for the new song.');

-- A song no copy of its tier or its singer's can take, with no new copy, landed nowhere listed.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(198,0,130,7800)}),10,{cast(198,395,2003,0)});
view,events=frame(snapshot(3,2,{status(198,0,130,7800)}),11.6,{cast(198,394,2002,1)});
view,events=frame(snapshot(4,3,{status(198,0,131,7860)}),11.9);
assert(#events==0 and rows(view,198)[1].spell==395 and rows(view,198)[1].source==2003,
    'Another bard\'s song does not take 2003\'s copy.');

-- Two casts on one copy before one listing: the last one owns it. An older one with no copy left was
-- overwritten and is dropped, so it can't go to a copy later.
for _,order in ipairs({{2005,2001},{2001,2005}}) do
    tracker=require('core.tracker').new();
    frame(snapshot(1,0,{}),0);
    frame(snapshot(2,1,{status(33,0,180,10800)}),0.5,{cast(33,57,2001,0)});
    view,events=frame(snapshot(3,2,{status(33,0,181,10860)}),1.2,{cast(33,57,order[1],1),cast(33,57,order[2],1)});
    local row=rows(view,33)[1];
    assert(row.source==order[2],'The last cast owns the copy: '..tostring(row.source));
    assert(row.instance==(order[2]==2001 and 1 or 2),'A recast by its own caster is no new instance.');
    view,events=frame(snapshot(4,3,{}),2,{{kind='remove',entity_id=1001,effect=33,scope='self'}});
    view,events=frame(snapshot(5,4,{status(33,0,240,14400)}),2.5);
    row=rows(view,33)[1];
    assert(row and row.source==nil and row.spell==nil,'A Haste with no application seen takes none of the old ones.');
end;

-- Only an application with a spell is credited.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(34,0,100,6000)}),1,{cast(34,249,1001,0)});
view,events=frame(snapshot(3,2,{status(34,0,100,6000)}),5,{
    {kind='apply',entity_id=1001,effect=34,scope='self',source=0x1000010,timer_revision=1}});
assert(#events==0,'Nothing is renewed.');
assert(rows(view,34)[1].spell==249 and rows(view,34)[1].source==1001 and rows(view,34)[1].instance==1,
    'Spikes reported without a spell are not a new cast.');

-- An application with no 0x063 count, or no 0x063 after it, proves nothing.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(198,0,130,7800)}),10,{cast(198,395,2003,0)});
local unstamped=cast(198,394,2003,nil);
view,events=frame(snapshot(4,2,{status(198,0,130,7800)}),11.6,{unstamped});
view,events=frame(snapshot(6,2,{status(198,0,131,7860)}),11.9);
assert(#events==0 and rows(view,198)[1].spell==395,'Without the count the row keeps its caster.');

-- An application more than 3 s old is no longer waiting, as for any row.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(198,0,130,7800)}),10,{cast(198,395,2003,0)});
view,events=frame(snapshot(3,2,{status(198,0,130,7800)}),11,{cast(198,394,2003,2)});
view,events=frame(snapshot(4,3,{status(198,0,131,7860)}),14.05);
assert(#events==0 and rows(view,198)[1].spell==395,'A stale application credits nothing.');
