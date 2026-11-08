-- Coming back to a character whose job is linked to the profile already active: its saved settings are what
-- was left, so the profile isn't loaded over them. Loading it again would publish its old placement over a
-- newer shared layout another character saved, and undo a lock saved since.
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
command('/vg set shared_layout true');frames(30);
command('/vg unlock');
assert(app.callbacks.profile_save('Melee',false));
assert(app.callbacks.profile_link(1,'Melee'));
command('/vg lock');frames(30);
assert(settings().panels.self_buffs.locked and disk().panels.self_buffs.locked,'Fixture: locked and saved.');
local root=app.state.path:gsub('Tester_1001/settings.json$','');
local layout_path=root..'shared_layout.json';
local function shared()return assert(store.read(layout_path));end;
local x=shared().self_debuffs.x;
-- Another character moves a shared panel.
SNAP.id,SNAP.name=2002,'Second';frames(5);
assert(app.state.identity=='2002:Second','Fixture: switched.');
command('/vg set shared_layout true');frames(30);
command('/vg set panels.self_debuffs.x '..(x+70));frames(30);
assert(shared().self_debuffs.x==x+70,'Fixture: the second character published its move.');
-- Back to the first, on the same job.
SNAP.id,SNAP.name=1001,'Tester';frames(30);
assert(app.state.identity=='1001:Tester','Fixture: back.');
assert(shared().self_debuffs.x==x+70 and settings().panels.self_debuffs.x==x+70,
    'The newer shared layout is kept: file '..shared().self_debuffs.x..', newer '..(x+70));
assert(settings().panels.self_buffs.locked and settings().party_ui.locked and disk().panels.self_buffs.locked,
    'The saved lock is kept.');
-- A real job change still loads the linked profile, when another profile is the active one.
assert(app.callbacks.profile_save('Other',false) and settings().active_profile=='Other','Fixture: another profile is active.');
SNAP.job=2;frames(3);SNAP.job=1;frames(3);
assert(not settings().panels.self_buffs.locked and settings().active_profile=='Melee','Changing to the linked job loads the profile, as before.');
