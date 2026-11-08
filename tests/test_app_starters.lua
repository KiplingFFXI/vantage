-- The starter profiles through the addon itself: Apply as one Undo step with its samples, /vg starter without them, and
-- Save as new after them, which makes a profile a job link can load.
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
local custom=require('core.customization');
local app=dofile(ADDON_DIR..'/vantage.lua');
local function settings()return app.state.settings;end;
local function disk()return store.read(app.state.path);end;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked,'Fixture: the command ran.');end;
local function frames(count)for _=1,count do MOCK.frame(.11);end;end;
local function said(text)
    for _,message in ipairs(MOCK.printed)do if message:find(text,1,true)then return true;end;end;
    return false;
end;
MOCK.fire('load');app.refresh(0);
app.state.dirty=true;assert(app.callbacks.save(),'Fixture: the settings are on disk.');
local first=store.copy(settings());

-- Nothing changes until a starter is applied.
assert(not first.panels.party.enabled and not first.preview,'Fixture: fresh settings have no party timers or samples.');

-- Apply: every display that's on shows samples, it's saved, and it's one step of Undo.
local revision=app.callbacks.settings_revision();
assert(app.callbacks.starter('healer',true),'Apply works.');
local s=settings();
assert(s.panels.party.enabled and s.panels.party.mine_only and s.party_ui.enabled and s.overhead.units.party,'It is on.');
assert(s.preview and s.party_ui.preview and s.overhead.preview and s.pet.preview,'It shows samples.');
assert(not s.rolls.preview and not s.party_cooldowns.preview,'A display that is off shows none.');
assert(#s.alerts.rules==1 and s.alerts.rules[1].name=='Silenced','It adds its rule.');
assert(app.callbacks.settings_revision()>revision,'Home sees the change, so its label moves.');
assert(disk().panels.party.enabled,'It is saved.');
command('/vg undo');
assert(custom.equal(settings(),first),'One Undo puts everything back: the displays, the samples and the rules.');
assert(not disk().panels.party.enabled,'And that is saved.');
command('/vg redo');
assert(settings().panels.party.enabled and settings().preview and #settings().alerts.rules==1,'Redo brings all of it back.');
command('/vg undo');

-- /vg starter goes by name, in any case, with no samples.
command('/vg starter healer');
assert(settings().panels.party.enabled and not settings().preview and not settings().overhead.preview,'/vg starter shows no samples.');
command('/vg starter PET');
assert(settings().overhead.units.pet and not settings().panels.party.enabled and not settings().party_ui.enabled,'/vg starter pet works.');
command('/vg starter crowd control');
assert(settings().panels.watch.list_debuffed and settings().panels.watch.enabled,'A name of two words works.');
command('/vg starter "Crowd control"');
assert(settings().panels.watch.list_debuffed,'And in quotes.');
-- A name that isn't one says what is, and changes nothing.
local held=store.copy(settings());
MOCK.printed={};
command('/vg starter solo');
assert(said('Choose Melee, Tank, Healer, Support, Crowd control or Pet.'),'A name that isn\'t one is refused.');
assert(custom.equal(settings(),held),'Nothing changed.');
command('/vg undo');command('/vg undo');command('/vg undo');command('/vg undo');
assert(custom.equal(settings(),first),'Each one was one step.');

-- Apply and then Save as new makes a starter a normal profile.
assert(app.callbacks.starter('healer'),'Fixture: Healer is on.');
local seen=store.copy(settings());
assert(app.callbacks.profile_save('Healer',false),'The save works.');
local names=app.callbacks.profile_list();
assert(#names==1 and names[1]=='Healer','It is a normal profile.');

-- Loading it gives the starter with the look and positions it was saved with.
command('/vg set panels.target.x 345');
assert(app.callbacks.profile_load('Healer'),'It loads.');
s=settings();
assert(s.panels.party.enabled and s.party_ui.enabled and s.overhead.units.alliance and s.overhead.types.party.show_protect_shell,'The Healer starter is on.');
assert(s.panels.target.x==seen.panels.target.x,'A profile holds its positions.');
assert(require('core.starters').matching(s)=='healer','It reads as in use.');
-- Its Watched option goes with a profile.
assert(app.callbacks.starter('crowd control'),'Fixture: Crowd control.');
assert(app.callbacks.profile_save('Sleeper',false));
assert(app.callbacks.starter('melee'),'Fixture: Melee.');
assert(not settings().panels.watch.list_debuffed);
assert(app.callbacks.profile_load('Sleeper'));
assert(settings().panels.watch.list_debuffed,'A saved profile holds Also list enemies I debuff.');

-- "Load this profile when I change to WHM" works on it.
assert(app.callbacks.starter('melee'),'Fixture: Melee.');
frames(3);
command('/vg profile link 3 "Healer"');
snapshot.job=1;frames(3);
assert(not settings().panels.party.enabled,'Fixture: on WAR it is Melee.');
snapshot.job=3;frames(3);
assert(settings().panels.party.enabled and settings().active_profile=='Healer','The job link loads the starter.');
return true;
