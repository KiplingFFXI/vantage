-- A spell Phoenix marks Always_Overwrite (Refresh, the bar-spells, storms, Aquaveil, Embrava) takes the old
-- copy off with a wear-off message, then adds the new one (enhancing_spell.lua: delStatusEffect, then
-- addStatusEffect). The message goes to the owner and to the old copy's caster, so the player sees it for
-- what they cast on others too (status_effect_container.cpp RemoveStatusEffect), just before the action
-- that renews it. That is one renewal, and alerts never announce a removal the same batch undid.
local tracker,alerts;
local SELF,BOB=1001,2001;
local function snapshot(revision,timers,self_effects,bob_effects,bob_revision)
    return {valid=true,id=SELF,name='Tester',zone=102,job=5,self_known=true,self_revision=revision,
        self_timer_revision=timers,self_effects=self_effects,
        party={{id=BOB,name='Bob',scope='party',valid=true,zone=102,revision=bob_revision,effects=bob_effects}},entities={}};
end;
local rules={
    {id='party_removed',enabled=true,event='removed',effect=43,scope='party',cooldown=0,duration=30,visual=true},
    {id='self_removed',enabled=true,event='removed',effect=43,scope='self',cooldown=0,duration=30,visual=true},
    {id='self_gain',enabled=true,event='gain',effect=43,scope='self',cooldown=0,duration=30,visual=true},
};
local fired;
local function frame(snap,now,observations)
    tracker:observe(observations or {},now,snap);
    tracker:reconcile(snap,now);
    local view=tracker:view(now,{},snap);
    local events=tracker:drain_events();
    alerts:update(view,events,rules,now,{});
    fired={};
    for _,notice in ipairs(alerts:drain(now)) do fired[notice.rule_id]=(fired[notice.rule_id] or 0)+1; end;
    return view,events;
end;
local function kinds(events)
    local out={};
    for _,event in ipairs(events) do
        if event.entity_id then out[#out+1]=event.kind..':'..tostring(event.entity_id)..':'..tostring(event.effect)..':'..tostring(event.source); end
    end;
    return table.concat(out,',');
end;
local function rows(view,entity)
    local out={};
    for _,row in ipairs(view.rows) do if row.entity_id==entity and row.effect==43 then out[#out+1]=row; end; end;
    return out;
end;
local function apply(target,source,count)
    return {kind='apply',entity_id=target,effect=43,scope=target==SELF and 'self' or 'party',source=source,spell=109,
        action_category=4,duration=150,timer_revision=target==SELF and count or nil};
end;
-- The copy to its caster: actor the caster, target the owner.
local function wearoff(target,source,count)
    return {kind='remove',entity_id=target,effect=43,scope=target==SELF and 'self' or 'party',source=source,
        reason='Observed wearoff',timer_revision=target==SELF and count or nil};
end;

-- The player refreshes Bob early, and again; another RDM refreshes Bob's Refresh the player cast.
for _,by in ipairs({SELF,2005}) do
    tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
    frame(snapshot(1,0,{},{},1),0);
    frame(snapshot(1,0,{},{},1),10,{apply(BOB,SELF)});
    local view,events=frame(snapshot(2,0,{},{{effect=43,slot=0}},2),11);
    local key=rows(view,BOB)[1].key;
    view,events=frame(snapshot(2,0,{},{{effect=43,slot=0}},2),15,{wearoff(BOB,SELF),apply(BOB,by)});
    assert(kinds(events)=='refresh:2001:43:'..by and #rows(view,BOB)==1 and rows(view,BOB)[1].key==key
        and rows(view,BOB)[1].source==by and not rows(view,BOB)[1].departing,'One renewal of Bob\'s Refresh: '..kinds(events));
    assert(fired.party_removed==nil,'No removal alert.');
    view,events=frame(snapshot(2,0,{},{{effect=43,slot=0}},3),15.5);
    assert(#events==0 and rows(view,BOB)[1].key==key,'And the listing after it changes nothing: '..kinds(events));
end;
-- A removal with nothing after it is still one; so is one after the cast.
tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
frame(snapshot(1,0,{},{},1),0);
frame(snapshot(1,0,{},{},1),10,{apply(BOB,SELF)});
frame(snapshot(2,0,{},{{effect=43,slot=0}},2),11);
local view,events=frame(snapshot(2,0,{},{{effect=43,slot=0}},2),15,{apply(BOB,SELF),wearoff(BOB,SELF)});
assert(kinds(events)=='refresh:2001:43:1001,removed:2001:43:1001' and fired.party_removed==1,'It went after the cast: '..kinds(events));

-- The player's Refresh ran out as they cast it in that tick: the listing shows the new copy alone, so it
-- went and came again. The removal alert stays quiet, since the same batch has it back.
tracker,alerts=require('core.tracker').new(),require('core.alerts').new();
frame(snapshot(1,0,{},{},1),0);
frame(snapshot(2,1,{{effect=43,slot=0,raw_timer=480,deadline=8}},{},1),0.5,{apply(SELF,SELF,0)});
view,events=frame(snapshot(4,2,{{effect=43,slot=0,raw_timer=9480,deadline=158}},{},1),8.2,{wearoff(SELF,nil,1),apply(SELF,SELF,1)});
assert(kinds(events)=='removed:1001:43:1001,gain:1001:43:1001','It wore off and was gained again: '..kinds(events));
assert(fired.self_removed==nil and fired.self_gain==1,'Only the gain is announced.');
-- A removal with no gain after it in the batch is announced.
view,events=frame(snapshot(6,3,{},{},1),10,{wearoff(SELF,nil,2)});
assert(kinds(events)=='removed:1001:43:1001' and fired.self_removed==1,'A plain removal is: '..kinds(events));
