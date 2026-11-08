local raw_time = 1000;
package.preload['core.clock'] = function() return {available=function() return true; end,get_game_time_raw=function() return raw_time; end}; end;
local client = require('core.client');
local stats = AshitaCore:GetMemoryManager():GetPlayer();
local icons, timers = {}, {};
stats.GetStatusIcons = function() return icons; end;
stats.GetStatusTimers = function() return timers; end;
stats.GetBuffs = function() return icons; end;
for slot=1,32 do icons[slot],timers[slot]=255,0; end
icons[1],icons[32],timers[1],timers[32]=33,40,66000,72000;
local snapshot=client.read(10);
assert(snapshot.valid and snapshot.self_known and #snapshot.self_effects==2,
    'One-based Lua status tables must be complete without a fictitious missing slot zero.');
assert(snapshot.self_effects[1].effect==33 and snapshot.self_effects[1].slot==0 and snapshot.self_effects[1].deadline==110);
assert(snapshot.self_effects[2].effect==40 and snapshot.self_effects[2].slot==31 and snapshot.self_effects[2].deadline==210,
    'The final status slot must retain its matching timer.');
local tracker=require('core.tracker').new(); tracker:reconcile(snapshot,10);
local view=tracker:view(10,{},snapshot);
assert(#view.rows==2 and view.self_known, 'A self buff must reach the HUD row model from the real Lua table shape.');
icons[12]=nil;
snapshot=client.read(11);
assert(not snapshot.self_known, 'An actual missing icon slot must still invalidate the status snapshot.');
local diagnostics=snapshot.self_diagnostics;
assert(diagnostics.source=='GetBuffs' and diagnostics.icon_type=='table' and diagnostics.icon_base==1
    and diagnostics.timer_base==1 and diagnostics.clock_available and #diagnostics.rejected_slots==1);
local rejected=diagnostics.rejected_slots[1];
assert(rejected.slot==11 and rejected.index==12 and rejected.raw_type=='nil' and rejected.raw_value=='nil' and rejected.readable);
tracker:reconcile(snapshot,11);
view=tracker:view(11,{},snapshot);
assert(#view.rows==2 and not view.self_known and view.rows[1].present and view.rows[2].present,
    'Readable buffs must reach the HUD even when another icon slot is missing.');
icons[12]=-2; icons[13]=1024; icons[14]=33.5; icons[15]=0/0; icons[16]=string.rep('x',100); icons[17]={};
snapshot=client.read(11.5);
assert(not snapshot.self_known and #snapshot.self_effects==2 and #snapshot.self_diagnostics.rejected_slots==6,
    'Invalid and fractional IDs cannot become observed statuses.');
rejected=snapshot.self_diagnostics.rejected_slots;
assert(rejected[1].raw_value==-2 and rejected[2].raw_value==1024 and rejected[3].raw_value==33.5);
assert(type(rejected[4].raw_value)=='string' and #rejected[5].raw_value==64 and rejected[6].raw_value=='table',
    'Report values are bounded and serializable without exposing object addresses.');
for slot=12,17 do icons[slot]=255; end
icons[12],icons[13]=-1,65535;
snapshot=client.read(11.75);
assert(snapshot.self_known and #snapshot.self_effects==2,'The buff array marks an empty slot 0xFFFF, signed or not.');
icons[12],icons[13]=255,255;
timers[32]=nil;
snapshot=client.read(12);
assert(snapshot.self_known and snapshot.self_effects[1].deadline==nil and snapshot.self_effects[2].deadline==nil,
    'An incomplete timer table cannot shift another slot timer onto the wrong status.');
icons[32]=nil;
assert(not client.read(13).self_known, 'An incomplete one-based status table must remain unknown.');
icons,timers={},{};
for slot=0,31 do icons[slot],timers[slot]=255,0; end
icons[0],icons[31],timers[0],timers[31]=33,40,66000,72000;
snapshot=client.read(14);
assert(snapshot.self_known and #snapshot.self_effects==2 and snapshot.self_effects[2].slot==31);
icons[12]=nil;
assert(not client.read(15).self_known, 'Zero-based Lua table holes are still invalid.');
local mocked_ffi=package.loaded.ffi;
package.loaded.ffi=nil;
local ffi=require('ffi');
package.loaded.ffi=mocked_ffi;
local native_icons,native_timers=ffi.new('int16_t[32]'),ffi.new('uint32_t[32]');
for slot=0,31 do native_icons[slot],native_timers[slot]=255,0; end
native_icons[0],native_icons[31],native_timers[0],native_timers[31]=33,40,66000,72000;
icons,timers=native_icons,native_timers;
snapshot=client.read(16);
assert(snapshot.self_known and #snapshot.self_effects==2 and snapshot.self_effects[2].slot==31,
    'Native arrays retain zero-based access without probing out-of-bounds slot32.');
stats.GetStatusIcons=function() return nil; end;
stats.GetBuffs=function() local buffs={}; for i=1,32 do buffs[i]=-1; end; buffs[32]=33; return buffs; end;
snapshot=client.read(17);
assert(snapshot.self_known and #snapshot.self_effects==1 and snapshot.self_effects[1].effect==33 and snapshot.self_effects[1].deadline==nil,
    'One-based buffs retain presence without a status icon to pair a timer with.');
assert(snapshot.self_diagnostics.source=='GetBuffs');
stats.GetBuffs=function() return nil; end;
stats.GetStatusIcons=function() local values={}; for i=1,32 do values[i]=255; end; values[32]=40; return values; end;
snapshot=client.read(18);
assert(snapshot.self_known and #snapshot.self_effects==1 and snapshot.self_effects[1].effect==40 and snapshot.self_effects[1].deadline==218,
    'Without a buff array the status icons stand in, with their own timers.');
assert(snapshot.self_diagnostics.source=='GetStatusIcons');
stats.GetBuffs=function() return icons; end;

local function proxy_array(values, reads)
    local proxy=newproxy(true);
    getmetatable(proxy).__index=function(_,index)
        reads[index]=(reads[index] or 0)+1;
        return values[index];
    end;
    return proxy;
end
local proxy_icons,proxy_timers,icon_reads,timer_reads={},{},{},{};
for slot=1,32 do proxy_icons[slot],proxy_timers[slot]=255,0; end
proxy_icons[1],proxy_icons[2],proxy_icons[32]=40,39,33;
proxy_timers[1],proxy_timers[2],proxy_timers[32]=66000,72000,78000;
icons,timers=proxy_array(proxy_icons,icon_reads),proxy_array(proxy_timers,timer_reads);
stats.GetStatusIcons=function() return icons; end;
client.reset();
snapshot=client.read(20);
assert(type(icons)=='userdata' and snapshot.valid and snapshot.self_known and #snapshot.self_effects==3,
    'Ashita one-based userdata has no index zero and still supplies a complete status list.');
diagnostics=snapshot.self_diagnostics;
assert(diagnostics.icon_type=='userdata' and diagnostics.timer_type=='userdata' and diagnostics.icon_base==1
    and diagnostics.timer_base==1 and #diagnostics.rejected_slots==0);
assert(snapshot.self_effects[1].effect==40 and snapshot.self_effects[1].slot==0 and snapshot.self_effects[1].deadline==120);
assert(snapshot.self_effects[2].effect==39 and snapshot.self_effects[2].slot==1 and snapshot.self_effects[2].deadline==220);
assert(snapshot.self_effects[3].effect==33 and snapshot.self_effects[3].slot==31 and snapshot.self_effects[3].deadline==320,
    'Userdata status index32 must retain timer index32 rather than drop or shift the final buff.');
tracker=require('core.tracker').new();tracker:reconcile(snapshot,20);
view=tracker:view(20,{},snapshot);
assert(view.self_known and view.subjects[1].known and #view.rows==3 and #tracker:drain_events()==0,
    'A complete userdata read must establish a quiet known baseline in the tracker.');
local alerts=require('core.alerts').new();
local rules={
    {id='userdata_missing',enabled=true,event='missing',effect=40,scope='self',cooldown=0,visual=true},
    {id='userdata_gain',enabled=true,event='gain',effect=40,scope='self',cooldown=0,visual=true},
};
alerts:update(view,{},rules,20,{});
assert(#alerts:drain(20)==0,'The initial complete userdata read must not generate a gain or missing warning.');
proxy_icons[1],proxy_timers[1]=255,0;
snapshot=client.read(21);tracker:reconcile(snapshot,21);view=tracker:view(21,{},snapshot);
local events=tracker:drain_events();
assert(view.self_known and #view.rows==2 and #events==1 and events[1].kind=='removed' and events[1].effect==40);
alerts:update(view,events,rules,21,{});
local notices=alerts:drain(21);
assert(#notices==1 and notices[1].event=='missing' and notices[1].effect==40,
    'A complete userdata read can confirm absence after a previously present buff disappears.');
proxy_icons[1],proxy_timers[1]=40,84000;
snapshot=client.read(22);tracker:reconcile(snapshot,22);view=tracker:view(22,{},snapshot);
events=tracker:drain_events();
assert(view.self_known and #view.rows==3 and #events==1 and events[1].kind=='gain' and events[1].effect==40);
alerts:update(view,events,rules,22,{});notices=alerts:drain(22);
assert(#notices==1 and notices[1].event=='gain' and notices[1].effect==40,
    'A later userdata application should produce one real gain without a stale missing warning.');
proxy_icons[12]=nil;
snapshot=client.read(23);rejected=snapshot.self_diagnostics.rejected_slots;
assert(not snapshot.self_known and #snapshot.self_effects==3 and #rejected==1 and rejected[1].index==12
    and rejected[1].slot==11 and rejected[1].raw_type=='nil',
    'A genuine interior userdata hole stays incomplete instead of being treated as an empty status.');
proxy_icons[12]=-2;
snapshot=client.read(24);rejected=snapshot.self_diagnostics.rejected_slots;
assert(not snapshot.self_known and #rejected==1 and rejected[1].raw_value==-2,
    'Index-base detection must not silently normalize values the buff array never holds.');
proxy_icons[12],proxy_icons[32]=255,nil;
snapshot=client.read(25);
assert(not snapshot.self_known and not snapshot.self_diagnostics.index_base_known,
    'A userdata array with neither endpoint readable cannot establish a complete index range.');
proxy_icons[32]=33;proxy_timers[32]=nil;
snapshot=client.read(26);
assert(snapshot.self_known and snapshot.self_effects[1].deadline==nil and snapshot.self_effects[3].deadline==nil,
    'Incomplete userdata timers cannot attach a shifted countdown to otherwise valid icons.');
proxy_timers[32]=78000;
stats.GetStatusIcons=function() return nil; end;
stats.GetBuffs=function() return icons; end;
snapshot=client.read(27);
assert(snapshot.self_known and #snapshot.self_effects==3 and snapshot.self_diagnostics.source=='GetBuffs'
    and snapshot.self_effects[3].slot==31 and snapshot.self_effects[3].deadline==nil,
    'The GetBuffs fallback accepts one-based userdata but never borrows unpaired status timers.');
stats.GetStatusIcons=function() return icons; end;
proxy_icons,proxy_timers,icon_reads,timer_reads={},{},{},{};
for slot=0,31 do proxy_icons[slot],proxy_timers[slot]=255,0; end
proxy_icons[0],proxy_icons[31],proxy_timers[0],proxy_timers[31]=40,39,66000,72000;
icons,timers=proxy_array(proxy_icons,icon_reads),proxy_array(proxy_timers,timer_reads);
client.reset();snapshot=client.read(28);
assert(snapshot.self_known and #snapshot.self_effects==2 and snapshot.self_diagnostics.icon_base==0
    and snapshot.self_diagnostics.timer_base==0 and snapshot.self_effects[2].slot==31);
assert(icon_reads[32]==nil and timer_reads[32]==nil,
    'Zero-based userdata must never probe index32 after index zero establishes its base.');
proxy_icons[12]=nil;snapshot=client.read(29);
assert(not snapshot.self_known and snapshot.self_diagnostics.rejected_slots[1].index==12,
    'Zero-based userdata retains validation of holes within its established range.');
local unreadable=newproxy(true);
getmetatable(unreadable).__index=function() error('Unreadable status array'); end;
icons=unreadable;
local read_ok,unreadable_snapshot=pcall(client.read,30);
assert(read_ok and unreadable_snapshot.valid and not unreadable_snapshot.self_known,
    'An unreadable userdata binding stays unknown without throwing from base detection.');
return true;
