-- Same-ID songs paired with the listed copies by what Phoenix does (status_effect_container.cpp): a song
-- of one ID and tier replaces that copy in its slot whoever sings it; over a singer's cap their song that
-- ends first is replaced in its slot; songs keep their slots, so their order in the list; an untouched
-- copy's raw timer reads one of two values 60 apart (0x063_miscdata_status_icons.cpp).
local tracker;
local SELF=1001;
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(revision,timers,effects)
    return {valid=true,id=SELF,name='Tester',zone=102,job=1,self_known=true,self_revision=revision,
        self_timer_revision=timers,self_effects=effects,party={},entities={}};
end;
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    return tracker:view(now,{},snap),tracker:drain_events();
end;
local function at(view,slot)
    for _,row in ipairs(view.rows) do if row.slot==slot and row.present then return row; end; end;
end;
local function kinds(events)
    local out={};
    for _,event in ipairs(events) do out[#out+1]=event.kind..':'..tostring(event.effect)..':'..tostring(event.spell)..'/'..tostring(event.source); end;
    return table.concat(out,',');
end;
local function cast(effect,spell,source,count)
    return {kind='apply',entity_id=SELF,effect=effect,scope='self',source=source,spell=spell,timer_revision=count};
end;

-- A copy's raw timer moves by 60 at most untouched: 120 is a renewal, though the client's deadlines,
-- worked out from whole seconds, read only a second apart.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(198,0,690,41400)}),570,{cast(198,394,2003,0)});
frame(snapshot(3,2,{status(198,0,690,41400),status(198,1,690.9,41400)}),570.9,{cast(198,395,2003,1)});
local view,events=frame(snapshot(4,3,{status(198,0,691,41460),status(198,1,691.9,41520)}),572.9,{cast(198,395,2003,2)});
assert(at(view,0).spell==394 and at(view,0).instance==1,'The copy that moved 60 is the same one.');
assert(at(view,1).spell==395 and at(view,1).instance==2 and at(view,1).start==572.9 and kinds(events)=='refresh:198:395/2003',
    'The one that moved 120 was recast: '..kinds(events));

-- A row that has read both of its values keeps to them: the new copy took the old value it no longer reads.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(198,0,1233,73980)}),1100,{cast(198,394,SELF,0)});
frame(snapshot(3,2,{status(198,0,1232,73920)}),1105);
frame(snapshot(4,3,{status(198,0,1233,73980)}),1110);
view,events=frame(snapshot(5,4,{status(198,0,1234,74040),status(198,1,1232,73920)}),1114.9,{cast(198,395,2003,3)});
assert(at(view,1).spell==394 and at(view,1).source==SELF and at(view,1).instance==1,'394 keeps its own timer.');
assert(at(view,0).spell==395 and at(view,0).source==2003 and kinds(events)=='gain:198:395/2003',
    'The new copy listed first is 2003\'s: '..kinds(events));

-- 2002 sings 420 over its cap; 394, its song that ends first, makes way. 2003's 395 reads the same timer.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(198,0,200,12000)}),80,{cast(198,394,2002,0)});
frame(snapshot(3,2,{status(198,0,200,12000),status(198,1,200.5,12000)}),80.5,{cast(198,395,2003,1)});
frame(snapshot(4,3,{status(198,0,200,12000),status(198,1,200.5,12000),status(214,2,230,13800)}),110,{cast(214,419,2002,2)});
view,events=frame(snapshot(5,4,{status(214,0,240,14400),status(198,1,200.5,12000),status(214,2,230,13800)}),120,
    {cast(214,420,2002,3)});
assert(at(view,1).spell==395 and at(view,1).source==2003,'The copy that stays is 2003\'s.');
assert(kinds(events)=='removed:198:394/2002,gain:214:420/2002','2002\'s 394 went: '..kinds(events));

-- 2003 resings 394, which ends after its 395, over its cap: 394's old copy is replaced, and 395, its song
-- that ends first, is lost too; the new 394 takes 395's slot, ahead. Both rows read as renewed; the one
-- the cast lands on is 394.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(198,0,2278,136680)}),2158,{cast(198,395,2003,0)});
frame(snapshot(3,2,{status(198,0,2278,136680),status(198,1,2325,139500)}),2205,{cast(198,394,2003,1)});
view,events=frame(snapshot(5,3,{status(198,0,2350,141000)}),2230,{cast(198,394,2003,2)});
assert(at(view,0).spell==394 and at(view,0).instance==2 and at(view,0).start==2230
    and kinds(events)=='removed:198:395/2003,refresh:198:394/2003','The 394 row is renewed and 395 is lost: '..kinds(events));
