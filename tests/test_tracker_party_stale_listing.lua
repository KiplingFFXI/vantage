-- A party member's 0x076 copies their icon cache, which on Phoenix keeps a copy that was replaced or removed
-- until their own next tick (status_effect_container.cpp: RemoveStatusEffect only marks it deleted and
-- UpdateStatusIcons walks deleted copies). Another member's PostTick in between sends it once more. So a
-- copy listed once more after an application landed on it, or after its removal was seen, is no gain, no
-- second removal, and the row keeps its caster and countdown.
local tracker,alerts;
local SELF,BOB=1001,2002;
local function snapshot(rev,bob)
    return {valid=true,id=SELF,name='Tester',zone=102,job=10,self_known=true,self_revision=1,self_timer_revision=1,
        self_effects={},party={{id=BOB,name='Bob',scope='party',group=1,slot=1,zone=102,valid=true,revision=rev,effects=bob}},
        entities={[BOB]={id=BOB,name='Bob',kind='player'}}};
end;
local rules={{id='gain',enabled=true,event='gain',effect=0,scope='party',cooldown=0,duration=30,visual=true},
    {id='removed',enabled=true,event='removed',effect=0,scope='party',cooldown=0,duration=30,visual=true}};
local notices;
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    local view,events=tracker:view(now,{},snap),tracker:drain_events();
    alerts:update(view,events,rules,now,{});
    notices=#alerts:drain(now);
    return view,events;
end;
local function count(events,kind)
    local n=0;for _,e in ipairs(events) do if e.kind==kind then n=n+1;end;end;return n;
end;
local function bob(view,effect)
    local out={};for _,r in ipairs(view.rows) do if r.entity_id==BOB and r.effect==effect then out[#out+1]=r;end;end;return out;
end;
local function fresh()
    tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
    frame(snapshot(1,{}),0);
end;

-- The player resings Valor Minuet IV on the party. The caster's PostTick lists Bob's old copy beside the new one.
local sing={{kind='apply',entity_id=BOB,effect=198,scope='party',source=SELF,spell=397,tier=4,
    stackable=true,instance_hint=SELF..':397',duration=144}};
fresh();
frame(snapshot(2,{{effect=198,slot=0}}),10,sing);
local view,events=frame(snapshot(3,{{effect=198,slot=0},{effect=198,slot=1}}),70,sing);
assert(count(events,'gain')==0 and count(events,'refresh')==1 and #bob(view,198)==1,
    'A resung song listed once more beside its old copy is one refresh, no gain.');
view,events=frame(snapshot(4,{{effect=198,slot=0}}),70.4);
local row=bob(view,198)[1];
assert(#events==0 and #bob(view,198)==1 and row.source==SELF and row.spell==397 and row.remaining and row.remaining>140,
    'Bob\'s Minuet keeps its caster, spell and countdown once the old copy is gone.');
view,events=frame(snapshot(5,{{effect=198,slot=0}}),75);
assert(#events==0 and bob(view,198)[1].source==SELF,'And keeps them.');

-- Protectra on the party: Bob's Protect from another caster is replaced in place.
fresh();
frame(snapshot(2,{{effect=40,slot=0}}),1);
view,events=frame(snapshot(3,{{effect=40,slot=0},{effect=40,slot=1}}),10,
    {{kind='apply',entity_id=BOB,effect=40,scope='party',source=SELF,spell=129,duration=1800}});
assert(count(events,'gain')==0 and notices==0,'Protectra over a listed Protect is no gain.');
view,events=frame(snapshot(4,{{effect=40,slot=0}}),10.4);
assert(#events==0 and bob(view,40)[1].source==SELF and bob(view,40)[1].spell==129,'The Protect row keeps Protectra\'s caster.');

-- The player's Erase on Bob, then another member's 0x076 that still copies Bob's Poison, then Bob's own.
fresh();
frame(snapshot(2,{{effect=3,slot=0}}),1);
view,events=frame(snapshot(2,{{effect=3,slot=0}}),10,{{kind='remove',entity_id=BOB,effect=3,scope='party',reason='Observed removal'}});
assert(count(events,'removed')==1 and notices==1,'The Erase is one removal.');
view,events=frame(snapshot(3,{{effect=3,slot=0}}),10.05);
assert(#events==0 and notices==0,'A newer listing that still copies the removed Poison is no gain.');
view,events=frame(snapshot(4,{}),10.4);
assert(#events==0 and notices==0 and #bob(view,3)==0,'The listing that drops it is no second removal.');
-- The listing from before the removal, read again, is no gain either.
fresh();
frame(snapshot(2,{{effect=3,slot=0}}),1);
frame(snapshot(2,{{effect=3,slot=0}}),10,{{kind='remove',entity_id=BOB,effect=3,scope='party',reason='Observed removal'}});
view,events=frame(snapshot(2,{{effect=3,slot=0}}),20);
assert(#events==0 and #bob(view,3)==0,'The cached listing from before the removal brings nothing back.');

-- A Corsair at the roll cap: the oldest roll's wear-off, then a 0x076 that still lists it beside the new roll.
fresh();
frame(snapshot(2,{{effect=310,slot=0},{effect=311,slot=1}}),1);
view,events=frame(snapshot(2,{{effect=310,slot=0},{effect=311,slot=1}}),10,
    {{kind='remove',entity_id=BOB,effect=310,scope='party',source=SELF,reason='Observed wearoff'},
     {kind='apply',entity_id=BOB,effect=312,scope='party',source=SELF,spell=100,duration=300}});
assert(count(events,'removed')==1 and count(events,'gain')==1,'The evicted roll is one removal and the new roll one gain.');
view,events=frame(snapshot(3,{{effect=310,slot=0},{effect=311,slot=1},{effect=312,slot=2}}),10.05);
assert(#events==0 and notices==0,'The evicted roll listed once more is no gain.');
view,events=frame(snapshot(4,{{effect=311,slot=0},{effect=312,slot=1}}),10.4);
assert(#events==0 and notices==0 and #bob(view,310)==0,'The listing that drops it is no second removal.');

-- A removed effect listed again well after its removal, by a newer listing, is back.
fresh();
frame(snapshot(2,{{effect=40,slot=0}}),1);
frame(snapshot(2,{{effect=40,slot=0}}),10,{{kind='remove',entity_id=BOB,effect=40,scope='party',reason='Observed removal'}});
view,events=frame(snapshot(3,{{effect=40,slot=0}}),16);
assert(count(events,'gain')==1 and #bob(view,40)==1,'A newer listing still holding it after 5 s brings it back.');
-- And one cast again right after its removal is a gain at once.
fresh();
frame(snapshot(2,{{effect=40,slot=0}}),1);
frame(snapshot(2,{{effect=40,slot=0}}),10,{{kind='remove',entity_id=BOB,effect=40,scope='party',reason='Observed removal'}});
view,events=frame(snapshot(2,{{effect=40,slot=0}}),11,{{kind='apply',entity_id=BOB,effect=40,scope='party',source=SELF,spell=43,duration=1800}});
assert(count(events,'gain')==1 and #bob(view,40)==1 and not bob(view,40)[1].departing,'Protect cast again after its removal is back.');
