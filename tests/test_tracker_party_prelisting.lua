-- Phoenix sends a 0x076 from the PostTick of any member whose own icons changed, with every member's cache as
-- it is then (CCharEntity::PostTick -> CParty::PushEffectsPacket). A member ticking before the caster sends
-- Bob's icons from before Dave's Haste, in the same reply as Dave's 0x028; Bob already ticked, so his 0x076
-- with Haste comes a tick later. That earlier listing must not remove the new row, and the row keeps its
-- caster, spell and estimate. Real parsers: client.accept for 0x076, observer.read for 0x028.
local client=require('core.client');
local observer=require('core.observer');
local tracker=require('core.tracker').new();
local mm=AshitaCore:GetMemoryManager();
AshitaCore.GetMemoryManager=function() return mm; end;
local party=mm:GetParty();
MOCK.player.server_id=1001; MOCK.player.zone=102; MOCK.player.index=0x400;
local members={[0]={id=1001,index=0x400,zone=102},[1]={id=1002,index=0x401,zone=102},[2]={id=1003,index=0x402,zone=102}};
for name,k in pairs({GetMemberServerId='id',GetMemberTargetIndex='index',GetMemberZone='zone'}) do
    party[name]=function(_,slot) return members[slot] and members[slot][k] or 0; end;
end
party.GetMemberName=function(_,slot) return ({[0]='Tester','Bob','Dave'})[slot] or ''; end;
party.GetMemberIsActive=function(_,slot) return members[slot] and 1 or 0; end;
party.GetMemberHPPercent=function() return 100; end;
party.GetStatusIconsServerId=function() return 0; end;
party.GetStatusIconsTargetIndex=function() return 0; end;
mm.GetEntity=function() return {GetServerId=function() return 0;end,GetName=function() return '';end,GetSpawnFlags=function() return 0;end};end;
local function putbits(bytes, offset, length, value)
    for i = 0, length - 1 do
        local at = offset + i;
        if math.floor(value / 2 ^ i) % 2 == 1 then bytes[math.floor(at / 8)] = bytes[math.floor(at / 8)] + 2 ^ (at % 8); end
    end
end
local function action(category, id, targets, actor)
    local bytes, at = MOCK.bytes(2048), 150;
    putbits(bytes, 40, 32, actor); putbits(bytes, 72, 6, #targets);
    putbits(bytes, 82, 4, category); putbits(bytes, 86, 32, id);
    for _, target in ipairs(targets) do
        putbits(bytes, at, 32, target.id); putbits(bytes, at + 32, 4, #target.rows); at = at + 36;
        for _, row in ipairs(target.rows) do
            putbits(bytes, at + 27, 17, row.param or 0); putbits(bytes, at + 44, 10, row.message or 0); at = at + 85;
            at = at + 1; at = at + 1;
        end
    end
    bytes.n = math.ceil(at / 8);
    return MOCK.packet(0x028, bytes);
end
-- 0x076 listing Bob (row 0) and Dave (row 1) with the given effect lists.
local function group(bob, dave)
    local p=MOCK.bytes(244);
    local rows={{1002,0x401,bob},{1003,0x402,dave}};
    for r,info in ipairs(rows) do
        local start=4+(r-1)*48;
        MOCK.put(p,start,4,info[1]); MOCK.put(p,start+4,2,info[2]);
        for i=0,31 do p[start+16+i]=255; end
        for i,e in ipairs(info[3]) do p[start+16+i-1]=e; end
    end
    return MOCK.packet(0x076,p);
end
local queue,snap={},nil;
local alerts=require('core.alerts').new();
local rules={
    {id='gain',enabled=true,event='gain',effect=0,scope='party',cooldown=0,duration=30,visual=true},
    {id='removed',enabled=true,event='removed',effect=0,scope='party',cooldown=0,duration=30,visual=true},
};
local function packet(e,t)
    for _,o in ipairs(observer.read(e,t,snap)) do queue[#queue+1]=o; end
end
local function refresh(t)
    snap=client.read(t);
    tracker:observe(queue,t,snap); queue={};
    tracker:reconcile(snap,t);
    local view=tracker:view(t,{},snap);
    local events=tracker:drain_events();
    alerts:update(view,events,rules,t,{});
    local fired={};
    for _,notice in ipairs(alerts:drain(t)) do fired[notice.rule_id]=(fired[notice.rule_id] or 0)+1; end
    local ev={};
    for _,e in ipairs(events) do if e.entity_id==1002 then ev[#ev+1]=e.kind..':'..e.effect; end end
    local rows={};
    for _,r in ipairs(view.rows) do if r.entity_id==1002 then rows[#rows+1]=r; end end
    return rows,table.concat(ev,','),fired;
end
local function row_of(rows,effect) for _,r in ipairs(rows) do if r.effect==effect then return r; end end end

refresh(0);
packet(group({},{}),0.1);
refresh(0.2);
-- One reply: the 0x076 another member's tick pushed before Dave's cast, then Dave's 0x028 Haste on Bob.
packet(group({},{}),0.5); packet(action(4,57,{{id=1002,rows={{message=230,param=33}}}},1003),0.5);
local rows,events,fired=refresh(0.55);
assert(events=='gain:33' and not fired.removed,'A listing from before the cast removes nothing: '..events);
local haste=row_of(rows,33);
assert(haste and haste.source==1003 and haste.spell==57,'The new row stays, credited to Dave.');
-- Bob's own 0x076 at his next tick lists the Haste.
packet(group({33},{}),0.9);
rows,events,fired=refresh(0.95);
haste=row_of(rows,33);
assert(events=='' and not fired.gain,"Bob's own listing shows a Haste already gained: "..events);
assert(haste and haste.source==1003 and haste.spell==57 and haste.remaining and haste.remaining>170,
    'And it keeps its caster, spell and estimate.');
-- A listing from after the cast that still lacks it drops it, as a removal nothing reported.
packet(action(4,43,{{id=1002,rows={{message=230,param=40}}}},1003),5.0);
rows,events=refresh(5.05);
assert(events=='gain:40','Protect lands: '..events);
packet(group({33},{}),5.4);
rows,events=refresh(5.45);
assert(events=='removed:40' and not row_of(rows,40),'A listing that came after the cast and lacks it removes it: '..events);
