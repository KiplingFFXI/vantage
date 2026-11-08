-- Phoenix keeps an effect without on_zone through a zone change as the same copy and lists it again at
-- zone-in (status_effect_container.cpp BuildPersistRows, LoadStatusEffects). The player's own Protect keeps
-- who cast it across the zone reset. A song, a different character, or a copy recast since gets nothing.
local tracker=require('core.tracker').new();
local SELF=1001;
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(id,zone,revision,timers,effects)
    return {valid=true,id=id,name='Tester',zone=zone,job=3,self_known=true,self_revision=revision,
        self_timer_revision=timers,self_effects=effects,party={},entities={}};
end;
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    return tracker:view(now,{},snap),tracker:drain_events();
end;
local function find(view,effect) for _,r in ipairs(view.rows) do if r.effect==effect then return r;end;end;end;
local function cast(effect,spell,source,count,extra)
    local out={kind='apply',entity_id=SELF,effect=effect,scope='self',source=source,spell=spell,timer_revision=count};
    for k,v in pairs(extra or {}) do out[k]=v;end;
    return out;
end;
local function zone_in(id,zone,effects,now)
    tracker:clear('Zone changed',now);
    frame({valid=false},now+1);
    return frame(snapshot(id,zone,1,1,effects),now+5);
end;
local function setup()
    tracker=require('core.tracker').new();
    frame(snapshot(SELF,102,1,0,{}),0);
    frame(snapshot(SELF,102,3,1,{status(40,0,1800,108000)}),10,{cast(40,43,SELF,0)});
    frame(snapshot(SELF,102,5,2,{status(40,0,1790,108000),status(198,1,120,7200)}),20,{cast(198,397,SELF,1,{tier=4})});
    local view=frame(snapshot(SELF,102,5,2,{status(40,0,1790,108000),status(198,1,120,7200)}),21);
    assert(find(view,40).source==SELF and find(view,40).mine and find(view,198).source==SELF,'Fixture: both are the player\'s.');
end;

setup();
local view,events=zone_in(SELF,103,{status(40,0,1700,102000),status(198,1,100,6000)},30);
local protect=find(view,40);
assert(protect and protect.source==SELF and protect.mine==true and protect.spell==43,
    'Protect kept through the zone change keeps its caster and still counts as the player\'s own.');
assert(#events==0,'Nothing is announced at zone-in.');
assert(find(view,198).source==nil,'A song is lost on a zone change on Phoenix, so a Minuet listed after it has no caster to carry.');
view=frame(snapshot(SELF,103,1,1,{status(40,0,1700,102000)}),40);
assert(find(view,40).source==SELF,'And keeps it.');

-- Another character after the reset gets nothing.
setup();
view=zone_in(2002,103,{status(40,0,1700,102000)},30);
assert(find(view,40).source==nil and not find(view,40).mine,'Another character does not take the player\'s casters.');

-- Recast during zone-in: that cast is the one credited.
setup();
tracker:clear('Zone changed',30);
frame({valid=false},31);
view=frame(snapshot(SELF,103,1,1,{status(40,0,1800,108000)}),35,{cast(40,44,2003,0)});
assert(find(view,40).source==2003,'A Protect cast since is credited to its caster.');

-- The carried casters last only to the first whole listing.
setup();
zone_in(SELF,103,{},30);
view=frame(snapshot(SELF,103,3,2,{status(40,0,1800,108000)}),40);
assert(find(view,40).source==nil,'A Protect that shows up later is not given the old caster.');
