local client=require('core.client');
local roster=require('core.roster');
local memory=AshitaCore:GetMemoryManager();
local party=memory:GetParty();
local members,reads={},{};
for slot=0,17 do members[slot]={id=1001+slot,index=0x400+slot,zone=102,name='Member '..slot,active=true}; end
for method,key in pairs({GetMemberServerId='id',GetMemberTargetIndex='index',GetMemberZone='zone',GetMemberName='name',GetMemberIsActive='active'}) do
    party[method]=function(_,slot)
        reads[method]=(reads[method] or 0)+1;
        return members[slot] and members[slot][key];
    end;
end
party.GetMemberMainJob=function() return 5;end;
party.GetMemberLastUpdatedTimestamp=function() return 1;end;
AshitaCore.GetMemoryManager=function() return memory;end;
local function read_count(name) return reads[name] or 0;end
local snapshot=client.read(1);
reads={};
local result=roster.read(1,snapshot);
assert(result.valid and #result.members==18);
assert(read_count('GetMemberName')==0 and read_count('GetMemberTargetIndex')==0,'The same acquisition reuses every member name, and no index is read');
assert(read_count('GetMemberIsActive')==1 and read_count('GetMemberZone')==2,'Only self activity and the owner zone guards need another read');
assert(read_count('GetMemberServerId')==20,'Each slot ID is checked again before reading its jobs');
assert(result.members[2].name=='Member 1' and result.members[2].job==5);
assert(client.roster_members(snapshot,1)~=nil and client.roster_members(snapshot,1.1)==nil);

reads={};
result=roster.read(1.1,snapshot);
assert(result.valid and read_count('GetMemberName')==18,'A later read cannot reuse an old identity snapshot');
local copied=require('core.store').copy(snapshot);
assert(client.roster_members(copied,1)==nil,'Copying a snapshot does not authorize cached identities');
reads={};result=roster.read(1,copied);
assert(result.valid and read_count('GetMemberName')==18,'External snapshot callers keep their fresh SDK path');

snapshot=client.read(2);
members[1].id=9999;
result=roster.read(2,snapshot);
for _,member in ipairs(result.members) do assert(member.slot~=1,'A reused slot cannot attach new jobs to the cached member');end
members[1].id=1002;
members[2].active=false;members[3].id=1002;
snapshot=client.read(3);result=roster.read(3,snapshot);
assert(#result.members==16,'Inactive and duplicate members stay omitted');
for _,member in ipairs(result.members) do assert(member.slot~=2 and member.slot~=3);end
members[2].active=true;members[3].id=1004;

snapshot=client.read(4);
members[0].zone=103;
result=roster.read(4,snapshot);
assert(not result.valid and #result.members==0,'A changed owner zone rejects shared identities');
members[0].zone=102;
snapshot=client.read(5);
local job=party.GetMemberMainJob;
party.GetMemberMainJob=function(_,slot) if slot==17 then members[0].zone=103;end;return 5;end;
result=roster.read(5,snapshot);
assert(not result.valid and #result.members==0,'A zone change during the jobs read rejects the completed snapshot');
party.GetMemberMainJob=job;members[0].zone=102;
snapshot=client.read(6);client.reset();
assert(client.roster_members(snapshot,6)==nil,'Client reset discards shared identities');

