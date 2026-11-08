-- Who is in the party and alliance, where they are and their jobs, from the client. A value it can't read stays nil.
local roster = {};
local client = require('core.client');
local zone_names = {};
-- pcall(index_of, object, key) guards a lookup without making a closure for it.
local function index_of(object, key) return object[key]; end
local function call(object, method, ...)
    if not object then return nil; end
    local ok, fn = pcall(index_of, object, method);
    if not ok or type(fn) ~= 'function' then return nil; end
    local success, value = pcall(fn, object, ...);
    if success then return value; end
end
local function number(value, maximum, minimum)
    if type(value)=='number' and value==value and value>= (minimum or 0) and value<=maximum
        and value==math.floor(value) then return value; end
end
local function truth(value) return value==true or value==1; end
local function zone_name(zone, now)
    if not zone or zone > 1023 then return nil; end
    local entry = zone_names[zone];
    if entry and (entry.name or now < entry.retry) then return entry.name; end
    local name = call(call(AshitaCore, 'GetResourceManager'), 'GetString', 'zones.names', zone);
    if type(name) == 'string' and #name <= 128 and not name:find('[%c]') then
        name = name:match('^%s*(.-)%s*$');
        if name == '' or name == '.' then name = nil; end
    else name = nil; end
    zone_names[zone] = { name = name, retry = now + 30 };
    return name;
end

function roster.read(now, snapshot)
    snapshot=snapshot or client.read(now);
    local out={valid=snapshot.valid==true,id=snapshot.id,zone=snapshot.zone,members={},
        typing=snapshot.chat_open==true,in_event=snapshot.in_event==true,map=snapshot.map==true,hidden=snapshot.hidden==true};
    if not out.valid then return out; end
    local memory=call(AshitaCore,'GetMemoryManager');
    local party=call(memory,'GetParty');
    if call(party,'GetMemberServerId',0)~=out.id or call(party,'GetMemberZone',0)~=out.zone then
        out.valid=false; return out;
    end
    local shared=client.roster_members and client.roster_members(snapshot,now);
    local seen={};
    for slot=0,17 do
        local identity=shared and shared[slot];
        local id=number(call(party,'GetMemberServerId',slot),4294967295,1);
        local active;
        if shared and slot~=0 then
            active=identity~=nil and identity.id==id;
        else active=call(party,'GetMemberIsActive',slot); end
        if identity and identity.id~=id then active=false; end
        if id and not seen[id] and (active==nil or truth(active)) then
            seen[id]=true;
            local zone=number(identity and identity.zone or call(party,'GetMemberZone',slot),65535,1);
            local zone2=number(call(party,'GetMemberZone2',slot),65535);
            local same_zone=zone~=nil and zone==out.zone;
            local available=same_zone and (zone2==nil or zone2==0);
            local updated=call(party,'GetMemberLastUpdatedTimestamp',slot);
            -- Someone out of the zone, or a slot the client hasn't filled yet, can hold an old job.
            local current=available and (updated==nil or number(updated,4294967295,1)~=nil);
            local name=identity and identity.name or call(party,'GetMemberName',slot);
            local row={id=id,slot=slot,group=math.floor(slot/6)+1,
                -- A member whose name hasn't come yet has none, so the displays show their own fallback, never the id.
                name=type(name)=='string' and name~='' and name or nil,zone=zone,active=true,
                same_zone=same_zone,available=available};
            row.scope=slot==0 and 'self' or row.group==1 and 'party' or 'alliance';
            row.zone_name = zone_name(zone, now);
            row.job=current and number(call(party,'GetMemberMainJob',slot),18,1) or nil;
            row.subjob=current and number(call(party,'GetMemberSubJob',slot),18,1) or nil;
            if slot == 0 then
                row.job = row.job or number(snapshot.job, 18, 1);
                if current and row.subjob == nil then
                    row.subjob = number(call(call(memory, 'GetPlayer'), 'GetSubJob'), 18, 1);
                end
            end
            out.members[#out.members+1]=row;
        end
    end
    if shared and (call(party,'GetMemberServerId',0)~=out.id or call(party,'GetMemberZone',0)~=out.zone) then
        out.valid,out.members=false,{};
    end
    return out;
end

function roster.reset() zone_names = {}; end
return roster;
