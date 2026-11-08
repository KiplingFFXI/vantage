-- The copy the player's own action replaces is only marked deleted (OverwriteStatusEffect, ApplyBardEffect)
-- and erased at the next CheckEffectsExpiry, so the player's PostTick lists it once more, before the new
-- copy (statusOrdering keeps equal keys in insertion order). Phoenix status_effect_container.cpp. Whatever
-- else that listing holds, the player's cast is one refresh or one gain, and the old copy leaves with no
-- removal.
local tracker;
local SELF=1001;
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(revision,timers,effects,pending)
    return {valid=true,id=SELF,name='Tester',zone=102,job=1,self_known=true,self_revision=revision,
        self_timer_revision=timers,self_timers_pending=pending,self_effects=effects,party={},entities={}};
end;
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    return tracker:view(now,{},snap),tracker:drain_events();
end;
local function rows(view,effect)
    local out={};
    for _,row in ipairs(view.rows) do if row.effect==effect and row.present~=false then out[#out+1]=row; end; end;
    table.sort(out,function(a,b) return a.slot<b.slot; end);
    return out;
end;
local function kinds(events)
    local out={};
    for _,event in ipairs(events) do out[#out+1]=event.kind..':'..tostring(event.effect)..':'..tostring(event.source); end;
    return table.concat(out,',');
end;
local function cast(effect,spell,source,count,extra)
    local out={kind='apply',entity_id=SELF,effect=effect,scope='self',source=source,spell=spell,timer_revision=count};
    for key,value in pairs(extra or {}) do out[key]=value; end;
    return out;
end;

-- No Haste up. 2002 casts it and the player casts it the same tick (or 2002 the tick before, after the
-- player's PostTick): the player's replaced 2002's before any listing showed it, so both are listed.
for _,split in ipairs({false,true}) do
    tracker=require('core.tracker').new();
    frame(snapshot(1,0,{status(40,0,1800,108000)}),0);
    local view,events;
    if split then
        view,events=frame(snapshot(2,0,{status(33,0,nil,nil),status(33,1,nil,nil),status(40,2,nil,nil)},true),100,
            {cast(33,57,2002,0),cast(33,57,SELF,0)});
        assert(#events==0,'The 0x037 alone gains nothing.');
        view,events=frame(snapshot(3,1,{status(33,0,180,6000),status(33,1,180,6000),status(40,2,1800,108000)}),100.05);
    else
        view,events=frame(snapshot(3,1,{status(33,0,180,6000),status(33,1,180,6000),status(40,2,1800,108000)}),100,
            {cast(33,57,2002,0),cast(33,57,SELF,0)});
    end
    local both=rows(view,33);
    assert(kinds(events)=='gain:33:1001','One gain, the player\'s: '..kinds(events));
    assert(#both==2 and both[2].source==SELF and both[2].mine and not both[2].departing and both[1].departing
        and both[1].source==2002,'The new copy is the player\'s; the one before it shows 2002\'s and leaves.');
    local key=both[2].key;
    view,events=frame(snapshot(5,2,{status(33,0,180,6000),status(40,1,1800,108000)}),100.4);
    assert(#events==0 and #rows(view,33)==1 and rows(view,33)[1].key==key and rows(view,33)[1].source==SELF,
        'The old copy leaves with no removal: '..kinds(events));
end;

-- The same with a song: 2003's 394 and the player's 394, one tier.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{status(40,0,1800,108000)}),0);
local view,events=frame(snapshot(3,1,{status(40,0,1800,108000),status(198,1,220,13200),status(198,2,220,13200)}),100,
    {cast(198,394,2003,0),cast(198,394,SELF,0)});
assert(kinds(events)=='gain:198:1001' and rows(view,198)[2].source==SELF and rows(view,198)[1].departing,
    'One gain for the song, the player\'s: '..kinds(events));
view,events=frame(snapshot(5,2,{status(40,0,1800,108000),status(198,1,220,13200)}),100.4);
assert(#events==0 and rows(view,198)[1].source==SELF,'No removal.');

-- The player's March replaces their own; the copy listed after the old one is the new one even when it
-- reads like 2002's 419 within a restamp step: 2004 replaced that one in its slot after the player's last
-- PostTick, and 2004's copy is listed in 2002's place.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
view=frame(snapshot(2,1,{status(214,0,130,7800)}),10,{cast(214,420,SELF,0)});
local mine=rows(view,214)[1].key;
view=frame(snapshot(3,2,{status(214,0,130,7800),status(214,1,160,9600)}),11,{cast(214,419,2002,1)});
local theirs=rows(view,214)[2].key;
frame(snapshot(3,2,{status(214,0,130,7800),status(214,1,160,9600)}),40,{cast(214,419,2004,2)});
view,events=frame(snapshot(5,3,{status(214,0,130,7800),status(214,1,161,9660),status(214,2,200,12000)}),40.4,
    {cast(214,420,SELF,2)});
local march=rows(view,214);
assert(kinds(events)=='refresh:214:1001,refresh:214:2004','The player\'s March and 2004\'s are renewals: '..kinds(events));
assert(march[2].key==mine and march[2].source==SELF and march[2].spell==420 and march[1].departing
    and march[3].key==theirs and march[3].source==2004 and march[3].spell==419,'Each row is on its own copy.');
view,events=frame(snapshot(7,4,{status(214,0,161,9660),status(214,1,200,12000)}),40.8);
assert(#events==0 and rows(view,214)[1].key==mine and rows(view,214)[2].key==theirs,'And nothing wore off: '..kinds(events));

-- 2002 is at its cap (419 and 394) and sings 420 over the player's 420, the tick before the player sings
-- it again: 2002's 420 took the player's copy (same tier) and 419's slot (the one of 2002's ending first).
-- The player's PostTick lists 2002's 420, deleted, and the player's. 2002's 419 was lost.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(214,0,120,7200)}),10,{cast(214,419,2002,0)});
frame(snapshot(3,2,{status(214,0,120,7200),status(198,1,130,7800)}),10.4,{cast(198,394,2002,1)});
view=frame(snapshot(4,3,{status(214,0,120,7200),status(198,1,130,7800),status(214,2,140,8400)}),20,{cast(214,420,SELF,2)});
mine=rows(view,214)[2].key;
frame(snapshot(4,3,{status(214,0,120,7200),status(198,1,130,7800),status(214,2,140,8400)}),50,{cast(214,420,2002,3)});
view,events=frame(snapshot(6,4,{status(214,0,170,10200),status(214,1,170,10200),status(198,2,130,7800)}),50.4,
    {cast(214,420,SELF,3)});
