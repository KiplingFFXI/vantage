-- A known_only panel keeps showing a self effect whose server timer just ran out until the server clears its
-- slot, for the whole gap between the timer and the status update.
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
    p.show_heading=false;p.mode='icons';p.width=300;p.max_rows=32;p.known_only=true;
end;
local function snapshot(revision,effects)
    memory[container+0x40]=#effects;
    for index,row in ipairs(effects) do memory[container+0x290+(index-1)*2]=row.effect; end;
    return {valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_revision=revision,
        self_effects=effects,party={},entities={}};
end;
local function find(view,effect)
    for _,row in ipairs(view.rows) do if row.effect==effect then return row; end; end;
end;
local tracker=require('core.tracker').new();
local live=snapshot(1,{{effect=33,slot=0,deadline=100,raw_timer=6000},{effect=4,slot=1,deadline=160,raw_timer=9600}});
tracker:reconcile(live,90);
-- The effects whose icons the self panels show in full this frame.
local function draw(view,now)
    MOCK.imgui_calls={};
    hud.draw(view,s,now,{});
    local shown={};
    for _,icon in ipairs(visible(function(texture) return texture>1000; end)) do shown[icon.texture-1000]=true; end;
    return shown;
end;
local view=tracker:view(99,s,live);
local shown=draw(view,99);
assert(shown[33] and shown[4],'Both timers are known before expiry.');

-- A full refresh with no new packet after the timer ran out.
tracker:reconcile(live,100.5);
view=tracker:view(100.5,s,live);
local row=find(view,33);
assert(row and row.present and row.status=='server' and row.remaining==0,'The timer stays known at zero.');
shown=draw(view,100.5);
assert(shown[33],'known_only keeps the expired effect while its slot still lists it.');
assert(#tracker:drain_events()==0,'Timer expiry is not a removal.');

-- Frames between refreshes only project the countdown.
tracker=require('core.tracker').new();
tracker:reconcile(live,90);
view=tracker:view(99.9,s,live);
tracker:project(view,100.6);
row=find(view,33);
assert(row and row.status=='server' and row.remaining==0,'Projection keeps the timer known at zero.');
shown=draw(view,100.6);
assert(shown[33],'A projected frame keeps showing the expired effect.');

-- The status update clears the slot: an ordinary wear-off.
live=snapshot(2,{{effect=4,slot=0,deadline=160,raw_timer=9600}});
tracker:reconcile(live,101.2);
local events=tracker:drain_events();
view=tracker:view(101.2,s,live);
assert(not find(view,33) and #events==1 and events[1].kind=='removed' and events[1].effect==33,'The slot clearing reports the wear-off once.');
shown=draw(view,101.2);
assert(shown[4]);

-- Estimated timers on others still expire to unknown.
tracker:observe({{kind='apply',entity_id=500,effect=2,source=1001,duration=10}},101.2,live);
view=tracker:view(112,s,live);
row=find(view,2);
assert(row and row.status=='unknown' and row.deadline==nil and row.remaining==nil,'An estimate that ran out is unknown.');

-- Another effect's slot clears first and moves the expired one down a slot. The client has no deadline
-- for a timer that already ran out under a new slot, but it is the same timer.
tracker=require('core.tracker').new();
live=snapshot(3,{{effect=40,slot=0,deadline=100,raw_timer=6000},{effect=42,slot=1,deadline=101,raw_timer=6060}});
tracker:reconcile(live,90);
tracker:reconcile(live,101.5);
live=snapshot(4,{{effect=42,slot=0,raw_timer=6060}});
tracker:reconcile(live,101.7);
view=tracker:view(101.7,s,live);
row=find(view,42);
assert(row and row.present and row.status=='server' and row.remaining==0,'A shifted expired timer stays known at zero.');
shown=draw(view,101.7);
assert(shown[42],'known_only keeps showing it for the rest of the gap.');

-- The same 0x063 restamps the expired timer by 60.
tracker=require('core.tracker').new();
live=snapshot(5,{{effect=42,slot=0,deadline=753,raw_timer=45180}});
tracker:reconcile(live,700);
live=snapshot(6,{{effect=42,slot=0,raw_timer=45120}});
tracker:reconcile(live,753.2);
view=tracker:view(753.2,s,live);
row=find(view,42);
assert(row and row.status=='server' and row.remaining==0 and row.raw_timer==45120,'A restamp after the timer ran out keeps it known.');
shown=draw(view,753.2);
assert(shown[42] and #tracker:drain_events()==0);
-- A different value with no deadline is not the same timer.
live=snapshot(7,{{effect=42,slot=0,raw_timer=0x7FFFFFFF}});
tracker:reconcile(live,753.4);
row=find(tracker:view(753.4,s,live),42);
assert(row and row.status=='unknown' and row.deadline==nil,'A timer that changed is not kept.');
