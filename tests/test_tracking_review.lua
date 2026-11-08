local T = require('core.tracker');
local t = T.new();
local s = {valid=true,id=10,name='Self',zone=1,self_known=true,self_effects={},entities={},
    party={{id=20,name='Friend',zone=1,valid=true,effects={},revision=1}}};
t:reconcile(s,0); t:drain_events();
t:observe({{kind='apply',entity_id=20,effect=40,source=10,duration=1800}},1,s);
t:drain_events();
t:reconcile(s,8);
local v = t:view(8,{},s);
assert(#v.rows == 1 and v.rows[1].remaining == 1793, 'Rereading a cached packet cannot remove a later observed buff.');
assert(#t:drain_events() == 0 and not t.entities[20].known, 'Stale party evidence cannot produce wearoff or missing alerts.');
s.party[1].revision, s.party[1].effects = 2, {{effect=40,slot=0}};
t:reconcile(s,9);
assert(t.entities[20].known and t:view(9,{},s).rows[1].present);
t:observe({{kind='remove',entity_id=20,effect=40}},10,s); t:drain_events();
t:reconcile(s,20);
assert(#t:view(20,{},s).rows == 0 and #t:drain_events() == 0, 'An old cached party icon cannot reappear after the removal guard ages.');
s.party[1].revision, s.party[1].effects = 3, {};
t:reconcile(s,21);
s.party[1].revision, s.party[1].effects = 4, {{effect=13,slot=0}};
t:reconcile(s,22); t:drain_events();
t:observe({{kind='apply',entity_id=20,effect=33,duration=180,drops={13}}},23,s); t:drain_events();
t:reconcile(s,30); v=t:view(30,{},s);
assert(#v.rows == 1 and v.rows[1].effect == 33 and #t:drain_events() == 0, 'A replaced Slow icon must not return from a stale party packet.');
s.party[1].revision, s.party[1].effects = 5, {{effect=33,slot=0}};
t:reconcile(s,31); assert(t:view(31,{},s).rows[1].present);

t=T.new(); s.party[1].revision, s.party[1].effects=1, {};
t:reconcile(s,0);
t:observe({{kind='apply',entity_id=20,effect=195,source=10,spell=1,instance_hint='10:1',stackable=true,duration=120},
    {kind='apply',entity_id=20,effect=195,source=10,spell=2,instance_hint='10:2',stackable=true,duration=150}},1,s);
s.party[1].revision, s.party[1].effects=2, {{effect=195,slot=0},{effect=195,slot=1}};
t:reconcile(s,2); t:drain_events();
s.party[1].revision, s.party[1].effects=3, {{effect=195,slot=0}};
t:reconcile(s,3); v=t:view(3,{},s);
assert(#v.rows==1 and v.rows[1].present and v.rows[1].status=='unknown');
assert(v.rows[1].source==nil and v.rows[1].spell==nil and v.rows[1].remaining==nil,
    'An icon-only duplicate count reduction cannot identify the remaining song or timer.');
assert(#t:drain_events()==0, 'Ambiguous duplicate replacement must not claim which song wore off or a new gain.');
s.party[1].revision, s.party[1].effects=4, {};
t:reconcile(s,4); assert(t:drain_events()[1].kind=='removed', 'Complete icon absence is still authoritative.');
t=T.new(); s.party[1].revision, s.party[1].effects=1, {{effect=195,slot=0}};
t:reconcile(s,0);
t:observe({{kind='apply',entity_id=20,effect=195,source=10,spell=2,instance_hint='10:2',stackable=true,duration=150}},1,s);
t:drain_events(); t:reconcile(s,8); v=t:view(8,{},s);
assert(#v.rows==2 and #t:drain_events()==0, 'An older duplicate icon count cannot replace a newly applied song before the new packet.');
local estimated=0; for _, row in ipairs(v.rows) do if row.status=='estimated' then estimated=estimated+1; end end
assert(estimated==1 and not t.entities[20].known);
t=T.new(); s.party[1].revision, s.party[1].effects=1, {};
t:reconcile(s,0);
t:observe({{kind='apply',entity_id=20,effect=40,source=10,duration=1}},1,s);
t:reconcile(s,20); t:view(20,{tracking={stale_seconds=10}},s);
t:reconcile(s,21);
assert(not t.entities[20].known, 'Retiring an old estimate cannot make the pre-cast packet authoritative again.');
s.party[1].revision=2; t:reconcile(s,22); assert(t.entities[20].known);
return true;
