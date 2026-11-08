-- /vg overhead on, off, preview and calibrate. On, off and preview are each one Undo step that saves and says what is
-- now on; off ends the samples and the samples turn the icons on; on and preview show displays /vg hide hid, as /vg
-- party show does. Calibrate asks the next frame to read the target. Anything else prints the usage, /vg help lists
-- them all, /vg get and /vg set reach the overhead settings, and /vg reset overhead puts the page back in one step.
local store=require('core.store');
local SNAP={valid=true,id=1001,name='Tester',zone=102,job=3,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(SNAP);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,status=function()return {active=false};end};
local overhead=require('core.overhead');
local calibrated=0;
overhead.calibrate=function(settings) assert(settings==package.loaded['vantage_app'].state.settings);calibrated=calibrated+1;end;
local app=dofile(ADDON_DIR..'/vantage.lua');
package.loaded['vantage_app']=app;
MOCK.fire('load');app.refresh(0);
local function command(text) local event={command=text};MOCK.fire('command',event);assert(event.blocked,text);end;
local function said() return MOCK.printed[#MOCK.printed] or ''; end;
local function disk() return store.read(app.state.path).overhead; end;
local o=function() return app.state.settings.overhead; end;
assert(not o().enabled and not o().preview,'Overhead icons start off, with no samples.');

local function step(text,label,enabled,preview,line)
    local count,printed=#app.state.history,#MOCK.printed;
    command(text);
    assert(o().enabled==enabled and o().preview==preview,text..' leaves on '..tostring(enabled)..', samples '..tostring(preview));
    assert(#app.state.history==count+1 and app.state.history[#app.state.history].label==label,text..' is one Undo step: '..label);
    assert(disk().enabled==enabled and disk().preview==preview,text..' saves.');
    assert(#MOCK.printed==printed+1 and said():find(line,1,true),text..' says '..line..': '..said());
end;
step('/vg overhead on','Overhead icons on',true,false,'Overhead icons are on.');
step('/vg overhead preview','Overhead icons preview',true,true,'Overhead sample icons are on.');
step('/vg overhead preview','Overhead icons preview',true,false,'Overhead sample icons are off.');
step('/vg overhead off','Overhead icons off',false,false,'Overhead icons are off.');
-- The samples turn the icons on, and off ends the samples.
step('/vg overhead preview','Overhead icons preview',true,true,'Overhead sample icons are on.');
step('/vg overhead off','Overhead icons off',false,false,'Overhead icons are off.');
-- Undo and Redo step through them.
assert(app.callbacks.undo() and o().enabled and o().preview,'Undo brings back the icons and their samples.');
assert(app.callbacks.redo() and not o().enabled and not o().preview,'Redo turns them off again.');
-- A command that changes nothing adds no step.
local count=#app.state.history;
command('/vg overhead off');
assert(#app.state.history==count and said():find('Overhead icons are off.',1,true),'Off again adds no step.');
-- On and the samples show displays /vg hide hid; off doesn't.
command('/vg hide');
command('/vg overhead off');
assert(app.state.hidden,'Off leaves the displays hidden.');
command('/vg overhead on');
assert(not app.state.hidden,'On shows the hidden displays.');
command('/vg hide');
command('/vg overhead preview');
assert(not app.state.hidden and o().preview,'The samples show the hidden displays.');

-- Calibrate, the usage line and the command list.
command('/vg overhead calibrate');
assert(calibrated==1,'Calibrate asks the next frame to read the target.');
count=#app.state.history;
for _,text in ipairs({'/vg overhead','/vg overhead show','/vg overhead on now','/vg overhead calibrate again'})do
    command(text);
    assert(said():find('Usage: /vg overhead on|off|preview|calibrate',1,true),text..' prints the usage: '..said());
end;
assert(calibrated==1 and #app.state.history==count,'Usage changes nothing.');
command('/vg help');
assert(said():find('overhead [on|off|preview|calibrate]',1,true),'/vg help lists them: '..said());

-- /vg get and /vg set reach what the page doesn't show, such as a race's head height, each set one Undo step that
-- saves; a value out of range changes nothing.
command('/vg get overhead.head.race_heights.8');
assert(said():find('overhead.head.race_heights.8 = 2.05',1,true),'/vg get reads a race height: '..said());
count=#app.state.history;
command('/vg set overhead.head.race_heights.5 1.1');
assert(o().head.race_heights[5]==1.1 and disk().head.race_heights[5]==1.1,'/vg set changes a race height and saves.');
assert(#app.state.history==count+1 and app.state.history[#app.state.history].label=='Set overhead.head.race_heights.5','In one Undo step.');
command('/vg set overhead.head.race_heights.5 9');
assert(o().head.race_heights[5]==1.1 and said():find('outside the allowed',1,true),'A height out of range changes nothing: '..said());
command('/vg set overhead.camera.capture scene');
assert(o().camera.capture=='scene','It reaches the camera settings.');
command('/vg set overhead.head.heights {"Fafnir":9}');
assert(o().head.heights.Fafnir==9,'And the heights by name, as a whole map.');
-- /vg set turning the icons off ends their samples as every other way does, so Home has none to end; turning the samples
-- on turns the icons on, as /vg overhead preview does.
local window=require('ui.settings_window');
local function home()
    local s=app.state.settings;
    s.window.open,s.window.tab,MOCK.imgui_calls=true,'Home',{};
    window.draw(s,{rows={},context={valid=true,job=3,entities={}}},app.callbacks);
    for _,call in ipairs(MOCK.imgui_calls)do if call[1]=='Button' and call[2]=='End samples##main' then return true;end;end;
    return false;
end;
assert(o().enabled and o().preview and home(),'Fixture: the main page offers End samples.');
command('/vg set overhead.enabled false');
assert(not o().enabled and not o().preview and not disk().preview,'/vg set turning the icons off ends their samples.');
assert(not home(),'The main page has no samples to end once the icons are off.');
command('/vg set overhead.preview true');
assert(o().enabled and o().preview and disk().enabled,'/vg set turning the samples on turns the icons on: '..said());

-- /vg reset overhead.
app.state.settings.overhead.max_units,app.state.settings.overhead.types.mob.layout=4,'split';
command('/vg reset overhead');
assert(app.state.history[#app.state.history].label=='Reset Overhead icons' and require('core.customization').equal(o(),require('ui.defaults').make().overhead),
    'Reset overhead puts the page back in one step.');
assert(#MOCK.commands==0,'The commands send nothing to the game.');
return 'The overhead commands turn the icons and their samples on and off as one Undo step each';
