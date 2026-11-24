local imgui=require('imgui');
local defaults=require('ui.defaults');
local custom=require('core.customization');
local copy=require('core.store').copy;
local app=dofile(ADDON_DIR..'/vantage.lua');
local window=require('ui.settings_window');

-- Each fold under How it looks remembers being open or closed under window.sections, as 'Home/Artwork' for Artwork, a
-- fresh install leaves them closed, and the attention lines show one fix only while something needs a hand.
local next_open,toggle,opened,query=nil,{},{},nil;
imgui.SetNextItemOpen=function(value) next_open=value;end;
imgui.CollapsingHeader=function(label)
    MOCK.imgui_calls[#MOCK.imgui_calls+1]={'CollapsingHeader',label};
    opened[label]=next_open;
    local value=next_open;
    if toggle[label]~=nil then value,toggle[label]=toggle[label],nil;end;
    return value;
end;
local input_with_hint=imgui.InputTextWithHint;
imgui.InputTextWithHint=function(label,hint,value,...)
    if label=='##find_settings' and query~=nil then value[1]=query;end;
    return input_with_hint(label,hint,value,...);
end;
local function frame(click)
    MOCK.imgui_calls,opened={},{};
    if click then MOCK.clicks[click]=true;end;
    window.draw(app.state.settings,{rows={},context={valid=false}},app.callbacks);
    if click then assert(not MOCK.clicks[click],'The control is on the main page: '..click);end;
    assert(#MOCK.font_stack==0);
end;
local function value() return custom.history_value(app.state.settings);end;
local function remembered()
    local out={};
    for key,state in pairs(app.state.settings.window.sections)do if key:sub(1,5)=='Home/' then out[key]=state;end;end;
    return out;
end;
local s=defaults.tidy(defaults.make());
s.window.open,s.window.tab=true,'Home';
app.state.settings=s;
app.state.history,app.state.redo,app.state.transaction={},{},nil;
local before=value();

-- A fresh install leaves the folds closed, and saves nothing for them.
local FOLDS={'Artwork','Sizes','Boxes','Text effects','Colors'};
frame();
for _,name in ipairs(FOLDS)do assert(opened[name]==false,name..' starts closed.');end;
assert(opened['More look']==nil,'There is no More look.');
assert(next(remembered())==nil and custom.equal(value(),before) and #app.state.history==0,'Opening the page records nothing.');

-- Opening or closing it is remembered under its own key, outside Undo.
toggle.Artwork=true;frame();
assert(app.state.settings.window.sections['Home/Artwork']==true,'Opening Artwork is remembered.');
frame();
assert(opened.Artwork==true,'The next frame opens what was left open.');
toggle.Colors=true;frame();
assert(app.state.settings.window.sections['Home/Colors']==true,'Colors remembers too.');
toggle.Artwork=false;frame();
assert(app.state.settings.window.sections['Home/Artwork']==false,'Closing Artwork is remembered.');
frame();
assert(opened.Artwork==false and opened.Colors==true,'The next frame leaves Artwork closed and Colors open.');
toggle.Artwork=true;frame();
assert(#app.state.history==0 and custom.equal(value(),before),'Section memory is not a settings change.');
local reloaded=defaults.tidy(copy(app.state.settings));
assert(reloaded.window.sections['Home/Artwork']==true and reloaded.window.sections['Home/Colors']==true,'The saved open state survives a reload.');

-- A search opens every fold without changing what is remembered.
toggle.Artwork=false;frame();
local kept=remembered();
query='volume';frame();
for _,name in ipairs(FOLDS)do assert(opened[name]==true,'Search opens '..name..'.');end;
assert(custom.equal(remembered(),kept),'Search does not rewrite the remembered state.');
query='';frame();query=nil;
assert(opened.Artwork==false and opened.Sizes==false and opened.Colors==true,'Clearing the search brings back the remembered state.');

-- The attention lines: nothing on a fresh install, then one line and one fix for each problem. Game window replacement
-- asks for nothing, since Vantage replaces no game window.
frame();
for _,call in ipairs(MOCK.imgui_calls)do assert(not(call[1]=='Button' and call[2]=='Review'),'Replacement asks for no review.');end;
assert(opened['Replace game windows']==nil,'The main page has no Replace game windows.');
-- Set by hand here, so the page's lines hear of it as they would from a change.
app.state.settings.preview,app.state.settings.party_ui.preview=true,true;
app.state.settings_revision=app.state.settings_revision+1;
app.state.history={};
local settled=value();
frame('End samples##main');
assert(not app.state.settings.preview and not app.state.settings.party_ui.preview and #app.state.history==1
    and app.state.history[1].label=='End samples','End samples is one Undo step.');
assert(app.callbacks.undo() and custom.equal(value(),settled),'Undo brings the samples back.');
frame('End samples##main');
app.state.settings.enabled=false;app.state.history={};
frame('Resume##main_resume');
assert(app.state.settings.enabled and #app.state.history==1 and app.state.history[1].label=='Resume timer panels','Resume is one Undo step.');
app.state.hidden=true;app.state.history={};
settled=value();
frame('Show##main_show');
assert(app.state.hidden==false and #app.state.history==0 and custom.equal(value(),settled),'Show only unhides; nothing is saved.');
frame();
local lines={'End samples##main','Resume##main_resume','Show##main_show','Use it again##main_use_list','Done arranging##main_edit_end'};
for _,label in ipairs(lines)do MOCK.clicks[label]=true;end;
frame();
local left=0;
for _,label in ipairs(lines)do if MOCK.clicks[label] then left=left+1;MOCK.clicks[label]=nil;end;end;
assert(left==#lines,'With nothing wrong the lines are gone.');
return 'The look folds remember their state and the attention lines offer one fix per problem';
