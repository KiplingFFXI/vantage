-- A reminder clicked again adds no copy, and a hide picker hides nothing until an effect is chosen.
local store=require('core.store');
local SNAP={valid=true,id=1001,name='Tester',zone=102,job=3,self_known=true,self_effects={},party={},entities={}};
package.loaded['core.client']={load=function()end,read=function()return store.copy(SNAP);end};
package.loaded['core.observer']={read=function()return {};end};
local hud=require('ui.hud');
hud.draw,hud.draw_notices=function()end,function()end;
package.loaded['core.native_party_ui']={treasure_open=function()return false;end,status=function()return {active=false};end};
local imgui=require('imgui');
local defaults=require('ui.defaults');
local app=dofile(ADDON_DIR..'/vantage.lua');
local window=require('ui.settings_window');
MOCK.fire('load');app.refresh(0);
local combo,typed;
imgui.BeginCombo=function(label,preview)
    MOCK.imgui_calls[#MOCK.imgui_calls+1]={'BeginCombo',label,preview};
    return label==combo;
end;
local input_with_hint=imgui.InputTextWithHint;
imgui.InputTextWithHint=function(label,hint,value,...)
    if typed and typed[1]==label then value[1],typed=typed[2],nil;return true;end;
    return input_with_hint(label,hint,value,...);
end;
local view={rows={},context={valid=true,job=3}};
local function frame(step)
    step=step or {};
    combo,typed=step.combo,step.typed;
    MOCK.imgui_calls={};
    if step.click then MOCK.clicks[step.click]=true;end;
    window.draw(app.state.settings,view,app.callbacks);
    assert(not step.click or not MOCK.clicks[step.click],'The control is on the page: '..tostring(step.click));
    MOCK.clicks={};
end;
local function begin(tab,setup)
    local s=defaults.tidy(defaults.make());
    s.window.open,s.window.tab=true,tab;
    app.state.settings=s;
    if setup then setup(s);end;
    frame();
    return s;
end;
local function drawn(kind,label,value)
    for _,call in ipairs(MOCK.imgui_calls)do
        if call[1]==kind and call[2]==label and (value==nil or call[3]==value)then return true;end;
    end;
    return false;
end;
-- Whether the button is drawn inside a disabled block.
local function disabled(label)
    local depth=0;
    for _,call in ipairs(MOCK.imgui_calls)do
        if call[1]=='BeginDisabled' then depth=depth+(call[2]==false and 0 or 1);
        elseif call[1]=='EndDisabled' then depth=math.max(0,depth-1);
        elseif call[1]=='Button' and call[2]==label then return depth>0;end;
    end;
end;

-- Quick reminders on Alerts.
require('ui.panel_frame').open('notices','show');
for _,tab in ipairs({'Display'})do
    local s=begin(tab);
    local rules=s.alerts.rules;
    frame({click='Haste reminder##frame'});frame({click='Haste reminder##frame'});frame();
    assert(#rules==1 and rules[1].name=='Haste ending' and rules[1].effect==33,tab..': a second click adds no copy.');
    assert(drawn('TextWrapped','Haste reminder is already on.'),tab..': the second click says the reminder is already on.');
    rules[1].enabled=false;
    frame({click='Sleep reminder##frame'});frame({click='Haste reminder##frame'});frame();
    assert(#rules==2 and rules[1].enabled,tab..': clicking it again turns the reminder back on.');
    assert(drawn('TextWrapped','Haste reminder is on again.') and not drawn('TextWrapped','Haste reminder is already on.'),
        tab..': the note says the click turned the reminder back on.');
    -- A rule changed since is the player's own, so the reminder adds one beside it.
    rules[1].thresholds={20};
    frame({click='Haste reminder##frame'});
    assert(#rules==3 and rules[3].name=='Haste ending' and rules[3].thresholds[1]==30,tab..': a changed rule is left as it is.');
end;
-- Alerts opens the reminder it turned on: its row says Done.
local function open_alert()
    local name;
    for _,call in ipairs(MOCK.imgui_calls)do
        if call[1]=='Checkbox' and tostring(call[2]):find('##alert_on',1,true)then name=call[2]:match('^(.-)##');
        elseif call[1]=='Button' and call[2]=='Done##alert' then return name;end;
    end;
end;
local s=begin('Display');
frame({click='Haste reminder##frame'});frame({click='Sleep reminder##frame'});frame();
assert(open_alert()=='Sleep ending','Fixture: the new Sleep rule is open.');
frame({click='Haste reminder##frame'});frame();
assert(#s.alerts.rules==2 and open_alert()=='Haste ending','The reminder that is already there opens.');

local rules;
-- Hidden everywhere's picker.
require('ui.panel_frame').open('hidden','show');
s=begin('Display');
rules=s.effect_filters.rules;
assert(drawn('BeginCombo','##frame_Effect','Choose an effect') and disabled('Hide it everywhere##frame'),
    'The hide picker starts with nothing chosen.');
frame({click='Hide it everywhere##frame'});
assert(#rules==0,'Hide it everywhere with nothing chosen hides nothing.');
frame({combo='##frame_Effect',click='Haste##33'});frame();
assert(drawn('BeginCombo','##frame_Effect','Haste') and not disabled('Hide it everywhere##frame'));
frame({click='Hide it everywhere##frame'});
assert(#rules==1 and rules[1].effect==33 and rules[1].enabled,'The picked effect is hidden everywhere.');

-- Show on Party list buffs with no group ticked shows Your party, as the same switch on the main page does.
require('ui.panel_frame').open('party_ui','show');
s=begin('Display',function(settings)
    settings.party_ui.enabled=false;
    for key in pairs(settings.party_ui.strips)do settings.party_ui.strips[key]=false;end;
end);
frame({click='On##frame_display'});
assert(s.party_ui.strips.party and s.party_ui.enabled and s.party_ui.effects.enabled==nil,
    'Show turns the party effects on, as on the main page.');
assert(not drawn('BeginCombo','##frame_Party display'),'The panel has no party display choice.');
return true;
