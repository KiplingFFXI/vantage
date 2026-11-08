-- A split send (the 0x037 before its 0x063) holds back a same-ID row it can't place. However old that row
-- is, it waits for the 0x063 instead of retiring as stale, so the removal still goes to the song that
-- ended and the other song keeps its row.
local tracker;
local settings={tracking={stale_seconds=10}};
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(revision,effects,pending)
    return {valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_revision=revision,
        self_timers_pending=pending,self_effects=effects,party={},entities={}};
end;
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    return tracker:view(now,settings,snap),tracker:drain_events();
end;
local function count(events,kind)
    local n=0;
    for _,event in ipairs(events) do if event.kind==kind then n=n+1; end; end;
    return n;
end;
local function by_key(view,key)
    for _,row in ipairs(view.rows) do if row.key==key then return row; end; end;
end;
local function song(spell,source)
    return {kind='apply',entity_id=1001,effect=198,scope='self',source=source,spell=spell};
end;

tracker=require('core.tracker').new();
frame(snapshot(1,{}),0);
frame(snapshot(2,{status(198,0,100,6000)}),1,{song(394,2002)});
local both={status(198,0,100,6000),status(198,1,130,7800)};
local view=frame(snapshot(3,both),2,{song(395,2003)});
local key;
for _,row in ipairs(view.rows) do if row.spell==395 then key=row.key; end; end;
-- 394 ends. Two candidates leave it to the status update, which comes split, 98 s after 395 was seen.
frame(snapshot(3,both),100.1,{{kind='remove',entity_id=1001,effect=198,scope='self'}});
local events;
view,events=frame(snapshot(4,{status(198,0,nil,nil)},true),100.3);
local held=by_key(view,key);
assert(#events==0 and held and held.present==false,'The row held back by the split is kept past the stale time.');
view,events=frame(snapshot(4,{status(198,0,nil,nil)},true),100.32);
assert(#events==0 and by_key(view,key),'It stays held while the split lasts.');
view,events=frame(snapshot(5,{status(198,0,130,7800)}),100.35);
assert(count(events,'refresh')==0 and count(events,'gain')==0,'The 0x063 makes no refresh or gain.');
assert(count(events,'removed')==1 and events[1].spell==394 and events[1].source==2002,'The removal goes to the song that ended.');
local row=by_key(view,key);
assert(#view.rows==1 and row and row.present and row.spell==395 and row.source==2003 and row.instance==1 and row.slot==0,
    'The other song keeps its row and caster.');

-- A row that is not held still retires once it is past the stale time.
tracker:reconcile({valid=true,id=1001,name='Tester',zone=102,job=1,self_known=false,self_revision=6,
    self_effects={},party={},entities={}},101);
view=tracker:view(112,settings);
assert(#view.rows==0 and #tracker:drain_events()==0,'An unreadable row still retires quietly after the stale time.');
