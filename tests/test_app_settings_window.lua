-- The settings window opens on top of the panels, and a settings page that fails doesn't take the panels down.
local store=require('core.store');
local copy=store.copy;
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_effects={{effect=33,slot=0}},party={},entities={}};
local hooks,order={},{};
local blocking=false;
local function count(list,name) list[name]=(list[name] or 0)+1; end;
package.loaded['core.client']={load=function()end,read=function()return copy(snapshot);end,visibility=function()return copy(snapshot);end};
package.loaded['core.observer']={read=function()return {};end};
package.loaded['core.native_party_ui']={status=function()return {available=true};end,treasure_open=function()return false;end};
package.loaded['ui.native_party_hud']={cancel_layout_gesture=function()end,
    draw=function()order[#order+1]='party';return false,{},{};end};
package.loaded['ui.hud']={
    draw=function()order[#order+1]='hud';end,
    draw_notices=function()end,cancel_gesture=function()end};
package.loaded['ui.settings_window']={blocks_input=function(s)return blocking and s.window.open;end,
    draw=function(settings,_,callbacks)
        order[#order+1]=settings.window.open and 'window' or 'closed';
        local hook=settings.window.open and hooks.window or not settings.window.open and hooks.closed;
        if hook then hook(settings,callbacks);end;
    end};
local app=dofile(ADDON_DIR..'/vantage.lua');
MOCK.now=1;app.refresh(1);
local settings=app.state.settings;
local function showing()
    settings.enabled=true;
    settings.party_ui.enabled=true;
end;
showing();
local function present()order={};MOCK.frame(.011);end;
local function scene()MOCK.now=MOCK.now+.001;MOCK.fire('d3d_beginscene',true);end;
local function command(text)local event={command=text};MOCK.fire('command',event);assert(event.blocked);settings=app.state.settings;end;
local function position(name) for index,value in ipairs(order) do if value==name then return index;end;end;end;
local function panels()return position('hud') and position('party') and true or false;end;

-- Loaded with the settings window saved open: everything is created on the first Present. The window
-- waits a frame, so it's created after every panel exists and opens on top of them.
settings.window.open=true;
present();scene();
assert(panels() and not position('window'),'The first Present draws every panel and not the appearing settings window; order: '
    ..table.concat(order,','));
present();scene();
assert(order[1]=='window' and panels(),'The next Present creates the settings window, then draws every panel.');

-- A settings page that fails still ends its own frame, as any display failure does.
present();scene();
local before,file=copy(settings),store.read(app.state.path);
local failures=0;
hooks.window=function()failures=failures+1;error('Fixture settings page failure.');end;
present();
assert(#order==1 and order[1]=='window','No panel draws inside the failed settings window.');
scene();
-- Then the window stops, so the panels come back on the next frames.
blocking=true;
for i=1,10 do
    present();
    assert(not position('window') and panels(),'A stopped settings window is not drawn, and every panel is: frame '..i);
    scene();
end;
assert(failures==1,'The failing page is drawn once.');
assert(not app.callbacks.settings_blocks_input(10,10,false,false),'A stopped settings window takes no mouse input.');
local function reported()
    local count=0;
    for _,message in ipairs(MOCK.printed)do if message:find('Fixture settings page failure.',1,true)then count=count+1;end;end;
    return count;
end;
assert(reported()==1,'The failure is reported once.');
assert(store.equal(before,settings) and settings.window.open,'Stopping the settings window changes no setting or lock.');
assert(store.equal(file,store.read(app.state.path)),'Stopping the settings window saves nothing.');

-- /vg closes a stopped window. The close is saved, so the failed window doesn't open again on the
-- next load. It stays stopped while closed, and the next /vg opens it and tries it again.
hooks.window=nil;
command('/vg');
file=store.read(app.state.path);
assert(not settings.window.open,'/vg closes a stopped settings window rather than drawing it again.');
assert(type(file.window)=='table' and file.window.open==false,'The close is saved, so the next load does not open the failed window.');
present();scene();
assert(not position('window') and not position('closed') and panels(),'The closed window stays stopped, and every panel draws.');
command('/vg');
assert(settings.window.open and settings.window.tab=='Home','The next /vg opens it on Home.');
assert(app.callbacks.settings_blocks_input(10,10,false,false),'A reopened settings window takes the mouse again.');
present();scene();
assert(not position('window') and panels(),'The reopened window waits its appearing frame.');
present();scene();
assert(order[1]=='window' and panels(),'Then it draws first again.');

-- A command can land right after the failing Present. The window it opens still waits its appearing
-- frame, so it opens on top of the panels.
local count=reported();
hooks.window=function()error('Fixture settings page failure.');end;
present();hooks.window=nil;
assert(#order==1 and order[1]=='window' and reported()==count+1,'Fixture: the page failed.');
command('/vg filters');
scene();present();scene();
assert(settings.window.tab=='Filters' and not position('window') and panels(),
    'A window opened right after the failing Present waits its appearing frame.');
present();scene();
assert(order[1]=='window' and panels(),'Then it draws first.');

-- Every stop is reported, even one that repeats the last error.
local function stop(label)
    count=reported();
    hooks.window=function()error('Fixture settings page failure.');end;
    present();hooks.window=nil;scene();
    present();scene();assert(app.state.settings_stopped==true and not position('window') and panels(),'Fixture: stopped '..label..'.');
    assert(reported()==count+1,'The stop '..label..' is reported.');
end;
local function returns(label)
    present();scene();assert(not position('window'),label..' waits the appearing frame.');
    present();scene();
    assert(order[1]=='window' and panels(),label..' draws the settings window again.');
end;
-- A stopped window isn't tried again by anything else, open or closed.
local function holds(label)
    local failed;
    count,failed=reported(),failures;
    hooks.window=function()failures=failures+1;error('Fixture settings page failure.');end;
    hooks.closed=hooks.window;
    for i=1,3 do
        present();
        assert(not position('window') and not position('closed') and panels(),label..' keeps the settings window stopped: frame '..i);
        scene();
    end;
    assert(failures==failed and reported()==count,label..' does not try the failed page again.');
    hooks.window,hooks.closed=nil,nil;
end;

-- A command that opens a page tries it again.
stop('after reopening');
command('/vg filters');
present();scene();present();scene();
assert(order[1]=='window' and settings.window.tab=='Filters','Opening a page by command draws the window again.');

-- Closing it keeps the stop. Opening it by /vg set is a command that opens it, and so is setting a
-- stopped window open that is still open.
stop('before closing');
command('/vg set window.open false');
assert(not settings.window.open,'Fixture: /vg set closed it.');
holds('Closing it');
command('/vg set window.open true');
returns('/vg set window.open true');
stop('while open');
command('/vg set window.tab Durations');
assert(settings.window.open and settings.window.tab=='Durations','Fixture: /vg set changed the open window.');
holds('/vg set window.tab');
command('/vg set window.open true');
returns('/vg set window.open true on a window still open');

-- A closed window that fails stops too, so it doesn't fail again every frame.
command('/vg');
assert(not settings.window.open,'Fixture: closed.');
present();scene();
local closed=0;
count=reported();
hooks.closed=function()closed=closed+1;error('Fixture settings page failure.');end;
for _=1,4 do present();scene();end;
hooks.closed=nil;
assert(closed==1 and reported()==count+1 and panels(),'A closed window that fails is drawn once, then every panel is.');
command('/vg');
returns('/vg after a closed window failed');

-- The stop belongs to this character and the failed page. Replacing the settings keeps it, as every
-- other change does.
stop('before the changes that keep it');
command('/vg lock');holds('/vg lock');
command('/vg sort oldest');holds('/vg sort');
command('/vg minimal on');holds('/vg minimal');
command('/vg mute');holds('/vg mute');
command('/vg set style.font_size 21');
assert(settings.style.font_size==21,'Fixture: /vg set replaced the settings.');
holds('/vg set');
command('/vg skin Ember');holds('/vg skin');
command('/vg font XI View');
assert(settings.style.font=='XI View','Fixture: /vg font replaced the settings.');
holds('/vg font');
command('/vg starter melee');holds('/vg starter');
command('/vg reset alerts');holds('/vg reset alerts');
command('/vg unlock');
assert(not settings.party_ui.locked,'Fixture: unlocked.');
holds('/vg unlock');
command('/vg undo');
assert(settings.party_ui.locked,'Fixture: undo locked it again.');
holds('/vg undo');
command('/vg redo');
assert(not settings.party_ui.locked,'Fixture: redo unlocked it.');
holds('/vg redo');
assert(app.callbacks.profile_save('Alpha',false),'Fixture: profile saved.');
command('/vg lock');
command('/vg profile load Alpha');
assert(not settings.party_ui.locked,'Fixture: the profile restored its unlocked layout.');
holds('A profile load');
assert(app.callbacks.profile_link(2,'Alpha'),'Fixture: Alpha loads on the next job.');
command('/vg lock');
-- Another profile is the active one, so the job change loads Alpha.
assert(app.callbacks.profile_save('Spare',false),'Fixture: another profile is active.');
snapshot.job=2;
MOCK.fire('packet_in',{id=0x063});
holds('A job change');
settings=app.state.settings;
assert(not settings.party_ui.locked and settings.active_profile=='Alpha','Fixture: the job change loaded Alpha.');
command('/vg set shared_layout true');
assert(settings.shared_layout,'Fixture: the settings are shared.');
holds('Sharing');
local polled=app.state.shared_at;
MOCK.now=MOCK.now+3;
holds('The shared layout poll');
assert(app.state.shared_at~=polled,'Fixture: the shared layout was polled.');

-- A window reset tries it again, alone or with everything else.
command('/vg reset window');
assert(settings.window.open,'Fixture: resetting the window keeps it open.');
returns('/vg reset window');
stop('before resetting everything');
command('/vg reset');
assert(settings.window.open,'Fixture: resetting everything keeps the window open.');
showing();
returns('/vg reset');

-- The next character's saved-open window isn't hidden by a stop on this one.
local other=copy(settings);
local path=require('core.identity').root()..'Other_1002/settings.json';
assert(other.window.open and store.write(path,other),'Fixture: the next character saved with the window open.');
stop('before a character switch');
snapshot.id,snapshot.name=1002,'Other';
MOCK.fire('packet_in',{id=0x063});
present();scene();settings=app.state.settings;
assert(app.state.path==path and settings.window.open and not position('window'),
    'Fixture: the next character loaded with the window open, which waits its appearing frame.');
present();scene();
assert(order[1]=='window' and panels(),'A character switch draws the next character\'s saved-open window.');
stop('on the next character');
