-- Effects like Signet survive a KO. While KO the self rows keep following the raw slots, quietly, so the
-- self panels keep showing them.
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
local function snapshot(revision,dead,effects)
    memory[container+0x40]=#effects;
    for index,row in ipairs(effects) do memory[container+0x290+(index-1)*2]=row.effect; end;
    return {valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_revision=revision,dead=dead,
        self_effects=effects,party={},entities={}};
end;
local tracker=require('core.tracker').new();
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
local signet=status(253,1,nil,0x7FFFFFFF);
local view,shown,events=frame(snapshot(1,false,{status(40,0,1800,108000),signet}),1);
assert(#events==0);
local key=find(view,253).key;

-- The KO packet lands before the status update that wipes Protect.
view,shown,events=frame(snapshot(1,true,{status(40,0,1800,108000),signet}),2);
assert(find(view,40) and find(view,40).present and find(view,253) and find(view,253).present,'While KO the listed self effects stay.');
assert(shown[40] and shown[253],'The HUD keeps showing them.');
assert(#events==0 and not view.self_known,'A KO is quiet and the self list is not claimed complete.');
view,shown,events=frame(snapshot(2,true,{status(253,0,nil,0x7FFFFFFF)}),2.4);
assert(not find(view,40) and #events==0,'The KO wiping Protect drops its row without a removal event.');
assert(find(view,253) and find(view,253).key==key,'Signet keeps its row through the KO.');
assert(shown[253],'Signet stays shown for the whole KO.');
view,shown,events=frame(snapshot(2,true,{status(253,0,nil,0x7FFFFFFF)}),3,
    {{kind='remove',entity_id=1001,effect=253,scope='self'}});
assert(find(view,253) and #events==0,'Self messages stay ignored while KO; the slots decide.');
view,shown,events=frame(snapshot(3,true,{status(253,0,nil,0x7FFFFFFF),status(254,1,nil,0x7FFFFFFF)}),5);
assert(find(view,254) and shown[254] and #events==0,'An effect gained while KO is drawn without a gain event.');

-- Raise: the first snapshot is quiet, then the baseline is live again.
view,shown,events=frame(snapshot(4,false,{status(1,0,600,36000),status(253,1,nil,0x7FFFFFFF)}),10);
assert(#events==0,'The first snapshot after a raise stays quiet.');
assert(find(view,253) and find(view,253).key==key and find(view,1));
view,shown,events=frame(snapshot(5,false,{status(253,0,nil,0x7FFFFFFF)}),11);
assert(#events==1 and events[1].kind=='removed' and events[1].effect==1,'After the raise removals are reported again.');

-- The KO and the status update that wipes Protect arrive together.
tracker=require('core.tracker').new();
frame(snapshot(1,false,{status(40,0,1800,108000),signet}),20);
view,shown,events=frame(snapshot(2,true,{status(253,0,nil,0x7FFFFFFF)}),21);
assert(#events==0 and not find(view,40),'The first KO snapshot drops wiped effects quietly.');
assert(find(view,253));
