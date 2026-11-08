-- A caster's song doesn't stack with itself, so an application with the spell and caster of a song still
-- listed re-applied that song. A recast landing within a second of the old timer doesn't move it enough to
-- see, so its application waits up to 3 s; a new song in that time must not take it.
local tracker;
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
local function at(view,slot)
    for _,row in ipairs(view.rows) do if row.effect==198 and row.slot==slot then return row; end; end;
end;
local function song(spell,source)
    return {kind='apply',entity_id=1001,effect=198,scope='self',source=source,spell=spell};
end;

-- 394 is sung again half a second later; the timer moves by one restamp step.
tracker=require('core.tracker').new();
frame(snapshot(1,{}),990);
frame(snapshot(2,{status(198,0,1110,66600)}),990.2,{song(394,2002)});
local view,events=frame(snapshot(3,{status(198,0,1111,66660)}),990.7,{song(394,2002)});
assert(#events==0,'The recast shows no refresh.');
view,events=frame(snapshot(4,{status(198,0,1111,66660),status(198,1,1112,66720)}),991.6,{song(395,2003)});
assert(#events==1 and events[1].kind=='gain' and events[1].spell==395 and events[1].source==2003,
    'The new song is credited to its own bard, not the recast still waiting.');
assert(at(view,0).spell==394 and at(view,0).source==2002 and at(view,1).spell==395 and at(view,1).source==2003,
    'Each row keeps its own caster.');

-- One status update brings another bard's new song and a recast of 394, the new song's message first.
tracker=require('core.tracker').new();
frame(snapshot(1,{}),0);
frame(snapshot(2,{status(198,0,100,6000)}),1,{song(394,2002)});
view,events=frame(snapshot(3,{status(198,0,170,10200),status(198,1,171,10260)}),50.1,{song(395,2003),song(394,2002)});
assert(at(view,0).spell==394 and at(view,0).source==2002 and at(view,0).instance==2,'The recast song takes its own application.');
assert(at(view,1).spell==395 and at(view,1).source==2003,'The new song takes the other bard\'s.');

-- 394 wears and is sung again before the update that drops the old copy. The departing copy holds nothing.
tracker=require('core.tracker').new();
frame(snapshot(1,{}),0);
frame(snapshot(2,{status(198,0,100,6000)}),1,{song(394,2002)});
frame(snapshot(2,{status(198,0,100,6000)}),2);
view,events=frame(snapshot(2,{status(198,0,100,6000)}),100.1,{{kind='remove',entity_id=1001,effect=198,scope='self'}});
local worn=at(view,0);
assert(#events==1 and events[1].kind=='removed' and worn and worn.departing,'The worn copy departs.');
view,events=frame(snapshot(3,{status(198,0,100,6000),status(198,1,220,13200)}),100.5,{song(394,2002)});
assert(at(view,1) and at(view,1).spell==394 and at(view,1).source==2002,'The new copy takes the application.');
