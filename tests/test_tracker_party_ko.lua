-- A party member's KO on Phoenix (CCharEntity::Die): the defeat message (97 when a mob killed them, 20 with
-- no attacker), the effects with the death flag dropped silently, and their next 0x076 listing what is
-- left. As for the player's own KO, that is no removal of each effect and nothing is missing on them while
-- they are down; their rows keep who cast them. Once raised, their listing counts again.
local observer=require('core.observer');
local tracker,alerts;
local SELF,BOB,CRAB=1001,2002,0x1000010;
local function snapshot(rev,effects,hpp)
    return {valid=true,id=SELF,name='Tester',zone=102,job=3,self_known=true,self_revision=1,self_timer_revision=1,
        self_effects={},party={{id=BOB,name='Bob',scope='party',group=1,slot=1,zone=102,valid=true,revision=rev,effects=effects,hpp=hpp}},
        entities={[BOB]={id=BOB,name='Bob',kind='player'},[CRAB]={id=CRAB,name='Crab',kind='monster'}}};
end;
local rules={{id='removed',enabled=true,event='removed',effect=0,scope='party',cooldown=0,duration=30,visual=true},
    {id='missing',enabled=true,event='missing',effect=33,scope='party',entity_id=BOB,cooldown=0,duration=30,visual=true}};
local notices;
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    local view,events=tracker:view(now,{},snap),tracker:drain_events();
    alerts:update(view,events,rules,now,{});
    notices={};for _,n in ipairs(alerts:drain(now)) do notices[#notices+1]=n.message;end;
    return view,events;
end;
local function defeat(message,actor)
    local data={};for i=1,32 do data[i]='\0';end;
    local function put(at,value) for i=0,3 do data[at+i+1]=string.char(math.floor(value/256^i)%256);end;end;
    put(4,actor);put(8,BOB);data[25]=string.char(message);
    local text=table.concat(data);
    local bytes={n=#text};for i=0,#text-1 do bytes[i]=text:byte(i+1);end;
    return {id=0x029,size=#text,data=text,data_raw=bytes,injected=false,blocked=false};
end;
local function bob(view)
    local out={};for _,r in ipairs(view.rows) do if r.entity_id==BOB then out[#out+1]=r;end;end;return out;
end;
local buffs={{effect=40,slot=0},{effect=33,slot=1}};
for _,case in ipairs({{97,CRAB,'a mob'},{20,BOB,'no attacker'}}) do
    tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
    local snap=snapshot(1,{},100);
    frame(snap,0);
    frame(snapshot(2,buffs,100),1,{{kind='apply',entity_id=BOB,effect=40,scope='party',source=SELF,spell=43,duration=1800},
        {kind='apply',entity_id=BOB,effect=33,scope='party',source=SELF,spell=57,duration=180}});
    snap=snapshot(2,buffs,100);
    local seen=observer.read(defeat(case[1],case[2]),5,snap);
    assert(#seen==1 and seen[1].kind=='death' and seen[1].entity_id==BOB,'The defeat message ('..case[3]..') is read as a death.');
    local view,events=frame(snap,5,seen);
    assert(#bob(view)==2 and bob(view)[1].source==SELF,'KO by '..case[3]..': Bob\'s rows stay, with their caster.');
    -- The next 0x076 drops the death-flag effects; their HP update can come after it.
    view,events=frame(snapshot(3,{},100),5.4);
    assert(#events==0 and #notices==0,'KO by '..case[3]..': nothing is announced as removed and nothing is missing.');
    view,events=frame(snapshot(3,{},0),6);
    for _=1,5 do view,events=frame(snapshot(3,{},0),7+_);assert(#notices==0,'Nothing is missing on Bob while he is down.');end;
    -- Raised: Weakness, then the listing counts again.
    view,events=frame(snapshot(4,{{effect=1,slot=0}},10),20);
    assert(#notices==0,'The listing at the raise is read quietly too.');
    view,events=frame(snapshot(5,{{effect=1,slot=0}},10),21);
    view,events=frame(snapshot(6,{},10),30);
    assert(#events==1 and events[1].kind=='removed','Once raised, a removal is announced again.');
end;

-- An alliance member (slot 6 on, no listing of their own) or a party member whose listing hasn't come yet:
-- nothing will drop their effects, so their KO forgets their rows, quietly.
for _,case in ipairs({{'alliance',6},{'party',2}}) do
    for _,message in ipairs({97,20}) do
        tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
        local function far(rev)
            local snap=snapshot(rev,{},100);
            snap.party[1].scope,snap.party[1].slot,snap.party[1].valid=case[1],case[2],false;
            snap.party[1].group=case[1]=='alliance' and 2 or 1;
            return snap;
        end;
        frame(far(1),0);
        frame(far(1),1,{{kind='apply',entity_id=BOB,effect=33,scope=case[1],source=SELF,spell=57,duration=180}});
        local snap=far(1);
        local view,events=frame(snap,5,observer.read(defeat(message,message==97 and CRAB or BOB),5,snap));
        local loud=0;for _,e in ipairs(events) do if not e.quiet then loud=loud+1;end;end;
        assert(#bob(view)==0 and loud==0 and #notices==0,
            'A KO with no listing to follow forgets the rows quietly: '..case[1]..' '..message);
    end;
end;
