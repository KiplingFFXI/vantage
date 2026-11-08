-- A party AoE on Phoenix sends one 0x076 per member PostTick (party.cpp PushEffectsPacket clears the party
-- flag, each later member's erase raises it again), so a member who has not ticked yet is listed with the
-- replaced copy beside the new one in several listings, not one. Each of them is no gain, and when the
-- member's own tick drops the old copy the row keeps its caster, spell and countdown.
local tracker,alerts;
local SELF,BOB=1001,2002;
local function snapshot(rev,bob)
    return {valid=true,id=SELF,name='Tester',zone=102,job=3,self_known=true,self_revision=1,self_timer_revision=1,
        self_effects={},party={{id=BOB,name='Bob',scope='party',group=1,slot=1,zone=102,valid=true,revision=rev,effects=bob}},
        entities={[BOB]={id=BOB,name='Bob',kind='player'}}};
end;
local rules={{id='gain',enabled=true,event='gain',effect=0,scope='party',cooldown=0,duration=30,visual=true},
    {id='removed',enabled=true,event='removed',effect=0,scope='party',cooldown=0,duration=30,visual=true}};
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    local view,events=tracker:view(now,{},snap),tracker:drain_events();
    alerts:update(view,events,rules,now,{});
    local notices=alerts:drain(now);
    local out={};
    for _,e in ipairs(events) do out[#out+1]=e.kind..':'..tostring(e.effect)..':'..tostring(e.source); end;
    local rows={};
    for _,r in ipairs(view.rows) do if r.entity_id==BOB then rows[#rows+1]=r; end; end;
    return rows,table.concat(out,','),notices;
end;
tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
frame(snapshot(1,{}),0);
frame(snapshot(2,{{effect=40,slot=0}}),1,{{kind='apply',entity_id=BOB,effect=40,scope='party',source=2001,spell=43,duration=1800,party_revision=1}});
frame(snapshot(2,{{effect=40,slot=0}}),2);
-- The player casts Protectra: the 0x028, then three 0x076 from other members' PostTicks while Bob has not ticked.
local protectra={{kind='apply',entity_id=BOB,effect=40,scope='party',source=SELF,spell=129,duration=1800,party_revision=2}};
local rows,events=frame(snapshot(3,{{effect=40,slot=0},{effect=40,slot=1}}),10,protectra);
assert(#rows==1 and events=='refresh:40:1001','The first stale listing is a refresh of the copy the cast landed on: '..events);
local notices;
rows,events,notices=frame(snapshot(4,{{effect=40,slot=0},{effect=40,slot=1}}),10.02);
assert(#rows==1 and events=='' and #notices==0,'The second stale listing is no gain either: events '..events..', '..#notices..' notices, '..#rows..' rows.');
rows,events,notices=frame(snapshot(5,{{effect=40,slot=0},{effect=40,slot=1}}),10.04);
assert(#rows==1 and events=='' and #notices==0,'Nor the third: events '..events..', '..#rows..' rows.');
-- Bob's own tick erased the old copy.
rows,events=frame(snapshot(6,{{effect=40,slot=0}}),10.4);
assert(#rows==1 and rows[1].source==SELF and rows[1].spell==129 and rows[1].mine==true and rows[1].remaining~=nil,
    'The member keeps the caster, spell and countdown of the cast: source='..tostring(rows[1] and rows[1].source)..' spell='..tostring(rows[1] and rows[1].spell));
rows,events=frame(snapshot(6,{{effect=40,slot=0}}),12);
assert(#rows==1 and rows[1].source==SELF and events=='','Nothing changes while the listing stands.');
-- A stale listing long after the cast is past the spare: its extra copy is a row of its own, and when the
-- member's listing drops a copy of an effect with one copy, the row the cast landed on is the one kept.
rows,events=frame(snapshot(7,{{effect=40,slot=0},{effect=40,slot=1}}),13.5);
assert(#rows==2,'Fixture: the late extra copy is a row of its own.');
rows,events=frame(snapshot(8,{{effect=40,slot=0}}),14);
assert(#rows==1 and rows[1].source==SELF and rows[1].spell==129,
    'With one copy left, the labelled row survives: source='..tostring(rows[1] and rows[1].source)..' spell='..tostring(rows[1] and rows[1].spell));
-- A copy that really is new after that (another caster's Protect on a member with none) is a gain.
rows,events,notices=frame(snapshot(9,{}),20);
rows,events,notices=frame(snapshot(10,{{effect=40,slot=0}}),21,{{kind='apply',entity_id=BOB,effect=40,scope='party',source=2001,spell=43,duration=1800,party_revision=9}});
assert(#rows==1 and rows[1].source==2001 and #notices==1,'A new copy after the stale window is a gain with its alert: '..events..', '..#notices..' notices.');
