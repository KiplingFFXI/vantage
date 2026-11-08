-- A job-linked profile loads on a real job change only. The settings remember the job they were last saved on
-- (profile_job), so logging back in on that job loads nothing over them, while a job changed with Vantage not
-- running still loads its profile. A job change to a job whose linked profile is already the active one keeps
-- the settings saved since, locks and moves too, and publishes nothing old over the shared layout.
local store=require('core.store');
local SNAP={valid=true,id=1001,name='Tester',zone=102,job=3,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(SNAP);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
require('ui.party_hud').draw=function()return 0,{};end;
require('ui.native_party_hud').draw=function()return 0,{};end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end,suspend=function()return true;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local function settings()return app.state.settings;end;
local function disk()return store.read(app.state.path);end;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked,'Fixture: the command ran.');end;
local function frames(count)for _=1,count do MOCK.frame(.11);end;end;
local function switch_back()
    SNAP.id,SNAP.name=2002,'Second';frames(10);
    assert(app.state.identity=='2002:Second','Fixture: switched.');
    SNAP.id,SNAP.name=1001,'Tester';frames(10);
    assert(app.state.identity=='1001:Tester','Fixture: back.');
end;
-- Tidy keeps a saved job and drops a damaged one; a save without one gets none.
local defaults=require('ui.defaults');
assert(defaults.tidy({profile_job=3}).profile_job==3,'A saved job loads.');
assert(defaults.tidy({profile_job=99}).profile_job==nil and defaults.tidy({profile_job='3'}).profile_job==nil,'A damaged job is dropped.');
assert(defaults.tidy({style={font_size=20}}).profile_job==nil and defaults.make().profile_job==nil,'Loading adds no job.');
MOCK.fire('load');app.refresh(0);
app.state.dirty=true;assert(app.callbacks.save(),'Fixture: the settings are on disk.');
assert(disk().profile_job==3,'A save keeps the job the settings are used on.');
assert(require('core.profiles').capture(settings()).profile_job==nil,'A profile does not carry the job.');

-- Healer (font 18) is linked to WHM; Party (font 26) is saved too. On WHM the player loads Party by hand, then
-- changes the font to 30. Logging in again on WHM (here a switch away and back) loads nothing over that.
command('/vg set style.font_size 18');frames(10);
assert(app.callbacks.profile_save('Healer',false),'Fixture: Healer saved.');
assert(app.callbacks.profile_link(3,'Healer'),'Fixture: Healer linked to WHM.');
command('/vg set style.font_size 26');frames(10);
assert(app.callbacks.profile_save('Party',false),'Fixture: Party saved.');
assert(app.callbacks.profile_load('Party'),'Fixture: Party loaded.');
command('/vg set style.font_size 30');frames(10);
assert(settings().active_profile=='Party' and disk().style.font_size==30,'Fixture: Party loaded by hand, font 30 saved.');
switch_back();
assert(settings().active_profile=='Party','Back on WHM, which never changed, the hand-loaded profile stays active.');
assert(settings().style.font_size==30 and disk().style.font_size==30,'Back on WHM, the saved font 30 is kept.');

-- The job changed while Vantage wasn't running: the settings were last saved on WHM, the login is on RDM, which
-- is linked to Healer. Healer loads.
assert(app.callbacks.profile_link(5,'Healer'),'Fixture: Healer linked to RDM.');
SNAP.id,SNAP.name=2002,'Second';frames(10);
SNAP.job=5;SNAP.id,SNAP.name=1001,'Tester';frames(10);
assert(app.state.identity=='1001:Tester','Fixture: back on RDM.');
assert(settings().active_profile=='Healer' and settings().style.font_size==18,'A job changed with Vantage not running loads its profile.');
assert(disk().profile_job==5,'The settings now remember RDM.');

-- A save with no profile_job: a login on a job whose linked profile is the active one keeps the settings; one whose
-- linked profile isn't loads it.
local old=disk();old.profile_job=nil;old.active_profile='Party';old.style.font_size=31;
assert(store.write(app.state.path,old),'Fixture: a save with no job.');
switch_back();
assert(settings().active_profile=='Healer' and settings().style.font_size==18,'Without a saved job, the linked profile loads.');
old=disk();old.profile_job=nil;old.style.font_size=32;
assert(old.active_profile=='Healer' and store.write(app.state.path,old),'Fixture: a save with no job, its linked profile active.');
switch_back();
assert(settings().active_profile=='Healer' and settings().style.font_size==32,'Without a saved job, an active linked profile stays as saved.');
-- Loading adds nothing: the job is written by the next save.
old=disk();old.profile_job=nil;assert(store.write(app.state.path,old),'Fixture: a save with no job.');
switch_back();
assert(disk().profile_job==nil,'Loading writes no job into the saved file.');
command('/vg set style.font_size 21');frames(10);
assert(disk().profile_job==5,'The next save does.');

-- WHM -> WAR (no link) -> WHM, with Open (saved unlocked) linked to WHM and active, sharing on, and a lock and a
-- move saved since.
SNAP.job=3;frames(5);
command('/vg set shared_layout true');frames(30);
command('/vg unlock');frames(10);
assert(app.callbacks.profile_save('Open',false) and app.callbacks.profile_link(3,'Open'),'Fixture: Open saved unlocked and linked.');
assert(settings().active_profile=='Open','Fixture: Open active.');
command('/vg lock');
local x=settings().panels.self_debuffs.x;
command('/vg set panels.self_debuffs.x '..(x+55));frames(30);
assert(disk().panels.self_buffs.locked and disk().panels.self_debuffs.x==x+55,'Fixture: lock and move saved.');
local root=app.state.path:gsub('Tester_1001/settings.json$','');
local function shared()return assert(store.read(root..'shared_layout.json'),'Fixture: the shared layout reads.');end;
assert(shared().self_debuffs.x==x+55,'Fixture: the move is in the shared layout.');
SNAP.job=1;frames(5);
assert(settings().active_profile=='Open','Fixture: on WAR, unlinked, Open is still active.');
SNAP.job=3;frames(30);
assert(settings().panels.self_buffs.locked==true,'Back on WHM, the lock saved since the profile loaded is kept.');
assert(settings().panels.self_debuffs.x==x+55,'Back on WHM, the move saved since is kept.');
assert(shared().self_debuffs.x==x+55,'Back on WHM, the shared layout keeps the newer move.');
-- A job change to a job linked to a profile that isn't active still loads it.
assert(app.callbacks.profile_load('Party') and settings().active_profile=='Party','Fixture: Party active.');
SNAP.job=1;frames(5);SNAP.job=3;frames(10);
assert(settings().active_profile=='Open' and not settings().panels.self_buffs.locked,'A job change loads a linked profile that is not active.');
return true;
