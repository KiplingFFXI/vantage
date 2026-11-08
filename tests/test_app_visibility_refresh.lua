-- The map, events, the hidden UI and chat send no packet, so Present checks them itself and reads the client again
-- straight away when one opens or closes. Matching, unreadable or missing flags add no extra read.
local store=require('core.store');
local copy=store.copy;
local world={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_effects={{effect=33,slot=0}},party={},entities={},
    hidden=false,map=false,in_event=false,chat_open=false,combat=true};
local reads,unreadable,sparse=0,false,false;
package.loaded['core.client']={load=function()end,
    read=function()
        reads=reads+1;local value=copy(world);
        if sparse then for _,key in ipairs({'hidden','map','in_event','chat_open'})do if value[key]==false then value[key]=nil;end;end;end;
        return value;
    end,
    visibility=function()
        if unreadable then return nil;end;
        return {valid=true,id=world.id,zone=world.zone,hidden=world.hidden,map=world.map,in_event=world.in_event,chat_open=world.chat_open};
    end};
package.loaded['core.observer']={read=function()return {};end};
package.loaded['ui.hud']={draw=function()end,draw_notices=function()end,cancel_gesture=function()end};
package.loaded['ui.settings_window']={draw=function()end,blocks_input=function()return false;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
MOCK.now=1;app.refresh(1);
local settings=app.state.settings;
settings.enabled=true;
settings.party_ui.enabled=false;
MOCK.frame(.11);
assert(app.state.snapshot.valid,'Fixture: Vantage has read the client.');

for _,field in ipairs({'map','in_event','hidden','chat_open'})do
    MOCK.frame(.01);local before=reads;
    MOCK.frame(.01);assert(reads==before,'Fixture: a Present 10 ms after the last one reuses its snapshot.');
    world[field]=true;MOCK.frame(.01);
    assert(reads==before+1 and app.state.snapshot[field]==true,'A changed '..field..' refreshes Vantage on the next Present.');
    world[field]=false;MOCK.frame(.01);
    assert(reads==before+2 and app.state.snapshot[field]==false,'A cleared '..field..' refreshes Vantage on the next Present.');
    MOCK.frame(.01);assert(reads==before+2,'Matching visibility adds no refresh.');
    unreadable=true;world[field]=true;MOCK.frame(.01);
    assert(reads==before+2,'Unreadable visibility never forces a refresh.');
    unreadable=false;world[field]=false;MOCK.frame(.01);
end;
sparse=true;MOCK.frame(.11);local before=reads;MOCK.frame(.01);MOCK.frame(.01);
assert(reads==before,'A flag the snapshot leaves out reads as off and adds no refresh.');
sparse=false;
assert(#MOCK.commands==0);
