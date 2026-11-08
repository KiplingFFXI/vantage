-- Phoenix only marks a replaced copy deleted (OverwriteStatusEffect, ApplyBardEffect) and erases it at the
-- target's next CheckEffectsExpiry. What the player does to themselves runs after that in the same tick, so
-- that tick's 0x037 and 0x063 list the old copy, first, beside the new one; the next tick drops the old one
-- with no message. Other casters' copies are erased before the player's status packets. A recast on
-- yourself is one refresh: no gain, no removal, the right caster, and the row keeps its key.
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
local function wearoff(effect,count) return {kind='remove',entity_id=SELF,effect=effect,scope='self',timer_revision=count}; end;

-- Protect: 2001's copy, then the player's own recast lists both for one tick.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
local view=frame(snapshot(2,1,{status(40,0,1800,108000)}),0.5,{cast(40,43,2001,0)});
local key,first=rows(view,40)[1].key,rows(view,40)[1].first_seen;
local events;
view,events=frame(snapshot(4,2,{status(40,0,1800,108000),status(40,1,1900,114000)}),100,{cast(40,43,SELF,1)});
local both=rows(view,40);
assert(#both==2 and #events==1 and events[1].kind=='refresh' and events[1].source==SELF and events[1].key==key,
    'The two-copy listing is one refresh of the row: '..kinds(events));
assert(both[2].key==key and both[2].instance==2 and both[2].source==SELF and both[2].mine and both[2].start==100
    and both[2].raw_timer==114000 and both[2].first_seen==first,'The row moves to the new copy with the player\'s cast.');
assert(both[1].departing and both[1].source==2001 and both[1].raw_timer==108000 and both[1].first_seen==first,
    'The old copy shows as leaving, with its own caster.');