march=rows(view,214);
assert(kinds(events)=='removed:214:2002,refresh:214:1001','2002\'s 419 went and the player\'s March is renewed: '..kinds(events));
assert(march[2].key==mine and march[2].source==SELF and march[2].spell==420 and march[1].departing and march[1].source==2002
    and march[1].spell==420,'The row is on the player\'s copy; the one before it shows 2002\'s 420.');
view,events=frame(snapshot(8,5,{status(214,0,170,10200),status(198,1,130,7800)}),50.8);
assert(#events==0 and rows(view,214)[1].key==mine and rows(view,214)[1].source==SELF,'And the player\'s March stays: '..kinds(events));

-- Copies read alike: 2002's 419 and the player's 420 read the same timer. The player sings 420 over their
-- cap: it takes the slot of their 394, which ends first, listed beside it, and the old 420 stays listed in
-- its own slot. The row of the old copy keeps its place among the rows that read alike.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(214,0,970,58200)}),850,{cast(214,419,2002,0)});
frame(snapshot(3,2,{status(214,0,970,58200),status(198,1,963,57780)}),851,{cast(198,394,SELF,1)});
view=frame(snapshot(4,3,{status(214,0,970,58200),status(198,1,963,57780),status(214,2,970,58200)}),850.5,{cast(214,420,SELF,2)});
mine=rows(view,214)[2].key;
local key419=rows(view,214)[1].key;
view,events=frame(snapshot(6,4,{status(214,0,970,58200),status(198,1,964,57840),status(214,2,996,59760),status(214,3,970,58200)}),
    876.8,{cast(214,420,SELF,3)});
march=rows(view,214);
assert(kinds(events)=='refresh:214:1001','One refresh: '..kinds(events));
assert(march[1].key==key419 and march[1].source==2002 and march[2].key==mine and march[2].raw_timer==59760 and march[3].departing,
    '2002\'s 419 keeps its copy; the player\'s row moves to the new one beside 394.');
view,events=frame(snapshot(8,5,{status(214,0,970,58200),status(214,1,996,59760)}),877.2);
assert(kinds(events)=='removed:198:1001' and rows(view,214)[2].key==mine,'394 was lost to the cap: '..kinds(events));

