-- A deleted profile kept for recovery keeps no Undo step alive once that step has left Undo and Redo.
local store=require('core.store');
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=3,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(snapshot);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
require('ui.party_hud').draw=function()return 0,{};end;
require('ui.native_party_hud').draw=function()return 0,{};end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end,suspend=function()return true;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
MOCK.fire('load');app.refresh(0);
app.state.dirty=true;assert(app.callbacks.save());
local old=setmetatable({},{__mode='k'});
for size=11,30 do command('/vg set style.font_size '..size); end;
for _,entry in ipairs(app.state.history) do old[entry.settings]=true; end;
command('/vg profile save "Melee"');
command('/vg profile delete "Melee"');
for size=9,29 do command('/vg set style.font_size '..size); end;
jit.flush(); collectgarbage('collect');collectgarbage('collect');
local alive=0;
for _ in pairs(old) do alive=alive+1; end;
assert(alive==0,'Steps that left Undo are not kept by the recoverable delete: '..alive..' kept.');
-- The recovery still works.
command('/vg profile recover');
assert(app.state.settings.active_profile~=nil,'Fixture: recovered.');
