-- Phoenix's ApplyBardEffect replaces the song of the same status ID and tier (status_effect_container.cpp,
-- GetTier), and spells share tiers: all eight Carols, both Mazurkas, seven Etudes a tier (enhancing_song.lua
-- songPTable). So a song lands on the copy of its tier whatever the spell, on the player and on others.
local tracker;
local SELF,BOB=1001,2001;
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(revision,timers,effects,party)
    return {valid=true,id=SELF,name='Tester',zone=102,job=1,self_known=true,self_revision=revision,
        self_timer_revision=timers,self_effects=effects,party=party or {},entities={}};
end;
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    return tracker:view(now,{},snap),tracker:drain_events();
end;
local function rows(view,effect,entity)
    local out={};
    for _,row in ipairs(view.rows) do
        if row.effect==effect and row.entity_id==(entity or SELF) and row.present~=false then out[#out+1]=row; end
    end
    table.sort(out,function(a,b) return (a.slot or 0)<(b.slot or 0) or a.slot==b.slot and a.key<b.key; end);
    return out;
end;
local function kinds(events)
    local out={};
    for _,event in ipairs(events) do
        out[#out+1]=event.kind..':'..tostring(event.effect)..':'..tostring(event.spell)..'/'..tostring(event.source);
    end;
    return table.concat(out,',');
end;
local function cast(effect,spell,tier,source,count,target)
    return {kind='apply',entity_id=target or SELF,effect=effect,scope=target and 'party' or 'self',source=source,spell=spell,
        tier=tier,timer_revision=target==nil and count or nil,stackable=target and true or nil,
        instance_hint=target and tostring(source)..':'..tostring(spell) or nil,duration=120};
end;

-- The player's Sinewy Etude, then their Dextrous Etude: one tier, so it replaced the first in place and the
-- player's PostTick lists both. One renewal, with no removal.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
local view=frame(snapshot(2,1,{status(215,0,130,7800)}),10,{cast(215,424,1,SELF,0)});
local key=rows(view,215)[1].key;
local events;
view,events=frame(snapshot(4,2,{status(215,0,130,7800),status(215,1,170,10200)}),50,{cast(215,425,1,SELF,1)});
assert(kinds(events)=='refresh:215:425/1001' and rows(view,215)[2].key==key and rows(view,215)[1].departing,
    'Dextrous Etude renews Sinewy\'s copy: '..kinds(events));
view,events=frame(snapshot(6,3,{status(215,0,170,10200)}),50.4);
assert(#events==0 and rows(view,215)[1].key==key and rows(view,215)[1].spell==425,'Nothing wore off: '..kinds(events));

-- 2002's Fire Carol, then the player's Ice Carol: every Carol is one tier.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
view=frame(snapshot(2,1,{status(216,0,130,7800)}),10,{cast(216,438,1,2002,0)});
key=rows(view,216)[1].key;
view,events=frame(snapshot(4,2,{status(216,0,130,7800),status(216,1,170,10200)}),50,{cast(216,439,1,SELF,1)});
assert(kinds(events)=='refresh:216:439/1001' and rows(view,216)[2].key==key and rows(view,216)[2].mine
    and rows(view,216)[1].source==2002 and rows(view,216)[1].spell==438,'Ice Carol renews Fire Carol\'s copy: '..kinds(events));
view,events=frame(snapshot(6,3,{status(216,0,170,10200)}),50.4);
assert(#events==0 and rows(view,216)[1].key==key,'And no removal: '..kinds(events));

-- 2002's Sinewy (tier 1) and 2004's Herculean (tier 2) are up. 2003's Uncanny (tier 2) and 2005's Dextrous
-- (tier 1) land in one tick, each on the copy of its tier.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(215,0,120,7200)}),0,{cast(215,424,1,2002,0)});
frame(snapshot(3,2,{status(215,0,120,7200),status(215,1,130,7800)}),10,{cast(215,431,2,2004,1)});
view,events=frame(snapshot(5,3,{status(215,0,170,10200),status(215,1,170,10200)}),50,{cast(215,432,2,2003,2),cast(215,425,1,2005,2)});
local etude=rows(view,215);
assert(etude[1].spell==425 and etude[1].source==2005 and etude[1].tier==1 and etude[2].spell==432 and etude[2].source==2003
    and etude[2].tier==2,'Each copy has the song of its tier.');

-- Another bard's Etude of the same tier that moved the timer too little to see still took the copy.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(215,0,130,7800)}),10,{cast(215,424,1,2002,0)});
view,events=frame(snapshot(4,2,{status(215,0,130.5,7800)}),10.5,{cast(215,425,1,2003,1)});
assert(kinds(events)=='refresh:215:425/2003' and rows(view,215)[1].source==2003,'2003\'s Dextrous took it: '..kinds(events));

-- Two Etudes of one tier before one listing: the later replaced the earlier, so a new copy is the later.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
view,events=frame(snapshot(2,2,{status(215,0,220.4,13200)}),100.4,{cast(215,424,1,2002,0),cast(215,426,1,2003,1)});
assert(kinds(events)=='gain:215:426/2003','The new copy is 2003\'s: '..kinds(events));

-- On a party member: 2003's Dextrous replaces 2002's Sinewy; Herculean is another tier and stacks; the two
-- Mazurkas share one tier.
tracker=require('core.tracker').new();
local function party(effects,revision)
    return {{id=BOB,name='Bob',scope='party',valid=true,zone=102,revision=revision,effects=effects}};
end;
frame(snapshot(1,0,{},party({},1)),0);
frame(snapshot(1,0,{},party({},1)),1,{cast(215,424,1,2002,nil,BOB)});
view,events=frame(snapshot(1,0,{},party({{effect=215,slot=0}},2)),2);
key=rows(view,215,BOB)[1].key;
view,events=frame(snapshot(1,0,{},party({{effect=215,slot=0}},2)),30,{cast(215,425,1,2003,nil,BOB)});
local bob=rows(view,215,BOB);
assert(#bob==1 and bob[1].key==key and bob[1].source==2003 and bob[1].spell==425 and kinds(events)=='refresh:215:425/2003',
    'One Etude on Bob, now 2003\'s: '..kinds(events));
view,events=frame(snapshot(1,0,{},party({{effect=215,slot=0}},2)),31,{cast(215,431,2,2003,nil,BOB)});
assert(#rows(view,215,BOB)==2 and kinds(events)=='gain:215:431/2003','Herculean is a second copy: '..kinds(events));
view,events=frame(snapshot(1,0,{},party({{effect=215,slot=0}},2)),32,{cast(219,465,1,2002,nil,BOB),cast(219,466,1,2004,nil,BOB)});
local mazurka=rows(view,219,BOB);
assert(#mazurka==1 and mazurka[1].source==2004 and mazurka[1].spell==466,'One Mazurka: '..kinds(events));
