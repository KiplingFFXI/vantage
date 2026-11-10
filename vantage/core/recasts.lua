-- Reads the client's cooldowns without issuing actions or predicting charge counts.
local recasts = {};
local methods = {};
methods.__index = methods;
local names = {spell={},ability={},item={}};
local indexed = {spell=false,ability=false};
local catalogs = {};
local ability_candidates, preview_icons = {}, {spell={},ability={},item={}};
local preview_missing = {spell={},ability={},item={}};
local ready_observations = {spell={},ability={}};
local item_library, item_library_tried, item_library_problem;
local clear = require('table.clear');

local function finite(value)
    return type(value)=='number' and value==value and math.abs(value)<math.huge;
end

local function integer(value, low, high)
    return finite(value) and value==math.floor(value) and value>=low and value<=high;
end

-- pcall(index_of, object, key) guards a lookup without making a closure for it.
local function index_of(object, key) return object[key]; end;

local function field(object, key)
    if object==nil then return nil; end;
    local ok,value=pcall(index_of,object,key);
    if ok then return value; end;
end

local function call(object, key, ...)
    local fn=field(object,key);
    if type(fn)~='function' then return nil; end;
    local ok,value=pcall(fn,object,...);
    if ok then return value; end;
end

local function copy(value)
    local result={};
    for key,item in pairs(value) do result[key]=item; end;
    return result;
end

local function resource_name(resource)
    local value=field(field(resource,'Name'),1);
    if type(value)~='string' then return nil; end;
    value=value:gsub('%c',''):match('^%s*(.-)%s*$');
    if value~='' and value~='.' then return value:sub(1,200); end;
end

local function entry(kind, id, name, shared)
    local encoded=(kind=='spell' and 10000 or kind=='ability' and 20000 or 30000)+id;
    return {id=encoded,effect=encoded,recast_id=id,name=name,kind=kind,
        group=kind=='spell' and 'spell_recasts' or kind=='ability' and 'ability_recasts' or 'item_recasts',shared=shared};
end

local function icon_number(value)
    if integer(value,0,65535) then return value; end;
end

local function action_icon(kind,id,resource)
    if preview_icons[kind][id] and not preview_missing[kind][id] then return preview_icons[kind][id]; end;
    local result={name=resource_name(resource)};
    if kind=='spell' then
        result.spell_id=id;
        result.list_icon_nq=icon_number(field(resource,'ListIconNQ'));
        result.list_icon_hq=icon_number(field(resource,'ListIconHQ'));
    elseif kind=='ability' then
        result.ability_id=id;
        result.list_icon_id=icon_number(field(resource,'ListIconId'));
        result.list_icon_hq=result.list_icon_id;
        local element=field(resource,'Element');
        result.list_icon_nq=integer(element,0,255) and element or nil;
        result.ability_element=result.list_icon_nq;
    else result.item_id=id; end;
    preview_icons[kind][id]=result;
    preview_missing[kind][id]=resource==nil and kind~='item' and os.clock() or nil;
    return result;
end

function recasts.preview_icon(kind,id)
    if not preview_icons[kind] or not integer(id,kind=='item' and 1 or 0,kind=='spell' and 1023 or kind=='ability' and 2047 or 65534) then return nil; end;
    local retry=preview_missing[kind][id];
    if preview_icons[kind][id] and (not retry or os.clock()-retry<1) then return preview_icons[kind][id]; end;
    local resources=call(AshitaCore,'GetResourceManager');
    local resource=kind=='spell' and call(resources,'GetSpellById',id) or kind=='ability' and call(resources,'GetAbilityById',id) or nil;
    return action_icon(kind,id,resource);
end

local function icon_key(icon)
    local hq,nq=icon.list_icon_hq,icon.list_icon_nq;
    if hq~=nil and hq~=65535 then return 'hq:'..hq; end;
    if hq==65535 and nq~=nil and nq~=65535 then return 'nq:'..nq; end;
end

