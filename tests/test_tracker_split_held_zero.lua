-- A server timer that runs out stays known at zero until the server clears its slot. That holds for a
-- same-ID copy a split send holds back (present false) too: when its 0x063 shows it stayed with the same
-- timer, it is still known at zero, as it would be without the split.
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(revision,effects,pending)
    return {valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_revision=revision,
        self_timers_pending=pending,self_effects=effects,party={},entities={}};
end;
local function run(split)
    local tracker=require('core.tracker').new();
    local function frame(snap,now,observations)
        tracker:observe(observations or {},now,snap);
        tracker:reconcile(snap,now);
        return tracker:view(now,{},snap),tracker:drain_events();
    end;
    local both={status(198,0,100,6000),status(198,1,100.2,6012)};
    frame(snapshot(1,{}),0);
    frame(snapshot(2,both),1);
    frame(snapshot(2,both),100.05,{{kind='remove',entity_id=1001,effect=198,scope='self'}});
    local held;
    if split then
        local view=frame(snapshot(3,{status(198,0,nil,nil)},true),100.3);
        for _,row in ipairs(view.rows) do if row.raw_timer==6012 then held=row; end; end;
        assert(held and held.present==false and held.status=='server' and held.deadline==100.2 and held.remaining==0,
            'The held copy stays known at zero during the split.');
        tracker:project(view,100.32);
        assert(held.status=='server' and held.remaining==0,'Projection keeps it known at zero.');
    end;
    local view,events=frame(snapshot(4,{status(198,0,nil,6012)}),100.35);
    local row;
    for _,held_row in ipairs(view.rows) do if held_row.raw_timer==6012 then row=held_row; end; end;
    assert(#events==1 and events[1].kind=='removed' and events[1].raw_timer==6000,'The copy that ended is reported.');
    return row;
end;
local plain,split=run(false),run(true);
assert(plain and plain.status=='server' and plain.deadline==100.2 and plain.remaining==0,'Without a split it is known at zero.');
assert(split and split.present and split.status=='server' and split.deadline==100.2 and split.remaining==0,
    'After the split it is known at zero the same way.');
