-- Two songs with one ID keep their order in the server's list. Each 0x063 rebuilds the timers from
-- truncated clocks, so songs that end a second apart have timers 60 apart and a restamp can give one
-- song the other's old timer. The slot order decides which row is which; a timer only tells a recast.
local tracker=require('core.tracker').new();
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(revision,effects)
    return {valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_revision=revision,
        self_effects=effects,party={},entities={}};
end;
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    return tracker:view(now,{},snap),tracker:drain_events();
end;
local function songs(view)
    local out={};
    for _,row in ipairs(view.rows) do if row.effect==198 then out[row.spell or 0]=row; end; end;
    return out;
end;
local function song(spell,source)
    return {kind='apply',entity_id=1001,effect=198,scope='self',source=source,spell=spell};
end;

-- Both songs are restamped 60 lower: the later song gets the earlier song's old timer.
frame(snapshot(1,{}),0);
frame(snapshot(2,{status(198,0,130,7800)}),10,{song(394,2002)});
local both={status(198,0,130,7800),status(198,1,131,7860)};
frame(snapshot(3,both),11,{song(395,2003)});
frame(snapshot(3,both),12);
local view,events=frame(snapshot(5,{status(198,0,129,7740),status(198,1,130,7800)}),20);
local by=songs(view);
assert(#events==0,'A restamp of both songs is quiet.');
assert(by[394] and by[394].slot==0 and by[394].raw_timer==7740 and by[394].instance==1,'The first song keeps its slot.');
assert(by[395] and by[395].slot==1 and by[395].raw_timer==7800 and by[395].source==2003 and by[395].instance==1,
    'The second song keeps its row and caster.');
-- 394 ends. The message can't say which song; the update lists 395, restamped back.
view,events=frame(snapshot(7,{status(198,0,130,7800)}),129.5,{{kind='remove',entity_id=1001,effect=198,scope='self'}});
assert(#events==1 and events[1].kind=='removed' and events[1].spell==394,'The song that ended is reported.');
by=songs(view);
assert(by[395] and by[395].source==2003 and not by[394],'The song still on is 395.');

-- 394 is recast and the same 0x063 restamps 395 onto the timer 394 just got.
tracker=require('core.tracker').new();
frame(snapshot(1,{}),1500);
frame(snapshot(2,{status(198,0,1627,97620)}),1507,{song(394,2002)});
both={status(198,0,1627,97620),status(198,1,1666,99960)};
frame(snapshot(3,both),1546,{song(395,2003)});
frame(snapshot(3,both),1547);
view,events=frame(snapshot(5,{status(198,0,1666,99960),status(198,1,1665,99900)}),1550,{song(394,2002)});
assert(#events==1 and events[1].kind=='refresh' and events[1].spell==394 and events[1].slot==0,'Only the recast song is refreshed.');
by=songs(view);
assert(by[394] and by[394].slot==0 and by[394].raw_timer==99960 and by[394].instance==2,'The recast song gets its new timer.');
assert(by[395] and by[395].slot==1 and by[395].raw_timer==99900 and by[395].instance==1 and by[395].source==2003,
    'The other song keeps its row.');
