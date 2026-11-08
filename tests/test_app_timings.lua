-- With timings available, each Present records the refresh, the draws and the whole frame as stages of their own,
-- and /vg report carries the timing snapshot. The load event times its own parts (the module requires, its font part
-- and the sound list) and itself; the rest runs as warmup steps from the second Present after it, each
-- timed under its own name, with the first Present, each Present's steps and the whole warmup timed too, and the first
-- refresh in parts. A part of the load that fails is said once in plain words, the report keeps why, and the load goes
-- on.
local store=require('core.store');
local copy=store.copy;
local snapshot={valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,self_effects={},party={},entities={}};
local timing={stages={}};
package.loaded['core.performance']={
    now=function()return MOCK.now*1000;end,
    record=function(stage,started)
        assert(type(started)=='number' and started<=MOCK.now*1000,'A stage is timed from a start before its end: '..tostring(stage));
        timing.stages[stage]=(timing.stages[stage] or 0)+1;
        return true;
    end,
    zone_begin=function()return true;end,zone_ready=function()return true;end,
    snapshot=function()return {unit='ms',overlapping=true,retained=true};end};
package.loaded['core.client']={load=function()end,read=function()return copy(snapshot);end,visibility=function()return copy(snapshot);end};
package.loaded['core.observer']={read=function()return {};end};
package.loaded['ui.hud']={draw=function()end,draw_notices=function()end,cancel_gesture=function()end};
package.loaded['ui.settings_window']={draw=function()end,blocks_input=function()return false;end};
local app=dofile(ADDON_DIR..'/vantage.lua');
MOCK.now=1;app.refresh(1);
app.state.settings.party_ui.enabled=false;
for _=1,3 do app.state.wake=true;MOCK.frame(.02);end;
assert(timing.stages['frame.refresh']>0 and timing.stages['frame.render']==3 and timing.stages['draw.hud']==3
    and timing.stages['draw.settings']==3,'State refresh, the draws and the whole frame have separate stages.');

local original_write=store.write;
local recorded;
store.write=function(_,report)recorded=report;return true;end;
assert(app.callbacks.export_report());
store.write=original_write;
assert(recorded.performance.retained and recorded.performance.unit=='ms' and recorded.performance.overlapping,
    'Reports include the timing snapshot without treating nested stages as additive costs.');

local function said(text)
    local count=0;
    for _,line in ipairs(MOCK.printed)do if line:find(text,1,true)then count=count+1;end;end;
    return count;
end;
local fonts,sound=require('ui.fonts'),require('core.sound');
local font_load,sound_refresh=fonts.load,sound.refresh;
fonts.load,sound.refresh=function()end,function()end;
timing.stages={};
MOCK.fire('load');
for _,stage in ipairs({'load.requires','load.fonts','load.sound','load.event'})do
    assert(timing.stages[stage]==1,'The load event times its part: '..stage);
end;
for _,stage in ipairs({'load.client','load.chat','load.icons','load.jobs','load.recasts','load.xiview','clock.game_time','warmup.frame'})do
    assert(not timing.stages[stage],'The load event leaves this for the Presents: '..stage);
end;
app.state.wake=true;MOCK.frame(.02);
assert(timing.stages['load.first_present']==1 and not timing.stages['warmup.frame'],'The first Present is timed and runs no step.');
for _,part in ipairs({'client_read','read_settings','tracker','chat','view','recasts','roster','rest'})do
    assert(timing.stages['first_refresh.'..part]==1,'The first refresh is timed in parts: '..part);
end;
for _=1,3 do app.state.wake=true;MOCK.frame(.02);end;
assert(timing.stages['warmup.frame']>=1 and timing.stages['warmup.total']==1,'The Presents that run steps and the whole warmup are timed.');
assert(timing.stages['clock.game_time']==1 and timing.stages['fonts.face']==1,
    'Each step is timed under its own name.');
assert(timing.stages['first_refresh.client_read']==1 and timing.stages['load.first_present']==1,'Only the first refresh is split.');
MOCK.fire('command',{command='/vg report'});
assert(timing.stages['command.report']==1,'/vg report is timed.');
store.write=function(_,report)recorded=report;return true;end;
assert(app.callbacks.export_report());
store.write=original_write;
assert(recorded.startup and recorded.startup.spread and recorded.startup.ready and #recorded.startup.steps>0,
    'The report carries the warmup: its steps and when the displays could draw.');

fonts.load=function()error('Measured startup failure',0);end;
assert(pcall(MOCK.fire,'load'),'A load part that fails does not stop the load.');
assert(timing.stages['load.fonts']==2,'A failed part still records its cost.');
assert(timing.stages['load.sound']==2 and timing.stages['load.event']==2,'The rest of the load goes on.');
assert(said('Measured startup failure')==0 and said('load.fonts')==0
    and said('Part of Vantage could not load (the fonts), so it goes on without it. /vg report has the reason.')==1,
    'The failure is said once, in plain words.');
local failed=require('core.warmup').report().failed;
assert(#failed==1 and failed[1].name=='load.fonts' and failed[1].problem=='Measured startup failure',
    'The report keeps the part and why.');
MOCK.frame(.02);MOCK.frame(.02);
assert(timing.stages['clock.game_time']==1 and timing.stages['warmup.total']==2,'The warmup still runs after it.');
-- A sounds folder that can't be read is said the same way, though sound.refresh returns why rather than throwing.
fonts.load=function()end;
sound.refresh=function()return {},'The local sounds folder could not be opened.';end;
MOCK.fire('load');
assert(said('Part of Vantage could not load (the sound list), so it goes on without it. /vg report has the reason.')==1,
    'A sounds folder that can\'t be read is said once.');
failed=require('core.warmup').report().failed;
assert(#failed==1 and failed[1].name=='load.sound' and failed[1].problem=='The local sounds folder could not be opened.',
    'The report keeps why.');
fonts.load,sound.refresh=font_load,sound_refresh;
assert(#MOCK.commands==0);
