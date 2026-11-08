-- A WAR main's Warcry is up on the party when a /WAR uses Warcry. Phoenix refuses the weaker one
-- (CanGainStatusEffect, equal_higher by power) but still reports the use to every target (116 and 285 with
-- param 68, CCharEntity::OnAbility). A party member's listing has no timer to tell, so the copy is nobody's
-- in particular; the player's own copy keeps its caster, since a Warcry that took restarts its timer.
local observer=require('core.observer');
local client=require('core.client');
local SELF,MAIN,SUB,BOB=1001,2001,2002,1002;
local names={[SELF]='Tester',[MAIN]='Main',[SUB]='Sub',[BOB]='Bob'};
local function bits(bytes,offset,length,value)
    for i=0,length-1 do
        local at=offset+i;
        if math.floor(value/2^i)%2==1 then bytes[math.floor(at/8)]=bytes[math.floor(at/8)]+2^(at%8); end;
    end;
end;
local function action(actor,category,id,targets)
    local bytes,at=MOCK.bytes(2048),150;
    bits(bytes,40,32,actor);bits(bytes,72,6,#targets);bits(bytes,82,4,category);bits(bytes,86,32,id);
    for _,target in ipairs(targets) do
        bits(bytes,at,32,target[1]);bits(bytes,at+32,4,1);at=at+36;
        bits(bytes,at+27,17,target[3]);bits(bytes,at+44,10,target[2]);at=at+87;
    end;
    bytes.n=math.ceil(at/8);
    return MOCK.packet(0x028,bytes);
end;
-- Warcry (32) used by one, reported on all four with its effect (68).
local function warcry(user)
    local targets={};
    for _,id in ipairs({user,SELF,MAIN,SUB,BOB}) do
        local seen=false;for _,t in ipairs(targets) do seen=seen or t[1]==id; end;
        if not seen then targets[#targets+1]={id,id==user and 116 or 285,68}; end;
    end;
    return action(user,6,32,targets);
end;
local tracker,me,party_rev;
-- A 0x063 the client takes in, which the observer's stamps and the listing's count follow.
local function icons063(s)
    local bytes=MOCK.bytes(200);MOCK.put(bytes,4,2,9);
    client.accept(MOCK.packet(0x063,bytes),0,s);
end;
-- A listing carries the client's 0x076 count, as the observer stamps an application with it. No 0x076 comes
-- in here, so the count stays 0: the first listing is from before the Warcry, the next one after it.
local function snap(self_effects)
    local party={};
    for n,id in ipairs({MAIN,SUB,BOB}) do
        if id~=me then
            party[#party+1]={id=id,name=names[id],scope='party',group=1,slot=n,zone=102,valid=true,
                revision=client.party_revision()+party_rev-1,
                effects=party_rev>1 and {{effect=68,slot=0}} or {},hpp=100};
        end;
    end;
    local entities={};
    for id,name in pairs(names) do entities[id]={id=id,name=name,kind='player'}; end;
    local timers=client.self_timer_revision();
    return {valid=true,id=me,name=names[me],zone=102,job=1,self_known=true,self_revision=timers+10,
        self_timer_revision=timers,self_effects=self_effects,party=party,entities=entities};
end;
local function frame(s,now,packets)
    local seen={};
    for _,packet in ipairs(packets or {}) do
        for _,observation in ipairs(observer.read(packet,now,s)) do seen[#seen+1]=observation; end;
    end;
    tracker:observe(seen,now,s);tracker:reconcile(s,now);
    return tracker:view(now,{},s),tracker:drain_events();
end;
local function rows(view)
    local out={};
    for _,row in ipairs(view.rows) do if row.effect==68 then out[row.entity_id]=row; end; end;
    return out;
end;
local function refreshes(events,party)
    local count=0;
    for _,event in ipairs(events) do
        if event.kind=='refresh' and event.effect==68 and (event.entity_id==me)~=party then count=count+1; end;
    end;
    return count;
end;
local first_copy={effect=68,slot=0,raw_timer=1806,deadline=30.1};
-- Start: the first Warcry lands everywhere, and the next listings show it.
local function start(player,first)
    tracker,me,party_rev=require('core.tracker').new(),player,1;
    frame(snap({}),0);
    frame(snap({}),0.1,{warcry(first)});
    icons063(snap({}));party_rev=2;
    return frame(snap({first_copy}),0.15);
end;

for _,case in ipairs({{SELF,'a bystander'},{SUB,'the /WAR'},{MAIN,'the WAR main'}}) do
    local player=case[1];
    for id,row in pairs(rows(start(player,MAIN))) do
        assert(row.source==MAIN,'Fixture: the WAR main gave everyone Warcry: '..case[2]);
    end;
    -- The /WAR's Warcry, refused: no listing changes.
    local view,events=frame(snap({first_copy}),10,{warcry(SUB)});
    local held=rows(view);
    for id,row in pairs(held) do
        if id~=player then
            assert(row.source==nil and row.mine==nil,'A party member\'s copy is nobody\'s after a Warcry that may not have taken: '..case[2]);
        end;
    end;
    assert(refreshes(events,true)==0,'Nor is it a refresh: '..case[2]);
    -- A Protect from the WAR main lands on the player with its own 0x063 within 3 s.
    local protect=action(MAIN,4,43,{{player,230,40}});
    frame(snap({first_copy}),11.5,{protect});
    icons063(snap({first_copy}));
    view,events=frame(snap({{effect=40,slot=0,raw_timer=108090,deadline=1811.5},{effect=68,slot=1,raw_timer=1806,deadline=30.1}}),11.55);
    local own=rows(view)[player];
    assert(own.source==MAIN and own.mine==(player==MAIN) and own.start==0.1 and math.abs(own.total-30)<0.01
        and refreshes(events,false)==0,'The player\'s own copy keeps the WAR main\'s Warcry: '..case[2]);
end;

-- Control: the /WAR's Warcry first, then the WAR main's, which takes and restarts the player's timer.
start(SELF,SUB);
local view,events=frame(snap({first_copy}),10,{warcry(MAIN)});
icons063(snap({first_copy}));
view,events=frame(snap({{effect=68,slot=0,raw_timer=2406,deadline=40.05}}),10.05);
local own=rows(view)[SELF];
assert(own.source==MAIN and own.start==10 and refreshes(events,false)==1,'A Warcry that restarts the player\'s timer is the WAR main\'s.');
-- The same caster's Warcry again on a party member is a refresh of their copy.
start(SELF,MAIN);
view,events=frame(snap({first_copy}),10,{warcry(MAIN)});
assert(rows(view)[BOB].source==MAIN and refreshes(events,true)==3,'A caster\'s own Warcry again refreshes the copy it holds.');
