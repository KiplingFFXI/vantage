-- A settings page that fails between Begin and End leaves what the window opened to the Present, whose guard
-- (ui/imgui_scopes.lua) closes all of it, so ImGui's stacks stay balanced, and its error goes on to the caller.
local base=require('imgui');
-- The checker works as ImGui does: windows, children, combos, tooltips and tables nest, and each push
-- stack must be back where it was when the scope around it began.
local scopes,stacks,problems,windows={},{color=0,var=0,id=0,font=0,wrap=0,disabled=0},{},0;
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
local checked={
    Begin=function()windows=windows+1;begin('window');return true;end,End=function()finish('window');end,
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
local imgui=setmetatable({},{__index=function(_,name)
    local check=checked[name];
    if not check then return base[name];end;
    return function(...)
        local shown=check(...);
        base[name](...);
        return shown;
    end;
end});
package.loaded.imgui=imgui;
local guard=require('ui.imgui_scopes');
guard.install(imgui);

local page;
package.loaded['ui.main_page']={labels={},draw=function(ui)if page then page(ui);end;end};
local defaults,window=require('ui.defaults'),require('ui.settings_window');
local s=defaults.make();
s.window.open,s.window.tab=true,'Home';
local history_status=function()return {undo=0,redo=0};end;
local callbacks={save=function()return true;end,changed=function()end,now=function()return 100;end,history_status=history_status};
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

-- An ordinary frame.
page=function(ui)ui.PushID('fixture');ui.PopID();end;
local drawn=windows;
local ok,why=draw();
assert(ok and windows==drawn+1,'Fixture: the window draws. '..tostring(why));
balanced('An ordinary frame');

-- A page that fails inside a child, an open combo, a tooltip and a table, with pushes on every stack,
-- some made through its own require('imgui'). What it already popped, and a combo that didn't open,
-- aren't ended again.
page=function(ui)
    ui.PushStyleColor(2,{1,1,1,1});ui.PushStyleColor(3,{1,1,1,1});ui.PopStyleColor(2);
    ui.PushID('fixture');
    ui.PushStyleColor(0,{1,1,1,1});ui.PushStyleColor(1,{1,1,1,1});
    ui.PushStyleVar(0,1);
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
assert(package.loaded.imgui==imgui and require('imgui')==imgui,'imgui is itself again after the failed draw.');

-- The next frame draws as before.
page=function(ui)ui.PushID('fixture');ui.PopID();end;
drawn=windows;
ok,why=draw();
assert(ok and windows==drawn+1,'The next frame draws the window again. '..tostring(why));
balanced('The frame after a failure');

-- The window's own code failing after Begin closes it too.
callbacks.history_status=function()error('Fixture window failure.');end;
ok,why=draw();
assert(not ok and tostring(why):find('Fixture window failure.',1,true),'The window error goes on to the caller.');
balanced('The window failing after Begin');
callbacks.history_status=history_status;
ok=draw();
assert(ok,'Fixture: the window draws once more.');
balanced('The last frame');
