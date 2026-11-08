-- A caster's song doesn't stack with itself. With two songs of one ID the wear-off message can't say which
-- ended, so the old copy stays listed until its slot clears; the same bard singing it again meanwhile adds
-- a new copy. That copy replaced the old one, so it takes the application the old one seems to own.
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
    for _,row in ipairs(view.rows) do if row.effect==198 and row.slot==slot and row.present then return row; end; end;
end;
local function song(spell,source)
    return {kind='apply',entity_id=1001,effect=198,scope='self',source=source,spell=spell};
end;
local wearoff={kind='remove',entity_id=1001,effect=198,scope='self',reason='Observed wearoff'};

-- Another bard's song, then the player's own.
for _,bard in ipairs({2002,1001}) do
    tracker=require('core.tracker').new();
    local both={status(198,0,100,6000),status(198,1,130,7800)};
    frame(snapshot(1,{}),0);
    frame(snapshot(2,{both[1]}),1,{song(394,bard)});
    local view=frame(snapshot(3,both),2,{song(395,2003)});
    local old=at(view,0).key;
    local events;
    view,events=frame(snapshot(3,both),100.1,{wearoff});
    assert(#events==0 and not at(view,0).departing and not at(view,1).departing,'Two candidates: the message marks neither song.');
    view,events=frame(snapshot(4,{both[1],both[2],status(198,2,220,13200)}),100.5,{song(394,bard)});
    local new=at(view,2);
    assert(#events==1 and events[1].kind=='gain' and events[1].spell==394 and events[1].source==bard,
        'The new copy is gained with its caster.');
    assert(new and new.key~=old and new.spell==394 and new.source==bard and new.mine==(bard==1001)
        and new.start==100.5 and new.total==119.5,'The new copy takes the application and its start.');
    view,events=frame(snapshot(5,{status(198,0,130,7800),status(198,1,220,13200)}),100.9);
    assert(#events==1 and events[1].kind=='removed' and events[1].key==old and events[1].spell==394 and events[1].source==bard,
        'The old copy leaves as itself once its slot clears.');
    local kept=at(view,1);
    assert(kept and kept.key==new.key and kept.spell==394 and kept.source==bard and kept.mine==(bard==1001),
        'The new copy keeps its caster for the rest of its time, so a mine_only panel keeps showing it.');
    assert(at(view,0).spell==395 and at(view,0).source==2003,'The other song keeps its own caster.');
end;

-- A created row still takes an application no listed row owns before one a listed row owns.
tracker=require('core.tracker').new();
local both={status(198,0,100,6000),status(198,1,130,7800)};
frame(snapshot(1,{}),0);
frame(snapshot(2,{both[1]}),1,{song(394,2002)});
frame(snapshot(3,both),2,{song(395,2003)});
local view,events=frame(snapshot(4,{both[1],both[2],status(198,2,221,13260)}),100.5,{song(394,2002),song(396,2004)});
local new=at(view,2);
assert(#events==1 and events[1].kind=='gain' and new and new.spell==396 and new.source==2004,
    'The new copy is the other bard\'s song, not a recast of the copy still listed.');
assert(at(view,0).spell==394 and at(view,0).source==2002 and at(view,0).instance==1,'The listed copy keeps its own.');
