local counts,spells,abilities,equipped,items,info={},{},{},{},{},{};
local invalid,throwing={},{};
local function counted(key) counts[key]=(counts[key] or 0)+1; end;
local manager={
    GetSpellTimer=function(_,id) counted('spells');counts.spell_min=math.min(counts.spell_min or id,id);counts.spell_max=math.max(counts.spell_max or id,id);if throwing[id] then error('unreadable');end;if invalid[id]~=nil then return invalid[id];end;return spells[id] or 0;end,
    GetAbilityTimerId=function(_,slot) counted('ids');counts.slot_min=math.min(counts.slot_min or slot,slot);counts.slot_max=math.max(counts.slot_max or slot,slot);return abilities[slot] and abilities[slot].id or 0;end,
    GetAbilityTimer=function(_,slot) counted('abilities');return abilities[slot] and abilities[slot].timer or 0;end,
};
local inventory={
    GetEquippedItem=function(_,slot) counted('equipment');counts.equipment_min=math.min(counts.equipment_min or slot,slot);counts.equipment_max=math.max(counts.equipment_max or slot,slot);return {Index=equipped[slot] or 0};end,
    GetContainerItem=function(_,container,index) counted('items');return items[container*256+index];end,
};
local spell_resources={[2]={Name={[1]='Cure'}},[4]={Name={[1]='Curaga'}},[1023]={Name={[1]='Last spell'}}};
local ability_resources={
    [512]={Name={[1]='Provoke'},RecastTimerId=5},
    [513]={Name={[1]='Shared action'},RecastTimerId=5},
    [514]={Name={[1]='Stratagem'},RecastTimerId=231},
};
local item_resource={Name={[1]='Enchanted ring'},Type=5,MaxCharges=10,CastDelay=30,RecastDelay=1800};
local resources={
    GetSpellById=function(_,id) counted('spell_names');return spell_resources[id];end,
    GetAbilityById=function(_,id) counted('ability_names');counts.name_min=math.min(counts.name_min or id,id);counts.name_max=math.max(counts.name_max or id,id);return ability_resources[id];end,
    GetAbilityByTimerId=function() counted('timer_names');return nil;end,
    GetItemById=function(_,id) counted('item_names');return id==17570 and item_resource or nil;end,
};
local memory={GetRecast=function() return manager;end,GetInventory=function() return inventory;end};
AshitaCore.GetMemoryManager=function() return memory;end;
AshitaCore.GetResourceManager=function() return resources;end;
package.preload['ffxi.itemdata']=function() return {parse_timer_info=function(item,resource,is_equipped)
    counted('parse');assert(is_equipped==true and resource==item_resource);
    if info[item.Index]=='error' then error('game clock unreadable');end;
    return info[item.Index] or {};
end};end;
local recasts=require('core.recasts');
local model=recasts.new();
local snapshot={valid=true,id=1001,zone=230,job=1,name='Aster'};
local now=100;
local function update(delta) now=now+(delta or 0.1);model:update(snapshot,now);return model:view(now);end;
local function get(view,kind,id)
    for _,row in ipairs(view.rows) do if row.kind==kind and row.recast_id==id then return row;end;end;
