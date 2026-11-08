-- A split send holds back the same-ID row it can't place (present false) until the 0x063 says which copy
-- left. Alerts don't treat that row as present: its countdown doesn't fire on it. They don't treat it as
-- gone either: its countdown state and shown notices wait, so a threshold crossed meanwhile fires once
-- the 0x063 shows the row is still there.
local tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
local rules={
    {id='count',enabled=true,event='remaining',effect=198,scope='self',thresholds={30},cooldown=0,duration=30,visual=true},
    {id='repeat',enabled=true,event='remaining',effect=198,scope='self',thresholds={40},repeat_seconds=5,cooldown=0,
        duration=10,visual=true},
    {id='gain',enabled=true,event='gain',effect=198,scope='self',cooldown=0,duration=30,visual=true},
};
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(revision,effects,pending)
    return {valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_revision=revision,
        self_timers_pending=pending,self_effects=effects,party={},entities={}};
end;
local key;
-- One refresh; returns the view and how many notices each rule drained for the 395 song.
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    local view=tracker:view(now,{},snap);
    alerts:update(view,tracker:drain_events(),rules,now,{});
    local fired={};
    for _,notice in ipairs(alerts:drain(now)) do
        if notice.key==key then fired[notice.rule_id]=(fired[notice.rule_id] or 0)+1; end;
    end;
    return view,fired;
end;
local function shown(now,rule)
    for _,notice in ipairs(alerts:view(now)) do if notice.key==key and notice.rule_id==rule then return true; end; end;
    return false;
end;
local function song(spell,source)
    return {kind='apply',entity_id=1001,effect=198,scope='self',source=source,spell=spell};
end;

-- 394 is first seen inside both thresholds, so only 395 counts down here.
local a,b=status(198,0,100,6000),status(198,1,130.2,7812);
for t=0,70,5 do frame(snapshot(1,{}),t); end;
local view=frame(snapshot(3,{a,b}),75,{song(394,2002),song(395,2003)});
for _,row in ipairs(view.rows) do if row.spell==395 then key=row.key; end; end;
local totals={};
for t=75.5,100,0.5 do
    local _,fired=frame(snapshot(3,{a,b}),t);
    for rule,n in pairs(fired) do totals[rule]=(totals[rule] or 0)+n; end;
end;
assert(totals['repeat']==2 and not totals.count,'Before the split 395 crosses 40 s and repeats once.');
local fired;
_,fired=frame(snapshot(3,{a,b}),100.1,{{kind='remove',entity_id=1001,effect=198,scope='self'}});
assert(not fired.count,'At 30.1 s left nothing fires yet.');

-- The split lists one copy without timers; 395 is held back while it crosses 30 s.
view,fired=frame(snapshot(4,{status(198,0,nil,nil)},true),100.3);
local held;
for _,row in ipairs(view.rows) do if row.key==key then held=row; end; end;
assert(held and held.present==false and held.remaining<30,'395 is held back past its threshold.');
assert(not fired.count,'A held-back row fires no countdown.');
assert(shown(100.3,'repeat') and shown(100.3,'gain'),'Its notices stay shown while it is held.');

-- The 0x063 shows 395 is the copy still on.
_,fired=frame(snapshot(5,{status(198,0,130.2,7812)}),100.35);
assert(fired.count==1,'The crossing made during the split fires once the row is present again.');
local late={};
for t=100.5,106,0.5 do
    local _,step=frame(snapshot(5,{status(198,0,130.2,7812)}),t);
    for rule,n in pairs(step) do late[rule]=(late[rule] or 0)+n; end;
    if t==100.5 then assert(step['repeat']==1,'Its repeat keeps its schedule through the split.'); end;
end;
assert(late['repeat']==2 and not late.count,'One repeat every 5 s and no second countdown.');
