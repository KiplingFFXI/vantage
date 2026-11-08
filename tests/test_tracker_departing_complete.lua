-- A departing mark clears only on a listing that can report the effect's return: complete, and not during a
-- KO or the quiet listing after a KO or an incomplete one. Clearing it anywhere else loses the gain, so a
-- later removal reports the effect gone twice with no gain between.
local tracker,alerts,fired;
local rules={
    {id='removed',enabled=true,event='removed',effect=33,scope='self',cooldown=0,visual=true},
    {id='gain',enabled=true,event='gain',effect=33,scope='self',cooldown=0,visual=true},
};
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(revision,effects,extra)
    local snap={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_revision=revision,
        self_effects=effects,party={},entities={}};
    for k,v in pairs(extra or {}) do snap[k]=v; end;
    return snap;
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
local removal={{kind='remove',entity_id=1001,effect=33,scope='self',reason='Haste wore off.'}};
local haste,signet=status(33,0,200,12000),status(253,1,nil,0x7FFFFFFF);
local view,events,row;

-- An incomplete listing well after the message still shows Haste.
tracker,alerts,fired=require('core.tracker').new(),require('core.alerts').new(),{};
frame(snapshot(1,{haste,signet}),10);
frame(snapshot(1,{haste,signet}),11);
frame(snapshot(1,{haste,signet}),20,removal);
view,events=frame(snapshot(2,{haste,signet},{self_known=false}),26);
row=find(view,33);
assert(row and row.departing and row.instance==1 and #events==0,'An incomplete listing keeps the mark, quietly.');
view,events=frame(snapshot(3,{haste,signet}),27);
row=find(view,33);
assert(row and row.departing and #events==0,'So does the quiet complete listing after it.');
view,events=frame(snapshot(3,{haste,signet}),28);
row=find(view,33);
assert(row and not row.departing and row.instance==2,'The next listing clears it.');
assert(#events==1 and events[1].kind=='gain' and events[1].instance==2,'Its return is a gain.');
view,events=frame(snapshot(4,{status(253,0,nil,0x7FFFFFFF)}),30);
assert(#events==1 and events[1].kind=='removed' and events[1].instance==2,'A later slot clearing is a new removal.');
assert(fired.removed==2 and fired.gain==1,'Alerts see removed, gain, removed.');

-- Haste outlasts a KO in the listing well after the message.
tracker,alerts,fired=require('core.tracker').new(),require('core.alerts').new(),{};
frame(snapshot(1,{haste,signet}),10);
frame(snapshot(1,{haste,signet}),11);
frame(snapshot(1,{haste,signet}),20,removal);
frame(snapshot(2,{haste,signet},{dead=true}),21);
view,events=frame(snapshot(3,{haste,signet},{dead=true}),27);
row=find(view,33);
assert(row and row.departing and row.instance==1 and #events==0,'A KO listing keeps the mark, quietly.');
view,events=frame(snapshot(4,{haste,signet}),30);
row=find(view,33);
assert(row and row.departing and #events==0,'So does the quiet listing after the raise.');
view,events=frame(snapshot(4,{haste,signet}),31);
row=find(view,33);
assert(row and not row.departing and row.instance==2,'The next listing clears it.');
assert(#events==1 and events[1].kind=='gain' and events[1].instance==2,'Its return is a gain.');
view,events=frame(snapshot(5,{status(253,0,nil,0x7FFFFFFF)}),35);
assert(#events==1 and events[1].kind=='removed' and events[1].instance==2,'A later slot clearing is a new removal.');
assert(fired.removed==2 and fired.gain==1,'Alerts see removed, gain, removed.');
