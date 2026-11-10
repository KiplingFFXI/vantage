-- With a timing clock, as the game has, so the load leaves what it makes to the warmup (core/warmup.lua).
package.loaded['core.performance'] = { now=function() return MOCK.now*1000; end, record=function() return true; end,
    add=function() return true; end, zone_begin=function() return true; end, zone_ready=function() return true; end,
    snapshot=function() return {}; end, origin_ms=0 };
local store = require('core.store');
local defaults = require('ui.defaults');
local snapshot = { valid=true,id=1001,name='Tester',zone=102,job=1,job_name='WAR',self_known=true,
    self_effects={{effect=33,slot=0,deadline=100,raw_timer=6000}},party={},entities={},
    target={id=16781313,name='Crab',index=1,kind='monster'} };
local observed, hud_calls, notice_calls, settings_calls = 0, 0, 0, 0;
package.loaded['core.client'] = { read=function() return store.copy(snapshot); end, load=function() end };
package.loaded['core.observer'] = { read=function(e) observed=observed+1; return e.observations or {}; end };
package.loaded['ui.hud'] = {
    draw=function(_,settings) notice_calls=notice_calls+1; if settings.enabled then hud_calls=hud_calls+1; end end,
    draw_notices=function() notice_calls=notice_calls+1; end,
};
package.loaded['ui.settings_window'] = { draw=function() settings_calls=settings_calls+1; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
local function command(text)
    local e = {command=text}; MOCK.fire('command',e); return e;
end
local function refresh(t) MOCK.now=t; app.refresh(t); end
local function text_file(path)
    local file=assert(io.open(path,'rb')); local text=file:read('*a'); file:close(); return text;
end
MOCK.fire('load'); refresh(0);
assert(app.state.path:find('/Tester_1001/settings.json',1,true));
assert(#app.state.view.rows==1 and #app.state.view.notices==0, 'Loading an active effect is a quiet baseline.');
assert(app.state.ready==false, 'After /load the displays wait for the warmup.');
assert(command('/echo hello').blocked==nil and not app.state.settings.window.open);
assert(app.state.ready==false, 'A command that isn\'t ours leaves the warmup be.');
assert(command('/vg').blocked and app.state.settings.window.open);
assert(app.state.ready==true, 'A Vantage command runs what is left of the warmup first.');
command('/vantage hide'); MOCK.frame(0.2); MOCK.frame(0.2);
assert(hud_calls==0 and notice_calls==2 and settings_calls==1, 'Hide suppresses panels while notices and settings remain available.');
command('/vantage show'); MOCK.frame(0.2); assert(hud_calls==1);
app.state.settings.enabled=false; MOCK.frame(0.2);
assert(hud_calls==1 and notice_calls==4 and settings_calls==3, 'Show panels off still draws the visual alert channel.');
app.state.settings.enabled=true;
command('/vantage unlock'); assert(not app.state.settings.panels.self_buffs.locked);
command('/vantage undo'); assert(app.state.settings.panels.self_buffs.locked);
command('/vantage watch'); command('/vg watch');
assert(#app.state.settings.watch_ids==1 and app.state.settings.watch_ids[1]==16781313);
assert(app.state.settings.panels.watch.enabled);
command('/vg unwatch'); assert(#app.state.settings.watch_ids==0);
-- An ID that isn't a number is no ID, and never your target.
local printed=#MOCK.printed;
command('/vg watch 12x'); command('/vg unwatch 12x');
assert(#app.state.settings.watch_ids==0 and #MOCK.printed==printed+2 and MOCK.printed[printed+1]:find('12x is not an entity ID',1,true),
    "A typed ID that isn't a number watches nothing: "..tostring(MOCK.printed[printed+1]));
command('/vg profile save "Healer bars"');
assert(app.callbacks.profile_list()[1]=='Healer bars');
app.callbacks.changed('before'); app.state.settings.panels.self_buffs.width=480; app.callbacks.changed('after');
assert(app.callbacks.save());
command('/vg profile load "Healer bars"');
assert(app.state.settings.panels.self_buffs.width==300 and app.state.settings.window.open);
assert(app.callbacks.profile_link(3,'Healer bars'));
-- Another profile is the active one, so the job change loads Healer bars.
command('/vg profile save "Spare"'); assert(app.state.settings.active_profile=='Spare','Fixture: another profile is active.');
app.state.settings.panels.self_buffs.width=510; snapshot.job=3; refresh(1);
assert(app.state.settings.panels.self_buffs.width==300 and app.state.settings.active_profile=='Healer bars');
command('/vg profile delete "Spare"');
command('/vg profile delete "Healer bars"');
assert(#app.callbacks.profile_list()==0 and app.state.settings.job_profiles['3']==nil);
local original=text_file(app.state.path);
MOCK.file_replace_error=true;
app.callbacks.changed('before'); app.state.settings.panels.self_buffs.width=420; app.callbacks.changed('after');
assert(not app.callbacks.save() and app.state.dirty);
assert(text_file(app.state.path)==original, 'A failed settings save retains the previous complete file.');
MOCK.file_replace_error=false; assert(app.callbacks.save());
local event={id=0x028,observations={{kind='apply',entity_id=16781313,entity_name='Crab',effect=2,duration=30,source=1001,scope='target'}}};
MOCK.fire('packet_in',event);
assert(observed==1 and event.blocked==nil and #app.state.queue==1);
refresh(2); assert(#app.state.view.rows==2);
local injected={id=0x028,injected=true,observations=event.observations}; MOCK.fire('packet_in',injected);
assert(observed==1 and #app.state.queue==0 and injected.blocked==nil);
local reset={id=0x00B,observations={{kind='reset',reason='zone'}}}; MOCK.fire('packet_in',reset);
assert(#app.tracker:view(2,app.state.settings,snapshot).rows==0 and #app.alerts:view(2)==0);
assert(reset.blocked==nil and #app.state.queue==0);
refresh(3); assert(#app.state.view.rows==1 and #app.state.view.notices==0);
command('/vg watch 16781313');
command('/vg set style.font_size 20');
MOCK.fire('packet_in',{id=0x00A,observations={{kind='reset',reason='Zone changed'}}});
assert(#app.state.settings.watch_ids==0, 'A same-zone entry packet clears watched IDs immediately.');
command('/vg undo');
assert(#app.state.settings.watch_ids==0, 'Undo cannot restore watched IDs from before same-zone reentry.');
command('/vg watch 16781313'); snapshot.zone=103; refresh(4);
assert(#app.state.settings.watch_ids==0, 'A zone change clears watched entity IDs.');
local rule=defaults.rule('remaining'); rule.effect=33; rule.thresholds={10}; rule.chat=false; rule.sound='';
app.state.settings.alerts.rules={rule};
for t=5,85,5 do refresh(t); end
refresh(92);
assert(#app.state.view.notices==1, 'The entrypoint forwards threshold crossings to local alerts.');
command('/vg mute'); assert(app.state.settings.alerts.muted and #app.alerts:view(92)==0);
command('/vg mute'); refresh(93); assert(#app.state.view.notices==0, 'Unmute cannot replay an old crossing.');
snapshot.dead=true; snapshot.self_effects={}; refresh(94);
assert(#app.state.view.notices==0, 'Death cleanup is quiet.');
assert(#MOCK.commands==0, 'Tracking, alerts and commands must not send gameplay commands.');
MOCK.fire('unload');
return true;
