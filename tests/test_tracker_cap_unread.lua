-- The player at their song cap sings Valor Minuet IV just after another bard's Minuet IV landed on them,
-- before a listing showed it. Phoenix ApplyBardEffect deletes the other bard's copy (same ID and tier), then
-- gives the new copy the slot of the player's song that ends first and deletes that too. The cast's listing
-- shows the other bard's copy where it was, apart from the new one: it is the replaced copy, so the cast
-- is one gain of the player's Minuet, and the next tick removes only the song the cap dropped.
local SELF=1001;
local tracker;
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(revision,timers,effects)
    return {valid=true,id=SELF,name='Tester',zone=102,job=10,self_known=true,self_revision=revision,
        self_timer_revision=timers,self_effects=effects,party={},entities={}};
end;
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    return tracker:view(now,{},snap),tracker:drain_events();
end;
local function kinds(events)
    local out={};
    for _,event in ipairs(events) do if event.entity_id then out[#out+1]=event.kind..':'..tostring(event.effect)..':'..tostring(event.source); end end;
    return table.concat(out,',');
end;
local function cast(effect,spell,source,count,tier)
    return {kind='apply',entity_id=SELF,effect=effect,scope='self',source=source,spell=spell,timer_revision=count,tier=tier,
        stackable=true,instance_hint=source..':'..spell};
end;
local function setup()
    tracker=require('core.tracker').new();
    frame(snapshot(1,0,{}),0);
    frame(snapshot(2,1,{status(214,0,120,7200)}),10,{cast(214,420,SELF,0,2)});
    frame(snapshot(3,2,{status(214,0,120,7200),status(196,1,140,8400)}),20,{cast(196,386,SELF,1,1)});
end;
local function minuets(view)
    local out={};for _,r in ipairs(view.rows) do if r.effect==198 and not r.departing then out[#out+1]=r;end;end;return out;
end;
-- Both casts in one batch, the other bard's copy reading like the new one or shorter.
for _,variant in ipairs({{170,10200},{160,9600}}) do
    setup();
    local view,events=frame(snapshot(5,3,{status(198,0,170,10200),status(214,1,120,7200),status(196,2,140,8400),
        status(198,3,variant[1],variant[2])}),50,{cast(198,397,2003,2,4),cast(198,397,SELF,2,4)});
    assert(kinds(events)=='gain:198:1001','Over the cap the cast tick is one gain of the player\'s Minuet: '..kinds(events));
    assert(#minuets(view)==1 and minuets(view)[1].source==SELF,'One Minuet, the player\'s.');
    view,events=frame(snapshot(7,4,{status(198,0,170,10200),status(196,1,140,8400)}),50.4);
    assert(kinds(events)=='removed:214:1001','The next tick removes only the March the cap dropped: '..kinds(events));
    assert(#minuets(view)==1 and minuets(view)[1].source==SELF and minuets(view)[1].spell==397,'The Minuet stays the player\'s.');
end;
-- The other bard's 0x028 a batch earlier, with no listing between.
setup();
frame(snapshot(3,2,{status(214,0,120,7200),status(196,1,140,8400)}),49.7,{cast(198,397,2003,2,4)});
local view,events=frame(snapshot(5,3,{status(198,0,170,10200),status(214,1,120,7200),status(196,2,140,8400),status(198,3,170,10200)}),50.1,
    {cast(198,397,SELF,2,4)});
assert(kinds(events)=='gain:198:1001','A batch earlier, the same: '..kinds(events));
view,events=frame(snapshot(7,4,{status(198,0,170,10200),status(196,1,140,8400)}),50.5);
assert(kinds(events)=='removed:214:1001','And the next tick removes only the March: '..kinds(events));
-- Not over the cap: the new copy takes the other bard's slot, right after it.
tracker=require('core.tracker').new();
frame(snapshot(1,0,{}),0);
frame(snapshot(2,1,{status(214,0,120,7200)}),10,{cast(214,420,SELF,0,2)});
view,events=frame(snapshot(5,2,{status(214,0,120,7200),status(198,1,170,10200),status(198,2,170,10200)}),50,
    {cast(198,397,2003,1,4),cast(198,397,SELF,1,4)});
assert(kinds(events)=='gain:198:1001','Under the cap, one gain too: '..kinds(events));
view,events=frame(snapshot(7,3,{status(214,0,120,7200),status(198,1,170,10200)}),50.4);
assert(kinds(events)=='','Under the cap nothing leaves: '..kinds(events));
