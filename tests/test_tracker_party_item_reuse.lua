-- A party member using a Reraise Earring again (Phoenix reraise_earring.lua: delStatusEffect, addStatusEffect,
-- messageBasic 205). Both messages go to that member alone (lua_base_entity.cpp messageBasic; the wear-off goes
-- to the owner and its origin, who is the member), and the item's 0x028 has no message. What the party sees is
-- their 0x076 from their own PostTick listing the deleted copy beside the new one, maybe once more from another
-- member's PostTick, and their next tick's listing one copy (party.cpp PushEffectsPacket). No timers, no caster.
-- That is no gain and no removal, and the row keeps its key. A second copy that stays (an item enchantment
-- wearing the icon of a buff already up, haste_belt.lua) is a gain, once the listings show it stay.
local client=require('core.client');
local observer=require('core.observer');
local alerts=require('core.alerts').new();
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
local BOB,DAVE,RERAISE,HASTE=1002,1003,113,33;
local rules={};
for _,event in ipairs({'gain','removed','missing'}) do
    rules[#rules+1]={id=event,enabled=true,event=event,effect=0,scope='party',cooldown=0,duration=30,visual=true};
end;
rules[#rules+1]={id='missing_reraise',enabled=true,event='missing',effect=RERAISE,scope='party',cooldown=0,duration=30,visual=true};
local function putbits(bytes, offset, length, value)
    for i = 0, length - 1 do
        local at = offset + i;
        if math.floor(value / 2 ^ i) % 2 == 1 then bytes[math.floor(at / 8)] = bytes[math.floor(at / 8)] + 2 ^ (at % 8); end
    end
end
local function action(category, id, target, message, param, actor)
    local bytes, at = MOCK.bytes(512), 150;
    putbits(bytes, 40, 32, actor); putbits(bytes, 72, 6, 1);
    putbits(bytes, 82, 4, category); putbits(bytes, 86, 32, id);
    putbits(bytes, at, 32, target); putbits(bytes, at + 32, 4, 1); at = at + 36;
    putbits(bytes, at + 27, 17, param); putbits(bytes, at + 44, 10, message); at = at + 87;
    bytes.n = math.ceil(at / 8);
    return MOCK.packet(0x028, bytes);
end
-- 0x076 listing Bob (row 0) and Dave (row 1).
local function group(bob, dave)
    local p=MOCK.bytes(244);
    local rows={{BOB,0x401,bob},{DAVE,0x402,dave}};
    for r,info in ipairs(rows) do
        local start=4+(r-1)*48;
        MOCK.put(p,start,4,info[1]); MOCK.put(p,start+4,2,info[2]);
        for i=0,31 do p[start+16+i]=255; end
        for i,e in ipairs(info[3]) do p[start+16+i-1]=e; end
    end
    return MOCK.packet(0x076,p);
end
local queue,snap={},nil;
local function packet(e,t) for _,o in ipairs(observer.read(e,t,snap)) do queue[#queue+1]=o; end end
-- Bob's rows of the effect, the kinds of their events, and his alerts.
local function refresh(t,effect)
    snap=client.read(t);
    tracker:observe(queue,t,snap); queue={};
    tracker:reconcile(snap,t);
    local view=tracker:view(t,{},snap);
    local events=tracker:drain_events();
    alerts:update(view,events,rules,t,{enabled=true});
    local ev,fired,rows={},{},{};
    for _,e in ipairs(events) do if e.entity_id==BOB and e.effect==effect then ev[#ev+1]=e.kind; end end
    for _,n in ipairs(alerts:drain(t)) do if n.entity_id==BOB then fired[#fired+1]=n.rule_id; end end
    for _,r in ipairs(view.rows) do if r.entity_id==BOB and r.effect==effect and r.present~=false then rows[#rows+1]=r; end end
    return rows,table.concat(ev,','),table.concat(fired,',');
end
local function settle(from,to,list,effect)
    local all,fired={},{};
    for t=from,to,0.25 do
        packet(group(list,{}),t);
        local _,ev,f=refresh(t+0.05,effect);
        if ev~='' then all[#all+1]=ev; end
        if f~='' then fired[#fired+1]=f; end
    end
    return table.concat(all,','),table.concat(fired,',');
end

-- Bob's Reraise, first seen in his listing.
refresh(0,RERAISE);
packet(group({},{}),0.05); refresh(0.1,RERAISE);
settle(0.5,2,{},RERAISE);
packet(group({RERAISE},{}),3.0);
local rows,events,fired=refresh(3.05,RERAISE);
assert(#rows==1 and events=='gain' and fired=='gain','Fixture: Bob gains Reraise: '..events..' / '..fired);
local key=rows[1].key;
settle(4,9,{RERAISE},RERAISE);

-- He uses the earring: the item's 0x028 and his PostTick's 0x076 in one reply, another member's PostTick lists
-- both copies once more, and his next tick lists one.
packet(action(5,14790,BOB,0,0,BOB),10.0); packet(group({RERAISE,RERAISE},{}),10.0);
local two,first,first_fired=refresh(10.05,RERAISE);
packet(group({RERAISE,RERAISE},{}),10.2);
local _,second,second_fired=refresh(10.25,RERAISE);
packet(group({RERAISE},{}),10.4);
rows,events,fired=refresh(10.45,RERAISE);
local after,after_fired=settle(11,15,{RERAISE},RERAISE);
assert(#two==2 and first..second..events..after=='','Both copies are drawn while his listing shows them, with no gain and no removal: '
    ..#two..' rows, '..first..'/'..second..'/'..events..'/'..after);
assert(first_fired..second_fired..fired..after_fired=='','And no alert: '..first_fired..'/'..second_fired..'/'..fired..'/'..after_fired);
assert(#rows==1 and rows[1].key==key and rows[1].instance==1,'The row keeps its key: '..tostring(rows[1] and rows[1].key)..' vs '..key);

-- The same with nothing but the two listings, as when Bob is out of range of his 0x028.
packet(group({RERAISE,RERAISE},{}),20.0);
_,first,first_fired=refresh(20.05,RERAISE);
packet(group({RERAISE},{}),20.4);
rows,events,fired=refresh(20.45,RERAISE);
after,after_fired=settle(21,24,{RERAISE},RERAISE);
assert(first..events..after=='' and first_fired..fired..after_fired=='' and #rows==1 and rows[1].key==key,
    'Listings alone read the same: '..first..'/'..events..'/'..after..' alerts '..first_fired..fired..after_fired);

-- Dave's Haste on Bob, then Bob's Haste Belt: its enchantment wears the Haste icon beside it, and stays.
packet(action(4,57,BOB,230,HASTE,DAVE),30.0); packet(group({RERAISE,HASTE},{}),30.0);
rows,events=refresh(30.05,HASTE);
assert(#rows==1 and events=='gain' and rows[1].source==DAVE,'Fixture: Dave\'s Haste on Bob: '..events);
settle(31,34,{RERAISE,HASTE},HASTE);
packet(action(5,15290,BOB,0,0,BOB),40.0); packet(group({RERAISE,HASTE,HASTE},{}),40.0);
_,first,first_fired=refresh(40.05,HASTE);
packet(group({RERAISE,HASTE,HASTE},{}),40.4);
_,second,second_fired=refresh(40.45,HASTE);
after,after_fired=settle(41,43,{RERAISE,HASTE,HASTE},HASTE);
rows=refresh(43.5,HASTE);
local labelled=0;
for _,r in ipairs(rows) do if r.source==DAVE then labelled=labelled+1; end end
assert(first..second=='' and after=='gain' and first_fired..second_fired=='' and after_fired=='gain' and #rows==2 and labelled==1,
    'A second copy that stays is gained once the listings show it stay, and the copy of Dave keeps its labels: '..first..'/'..second
    ..'/'..after..' alerts '..first_fired..'/'..second_fired..'/'..after_fired);
