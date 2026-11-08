-- The player recasts Refresh (Always_Overwrite) with time left: Phoenix sends the old copy's wear-off, the 0x028,
-- that tick's status packets listing both copies, and the next tick's with the new copy alone. Read tick by
-- tick, or with both ticks in one reply (a send gap over 400 ms), or with the messages first and both ticks'
-- status packets together, it is one renewal: a refresh, no gain or removal alert, the same row.
local raw_time=1000;
package.preload['core.clock']=function() return {available=function() return true; end,get_game_time_raw=function() return raw_time; end}; end;
local client=require('core.client');
local observer=require('core.observer');
local stats=AshitaCore:GetMemoryManager():GetPlayer();
local buffs,icons,timers={},{},{};
stats.GetBuffs=function() return buffs; end;
stats.GetStatusIcons=function() return icons; end;
stats.GetStatusTimers=function() return timers; end;
local function set_buffs(list) for slot=0,31 do buffs[slot]=list[slot+1] or 65535; end; end;
local function set_icons(list,times) for slot=0,31 do icons[slot]=list[slot+1] or 255; timers[slot]=times[slot+1] or 0; end; end;
local SELF=MOCK.player.server_id;
local s=require('ui.defaults').make();
local rules={
    {id='removed',enabled=true,event='removed',effect=43,scope='self',cooldown=0,visual=true},
    {id='gained',enabled=true,event='gain',effect=43,scope='self',cooldown=0,visual=true},
    {id='refreshed',enabled=true,event='refresh',effect=43,scope='self',cooldown=0,visual=true},
};
local tracker,alerts,snap,queue,kinds,fired,keys;
local function feed(list) for _,o in ipairs(list) do queue[#queue+1]=o; end; end;
local function p037(t) client.accept(MOCK.packet(0x037,MOCK.bytes(0x50)),t,snap); end;
local function p063(t) local b=MOCK.bytes(200);MOCK.put(b,4,2,9);client.accept(MOCK.packet(0x063,b),t,snap); end;
local function putbits(bytes, offset, length, value)
    for i = 0, length - 1 do
        local at = offset + i;
        if math.floor(value / 2 ^ i) % 2 == 1 then bytes[math.floor(at / 8)] = bytes[math.floor(at / 8)] + 2 ^ (at % 8); end
    end
end
local function cast(t)
    local bytes, at = MOCK.bytes(512), 150;
    putbits(bytes, 40, 32, SELF); putbits(bytes, 72, 6, 1);
    putbits(bytes, 82, 4, 4); putbits(bytes, 86, 32, 109);
    putbits(bytes, at, 32, SELF); putbits(bytes, at + 32, 4, 1); at = at + 36;
    putbits(bytes, at + 27, 17, 43); putbits(bytes, at + 44, 10, 230); at = at + 87;
    bytes.n = math.ceil(at / 8);
    feed(observer.read(MOCK.packet(0x028, bytes), t, snap));
end
local function wear_off(t)
    local b=MOCK.bytes(28);
    MOCK.put(b,4,4,SELF);MOCK.put(b,8,4,SELF);MOCK.put(b,12,4,43);MOCK.put(b,24,2,206);
    feed(observer.read(MOCK.packet(0x029,b),t,snap));
end;
local function present(t)
    raw_time=1000+t;
    local current=client.read(t,s);
    tracker:observe(queue,t,current);queue={};
    tracker:reconcile(current,t);
    snap=current;
    local view=tracker:view(t,s,current);
    local events=tracker:drain_events();
    alerts:update(view,events,rules,t,{enabled=true});
    for _,event in ipairs(events) do if event.effect==43 then kinds[#kinds+1]=event.kind; end; end;
    for _,notice in ipairs(alerts:drain(t)) do fired[#fired+1]=notice.rule_id; end;
    for _,row in ipairs(view.rows) do if row.effect==43 and not row.departing then keys[row.key]=true; end; end;
    return view;
end;
local function raw_at(t,left) return (1000+t)*60+left*60; end
local OLDRAW, BEFORE;
local function start()
    tracker,alerts,queue,kinds,fired,keys=require('core.tracker').new(),require('core.alerts').new(),{},{},{},{};
    raw_time=1000; set_buffs({});set_icons({},{});
    snap=client.read(0,s); present(0.1);
    -- first cast at 0.5, its tick's listing
    raw_time=1000.5; cast(0.5); OLDRAW=raw_at(0.5,150);
    set_buffs({43});set_icons({43},{OLDRAW});p037(0.5);p063(0.5);p037(0.5);
    present(0.52);
    local v; for t=1,50 do v=present(t); end
    BEFORE=nil; for _,row in ipairs(v.rows) do if row.effect==43 then BEFORE=row.key; end end
    kinds,fired,keys={},{},{};
end
local NEWRAW=raw_at(50.5,150);
local function tick_both(t) set_buffs({43,43});set_icons({43,43},{OLDRAW,NEWRAW});p037(t);p063(t);p037(t); end
local function tick_new(t) set_buffs({43});set_icons({43},{NEWRAW});p037(t);p063(t); end
local function check(label)
    local count, key = 0, next(keys);
    for _ in pairs(keys) do count = count + 1; end
    assert(table.concat(kinds,',')=='refresh',label..': one renewal, got '..table.concat(kinds,','));
    assert(#fired==0,label..': no gain or removal alert, got '..table.concat(fired,','));
    assert(count==1 and key==BEFORE,label..': the row keeps its key.');
end
-- Tick by tick.
start(); raw_time=1050.5; wear_off(50.5); cast(50.5); tick_both(50.5); present(50.52);
raw_time=1050.9; tick_new(50.9); present(50.92); present(52); check('Tick by tick');
-- Both ticks in one reply, read by one refresh.
start(); raw_time=1050.5; wear_off(50.5); cast(50.5); tick_both(50.5); raw_time=1050.9; tick_new(50.9); present(50.92); present(52);
check('Both ticks bunched');
-- The messages alone first, then both ticks' status packets together.
start(); raw_time=1050.5; wear_off(50.5); cast(50.5); present(50.52); raw_time=1050.9; tick_both(50.9); tick_new(50.9); present(50.92); present(52);
check('Messages first');
