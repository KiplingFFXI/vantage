local store=require('core.store');
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={read=function()return store.copy(snapshot);end,load=function()end};
local reads,writes,incoming,last_report={},0;
store.read=function(path)
    reads[#reads+1]=path;
    if incoming and path:find('/Second_1002/settings.json',1,true) then return store.copy(incoming);end;
end;
store.write=function(_,value)writes=writes+1;last_report=value;return true;end;
local app=dofile(ADDON_DIR..'/vantage.lua');
app.refresh(0);
local saved,path=app.state.settings,app.state.path;
saved.style.font_size=27;saved.panels.self_buffs.width=479;saved.panels.self_buffs.locked=false;
saved.job_profiles['2']='Previous owner';
local profile_loads,last_profile=0;
app.callbacks.profile_load=function(name)profile_loads=profile_loads+1;last_profile=name;return true;end;
local settings=store.copy(saved);
local function unchanged()
    assert(app.state.settings==saved and app.state.path==path,'An unknown name must retain the current character settings and path.');
    assert(require('core.customization').equal(app.state.settings,settings),'Unknown names cannot change manual sizes, locks, or other options.');
    assert(#reads==1 and writes==0,'An unknown name cannot read or create an alternate settings file.');
end;
for _,name in ipairs({'','\0','///'})do
    snapshot.name=name;app.refresh(1);unchanged();
end;
snapshot.name=nil;app.refresh(2);unchanged();
snapshot.name='Tester';snapshot.zone=103;app.refresh(3);unchanged();
assert(path:find('/Tester_1001/settings.json',1,true),'The established saved path is unchanged.');
snapshot.name='';snapshot.job=2;app.refresh(3.1);
assert(profile_loads==1 and last_profile=='Previous owner' and app.state.last_job==2,
    'The established owner still applies their own job profile while their name is unavailable.');
snapshot.name='Tester';snapshot.job=1;app.refresh(3.2);profile_loads=0;
local fresh_snapshot={valid=true,id=1002,name='',zone=103,job=2,self_known=true,self_effects={},party={},entities={}};
snapshot=fresh_snapshot;app.refresh(4);unchanged();
assert(profile_loads==0 and app.state.last_job==1,'An unknown-name owner cannot apply or consume the previous character job profile.');
incoming=require('ui.defaults').make();incoming.job_profiles['2']='Second owner';
snapshot.name='Second';app.refresh(5);
assert(app.state.path:find('/Second_1002/settings.json',1,true) and app.state.settings_owner_id==1002);
assert(profile_loads==1 and last_profile=='Second owner' and app.state.last_job==2,
    'A stable new owner applies their own profile after their settings bind.');
app.state.problem='The display could not update. Test failure.';
assert(app.callbacks.export_report());
assert(last_report.problem==app.state.problem,'Explicit reports retain the last distinct display failure.');
