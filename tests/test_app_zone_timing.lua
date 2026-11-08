-- The zone window in /vg report starts at an accepted zone change and is ready at the first refresh that reads the
-- player in the new zone. A departure alone keeps the old zone's snapshot, so it never makes the window ready.
local store=require('core.store');
local copy=store.copy;
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_effects={},party={},entities={}};
local timing={begins=0,ready=0};
package.loaded['core.performance']={now=function()return MOCK.now*1000;end,record=function()return true;end,
    zone_begin=function()timing.begins=timing.begins+1;return true;end,
    zone_ready=function()timing.ready=timing.ready+1;return true;end,
    snapshot=function()return {unit='ms'};end};
package.loaded['core.client']={load=function()end,read=function()return copy(snapshot);end,visibility=function()return copy(snapshot);end,
    packet_size=function(e)return e.size or 0;end};
package.loaded['core.observer']={read=function(e)
    return e.id==0x00A and {{kind='reset',reason='Zone changed'}} or {};
end};
package.loaded['ui.hud']={draw=function()end,draw_notices=function()end,cancel_gesture=function()end};
package.loaded['ui.settings_window']={draw=function()end,blocks_input=function()return false;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
MOCK.now=1;app.refresh(1);
local settings=app.state.settings;
settings.party_ui.enabled=false;
local function frames(count)for _=1,count do MOCK.frame(.11);end;end;
frames(3);
assert(timing.begins==0 and timing.ready==0,'Fixture: no zone change yet.');

-- Leaving: the old zone's snapshot is still valid, and the window waits.
MOCK.fire('packet_in',{id=0x00B,data=string.rep('\0',8),size=8});
assert(timing.begins==1,'An accepted departure starts the zone window.');
frames(3);
assert(timing.ready==0,'A departure alone never makes the zone window ready.');
-- Arriving: no snapshot while the client loads the zone, then the player in the new zone.
snapshot.valid=false;
MOCK.fire('packet_in',{id=0x00A,data=string.rep('\0',64),size=64});
frames(3);
assert(timing.ready==0,'The zone window waits while the player is not read yet.');
snapshot.valid,snapshot.zone=true,103;
frames(1);
assert(timing.ready==1,'The first refresh that reads the player in the new zone makes the window ready.');
frames(5);
assert(timing.ready==1,'Later refreshes leave it alone.');
-- Packets Vantage doesn't take start nothing: injected, blocked, or too short to be a zone change.
for _,event in ipairs({{id=0x00A,injected=true,data=string.rep('\0',64),size=64},{id=0x00B,blocked=true,data=string.rep('\0',8),size=8},
    {id=0x00A,data=string.rep('\0',40),size=40},{id=0x00B,data=string.rep('\0',4),size=4}})do
    MOCK.fire('packet_in',event);
end;
frames(2);
assert(timing.begins==2 and timing.ready==1,'Injected, blocked and short zone packets start no zone window.');
assert(#MOCK.commands==0);
