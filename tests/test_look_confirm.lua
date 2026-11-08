local imgui=require('imgui');
local defaults=require('ui.defaults');
local custom=require('core.customization');
local copy=require('core.store').copy;
local appearance=require('ui.appearance');
local app=dofile(ADDON_DIR..'/vantage.lua');
local window=require('ui.settings_window');

-- A skin pick on the main page asks first when a display has its own look, names those displays, and says what stays.
local combo;
imgui.BeginCombo=function(label) return label==combo;end;
local function frame(click,opened)
    combo=opened;
    MOCK.imgui_calls={};
    if click then MOCK.clicks[click]=true;end;
    window.draw(app.state.settings,{rows={},context={valid=false}},app.callbacks);
    if click then assert(not MOCK.clicks[click],'The control is on screen: '..click);end;
    assert(#MOCK.font_stack==0);
end;
local function drawn(label)
    for _,call in ipairs(MOCK.imgui_calls)do if call[1]=='Button' and call[2]==label then return true;end;end;
    return false;
end;
local function question()
    for _,call in ipairs(MOCK.imgui_calls)do
        if call[1]=='TextWrapped' and tostring(call[2]):find(' replaces the custom look on: ',1,true) then return call[2];end;
    end;
end;
local function page_height()
    for _,call in ipairs(MOCK.imgui_calls)do
        if call[1]=='BeginChild' and call[2]=='##settings_page' then return call[3][2];end;
    end;
end;
local function value() return custom.history_value(app.state.settings);end;
local function open(s)
    s.window.open,s.window.tab=true,'Home';
    app.state.settings=s;
    frame();
    assert(s.window.tab=='Home','The page opens: '..s.window.tab);
    app.state.history,app.state.redo,app.state.transaction={},{},nil;
end;
local function fresh() return defaults.tidy(defaults.make());end;
local STAYS=' Colors you set for one effect and row text colors stay.';
local PICK,MINT='Mint##Mint','##main_skin';
local APPLY,CANCEL='Apply##look_main_skin','Cancel##look_main_skin';
local function result(source)
    local expected=copy(source);
    appearance.apply(expected,'Mint',{matching=true,window_type=source.style.window_type});
    return expected;
end;
local function named(source)
    local list={};
    for index,entry in ipairs(appearance.replaced(source,result(source)))do list[index]=entry.label;end;
    if #list==1 then return 'Mint replaces the custom look on: '..list[1]..'.'..STAYS;end;
    return 'Mint replaces the custom look on: '..table.concat(list,', ',1,#list-1)..' and '..list[#list]..'.'..STAYS;
end;

-- One display with its own look.
local s=fresh();
s.overhead.countdown_color={.2,.4,.6,1};
open(s);
local plain=page_height();
local source=copy(app.state.settings);
local before=value();
frame(PICK,MINT);
assert(custom.equal(value(),before) and #app.state.history==0,'A skin pick does not replace a custom look on the first click.');
assert(question()=='Mint replaces the custom look on: Overhead icons.'..STAYS,'The question names the pick and the display: '..tostring(question()));
frame();
assert(question()=='Mint replaces the custom look on: Overhead icons.'..STAYS and drawn(APPLY) and drawn(CANCEL),
    'The question stays with Apply and Cancel until answered.');
assert(page_height()==plain,'A question on the main page needs no footer.');
frame(CANCEL);
assert(custom.equal(value(),before) and #app.state.history==0,'Cancel keeps every look.');
frame();
assert(not question() and not drawn(APPLY),'Cancel closes the question.');
frame(PICK,MINT);
frame(APPLY);
assert(#app.state.history==1 and app.state.history[1].label=='Skin: Mint','Apply in the question is one Undo step.');
assert(custom.equal(value(),custom.history_value(result(source))),'Apply in the question applies the picked skin.');
frame();
assert(not question(),'The question closes once applied.');
assert(app.callbacks.undo() and custom.equal(value(),custom.history_value(source)),'Undo brings the custom look back.');

-- Several displays are all named.
s=fresh();
s.party_ui.style.icon_art='XI View';
s.overhead.countdown_color={.2,.4,.6,1};
s.panels.self_buffs.colors={text={.2,.4,.6,1}};
open(s);
source=copy(app.state.settings);
frame(PICK,MINT);
assert(#app.state.history==0 and question()==named(source),'The pick asks and names every display: '..tostring(question()));
for _,label in ipairs({'Party buff icons','Overhead icons','Self buffs'})do
    assert((question() or ''):find(label,1,true),'The question names '..label);
end;
assert(not drawn('Reset to default') and not drawn('Apply setup'),'Nothing is left of the whole setup here.');
frame(APPLY);
assert(#app.state.history==1 and app.state.history[1].label=='Skin: Mint','Apply in the question applies the skin.');

-- Colors set for one effect and row text colors aren't asked about, and stay.
s=fresh();
s.panels.self_buffs.effect_colors={[33]={.1,.2,.3,1}};
s.panels.self_buffs.field_colors={name={.3,.2,.1,1}};
open(s);
frame(PICK,MINT);
assert(not question() and #app.state.history==1,'With nothing of theirs replaced the pick applies at once.');
assert(custom.equal(app.state.settings.panels.self_buffs.effect_colors,{[33]={.1,.2,.3,1}})
    and custom.equal(app.state.settings.panels.self_buffs.field_colors,{name={.3,.2,.1,1}}),'A skin keeps colors set for one effect and row text colors.');

-- A question belongs to the settings it was asked about.
s=fresh();
s.overhead.countdown_color={.2,.4,.6,1};
open(s);
frame(PICK,MINT);
assert(question(),'The question is shown.');
app.state.settings=copy(app.state.settings);
before=value();
frame();
assert(not question() and not drawn(APPLY),'Undo or a profile load drops a waiting question.');
MOCK.clicks[APPLY]=true;
frame();
assert(MOCK.clicks[APPLY] and custom.equal(value(),before) and #app.state.history==0,'A dropped question cannot apply to the new settings.');
MOCK.clicks[APPLY]=nil;
return 'Skin picks confirm before replacing custom looks, naming them';