local function ability_icons(result,candidates,source,known)
    local icons,ids,unique,icon_ids={},{},{},{};
    local common,first,ambiguous;
    for _,candidate in ipairs(candidates or {}) do
        local icon=candidate.icon;
        icons[#icons+1]=icon;
        if known then ids[#ids+1]=icon.ability_id; end;
        if icon.list_icon_id~=nil and not unique[icon.list_icon_id] then
            unique[icon.list_icon_id]=true;icon_ids[#icon_ids+1]=icon.list_icon_id;
        end;
        local key=icon_key(icon);
        if not first then first,common=icon,key; elseif key~=common then ambiguous=true; end;
        if not key then ambiguous=true; end;
    end;
    table.sort(ids);table.sort(icon_ids);
    result.action_icons,result.ability_ids,result.list_icon_ids=icons,ids,icon_ids;
    result.ability_id=#ids==1 and ids[1] or nil;
    result.icon_source=source;
    result.icon_ambiguous=ambiguous==true or #icons==0;
    if first and not result.icon_ambiguous then
        result.list_icon_id,result.list_icon_hq,result.list_icon_nq=first.list_icon_id,first.list_icon_hq,first.list_icon_nq;
        result.ability_element=first.ability_element;
    else result.list_icon_id,result.list_icon_hq,result.list_icon_nq,result.ability_element=nil,nil,nil,nil; end;
    return result;
end

-- A shared timer is named for its first two actions; the others are left out.
local function ability_caption(candidates)
    local values,list={},{};
    for _,candidate in ipairs(candidates) do values[candidate.name]=true; end;
    for name in pairs(values) do list[#list+1]=name; end;
    table.sort(list);
    return table.concat(list,' / ',1,math.min(2,#list));
end

-- The ids data/actions.lua keeps. What it leaves out doesn't exist on Phoenix: those rows stay here, as names, icons
-- and live rows read them, marked unlisted for the pickers to leave out.
local function on_phoenix(list)
    local ids={};
    for _,id in ipairs(require('data.actions')[list]) do ids[id]=true; end;
    return ids;
end

local function index_abilities(resources)
    if indexed.ability or not resources then return; end;
    local groups,listed,kept={},on_phoenix('abilities'),{};
    for id=0,2047 do
        local resource=call(resources,'GetAbilityById',id);
        local timer,name=field(resource,'RecastTimerId'),resource_name(resource);
        -- Timer zero is also a default on pet records; player specials use type 1.
        if integer(timer,0,4095) and name and id>=512 and id<1536 and (timer~=0 or field(resource,'Type')==1) then
            groups[timer]=groups[timer] or {};
            groups[timer][#groups[timer]+1]={name=name,icon=action_icon('ability',id,resource),type=field(resource,'Type')};
            kept[timer]=kept[timer] or listed[id-512];
        end;
    end;
    for timer,values in pairs(groups) do
        ability_candidates[timer]=values;
        local shared=#values>1 or timer==0;
        local caption=timer==0 and 'Job special' or ability_caption(values);
        names.ability[timer]=ability_icons(entry('ability',timer,caption..(shared and ' (shared)' or ''),shared),
            timer==0 and {} or values,'resource_aliases',false);
        -- One ability on the list keeps its timer, and timer 0 is every job's special.
        names.ability[timer].unlisted=timer~=0 and not kept[timer] or nil;
    end;
    names.ability[0]=names.ability[0] or ability_icons(entry('ability',0,'Job special (shared)',true),{},'unavailable',false);
    indexed.ability=true;
    catalogs.ability,catalogs.all=nil,nil;
end

local function metadata(kind,id,resources,resource)
    if names[kind][id] then return names[kind][id]; end;
    if kind=='ability' then
        index_abilities(resources);
        if names.ability[id] then return names.ability[id]; end;
        resource=call(resources,'GetAbilityByTimerId',id);
    elseif kind=='spell' then resource=call(resources,'GetSpellById',id); end;
    local name=resource_name(resource) or (kind=='spell' and 'Spell ' or kind=='ability' and 'Ability timer ' or 'Item ')..id;
    local result=entry(kind,id,name);
    if kind=='spell' or kind=='item' then
        for key,value in pairs(action_icon(kind,id,resource)) do if key~='name' then result[key]=value; end;end;
    elseif id~=0 then
        local action_id=field(resource,'Id');
        if integer(action_id,512,1535) and field(resource,'RecastTimerId')==id then
            local candidate={name=name,icon=action_icon('ability',action_id,resource),type=field(resource,'Type')};
            ability_candidates[id]={candidate};
            ability_icons(result,{candidate},'resource_lookup',false);
        end;
    end;
    names[kind][id]=result;
    catalogs[kind],catalogs.all=nil,nil;
    return result;
end

function recasts.catalog(kind)
    local resources=call(AshitaCore,'GetResourceManager');
    if (kind==nil or kind=='spell') and not indexed.spell and resources then
        local listed=on_phoenix('spells');
        for id=0,1023 do
            local resource=call(resources,'GetSpellById',id);
            if resource_name(resource) then
                local result=entry('spell',id,resource_name(resource));
                for key,value in pairs(action_icon('spell',id,resource)) do if key~='name' then result[key]=value; end;end;
                result.unlisted=not listed[id] or nil;
                names.spell[id]=result;
            end;
        end;
        indexed.spell=true;
        catalogs.spell,catalogs.all=nil,nil;
    end;
    if kind==nil or kind=='ability' then index_abilities(resources); end;
    local cache_key=kind or 'all';
    if catalogs[cache_key] then return catalogs[cache_key]; end;
    local result={};
    for _,category in ipairs({'spell','ability','item'}) do if kind==nil or category==kind then
        for _,value in pairs(names[category]) do result[#result+1]=copy(value); end;
    end end;
    table.sort(result,function(a,b)
        local first,second=a.name:lower(),b.name:lower();
        if first==second then return a.id<b.id; end;
        return first<second;
    end);
    catalogs[cache_key]=result;
    return result;
end

function recasts.new()
    return setmetatable({rows={},previous={},events={},sequence=0,version=0,valid=false,capabilities={}},methods);
end

-- A zone change or a pause drops the rows, but the client keeps counting the same cooldowns. Rows that knew their
-- start and total are kept aside, so the first sample after can give them back to the same character and job.
function methods:reset()
    local kept;
    for key,row in pairs(self.rows) do if row.total and row.start and row.deadline then
        kept=kept or {};kept[key]=row;
    end end;
    if kept then self.carried={owner=self.owner,time=self.last_time,rows=kept}; end;
    if next(self.rows) then self.version=self.version+1; end;
    self.rows,self.previous,self.spare,self.events,self.epoch,self.last_time={},{},nil,{},nil,nil;
    self.ability_metadata,self.ability_context,self.ability_checked={},nil,nil;
    self.valid=false;
end

local function known_value(value)
    if value==true or value==1 then return true; end;
    if value==false or value==0 then return false; end;
end

local function refresh_ability_context(model,memory,now)
    local player=call(memory,'GetPlayer');
    local ready=known_value(call(player,'HasAbilityData'));
    local fields={tostring(ready)};
    for _,key in ipairs({'GetMainJob','GetSubJob','GetMainJobLevel','GetSubJobLevel'}) do fields[#fields+1]=tostring(call(player,key)); end;
    local signature=table.concat(fields,':');
    if model.ability_context~=signature or not model.ability_checked or now-model.ability_checked>=1 then
        model.ability_context,model.ability_checked,model.ability_metadata=signature,now,{};
    end;
    return player,ready;
end

local function live_ability_metadata(model,id,resources,player,ready,counts)
    local base=metadata('ability',id,resources);
    if model.ability_metadata[id] then return model.ability_metadata[id]; end;
    local candidates,selected=ability_candidates[id] or {},{};
    local complete=ready==true and type(field(player,'HasAbility'))=='function';
    if complete then
        for _,candidate in ipairs(candidates) do
            counts.ability_known=(counts.ability_known or 0)+1;
            local known=known_value(call(player,'HasAbility',candidate.icon.ability_id));
            local pet=false;
            -- Timer zero is the player special timer, not a pet-command timer.
            if id~=0 and known~=true and type(field(player,'HasPetCommand'))=='function' then
                counts.ability_known=counts.ability_known+1;
                pet=known_value(call(player,'HasPetCommand',candidate.icon.ability_id));
            end;
            if known==true or pet==true then selected[#selected+1]=candidate;
            elseif known==nil or pet==nil then complete=false; end;
        end;
    end;
    local result=base;
    if complete and #selected>0 then
        result=copy(base);
        result.name=ability_caption(selected)..(base.shared and ' (shared)' or '');
        ability_icons(result,selected,'known_abilities',true);
    end;
    model.ability_metadata[id]=result;
    return result;
end

local icon_fields={'spell_id','item_id','ability_id','ability_ids','action_icons','list_icon_ids',
    'list_icon_id','list_icon_hq','list_icon_nq','ability_element','icon_source','icon_ambiguous'};

local function apply_metadata(row,meta)
    row.name,row.shared=meta.name,meta.shared;
    for _,key in ipairs(icon_fields) do row[key]=meta[key]; end;
end

local function timer_reader(object,key,counts)
    local fn=field(object,key);
    return function(index)
        if type(fn)~='function' then return nil; end;
        counts[key]=(counts[key] or 0)+1;
        local ok,value=pcall(fn,object,index);
        if ok and integer(value,0,2147483647) then return value; end;
    end;
end

local function observation(kind,id,seconds)
    if seconds>0 then return {kind=kind,id=id,seconds=seconds}; end;
    -- Ready samples never change; reuse them instead of allocating one for each timer each tick.
    local cache=ready_observations[kind];
    if not cache[id] then cache[id]={kind=kind,id=id,seconds=0}; end;
    return cache[id];
end

-- The spells the client has a name for, and each one's row key, found once. A sample reads only their timers and makes
-- no keys: a spell with no name has nothing to show. A client that names none yet is asked again the next sample.
local named_spells,spell_keys;
local function spells_to_read(resources)
    if not named_spells and resources then
        local found,keys={},{};
        for id=0,1023 do
            if resource_name(call(resources,'GetSpellById',id)) then
                found[#found+1]=id;
                keys[#found]='spell:'..id;
            end;
        end;
        if #found>0 then named_spells,spell_keys=found,keys; end;
    end;
    return named_spells;
end

-- Item recasts come from Ashita's item data library, loaded on the first equipped item with charges. It needs
-- Ashita's time library and all of that library's client patterns, so on a client where one is missing item
-- recasts are off and nothing else changes.
local function item_parser()
    if not item_library_tried then
        item_library_tried=true;
        local ok,value=pcall(require,'ffxi.itemdata');
        if ok and type(value)=='table' and type(value.parse_timer_info)=='function' then item_library=value;
        else item_library_problem=ok and 'it has no item timers' or tostring(value); end;
    end;
    return item_library;
end

local function read_items(memory,resources,result,counts,capabilities)
    local inventory=call(memory,'GetInventory');
    capabilities.items=inventory~=nil;
    if not inventory then return; end;
    for slot=0,15 do
        counts.equipment=(counts.equipment or 0)+1;
        local equipped=call(inventory,'GetEquippedItem',slot);
        local index=field(equipped,'Index');
        if integer(index,1,65535) then
            counts.inventory=(counts.inventory or 0)+1;
            local item=call(inventory,'GetContainerItem',math.floor(index/256),index%256);
            local id=field(item,'Id');
            if integer(id,1,65534) then
                local resource=call(resources,'GetItemById',id);
                local kind,max_charges,delay,cast=field(resource,'Type'),field(resource,'MaxCharges'),field(resource,'RecastDelay'),field(resource,'CastDelay');
                local extra=field(item,'Extra');
                -- Weapons and armor (types 4 and 5) with charges, whose first extra byte is 1, are what parse_timer_info
                -- reads, from 12 extra bytes.
                if (kind==4 or kind==5) and integer(max_charges,1,255) and finite(delay) and delay>0 and finite(cast) and cast>0
                    and type(extra)=='string' and #extra>=12 and extra:byte(1)==1 then
                    local parser=item_parser();
                    capabilities.item_timers=parser~=nil;
                    if parser then
                        counts.item_timers=(counts.item_timers or 0)+1;
                        local ok,info=pcall(parser.parse_timer_info,item,resource,true);
                        local seconds=ok and type(info)=='table' and info.use_delay or nil;
                        local charges=ok and type(info)=='table' and info.remaining_charges or nil;
                        if finite(seconds) and seconds>=-2147483648 and seconds<=2147483647 and integer(charges,1,255) then
                            local key='item:'..id..':'..index;
                            result[key]={kind='item',id=id,seconds=math.max(0,seconds),meta=metadata('item',id,resources,resource),
                                charges=charges,equipment_slot=slot,inventory_index=index};
                        end;
                    end;
                end;
            end;
        end;
    end;
end

local function same_session(memory,snapshot)
    local party,player=call(memory,'GetParty'),call(memory,'GetPlayer');
    if party and (call(party,'GetMemberServerId',0)~=snapshot.id or call(party,'GetMemberZone',0)~=snapshot.zone) then return false; end;
    if player and call(player,'GetMainJob')~=snapshot.job then return false; end;
    local zoning=call(player,'GetIsZoning');
    if zoning==true or zoning==1 then return false; end;
    return true;
end

function methods:queue(kind,row,now)
    local event=copy(row);
    event.category,event.kind,event.time=row.kind,kind,now;
    if #self.events>=512 then table.remove(self.events,1); end;
    self.events[#self.events+1]=event;
end

function methods:update(snapshot,now,options)
    options=options or {};
    if not finite(now) or options.enabled==false or not snapshot or not snapshot.valid or not integer(snapshot.id,1,4294967295) then
        self:reset();self.capabilities={};return;
    end;
    local epoch=table.concat({snapshot.id,snapshot.zone or 0,snapshot.job or 0},':');
    if self.epoch~=epoch or self.last_time and (now<self.last_time or now-self.last_time>2) then self:reset(); end;
    local baseline=self.epoch~=epoch;
    self.epoch,self.last_time,self.owner=epoch,now,snapshot.id..':'..(snapshot.job or 0);
    -- Time that went back makes the kept end times meaningless; another character or job has other cooldowns.
    local carried=self.carried;
    if carried and (now<carried.time or carried.owner~=self.owner) then
        carried,self.carried=nil,nil;
    end;
    local memory=call(AshitaCore,'GetMemoryManager');
    if not same_session(memory,snapshot) then self:reset();self.capabilities={identity_changed=true};return; end;
    local manager,resources=call(memory,'GetRecast'),call(AshitaCore,'GetResourceManager');
    local counts,observed={},self.spare or {};
    self.spare=nil;clear(observed);
    local capabilities={spells=type(field(manager,'GetSpellTimer'))=='function',abilities=type(field(manager,'GetAbilityTimer'))=='function'
        and type(field(manager,'GetAbilityTimerId'))=='function',items=false,reads=counts};
    local spells=options.spells~=false and capabilities.spells and spells_to_read(resources);
    if spells then
        local read=timer_reader(manager,'GetSpellTimer',counts);
        for index,id in ipairs(spells) do
            local raw=read(id);
            if raw~=nil then observed[spell_keys[index]]=observation('spell',id,raw/60); end;
        end;
    end;
    if options.abilities~=false and capabilities.abilities then
        local read_id,read_timer=timer_reader(manager,'GetAbilityTimerId',counts),timer_reader(manager,'GetAbilityTimer',counts);
        local complete=true;
        for slot=0,30 do
            local id,raw=read_id(slot),read_timer(slot);
            if not integer(id,0,4095) or raw==nil then complete=false; end;
            -- Id 0 is the job special only in slot 0. In any other slot it is an empty slot.
            if integer(id,0,4095) and (id~=0 or slot==0) and raw~=nil then
                local key='ability:'..id;
                if not observed[key] or raw/60>observed[key].seconds then observed[key]=observation('ability',id,raw/60); end;
            end;
        end;
        if not complete then
            for key,input in pairs(observed) do if input.kind=='ability' and input.seconds==0 then observed[key]=nil; end;end;
        end;
        capabilities.ability_complete=complete;
    end;
    if options.items~=false then read_items(memory,resources,observed,counts,capabilities); end;
    local player,ready,identity_checked;
    for _,input in pairs(observed) do if input.kind=='ability' and input.seconds>0 then
        if not identity_checked then player,ready=refresh_ability_context(self,memory,now);identity_checked=true; end;
        input.meta=live_ability_metadata(self,input.id,resources,player,ready,counts);
    end end;
    if not same_session(memory,snapshot) then self:reset();self.capabilities={identity_changed=true,reads=counts};return; end;
    self.valid,self.capabilities=capabilities.spells or capabilities.abilities or capabilities.items,capabilities;
    -- Whether a row came, went or took another name. Only that moves the version, which has the settings window build
    -- its list of recasts again.
    local changed=false;
    for key,input in pairs(observed) do
        local previous,row=self.previous[key],self.rows[key];
        if input.seconds>0 then
            -- Phoenix sends every ability timer again, rounded up to whole seconds (0x119), each time an ability is
            -- used, so a running ability timer can rise by up to a second without a new use.
            local started=not baseline and previous and (previous.seconds==0
                or input.seconds>previous.seconds+(input.kind=='ability' and 1.5 or 0.1));
            local meta=input.meta or metadata(input.kind,input.id,resources);
            if not row or started then
                if not row then changed=true; end;
                self.sequence=self.sequence+1;
                row={key='recast:'..snapshot.id..':'..key,instance=self.sequence,domain='recast',scope='self',kind=input.kind,
                    group=meta.group,effect=meta.effect,recast_id=input.id,name=meta.name,entity_id=snapshot.id,entity_name=snapshot.name or 'You',
                    present=true,first_seen=now,priority=0,total=started and input.seconds or nil,start=started and now or nil,shared=meta.shared};
                self.rows[key]=row;
                -- The same cooldown ends when it did before the zone change or pause: it keeps its start and total, and
                -- its instance, so a ready pulse that played for it doesn't play again.
                local kept=baseline and carried and carried.rows[key];
                if kept and not started and math.abs(kept.deadline-(now+input.seconds))<=1.5 then
                    row.start,row.total,row.instance=kept.start,kept.total,kept.instance;
                end;
            elseif not previous then row.total,row.start=nil,nil; end;
            local name=row.name;
            apply_metadata(row,meta);
            if row.name~=name then changed=true; end;
            row.observed_at,row.deadline,row.remaining,row.status,row.unavailable_at=now,now+input.seconds,input.seconds,'server',nil;
            row.charges,row.equipment_slot,row.inventory_index=input.charges,input.equipment_slot,input.inventory_index;
            row.reason=input.kind=='ability' and 'Client ability recast. Shared or charge-based actions can be usable before this timer reaches zero; charges are not inferred.'
                or input.kind=='item' and 'Client use delay for this equipped enchanted item; includes its equip delay.' or 'Client spell recast.';
            if started then self:queue('started',row,now); end;
        elseif row then
            if previous and previous.seconds>0 and not baseline then
                row.present,row.remaining,row.deadline,row.status=false,0,now,'server';
                self:queue('ready',row,now);
            end;
            self.rows[key],changed=nil,true;
        end;
    end;
    for key,row in pairs(self.rows) do if not observed[key] then
        row.status,row.remaining,row.deadline,row.total='unknown',nil,nil,nil;
        row.reason='The client recast is no longer readable.';
        row.unavailable_at=row.unavailable_at or now;
        if now-row.unavailable_at>10 then self.rows[key],changed=nil,true; end;
    end end;
    if baseline then self.carried=nil; end;
    self.spare,self.previous=self.previous,observed;
    if changed then self.version=self.version+1; end;
end

function methods:project(view,now)
    if not view or not finite(now) then return; end;
    for _,row in ipairs(view.rows or {}) do if row.domain=='recast' then
        row.elapsed=row.start and math.max(0,now-row.start) or nil;
        if row.deadline and row.deadline>now then row.remaining=math.max(0,row.deadline-now);
        elseif row.deadline then
            row.remaining,row.status=nil,'unknown';
            row.reason='Waiting for the client to confirm that the recast has finished.';
        end;
    end end;
end

function methods:view(now)
    local result={rows={},valid=self.valid,version=self.version,capabilities=self.capabilities};
    for _,row in pairs(self.rows) do result.rows[#result.rows+1]=copy(row); end;
    table.sort(result.rows,function(a,b) return a.key<b.key; end);
    self:project(result,now);
    return result;
end

function methods:drain_events()
    local result=self.events;self.events={};return result;
end

-- For /vg report and the Recasts tab, which asks each frame: whether item recasts can be read. Callers only read it.
local ITEMS_WAITING={reason='Item recasts load with the first equipped item that has charges.'};
local ITEMS_ON={available=true,reason='Item recasts are on.'};
function recasts.item_status()
    if not item_library_tried then return ITEMS_WAITING; end;
    if item_library then return ITEMS_ON; end;
    return {available=false,problem=item_library_problem,
        reason='Item recasts are off because the Ashita item data library could not load on this client.'};
end;

return recasts;
