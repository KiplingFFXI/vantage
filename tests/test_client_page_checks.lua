-- Every raw read the client reader makes checks its page first: an address on a page that can't be read is
-- never read, and reads as nothing. Without a page check at all, nothing is read.
local event_scan,interface_scan,focus_scan=0x110000,0x120000,0x130000;
local interface,event_flag,menu,header=0x210000,0x220000,0x230000,0x240000;
local memory={[event_scan+1]=event_flag,[interface_scan+10]=interface,[focus_scan]=interface+0x54,
    [interface+0xB4]=0,[event_flag]=0,[interface+0x54]=menu,[menu+4]=header,[header+0x4E]=0x2070616D};
local unreadable,reads,checks={},{},{};
AshitaCore.GetMemoryManager=function() return {
    GetParty=function() return {GetMemberServerId=function() return 1001; end,GetMemberZone=function() return 102; end}; end,
    GetPlayer=function() return {GetIsZoning=function() return false; end}; end,
}; end;
ashita.memory.find=function(_,_,pattern)
    if pattern:sub(1,2)=='A0' then return event_scan; end;
    return pattern:sub(1,8)=='8B442404' and interface_scan or focus_scan;
end;
local function read(at)
    assert(not unreadable[at],string.format('0x%X is on an unreadable page and must not be read.',at));
    reads[#reads+1]=at;
    return memory[at];
end;
ashita.memory.read_uint8,ashita.memory.read_uint32=read,read;
local function pages(at,size,writable)
    assert(writable==false,'The client reader only reads.');
    checks[#checks+1]={at,size};
    return not unreadable[at];
end;
local function fresh(valid)
    package.loaded['core.client']=nil;
    local client=require('core.client');
    client._set_pages(valid);
    return client;
end;
local snapshot={valid=true,id=1001,zone=102};
local client=fresh(pages);
local seen=client.visibility(snapshot);
assert(seen and seen.map and not seen.hidden and not seen.in_event,'Fixture: readable pages give the menu flags.');
for _,at in ipairs(reads) do
    local checked=false;
    for _,check in ipairs(checks) do checked=checked or check[1]==at; end;
    assert(checked,string.format('0x%X was read after its page was checked.',at));
end;
assert(#checks>=#reads);
for _,at in ipairs({interface+0xB4,event_flag,interface+0x54,menu+4,header+0x4E}) do
    unreadable[at]=true;reads={};
    assert(client.visibility(snapshot)==nil,string.format('A flag on an unreadable page at 0x%X is not taken for false.',at));
    unreadable[at]=nil;
end;
-- The pointers found at load are page checked too.
unreadable[interface_scan+10]=true;
client=fresh(pages);
assert(not client.capabilities().hidden,'An unreadable pointer is not taken for an address.');
unreadable={};

-- No page check at all: nothing is read.
reads={};
ashita.memory.read_uint8,ashita.memory.read_uint32=read,read;
client=fresh(nil);
assert(client.visibility(snapshot)==nil and #reads==0,'Without a page check nothing is read.');
return 'Client reads are page checked';
