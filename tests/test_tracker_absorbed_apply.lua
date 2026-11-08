-- Phoenix sends an application's 0x028 at once and its 0x063 on the next effect tick. Each self application
-- carries the 0x063 count at its packet's arrival. A complete listing whose timers agree, read after a later
-- 0x063, already shows what the application did; a recast that moved the timer too little to see is done
-- then, and must not wait to credit a later renewal of that row.
local tracker;
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(revision,timers,effects,extra)
    local snap={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_revision=revision,
        self_timer_revision=timers,self_effects=effects,party={},entities={}};
    for key,value in pairs(extra or {}) do snap[key]=value; end;
    return snap;
end;
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    return tracker:view(now,{},snap),tracker:drain_events();
end;
local function find(view,effect)
    for _,row in ipairs(view.rows) do if row.effect==effect and row.present then return row; end; end;
end;
local function song(spell,source,count)
    return {kind='apply',entity_id=1001,effect=198,scope='self',source=source,spell=spell,
        timer_revision=count};
end;

-- 2002 recasts 394 0.6 s on (one restamp step). 2 s later 2003 sings 394 over it and the timer moves.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(198,0,121,7260)}),1,{song(394,2002,0)});
local view,events=frame(snapshot(3,2,{status(198,0,122,7320)}),1.6,{song(394,2002,1)});
assert(#events==0 and find(view,198).instance==1,'The recast shows no refresh.');
view,events=frame(snapshot(4,3,{status(198,0,124,7440)}),3.6,{song(394,2003,2)});
local row=find(view,198);
assert(#events==1 and events[1].kind=='refresh' and events[1].source==2003,'The renewal is the other bard\'s.');
assert(row.spell==394 and row.source==2003 and row.instance==2 and row.start==3.6,'The row is credited to 2003, not the recast before it.');

-- Phoenix's extra 0x037 after an HP change brings no 0x063: the listing it gives doesn't show the
-- application yet, so the application waits for the 0x063 that shows its renewal.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(198,0,121,7260)}),1,{song(394,2002,0)});
view,events=frame(snapshot(3,1,{status(198,0,121,7260)}),50,{song(394,2002,1)});
assert(#events==0,'Nothing shows before the 0x063.');
view,events=frame(snapshot(5,2,{status(198,0,170,10200)}),50.3);
row=find(view,198);
assert(#events==1 and events[1].kind=='refresh' and row.spell==394 and row.source==2002 and row.start==50 and row.instance==2,
    'The renewal takes the application that waited.');

-- A 0x063 after the application, then a 0x037 without its 0x063: the listing has no timers to show the
-- renewal, so the application waits for the next 0x063.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(198,0,121,7260)}),1,{song(394,2002,0)});
view,events=frame(snapshot(5,2,{status(198,0,nil,nil),status(33,1,nil,nil)},{self_timers_pending=true}),50,{song(394,2002,1)});
assert(find(view,198).instance==1,'The split listing renews nothing.');
view,events=frame(snapshot(6,3,{status(198,0,170,10200),status(33,1,230,13800)}),50.05);
row=find(view,198);
assert(row.spell==394 and row.source==2002 and row.start==50 and row.instance==2,'The 0x063 renewal takes the application.');

-- A listing with an unreadable slot is not complete; what it leaves out may be the application's new copy.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(198,0,121,7260)}),1,{song(395,2003,0)});
view,events=frame(snapshot(3,2,{status(198,0,121,7260)},{self_known=false}),50,{song(394,2002,1)});
row=find(view,198);
assert(row.spell==395 and row.source==2003 and row.instance==1,'The copy listed is not credited to the application.');
view,events=frame(snapshot(4,2,{status(198,0,121,7260),status(198,1,170,10200)}),50.1);
local new;
for _,held in ipairs(view.rows) do if held.slot==1 then new=held; end; end;
assert(new and new.spell==394 and new.source==2002 and new.start==50,'The new copy takes it once a complete listing shows it.');
