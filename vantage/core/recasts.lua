-- Reads the client's cooldowns without issuing actions or predicting charge counts.
local recasts = {};
local methods = {};
methods.__index = methods;
local names = {spell={},ability={},item={}};
local indexed = {spell=false,ability=false};
local catalogs = {};
local ability_candidates, preview_icons = {}, {spell={},ability={},item={}};
-- Each job ability's timer, by the ability's id, found with the aliases.
local action_timers = {};
local preview_missing = {spell={},ability={},item={}};
local ready_observations = {spell={},ability={}};
local item_library, item_library_tried, item_library_problem;
local clear = require('table.clear');
local steady = require('core.steady');

local function finite(value)
    return type(value)=='number' and value==value and math.abs(value)<math.huge;
end

local function integer(value, low, high)
    return finite(value) and value==math.floor(value) and value>=low and value<=high;
end

local field, call, resource_name = require('core.guard').field, require('core.guard').call, require('core.guard').resource_name;

local function copy(value)
    local result={};
    for key,item in pairs(value) do result[key]=item; end;
    return result;
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
    preview_missing[kind][id]=resource==nil and kind~='item' and steady() or nil;
    return result;
end

function recasts.preview_icon(kind,id)
    if not preview_icons[kind] or not integer(id,kind=='item' and 1 or 0,kind=='spell' and 1023 or kind=='ability' and 2047 or 65534) then return nil; end;
    local retry=preview_missing[kind][id];
    if preview_icons[kind][id] and (not retry or steady()-retry<1) then return preview_icons[kind][id]; end;
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
-- A timer a whole group of abilities shares goes by the group's name, as the game's menu has it: its first two names
-- would read as the two you used. By recast id (Phoenix sql/abilities.sql recastId): each kind of blood pact, the
-- rolls, the Quick Draw shots and the maneuvers. Sic's timer (:92) has Ready (:269) and the jug pets' moves (:528 on)
-- too, but Ready is WotG and isn't loaded, so on Phoenix the timer is Sic's alone (data/pets.lua) and goes by its name.
local GROUPS={[102]='Sic',[173]='Blood Pact: Rage',[174]='Blood Pact: Ward',[193]='Phantom Roll',[195]='Quick Draw',[210]='Maneuvers'};
local function ability_name(timer,candidates,shared)
    return GROUPS[timer] or ability_caption(candidates)..(shared and ' (shared)' or '');
end

