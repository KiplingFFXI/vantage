-- A Confirm on the client's + menu clears Haste from its own buff list (0x037 array) with no packet, and
-- leaves its status icons as they were. Phoenix answers the 0xF1 with the 0x029, and its status packets
-- follow at the next tick. A 0x037 the server queued before the 0xF1 can still list Haste after the clear.
-- The cancel is one removal: no gain when Haste is listed once more, and no second removal after it.
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
local NONE=0x7FFFFFFF;
local s=require('ui.defaults').make();
local rules={
    {id='removed',enabled=true,event='removed',effect=33,scope='self',cooldown=0,visual=true},
    {id='gained',enabled=true,event='gain',effect=33,scope='self',cooldown=0,visual=true},
};
local tracker,alerts,snap,queue,kinds,fired;
local function p037(t) client.accept(MOCK.packet(0x037,MOCK.bytes(0x50)),t,snap); end;
local function p063(t) local b=MOCK.bytes(200);MOCK.put(b,4,2,9);client.accept(MOCK.packet(0x063,b),t,snap); end;
local function wear_off(t)
    local b=MOCK.bytes(28);
    MOCK.put(b,4,4,MOCK.player.server_id);MOCK.put(b,8,4,MOCK.player.server_id);MOCK.put(b,12,4,33);MOCK.put(b,24,2,206);
    for _,observation in ipairs(observer.read(MOCK.packet(0x029,b),t,snap)) do queue[#queue+1]=observation; end;
end;
-- vantage.lua's refresh: the snapshot, then the queued observations and the listing, then the alerts.
local function present(t)
    local current=client.read(t,s);
    tracker:observe(queue,t,current);queue={};
    tracker:reconcile(current,t);
    snap=current;
    local view=tracker:view(t,s,current);
    local events=tracker:drain_events();
    alerts:update(view,events,rules,t,{enabled=true});
    for _,event in ipairs(events) do if event.effect==33 then kinds[#kinds+1]=event.kind; end; end;
    for _,notice in ipairs(alerts:drain(t)) do fired[#fired+1]=notice.rule_id; end;
    for _,row in ipairs(view.rows) do if row.effect==33 then return row; end; end;
end;
local function start()
    tracker,alerts,queue,kinds,fired=require('core.tracker').new(),require('core.alerts').new(),{},{},{};
    set_buffs({33,253});set_icons({33,253},{66000,NONE});
    snap=client.read(0,s);p037(1);p063(1);
    present(10);present(11);
end;
local function server_listing(t) set_buffs({253});set_icons({253},{NONE});p037(t);p063(t); end;
local function confirm() set_buffs({nil,253}); end;
local function once(label)
    assert(#kinds==1 and kinds[1]=='removed','One removal and nothing else: '..label..' '..table.concat(kinds,','));
    assert(#fired==1 and fired[1]=='removed','One removed alert and no gain alert: '..label..' '..table.concat(fired,','));
end;

-- Nothing in flight.
start();
confirm();
local row=present(11.10);
assert(row and row.departing and row.present==false,'The cleared row stays out of sight, leaving.');
wear_off(11.25);present(11.27);
server_listing(11.6);present(11.62);
assert(present(12.6)==nil,'The server listing drops it.');
once('plain');
-- A 0x037 queued before the 0xF1 comes in the reply datagram with the 0x029.
start();
confirm();present(11.10);
set_buffs({33,253});p037(11.25);wear_off(11.25);
row=present(11.27);
assert(row and row.departing and row.present==true,'Listed once more, the leaving row is drawn as the client lists it.');
server_listing(11.6);present(11.62);present(12.6);
once('same datagram');
-- A 0x037 from an earlier reply lands first, the 0x029 an update later.
start();
confirm();present(11.10);
set_buffs({33,253});p037(11.15);present(11.17);
wear_off(11.25);present(11.27);
server_listing(11.6);present(11.62);present(12.6);
once('separate 0x037');
-- The server's own removal, with nothing cleared on the client, is one removal as before.
start();
wear_off(11.25);present(11.27);
server_listing(11.6);present(11.62);present(12.6);
once('server removal');
