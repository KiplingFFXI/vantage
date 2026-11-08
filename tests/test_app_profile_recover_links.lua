-- Recovering a rename puts the old name back in the file. A job linked to the new name after the rename, and
-- an active profile loaded by it, follow the name back, so the job still loads it and nothing points at a
-- profile that no longer exists.
local store=require('core.store');
local SNAP={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(SNAP);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
require('ui.party_hud').draw=function()return 0,{};end;
require('ui.native_party_hud').draw=function()return 0,{};end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end,suspend=function()return true;end};
local page;
package.loaded['ui.main_page']={labels={},draw=function(_,s,_,callbacks,ui)if page then page(s,callbacks,ui);end;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local function settings()return app.state.settings;end;
local function disk()return store.read(app.state.path);end;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
local function frames(count)for _=1,count do MOCK.frame(.11);end;end;
MOCK.fire('load');app.refresh(0);
app.state.dirty=true;assert(app.callbacks.save());
local root=app.state.path:gsub('Tester_1001/settings.json$','');
local function profiles()return store.read(root..'profiles.json') or {};end;
command('/vg set style.font_size 31');
command('/vg profile save "Melee"');
command('/vg set style.font_size 18');
command('/vg profile rename "Melee" "Melee DD"');
command('/vg profile link 2 "Melee DD"');
assert(settings().job_profiles['2']=='Melee DD','Fixture: job 2 linked after the rename.');
command('/vg profile recover');
assert(profiles().Melee and not profiles()['Melee DD'],'Fixture: the rename is recovered.');
assert(settings().job_profiles['2']=='Melee' and disk().job_profiles['2']=='Melee',
    'The link made after the rename moves back to the old name: '..tostring(settings().job_profiles['2']));
-- Another profile is the active one, so the job change loads Melee.
command('/vg profile save "Spare"');
assert(settings().active_profile=='Spare','Fixture: another profile is active.');
SNAP.job=2;frames(3);
assert(settings().style.font_size==31,'Job 2 still loads its profile.');

command('/vg profile save "Other"');
assert(settings().active_profile=='Other','Fixture: Other is active.');
command('/vg profile rename "Melee" "Melee DD"');
command('/vg profile load "Melee DD"');
assert(settings().active_profile=='Melee DD','Fixture: the renamed profile is loaded.');
command('/vg profile recover');
local status=app.callbacks.profile_status();
assert(settings().active_profile=='Melee' and not status.missing,
    'The active profile follows the name back: '..settings().active_profile..', missing '..tostring(status.missing));
