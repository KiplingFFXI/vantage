-- A busy send can deliver the buff array (0x037) before its status icons and timers (0x063). The client
-- reads no slot timer until the 0x063 comes, so that listing says which IDs are there but not which
-- instance is which. The tracker leaves removals, refreshes and returns to the timers.
local tracker;
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(revision,effects,pending)
    return {valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_revision=revision,
        self_timers_pending=pending,self_effects=effects,party={},entities={}};
end;
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    return tracker:view(now,{},snap),tracker:drain_events();
end;
local function find(view,effect)
    for _,row in ipairs(view.rows) do if row.effect==effect and row.present~=false then return row; end; end;
end;
local function drawn(view,effect)
    local n=0;
    for _,row in ipairs(view.rows) do if row.effect==effect and row.present~=false then n=n+1; end; end;
    return n;
end;
local function count(events,kind)
    local n=0;
    for _,event in ipairs(events) do if event.kind==kind then n=n+1; end; end;
    return n;
end;
local function apply(effect,spell,source)
    return {kind='apply',entity_id=1001,effect=effect,scope='self',source=source,spell=spell};
end;
local function wearoff(effect) return {{kind='remove',entity_id=1001,effect=effect,scope='self'}}; end;

-- Two songs with one ID. One wears off and the message can't say which.
tracker=require('core.tracker').new();
frame(snapshot(1,{}),0);
frame(snapshot(2,{status(198,0,100,6000)}),1,{apply(198,394,2002)});
local both={status(198,0,100,6000),status(198,1,200,12000)};
frame(snapshot(3,both),80,{apply(198,395,2003)});
local view,events=frame(snapshot(3,both),100.1,wearoff(198));
assert(#events==0,'Two candidates leave the removal to the status update.');
view,events=frame(snapshot(4,{status(198,0,nil,nil)},true),100.3);
assert(#events==0 and drawn(view,198)==1,'The 0x037 alone decides nothing; one song is drawn.');
view,events=frame(snapshot(5,{status(198,0,200,12000)}),100.35);
assert(#events==1 and events[1].kind=='removed','The 0x063 decides the removal, with no refresh.');
assert(events[1].spell==394 and events[1].source==2002,'The song that ended is the one reported.');
local row=find(view,198);
assert(drawn(view,198)==1 and row.spell==395 and row.source==2003 and row.raw_timer==12000 and row.instance==1,
    'The other song keeps its row and caster.');

-- Haste wears off and is cast again; the 0x037 lists it before the new timer.
tracker=require('core.tracker').new();
local haste=status(33,0,100,6000);
frame(snapshot(1,{haste}),50);
frame(snapshot(1,{haste}),51);
view,events=frame(snapshot(1,{haste}),100.1,wearoff(33));
assert(count(events,'removed')==1);
view,events=frame(snapshot(2,{status(33,0,nil,nil)},true),100.4,{apply(33,57,1001)});
row=find(view,33);
assert(#events==0 and row and row.departing,'The 0x037 alone keeps the worn row departing.');
view,events=frame(snapshot(3,{status(33,0,280,16800)}),100.45);
assert(#events==1 and events[1].kind=='gain','The new timer makes the recast a gain, not a refresh.');
row=find(view,33);
assert(drawn(view,33)==1 and not row.departing and row.spell==57 and row.mine and row.raw_timer==16800,
    'The recast is attributed and the worn row is gone.');

-- A listing without timers well after the message does not bring a worn effect back; its 0x063 does.
tracker=require('core.tracker').new();
local signet=status(253,1,nil,0x7FFFFFFF);
haste=status(33,0,200,12000);
frame(snapshot(1,{haste,signet}),10);
frame(snapshot(1,{haste,signet}),11);
frame(snapshot(1,{haste,signet}),20,wearoff(33));
view,events=frame(snapshot(2,{status(33,0,nil,nil),status(253,1,nil,nil)},true),26);
row=find(view,33);
assert(row and row.departing and #events==0,'The 0x037 alone keeps the mark.');
view,events=frame(snapshot(3,{haste,signet}),26.05);
row=find(view,33);
assert(row and not row.departing and #events==1 and events[1].kind=='gain','The same timer in the 0x063 brings it back.');
