local counts,known,pets,throws={},{},{},{};
local ready,main,sub,level,sublevel=false,1,2,75,37;
local spell_data={
    [2]={Name={[1]='Cure'},ListIconNQ=17,ListIconHQ=0},
    [3]={Name={[1]='Cure II'},ListIconNQ=4,ListIconHQ=1008},
    [4]={Name={[1]='Cure III'},ListIconNQ=0,ListIconHQ=65535},
    [5]={Name={[1]='Malformed'},ListIconNQ=-1,ListIconHQ=0/0},
};
local ability_data={
    [4]={Name={[1]='Weapon skill'},RecastTimerId=0,ListIconId=900,Element=1},
    [528]={Name={[1]='Mighty Strikes'},Type=1,RecastTimerId=0,ListIconId=401,Element=1},
    [529]={Name={[1]='Hundred Fists'},Type=1,RecastTimerId=0,ListIconId=402,Element=2},
    [530]={Name={[1]='Pet-only command'},Type=6,RecastTimerId=0,ListIconId=403,Element=3},
    [531]={Name={[1]='Unverified action type'},RecastTimerId=0,ListIconId=404,Element=4},
    [547]={Name={[1]='Provoke'},RecastTimerId=5,ListIconId=22,Element=0},
    [600]={Name={[1]='Alternate action'},RecastTimerId=5,ListIconId=23,Element=1},
    [611]={Name={[1]='Fallback A'},RecastTimerId=10,ListIconId=65535,Element=3},
    [612]={Name={[1]='Fallback B'},RecastTimerId=10,ListIconId=65535,Element=4},
    [613]={Name={[1]='Common A'},RecastTimerId=11,ListIconId=18,Element=3},
    [614]={Name={[1]='Common B'},RecastTimerId=11,ListIconId=18,Element=4},
    [615]={Name={[1]='Unknown icon'},RecastTimerId=12,ListIconId=65536,Element=256},
    [616]={Name={[1]='Pet action'},RecastTimerId=13,ListIconId=1032,Element=0},
    [617]={Name={[1]='Zero shape'},RecastTimerId=14,ListIconId=0,Element=0},
    [1536]={Name={[1]='Trait'},RecastTimerId=0,ListIconId=901,Element=1},
};
local function count(key) counts[key]=(counts[key] or 0)+1; end;
local resources={
    GetSpellById=function(_,id) count('spells');return spell_data[id];end,
    GetAbilityById=function(_,id) count('abilities');return ability_data[id];end,
    GetAbilityByTimerId=function(_,id)
        count('fallback');
        if id==15 then return {Id=618,Name={[1]='Late resource'},RecastTimerId=15,ListIconId=55,Element=5};end;
        if id==16 then return {Id=619,Name={[1]='Wrong timer'},RecastTimerId=17,ListIconId=56,Element=5};end;
    end,
};
local player={
    GetMainJob=function() return main;end,GetSubJob=function() return sub;end,
    GetMainJobLevel=function() return level;end,GetSubJobLevel=function() return sublevel;end,
    HasAbilityData=function() count('readiness');return ready;end,
    HasAbility=function(_,id) count('known');if throws[id] then error('unreadable');end;return known[id]==true;end,
    HasPetCommand=function(_,id) count('pets');return pets[id]==true;end,
};
local active={0,5,10,11,12,13,14,15,16};
local ticks=600;
local late_spell=false;
local manager={
    GetSpellTimer=function(_,id) count('timers');return (id>=2 and id<=5 or late_spell and id==6) and ticks or 0;end,
    GetAbilityTimerId=function(_,slot) count('timers');return active[slot+1] or 255;end,
    GetAbilityTimer=function(_,slot) count('timers');return active[slot+1] and ticks or 0;end,
};
local memory={GetPlayer=function() return player;end,GetRecast=function() return manager;end};
AshitaCore.GetMemoryManager=function() return memory;end;
AshitaCore.GetResourceManager=function() count('managers');return resources;end;
local recasts=require('core.recasts');
local function preview(kind,id) return recasts.preview_icon(kind,id);end;

