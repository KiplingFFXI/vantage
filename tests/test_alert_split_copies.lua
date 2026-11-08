-- A split send (the 0x037 before its 0x063) lists same-ID copies without timers. When their count changes,
-- the copy that keeps a slot may be the one that left, so no copy of that effect fires a countdown until a
-- complete listing settles which stayed. Then a copy still on and still past its threshold fires, late by
-- the split at most; the copy that left never does.
local tracker,alerts;
local rules={{id='count',enabled=true,event='remaining',effect=198,scope='self',thresholds={60},cooldown=0,duration=10,visual=true},
    {id='haste',enabled=true,event='remaining',effect=33,scope='self',thresholds={60},cooldown=0,duration=10,visual=true}};
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(revision,effects,pending)
    return {valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_revision=revision,
        self_timers_pending=pending,self_effects=effects,party={},entities={}};
end;
local fired;
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    local view=tracker:view(now,{},snap);
    alerts:update(view,tracker:drain_events(),rules,now,{});
    for _,notice in ipairs(alerts:drain(now)) do fired[#fired+1]=notice; end;
    return view;
end;
local function song(spell,source)
    return {kind='apply',entity_id=1001,effect=198,scope='self',source=source,spell=spell};
end;
local function spells(from)
    local out={};
    for n=from,#fired do out[#out+1]=tostring(fired[n].rule_id)..':'..tostring(fired[n].key)..'@'..fired[n].time; end;
    return table.concat(out,',');
end;
local keys;
-- 394 (slot 0) ends at 160 and 395 at 200; Haste ends at 160 too. Both songs run to 60.1 s left on 394.
local function start(extra)
    tracker,alerts,fired,keys=require('core.tracker').new(),require('core.alerts').new(),{},{};
    local a,b=status(198,0,160,9600),status(198,1,200,12000);
    for t=0,50,5 do frame(snapshot(1,{}),t); end;
    local listing={a,b,extra};
    local view=frame(snapshot(2,listing),55,{song(394,2002),song(395,2003)});
    for _,row in ipairs(view.rows) do keys[row.spell or row.effect]=row.key; end;
    for t=55.1,99.9,0.1 do frame(snapshot(2,listing),t); end;
    assert(#fired==0,'Nothing has crossed yet.');
end;

-- 394 is dropped with no message. The split lists one copy, which pairing gives to 394.
start();
local view=frame(snapshot(3,{status(198,0,nil,nil)},true),100.05);
local kept;
for _,row in ipairs(view.rows) do if row.present then kept=row; end; end;
assert(kept and kept.key==keys[394] and kept.remaining<60,'The copy that kept the slot is past 60 s.');
assert(#fired==0,'No countdown fires for it during the split: '..spells(1));
frame(snapshot(4,{status(198,0,200,12000)}),100.1);
assert(#fired==0,'The 0x063 shows 394 left: its countdown never fires.');
for t=100.2,141,0.1 do frame(snapshot(4,{status(198,0,200,12000)}),t); end;
assert(#fired==1 and fired[1].key==keys[395],'395 still counts down on time: '..spells(1));

-- 395 is the copy that left. 394 crossed during the split and fires once it is settled.
start();
frame(snapshot(3,{status(198,0,nil,nil)},true),100.05);
assert(#fired==0,'Held during the split.');
frame(snapshot(4,{status(198,0,160,9600)}),100.1);
assert(#fired==1 and fired[1].key==keys[394] and fired[1].time==100.1 and fired[1].threshold==60,
    'The crossing fires once the 0x063 shows 394 stayed: '..spells(1));
for t=100.2,110,0.1 do frame(snapshot(4,{status(198,0,160,9600)}),t); end;
assert(#fired==1,'And only once.');

-- A count that rises in a split holds the copies too; another effect's countdown is not held.
start(status(33,2,160,9600));
frame(snapshot(3,{status(198,0,nil,nil),status(198,1,nil,nil),status(198,2,nil,nil),status(33,3,nil,nil)},true),100.05);
assert(#fired==1 and fired[1].rule_id=='haste','Only Haste fires during the split: '..spells(1));
frame(snapshot(4,{status(198,0,160,9600),status(198,1,200,12000),status(198,2,220,13200),status(33,3,160,9600)}),100.1);
assert(#fired==2 and fired[2].key==keys[394] and fired[2].time==100.1,'394 fires once settled: '..spells(1));
