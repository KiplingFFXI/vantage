local calls={};
local function called(name,fail)
    return function()
        calls[name]=(calls[name] or 0)+1;
        if fail then error('fixture '..name..' failure');end;
        return true;
    end;
end;
local hud=require('ui.hud');
local app=dofile(ADDON_DIR..'/vantage.lua');
MOCK.now=1;app.refresh(1);
local saved=require('core.store').copy(app.state.settings);
hud.cancel_gesture=called('hud_cancel',true);
require('ui.native_party_hud').cancel_layout_gesture=called('party_cancel');
hud.draw=function()error('fixture display failure');end;
MOCK.frame(.01);
assert(calls.hud_cancel and calls.party_cancel,
    'A failed gesture cleanup cannot leave another display in an active move or resize.');
assert(require('core.customization').equal(saved,app.state.settings),'Recovery cannot change saved options or locks.');
local reported=false;
for _,message in ipairs(MOCK.printed)do if message:find('fixture display failure',1,true)then reported=true;end;end;
assert(reported,'The original drawing failure remains visible even if cleanup also fails.');
assert(#MOCK.commands==0,'Recovery never injects a gameplay command.');

-- A display that fails on every frame still lets alerts be given and changes save.
local drained,drain=0,app.alerts.drain;
app.alerts.drain=function(...) drained=drained+1; return drain(...); end;
assert(app.state.path,'Fixture: a character is loaded.');
app.state.settings.style.font_size=app.state.settings.style.font_size+1;
app.state.dirty,app.state.changed_at=true,MOCK.now-1;
MOCK.frame(.01);
assert(drained==1,'A failed display still gives alerts.');
assert(not app.state.dirty and require('core.store').read(app.state.path).style.font_size==app.state.settings.style.font_size,
    'A failed display still saves changes.');
