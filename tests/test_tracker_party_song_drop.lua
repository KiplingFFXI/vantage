-- Two copies of one song on a party member, from different tiers (Minuet IV and III). When their 0x076 lists
-- one copy, the copy that left is the one whose estimate ran out, or, after a singer's new song, that singer's
-- song from before it that ends first (Phoenix drops it over the cap, ApplyBardEffect). That copy is
-- removed and the other keeps its caster and countdown. When nothing tells them apart it stays quiet.
local tracker,alerts;
local SELF,BOB=1001,2002;
local function snapshot(rev,effects)
    return {valid=true,id=SELF,name='Tester',zone=102,job=10,self_known=true,self_revision=1,self_timer_revision=1,
        self_effects={},party={{id=BOB,name='Bob',scope='party',group=1,slot=1,zone=102,valid=true,revision=rev,effects=effects}},
        entities={[BOB]={id=BOB,name='Bob',kind='player'}}};
end;
local rules={{id='removed',enabled=true,event='removed',effect=0,scope='party',cooldown=0,duration=30,visual=true}};
local notices;
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    local view,events=tracker:view(now,{},snap),tracker:drain_events();
    alerts:update(view,events,rules,now,{});
    notices={};for _,n in ipairs(alerts:drain(now)) do notices[#notices+1]=n.message;end;
    return view,events;
end;
local function sing(spell,tier,duration,effect)
    return {kind='apply',entity_id=BOB,effect=effect or 198,scope='party',source=SELF,spell=spell,tier=tier,
        stackable=true,instance_hint=SELF..':'..spell,duration=duration};
end;
local function songs(view,effect)
    local out={};for _,r in ipairs(view.rows) do if r.entity_id==BOB and r.effect==(effect or 198) then out[#out+1]=r;end;end;return out;
end;
local function removed(events)
    local out={};for _,e in ipairs(events) do if e.kind=='removed' then out[#out+1]=e;end;end;return out;
end;
local two={{effect=198,slot=0},{effect=198,slot=1}};
local function setup()
    tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
    frame(snapshot(1,{}),0);
    frame(snapshot(2,{{effect=198,slot=0}}),10,{sing(397,4,120)});
    frame(snapshot(3,two),18,{sing(396,3,120)});
    frame(snapshot(3,two),60);
end;

-- Minuet IV runs out first.
setup();
for t=65,130,5 do frame(snapshot(3,two),t); end;
local view,events=frame(snapshot(4,{{effect=198,slot=0}}),130.35);
local gone,left=removed(events),songs(view);
assert(#gone==1 and gone[1].spell==397 and #notices==1,'The copy whose time ran out is the one removed.');
assert(#left==1 and left[1].spell==396 and left[1].source==SELF and left[1].remaining and left[1].remaining>5,
    'The other copy keeps its caster and countdown.');

-- Over the cap: the singer's new March drops their Minuet that ends first, with no message.
setup();
view,events=frame(snapshot(4,{{effect=198,slot=0},{effect=198,slot=1},{effect=214,slot=2}}),60.2,{sing(420,2,120,214)});
assert(#removed(events)==0,'Fixture: the new song\'s first listing still lists both Minuets.');
view,events=frame(snapshot(5,{{effect=198,slot=0},{effect=214,slot=1}}),60.6);
gone,left=removed(events),songs(view);
assert(#gone==1 and gone[1].spell==397 and #left==1 and left[1].spell==396 and left[1].source==SELF,
    'Over the cap, the singer\'s Minuet that ends first is the one removed; the other keeps its labels.');

-- Nothing tells them apart: one leaves well before either estimate, with no new song.
setup();
view,events=frame(snapshot(4,{{effect=198,slot=0}}),70);
assert(#removed(events)==0 and #songs(view)==1 and songs(view)[1].spell==nil,'A drop nothing explains stays quiet and unlabelled.');

-- Two bards sing to Bob within 3 s. A has Minuet IV (ends first) and March up, B has Minuet III. A's Ballad
-- drops A's Minuet IV over A's cap, and B's Madrigal, under B's cap, drops nothing; but a singer's cap
-- depends on their instrument, so B's Madrigal could as well have dropped B's Minuet III. Neither is named.
local A,B=2001,2003;
local function by(source,spell,tier,effect)
    local cast=sing(spell,tier,120,effect);
    cast.source,cast.instance_hint=source,source..':'..spell;
    return cast;
end;
local function bards()
    tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
    frame(snapshot(1,{}),0);
    frame(snapshot(2,{{effect=198,slot=0}}),0.2,{by(A,397,4,198)});
    frame(snapshot(3,two),5.2,{by(B,396,3,198)});
    frame(snapshot(4,{{effect=198,slot=0},{effect=198,slot=1},{effect=214,slot=2}}),10.2,{by(A,419,2,214)});
end;
bards();
view,events=frame(snapshot(5,{{effect=196,slot=0},{effect=198,slot=1},{effect=214,slot=2},{effect=199,slot=3}}),100.6,
    {by(A,386,1,196),by(B,399,1,199)});
assert(#removed(events)==0 and #songs(view)==1 and songs(view)[1].source==nil,
    'Two singers who could each have dropped a Minuet leave it quiet and unlabelled.');
-- Only B sings, while A's Minuet IV is about to run out: B's cap or A's time, so neither is named either.
bards();
view,events=frame(snapshot(5,{{effect=198,slot=1},{effect=214,slot=2},{effect=199,slot=3}}),119.4,{by(B,399,1,199)});
assert(#removed(events)==0 and #songs(view)==1 and songs(view)[1].source==nil,
    'A singer\'s cap and a copy whose time ran out that name different copies leave it quiet and unlabelled.');
