-- Self effect IDs come from the 0x037 array and each slot's timer only once a 0x063 with the same ID has
-- arrived. A timer showing up, a timer restamped by 60 or a slot shift is never a new application.
package.loaded['ui.icons']={status=function(id) return 1000+id; end};
local hud,defaults,visible=require('ui.hud'),require('ui.defaults'),require('visible_icons');
MOCK.screen={1600,1000};
local s=defaults.make();
s.style.font,s.style.font_size,s.style.scale='Ashita',14,1;
for id,p in pairs(s.panels) do
    p.enabled=id=='self_buffs' or id=='self_debuffs';
    p.show_heading=false;p.mode='icons';p.width=300;p.max_rows=32;
end;
local function status(effect,at,deadline,raw) return {effect=effect,slot=at,deadline=deadline,raw_timer=raw}; end;
local function snapshot(revision,effects)
    return {valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_revision=revision,
        self_effects=effects,party={},entities={}};
end;
local function find(view,effect)
    for _,row in ipairs(view.rows) do if row.effect==effect then return row; end; end;
end;
local tracker=require('core.tracker').new();
local signet=status(253,0,nil,0x7FFFFFFF);
tracker:reconcile(snapshot(1,{signet}),0);
assert(#tracker:drain_events()==0);

-- The 0x037 shows Haste before its 0x063 timer.
tracker:observe({{kind='apply',entity_id=1001,effect=33,source=1001,source_name='Tester',spell=57}},5,snapshot(1,{signet}));
tracker:reconcile(snapshot(2,{signet,status(33,1,nil,nil)}),5.1);
local events=tracker:drain_events();
local view=tracker:view(5.1,s,snapshot(2,{}));
local row=find(view,33);
assert(#events==1 and events[1].kind=='gain' and events[1].effect==33,'The icon alone is the gain.');
assert(row and row.status=='unknown' and row.start==5 and row.mine,'The application is attributed while the timer is unknown.');
local key=row.key;
tracker:reconcile(snapshot(3,{signet,status(33,1,185,10800)}),5.3);
events=tracker:drain_events();
view=tracker:view(5.3,s,snapshot(3,{}));
row=find(view,33);
assert(#events==0,'The timer arriving is not a refresh.');
assert(row and row.key==key and row.instance==1,'The same row and instance get the timer.');
assert(row.mine and row.source==1001 and row.spell==57,'The attribution is kept.');
assert(row.status=='server' and row.total==180 and math.abs(row.remaining-179.7)<1e-9,'The duration is known once the timer arrives.');

-- Each 0x063 rebuilds timers from truncated clocks, so an untouched timer moves by 60.
tracker:reconcile(snapshot(4,{signet,status(33,1,186.9,10860)}),20);
events=tracker:drain_events();
row=find(tracker:view(20,s,snapshot(4,{})),33);
assert(#events==0 and row.instance==1 and row.mine and row.total==180,'A +60 restamp is not a refresh.');
tracker:reconcile(snapshot(5,{signet,status(33,1,185.1,10800)}),21);
events=tracker:drain_events();
row=find(tracker:view(21,s,snapshot(5,{})),33);
assert(#events==0 and row.instance==1 and row.mine,'A -60 restamp is not a refresh.');
assert(row.deadline==185.1 and row.raw_timer==10800,'The restamped timer is still followed.');
tracker:reconcile(snapshot(6,{signet,status(33,1,365,21600)}),185);
events=tracker:drain_events();
row=find(tracker:view(185,s,snapshot(6,{})),33);
assert(#events==1 and events[1].kind=='refresh' and row.instance==2 and row.key==key,'A real recast is still a refresh.');

-- A gain sorted before Haste shifts it to a slot whose 0x063 timer has not come yet.
tracker:reconcile(snapshot(7,{signet,status(41,1,nil,nil),status(33,2,nil,nil)}),186);
events=tracker:drain_events();
view=tracker:view(186,s,snapshot(7,{}));
row=find(view,33);
assert(#events==1 and events[1].kind=='gain' and events[1].effect==41,'Only the new effect is a gain.');
assert(row and row.status=='server' and row.deadline==365 and row.remaining==179 and row.instance==2,
    'A shifted slot keeps its last known timer until the 0x063 comes.');
s.panels.self_buffs.known_only=true;
MOCK.imgui_calls={};
hud.draw(view,s,186,{});
assert(#visible(function(texture) return texture==1033; end)==1,'known_only keeps showing the shifted effect.');
s.panels.self_buffs.known_only=false;
tracker:reconcile(snapshot(8,{signet,status(41,1,486,27000),status(33,2,365,21600)}),186.2);
events=tracker:drain_events();
view=tracker:view(186.2,s,snapshot(8,{}));
assert(#events==0,'Timers arriving after the shift are not refreshes.');
assert(find(view,33).instance==2 and find(view,41).instance==1 and find(view,41).status=='server');

-- Two songs with the same ID cast less than a second apart keep their order in the server's list. A
-- restamp of both by 60 gives the first song the second one's old timer; each keeps its own row.
tracker=require('core.tracker').new();
tracker:observe({{kind='apply',entity_id=1001,effect=198,source=1001,spell=394}},0,snapshot(1,{}));
tracker:reconcile(snapshot(1,{status(198,0,100,6000)}),0);
tracker:observe({{kind='apply',entity_id=1001,effect=198,source=1001,spell=395}},0.8,snapshot(1,{}));
tracker:reconcile(snapshot(2,{status(198,0,100,6000),status(198,1,101,6060)}),0.8);
tracker:drain_events();
local spells={};
for _,held in ipairs(tracker:view(1,s,snapshot(2,{})).rows) do spells[held.slot]=held.spell; end;
tracker:reconcile(snapshot(3,{status(198,0,101,6060),status(198,1,102,6120)}),2);
events=tracker:drain_events();
view=tracker:view(2,s,snapshot(3,{}));
assert(#events==0 and spells[0]==394 and spells[1]==395);
for _,held in ipairs(view.rows) do
    assert(held.spell==spells[held.slot] and held.raw_timer==6060+held.slot*60 and held.instance==1,
        'Each song keeps its own row through the restamp.');
end;
-- A gain sorted first shifts both songs while the same 0x063 restamps them back.
tracker:reconcile(snapshot(4,{status(41,0,300,18000),status(198,1,100,6000),status(198,2,101,6060)}),3);
events=tracker:drain_events();
view=tracker:view(3,s,snapshot(4,{}));
assert(#events==1 and events[1].kind=='gain' and events[1].effect==41,'Shifted and restamped songs are not refreshes.');
for _,held in ipairs(view.rows) do
    if held.effect==198 then
        assert(held.spell==spells[held.slot-1] and held.instance==1,'Each restamped song keeps its own row.');
    end;
end;