-- Over the cap again, the song whose slot the new one takes is another effect of the same tier: the
-- player's Minuet, tier 2 like the player's Vital Etude. It sorts first in that slot.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
view=frame(snapshot(2,1,{status(215,0,600,36000)}),480,{cast(215,433,SELF,0,{tier=2})});
mine=rows(view,215)[1].key;
frame(snapshot(3,2,{status(215,0,600,36000),status(198,1,509,30540)}),389,{cast(198,395,SELF,1,{tier=2})});
view,events=frame(snapshot(5,3,{status(215,0,600,36000),status(198,1,509,30540),status(215,2,609,36540)}),489.4,
    {cast(215,433,SELF,2,{tier=2})});
assert(kinds(events)=='refresh:215:1001' and rows(view,215)[2].key==mine and rows(view,215)[1].departing,
    'The Etude is renewed beside the Minuet: '..kinds(events));
view,events=frame(snapshot(7,4,{status(215,0,609,36540)}),489.8);
assert(kinds(events)=='removed:198:1001' and rows(view,215)[1].key==mine,'The Minuet was lost: '..kinds(events));

-- Under the cap the player's 394 replaces 2003's in its slot, right after it, though it reads like it and
-- the player's March is listed just before: a song over the cap would sort before March (198 < 214).
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(214,0,375,22500)}),255,{cast(214,420,SELF,0)});
frame(snapshot(3,2,{status(214,0,375,22500),status(198,1,437,26220)}),317,{cast(198,394,2003,1)});
view=frame(snapshot(4,3,{status(214,0,375,22500),status(198,1,437,26220),status(198,2,403,24180)}),283,{cast(198,395,2003,2)});
local theirs394,theirs395=rows(view,198)[1].key,rows(view,198)[2].key;
view,events=frame(snapshot(6,4,{status(214,0,375,22500),status(198,1,437,26220),status(198,2,438,26280),status(198,3,403,24180)}),
    319.7,{cast(198,394,SELF,3)});
local songs=rows(view,198);
assert(kinds(events)=='refresh:198:1001' and songs[2].key==theirs394 and songs[2].source==SELF and songs[1].departing
    and songs[3].key==theirs395,'The 394 row takes the new copy of the player: '..kinds(events));
view,events=frame(snapshot(8,5,{status(214,0,375,22500),status(198,1,438,26280),status(198,2,403,24180)}),320.3);
assert(#events==0 and rows(view,198)[1].key==theirs394 and rows(view,214)[1].source==SELF,'Nothing wore off: '..kinds(events));

-- Over the cap again, and the new March reads like the old one a second later: it is the copy beside the
-- Minuet whose slot it took, not a pair in place.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(214,0,4386,263160)}),4266,{cast(214,419,2002,0)});
frame(snapshot(3,2,{status(214,0,4386,263160),status(198,1,4362,261720)}),4242,{cast(198,395,2003,1)});
frame(snapshot(4,3,{status(214,0,4386,263160),status(198,1,4362,261720),status(198,2,4377,262620)}),4257,{cast(198,394,SELF,2)});
view=frame(snapshot(5,4,{status(214,0,4386,263160),status(198,1,4362,261720),status(198,2,4377,262620),status(214,3,4400,264000)}),
    4280,{cast(214,420,SELF,3)});
local ours=rows(view,214)[2].key;
view,events=frame(snapshot(7,5,{status(214,0,4386,263160),status(198,1,4361,261660),status(198,2,4377,262620),status(214,3,4401,264060),
    status(214,4,4400,264000)}),4282.7,{cast(214,420,SELF,4)});
assert(kinds(events)=='refresh:214:1001' and rows(view,214)[2].key==ours and rows(view,214)[2].raw_timer==264060
    and rows(view,214)[3].departing,'The March row moves to the copy beside the Minuet: '..kinds(events));
view,events=frame(snapshot(9,6,{status(214,0,4386,263160),status(198,1,4362,261720),status(214,2,4401,264120)}),4283);
assert(kinds(events)=='removed:198:1001' and rows(view,214)[2].key==ours,'The Minuet was lost: '..kinds(events));