view,events=frame(snapshot(6,3,{status(40,0,1900,114000)}),100.4);
assert(#events==0 and #rows(view,40)==1 and rows(view,40)[1].key==key,'The old copy leaves with no removal.');

-- A song of the same tier replaces its copy in place, whoever sang it; the old copy is 2002's.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
view=frame(snapshot(2,1,{status(198,0,120,7200)}),10,{cast(198,394,2002,0)});
key=rows(view,198)[1].key;
view,events=frame(snapshot(4,2,{status(198,0,120,7200),status(198,1,170,10200),status(214,2,150,9000)}),50,
    {cast(198,394,SELF,1),cast(214,419,SELF,1)});
both=rows(view,198);
assert(#events==2 and kinds(events)=='refresh:198:1001,gain:214:1001','The song reads as a refresh, the new one a gain: '..kinds(events));
assert(both[2].key==key and both[2].spell==394 and both[2].mine and both[1].departing and both[1].source==2002,
    'The row is the player\'s new copy; the old one leaves.');
view,events=frame(snapshot(6,3,{status(198,0,170,10200),status(214,1,150,9000)}),50.4);
assert(#events==0 and rows(view,198)[1].key==key and rows(view,198)[1].source==SELF,'Nothing wore off.');

-- The 0x037 can come before its 0x063: the new copy waits for its timer to be gained, and its 0x063 then
-- shows the two copies.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
view=frame(snapshot(2,1,{status(40,0,1800,108000)}),0.5,{cast(40,43,2001,0)});
key=rows(view,40)[1].key;
view,events=frame(snapshot(3,1,{status(40,0,nil,nil),status(40,1,nil,nil)},true),100,{cast(40,43,SELF,1)});
assert(#events==0 and #rows(view,40)==2,'The 0x037 alone gains nothing: '..kinds(events));
view,events=frame(snapshot(4,2,{status(40,0,1800,108000),status(40,1,1900,114000)}),100.05);
assert(#events==1 and events[1].kind=='refresh' and rows(view,40)[2].key==key and rows(view,40)[2].source==SELF,
    'The 0x063 shows the refresh: '..kinds(events));
view,events=frame(snapshot(6,3,{status(40,0,1900,114000)}),100.4);
assert(#events==0 and rows(view,40)[1].key==key,'And no removal.');

-- If a later 0x063 still lists both, the old one was no replaced copy: it stays, with no gain.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(40,0,1800,108000)}),0.5,{cast(40,43,2001,0)});
frame(snapshot(4,2,{status(40,0,1800,108000),status(40,1,1900,114000)}),100,{cast(40,43,SELF,1)});
view,events=frame(snapshot(5,2,{status(40,0,1800,108000),status(40,1,1900,114000)}),100.1);
assert(rows(view,40)[1].departing,'The trailing 0x037 of that tick changes nothing.');
view,events=frame(snapshot(7,3,{status(40,0,1800,108000),status(40,1,1900,114000)}),100.5);
both=rows(view,40);
assert(#events==0 and not both[1].departing and both[1].source==2001 and both[1].instance==1,'It is back quietly.');

-- Over the player's cap the resung song takes the slot of the player's song that ends first and is listed
-- there by status ID; the old copy of its tier is listed in its own slot until the next tick. Ballad (196)
-- sorts before Minuet in that slot, so the new copy is after it, apart from the old one. Ballad is lost;
-- Minuet is refreshed.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
view=frame(snapshot(2,1,{status(198,0,150,9000)}),30,{cast(198,394,SELF,0)});
key=rows(view,198)[1].key;
frame(snapshot(3,2,{status(198,0,150,9000),status(196,1,140,8400)}),30.4,{cast(196,386,SELF,1)});
view,events=frame(snapshot(5,3,{status(198,0,150,9000),status(196,1,140,8400),status(198,2,200,12000)}),80,{cast(198,394,SELF,2)});
local minuet=rows(view,198);
assert(#events==1 and events[1].kind=='refresh' and events[1].effect==198,'The resung song is a refresh: '..kinds(events));
assert(minuet[2].key==key and minuet[2].raw_timer==12000 and minuet[1].departing,'The row moves to the new copy.');
view,events=frame(snapshot(7,4,{status(198,0,200,12000)}),80.4);
assert(kinds(events)=='removed:196:1001' and rows(view,198)[1].key==key,'Ballad was lost: '..kinds(events));
-- March (214) sorts after Minuet in its slot, so there the new copy is right after the old one.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
view=frame(snapshot(2,1,{status(198,0,150,9000)}),30,{cast(198,394,SELF,0)});
key=rows(view,198)[1].key;
frame(snapshot(3,2,{status(198,0,150,9000),status(214,1,140,8400)}),30.4,{cast(214,420,SELF,1)});
view,events=frame(snapshot(5,3,{status(198,0,150,9000),status(198,1,200,12000),status(214,2,140,8400)}),80,{cast(198,394,SELF,2)});
minuet=rows(view,198);
assert(kinds(events)=='refresh:198:1001' and minuet[2].key==key and minuet[1].departing,'The resung song is a refresh: '..kinds(events));
view,events=frame(snapshot(7,4,{status(198,0,200,12000)}),80.4);
assert(kinds(events)=='removed:214:1001' and rows(view,198)[1].key==key,'March was lost: '..kinds(events));

-- The player's own Double-Up: Phoenix deletes the roll silently and adds it again in its slot at its full time
-- (corsair.lua :544-551), in the player's tick, so both are listed. The row moves to the new copy: one refresh, and
-- the old copy leaves with no removal.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
view=frame(snapshot(2,1,{status(310,0,310,18600)}),10,{cast(310,98,SELF,0)});
key=rows(view,310)[1].key;
view,events=frame(snapshot(4,2,{status(310,0,310,18600),status(310,1,400,24000)}),100,{cast(310,98,SELF,1)});
local roll=rows(view,310);
assert(#events==1 and events[1].kind=='refresh' and roll[2].key==key and roll[2].instance==2 and roll[2].raw_timer==24000
    and roll[1].departing,'The roll is renewed: '..kinds(events));
view,events=frame(snapshot(6,3,{status(310,0,399.6,23976)}),100.4);
assert(#events==0 and rows(view,310)[1].key==key,'And the old copy leaves with no removal.');

-- A wear-off sent just before an always-overwrite recast (Refresh), with no 0x063 between: the player's
-- own lists both copies, so it is one refresh.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
view=frame(snapshot(2,1,{status(43,0,150,9000)}),0.5,{cast(43,109,SELF,0)});
key=rows(view,43)[1].key;
view,events=frame(snapshot(4,2,{status(43,0,150,9000),status(43,1,250,15000)}),100,{wearoff(43,1),cast(43,109,SELF,1)});
assert(#events==1 and events[1].kind=='refresh' and rows(view,43)[2].key==key,'One refresh: '..kinds(events));
view,events=frame(snapshot(6,3,{status(43,0,250,15000)}),100.4);
assert(#events==0,'No removal.');
-- Refresh ran out and the player cast it in the same tick: one copy listed, so it went, and came again.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(43,0,150,9000)}),0.5,{cast(43,109,SELF,0)});
view,events=frame(snapshot(4,2,{status(43,0,250,15000)}),150.2,{wearoff(43,1),cast(43,109,SELF,1)});
assert(kinds(events)=='removed:43:1001,gain:43:1001','It wore off and was gained again: '..kinds(events));
-- Another caster's recast lists the new copy alone; the 0x063 may come in a later batch.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
view=frame(snapshot(2,1,{status(43,0,150,9000)}),0.5,{cast(43,109,SELF,0)});
key=rows(view,43)[1].key;
view,events=frame(snapshot(2,1,{status(43,0,150,9000)}),100,{wearoff(43,1),cast(43,109,2001,1)});
assert(#events==0 and rows(view,43)[1].departing,'The removal waits for the listing.');
view,events=frame(snapshot(4,2,{status(43,0,250,15000)}),100.4);
assert(#events==1 and events[1].kind=='refresh' and events[1].source==2001 and rows(view,43)[1].key==key
    and not rows(view,43)[1].departing,'It is one refresh by 2001: '..kinds(events));
-- With a timer that moved too little to see, the 0x063 after it still lists the copy.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(43,0,150,9000)}),0.5,{cast(43,109,SELF,0)});
frame(snapshot(2,1,{status(43,0,150,9000)}),1.1,{wearoff(43,1),cast(43,109,2001,1)});
view,events=frame(snapshot(4,2,{status(43,0,150,9060)}),1.4);
assert(#events==1 and events[1].kind=='refresh' and events[1].source==2001 and not rows(view,43)[1].departing,
    'Still one refresh: '..kinds(events));
-- A wear-off on an earlier 0x063 count than the cast is an expiry with another cast after it.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(43,0,150,9000)}),0.5,{cast(43,109,SELF,0)});
view,events=frame(snapshot(4,3,{status(43,0,300,18000)}),150.4,{wearoff(43,1),cast(43,109,2001,2)});
assert(kinds(events)=='removed:43:1001,gain:43:2001','It wore off: '..kinds(events));

