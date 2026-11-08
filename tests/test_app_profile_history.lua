-- Profile changes kept through Undo and Redo: a deleted profile recovered after other changes keeps its job
-- link and active profile through every step, saving as a profile keeps it active through earlier steps, and
-- /vg unwatch says why it did nothing.
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
assert(app.callbacks.profile_save('Melee',false),'Fixture: Melee is saved.');
local function kept(label)
    assert(settings().job_profiles['1']=='Melee' and disk().job_profiles['1']=='Melee' and settings().active_profile=='Melee',
        label..' keeps the recovered job link and active profile.');
end;
-- A change made after the delete, then Undo of it after the recovery.
command('/vg profile link 1 "Melee"');
command('/vg profile delete "Melee"');
command('/vg set style.font_size 25');
command('/vg profile recover');
kept('Fixture: the recovery');
command('/vg undo');
assert(settings().style.font_size~=25,'Fixture: undo put the font back.');
kept('Undoing a change made between the delete and the recovery');
command('/vg redo');
assert(settings().style.font_size==25,'Fixture: redo put the font back.');
kept('Redoing it');
-- An Undo made after the delete, then Redo after the recovery.
command('/vg set style.font_size 26');
command('/vg profile delete "Melee"');
command('/vg undo');
command('/vg profile recover');
command('/vg redo');
assert(settings().style.font_size==26,'Fixture: redo put the font back.');
kept('Redoing an Undo made between the delete and the recovery');
-- The step that made the link still unlinks when it is undone.
for _=1,3 do command('/vg undo'); end;
assert(settings().job_profiles['1']==nil,'Undoing the link itself still unlinks the job.');

-- Saving as a new profile keeps it active through Undo of an earlier change.
command('/vg set style.font_size 21');
command('/vg profile save "Ranged"');
assert(settings().active_profile=='Ranged','Fixture: saving made Ranged active.');
command('/vg undo');
assert(settings().style.font_size~=21,'Fixture: undo put the font back.');
assert(settings().active_profile=='Ranged' and disk().active_profile=='Ranged','Undo of an earlier change keeps the profile just saved.');

-- /vg unwatch explains a no-op and leaves the settings alone.
local history=#app.state.history;
MOCK.printed={};command('/vg unwatch');
assert(said('Select a watched entity to stop watching.') and #app.state.history==history,'/vg unwatch with no target says so.');
MOCK.printed={};command('/vg unwatch 12345');
assert(said('That entity is not watched.') and not app.state.dirty,'/vg unwatch of an entity not watched says so.');
command('/vg watch 12345');
MOCK.printed={};command('/vg unwatch 12345');
assert(#MOCK.printed==0 and #settings().watch_ids==0,'Unwatching a watched entity removes it quietly.');