end;
local function empty_events() assert(#model:drain_events()==0);end;
spells[2]=600;spells[1023]=120;
abilities[0]={id=0,timer=7200};abilities[3]={id=5,timer=1800};abilities[7]={id=5,timer=1200};
abilities[4]={id=231,timer=14400};
equipped[13]=2050;items[2050]={Id=17570,Index=2050,Extra=string.char(1)..string.rep('\0',11)};
info[2050]={use_delay=30,remaining_charges=7};
local view=update();
assert(#view.rows==6 and view.valid,'Baseline contains active spells, unique ability timers and equipped item delays');
assert(view.capabilities.reads.GetSpellTimer==3 and view.capabilities.reads.GetAbilityTimer==31 and view.capabilities.reads.GetAbilityTimerId==31,'Only the spells the client names are read');
assert(view.capabilities.reads.equipment==16 and view.capabilities.reads.inventory==1 and view.capabilities.item_timers);
assert(counts.spell_min==2 and counts.spell_max==1023 and counts.slot_min==0 and counts.slot_max==30);
assert(counts.equipment_min==0 and counts.equipment_max==15 and counts.name_min==0 and counts.name_max==2047);
assert(get(view,'spell',2).remaining==10 and get(view,'spell',1023).remaining==2,'Native clocks use60frames persecond, including finalvalidspellslot');
assert(get(view,'ability',5).remaining==30 and get(view,'ability',5).shared,'Duplicate slots become one sharedtimer with the longest nativeclock');
assert(get(view,'ability',5).name=='Provoke / Shared action (shared)');
assert(get(view,'ability',0).name=='Job special (shared)' and get(view,'ability',0).effect==20000);
assert(math.abs(get(view,'ability',231).remaining-240)<0.000001 and get(view,'ability',231).charges==nil,'No retail charge formula alters the native timer');
assert(get(view,'item',17570).charges==7 and get(view,'item',17570).effect==47570);
for _,row in ipairs(view.rows) do
    assert(row.domain=='recast' and row.scope=='self' and row.entity_id==1001 and row.status=='server');
    assert(row.total==nil and row.start==nil,'A timer present atload has no inferred full duration');
end;
empty_events();
local reads=counts.spells;local names_read=counts.ability_names;local spell_names_read=counts.spell_names;
model:project(view,now+0.5);
assert(get(view,'spell',2).remaining==9.5 and counts.spells==reads,'Perframe projection performs no client reads');
model:project(view,now+11);
assert(get(view,'spell',2).remaining==nil and get(view,'spell',2).status=='unknown' and get(view,'spell',2).present,'Deadline expiry waits for client confirmation');
empty_events();
spells[2]=0;abilities[3].timer=0;abilities[7].timer=0;info[2050].use_delay=-1;
view=update();local events=model:drain_events();
assert(#events==3 and not get(view,'spell',2) and not get(view,'ability',5) and not get(view,'item',17570));
for _,event in ipairs(events) do assert(event.kind=='ready' and event.domain=='recast' and event.remaining==0 and not event.present and event.category~=nil);end;
spells[2]=900;abilities[3].timer=1200;info[2050].use_delay=45;
view=update();events=model:drain_events();
assert(#events==3 and get(view,'spell',2).total==15 and get(view,'spell',2).start==now,'An observedready-to-active edge records its horizon');
for _,event in ipairs(events) do assert(event.kind=='started' and event.domain=='recast' and event.present);end;
local instance=get(view,'spell',2).instance;
spells[2]=894;update();empty_events();assert(counts.ability_names==names_read,'Ability metadata is indexed once');
assert(counts.spell_names==spell_names_read,'The spells to read are found once');
spells[2]=1500;view=update();events=model:drain_events();
assert(#events==1 and events[1].kind=='started' and get(view,'spell',2).instance~=instance and get(view,'spell',2).total==25);
-- Partial read failures, disappearing slots and depleted gear do not meanready.
invalid[2]=0/0;abilities[3],abilities[7]=nil,nil;info[2050].remaining_charges=0;
view=update();empty_events();
assert(get(view,'spell',2).status=='unknown' and get(view,'ability',5).status=='unknown');
assert(get(view,'item',17570).status=='unknown','Exhausted charges are not a readiness confirmation');
invalid[2]=nil;spells[2]=0;abilities[3]={id=5,timer=0};info[2050].remaining_charges=7;info[2050].use_delay=0;
update();empty_events();
assert(not get(model:view(now),'spell',2),'Recovery tozero after missing data isquiet');
-- Item instances with the same id remain distinct by client inventory location.
equipped[14]=2051;items[2051]={Id=17570,Index=2051,Extra=items[2050].Extra};
info[2050]={use_delay=60,remaining_charges=255};info[2051]={use_delay=90,remaining_charges=2};
view=update();events=model:drain_events();
local twins={};for _,row in ipairs(view.rows) do if row.kind=='item' then twins[#twins+1]=row;end;end;
assert(#twins==2 and twins[1].effect==twins[2].effect and twins[1].key~=twins[2].key);
assert(#events==1,'Only the already observed ready item emitsstarted; a newly equipped item isbaseline');
equipped[13],equipped[14]=0,0;view=update();empty_events();
assert(get(view,'item',17570).status=='unknown','Unequipping an item does not emitready');
-- Invalid native values never become fabricated countdowns.
for _,bad in ipairs({-1,1.5,math.huge,2147483648,'600'}) do
    invalid[4]=bad;view=update();assert(not get(view,'spell',4));empty_events();
end;
invalid[4]=nil;throwing[4]=true;view=update();assert(not get(view,'spell',4));throwing[4]=nil;
-- Session changes and interrupted sampling create quiet fresh baselines.
spells[2]=600;view=update();model:drain_events();
for _,axis in ipairs({'zone','job','id'}) do
    snapshot[axis]=snapshot[axis]+1;spells[2]=0;update();empty_events();
    spells[2]=600;view=update();assert(#model:drain_events()==1);
end;
spells[2]=0;update(3);empty_events();
spells[2]=600;view=update();model:drain_events();now=now-5;model:update(snapshot,now);empty_events();
assert(get(model:view(now),'spell',2).total==nil);
snapshot.valid=false;model:update(snapshot,now);assert(not model:view(now).valid and #model:view(now).rows==0);empty_events();
snapshot.valid=true;spells[2]=0;update();empty_events();
-- Catalogs cache resource walks and retain domain-specific numeric identities.
local catalog=recasts.catalog('spell');local count=counts.spell_names;
assert(catalog==recasts.catalog('spell') and counts.spell_names==count);
local seen={};for _,record in ipairs(catalog) do seen[record.id]=record.name;end;
assert(seen[10002]=='Cure' and seen[11023]=='Last spell');
catalog=recasts.catalog('ability');count=counts.ability_names;
assert(catalog==recasts.catalog('ability') and counts.ability_names==count and #catalog==3);
local item_catalog=recasts.catalog('item');assert(#item_catalog==1 and item_catalog[1].id==47570 and item_catalog==recasts.catalog('item'));
local all=recasts.catalog();assert(all==recasts.catalog() and #all==#catalog+#recasts.catalog('spell')+#item_catalog);
-- Disabled sampling and projection perform zero additional SDK reads.
local last=counts.spells;model:update(snapshot,now,{enabled=false});assert(counts.spells==last and #model:view(now).rows==0);
model:update(snapshot,now,{spells=false,abilities=false,items=false});assert(counts.spells==last and #model:view(now).rows==0);
-- A changed native identity during the scan invalidates the entire sample.
local native_id,native_zone,native_job=snapshot.id,snapshot.zone,snapshot.job;
memory.GetParty=function() return {GetMemberServerId=function() return native_id;end,GetMemberZone=function() return native_zone;end};end;
memory.GetPlayer=function() return {GetMainJob=function() return native_job;end};end;
spells[2]=600;update();model:drain_events();
local read_spell=manager.GetSpellTimer;
manager.GetSpellTimer=function(self,id) local value=read_spell(self,id);if id==1023 then native_id=native_id+1;end;return value;end;
spells[2]=0;view=update();empty_events();assert(not view.valid and #view.rows==0,'No false ready event survives a character change during sampling');
manager.GetSpellTimer=read_spell;native_id=snapshot.id;spells[2]=600;view=update();empty_events();assert(get(view,'spell',2).total==nil);
native_job=native_job+1;view=update();assert(not view.valid);empty_events();
native_job=snapshot.job;
-- Parser failures and malformed equipment records remain unavailable, neverready.
equipped[13]=2050;info[2050]={use_delay=45,remaining_charges=7};update();model:drain_events();
info[2050]='error';view=update();empty_events();assert(get(view,'item',17570).status=='unknown');
info[2050]={use_delay=0,remaining_charges=7};update();empty_events();
local parsed=counts.parse;items[2050].Extra='short';update();assert(counts.parse==parsed);
items[2050].Extra=string.char(2)..string.rep('\0',11);update();assert(counts.parse==parsed);
items[2050].Extra=string.char(1)..string.rep('\0',11);item_resource.CastDelay=0;update();assert(counts.parse==parsed);
item_resource.CastDelay=30;info[2050]={use_delay=math.huge,remaining_charges=7};update();empty_events();
-- Unreadable observations expire quietly rather than accumulating forever.
spells[2]=600;update();model:drain_events();throwing[2]=true;
for _=1,110 do update();empty_events();end;
assert(not get(model:view(now),'spell',2));throwing[2]=nil;
abilities[3]={id=5,timer=1200};update();model:drain_events();
abilities[3].timer=0;abilities[30]={id=-1,timer=0};view=update();empty_events();
assert(get(view,'ability',5).status=='unknown' and not view.capabilities.ability_complete,'A partial ability snapshot cannot confirm duplicate-slot completion');
abilities[30]=nil;update();empty_events();
