local defaults=require('ui.defaults');
local model=require('core.alerts').new();
local rule=defaults.rule('countdown');
rule.effect,rule.event,rule.thresholds=33,'remaining',{30};
rule.chat,rule.sound=false,'';
local rules={rule};
local enrichments=0;
local function enrich(source)
    enrichments=enrichments+1;
    local value=require('core.store').copy(source);
    value.effect_name='Haste';
    return value;
end
local row={key='self:33',instance=1,entity_id=1001,entity_name='Tester',effect=33,scope='self',status='server',present=true,remaining=40,name='Haste'};
local view={valid=true,rows={row},subjects={{id=1001,name='Tester',scope='self',known=true}},context={}};
local options={enabled=true,enrich=enrich};
model:update(view,{},rules,1,options);
local compiled=model.compiled;
assert(enrichments==1 and #model:drain(1)==0);
for i=1,20 do model:update(view,{},rules,1+i*0.1,options);end
assert(model.compiled==compiled and enrichments==1,'Unchanged rules reuse their enriched definitions and fingerprints');
row.remaining=29;model:update(view,{},rules,3.1,options);
assert(#model:drain(3.1)==1,'Compiled rules still fire on the first threshold crossing');

rule.thresholds[1]=10;
model:update(view,{},rules,3.2,options);
assert(model.compiled~=compiled and enrichments==2 and #model:drain(3.2)==0,'An in-place nested rule edit creates a new quiet baseline');
row.remaining=9;model:update(view,{},rules,3.3,options);
assert(#model:drain(3.3)==1);
compiled=model.compiled;
model:update(view,{},require('core.store').copy(rules),3.5,{enabled=true,enrich=enrich});
assert(model.compiled==compiled and enrichments==2,'Equivalent replacement settings do not rebuild definitions');

options.enabled=false;
model.last_sound=3.5;
model:update(view,{},rules,3.6,options);
assert(not model.ready and next(model.current)==nil and next(model.states)==nil and #model:view(3.6)==0);
assert(model.last_sound==3.5,'Disabling alerts preserves the sound rate limiter');
local unreadable=setmetatable({}, {__index=function() error('Disabled alerts must not scan rows');end});
model:update({valid=true,rows=unreadable},{},rules,3.7,options);
assert(enrichments==2 and model.compiled==nil,'Disabled alerts skip row indexes and compilation');
options.enabled=true;row.remaining=5;
model:update(view,{},rules,3.8,options);
assert(#model:drain(3.8)==0 and model.ready,'Re-enabling alerts baselines elapsed thresholds instead of replaying them');
rule.thresholds[1]=2;model:update(view,{},rules,3.9,options);
row.remaining=1;model:update(view,{},rules,4,options);assert(#model:drain(4)==1);

local missing=defaults.rule('missing effect');
missing.event,missing.effect,missing.chat,missing.sound='missing',33,false,'';
rules={missing};row.remaining=40;
model:update(view,{},rules,4.1,options);
view.rows={};model:update(view,{},rules,4.2,options);
local notices=model:drain(4.2);
assert(#notices==1 and notices[1].message=='Haste is missing on you.','Compiled missing rules retain their label and presence checks');
model:update(view,{},rules,4.3,{enabled=true,muted=true,enrich=enrich});
assert(not model.ready and #model:drain(4.3)==0);
model:update(view,{},rules,4.4,options);assert(#model:drain(4.4)==0,'Unmuting retains a quiet baseline');

