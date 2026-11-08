-- A settings page that recovers a deleted profile and then fails puts everything back, so recovering it
-- again afterwards still gives its job link and active profile back to Undo.
local store=require('core.store');
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(snapshot);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
require('ui.party_hud').draw=function()return 0,{};end;
require('ui.native_party_hud').draw=function()return 0,{};end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end};
local page;
package.loaded['ui.main_page']={labels={},draw=function(_,s,_,callbacks,ui)if page then page(s,callbacks,ui);end;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local function settings()return app.state.settings;end;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
MOCK.fire('load');app.refresh(0);
app.state.dirty=true;assert(app.callbacks.save(),'Fixture: the settings are on disk.');
assert(app.callbacks.profile_save('Melee',false) and app.callbacks.profile_link(1,'Melee'),'Fixture: Melee is saved and linked.');
command('/vg set style.font_size 25');
assert(app.callbacks.profile_delete('Melee',app.callbacks.profile_status('Melee').token),'Fixture: Melee is deleted.');
command('/vg');MOCK.frame(.11);MOCK.frame(.11);
page=function(_,callbacks)callbacks.profile_recover();error('Fixture settings page failure.');end;
MOCK.frame(.11);page=nil;
assert(settings().job_profiles['1']==nil and not app.callbacks.profile_status('Melee').exists,'Fixture: the failed page was put back.');
command('/vg profile recover');
assert(settings().job_profiles['1']=='Melee' and settings().active_profile=='Melee','Fixture: the recovery brings the link back.');
command('/vg undo');
assert(settings().style.font_size~=25,'Fixture: undo put the font back.');
assert(settings().job_profiles['1']=='Melee' and settings().active_profile=='Melee',
    'After a failed page, Undo still keeps the recovered job link and active profile.');
