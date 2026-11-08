-- Refresh on the player renewed by an Always_Overwrite recast (Phoenix enhancing_spell.lua: delStatusEffect,
-- then addStatusEffect, then the 0x028). When the caster ticks after the player, the status packets with the
-- new copy come a tick later, so a refresh reads the wear-off and the cast alone. The tracker holds the row for
-- the recast; a 'missing' rule must not fire while it does, and a real wear-off still alerts at once.
local raw_time=1000;
package.preload['core.clock']=function() return {available=function() return true; end,get_game_time_raw=function() return raw_time; end}; end;
local client=require('core.client');
local observer=require('core.observer');
local stats=AshitaCore:GetMemoryManager():GetPlayer();
local buffs,icons,timers={},{},{};
stats.GetBuffs=function() return buffs; end;
stats.GetStatusIcons=function() return icons; end;
stats.GetStatusTimers=function() return timers; end;
local function list(ids,raws) for slot=0,31 do buffs[slot]=ids[slot+1] or 65535; icons[slot]=ids[slot+1] or 255; timers[slot]=raws[slot+1] or 0; end; end;
local SELF=MOCK.player.server_id;
local RDM=SELF+4;
local s=require('ui.defaults').make();
local rules={
    {id='missing',enabled=true,event='missing',effect=43,scope='self',cooldown=0,duration=30,visual=true},
    {id='removed',enabled=true,event='removed',effect=43,scope='self',cooldown=0,duration=30,visual=true},
    {id='gain',enabled=true,event='gain',effect=43,scope='self',cooldown=0,duration=30,visual=true},
};
local tracker,alerts,snap,queue,fired,kinds;
local function putbits(bytes, offset, length, value)
    for i = 0, length - 1 do
        local at = offset + i;
        if math.floor(value / 2 ^ i) % 2 == 1 then bytes[math.floor(at / 8)] = bytes[math.floor(at / 8)] + 2 ^ (at % 8); end
    end
end
local function feed(packet,t) for _,o in ipairs(observer.read(packet,t,snap)) do queue[#queue+1]=o; end; end;
local function p037(t) feed(MOCK.packet(0x037,MOCK.bytes(0x50)),t); end;
local function p063(t) local b=MOCK.bytes(200);MOCK.put(b,4,2,9);feed(MOCK.packet(0x063,b),t); end;
local function wear_off(t)
    local b=MOCK.bytes(28);
    MOCK.put(b,4,4,SELF);MOCK.put(b,8,4,SELF);MOCK.put(b,12,4,43);MOCK.put(b,24,2,206);
    feed(MOCK.packet(0x029,b),t);
end;
local function refresh_cast(actor,t)
    local bytes, at = MOCK.bytes(512), 150;
    putbits(bytes, 40, 32, actor); putbits(bytes, 72, 6, 1);
    putbits(bytes, 82, 4, 4); putbits(bytes, 86, 32, 109);
    putbits(bytes, at, 32, SELF); putbits(bytes, at + 32, 4, 1); at = at + 36;
    putbits(bytes, at + 27, 17, 43); putbits(bytes, at + 44, 10, 230); at = at + 87;
    bytes.n = math.ceil(at / 8);
    feed(MOCK.packet(0x028, bytes),t);
end;
local function present(t)
    local current=client.read(t,s);
    tracker:observe(queue,t,current);queue={};
    tracker:reconcile(current,t);
    snap=current;
    local view=tracker:view(t,s,current);
    local events=tracker:drain_events();
    alerts:update(view,events,rules,t,{enabled=true});
    local out={};
    for _,event in ipairs(events) do if event.effect==43 then kinds[#kinds+1]=event.kind; end; end;
    for _,notice in ipairs(alerts:drain(t)) do fired[#fired+1]=notice.rule_id; out[#out+1]=notice.rule_id..'='..notice.message; end;
    local rows={};
    for _,row in ipairs(view.rows) do if row.effect==43 then rows[#rows+1]=tostring(row.source)..(row.departing and '/departing' or '')..(row.recast and '/recast' or ''); end; end;
    return 'rows['..table.concat(rows,' ')..'] alerts['..table.concat(out,'; ')..']';
end;
local function now_raw() return raw_time*60; end;
local function start(caster)
    tracker,alerts,queue,fired,kinds=require('core.tracker').new(),require('core.alerts').new(),{},{},{};
    raw_time=1000; list({},{});
    snap=client.read(0,s); present(0); present(0.5);
    refresh_cast(caster,1);
    list({43},{now_raw()+150*60}); p037(1); p063(1);
    present(1.05);
    for t=2,60 do raw_time=1000+t; present(t); end;
    fired,kinds={},{};
end;

-- A: another caster, the player's status packets one datagram later (caster ticks after the player).
start(RDM);
raw_time=1060; wear_off(60.1); refresh_cast(RDM,60.1);
present(60.12);
local after_first=table.concat(fired,',');
raw_time=1060; list({43},{now_raw()+150*60}); p037(60.5); p063(60.5);
present(60.52);
for t=61,66 do raw_time=1000+t; present(t); end;
assert(after_first=='',"No missing alert while another caster's recast holds the row: "..after_first);
assert(table.concat(kinds,',')=='refresh','One renewal: '..table.concat(kinds,','));

-- B: control, the same packets in one datagram.
start(RDM);
raw_time=1060; wear_off(60.1); refresh_cast(RDM,60.1); list({43},{now_raw()+150*60}); p037(60.1); p063(60.1);
present(60.12);
for t=61,66 do raw_time=1000+t; present(t); end;
assert(#fired==0,'The same packets in one datagram alert nothing.');

-- C: the player's own recast, the status packets (both copies) cut into the next datagram.
start(SELF);
raw_time=1060; wear_off(60.1); refresh_cast(SELF,60.1);
present(60.12);
after_first=table.concat(fired,',');
list({43,43},{now_raw()+90*60,now_raw()+150*60}); p037(60.2); p063(60.2);
present(60.22);
raw_time=1060; list({43},{now_raw()+150*60}); p037(60.5); p063(60.5);
present(60.52);
for t=61,66 do raw_time=1000+t; present(t); end;
assert(after_first=='',"No missing alert while the player's own recast holds the row: "..after_first);

-- D: a real wear-off (no recast) still alerts at once.
start(RDM);
raw_time=1060; wear_off(60.1);
present(60.12);
assert(table.concat(fired,',')=='missing,removed','A real wear-off alerts missing and removed: '..table.concat(fired,','));

