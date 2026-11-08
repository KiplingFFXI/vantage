-- A wear-off or removal message lands before the status update. The row stays drawn until its slot
-- clears.
package.loaded['ui.icons']={status=function(id) return 1000+id; end};
local hud,defaults,visible=require('ui.hud'),require('ui.defaults'),require('visible_icons');
local slot,container,ptr,header,vtable,manager=0x110000,0x120000,0x130000,0x140000,0x150000,0x170000;
local memory={[slot]=container,[container]=vtable,[container+8]=ptr,[ptr+12]=container,[ptr+4]=header,
    [ptr+0x6A]=1,[manager+0x54]=0,[manager+0x5C]=0};
for index,value in ipairs({0x756E656D,0x20202020,0x66667562,0x20202020}) do memory[header+0x46+(index-1)*4]=value; end;
MOCK.screen={1600,1000};
local s=defaults.make();
s.style.font,s.style.font_size,s.style.scale='Ashita',14,1;
for id,p in pairs(s.panels) do
    p.enabled=id=='self_buffs' or id=='self_debuffs';
    p.show_heading=false;p.mode='icons';p.width=300;p.max_rows=32;
end;
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(revision,effects)
    local ids={};
    for _,row in ipairs(effects) do ids[#ids+1]=row.effect; end;
    memory[container+0x40]=#ids;
    for index,id in ipairs(ids) do memory[container+0x290+(index-1)*2]=id; end;
    return {valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_revision=revision,
        self_effects=effects,party={},entities={}};
end;
local tracker;
-- Returns the view, the effects whose icons the self panels show in full this frame, and the events.
local function frame(snap,now,observations)
    if observations then tracker:observe(observations,now,snap); end;
    tracker:reconcile(snap,now);
    local view=tracker:view(now,s,snap);
    MOCK.imgui_calls={};
    hud.draw(view,s,now,{});
    local shown={};
    for _,icon in ipairs(visible(function(texture) return texture>1000; end)) do shown[icon.texture-1000]=true; end;
    return view,shown,tracker:drain_events();
end;
local function find(view,effect)
    for _,row in ipairs(view.rows) do if row.effect==effect then return row; end; end;
end;
local function count(events,kind)
    local n=0;
    for _,event in ipairs(events) do if event.kind==kind then n=n+1; end; end;
    return n;
end;
local removal={{kind='remove',entity_id=1001,effect=33,scope='self',reason='Haste wore off.'}};

-- Message first, status packet in a later network update.
tracker=require('core.tracker').new();
local alerts=require('core.alerts').new();
local rules={
    {id='removed',enabled=true,event='removed',effect=33,scope='self',cooldown=0,visual=true},
    {id='missing',enabled=true,event='missing',effect=33,scope='self',cooldown=0,visual=true},
    {id='remaining',enabled=true,event='remaining',effect=33,scope='self',thresholds={30},cooldown=0,visual=true},
};
local function notices(view,events,now)
    alerts:update(view,events,rules,now,{});
    local fired={};
    for _,notice in ipairs(alerts:drain(now)) do fired[notice.rule_id]=(fired[notice.rule_id] or 0)+1; end;
    return fired;
end;
local live=snapshot(1,{status(33,0,50,3000),status(253,1,nil,0x7FFFFFFF)});
local view,shown,events=frame(live,10);
assert(shown[33] and shown[253],'Both effects show before the message.');
notices(view,events,10);
view,shown,events=frame(live,11);
notices(view,events,11);
local before=find(view,33).key;
view,shown,events=frame(live,21,removal);
local row=find(view,33);
assert(count(events,'removed')==1 and #events==1,'The removal event fires at the message.');
assert(row and row.departing and row.present and row.key==before,'The row stays drawn while its slot still lists it.');
assert(shown[33],'The HUD keeps showing the departing effect.');
local fired=notices(view,events,21);
assert(fired.removed==1 and fired.missing==1 and fired.remaining==nil,'Alerts treat the departing row as gone.');
view,shown,events=frame(live,21.2);
assert(#events==0 and shown[33],'Later frames in the gap keep showing it and stay quiet.');
view,shown,events=frame(live,21.3,removal);
row=find(view,33);
assert(#events==0 and row and row.departing,'A repeated message in the gap does not repeat the removal.');
local gone=snapshot(2,{status(253,0,nil,0x7FFFFFFF)});
view,shown,events=frame(gone,21.4);
assert(not find(view,33) and #events==0,'The slot clearing drops the row without a second removal.');
assert(shown[253]);
assert(next(notices(view,events,21.4))==nil,'No countdown or missing alert follows the departing row.');

-- The server lists a removed effect until its next effect tick, so a newer revision inside the gap
-- can still list it. The row stays departing and shown.
tracker=require('core.tracker').new();
live=snapshot(1,{status(33,0,200,12000),status(253,1,nil,0x7FFFFFFF)});
frame(live,30);
before=find(tracker:view(30,s,live),33).key;
view,shown,events=frame(live,31,removal);
row=find(view,33);
assert(row and row.departing,'The message marks the listed row departing.');
view,shown,events=frame(snapshot(2,{status(33,0,200,12000),status(253,1,nil,0x7FFFFFFF)}),31.3);
row=find(view,33);
assert(row and row.departing and row.key==before and shown[33],
    'A newer revision inside the gap keeps the row departing and shown.');
assert(#events==0,'Keeping the mark is quiet.');

-- A new application in the slot is a new row, not a refresh of the departing one.
tracker=require('core.tracker').new();
live=snapshot(1,{status(33,0,200,12000),status(253,1,nil,0x7FFFFFFF)});
frame(live,40);
before=find(tracker:view(40,s,live),33).key;
frame(live,41,removal);
view,shown,events=frame(snapshot(2,{status(33,0,401,24060),status(253,1,nil,0x7FFFFFFF)}),41.3);
row=find(view,33);
assert(row and row.key~=before and not row.departing and row.instance==1,'A reapplied effect gets a new row.');
assert(#events==1 and events[1].kind=='gain','A reapplied effect is a gain, with no refresh or second removal.');

-- The message and the status update in the same network update.
tracker=require('core.tracker').new();
live=snapshot(1,{status(33,0,200,12000),status(253,1,nil,0x7FFFFFFF)});
frame(live,50);
view,shown,events=frame(snapshot(2,{status(253,0,nil,0x7FFFFFFF)}),51,removal);
assert(not find(view,33) and #events==1 and events[1].kind=='removed','An already cleared slot removes the row at once.');

-- A 0x063 for something else restamped the timer by 60 before the message.
tracker=require('core.tracker').new();
live=snapshot(1,{status(33,0,200,12000),status(253,1,nil,0x7FFFFFFF)});
frame(live,60);
before=find(tracker:view(60,s,live),33).key;
view,shown,events=frame(snapshot(2,{status(33,0,201,12060),status(253,1,nil,0x7FFFFFFF)}),61,removal);
row=find(view,33);
assert(row and row.departing and row.key==before,'A restamped timer is the same effect.');
assert(#events==1 and events[1].kind=='removed','A restamp at the message does not bring the effect back as a gain.');

-- The client showed the effect again before its timer (0x037 first): the slot has no timer yet.
tracker=require('core.tracker').new();
live=snapshot(1,{status(33,0,200,12000),status(253,1,nil,0x7FFFFFFF)});
frame(live,70);
before=find(tracker:view(70,s,live),33).key;
view,shown,events=frame(snapshot(2,{status(41,0,nil,nil),status(33,1,nil,nil),status(253,2,nil,0x7FFFFFFF)}),71,removal);
row=find(view,33);
assert(row and row.departing and row.key==before,'A slot without a timer yet still holds the departing effect.');
assert(count(events,'removed')==1 and count(events,'gain')==1 and #events==2,'Only the new effect is a gain.');
