-- A song sung on Bob whose copy of it no 0x028 labelled (the singer was out of range, or Vantage loaded with it
-- up). Phoenix's ApplyBardEffect replaces the copy of the same tier, so a resing of it leaves one copy; the
-- singer's own tick can still list the replaced copy beside the new one, and Bob's next tick lists one. That is
-- a renewal: no gain, and the copy takes the song's caster, mine and countdown, so later resings stay labelled.
-- A song of another tier is a new copy: its gain comes once no listing showed the count stay.
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
-- Valor Minuet IV (397, tier 4) or III (396, tier 3) from a singer, on the singer and on Bob.
local function sing(singer,spell)
    return action(4,spell,{{id=singer,rows={{message=230,param=198}}},{id=1002,rows={{message=266,param=198}}}},singer);
end
local queue,snap={},nil;
local function packet(e,t) for _,o in ipairs(observer.read(e,t,snap)) do queue[#queue+1]=o; end end
local function refresh(t)
    snap=client.read(t);
    tracker:observe(queue,t,snap); queue={};
    tracker:reconcile(snap,t);
    local view=tracker:view(t,{},snap);
    local ev={};
    for _,e in ipairs(tracker:drain_events()) do if e.entity_id==1002 and e.effect==198 then ev[#ev+1]=e.kind; end end
    local rows={};
    for _,r in ipairs(view.rows) do if r.entity_id==1002 and r.effect==198 then rows[#rows+1]=r; end end
    return rows,table.concat(ev,',');
end
local function settle(from,to,list)
    local all={};
    for t=from,to,0.25 do packet(group(list,{}),t); local _,ev=refresh(t+0.05); if ev~='' then all[#all+1]=ev; end end
    return table.concat(all,',');
end
local function labels(rows)
    local out={};
    for _,r in ipairs(rows) do out[#out+1]=tostring(r.source)..'/'..tostring(r.mine)..'/'..tostring(r.remaining and math.floor(r.remaining)); end
    return table.concat(out,' ');
end

-- Bob's Minuet is first seen in his listing.
refresh(0);
packet(group({198},{}),0.1);
local rows,events=refresh(0.2);
assert(#rows==1 and rows[1].source==nil,'Fixture: an unlabelled Minuet on Bob.');
settle(1,3,{198});
-- The player resings it. One reply holds the 0x028 and the singer's 0x076 listing both copies; Bob's next tick
-- lists one.
packet(sing(1001,397),10.0); packet(group({198,198},{}),10.0);
local _,first=refresh(10.05);
packet(group({198},{}),10.4);
rows,events=refresh(10.45);
-- Read before the next refresh, which hands out the copy again with its time left then.
assert(#rows==1 and rows[1].source==1001 and rows[1].mine and math.floor(rows[1].remaining)>=119,
    'The copy takes the labels of the song: '..labels(rows));
local after=settle(11,14,{198});
assert(first=='' and events=='refresh' and after=='','A resing of the copy Bob has is one renewal: '..first..'/'..events..'/'..after);
-- The next resing finds that labelled copy.
packet(sing(1001,397),120.0); packet(group({198,198},{}),120.0);
_,first=refresh(120.05);
packet(group({198},{}),120.4);
rows,events=refresh(120.45);
assert(first..events=='refresh' and #rows==1 and rows[1].mine,'And the next resing renews it: '..first..'/'..events);

-- The 0x028 alone first, then the singer's listing, then Bob's.
tracker=require('core.tracker').new();
packet(group({198},{}),200.0); refresh(200.05); settle(201,203,{198});
packet(sing(1003,397),210.0);
_,first=refresh(210.05);
packet(group({198,198},{}),210.1);
local _,second=refresh(210.15);
packet(group({198},{}),210.4);
rows,events=refresh(210.45);
after=settle(211,214,{198});
assert(first..second..after=='' and events=='refresh' and #rows==1 and rows[1].source==1003 and not rows[1].mine,
    'Read packet by packet, it is the same renewal, credited to Carol: '..first..'/'..second..'/'..events..'/'..after..' '..labels(rows));

-- Minuet III from Carol on Bob's unlabelled Minuet (IV): Bob keeps both. The gain comes, once.
tracker=require('core.tracker').new();
packet(group({198},{}),300.0); refresh(300.05); settle(301,303,{198});
packet(sing(1003,396),310.0); packet(group({198,198},{}),310.0);
_,first=refresh(310.05);
packet(group({198,198},{}),310.4);
_,second=refresh(310.45);
after=settle(311,314,{198,198});
rows=refresh(314.5);
assert((first..second..','..after):gsub('^,',''):gsub(',$','')=='gain' and #rows==2,
    'A song of another tier is a new copy, gained once: '..first..'/'..second..'/'..after..' rows '..#rows);
local credited=0;
for _,r in ipairs(rows) do if r.source==1003 and r.spell==396 then credited=credited+1; end end
assert(credited==1,'The new copy keeps its labels: '..labels(rows));
