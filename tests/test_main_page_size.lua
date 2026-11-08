local imgui=require('imgui');
local defaults=require('ui.defaults');
local custom=require('core.customization');
local appearance=require('ui.appearance');
local app=dofile(ADDON_DIR..'/vantage.lua');
local window=require('ui.settings_window');

-- Size on the main page: a button sets the scale and re-spaces what is still where Vantage put it, as one Undo step that
-- asks nothing and leaves colors, fonts and fields alone. The free slider only sets the scale. The Skin question names
-- the skin picked.
local combo;
imgui.BeginCombo=function(label,preview)
    MOCK.imgui_calls[#MOCK.imgui_calls+1]={'BeginCombo',label,preview};
    return label==combo;
end;
local slid;
imgui.SliderFloat=function(label,value)
    if slid and slid[1]==label then value[1],slid=slid[2],nil;return true;end;
    return false;
end;
local function frame(click,opened)
    combo=opened;
    MOCK.imgui_calls={};
    if click then MOCK.clicks[click]=true;end;
    window.draw(app.state.settings,{rows={},context={valid=false}},app.callbacks);
    if click then assert(not MOCK.clicks[click],'The control is on screen: '..click);end;
    MOCK.clicks={};
    assert(#MOCK.font_stack==0);
end;
local function drawn(label)
    for _,call in ipairs(MOCK.imgui_calls)do if call[1]=='Button' and call[2]==label then return true;end;end;
    return false;
end;
local function question()
    for _,call in ipairs(MOCK.imgui_calls)do
        if call[1]=='TextWrapped' and tostring(call[2]):find('the custom look on: ',1,true) then return call[2];end;
    end;
end;
local function settings() return app.state.settings;end;
local function last() return app.state.history[#app.state.history] or {};end;
local function value() return custom.history_value(settings());end;
local function open(s)
    s.window.open,s.window.tab=true,'Home';
    app.state.settings=s;
    frame();
    app.state.history,app.state.redo,app.state.transaction={},{},nil;
end;
local function fresh() return defaults.tidy(defaults.make());end;
local function moved(before,after,id) return before.panels[id].x~=after.panels[id].x or before.panels[id].y~=after.panels[id].y;end;

-- A Size button keeps the colors, the fonts and every field, and asks nothing whatever the look holds.
local s=fresh();
s.panels.self_buffs.colors={background={1,0,0,1}};
s.style.font,s.style.font_size,s.style.icon_size='Agave',23,29;
open(s);
local kept=custom.equal;
frame('1.5x##main_size');
frame();
assert(#app.state.history==1 and last().label=='Size 1.5x' and settings().style.scale==1.5,'A Size button is one Undo step.');
assert(not question() and not drawn('Apply##look_main_size') and not drawn('Apply size'),'It asks nothing.');
assert(kept(settings().panels.self_buffs.colors,{background={1,0,0,1}}) and settings().style.font=='Agave'
    and settings().style.font_size==23 and settings().style.icon_size==29,'It keeps colors, fonts and sizes.');

-- At 2x the displays still where they started are re-spaced. The top row keeps its spots, which have room at 2x. The
-- rows under it flow down and across, and the notices leave the top of the screen for a place clear of the game's windows.
s=fresh();open(s);
local start,before=defaults.make(),value();
frame('2x##main_size');
local panels=settings().panels;
assert(#app.state.history==1 and settings().style.scale==2,'2x is one step.');
assert(not moved(start,settings(),'self_buffs') and not moved(start,settings(),'self_debuffs') and not moved(start,settings(),'target'),
    'The top row stays.');
assert(moved(start,settings(),'party') and moved(start,settings(),'recasts')
    and (settings().alerts.notice_x~=start.alerts.notice_x or settings().alerts.notice_y~=start.alerts.notice_y),
    'Party timers, Recasts and Alert notices move.');
local after=value();
assert(app.callbacks.undo() and custom.equal(value(),before),'One Undo puts the size and the places back.');
assert(app.callbacks.redo() and custom.equal(value(),after),'One Redo sets them again.');

-- A display the player moved stays where they put it.
s=fresh();
s.panels.party.x,s.panels.party.y=333,444;
open(s);
frame('2x##main_size');
assert(settings().panels.party.x==333 and settings().panels.party.y==444,'A moved display is left alone.');

-- The size already on is a button that does nothing.
s=fresh();open(s);
frame('1x##main_size');
assert(#app.state.history==0 and settings().style.scale==1,'Picking the current size changes nothing.');

-- The free slider only sets the scale: nothing moves.
s=fresh();open(s);
start=defaults.make();
slid={'##main_scale',1.75};
frame();
assert(settings().style.scale==1.75 and #app.state.history==1 and last().label=='Size','The slider sets the scale.');
assert(not moved(start,settings(),'party') and not moved(start,settings(),'recasts')
    and settings().alerts.notice_x==start.alerts.notice_x and settings().alerts.notice_y==start.alerts.notice_y,'And moves nothing.');

-- The Skin question says which skin was picked.
s=fresh();
s.panels.self_buffs.colors={background={1,0,0,1}};
open(s);
frame('Phoenix##Phoenix','##main_skin');
frame();
assert(#app.state.history==0 and tostring(question()):find('Phoenix replaces the custom look on: Self buffs.',1,true) and drawn('Apply##look_main_skin'),
    'The Skin question names the skin it would apply: '..tostring(question()));
frame('Apply##look_main_skin');
assert(#app.state.history==1 and last().label=='Skin: Phoenix' and appearance.candidate(settings())=='Phoenix','Apply in it applies that skin.');
return 'Size never resets a look, and the Skin question names the pick';
