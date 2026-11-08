package.loaded['core.catalog']={get=function(id) return {id=id,name='Effect '..id,kind=id<32 and 'debuff' or 'buff',group='Test'}; end};
local tracker=require('core.tracker').new();
local function snapshot(effects)
    return {valid=true,id=10,name='Tester',zone=1,job=1,self_known=true,self_effects=effects or {},party={},entities={},target={id=100,name='Crab',kind='monster'}};
end
local function status(id,slot,deadline,raw)
    return {effect=id,slot=slot,deadline=deadline,raw_timer=raw};
end
local s=snapshot({status(33,0,100,6000),status(33,1,150,9000),status(251,2,nil,0x7fffffff)});
tracker:reconcile(s,0);
local v=tracker:view(0,{},s);
assert(#v.rows==3,'Duplicate icons must remain separate.');
assert(#tracker:drain_events()==0,'Reload baseline must be quiet.');
local first,second=v.rows[1].key,v.rows[2].key;
assert(v.rows[1].total==nil and v.rows[1].elapsed==nil,'Initial snapshot must not invent original duration.');
assert(v.rows[3].status=='unknown' and v.rows[3].present==true);
s.self_effects={status(33,1,150,9000),status(33,0,100,6000),status(251,2,nil,0x7fffffff)};
tracker:reconcile(s,1);
v=tracker:view(1,{},s);
assert(v.rows[1].key==first and v.rows[2].key==second);
assert(#tracker:drain_events()==0,'Slot movement is not an application.');
tracker:observe({{kind='apply',entity_id=10,effect=33,source=10,spell=57}},2,s);
s.self_effects={status(33,1,150,9000),status(33,0,182,10920),status(251,2,nil,0x7fffffff)};
tracker:reconcile(s,2);
v=tracker:view(2,{},s);
local refreshed;
for _,row in ipairs(v.rows) do if row.deadline==182 then refreshed=row; end end
assert(refreshed.key==first and refreshed.instance==2);
assert(refreshed.start==2 and refreshed.total==180 and refreshed.source==10);
local events=tracker:drain_events();
assert(#events==1 and events[1].kind=='refresh');
s.self_effects={status(33,0,182,10920)};
tracker:reconcile(s,3);
events=tracker:drain_events();
assert(#events==2 and events[1].kind=='removed');
tracker:observe({{kind='remove',entity_id=10,effect=33}},4,s);
assert(#tracker:drain_events()==1);
tracker:reconcile(s,4.1);v=tracker:view(4.1,{},s);
assert(#v.rows==1 and v.rows[1].departing and v.rows[1].present,'A removal message before the icon update keeps the row drawn until its slot clears.');
s.self_effects={}; tracker:reconcile(s,5);
assert(#tracker:drain_events()==0,'A stale icon after removal must not rearm gain alerts or repeat the removal.');
s.self_effects={status(37,0,6,500)};
tracker:reconcile(s,5.1); tracker:drain_events();
v=tracker:view(7,{},s);
assert(v.rows[1].present and v.rows[1].status=='server' and v.rows[1].remaining==0,'A server timer at zero stays until its slot clears.');
assert(#tracker:drain_events()==0,'A deadline is not proof of removal.');
tracker:observe({{kind='apply',entity_id=100,effect=2,source=10,duration=60,duration_min=30}},8,s);
v=tracker:view(8,{},s);
local enemy;
for _,row in ipairs(v.rows) do if row.entity_id==100 then enemy=row; end end
assert(enemy.status=='estimated' and enemy.total==60 and enemy.duration_min==30);
assert(enemy.present==nil and enemy.mine);
tracker:drain_events();
v=tracker:view(69,{},s);
for _,row in ipairs(v.rows) do if row.entity_id==100 then enemy=row; end end
assert(enemy.status=='unknown' and enemy.present==nil and enemy.deadline==nil);
assert(#tracker:drain_events()==0,'Estimated expiry must not emit a removal.');
v=tracker:view(200,{tracking={stale_seconds=60}},s);
for _,row in ipairs(v.rows) do assert(row.entity_id~=100,'Old observations must be retired.'); end
assert(#tracker:drain_events()==0);
s.party={{id=20,name='Friend',zone=1,valid=false,effects={}}};
tracker:reconcile(s,201); v=tracker:view(201,{},s);
for _,subject in ipairs(v.subjects) do if subject.id==20 then assert(not subject.known); end end
s.party[1].valid=true;s.party[1].effects={{effect=40,slot=0}};
tracker:reconcile(s,202); v=tracker:view(202,{},s);
for _,row in ipairs(v.rows) do if row.entity_id==20 then assert(row.present and row.status=='unknown'); end end
tracker:observe({{kind='apply',entity_id=20,effect=40,source=10,duration=1800}},203,s);
tracker:reconcile(s,203); v=tracker:view(203,{},s);
for _,row in ipairs(v.rows) do if row.entity_id==20 then assert(row.present and row.status=='estimated'); end end
tracker:drain_events();s.party[1].effects={}; tracker:reconcile(s,204);
assert(#tracker:drain_events()==1);
s.zone=2;tracker:reconcile(s,205);v=tracker:view(205,{},s);
for _,row in ipairs(v.rows) do assert(row.scope=='self'); end
events=tracker:drain_events();assert(events[1].kind=='reset' and events[1].quiet);
s.dead=true;tracker:reconcile(s,206);v=tracker:view(206,{},s);
assert(#v.rows==1 and v.rows[1].effect==37 and v.rows[1].present,'A KO keeps following the self slots.');
assert(#tracker:drain_events()==0,'A KO is quiet and resets nothing.');

local t=require('core.tracker').new();s=snapshot();t:reconcile(s,0);
for id=100,200 do t:observe({{kind='apply',entity_id=id,effect=5}},1,s); end
v=t:view(1,{tracking={max_entities=8}},s);
assert(#v.subjects<=8,'Entity retention must be bounded.');
for effect=1,100 do t:observe({{kind='apply',entity_id=200,effect=effect}},2,s); end
v=t:view(2,{},s);local count=0;
for _,row in ipairs(v.rows) do if row.entity_id==200 then count=count+1; end end
assert(count<=64,'Effect retention must be bounded.');

t=require('core.tracker').new();s=snapshot({status(33,0,300,18000)});t:reconcile(s,0);
s.self_known=false;s.self_effects={};t:reconcile(s,1);v=t:view(1,{},s);
assert(v.rows[1].status=='unknown' and v.rows[1].remaining==nil and not v.self_known,'Unavailable self data must not retain an authoritative countdown.');
s.self_known=true;s.self_effects={status(33,0,300,18000)};t:reconcile(s,2);v=t:view(2,{},s);
assert(v.rows[1].status=='server' and v.rows[1].remaining==298);
s.party={{id=20,name='Friend',zone=1,valid=true,effects={},revision=1}};
t:reconcile(s,3);t:drain_events();
t:observe({{kind='apply',entity_id=20,effect=40,source=10,duration=1800}},4,s);
t:drain_events();t:reconcile(s,4.1);v=t:view(4.1,{},s);
local held;
for _,r in ipairs(v.rows) do if r.entity_id==20 then held=r; end end
assert(held and held.status=='estimated','An older party snapshot must not erase an application before its icon update.');
assert(#t:drain_events()==0,'A stale party snapshot must not manufacture a wearoff.');
s.party[1].revision=2;s.party[1].effects={{effect=40,slot=0}};t:reconcile(s,4.2);v=t:view(4.2,{},s);
for _,r in ipairs(v.rows) do if r.entity_id==20 then held=r; end end
assert(held.present and held.status=='estimated');
t:observe({{kind='apply',entity_id=100,effect=5,source=10,duration=600}},5,s);
v=t:view(300,{tracking={stale_seconds=60}},s);held=nil;
for _,r in ipairs(v.rows) do if r.entity_id==100 then held=r; end end
assert(held and held.remaining==305,'A long timer must survive the unknown-observation retention window.');
v=t:view(606,{tracking={stale_seconds=60}},s);held=nil;
for _,r in ipairs(v.rows) do if r.entity_id==100 then held=r; end end
assert(held and held.status=='unknown','Keep the expired estimate briefly without asserting a wearoff.');
v=t:view(666,{tracking={stale_seconds=60}},s);
for _,r in ipairs(v.rows) do assert(r.entity_id~=100); end

t=require('core.tracker').new();s=snapshot();t:reconcile(s,0);
t:observe({{kind='apply',entity_id=10,effect=33,source=10}},1,s);s.self_effects={status(33,0,601,36060)};t:reconcile(s,1);t:drain_events();
assert(t:view(1,{},s).rows[1].mine);
s.self_effects={status(33,0,650,39000)};t:reconcile(s,2);v=t:view(2,{},s);t:drain_events();
assert(v.rows[1].mine==nil and v.rows[1].source==nil,'Unattributed refresh must clear the previous caster attribution.');
s.self_known=false;t:reconcile(s,190);t:view(190,{tracking={stale_seconds=10}},s);t:drain_events();
s.self_known=true;t:reconcile(s,191);
assert(#t:drain_events()==0,'Recovering a lost status snapshot must establish a quiet baseline.');
