local client=require('core.client');
local memory=AshitaCore:GetMemoryManager();
local player,party=memory:GetPlayer(),memory:GetParty();
local member_id,member_index,member_active=2000,0x401,true;
local entities={[0x400]=1001,[0x401]=2000};
party.GetMemberServerId=function(_,slot) return slot==0 and 1001 or slot==1 and member_id or 0;end;
party.GetMemberZone=function() return 102;end;
party.GetMemberTargetIndex=function(_,slot) return slot==0 and 0x400 or member_index;end;
party.GetMemberName=function(_,slot) return slot==0 and 'Tester' or 'Member '..member_id;end;
party.GetMemberIsActive=function(_,slot) if slot==0 then return true;end;return member_active;end;
memory.GetEntity=function() return {GetServerId=function(_,index) return entities[index] or 0;end};end;
memory.GetTarget=function() return {GetTargetIndex=function() return 0;end};end;
AshitaCore.GetMemoryManager=function() return memory;end;
local snapshot=client.read(1);assert(snapshot.valid and #snapshot.party==1);
member_active=false;snapshot=client.read(2);
assert(#snapshot.party==0 and not snapshot.entities[member_id],'A successful false activity flag means inactive, not unavailable');
member_active=0;assert(#client.read(3).party==0);
member_active=nil;assert(#client.read(4).party==1,'An unavailable activity API keeps the established identity fallback');
member_active=true;
local packet=MOCK.bytes(244);MOCK.put(packet,4,4,member_id);MOCK.put(packet,8,2,member_index);
for i=0,31 do packet[20+i]=255;end;packet[20]=33;
snapshot=client.read(5);member_active=false;
client.accept(MOCK.packet(0x076,packet),6,snapshot);
member_active=true;snapshot=client.read(7);
assert(not snapshot.party[1].valid,'An inactive member cannot seed a native status packet cache');

-- Snapshot-fed identities obey the same cache bound as resolved targets.
client.reset();snapshot=client.read(8);
assert(client.resolve(2000).name=='Member 2000');
for i=1,140 do
    member_id,member_index=2000+i,0x401+i;entities[member_index]=member_id;
    snapshot=client.read(8+i*0.1);
end;
assert(client.resolve(2000).name==nil,'Old party identities are evicted even without any target-resolution inserts');
assert(client.resolve(member_id).name=='Member '..member_id,'The current party identity remains available');

-- Duration modifiers are captured in the packet callback, never on unrelated actions.
local observer=require('core.observer');local catalog=require('core.catalog');
local samples,targets=0,{};
local original_sample,original_decode,original_duration=client.sample_modifiers,observer.decode,catalog.duration;
client.sample_modifiers=function(value)
    samples=samples+1;assert(value==snapshot);
    return {items={},buffs={},merits={},level=75,job=5,complete=true};
end;
catalog.duration=function(rule,id,effect,sample)
    if sample then targets[#targets+1]=sample.target_self;end;
    return original_duration(rule,id,effect,sample);
end;
snapshot.id=1001;snapshot.entities[1001]={id=1001,name='Tester',kind='player'};
local action;
observer.decode=function() return action;end;
local incoming={id=0x028,data='',size=0};
local function run(category,id,rows,actor)
    action={category=category,id=id,actor=actor or 1001,rows=rows};
    return observer.read(incoming,30,snapshot);
end;
assert(#run(1,0,{{target=member_id,message=1,param=40}})==0 and samples==0);
assert(#run(4,58,{{target=member_id,message=85,param=4}})==0 and samples==0);
assert(#run(4,260,{{target=member_id,message=341,param=13}})==1 and samples==0);
assert(#run(4,57,{{target=member_id,message=230,param=0}})==0 and samples==0);
assert(#run(4,57,{{target=0,message=230,param=33}})==0 and samples==0);
local events=run(4,57,{{target=1001,message=230,param=33},{target=member_id,message=230,param=33}});
assert(#events==2 and samples==1 and events[1].duration==180 and events[2].duration==180);
assert(targets[1]==true and targets[2]==false,'One synchronous equipment snapshot still receives each recipient context');
events=run(4,57,{{target=1001,message=230,param=33}},member_id);
assert(#events==1 and samples==1,'Another actor never receives local equipment modifiers');
events=run(1,0,{{target=member_id,message=1,param=40,added=160,added_param=3}});
assert(#events==1 and samples==2 and events[1].duration==nil,'Own added statuses retain their existing modifier path');
events=run(1,0,{{target=member_id,message=1,param=40,reaction=374,reaction_param=9}});
assert(#events==1 and samples==2,'Untimed reaction statuses do not need equipment');
client.sample_modifiers,observer.decode,catalog.duration=original_sample,original_decode,original_duration;

-- Reused ready observations retain explicit-zero and unavailable distinctions.
local raw,invalid=0,false;
local manager={GetSpellTimer=function(_,id) if id==2 then if invalid then return nil;end;return raw;end;return 0;end};
memory.GetRecast=function() return manager;end;
memory.GetPlayer=function() return nil;end;
-- The client names spell 2, so its timer is the one read.
local resources={GetSpellById=function(_,id) return id==2 and {Name={'Cure'}} or nil;end};
AshitaCore.GetResourceManager=function() return resources;end;
local recasts=require('core.recasts');local a,b=recasts.new(),recasts.new();
snapshot={valid=true,id=1001,zone=102,job=5};
local options={abilities=false,items=false};
a:update(snapshot,100,options);b:update(snapshot,100,options);
raw=600;b:update(snapshot,100.1,options);
assert(#b:drain_events()==1 and #a:view(100.1).rows==0,'One reader cannot mutate another reader\'s ready sample');
a:update(snapshot,100.1,options);assert(#a:drain_events()==1);
raw=0;a:update(snapshot,100.2,options);assert(a:drain_events()[1].kind=='ready');
invalid=true;a:update(snapshot,100.3,options);assert(#a:drain_events()==0);
invalid=false;raw=600;a:update(snapshot,100.4,options);
assert(#a:drain_events()==0 and a:view(100.4).rows[1].total==nil,'Unreadable-to-active recovery stays a quiet unknown-duration baseline');
