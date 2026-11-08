local store = require('core.store');
package.loaded['core.clock']={available=function() return true; end,get_game_time_raw=function() return 1000; end};
local event_scan,interface_scan,focus_scan=0x110000,0x120000,0x130000;
local interface,event_flag,menu,header=0x210000,0x220000,0x230000,0x240000;
local memory={
    [event_scan+1]=event_flag,[interface_scan+10]=interface,[focus_scan]=interface+0x54,
    [interface+0xB4]=0,[event_flag]=0,[interface+0x54]=0,[menu+4]=header,[header+0x4E]=0x2070616D,
};
local missing,unreadable,failed_read;
local finds,native_reads,status_reads,roster_reads,entity_reads=0,0,0,0,0;
local id,zone,zoning,chat=1001,102,false,false;
local stats={GetIsZoning=function() return zoning; end};
for _,name in ipairs({'GetStatusIcons','GetStatusTimers','GetBuffs','GetMainJob'}) do
    stats[name]=function() status_reads=status_reads+1; error('Visibility must not scan player status.'); end;
end;
local party={
    GetMemberServerId=function(_,slot) if slot~=0 then roster_reads=roster_reads+1; end; return id; end,
    GetMemberZone=function(_,slot) if slot~=0 then roster_reads=roster_reads+1; end; return zone; end,
};
AshitaCore.GetMemoryManager=function() return {
    GetParty=function() return party; end,GetPlayer=function() return stats; end,
    GetEntity=function() entity_reads=entity_reads+1; error('Visibility must not scan entities.'); end,
}; end;
AshitaCore.GetChatManager=function() return {IsInputOpen=function() return chat; end}; end;
ashita.memory.find=function(_,_,pattern,offset)
    finds=finds+1;
    local which=pattern:sub(1,2)=='A0' and 'event' or pattern:sub(1,8)=='8B442404' and 'interface' or 'focus';
    if missing==which then return 0; end;
    if which=='event' then assert(offset==0); return event_scan; end;
    if which=='interface' then assert(offset==0); return interface_scan; end;
    assert(offset==16); return focus_scan;
end;
local function read(at)
    native_reads=native_reads+1;
    if at==failed_read then error('Fixture unreadable native address.'); end;
    if at==unreadable then return nil; end;
    return memory[at];
end;
ashita.memory.read_uint8,ashita.memory.read_uint32=read,read;
ashita.memory.write_uint8=function() error('Visibility is read-only.'); end;
ashita.memory.write_uint32=function() error('Visibility is read-only.'); end;
-- Every address this fixture maps is on a readable page.
local function fresh()
    package.loaded['core.client']=nil;
    local loaded=require('core.client');loaded._set_pages(function() return true; end);
    return loaded;
end;
local snapshot={valid=true,id=id,zone=zone,hidden=true,map=true,in_event=true,chat_open=true};
local client=fresh();
assert(client.visibility(nil)==nil and client.visibility({valid=false})==nil and finds==0,
    'Unknown previous identity performs no native discovery.');
local before=store.copy(snapshot);
local current=assert(client.visibility(snapshot));
assert(current.valid and current.id==id and current.zone==zone and not current.hidden and not current.map
    and not current.in_event and not current.chat_open, 'Current visibility replaces stale snapshot flags.');
assert(store.equal(snapshot,before), 'Visibility does not mutate the previous snapshot.');
local previous_finds=finds;
assert(client.visibility(snapshot));
assert(finds==previous_finds and finds==3, 'Visibility pointers are discovered once.');

for _,value in ipairs({false,0}) do zoning=value; assert(client.visibility(snapshot)); end;
for _,value in ipairs({true,1}) do zoning=value; assert(client.visibility(snapshot)==nil); end;
zoning=nil; assert(client.visibility(snapshot)==nil,'Unknown zoning state cannot authorize replacement.');
zoning=false;
for _,key in ipairs({'id','zone'}) do
    local altered=store.copy(snapshot); altered[key]=altered[key]+1;
    assert(client.visibility(altered)==nil,'A stale '..key..' is rejected.');
