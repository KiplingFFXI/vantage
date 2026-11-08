local store=require('core.store');
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_effects={{effect=33,slot=0}},party={},entities={}};
package.loaded['core.client']={load=function() end,read=function() return store.copy(snapshot);end};
package.loaded['core.observer']={read=function() return {};end};
local cooldown={key='recast:spell:57',effect=10057,domain='recast',scope='self',kind='spell',group='spell_recasts',
    entity_id=1001,entity_name='Tester',name='Haste',status='server',remaining=40,deadline=41,present=true,instance=1};
local events,reads,projects,held,options={},0,0,true,nil;
local reader={reset=function() end,update=function(_,_,_,value) reads=reads+1;options=value;end,view=function() return {rows=held and {store.copy(cooldown)} or {},version=1};end,
    project=function(_,view,now) projects=projects+1;for _,row in ipairs(view.rows) do if row.domain=='recast' then row.remaining=math.max(0,row.deadline-now);end;end;end,
    drain_events=function() local out=events;events={};return out;end};
package.loaded['core.recasts']={new=function() return reader;end,catalog=function() return {};end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local function command(value) MOCK.fire('command',{command=value});end;
local function frame() MOCK.frame(0.11);end;
MOCK.now=1;app.refresh(1);
assert(#app.state.view.rows==2 and #app.state.party_subjects[1001].effects==1,'Cooldowns render without becoming member buff icons.');
assert(app.state.view.recast_version==1);
assert(options.enabled==false,'Unused cooldown categories perform no native reads.');
local before=reads;MOCK.frame(0.01);assert(reads==before and projects>0,'Frames project cooldowns without additional client sampling.');
command('/vg recasts show');assert(app.state.settings.panels.spell_recasts.enabled and app.state.settings.panels.ability_recasts.enabled and app.state.settings.panels.item_recasts.enabled);
frame();assert(options.spells and options.abilities and options.items);
before=reads;
for _=1,8 do MOCK.now=MOCK.now+0.001;app.refresh(MOCK.now);end;
assert(reads==before,'Packet-driven status refreshes cannot multiply full recast scans.');
command('/vg recasts config');assert(app.state.settings.window.tab=='Recasts');app.state.settings.window.open=false;
command('/vg recasts hide');assert(not app.state.settings.panels.spell_recasts.enabled);
local rule=require('ui.defaults').rule('specific_recast');
rule.domain,rule.effect,rule.event,rule.name,rule.cooldown='recast',10057,'started','My spell reminder',0;
app.state.settings.alerts.rules={rule};held=false;MOCK.now=MOCK.now+0.2;app.refresh(MOCK.now);
held=true;events={store.copy(cooldown)};events[1].kind='started';MOCK.now=MOCK.now+0.2;app.refresh(MOCK.now);
assert(#app.alerts:drain(MOCK.now)==1,'A selected recast start is not baselined by its newly available action name.');
rule.event='ready';MOCK.now=MOCK.now+0.2;app.refresh(MOCK.now);
held=false;events={store.copy(cooldown)};events[1].kind='ready';events[1].remaining=0;
MOCK.now=MOCK.now+0.2;app.refresh(MOCK.now);
local alerts=app.alerts:drain(MOCK.now);
assert(#alerts==1 and alerts[1].message=='Haste recast is ready.','A selected recast ready alert survives removal of the active row.');
MOCK.fire('unload');
assert(#MOCK.commands==0,'Recasts issue no game commands.');