-- At the cap the new song sorts by status ID in the slot it takes: beside the Ballad (196) it goes after it;
-- the player's March (214) before 2003's old copy can't hold it.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(214,0,375,22500)}),255,{cast(214,420,SELF,0)});
frame(snapshot(3,2,{status(214,0,375,22500),status(198,1,437,26220)}),317,{cast(198,394,2003,1)});
view=frame(snapshot(4,3,{status(214,0,375,22500),status(198,1,437,26220),status(196,2,350,21000)}),230,{cast(196,386,SELF,2)});
local old394=rows(view,198)[1].key;
view,events=frame(snapshot(6,4,{status(214,0,375,22500),status(198,1,437,26220),status(196,2,350,21000),status(198,3,438,26280)}),
    319.7,{cast(198,394,SELF,3)});
assert(kinds(events)=='refresh:198:1001' and rows(view,198)[2].key==old394 and rows(view,198)[2].raw_timer==26280
    and rows(view,198)[1].departing,'The 394 row moves to the copy after the Ballad: '..kinds(events));
view,events=frame(snapshot(8,5,{status(214,0,375,22500),status(198,1,438,26280)}),320.1);
assert(kinds(events)=='removed:196:1001' and rows(view,198)[1].key==old394,'The Ballad was lost: '..kinds(events));

-- 2002's March and the player's read one timer. With one song of their own up, the player is under the cap
-- of a bard with an instrument: the new copy is in place, after 2002's, though the player's Minuet is listed
-- just before it.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(198,0,4879,292740)}),4760,{cast(198,394,SELF,0)});
view=frame(snapshot(3,2,{status(198,0,4879,292740),status(214,1,4897,293820)}),4777,{cast(214,420,2002,1)});
local march2002=rows(view,214)[1].key;
view,events=frame(snapshot(5,3,{status(198,0,4879,292740),status(214,1,4897,293820),status(214,2,4897,293820)}),4778.7,
    {cast(214,420,SELF,2)});
assert(kinds(events)=='refresh:214:1001' and rows(view,214)[2].key==march2002 and rows(view,214)[1].departing
    and rows(view,214)[1].source==2002,'The player renews the March in place: '..kinds(events));
view,events=frame(snapshot(7,4,{status(198,0,4879,292740),status(214,1,4897,293820)}),4779);
assert(#events==0 and rows(view,214)[1].key==march2002 and rows(view,198)[1].source==SELF,'Nothing wore off: '..kinds(events));
-- Over the cap the replaced copy counts only if it was the player's: 2003's Etude ends before the player's
-- Minuet, which still makes way for the new Etude.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(215,0,5169,310140)}),5049,{cast(215,425,2003,0,{tier=1})});
frame(snapshot(3,2,{status(215,0,5169,310140),status(215,1,5186,311160)}),5066,{cast(215,433,SELF,1,{tier=2})});
view=frame(snapshot(4,3,{status(215,0,5169,310140),status(215,1,5186,311160),status(198,2,5173,310380)}),5053,{cast(198,395,SELF,2,{tier=2})});
local etude2003=rows(view,215)[1].key;
view,events=frame(snapshot(6,4,{status(215,0,5169,310140),status(215,1,5186,311160),status(198,2,5173,310380),status(215,3,5190,311400)}),
    5071,{cast(215,426,SELF,3,{tier=1})});
local etudes=rows(view,215);
assert(kinds(events)=='refresh:215:1001' and etudes[3].key==etude2003 and etudes[3].spell==426 and etudes[1].departing,
    'The tier 1 Etude row moves to the new copy beside the Minuet: '..kinds(events));
view,events=frame(snapshot(8,5,{status(215,0,5186,311160),status(215,1,5190,311400)}),5071.4);
assert(kinds(events)=='removed:198:1001' and rows(view,215)[2].key==etude2003,'The Minuet was lost: '..kinds(events));

-- Two rows read the copy after the first: the old copy is the one in the moving row's own place.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(214,0,4672.6,280560)}),4560,{cast(214,419,2002,0)});
view=frame(snapshot(3,2,{status(214,0,4672.6,280560),status(214,1,4678,280680)}),4558,{cast(214,420,SELF,1)});
mine,key419=rows(view,214)[2].key,rows(view,214)[1].key;
view,events=frame(snapshot(5,3,{status(214,0,4677,280620),status(214,1,4679,280740),status(214,2,4709,282540)}),4589.9,
    {cast(214,420,SELF,2)});
march=rows(view,214);
assert(kinds(events)=='refresh:214:1001' and march[1].key==key419 and march[1].instance==1 and march[2].departing
    and march[3].key==mine and march[3].raw_timer==282540,'The 419 row stays first; the player\'s moves on: '..kinds(events));