end;
for _,value in ipairs({0,-1,1.5,math.huge}) do
    id=value; local altered=store.copy(snapshot); altered.id=value;
    assert(client.visibility(altered)==nil,'Malformed current identity remains unknown.');
end;
id=snapshot.id;
zone=0; assert(client.visibility(snapshot)==nil); zone=snapshot.zone;

memory[interface+0xB4]=1; current=assert(client.visibility(snapshot)); assert(current.hidden);
memory[interface+0xB4]=0; memory[event_flag]=1; current=assert(client.visibility(snapshot)); assert(current.in_event);
memory[event_flag]=0; memory[interface+0x54]=menu; current=assert(client.visibility(snapshot)); assert(current.map);
memory[header+0x4E]=0x746F6F6C; current=assert(client.visibility(snapshot)); assert(not current.map,'An ordinary selected menu is not a map.');
for _,at in ipairs({interface+0xB4,event_flag,interface+0x54,menu+4,header+0x4E}) do
    unreadable=at; assert(client.visibility(snapshot)==nil,'Missing native visibility leaves the client visible.'); unreadable=nil;
    failed_read=at; assert(client.visibility(snapshot)==nil,'Failed native reads leave the client visible.'); failed_read=nil;
end;
memory[menu+4]=0; assert(client.visibility(snapshot)==nil,'An unresolved focused menu cannot be assumed safe.'); memory[menu+4]=header;
memory[interface+0x54]=0;
for _,value in ipairs({true,1,3}) do chat=value; assert(client.visibility(snapshot).chat_open); end;
for _,value in ipairs({false,0,2}) do chat=value; assert(not client.visibility(snapshot).chat_open); end;
chat=false;

for _,which in ipairs({'event','interface','focus'}) do
    missing=which; local unsupported=fresh();
    assert(unsupported.visibility(snapshot)==nil,'An undiscovered '..which..' pointer cannot authorize replacement.');
end;
missing=nil; memory[focus_scan]=interface+0x58;
assert(fresh().visibility(snapshot)==nil,'A focus pointer from another interface is rejected.');
memory[focus_scan]=interface+0x54;
client=fresh(); assert(client.visibility(snapshot));
local packet=MOCK.bytes(52); MOCK.put(packet,4,4,id); MOCK.put(packet,0x30,2,zone);
client.accept(MOCK.packet(0x00A,packet),1,snapshot);
assert(client.visibility(snapshot)==nil,'A zone packet invalidates visibility until status is ready.');
local ready=MOCK.bytes(200); MOCK.put(ready,4,2,9);
client.accept(MOCK.packet(0x063,ready),2,snapshot);
assert(client.visibility(snapshot),'Matching identity can be prepared after the zone readiness packet.');
MOCK.put(packet,4,4,id+1); client.accept(MOCK.packet(0x00A,packet),3,snapshot);
client.accept(MOCK.packet(0x063,ready),4,snapshot);
assert(client.visibility(snapshot)==nil,'A pending new character cannot reuse the old character snapshot.');
client.reset(); assert(client.visibility(snapshot));
-- Inside a Present the flags are read once: the overhead takes what the check between refreshes read, and the next
-- Present reads them again. Outside one, as for a buff cancel, every read is fresh.
local before=native_reads;
client.frame_begin();
assert(client.visibility(snapshot));
local first=native_reads-before;
assert(first>0,'Fixture: the flags were read.');
local _,hidden=client.world_flags();
assert(native_reads-before==first and hidden==0,'The overhead takes the flags this Present read.');
memory[interface+0xB4]=1;
assert(not client.visibility(snapshot).hidden and native_reads-before==first,'A second check in one Present reads nothing.');
client.frame_end();
before=native_reads;
assert(client.visibility(snapshot).hidden and native_reads-before==first,'Outside a Present the flags are read fresh.');
client.frame_begin();
_,hidden=client.world_flags();
assert(hidden==1,'The next Present reads them again.');
client.frame_end();
memory[interface+0xB4]=0;
assert(status_reads==0 and roster_reads==0 and entity_reads==0 and native_reads>0,
    'The before-scene check reads only self identity and native visibility, never effects or entity lists.');
assert(#MOCK.commands==0);
