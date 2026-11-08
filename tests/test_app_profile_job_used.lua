-- The settings remember the job they were last used on. A job change seen while Vantage runs is saved with them
-- even when no profile loads, so a later login on another job, changed with Vantage not running, loads that job's
-- linked profile. The job a login finds is only read: loading writes nothing.
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
local root=MOCK_INSTALL_PATH..'/config/addons/vantage/';
local function settings()return app.state.settings;end;
local function disk()return store.read(app.state.path);end;
local function raw(path)local file=io.open(path,'rb');if not file then return nil;end;local text=file:read('*a');file:close();return text;end;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked,'Fixture: the command ran.');end;
local function frames(count)for _=1,count do MOCK.frame(.11);end;end;
-- Logging out and in again: another character in between.
local function login(id,name,job)
    SNAP.id,SNAP.name=2002,'Away';frames(10);
    SNAP.id,SNAP.name,SNAP.job=id,name,job;frames(10);
    assert(app.state.identity==tostring(id)..':'..name,'Fixture: logged in.');
end;
-- WHM is linked to Healer (font 18), and Party (font 26) is loaded by hand on WHM, so the file says WHM.
local function setup(id,name,suffix)
    login(id,name,3);
    command('/vg set style.font_size 18');frames(10);
    assert(app.callbacks.profile_save('Healer'..suffix,false) and app.callbacks.profile_link(3,'Healer'..suffix),'Fixture: Healer linked to WHM.');
    command('/vg set style.font_size 26');frames(10);
    assert(app.callbacks.profile_save('Party'..suffix,false) and app.callbacks.profile_load('Party'..suffix),'Fixture: Party loaded by hand.');
    frames(10);
    assert(disk().profile_job==3 and settings().active_profile=='Party'..suffix,'Fixture: the file says WHM, with Party active.');
end;
MOCK.fire('load');app.refresh(0);frames(5);

-- In game the player changes to RDM, which has no link, logs out on RDM, and later logs in on WHM.
setup(1001,'Tester','A');
SNAP.job=5;frames(10);
assert(settings().active_profile=='PartyA','Fixture: on RDM, with no link, nothing loads.');
assert(disk().profile_job==5,'A job change that loads nothing is saved with the settings.');
login(1001,'Tester',3);
assert(settings().active_profile=='HealerA' and settings().style.font_size==18,'A login on WHM after leaving on RDM loads the WHM link.');
-- A login on the job in the file sees no change; a change in game after it is saved too.
login(1001,'Tester',3);
assert(settings().active_profile=='HealerA' and disk().profile_job==3,'Fixture: a login on WHM, the job in the file.');
SNAP.job=5;frames(10);
assert(disk().profile_job==5,'A job change after a login on the job in the file is saved too.');

-- RDM is linked to Party, the active profile, so the change to RDM loads nothing either (item 5.1 B).
setup(1003,'Bee','B');
assert(app.callbacks.profile_link(5,'PartyB'),'Fixture: Party linked to RDM.');
SNAP.job=5;frames(10);
assert(settings().active_profile=='PartyB' and settings().style.font_size==26,'Fixture: on RDM its linked profile is active, so nothing loads.');
assert(disk().profile_job==5,'A job change to a job whose linked profile is active is saved with the settings.');
login(1003,'Bee',3);
assert(settings().active_profile=='HealerB' and settings().style.font_size==18,'After such a change too, a login on WHM after leaving on RDM loads the WHM link.');

-- A login on RDM, changed with Vantage not running: the job the login finds isn't the file's, and RDM has no link.
setup(1004,'Cee','C');
SNAP.id,SNAP.name=2002,'Away';frames(10);
local kept=raw(root..'Cee_1004/settings.json');
SNAP.id,SNAP.name,SNAP.job=1004,'Cee',5;frames(20);
assert(app.state.identity=='1004:Cee' and settings().active_profile=='PartyC' and kept,'Fixture: on RDM, with no link, nothing loads.');
assert(raw(root..'Cee_1004/settings.json')==kept,'The job a login finds is only read: the file is not written.');
assert(raw(root..'Away_2002/settings.json')==nil,'A character with no saved file gets none from the job its login finds.');

-- With the saved file unreadable, a job change saves nothing over it and says nothing new.
MOCK_MKDIR(root..'Dee_1005');
local file=assert(io.open(root..'Dee_1005/settings.json','wb'),'Fixture: the file opens.');file:write('{"style":');file:close();
SNAP.id,SNAP.name,SNAP.job=1005,'Dee',3;frames(10);
assert(app.state.unread==app.state.path and app.state.problem,'Fixture: the file could not be read.');
local said=app.state.problem;
SNAP.job=5;frames(60);
assert(app.state.problem==said and not app.state.dirty,'A job change with the saved file unreadable tries no save and says nothing new.');
assert(raw(root..'Dee_1005/settings.json')=='{"style":','Fixture: the unreadable file is kept.');
return true;
