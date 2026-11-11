-- Blink is set once, under More look on the main page, for the status timers, the party list buffs, the overhead icons
-- and the pet. A tick or the slider writes only their blink keys, and the seconds are kept while it is off. Recasts have none.
local defaults,custom=require('ui.defaults'),require('core.customization');
local window,hud,imgui=require('ui.settings_window'),require('ui.hud'),require('imgui');
local settings=defaults.make();
settings.window.open, settings.window.tab = true, 'Home';
local pending,seen={},{};
local slider=imgui.SliderFloat;
imgui.SliderFloat=function(label,value,low,high,...)
    seen[label]={low=low,high=high};
    if pending[label]~=nil then value[1],pending[label]=pending[label],nil;return true;end;
    return slider(label,value,low,high,...);
end;
local phases={};
local callbacks={now=function()return 100;end,save=function()return true;end,
    changed=function(phase)phases[#phases+1]=phase;end};
local function frame(click,label,value)
    seen,phases,MOCK.imgui_calls={},{},{};
    if click then MOCK.clicks[click]=true;end;
    if label then pending[label]=value;end;
    window.draw(settings,hud.sample(100),callbacks);
    assert(not click or MOCK.clicks[click]==nil,'The actual checkbox consumed its pointer click');
    assert(not next(pending),'The actual threshold slider was reachable');
    assert(#MOCK.font_stack==0,'Effect controls preserve the font stack');
end;
local on_tick,off_tick='Blink before an effect ends, starting at##main_blink','Blink before an effect ends##main_blink';
local threshold='##main_blink_seconds';
local function holders(s)
    local out={s.party_ui.effects,s.overhead,s.pet};
    for _,id in ipairs(defaults.panel_order)do
        if not defaults.recast_panels[id] then out[#out+1]=s.panels[id];end;
    end;
    return out;
end;
for _,effects in ipairs(holders(settings))do
    assert(effects.blink_icons and effects.blink_seconds==15,'Fresh display icons use the verified client threshold');
end;
frame();
local baseline=custom.history_value(settings);
frame(on_tick);
local expected=defaults.copy(baseline);
for _,effects in ipairs(holders(expected))do effects.blink_icons=false;end;
assert(custom.equal(custom.history_value(settings),expected),'Disabling blink changes only each display\'s blink_icons field');
assert(#phases==2 and phases[1]=='before' and phases[2]=='after','A checkbox click is one settings transaction');
for _,effects in ipairs(holders(settings))do
    for key in pairs(effects)do
        assert(not tostring(key):find('Dims and brightens',1,true),'Help text must never become a saved setting key');
    end;
end;
frame();
assert(not seen[threshold],'With blink off the seconds are gone');
frame(off_tick);
assert(custom.equal(custom.history_value(settings),baseline),'Re-enabling blink restores exactly the original settings');
frame();
assert(seen[threshold].low==1 and seen[threshold].high==300,'The active threshold uses the supported seconds range');
frame(nil,threshold,47);
expected=defaults.copy(baseline);
for _,effects in ipairs(holders(expected))do effects.blink_seconds=47;end;
assert(custom.equal(custom.history_value(settings),expected),'Changing the threshold preserves every other display choice');
-- A typed nan is no number of seconds and changes nothing. A number past the ends is held at them.
frame(nil,threshold,0/0);
assert(custom.equal(custom.history_value(settings),expected) and #phases==0,'A nan typed into the seconds changes nothing');
assert(require('core.store').encode(settings)~=nil,'The settings still save');
frame(nil,threshold,math.huge);
assert(settings.overhead.blink_seconds==300,'Past the end, the seconds are held at 300');
frame(nil,threshold,47);
-- The slider is as wide as its longest text, so none of it is cut off.
frame();
local width;
for index,call in ipairs(MOCK.imgui_calls)do
    if call[1]=='SliderFloat' and call[2]==threshold then
        local before=MOCK.imgui_calls[index-1];
        width=before and before[1]=='SetNextItemWidth' and before[2];
    end;
end;
assert(width and width>=imgui.CalcTextSize('300 seconds left')+16,'The seconds slider fits "300 seconds left": '..tostring(width));
frame(on_tick);
for _,effects in ipairs(holders(expected))do effects.blink_icons=false;end;
assert(custom.equal(custom.history_value(settings),expected) and settings.overhead.blink_seconds==47,
    'Disabling blink preserves its selected threshold for later');

-- The switch says what blinks: effects whose time left is known or estimated, whether or not their countdown shows.
local help=require('ui.search_index').controls.Home['Blink before an effect ends'] or '';
assert(help:find('Effects whose time left is known or estimated blink, whether or not their countdown shows',1,true),
    'The blink switch says what blinks');
assert((require('ui.search_index').controls.Home['Blink seconds left'] or ''):find('Ending-soon colors and countdown styling keep their own settings.',1,true),
    'A timer panel\'s ending-soon colors keep their own settings');

-- With no display blinking the search leads to the tick, not to seconds that aren't there.
local function found(page,label,query)
    for _,result in ipairs(window.search(query))do if result.tab==page and result.label==label then return true;end;end;
    return false;
end;
assert(found('Home','Blink before an effect ends','Blink seconds left') and not found('Home','Blink seconds left','Blink seconds left'),
    'Off, the seconds are found through the tick');
frame(off_tick);
assert(found('Home','Blink seconds left','Blink seconds left'),'On, the seconds are found themselves');

settings.window.tab='Recasts';
frame();
for _,call in ipairs(MOCK.imgui_calls)do
    if call[1]=='Checkbox' then
        assert(not tostring(call[2]):find('Blink',1,true),'Recast controls do not expose status-expiry blinking');
    end;
end;
for _,result in ipairs(window.search('blink'))do assert(result.tab~='Recasts');end;
assert(#MOCK.commands==0,'Blink customization never issues gameplay commands');
imgui.SliderFloat=slider;
return 'The expiry blink tick and its seconds change only the blink keys of the displays that blink';
