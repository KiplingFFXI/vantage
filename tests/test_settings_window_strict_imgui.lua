-- A strict imgui: each function is a field of its own, and a name it doesn't bind raises. Text measured
-- inside an open settings window keeps the cache it has outside it, a page that fails still leaves ImGui
-- balanced once the Present's guard (ui/imgui_scopes.lua) closes what it opened, and a name the runtime
-- doesn't bind is skipped.
local base=require('imgui');
-- The functions the settings window and its pages use.
local bound={'AddFontFromFileTTF','AlignTextToFramePadding','Begin','BeginChild','BeginCombo','BeginDisabled','BeginTable',
    'BeginTooltip','Button','CalcTextSize','Checkbox','CollapsingHeader',
    'ColorEdit4','Dummy','End','EndChild','EndCombo','EndDisabled','EndTable','EndTooltip','GetBackgroundDrawList',
    'GetContentRegionAvail','GetCursorPosX','GetCursorScreenPos','GetFont','GetFontSize','GetForegroundDrawList',
    'GetFrameHeight','GetIO','GetItemRectMax','GetItemRectMin','GetMousePos','GetScrollY','GetStyle','GetWindowDrawList',
    'GetWindowPos','GetWindowSize','InputText','InputTextWithHint','InvisibleButton','IsAnyItemActive','IsItemActivated',
    'IsItemActive','IsItemHovered','IsKeyPressed','IsMouseClicked','IsMouseDown','IsMouseDragging','IsMouseReleased',
    'IsPopupOpen','IsWindowFocused','IsWindowHovered','NewLine','PopFont','PopID','PopStyleColor','PopStyleVar',
    'PopTextWrapPos','PushFont','PushID','PushStyleColor','PushStyleVar','PushTextWrapPos','RadioButton','SameLine','Selectable',
    'Separator','SetClipboardText','SetCursorPos','SetCursorScreenPos','SetMouseCursor','SetNextItemOpen',
    'SetNextItemWidth','SetNextWindowBgAlpha','SetNextWindowPos','SetNextWindowSize','SetNextWindowSizeConstraints',
    'SetScrollHereY','SetScrollY','SliderFloat','Spacing','TableNextColumn','TableSetupColumn','TextColored',
    'TextUnformatted','TextWrapped','col32'};