-- And when the new copy reads like another row, the pair that keeps the rows' order is the one.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(198,0,7048,422880)}),6928.9,{cast(198,395,2003,0)});
view=frame(snapshot(3,2,{status(198,0,7048,422880),status(198,1,7048,422880)}),6929.3,{cast(198,394,2002,1)});
local key395,key394=rows(view,198)[1].key,rows(view,198)[2].key;
view,events=frame(snapshot(5,3,{status(198,0,7048,422880),status(198,1,7047,422820),status(198,2,7048,422880)}),6929.8,
    {cast(198,394,SELF,2)});
local minuet=rows(view,198);
assert(kinds(events)=='refresh:198:1001' and minuet[1].key==key395 and minuet[1].source==2003 and minuet[2].departing
    and minuet[2].source==2002 and minuet[3].key==key394 and minuet[3].source==SELF,'395 stays first: '..kinds(events));

-- Only the cast's own tick lists its old copy: the next 0x063 is after the next tick's erase. When the
-- client misses that listing (a split send), a later one has no old copy in it.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
view=frame(snapshot(2,1,{status(214,0,120,7200)}),10,{cast(214,420,2002,0)});
local key=rows(view,214)[1].key;
frame(snapshot(4,2,{status(214,0,nil,nil),status(214,1,nil,nil),status(214,2,nil,nil)},true),11.3,
    {cast(214,420,SELF,1),cast(214,419,2004,2)});
view,events=frame(snapshot(6,3,{status(214,0,121,7260),status(214,1,150,9000)}),11.6);
march=rows(view,214);
assert(march[1].key==key and march[1].source==SELF and march[2].source==2004 and march[2].spell==419 and not march[1].departing,
    'No copy is taken for an old one: '..kinds(events));

-- The player's own Refresh, which always overwrites: its wear-off and cast come before a split listing, and
-- the 0x063 of that tick is read only with the next one, after the old copy was dropped. One renewal.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
view=frame(snapshot(2,1,{status(43,0,150,9000)}),0.5,{cast(43,109,SELF,0)});
key=rows(view,43)[1].key;
view,events=frame(snapshot(3,1,{status(43,0,nil,nil),status(43,1,nil,nil)},true),100,
    {{kind='remove',entity_id=SELF,effect=43,scope='self',timer_revision=1},cast(43,109,SELF,1)});
assert(#events==0,'Nothing yet.');
view,events=frame(snapshot(5,3,{status(43,0,250,15000)}),100.4);
assert(kinds(events)=='refresh:43:1001' and rows(view,43)[1].key==key and not rows(view,43)[1].departing,
    'One renewal: '..kinds(events));

-- Double-Up Chance is re-added by every Phantom Roll with no message naming it (corsair.lua corsairSetup):
-- the old copy and the new one are listed, and the next tick drops the old one.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
view=frame(snapshot(2,1,{status(308,0,45,2700)}),0);
key=rows(view,308)[1].key;
view,events=frame(snapshot(4,2,{status(308,0,45,2700),status(308,1,60,3600)}),15,{cast(310,98,SELF,1)});
assert(kinds(events)=='refresh:308:nil' and rows(view,308)[2].key==key and rows(view,308)[2].instance==2
    and rows(view,308)[1].departing,'One silent renewal: '..kinds(events));
view,events=frame(snapshot(6,3,{status(308,0,60,3600)}),15.4);
assert(#events==0 and rows(view,308)[1].key==key,'No removal: '..kinds(events));
-- A copy something else announced is no renewal: an enchantment wearing the Haste icon sends 205.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
view=frame(snapshot(2,1,{status(33,0,150,9000)}),0,{cast(33,57,2001,0)});
key=rows(view,33)[1].key;
view,events=frame(snapshot(4,2,{status(33,0,150,9000),status(33,1,200,12000)}),10,
    {{kind='apply',entity_id=SELF,effect=33,scope='self',timer_revision=1}});
assert(kinds(events)=='gain:33:nil' and rows(view,33)[1].key==key and not rows(view,33)[1].departing,'A second copy: '..kinds(events));
view,events=frame(snapshot(6,3,{status(33,0,150,9000),status(33,1,200,12000)}),10.4);
assert(#events==0 and #rows(view,33)==2 and rows(view,33)[1].key==key and rows(view,33)[1].source==2001,'Both stay, each as it was.');