-- Preview identities are resource IDs, never encoded alert IDs or recast-group IDs.
local icon=preview('spell',2);
assert(icon.spell_id==2 and icon.list_icon_hq==0 and icon.list_icon_nq==17,'Shape zero is a valid native icon');
assert(preview('spell',3).list_icon_hq==1008,'Secondary atlas indices remain raw for the renderer');
assert(preview('spell',4).list_icon_hq==65535 and preview('spell',4).list_icon_nq==0,'FFFF preserves the NQ fallback pair');
assert(preview('spell',5).list_icon_hq==nil and preview('spell',5).list_icon_nq==nil);
icon=preview('ability',547);
assert(icon.ability_id==547 and icon.name=='Provoke' and icon.list_icon_id==22 and icon.list_icon_hq==22 and icon.list_icon_nq==0);
assert(preview('ability',615).list_icon_id==nil and preview('ability',615).ability_element==nil);
assert(preview('item',15762).item_id==15762 and preview('item',65534).item_id==65534);
for _,bad in ipairs({-1,1.5,65535,math.huge,'2'}) do assert(preview('item',bad)==nil);end;
assert(preview('spell',1024)==nil and preview('ability',2048)==nil and preview('status',2)==nil);
local saved={};for key,value in pairs(counts) do saved[key]=value;end;
for _=1,100 do assert(preview('ability',547)==icon);preview('spell',2);preview('item',15762);end;
for key,value in pairs(counts) do assert(saved[key]==value,'Stable metadata does not re-read resources');end;
assert(counts.timers==nil and counts.known==nil and counts.readiness==nil,'Preview never inspects live player or cooldown state');
local clock=os.clock;local clock_value=20;os.clock=function() return clock_value;end;
local absent=preview('spell',9);local calls=counts.spells;
spell_data[9]={Name={[1]='Recovered spell'},ListIconHQ=91,ListIconNQ=9};
for _=1,20 do assert(preview('spell',9)==absent);end;
assert(counts.spells==calls,'Unavailable metadata is negatively cached');
clock_value=21.1;assert(preview('spell',9).list_icon_hq==91 and counts.spells==calls+1);
os.clock=clock;

local model=recasts.new();local now=100;
local snapshot={valid=true,id=999,job=1,zone=230,name='Aster'};
local function update(delta)
    now=now+(delta or 0.1);model:update(snapshot,now,{items=false});return model:view(now);
end;
local function row(view,kind,id)
    for _,value in ipairs(view.rows) do if value.kind==kind and value.recast_id==id then return value;end;end;
