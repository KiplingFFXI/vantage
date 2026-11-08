-- /vg profile link follows its usage line, recovering a deleted profile also restores it in Undo and Redo,
-- and closing the settings window with /vg is saved.
local store=require('core.store');
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=3,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(snapshot);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
require('ui.party_hud').draw=function()return 0,{};end;
require('ui.native_party_hud').draw=function()return 0,{};end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,update=function()end,
    status=function()return {active=false};end,restore=function()return true;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local function settings()return app.state.settings;end;
local function disk()return store.read(app.state.path);end;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);end;
local function said(text)
    for _,message in ipairs(MOCK.printed)do if message:find(text,1,true)then return true;end;end;
    return false;
end;
MOCK.fire('load');app.refresh(0);
app.state.dirty=true;assert(app.callbacks.save(),'Fixture: the settings are on disk.');
assert(app.callbacks.profile_save('Healer',false) and app.callbacks.profile_save('Melee',false),'Fixture: two profiles are saved.');

-- Link, with and without a job ID.
command('/vg profile link 3 "Healer"');
assert(settings().job_profiles['3']=='Healer' and disk().job_profiles['3']=='Healer','Fixture: job 3 is linked to Healer.');
command('/vg profile link "Melee"');
assert(settings().job_profiles['3']=='Melee' and disk().job_profiles['3']=='Melee','link "Name" links the current job to that profile.');
command('/vg profile link 1 "Healer"');
assert(settings().job_profiles['1']=='Healer' and settings().job_profiles['3']=='Melee','link <job> "Name" links that job.');
MOCK.printed={};
command('/vg profile link WAR "Healer"');
assert(said('That profile was not found.') and settings().job_profiles['3']=='Melee' and settings().job_profiles['1']=='Healer',
    'A job given by name is read as the profile name, so nothing is linked by mistake.');
command('/vg profile link 1');
assert(settings().job_profiles['1']==nil and disk().job_profiles['1']==nil,'link <job> with no name unlinks that job.');
MOCK.printed={};command('/vg profile');
assert(said('link [job] "Name"'),'The usage line shows the job ID as optional.');

-- Delete, recover, then Undo and Redo keep the recovered link and active profile.
command('/vg profile link 3 "Healer"');
command('/vg profile load "Healer"');
assert(settings().active_profile=='Healer','Fixture: Healer is active.');
command('/vg set style.font_size 25');
command('/vg profile delete "Healer"');
assert(settings().job_profiles['3']==nil and settings().active_profile=='','Fixture: the delete removed the link and active profile.');
command('/vg profile recover');
assert(settings().job_profiles['3']=='Healer' and settings().active_profile=='Healer','Fixture: the recovery put them back.');
command('/vg undo');
assert(settings().style.font_size~=25,'Fixture: undo put the font back.');
assert(settings().job_profiles['3']=='Healer' and disk().job_profiles['3']=='Healer'
    and settings().active_profile=='Healer' and disk().active_profile=='Healer',
    'Undoing an unrelated change after a recovery keeps the recovered job link and active profile.');
command('/vg profile delete "Healer"');
command('/vg profile recover');
command('/vg redo');
assert(settings().style.font_size==25,'Fixture: redo put the font back.');
assert(settings().job_profiles['3']=='Healer' and disk().job_profiles['3']=='Healer' and disk().active_profile=='Healer',
    'Redoing an unrelated change after a recovery keeps them too.');
-- Without a recovery, Undo still never brings back a link to a deleted profile.
command('/vg set style.font_size 26');
command('/vg profile delete "Healer"');
command('/vg undo');
assert(settings().job_profiles['3']==nil and settings().active_profile=='','Undo after a delete does not link the deleted profile.');

-- Closing the window with /vg is saved.
command('/vg');MOCK.frame(.11);MOCK.frame(.11);
MOCK.frame(.11);MOCK.frame(1);
-- Opening it is navigation, which the next save writes.
app.callbacks.save();
assert(settings().window.open and disk().window.open==true,'Fixture: the open window is saved.');
command('/vg');
assert(settings().window.open==false and disk().window.open==false,'Closing with /vg is saved, so the window does not open on the next load.');
