-- Buffs an item puts on yourself come as a 0x029 message 205 from you to you (Phoenix messageBasic in the
-- item scripts: Reraise Earring, Hermes Quencher and the rest), so the row is yours. Using the item again while
-- the effect is up (delStatusEffect with its message, then the 205, listed as two copies for one tick) is one
-- renewal: the row keeps its key, and neither a gain nor a removal is announced.
local observer=require('core.observer');
local SELF=1001;
local function snapshot(revision,timers,effects)
    return {valid=true,id=SELF,name='Tester',zone=102,job=1,self_known=true,self_revision=revision,
        self_timer_revision=timers,self_effects=effects,party={},entities={[SELF]={id=SELF,name='Tester',kind='player'}}};
end;
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
-- Stamped with the 0x063 count of the listing it came after, as the client's own count stamps it.
local function message(id,effect,actor,snap,now)
    local bytes=MOCK.bytes(64);
    MOCK.put(bytes,4,4,actor); MOCK.put(bytes,8,4,SELF); MOCK.put(bytes,12,4,effect); MOCK.put(bytes,24,2,id);
    local entry=observer.read(MOCK.packet(0x029,bytes),now,snap)[1];
    if entry then entry.timer_revision=snap.self_timer_revision; end;
    return entry;
end;
local own=message(205,113,SELF,snapshot(1,0,{}),1);
assert(own and own.kind=='apply' and own.source==SELF,'An item buff message from yourself names you as the caster: '..tostring(own and own.source));
local other=message(205,113,3003,snapshot(1,0,{}),1);
assert(other and other.kind=='apply' and other.source==nil,'A 205 from another actor stays uncredited: '..tostring(other.source));

local tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
local rules={{id='gain',enabled=true,event='gain',effect=0,scope='self',cooldown=0,duration=30,visual=true},
    {id='removed',enabled=true,event='removed',effect=0,scope='self',cooldown=0,duration=30,visual=true}};
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    local view,events=tracker:view(now,{},snap),tracker:drain_events();
    alerts:update(view,events,rules,now,{});
    local notices=alerts:drain(now);
    local out={};
    for _,e in ipairs(events) do out[#out+1]=e.kind..':'..tostring(e.effect)..':'..tostring(e.source); end;
    return view.rows,table.concat(out,','),notices;
end;
frame(snapshot(1,0,{}),0);
local rows,events,notices=frame(snapshot(2,1,{status(113,0,3600,216000)}),1,{message(205,113,SELF,snapshot(1,0,{}),1)});
assert(#rows==1 and rows[1].mine==true and rows[1].source==SELF and #notices==1,'Reraise from an earring is yours: mine='..tostring(rows[1] and rows[1].mine)..' events '..events);
local key=rows[1].key;
frame(snapshot(2,1,{status(113,0,3600,216000)}),5);
-- The earring used again at t=10: 206 then 205 on the same 0x063 count, then the two-copy tick, then the next tick.
local before=snapshot(2,1,{status(113,0,3600,216000)});
local wearoff,gain=message(206,113,SELF,before,10),message(205,113,SELF,before,10);
rows,events,notices=frame(snapshot(4,2,{status(113,0,3600,216000),status(113,1,3609,216540)}),10,{wearoff,gain});
assert(#notices==0 and events=='refresh:113:1001','Using the item again is one renewal, with no gain or removed alert: '..#notices..' notices, events '..events);
rows,events,notices=frame(snapshot(6,3,{status(113,0,3609,216540)}),10.4);
assert(#rows==1 and rows[1].key==key and rows[1].mine==true and events=='' and #notices==0,'The old copy leaves quietly and the row, still yours, keeps its key: events '..events..', '..#notices..' notices.');
