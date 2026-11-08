local store = require('core.store');
local filters = require('core.effect_filters');
local live = {valid=true,id=1001,name='Tester',zone=102,job=1,self_known=true,
    self_effects={{effect=253,slot=0,deadline=120,raw_timer=7200}},
    party={{id=1002,name='Friend',group=1,slot=1,scope='party',valid=true}},entities={}};
local reads, roster_reads, job, captured = 0, 0, 3, {};
package.loaded['core.client'] = {read=function() reads=reads+1; return store.copy(live); end};
package.loaded['core.roster'] = {read=function()
    roster_reads=roster_reads+1;
    return {valid=live.valid,id=live.id,zone=live.zone,members={
        {id=1001,name='Tester',job=1,group=1,slot=0},
        {id=1002,name='Friend',job=job,group=1,slot=1}}};
end};
package.loaded['ui.hud'] = {draw=function(view,settings,now,callbacks)
    captured.view,captured.callbacks=view,callbacks;
end,draw_notices=function() end};
local function frame_draw(_,subjects,settings,now,callbacks)
    captured.frame=callbacks;
    return false,{};
end;
package.loaded['ui.party_hud'] = {draw=frame_draw,cancel_layout_gesture=function() end};
package.loaded['ui.native_party_hud'] = {draw=frame_draw,cancel_layout_gesture=function() end};
package.loaded['ui.settings_window'] = {draw=function() end};
local app=dofile(ADDON_DIR..'/vantage.lua');
local function frame(at)
    MOCK.now=at;
    MOCK.fire('d3d_present');
    assert(app.state.problem==nil,app.state.problem);
end;
app.refresh(1);
app.state.settings.window.open=false;
app.state.settings.party_ui.enabled=false;
local config=app.state.settings.effect_filters;
assert(#config.rules==0 and roster_reads==0);
frame(1.01);
assert(not captured.callbacks.effect_filters.active and captured.view.effect_recipients==nil);
config.rules={{enabled=true,effect=253,kind='all',name='',job=0,scope='all'}};
frame(1.02);
local first=captured.view.effect_recipients;
assert(first[1001].is_self and first[1002].name=='friend');
assert(captured.frame.effect_recipients==first and captured.frame.effect_filters.active);
assert(reads==1 and roster_reads==0,'Global/name/group rules do not request extra client reads.');
frame(1.03);
assert(captured.view.effect_recipients==first,'Frames reuse recipient metadata until the next snapshot.');
assert(#captured.view.rows==1 and #app.state.party_subjects[1001].effects==1,
    'Tracker and alert inputs retain hidden effects.');
config.rules[1].job=3;
frame(1.04);
assert(reads==2 and roster_reads==1 and app.state.roster_ready,
    'A new job restriction requests current roster jobs even with party frames disabled.');
assert(captured.view.effect_recipients[1002].job==3);
assert(filters.hide(captured.frame.effect_filters,{effect=253,kind='buff'},captured.view.effect_recipients[1002]));
frame(1.05);
assert(reads==2 and roster_reads==1,'Job filters keep the existing reconciliation interval.');
job=nil;
MOCK.fire('packet_in',{id=0x0DD});
frame(1.06);
assert(reads==3 and roster_reads==2 and captured.view.effect_recipients[1002].job==nil);
assert(not filters.hide(captured.frame.effect_filters,{effect=253},captured.view.effect_recipients[1002]),
    'A no-longer-known job does not retain its old match.');
config.enabled=false;
frame(1.2);
assert(roster_reads==2 and not captured.frame.effect_filters.active and captured.view.effect_recipients==nil,
    'Pausing the rules releases their extra roster demand.');
config.enabled=true;
config.rules[1].job=0;
live.valid=false;
frame(1.4);
assert(next(captured.view.effect_recipients)==nil,'Invalid player state clears filter recipients.');
assert(#MOCK.commands==0,'Visibility rules do not send gameplay commands.');
