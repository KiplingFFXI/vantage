local tracker=require('core.tracker').new();
local s={valid=true,id=10,name='Self',zone=1,self_known=true,self_effects={{effect=33,slot=0,deadline=100}},
    party={{id=20,name='Party',scope='party',group=1,slot=1,zone=1,valid=true,revision=1,effects={{effect=40,slot=0}}},
        {id=30,name='Alliance',scope='alliance',group=2,slot=6,zone=1,valid=false,effects={}}},entities={}};
tracker:reconcile(s,0);tracker:drain_events();
tracker:observe({{kind='apply',entity_id=30,effect=33,source=20,duration=180}},1,s);tracker:drain_events();
s.dead=true;tracker:reconcile(s,2);
local v=tracker:view(2,{},s);local rows={};for _,row in ipairs(v.rows) do rows[row.entity_id]=row;end
assert(v.valid and rows[10] and rows[10].effect==33 and rows[10].present and rows[20].present and rows[30].scope=='alliance' and rows[30].remaining==179,
    'A KO keeps self rows that are still listed.');
assert(rows[30].present==nil,'Observed alliance application does not claim a complete icon list.');
local events=tracker:drain_events();assert(#events==0,'A KO is quiet.');
tracker:reconcile(s,2.1);assert(#tracker:drain_events()==0,'A KO is handled once without repeated reset events.');
tracker:observe({{kind='apply',entity_id=20,effect=37,source=30,duration=60},
    {kind='apply',entity_id=30,effect=40,source=20,duration=90},
    {kind='apply',entity_id=10,effect=40,source=20,duration=90}},3,s);
v=tracker:view(3,{},s);local count,own=0,0;for _,row in ipairs(v.rows) do if row.entity_id==10 then own=own+1;else count=count+1;end;end
assert(count==4,'Others continue receiving observations during local KO.');
assert(own==1 and not next(tracker.pending),'Self observations stay ignored while KO.');tracker:drain_events();
s.dead=false;tracker:reconcile(s,4);assert(#tracker:drain_events()==0,'Returning from KO establishes a quiet self baseline.');
v=tracker:view(4,{},s);local subject;
for _,row in ipairs(v.subjects) do if row.id==30 then subject=row;end;end
assert(subject.scope=='alliance' and subject.group==2 and subject.slot==6 and not subject.known);
s.party[2].zone=2;tracker:reconcile(s,5);v=tracker:view(5,{},s);
for _,row in ipairs(v.rows) do assert(row.entity_id~=30,'A roster member zone change discards old zone observations.');end
s.party[2].zone=1;s.party[2].scope='party';s.party[2].group=1;s.party[2].slot=2;
tracker:reconcile(s,6);tracker:observe({{kind='apply',entity_id=30,effect=40,source=20,duration=30}},6,s);
s.party[2].scope='alliance';s.party[2].group=3;s.party[2].slot=12;tracker:reconcile(s,7);
v=tracker:view(7,{},s);for _,row in ipairs(v.rows) do if row.entity_id==30 then assert(row.scope=='alliance');end;end
s.party[2]=nil;tracker:reconcile(s,8);v=tracker:view(8,{},s);
for _,row in ipairs(v.subjects) do assert(row.id~=30,'Departed alliance members do not remain roster subjects.');end
