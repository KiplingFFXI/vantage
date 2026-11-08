-- The server lists a removed effect until its next effect tick, so a status update sent between the
-- wear-off message and that tick still shows it. Only a full listing well after the message means the
-- effect is back; its removal was already reported, so it comes back as a gain.
local tracker,alerts,fired;
local rules={
    {id='removed',enabled=true,event='removed',effect=33,scope='self',cooldown=0,visual=true},
    {id='missing',enabled=true,event='missing',effect=33,scope='self',cooldown=0,visual=true},
    {id='gain',enabled=true,event='gain',effect=33,scope='self',cooldown=0,visual=true},
};
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(revision,effects)
    return {valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_revision=revision,
        self_effects=effects,party={},entities={}};
end;
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    local view=tracker:view(now,{},snap);
    local events=tracker:drain_events();
    alerts:update(view,events,rules,now,{});
    for _,notice in ipairs(alerts:drain(now)) do fired[notice.rule_id]=(fired[notice.rule_id] or 0)+1; end;
    return view,events;
end;
local function find(view,effect)
    for _,row in ipairs(view.rows) do if row.effect==effect then return row; end; end;
end;
local function count(events,kind)
    local n=0;
    for _,event in ipairs(events) do if event.kind==kind then n=n+1; end; end;
    return n;
end;
local removal={{kind='remove',entity_id=1001,effect=33,scope='self',reason='Haste wore off.'}};
local haste,signet=status(33,0,200,12000),status(253,1,nil,0x7FFFFFFF);

-- A status update inside the gap still lists the worn effect.
tracker,alerts,fired=require('core.tracker').new(),require('core.alerts').new(),{};
frame(snapshot(1,{haste,signet}),10);
local view=frame(snapshot(1,{haste,signet}),11);
local key=find(view,33).key;
local events;
view,events=frame(snapshot(1,{haste,signet}),21,removal);
assert(count(events,'removed')==1 and find(view,33).departing,'The message reports the removal and marks the row.');
view,events=frame(snapshot(2,{haste,signet}),21.2);
local row=find(view,33);
assert(row and row.departing and row.key==key and #events==0,'A newer listing inside the gap keeps the mark, quietly.');
view,events=frame(snapshot(3,{status(253,0,nil,0x7FFFFFFF)}),21.5);
assert(not find(view,33) and #events==0,'The slot clearing does not report the removal again.');
assert(fired.removed==1 and fired.missing==1 and fired.gain==nil,'One removal and one missing alert.');

-- The same timer is still listed well after the message: the effect is back.
tracker,alerts,fired=require('core.tracker').new(),require('core.alerts').new(),{};
frame(snapshot(1,{haste,signet}),30);
view=frame(snapshot(1,{haste,signet}),31);
key=find(view,33).key;
frame(snapshot(1,{haste,signet}),40,removal);
view,events=frame(snapshot(1,{haste,signet}),46);
assert(find(view,33).departing and #events==0,'With no status update since the message the mark stays.');
view,events=frame(snapshot(2,{haste,signet}),46.2);
row=find(view,33);
assert(row and not row.departing and row.key==key and row.instance==2,'The effect is back under a new instance.');
assert(#events==1 and events[1].kind=='gain' and events[1].instance==2,'Its return is a gain.');
view,events=frame(snapshot(3,{status(253,0,nil,0x7FFFFFFF)}),50);
assert(#events==1 and events[1].kind=='removed' and events[1].instance==2,'A later slot clearing is a new removal.');
assert(fired.removed==2 and fired.gain==1 and fired.missing==2,'Alerts see removed, gain, removed.');
