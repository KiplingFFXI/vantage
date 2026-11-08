-- A KO on Phoenix: Die sends the defeat message and the first status packets after it still list every
-- effect, with the player shown KO; the effects with the death flag are gone a tick later with no message
-- (death_state.cpp DelStatusEffectsByFlag, silent). Nothing of that is a wear-off. Raised, the player gets
-- Weakness, and from Arise Reraise, while still shown KO (char_entity.cpp OnRaise); the raise accepted is
-- the first cast while none is held, or the Reraise (or Goddess's Hymnus) up at the KO (sendRaise, Die,
-- hymnus.lua). No Raise can be cast while one is held (raise.lua hasRaiseTractorMenu), so one that lands
-- means the held one was declined. Those rows take it.
local tracker,alerts;
local SELF=1001;
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(revision,timers,dead,effects)
    return {valid=true,id=SELF,name='Tester',zone=102,job=3,self_known=true,self_revision=revision,dead=dead,
        self_timer_revision=timers,self_effects=effects,party={},entities={}};
end;
local rules={
    {id='removed',enabled=true,event='removed',effect=0,scope='self',cooldown=0,duration=30,visual=true},
    {id='remaining',enabled=true,event='remaining',effect=40,scope='self',thresholds={1700},cooldown=0,duration=30,visual=true},
};
local fired;
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    local view=tracker:view(now,{},snap);
    local events=tracker:drain_events();
    alerts:update(view,events,rules,now,{});
    fired=#alerts:drain(now);
    return view,events;
end;
local function find(view,effect)
    for _,row in ipairs(view.rows) do if row.effect==effect then return row; end; end;
end;
local function cast(effect,spell,source,count)
    return {kind='apply',entity_id=SELF,effect=effect,scope='self',source=source,spell=spell,timer_revision=count};
end;
local defeat={kind='death',entity_id=SELF,reason='Observed defeat'};
local function raise(spell,level,source) return {kind='raise',entity_id=SELF,source=source,source_name='Healer',spell=spell,level=level}; end;
local signet=status(253,1,nil,0x7FFFFFFF);

