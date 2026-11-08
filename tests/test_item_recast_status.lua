-- Item recasts load Ashita's item data library on the first equipped item with charges. On a client where it
-- can't load (its time library misses a pattern), item recasts are off, /vg report says so in a plain line,
-- and spell and ability recasts go on.
local spells,abilities={[2]=600},{[3]={id=5,timer=1800}};
local manager={
    GetSpellTimer=function(_,id) return spells[id] or 0;end,
    GetAbilityTimerId=function(_,slot) return abilities[slot] and abilities[slot].id or 0;end,
    GetAbilityTimer=function(_,slot) return abilities[slot] and abilities[slot].timer or 0;end,
};
local items={[2050]={Id=17570,Index=2050,Extra=string.char(1)..string.rep('\0',11)}};
local inventory={
    GetEquippedItem=function(_,slot) return {Index=slot==13 and 2050 or 0};end,
    GetContainerItem=function(_,container,index) return items[container*256+index];end,
};
local item_resource={Name={[1]='Enchanted ring'},Type=5,MaxCharges=10,CastDelay=30,RecastDelay=1800};
local resources={
    GetSpellById=function(_,id) return id==2 and {Name={[1]='Cure'}} or nil;end,
    GetAbilityById=function(_,id) return id==512 and {Name={[1]='Provoke'},RecastTimerId=5} or nil;end,
    GetAbilityByTimerId=function() return nil;end,
    GetItemById=function(_,id) return id==17570 and item_resource or nil;end,
};
AshitaCore.GetMemoryManager=function() return {GetRecast=function() return manager;end,GetInventory=function() return inventory;end};end;
AshitaCore.GetResourceManager=function() return resources;end;
local tries=0;
package.preload['ffxi.itemdata']=function()
    tries=tries+1;
    error('[lib.time] Error: Failed to locate required pointer(s).');
end;
local recasts=require('core.recasts');
local status=recasts.item_status();
assert(status.available==nil and status.reason:find('first equipped item',1,true),'Nothing is loaded before an item needs it.');
local model=recasts.new();
local snapshot={valid=true,id=1001,zone=230,job=1,name='Aster'};
local now=100;
local function update() now=now+0.2;model:update(snapshot,now);return model:view(now);end;
local view=update();
local kinds={};
for _,row in ipairs(view.rows) do kinds[row.kind]=(kinds[row.kind] or 0)+1; end;
assert(kinds.spell==1 and kinds.ability==1 and not kinds.item,'Spell and ability recasts go on without item recasts.');
assert(view.valid and view.capabilities.item_timers==false,'The view says item timers are off.');
status=recasts.item_status();
assert(status.available==false and status.problem:find('Failed to locate',1,true)
    and status.reason=='Item recasts are off because the Ashita item data library could not load on this client.');
update();update();
assert(tries==1,'The library is tried once per load, not every update.');
assert(not status.reason:find('?',1,true) and not status.reason:lower():find('unknown',1,true));
return 'Item recasts turn off alone when Ashita\'s item data library cannot load';
