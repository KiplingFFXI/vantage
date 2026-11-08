local imgui=require('imgui');
local defaults=require('ui.defaults');
local custom=require('core.customization');
local copy=require('core.store').copy;
local app=dofile(ADDON_DIR..'/vantage.lua');
local window=require('ui.settings_window');

-- Window frame and Font set the timer panels' look, which the party list buffs wear, so they read and write that one
-- value. A pick is one Undo step.
local combo,previews;
imgui.BeginCombo=function(label,preview) previews[label]=preview;return label==combo;end;
local function frame(click,opened)
    combo,previews=opened,{};
    MOCK.imgui_calls={};
    if click then MOCK.clicks[click]=true;end;
    window.draw(app.state.settings,{rows={},context={valid=false}},app.callbacks);
    if click then assert(not MOCK.clicks[click],'The pick is on the main page: '..click);end;
    assert(#MOCK.font_stack==0);
end;
local function value() return custom.history_value(app.state.settings);end;
local function open(s)
    defaults.tidy(s);
    s.window.open,s.window.tab=true,'Home';
    s.window.sections['Home/More look']=true;
    app.state.settings=s;
    frame();
    app.state.history,app.state.redo,app.state.transaction={},{},nil;
end;
local function fresh() return defaults.tidy(defaults.make());end;

-- They read the timer panels' value alone, and a pick leaves the party list buffs' settings as they were.
for _,case in ipairs({
    {id='##main_window_type',pick='Window Type 3##3',shown='Window Type 3',undo='Window frame',
        check=function(s) return s.style.window_type==3 and require('ui.theme').window(s).window_type==3;end},
    {id='##main_font',pick='XI View##XI View',shown='XI View',undo='Font',check=function(s) return s.style.font=='XI View';end},
})do
    local s=fresh();
    open(s);
    local source,before=copy(app.state.settings),value();
    frame(nil,case.id);
    assert(previews[case.id]~='Mixed','It reads the one value: '..case.undo);
    frame(case.pick,case.id);
    local now=app.state.settings;
    assert(case.check(now) and custom.equal(now.party_ui,source.party_ui),
        'The pick sets the timer panels and nothing of the party list buffs: '..case.undo);
    assert(#app.state.history==1 and app.state.history[1].label==case.undo,'The pick is one Undo step: '..case.undo);
    local after=value();
    frame(nil,case.id);
    assert(previews[case.id]==case.shown,'After the pick it reads the picked value: '..case.undo);
    assert(app.callbacks.undo() and custom.equal(value(),before),'Undo restores it: '..case.undo);
    assert(app.callbacks.redo() and custom.equal(value(),after),'Redo sets it again: '..case.undo);
end;

-- A pick that changes nothing adds no Undo step.
local s=fresh();open(s);
frame('XI View##XI View','##main_font');
assert(#app.state.history==1);
frame('XI View##XI View','##main_font');
assert(#app.state.history==1,'Picking the value already shown leaves Undo alone.');
return 'Window frame and Font read and write the one look, in one Undo step';