-- The defeat message, with the first KO listing still showing everything, then the listing a tick later.
for _,split in ipairs({false,true}) do
    tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
    frame(snapshot(1,0,false,{}),0);
    local view=frame(snapshot(2,1,false,{status(40,0,1800,108000),signet}),1,{cast(40,43,2001,0)});
    local key=find(view,253).key;
    frame(snapshot(2,1,false,{status(40,0,1800,108000),signet}),2);
    local events;
    if split then
        -- The message's datagram came alone: the status has not said KO yet.
        view,events=frame(snapshot(2,1,false,{status(40,0,1800,108000),signet}),5,{defeat});
        assert(#events==0 and fired==0,'The message alone is quiet.');
        view,events=frame(snapshot(3,1,true,{status(40,0,1800,108000),signet}),5.1);
    else
        view,events=frame(snapshot(3,1,true,{status(40,0,1800,108000),signet}),5,{defeat});
    end
    assert(#events==0 and fired==0 and find(view,40) and find(view,40).source==2001,'The first KO listing is quiet.');
    view,events=frame(snapshot(5,2,true,{status(253,0,nil,0x7FFFFFFF)}),5.5);
    assert(#events==0 and fired==0 and not find(view,40),'What the KO took leaves with no removal: '..#events);
    assert(find(view,253).key==key,'Signet keeps its row through the KO.');
    view,events=frame(snapshot(5,2,true,{status(253,0,nil,0x7FFFFFFF)}),9);
    assert(#events==0 and fired==0,'Nothing is announced while KO.');
end;

-- Raise from 2002, accepted: Weakness is listed while still KO and takes the raise.
tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
frame(snapshot(1,0,false,{signet}),0);
frame(snapshot(2,0,true,{signet}),1,{defeat});
local view,events=frame(snapshot(2,0,true,{signet}),5,{raise(12,1,2002)});
view,events=frame(snapshot(3,0,true,{status(1,0,300,18000),signet}),9);
local weak=find(view,1);
assert(weak and weak.source==2002 and weak.spell==12 and not weak.mine and weak.start==9 and #events==0,
    'Weakness comes with 2002\'s raise.');
view,events=frame(snapshot(3,0,false,{status(1,0,300,18000),signet}),11);
assert(find(view,1).source==2002 and #events==0,'And keeps it once up.');
assert(find(view,253).source==nil,'Signet takes nothing from it.');

-- Arise also gives Reraise.
tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
frame(snapshot(1,0,false,{}),0);
frame(snapshot(2,0,true,{}),1,{defeat});
frame(snapshot(2,0,true,{}),5,{raise(494,4,2002),raise(12,1,2003)});
view=frame(snapshot(3,0,true,{status(1,0,180,10800),status(113,1,3600,216000)}),9);
assert(find(view,1).source==2002 and find(view,113).source==2002 and find(view,113).spell==494,
    'The first raise is the one: Arise, with its Reraise.');
-- A Raise gives Weakness only.
tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
frame(snapshot(1,0,false,{}),0);
frame(snapshot(2,0,true,{}),1,{defeat});
frame(snapshot(2,0,true,{}),5,{raise(13,2,2003)});
view=frame(snapshot(3,0,true,{status(1,0,300,18000),status(113,1,3600,216000)}),9);
assert(find(view,1).source==2003 and find(view,113).source==nil,'Raise II gives no Reraise.');

-- Reraise up at the KO holds the raise: Weakness is that Reraise's.
tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
frame(snapshot(1,0,false,{}),0);
frame(snapshot(2,1,false,{status(113,0,3600,216000)}),1,{cast(113,135,2001,0)});
frame(snapshot(3,1,true,{status(113,0,3600,216000)}),5,{defeat});
frame(snapshot(4,2,true,{}),5.4);
view=frame(snapshot(5,2,true,{status(1,0,300,18000)}),9);
assert(find(view,1).source==2001 and find(view,1).spell==135,'Weakness comes with the Reraise.');
-- A Raise that lands after it means the Reraise was declined: Weakness is that Raise's.
tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
frame(snapshot(1,0,false,{}),0);
frame(snapshot(2,1,false,{status(113,0,3600,216000)}),1,{cast(113,135,2001,0)});
frame(snapshot(3,1,true,{status(113,0,3600,216000)}),5,{defeat});
frame(snapshot(4,2,true,{}),5.4);
frame(snapshot(4,2,true,{}),7,{raise(12,1,2002)});
view=frame(snapshot(5,2,true,{status(1,0,300,18000)}),9);
assert(find(view,1).source==2002 and find(view,1).spell==12,'After a declined Reraise, Weakness comes with the Raise that landed.');
-- Goddess's Hymnus up at the KO holds the raise too: Weakness is its bard's.
tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
frame(snapshot(1,0,false,{}),0);
frame(snapshot(2,1,false,{status(218,0,120,7200)}),1,{cast(218,464,2005,0)});
assert(find(frame(snapshot(2,1,false,{status(218,0,120,7200)}),2),218).source==2005,'Fixture: the Hymnus row names its bard.');
frame(snapshot(3,1,true,{status(218,0,120,7200)}),5,{defeat});
frame(snapshot(4,2,true,{}),5.4);
view=frame(snapshot(5,2,true,{status(1,0,300,18000)}),9);
assert(find(view,1).source==2005 and find(view,1).spell==464,'Weakness comes with the Hymnus.');
-- With both up, the Reraise holds it (it is removed first).
tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
frame(snapshot(1,0,false,{}),0);
frame(snapshot(2,1,false,{status(113,0,3600,216000),status(218,1,120,7200)}),1,{cast(113,135,2001,0),cast(218,464,2005,0)});
frame(snapshot(3,1,true,{status(113,0,3600,216000),status(218,1,120,7200)}),5,{defeat});
frame(snapshot(4,2,true,{}),5.4);
view=frame(snapshot(5,2,true,{status(1,0,300,18000)}),9);
assert(find(view,1).source==2001,'With a Reraise and a Hymnus up, Weakness comes with the Reraise.');
-- With no raise seen, Weakness has no caster.
tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
frame(snapshot(1,0,false,{}),0);
frame(snapshot(2,0,true,{}),1,{defeat});
view=frame(snapshot(3,0,true,{status(1,0,300,18000)}),9);
assert(find(view,1).source==nil and not find(view,1).mine,'No caster is made up.');
-- A raise seen on another KO is not this one's.
tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
frame(snapshot(1,0,false,{}),0);
frame(snapshot(2,0,true,{}),1,{defeat});
frame(snapshot(2,0,true,{}),5,{raise(12,1,2002)});
frame(snapshot(3,0,false,{}),20);
frame(snapshot(4,0,true,{}),40,{defeat});
view=frame(snapshot(5,0,true,{status(1,0,300,18000)}),50);
assert(find(view,1).source==nil,'The last KO\'s raise is gone.');
