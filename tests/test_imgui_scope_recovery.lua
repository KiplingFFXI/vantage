-- A display that fails inside its own window, child, tooltip, font or style still leaves ImGui's stacks as
-- they were: the Present closes, newest first, what it opened and didn't close. A combo or table that didn't
-- open needs no end. A Present that ends normally closes nothing more.
local imgui=require('imgui');
local hud=require('ui.hud');
local fail=false;
hud.draw=function()
    imgui.Begin('##fixture_panel',true,0);
    imgui.PushFont(nil,18);
    imgui.PushStyleColor(0,{1,1,1,1});imgui.PushStyleColor(1,{1,1,1,1});
    imgui.PushStyleVar(0,1);
    imgui.BeginChild('##fixture_child');
    imgui.BeginCombo('##fixture_combo','Closed');
    if imgui.BeginTooltip() then
        imgui.PushID('fixture');
        if fail then error('Fixture panel failure.'); end;
        imgui.PopID();
        imgui.EndTooltip();
    end;
    imgui.EndChild();
    imgui.PopStyleVar();
    imgui.PopStyleColor(2);
    imgui.PopFont();
    imgui.End();
end;
hud.draw_notices,hud.cancel_gesture=function() end,function() end;
local app=dofile(ADDON_DIR..'/vantage.lua');
MOCK.fire('load');app.refresh(1);
local ends={End=true,EndChild=true,EndTooltip=true,EndCombo=true,PopID=true,PopFont=true,PopStyleColor=true,PopStyleVar=true};
local function closes()
    local out={};
    for _,call in ipairs(MOCK.imgui_calls) do
        if ends[call[1]] then out[#out+1]=call[1]..(call[1]=='PopStyleColor' and '('..tostring(call[2])..')' or ''); end;
    end;
    return table.concat(out,',');
end;
local scopes=require('ui.imgui_scopes');
MOCK.imgui_calls={};MOCK.frame();
assert(closes()=='PopID,EndTooltip,EndChild,PopStyleVar,PopStyleColor(2),PopFont,End' and scopes.depth()==0,
    'A Present that ends normally closes only what the display closed: '..closes());
assert(#MOCK.font_stack==0);
fail=true;MOCK.imgui_calls={};MOCK.frame();
assert(app.state.problem and app.state.problem:find('Fixture panel failure.',1,true),'The failure is reported.');
assert(closes()=='PopID,EndTooltip,EndChild,PopStyleVar,PopStyleColor(1),PopStyleColor(1),PopFont,End',
    'The failed Present closes newest first what it opened: '..closes());
assert(scopes.depth()==0 and #MOCK.font_stack==0,'Nothing stays open after the failed Present.');
fail=false;MOCK.imgui_calls={};MOCK.frame();
assert(closes()=='PopID,EndTooltip,EndChild,PopStyleVar,PopStyleColor(2),PopFont,End','The next Present draws as before.');

-- A settings page that fails partway goes by the same count: the Present closes what the window and the page opened,
-- each once.
local main=require('ui.main_page');
local page,reached=main.draw,false;
main.draw=function()
    imgui.PushID('fixture_page');
    imgui.BeginChild('##fixture_page_child');
    imgui.PushStyleColor(0,{1,1,1,1});
    reached=true;
    error('Fixture settings failure.');
end;
app.callbacks.open_page('Home');
MOCK.frame();
MOCK.imgui_calls={};MOCK.frame();
assert(reached,'Fixture: the page was drawn.');
assert(app.state.problem and app.state.problem:find('Fixture settings failure.',1,true),'The settings failure is reported.');
local opens={Begin='End',BeginChild='EndChild',BeginDisabled='EndDisabled',BeginGroup='EndGroup',BeginTable='EndTable',
    BeginTooltip='EndTooltip',PushID='PopID',PushFont='PopFont',PushStyleColor='PopStyleColor',PushStyleVar='PopStyleVar',
    PushTextWrapPos='PopTextWrapPos',PushItemWidth='PopItemWidth'};
local count={};
for _,call in ipairs(MOCK.imgui_calls) do
    local by=(call[1]=='PopStyleColor' or call[1]=='PopStyleVar') and tonumber(call[2]) or 1;
    count[call[1]]=(count[call[1]] or 0)+by;
end;
for open,close in pairs(opens) do
    assert((count[open] or 0)==(count[close] or 0),open..' ran '..tostring(count[open])..' times and '..close..' '..tostring(count[close]));
end;
assert(scopes.depth()==0 and #MOCK.font_stack==0,'Nothing stays open after the failed settings page.');
main.draw=page;
