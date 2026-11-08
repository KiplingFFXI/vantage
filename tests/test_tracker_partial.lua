local Tracker = require('core.tracker');
local Alerts = require('core.alerts');
local function status(effect,slot,deadline,raw)
    return {effect=effect,slot=slot,deadline=deadline,raw_timer=raw};
end
local function snapshot(effects,known)
    return {valid=true,id=10,name='Tester',zone=1,job=1,self_known=known,self_effects=effects or {},
        party={},entities={},self_revision=1};
end
local function by_effect(view,effect)
    for _,row in ipairs(view.rows) do if row.effect==effect then return row; end end
end
local function quiet(tracker)
    assert(#tracker:drain_events()==0,'A partial list or recovered baseline cannot manufacture lifecycle events.');
end
local tracker=Tracker.new();
local s=snapshot({status(33,0,100,6000),status(41,1,nil,0)},false);
tracker:reconcile(s,10);
local v=tracker:view(10,{},s);
assert(#v.rows==2 and not v.self_known,'The two valid observations in an incomplete list must reach the row model.');
assert(by_effect(v,33).present==true and by_effect(v,33).status=='server' and by_effect(v,33).remaining==90);
assert(by_effect(v,41).present==true and by_effect(v,41).status=='unknown' and by_effect(v,41).remaining==nil);
assert(not v.subjects[1].known,'List completeness remains unknown even when individual statuses are readable.');
quiet(tracker);
local alerts=Alerts.new();
local rules={
    {id='missing',enabled=true,event='missing',effect=13,scope='self',cooldown=0,visual=true},
    {id='gain',enabled=true,event='gain',effect=0,scope='self',cooldown=0,visual=true},
    {id='removed',enabled=true,event='removed',effect=0,scope='self',cooldown=0,visual=true},
};
alerts:update(v,{},rules,10,{});
tracker:reconcile(s,30);v=tracker:view(30,{},s);
alerts:update(v,tracker:drain_events(),rules,30,{});
assert(#alerts:drain(30)==0,'Incomplete status lists cannot establish that an effect is missing.');
s.self_known=true;s.self_effects={status(33,0,100,6000),status(40,1,300,18000)};
tracker:reconcile(s,31);v=tracker:view(31,{},s);
assert(v.self_known and #v.rows==2 and not by_effect(v,41) and by_effect(v,40));
local events=tracker:drain_events();assert(#events==0);
alerts:update(v,events,rules,31,{});
assert(#alerts:drain(31)==0,'Returning to a complete list does not burst gain, wearoff, or missing alerts.');
s.self_effects={status(33,0,100,6000)};
tracker:reconcile(s,32);events=tracker:drain_events();
assert(#events==1 and events[1].kind=='removed' and events[1].effect==40,'A later complete transition can confirm a genuine removal.');

tracker=Tracker.new();
s=snapshot({status(33,0,200,12000),status(33,1,250,15000),status(41,2,300,18000)},true);
tracker:reconcile(s,0);v=tracker:view(0,{},s);
local duplicate_key;
for _,row in ipairs(v.rows) do if row.deadline==250 then duplicate_key=row.key; end end
quiet(tracker);
s.self_known=false;s.self_effects={status(33,1,250,15000)};
tracker:reconcile(s,120);v=tracker:view(120,{tracking={stale_seconds=10}},s);
assert(#v.rows==3,'Older omitted statuses remain visible briefly as unknown instead of disappearing immediately.');
for _,row in ipairs(v.rows) do
    if row.key==duplicate_key then
        assert(row.present==true and row.status=='server' and row.remaining==130,'Matching keeps the correct duplicate icon timer.');
    else
        assert(row.present==nil and row.status=='unknown' and row.remaining==nil,'Unreadable old rows lose authoritative presence and countdown.');
    end
end
quiet(tracker);
v=tracker:view(129,{tracking={stale_seconds=10}},s);assert(#v.rows==3);
s.self_known=true;s.self_effects={status(33,0,200,12000),status(33,1,250,15000),status(41,2,300,18000)};
tracker:reconcile(s,130);v=tracker:view(130,{},s);assert(#v.rows==3 and v.self_known);
for _,row in ipairs(v.rows) do assert(row.present and row.status=='server'); end
quiet(tracker);
s.self_known=false;s.self_effects={};
tracker:reconcile(s,140);tracker:reconcile(s,145);
v=tracker:view(151,{tracking={stale_seconds=10}},s);
assert(#v.rows==0,'Repeated incomplete reads cannot keep unobserved statuses forever.');
quiet(tracker);
s.self_effects={status(41,2,300,18000),status(-1,3),status(255,4),status(65535,5),'bad'};
tracker:reconcile(s,152);v=tracker:view(152,{},s);
assert(#v.rows==1 and v.rows[1].effect==41 and v.rows[1].present and not v.self_known,'Only validated positive observations are restored.');
quiet(tracker);

tracker=Tracker.new();s=snapshot({status(33,0,200,12000)},true);
tracker:reconcile(s,0);tracker:observe({{kind='remove',entity_id=10,effect=33}},1,s);
assert(#tracker:drain_events()==1);
s.self_known=false;s.self_effects={};tracker:reconcile(s,1.1);quiet(tracker);
s.self_effects={status(33,0,200,12000)};tracker:reconcile(s,1.2);
v=tracker:view(1.2,{},s);
assert(#v.rows==1 and v.rows[1].departing,'A partial omission cannot discard explicit-removal protection and resurrect a stale icon.');
quiet(tracker);
s.self_revision=2;tracker:reconcile(s,2);
assert(#tracker:view(2,{},s).rows==1,'A newer status revision can establish positive presence again.');
quiet(tracker);