-- 395 runs out (the wear-off can't say which copy) as 2004 sings 394 over 2002's copy: the copy left is
-- the one the cast lands on.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(198,0,120,7200)}),0,{cast(198,395,2003,0)});
frame(snapshot(3,2,{status(198,0,120,7200),status(198,1,150,9000)}),30,{cast(198,394,2002,1)});
view,events=frame(snapshot(5,3,{status(198,0,240,14400)}),120.2,{{kind='remove',entity_id=SELF,effect=198,scope='self'},
    cast(198,394,2004,2)});
assert(at(view,0).spell==394 and at(view,0).source==2004 and kinds(events)=='removed:198:395/2003,refresh:198:394/2004',
    'The 394 copy is renewed by 2004 and 395 is gone: '..kinds(events));

-- Two rows read one timer and carry each other's songs. 2002 recasts 419: the copy that moves is 419's,
-- so the rows trade labels.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(214,0,2160,129480),status(214,1,2160,129480)}),2040,{cast(214,419,2002,0),cast(214,420,2002,0)});
view=frame(snapshot(3,2,{status(214,0,2160,129480),status(214,1,2160,129480)}),2041);
local wrong={at(view,0).spell,at(view,1).spell};
view,events=frame(snapshot(5,3,{status(214,0,2160,129480),status(214,1,2165,129900)}),2045.6,
    {cast(214,wrong[2]==420 and 419 or 420,2002,2)});
local moved=at(view,1).spell;
assert(at(view,1).instance==2 and at(view,1).source==2002 and moved~=wrong[2],'The copy that moved takes the cast.');
assert(at(view,0).spell==wrong[2] and at(view,0).source==2002 and at(view,0).instance==1,'The other copy takes the old label.');

-- Songs keep their order against the other songs. 2002 sings 420 over its cap into 394's slot, ahead of
-- 2003's 395; 2002's 419, behind 395, reads the same timer as the new copy.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(198,0,3440,206400)}),3300,{cast(198,394,2002,0)});
frame(snapshot(3,2,{status(198,0,3440,206400),status(198,1,3428,205740)}),3308,{cast(198,395,2003,1)});
frame(snapshot(4,3,{status(198,0,3440,206400),status(198,1,3428,205740),status(214,2,3511,210660)}),3391,{cast(214,419,2002,2)});
view,events=frame(snapshot(5,4,{status(214,0,3512,210720),status(198,1,3428,205740),status(214,2,3512,210720)}),3392.6,
    {cast(214,420,2002,3)});
assert(at(view,2).spell==419 and at(view,2).instance==1,'419 stays behind 395.');
assert(at(view,0).spell==420 and at(view,0).source==2002 and kinds(events)=='removed:198:394/2002,gain:214:420/2002',
    'The new copy is ahead: '..kinds(events));

-- A renewal takes a cast of the row's tier from any singer, not one of another copy's tier.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(198,0,120,7200)}),0,{cast(198,394,2002,0)});
frame(snapshot(3,2,{status(198,0,120,7200),status(198,1,240,14400)}),0.5,{cast(198,395,2004,1)});
view,events=frame(snapshot(4,3,{status(198,0,120,7200),status(198,1,300,18000)}),60,{cast(198,394,2003,2),cast(198,395,2003,2)});
assert(at(view,1).spell==395 and at(view,1).source==2003,'The renewed 395 copy takes the 395 cast.');
-- The 394 cast moved its copy too little to see; its 0x063 shows it there.
assert(at(view,0).spell==394 and at(view,0).source==2003 and kinds(events)=='refresh:198:395/2003,refresh:198:394/2003',
    'And 394\'s copy is 2003\'s too: '..kinds(events));

-- A listing shows only applications counted before its own 0x063: one sent after the 0x063 waits.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(33,0,180,10800)}),0,{cast(33,57,2001,0)});
view,events=frame(snapshot(4,2,{status(33,0,240,14400)}),60,{cast(33,57,2001,1),cast(33,57,2005,2)});
assert(at(view,0).source==2001 and at(view,0).instance==2,'The renewal is 2001\'s; 2005\'s comes after it.');
view,events=frame(snapshot(6,3,{status(33,0,240.4,14400)}),60.4);
assert(at(view,0).source==2005 and kinds(events)=='refresh:33:57/2005','2005\'s shows on the next 0x063: '..kinds(events));

-- Two casts of one tier before one listing: the later replaced the earlier, so a new copy is the later one.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
view,events=frame(snapshot(2,2,{status(198,0,220.4,13200)}),100.4,{cast(198,394,2002,0),cast(198,394,2003,1)});
assert(at(view,0).source==2003 and kinds(events)=='gain:198:394/2003','The new copy is 2003\'s: '..kinds(events));