-- Another caster's replacement shown by a stray 0x037 (with no 0x063) lists both copies; the next 0x063
-- has the new one alone. That is one refresh too.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
view=frame(snapshot(2,1,{status(40,0,1800,108000)}),0.5,{cast(40,43,SELF,0)});
key=rows(view,40)[1].key;
view,events=frame(snapshot(3,1,{status(40,0,nil,nil),status(40,1,nil,nil)},true),100,{cast(40,43,2001,1)});
assert(#events==0,'The stray listing gains nothing.');
view,events=frame(snapshot(5,2,{status(40,0,1900,114000)}),100.4);
assert(#events==1 and events[1].kind=='refresh' and events[1].source==2001 and rows(view,40)[1].key==key
    and rows(view,40)[1].source==2001,'The row is renewed by 2001: '..kinds(events));

-- The player's song lands on its tier's copy and, over their cap, the row right after it in the listing
-- reads like the new copy by chance: that row goes back to its own copy, further on.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
view=frame(snapshot(2,1,{status(214,0,131.5,7860)}),11.5,{cast(214,420,SELF,0)});
key=rows(view,214)[1].key;
frame(snapshot(3,2,{status(214,0,131.5,7860),status(214,1,160,9600)}),40,{cast(214,419,2004,1)});
view,events=frame(snapshot(5,3,{status(214,0,131.5,7860),status(214,1,160,9600),status(198,2,150,9000),status(214,3,161,9660)}),
    40.5,{cast(214,420,SELF,2),cast(198,394,2002,2)});
local march=rows(view,214);
assert(march[3].spell==419 and march[3].source==2004 and march[3].instance==1,'2004\'s 419 keeps its copy.');
assert(march[2].key==key and march[2].source==SELF and march[2].instance==2 and march[1].departing,
    'The player\'s 420 moved to the copy after its old one.');
assert(kinds(events)=='refresh:214:1001,gain:198:2002','One refresh for March: '..kinds(events));