-- The checker works as ImGui does: windows, children, combos, tooltips and tables nest, and each push
-- stack must be back where it was when the scope around it began.
local scopes,stacks,problems={},{color=0,var=0,id=0,font=0,wrap=0,disabled=0},{};
local function begin(kind)
    local sizes={};
    for key,value in pairs(stacks)do sizes[key]=value;end;
    scopes[#scopes+1]={kind=kind,sizes=sizes};
end;
local function finish(kind)
    local top=table.remove(scopes);
    if not top or top.kind~=kind then problems[#problems+1]=kind..' ended out of order';return;end;
    for key,value in pairs(top.sizes)do
        if stacks[key]~=value then problems[#problems+1]='the '..key..' stack changed inside a '..kind;end;
    end;
end;
local function push(kind)stacks[kind]=stacks[kind]+1;end;
local function pop(kind,count)
    stacks[kind]=stacks[kind]-(count or 1);
    if stacks[kind]<0 then problems[#problems+1]=kind..' popped too often';end;
end;
local checks={
    Begin=function()begin('window');return true;end,End=function()finish('window');end,
    BeginChild=function()begin('child');return true;end,EndChild=function()finish('child');end,
    BeginCombo=function(label)if label=='##fixture_open' then begin('combo');return true;end;return false;end,
    EndCombo=function()finish('combo');end,
    BeginTooltip=function()begin('tooltip');return true;end,EndTooltip=function()finish('tooltip');end,
    BeginTable=function()begin('table');return true;end,EndTable=function()finish('table');end,
    BeginDisabled=function()push('disabled');end,EndDisabled=function()pop('disabled');end,
    PushID=function()push('id');end,PopID=function()pop('id');end,
    PushFont=function()push('font');end,PopFont=function()pop('font');end,
    PushStyleColor=function()push('color');end,PopStyleColor=function(count)pop('color',count);end,
    PushStyleVar=function()push('var');end,PopStyleVar=function(count)pop('var',count);end,
    PushTextWrapPos=function()push('wrap');end,PopTextWrapPos=function()pop('wrap');end,
};
local function runtime(unbound)
    local real={};
    for _,name in ipairs(bound)do
        local check=checks[name];
        if not unbound[name] then
            real[name]=check and function(...)local shown=check(...);base[name](...);return shown;end
                or function(...)return base[name](...);end;
        end;
    end;
    return setmetatable(real,{__index=function(_,name)error('Unsupported Vantage GUI method: '..tostring(name),2);end});
end;
local guard=require('ui.imgui_scopes');
local real=runtime({});
package.loaded.imgui=real;
guard.install(real);

local metrics,fonts=require('ui.text_metrics'),require('ui.fonts');
local measured,measure=0,fonts.measure;
fonts.measure=function(...)measured=measured+1;return measure(...);end;
local page;
package.loaded['ui.main_page']={labels={},draw=function(ui)if page then page(ui);end;end};
local defaults,window=require('ui.defaults'),require('ui.settings_window');
local s=defaults.make();
s.window.open,s.window.tab=true,'Home';
local callbacks={save=function()return true;end,changed=function()end,now=function()return 100;end,
    history_status=function()return {undo=0,redo=0};end};
-- As vantage.lua's Present does: what a draw that fails left open is closed back to where it began.
local function draw()
    problems={};
    local mark=guard.depth();
    local ok,why=pcall(window.draw,s,{rows={},subjects={},context={}},callbacks);
    if not ok then guard.close(mark);end;
    return ok,why;
end;
local function balanced(label)
    assert(#scopes==0,label..': every window, child, combo, tooltip and table is ended. Still open: '
        ..(scopes[#scopes] and scopes[#scopes].kind or 'none'));
    for key,value in pairs(stacks)do assert(value==0,label..': the '..key..' stack is back to empty.');end;
    assert(#problems==0,label..': '..table.concat(problems,'; '));
end;

-- The window's text and the panels' text use the same cache. Agave measures through the runtime and
-- Original FFXI through its bitmap.
local fonts_used={'Agave','Original FFXI'};
local inside;
local function measure_page()
    inside={};
    for index,font in ipairs(fonts_used)do
        inside[index]=metrics.token(font,18);
        metrics.width(font,'Protect',18);
    end;
end;
local function same_tokens(label)
    for index,font in ipairs(fonts_used)do
        local outside=metrics.token(font,18);
        metrics.width(font,'Protect',18);
        assert(inside[index]==outside,label..': '..font..' text has the same token inside the window as outside it.');
    end;
end;
page=measure_page;
local ok,why=draw();
assert(ok,'Fixture: the window draws. '..tostring(why));
same_tokens('The first frame');
local first,count={inside[1],inside[2]},measured;
for frame=2,4 do
    ok,why=draw();
    assert(ok,'Fixture: the window draws again. '..tostring(why));
    same_tokens('Frame '..frame);
    assert(inside[1]==first[1] and inside[2]==first[2],'Frame '..frame..': the tokens stay as they were.');
end;
assert(measured==count,'Text measured once is not measured again while the window stays open.');
balanced('Ordinary frames');

-- A page that fails deep inside still closes everything, some of it opened through its own
-- require('imgui'). What it already popped, and a combo that didn't open, aren't ended again.
page=function(ui)
    ui.PushStyleColor(2,{1,1,1,1});ui.PushStyleColor(3,{1,1,1,1});ui.PopStyleColor(2);
    ui.PushID('fixture');
    ui.PushStyleColor(0,{1,1,1,1});ui.PushStyleVar(0,1);
    ui.BeginDisabled(true);
    if ui.BeginChild('##fixture_child',{0,0})then
        if ui.BeginCombo('##fixture_closed','Closed')then ui.EndCombo();end;
        if ui.BeginCombo('##fixture_open','Open')then
            ui.BeginTooltip();
            ui.PushTextWrapPos(200);
            if ui.BeginTable('##fixture_table',2)then
                require('ui.fonts').push('Agave',16);
                require('imgui').PushID('deep');
                error('Fixture page failure.');
            end;
        end;
    end;
end;
ok,why=draw();
assert(not ok and tostring(why):find('Fixture page failure.',1,true),'The page error goes on to the caller.');
balanced('A page that fails deep inside');
assert(rawequal(package.loaded.imgui,real),'imgui is itself again after the failed draw.');

-- The page draws with the runtime itself, so a field the runtime changes or drops between draws is seen as it is now.
local view;
page=function(ui)view=ui;measure_page();end;
real.CalcTextSize=function(text)return #tostring(text)*9,18;end;
ok=draw();
assert(ok,'Fixture: the window draws with a new text measure.');
assert(rawequal(view,real),'The page draws with the runtime itself.');
same_tokens('A changed field');
real.SetClipboardText=nil;
ok=draw();
assert(ok,'Fixture: the window draws without the dropped field.');
same_tokens('A dropped field');
balanced('Changed fields');

-- A runtime without text wrap still draws the window, and a failing page still closes the rest.
real=runtime({PushTextWrapPos=true,PopTextWrapPos=true});
package.loaded.imgui=real;
guard.install(real);
page=nil;
ok,why=draw();
assert(ok,'A name the runtime does not bind is skipped. '..tostring(why));
balanced('A runtime without text wrap');
page=function(ui)
    ui.PushID('fixture');
    if ui.BeginChild('##fixture_child',{0,0})then
        ui.PushStyleColor(0,{1,1,1,1});
        error('Fixture page failure.');
    end;
end;
ok,why=draw();
assert(not ok and tostring(why):find('Fixture page failure.',1,true),'Fixture: the page failed.');
balanced('A failing page without text wrap');
-- One that can push a wrap but not pop it leaves that push alone and still closes the rest.
real=runtime({PopTextWrapPos=true});
package.loaded.imgui=real;
guard.install(real);
page=function(ui)
    ui.PushID('fixture');
    if ui.BeginChild('##fixture_child',{0,0})then
        ui.PushTextWrapPos(200);
        error('Fixture page failure.');
    end;
end;
ok,why=draw();
assert(not ok and tostring(why):find('Fixture page failure.',1,true),'The page error goes on, not one from a missing end.');
local others=0;
for _,problem in ipairs(problems)do if not problem:find('the wrap stack',1,true)then others=others+1;end;end;
assert(#scopes==0 and others==0 and stacks.id==0 and stacks.font==0 and stacks.color==0 and stacks.var==0,
    'A push the runtime cannot pop is left alone, and the rest is closed.');
stacks.wrap=0;