end;
local view=update();
local special=row(view,'ability',0);
assert(special.name=='Job special (shared)' and special.ability_id==nil and special.list_icon_hq==nil);
local shared=row(view,'ability',5);
assert(shared.ability_id==nil and #shared.ability_ids==0 and #shared.action_icons==2 and shared.icon_ambiguous);
assert(shared.action_icons[1].ability_id==547 and shared.action_icons[2].ability_id==600);
assert(shared.list_icon_hq==nil and shared.list_icon_ids[1]==22 and shared.list_icon_ids[2]==23);
assert(row(view,'ability',10).icon_ambiguous and row(view,'ability',10).list_icon_hq==nil,'Same FFFF needs matching NQ selectors');
assert(not row(view,'ability',11).icon_ambiguous and row(view,'ability',11).list_icon_hq==18,'Different NQ does not invalidate a common HQ icon');
assert(row(view,'ability',12).icon_ambiguous and row(view,'ability',12).list_icon_hq==nil);
assert(row(view,'ability',13).list_icon_hq==1032 and row(view,'ability',14).list_icon_hq==0);
assert(row(view,'ability',15).action_icons[1].ability_id==618 and row(view,'ability',15).list_icon_hq==55);
assert(row(view,'ability',16).list_icon_hq==nil,'Mismatched fallback timer cannot lend another action icon');
assert(row(view,'spell',2).spell_id==2 and row(view,'spell',2).list_icon_hq==0);
assert(counts.known==nil and counts.pets==nil,'Incomplete ability data never produces known-action identities');
assert(#model:drain_events()==0);
local old_instance,old_start=shared.instance,shared.start;
local indexed_reads=counts.abilities;

-- The native known-action set identifies a special without a hardcoded job map.
ready=true;known[528]=true;known[530]=true;known[531]=true;known[547]=true;pets[530]=true;pets[616]=true;
known[611]=true;known[613]=true;known[614]=true;known[618]=true;
view=update();special=row(view,'ability',0);shared=row(view,'ability',5);
assert(special.ability_id==528 and special.name=='Mighty Strikes (shared)' and special.list_icon_hq==401);
assert(#special.action_icons==1 and #special.ability_ids==1,'Pet-only, weapon-skill and trait identities cannot replace the job special');
assert(special.action_icons[1].ability_id~=530 and special.action_icons[1].ability_id~=531,'Timer zero requires verified player-action type even when another known bit is set');
assert(shared.ability_id==547 and #shared.action_icons==1 and shared.list_icon_hq==22 and shared.shared);
assert(shared.instance==old_instance and shared.start==old_start and shared.total==nil,'Metadata arrival does not restart a cooldown');
assert(row(view,'ability',10).list_icon_hq==65535 and row(view,'ability',10).list_icon_nq==3);
assert(#row(view,'ability',11).ability_ids==2 and row(view,'ability',11).ability_id==nil and row(view,'ability',11).list_icon_hq==18);
assert(row(view,'ability',13).ability_id==616 and row(view,'ability',13).list_icon_hq==1032,'Known pet actions resolve on their actual recast group');
assert(row(view,'ability',15).ability_id==618);
assert(#model:drain_events()==0 and counts.abilities==indexed_reads);
local probes=counts.known;local action_icons=shared.action_icons;
for _=1,5 do view=update();end;
assert(counts.known==probes and row(view,'ability',5).action_icons==action_icons,'Known-action probing is cached across refreshes');
local no_reads={};for key,value in pairs(counts) do no_reads[key]=value;end;
for _=1,120 do model:project(view,now+0.01);model:view(now+0.01);end;
for key,value in pairs(counts) do assert(value==no_reads[key],'Rendering projection performs no SDK reads');end;
known[547]=false;known[600]=true;view=update(1.1);
assert(row(view,'ability',5).ability_id==600 and row(view,'ability',5).list_icon_hq==23 and counts.abilities==indexed_reads);
assert(#model:drain_events()==0,'Same-job known data changes quietly at the bounded refresh');

-- Changes to job data invalidate the identity cache immediately.
known[528]=false;known[529]=true;main=2;snapshot.job=2;view=update();
assert(row(view,'ability',0).ability_id==529 and row(view,'ability',0).list_icon_hq==402);
assert(#model:drain_events()==0 and row(view,'ability',0).total==nil);
known[547]=true;known[600]=false;sub=3;view=update();assert(row(view,'ability',5).ability_id==547);
known[547]=false;known[600]=true;level=76;view=update();assert(row(view,'ability',5).ability_id==600);
known[547]=true;known[600]=false;sublevel=38;view=update();assert(row(view,'ability',5).ability_id==547);
ready=false;view=update();assert(row(view,'ability',5).ability_id==nil and row(view,'ability',5).icon_ambiguous);
assert(row(view,'ability',0).ability_id==nil and row(view,'ability',0).list_icon_hq==nil);
ready=true;throws[600]=true;view=update();assert(row(view,'ability',5).ability_id==nil and row(view,'ability',5).icon_source=='resource_aliases','Partial known data cannot falsely select one action');
throws[600]=nil;known[600]=true;view=update(1.1);
assert(row(view,'ability',5).ability_id==nil and #row(view,'ability',5).ability_ids==2 and row(view,'ability',5).icon_ambiguous);
known[529]=false;sublevel=39;view=update();
assert(row(view,'ability',0).name=='Job special (shared)' and row(view,'ability',0).list_icon_hq==nil,'A pet-only command cannot become the player special when no special is verified');
assert(#model:drain_events()==0);

-- Catalog identities stay stable and icon fields survive event snapshots.
local catalog=recasts.catalog('spell');local found;
for _,value in ipairs(catalog) do if value.recast_id==3 then found=value;end;end;
assert(found and found.spell_id==3 and found.list_icon_hq==1008);
assert(catalog==recasts.catalog('spell'));
local ability_catalog=recasts.catalog('ability');assert(ability_catalog==recasts.catalog('ability'));
ticks=0;update();local events=model:drain_events();assert(#events==13);
for _,event in ipairs(events) do
    assert(event.kind=='ready' and event.domain=='recast');
    if event.category=='spell' then assert(event.spell_id==event.recast_id);end;
    if event.recast_id==5 and event.category=='ability' then assert(#event.action_icons==2 and event.action_icons[1].ability_id==547);end;
end;
local read_count=counts.timers;model:update(snapshot,now,{enabled=false});assert(counts.timers==read_count and #model:view(now).rows==0);

-- A spell the client has no name for is never read and makes no row, whatever its timer holds. The spells to read are
-- found once, not on each sample.
late_spell=true;ticks=600;
local read_ids,read_spell,looked_up={},manager.GetSpellTimer,counts.spells;
manager.GetSpellTimer=function(self,id) read_ids[id]=(read_ids[id] or 0)+1;return read_spell(self,id);end;
for _=1,5 do view=update();end;
assert(read_ids[2]==5 and read_ids[6]==nil and not row(view,'spell',6) and row(view,'spell',2),'A spell with no name is not read');
assert(counts.spells==looked_up,'The spells to read are found once');
manager.GetSpellTimer=read_spell;