-- The ids data/actions.lua keeps. What it leaves out doesn't exist on Phoenix: those rows stay here, as names, icons
-- and live rows read them, marked unlisted for the pickers to leave out. A spell off the list is read live only if you
-- know it.
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
            action_timers[id-512]=timer;
        end;
    end;
    for timer,values in pairs(groups) do
        ability_candidates[timer]=values;
        local shared=#values>1 or timer==0;
        local name=timer==0 and 'Job special (shared)' or ability_name(timer,values,shared);
        names.ability[timer]=ability_icons(entry('ability',timer,name,shared),
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
    return setmetatable({rows={},previous={},events={},spare_events={},sequence=0,version=0,valid=false,capabilities={},uses={},pending={},requests={},
        item_answers={}},methods);
end

-- How far from a cooldown's first reading your use of its ability can come. Phoenix sends the two together. A pact's
-- cooldown starts when the avatar's move goes off, which core/observer.lua counts as a use of the pact too.
local USE_WINDOW=3;

-- How long what reset() kept waits for its timers after the first sample of a zone or pause. At a zone-in Phoenix
-- lists the abilities on cooldown (0x119) only after the rest of its answer to the client's first packets, the whole
-- inventory too (src/map/packets/c2s/0x00c_gameok.cpp:106 and 0x061_clistatus.cpp:35,
-- src/map/utils/charutils.cpp:1691). In Phoenix packet logs it came 1.6 to 8.1 seconds after the zone-in's status
-- icons (0x063).
local CARRY_WAIT=60;

-- Your own use of a job ability, or your avatar's pact going off, by its id (core/observer.lua). Phoenix lists only the
-- abilities on cooldown (0x119), so the first use of one since you logged in, zoned or changed jobs brings a timer with
-- no reading before it, and so does a zone's list that comes after the first read. Only one that comes with a use of
-- its own has started, and one a zone's late list brings back keeps what it had before the zone.
function methods:used(action_id,now)
    if integer(action_id,0,1023) and finite(now) then self.uses[action_id]=now; end;
end

-- How long your request waits for a paralysis. The server acts on it at its next tick, so the paralysis comes about a
-- round trip later, but a lag spike can hold it back for seconds. A request the server answered some other way can
-- meet a later paralysis too, but that starts nothing: its timer is listed already, or comes with a use of its own.
local REQUEST_WINDOW=10;

-- Your request to use a job ability (0x01A). Paralysis stops a use with an action that names no ability, though its
-- cooldown still starts (src/map/entities/char_entity.cpp OnAbility), so a paralysis counts as a use of each ability
-- you asked for in the 10 seconds before it.
function methods:requested(action_id,now)
    if integer(action_id,0,1023) and finite(now) then self.requests[action_id]=now; end;
end

function methods:paralyzed(now)
    if not finite(now) then return; end;
    for action,time in pairs(self.requests) do if now-time<=REQUEST_WINDOW then self:used(action,now); end;end;
    clear(self.requests);
end

-- Whether you used an ability on this timer within the window either side of at.
local function confirmed(model,timer,at)
    for action,time in pairs(model.uses) do
        if action_timers[action]==timer and math.abs(time-at)<=USE_WINDOW then return true; end;
    end;
    return false;
end

-- A zone change or a pause drops the rows, but the client keeps counting the same cooldowns. Rows still counting are
-- kept aside, so the samples after can give them back to the same character and job, with their start and total when
-- they knew them.
function methods:reset()
    local kept;
    for key,row in pairs(self.rows) do if row.deadline then
        kept=kept or {};kept[key]=row;
    end end;
    -- A second reset before every kept row came back, as a pause before a zone's late list, adds its rows to those
    -- still waiting.
    local carried=self.carried;
    if kept and carried and carried.owner==self.owner then
        for key,row in pairs(kept) do carried.rows[key]=row; end;
        carried.time=self.last_time or carried.time;
    elseif kept then self.carried={owner=self.owner,time=self.last_time,rows=kept}; end;
    if next(self.rows) then self.version=self.version+1; end;
    self.rows,self.previous,self.spare,self.events,self.epoch,self.last_time={},{},nil,{},nil,nil;
    clear(self.uses);clear(self.pending);clear(self.requests);
    self.ability_metadata,self.ability_context,self.ability_checked={},nil,nil;
    self.valid=false;
end

local function known_value(value)
    if value==true or value==1 then return true; end;
    if value==false or value==0 then return false; end;
end

-- What the known abilities go by, and the list a sample writes them into, made once.
local context_keys,context_fields={'GetMainJob','GetSubJob','GetMainJobLevel','GetSubJobLevel'},{};
local function refresh_ability_context(model,memory,now)
    local player=call(memory,'GetPlayer');
    local ready=known_value(call(player,'HasAbilityData'));
    context_fields[1]=tostring(ready);
    for index,key in ipairs(context_keys) do context_fields[index+1]=tostring(call(player,key)); end;
    local signature=table.concat(context_fields,':');
    if model.ability_context~=signature or not model.ability_checked then
        model.ability_context,model.ability_checked,model.ability_metadata,model.ability_last,model.ability_bases=signature,now,{},nil,{};
    elseif now-model.ability_checked>=1 then
        -- Once a second the known abilities are asked again. What their answers made last time is kept in
        -- ability_last, to hand out again when the answers are the same.
        model.ability_checked=now;
        model.ability_last,model.ability_metadata=model.ability_metadata,model.ability_last or {};
        clear(model.ability_metadata);
    end;
    return player,ready;
end

-- Whether what the known abilities made for timer id last time, last, is what they make now: a copy of the same base
-- for the same abilities, in the same order.
local function same_known(model,id,last,base,selected)
    if not last or last==base or model.ability_bases[id]~=base or #last.action_icons~=#selected then return false; end;
    for index,candidate in ipairs(selected) do if last.action_icons[index]~=candidate.icon then return false; end; end;
    return true;
end

-- The abilities of a timer the client names none for, and the list of a timer's abilities you know, refilled each time
-- it is asked about.
local NO_CANDIDATES,selected={},{};
local function live_ability_metadata(model,id,resources,player,ready,counts)
    local base=metadata('ability',id,resources);
    if model.ability_metadata[id] then return model.ability_metadata[id]; end;
    local candidates=ability_candidates[id] or NO_CANDIDATES;
    clear(selected);
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
    local result,last=base,model.ability_last and model.ability_last[id];
    if complete and #selected>0 and same_known(model,id,last,base,selected) then result=last;
    elseif complete and #selected>0 then
        result=copy(base);
        result.name=ability_name(id,selected,base.shared);
        ability_icons(result,selected,'known_abilities',true);
        model.ability_bases[id]=base;
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

-- One timer read with fn, the manager's function named key, counted under key.
local function read_timer(fn,object,key,counts,index)
    if type(fn)~='function' then return nil; end;
    counts[key]=(counts[key] or 0)+1;
    local ok,value=pcall(fn,object,index);
    if ok and integer(value,0,2147483647) then return value; end;
end

-- A running timer's reading goes in the table pool keeps for its key, refilled each time. A sample fills the pool of
-- the sample before last, as the last one's readings are what it compares with.
local function observation(pool,key,kind,id,seconds)
    if seconds>0 then
        local held=pool[key];
        if not held then held={kind=kind,id=id};pool[key]=held; end;
        held.seconds,held.meta=seconds,nil;
        return held;
    end;
    -- Ready samples never change; reuse them instead of allocating one for each timer each tick.
    local cache=ready_observations[kind];
    if not cache[id] then cache[id]={kind=kind,id=id,seconds=0}; end;
    return cache[id];
end

-- The spells the client has a name for, split into those on data/actions.lua's list and the rest, and each one's row
-- key by its id, found once. A spell with no name has nothing to show, and one off the list can't count down on Phoenix
-- (Phoenix src/map/utils/charutils.cpp:961 loads only the spells whose content is on). A client that names none yet is
-- asked again the next sample.
local listed_spells,other_spells,spell_keys;
-- How often the spells off the list you know are asked about again, in seconds. A new character, zone, job or support
-- job asks at once.
local SPELL_CHECK=5;
-- A sample reads the listed spells and the ones off the list you know, kept in one list for the model and refilled
-- only when they are asked about again. It makes no keys.
local function spells_to_read(model,memory,resources,now)
    if not listed_spells and resources then
        local listed,found,others,keys=on_phoenix('spells'),{},{},{};
        for id=0,1023 do
            if resource_name(call(resources,'GetSpellById',id)) then
                if listed[id] then found[#found+1]=id; else others[#others+1]=id; end;
                keys[id]='spell:'..id;
            end;
        end;
        if #found>0 or #others>0 then listed_spells,other_spells,spell_keys=found,others,keys; end;
    end;
    if not listed_spells then return nil; end;
    local ids,checked=model.spell_ids,model.spell_checked;
    if ids and model.spell_epoch==model.epoch and now>=checked and now-checked<SPELL_CHECK then return ids; end;
    if not ids then
        ids={};
        for index,id in ipairs(listed_spells) do ids[index]=id; end;
        model.spell_ids=ids;
    end;
    local count=#listed_spells;
    local player=call(memory,'GetPlayer');
    if type(field(player,'HasSpell'))=='function' then
        for _,id in ipairs(other_spells) do
            if known_value(call(player,'HasSpell',id))==true then count=count+1;ids[count]=id; end;
        end;
    end;
    for index=#ids,count+1,-1 do ids[index]=nil; end;
    model.spell_epoch,model.spell_checked=model.epoch,now;
    return ids;
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

-- The library's answer for a worn item comes from its extra bytes and the client's game time, which its game_time_diff
-- reads in whole seconds through the game time function core/clock.lua finds. So each item's answer is kept with its
-- bytes and that second, and the library is asked again only when either moved. An answer of 0 is kept while the bytes
-- stay the same, as the times they hold have passed or no charges are left. Each sample marks what it read with its
-- stamp. The clock is read only once core/clock.lua has looked for it, as self timers do, and without it a counting
-- item is asked at every sample.
local item_clock,item_stamp=nil,0;
local function game_second()
    if item_clock==nil then
        local ok,value=pcall(require,'core.clock');
        item_clock=ok and type(value)=='table' and type(value.get_game_time_raw)=='function' and value or false;
    end;
    if not item_clock or type(item_clock.loaded)=='function' and not item_clock.loaded() then return nil; end;
    local ok,value=pcall(item_clock.get_game_time_raw);
    if ok and finite(value) then return value; end;
end

local function read_items(memory,resources,result,counts,capabilities,pool,answers)
    local inventory=call(memory,'GetInventory');
    capabilities.items=inventory~=nil;
    if not inventory then return; end;
    item_stamp=item_stamp+1;
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
                        local key='item:'..id..':'..index;
                        local answer=answers[key];
                        if not (answer and answer.extra==extra and answer.seconds<=0) then
                            -- The second is read before the library reads the clock, so one that turns between them
                            -- only asks again at the next sample.
                            local second=game_second();
                            if not answer or answer.extra~=extra or not second or answer.second~=second then
                                local ok,info=pcall(parser.parse_timer_info,item,resource,true);
                                if ok and type(info)=='table' and type(info.use_delay)=='number' then
                                    answer=answer or {};answers[key]=answer;
                                    answer.extra,answer.second,answer.seconds,answer.charges=extra,second,info.use_delay,info.remaining_charges;
                                else answer,answers[key]=nil,nil; end;
                            end;
                        end;
                        if answer then answer.stamp=item_stamp; end;
                        local seconds,charges=answer and answer.seconds,answer and answer.charges;
                        if finite(seconds) and seconds>=-2147483648 and seconds<=2147483647 and integer(charges,1,255) then
                            -- The reading goes in the pool's table for its key, as a running timer's does.
                            local held=pool[key];
                            if not held then held={kind='item',id=id};pool[key]=held; end;
                            held.seconds,held.meta=math.max(0,seconds),metadata('item',id,resources,resource);
                            held.charges,held.equipment_slot,held.inventory_index=charges,slot,index;
                            result[key]=held;
                        end;
                    end;
                end;
            end;
        end;
    end;
    -- An item's key changes when it moves in the bag, so no answer is kept for an item this sample didn't read.
    for key,answer in pairs(answers) do if answer.stamp~=item_stamp then answers[key]=nil; end;end;
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
    -- Off, or with no character to read, it resets once and then makes nothing until a sample reads again. That sample
    -- resets too, as its epoch is new.
    if not finite(now) or options.enabled==false or not snapshot or not snapshot.valid or not integer(snapshot.id,1,4294967295) then
        if not self.off then self:reset();self.capabilities,self.off={},true; end;
        return;
    end;
    self.off=nil;
    -- A support job change drops the ability cooldowns as a main job change does (Phoenix
    -- src/map/packets/c2s/0x100_myroom_job.cpp:160). One that reads 0 for a while, as under a battlefield's restriction,
    -- changes nothing.
    if integer(snapshot.sub_job,1,255) then self.sub_job=snapshot.sub_job; end;
    local epoch=snapshot.id..':'..(snapshot.zone or 0)..':'..(snapshot.job or 0)..':'..(self.sub_job or 0);
    if self.epoch~=epoch or self.last_time and (now<self.last_time or now-self.last_time>2) then self:reset(); end;
    local baseline=self.epoch~=epoch;
    self.epoch,self.last_time,self.owner=epoch,now,snapshot.id..':'..(snapshot.job or 0);
    -- Time that went back makes the kept end times meaningless; another character or job has other cooldowns.
    local carried=self.carried;
    if carried and baseline then carried.from=now; end;
    if carried and (now<carried.time or carried.owner~=self.owner or now-carried.from>CARRY_WAIT) then
        carried,self.carried=nil,nil;
    end;
    local memory=call(AshitaCore,'GetMemoryManager');
    if not same_session(memory,snapshot) then self:reset();self.capabilities={identity_changed=true};return; end;
    -- A timer waits up to the window for a use, which can come up to the window before it, so a use is kept twice that.
    for action,time in pairs(self.uses) do if math.abs(now-time)>2*USE_WINDOW then self.uses[action]=nil; end;end;
    for action,time in pairs(self.requests) do if math.abs(now-time)>REQUEST_WINDOW then self.requests[action]=nil; end;end;
    local manager,resources=call(memory,'GetRecast'),call(AshitaCore,'GetResourceManager');
    -- The capabilities and read counts, and the readings, of the sample before last are refilled. The last sample's
    -- stay as they were: this one compares with its readings.
    local capabilities,observed,pool=self.spare_capabilities or {},self.spare or {},self.spare_pool or {};
    local counts=capabilities.reads or {};
    self.spare,self.spare_pool,self.spare_capabilities=nil,nil,nil;
    clear(observed);clear(capabilities);clear(counts);
    capabilities.spells=type(field(manager,'GetSpellTimer'))=='function';
    capabilities.abilities=type(field(manager,'GetAbilityTimer'))=='function' and type(field(manager,'GetAbilityTimerId'))=='function';
    capabilities.items,capabilities.reads=false,counts;
    local spells=options.spells~=false and capabilities.spells and spells_to_read(self,memory,resources,now);
    if spells then
        local read=field(manager,'GetSpellTimer');
        for _,id in ipairs(spells) do
            local raw=read_timer(read,manager,'GetSpellTimer',counts,id);
            if raw~=nil then observed[spell_keys[id]]=observation(pool,spell_keys[id],'spell',id,raw/60); end;
        end;
    end;
    if options.abilities~=false and capabilities.abilities then
        local read_id,read=field(manager,'GetAbilityTimerId'),field(manager,'GetAbilityTimer');
        local complete=true;
        for slot=0,30 do
            local id,raw=read_timer(read_id,manager,'GetAbilityTimerId',counts,slot),read_timer(read,manager,'GetAbilityTimer',counts,slot);
            if not integer(id,0,4095) or raw==nil then complete=false; end;
            -- Id 0 is the job special only in slot 0. In any other slot it is an empty slot.
            if integer(id,0,4095) and (id~=0 or slot==0) and raw~=nil then
                local key='ability:'..id;
                if not observed[key] or raw/60>observed[key].seconds then observed[key]=observation(pool,key,'ability',id,raw/60); end;
            end;
        end;
        if not complete then
            for key,input in pairs(observed) do if input.kind=='ability' and input.seconds==0 then observed[key]=nil; end;end;
        end;
        capabilities.ability_complete=complete;
    end;
    if options.items~=false then
        read_items(memory,resources,observed,counts,capabilities,pool,self.item_answers);
        -- An item's key changes when it moves in the bag, so the pool keeps no reading for an item this sample didn't read.
        for key,held in pairs(pool) do if held.kind=='item' and observed[key]~=held then pool[key]=nil; end;end;
    end;
    local player,ready,identity_checked;
    for _,input in pairs(observed) do if input.kind=='ability' and input.seconds>0 then
        if not identity_checked then player,ready=refresh_ability_context(self,memory,now);identity_checked=true; end;
        input.meta=live_ability_metadata(self,input.id,resources,player,ready,counts);
    end end;
    if not same_session(memory,snapshot) then self:reset();self.capabilities={identity_changed=true,reads=counts};return; end;
    self.valid,self.capabilities,self.spare_capabilities=capabilities.spells or capabilities.abilities or capabilities.items,capabilities,self.capabilities;
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
            -- The same cooldown ends when it did before the zone change or pause: it keeps its start and total, and its
            -- instance, so a ready pulse that played for it doesn't play again. An ability's can come back with a zone's
            -- list that comes late, and the job special's slot reads 0 until then, so that's no new use either.
            local kept=not row and carried and (baseline or not previous or input.kind=='ability') and carried.rows[key];
            if kept then
                carried.rows[key]=nil;
                if math.abs(kept.deadline-(now+input.seconds))<=1.5 then started=false; else kept=nil; end;
            end;
            -- An ability timer with no reading before it waits from its first reading for your use of it.
            local first=not kept and (self.pending[key] or not baseline and not previous and input.kind=='ability' and now);
            if first and not started then started=confirmed(self,input.id,first); end;
            self.pending[key]=first and not started and now-first<=USE_WINDOW and first or nil;
            local meta=input.meta or metadata(input.kind,input.id,resources);
            if not row or started then
                if not row then changed=true; end;
                self.sequence=self.sequence+1;
                row={key='recast:'..snapshot.id..':'..key,instance=self.sequence,domain='recast',scope='self',kind=input.kind,
                    group=meta.group,effect=meta.effect,recast_id=input.id,name=meta.name,entity_id=snapshot.id,entity_name=snapshot.name or 'You',
                    present=true,first_seen=now,priority=0,total=started and input.seconds or nil,start=started and now or nil,shared=meta.shared};
                self.rows[key]=row;
                if kept then row.start,row.total,row.instance=kept.start,kept.total,kept.instance; end;
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
    for key in pairs(self.pending) do if not observed[key] or observed[key].seconds==0 then self.pending[key]=nil; end;end;
    self.spare,self.previous=self.previous,observed;
    self.spare_pool,self.previous_pool=self.previous_pool,pool;
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

local function by_key(a,b) return a.key<b.key; end;

-- vantage.lua asks for a view each refresh. It gets the same list each time, and each row's copy again, refilled from
-- its row, so what was written on the copy goes. A row made again for a new use gets a new copy, so one held from
-- before keeps what it had. Nothing keeps the list or a copy past the next view.
function methods:view(now)
    local result,copies,sources=self.shown,self.copies,self.sources;
    if not result then
        result,copies,sources={rows={}},{},{};
        self.shown,self.copies,self.sources=result,copies,sources;
    end;
    local rows,count=result.rows,0;
    for key,row in pairs(self.rows) do
        local shown=copies[key];
        if shown and sources[key]==row then clear(shown);
        else shown={};copies[key],sources[key]=shown,row; end;
        for field,value in pairs(row) do shown[field]=value; end;
        count=count+1;rows[count]=shown;
    end;
    for index=#rows,count+1,-1 do rows[index]=nil; end;
    for key in pairs(copies) do if not self.rows[key] then copies[key],sources[key]=nil,nil; end;end;
    table.sort(rows,by_key);
    result.valid,result.version,result.capabilities=self.valid,self.version,self.capabilities;
    self:project(result,now);
    return result;
end

-- Two lists take turns, as the tracker's do: the one handed back now is emptied at the next drain, so its readers read
-- it within this refresh only.
function methods:drain_events()
    local result,spare=self.events,self.spare_events;
    clear(spare);
    self.events,self.spare_events=spare,result;
    return result;
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
