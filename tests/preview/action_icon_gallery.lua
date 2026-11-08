local imgui,icons=require('imgui'),require('ui.action_icons');
local examples={{86,'Cure'},{87,'Cure II'},{91,'Cure VI'},{143,'Haste'},{209,'Haste II'},
    {31,'NQ 31'},{360,'Provoke'},{470,'Wrap 470'},{500,'HQ 500'},{600,'HQ 600'},
    {674,'Death'},{1000,'HQ 1000'},{1064,'HQ 1064'}};
icons.prepare();
return function()
    imgui.SetNextWindowPos({20,20},ImGuiCond_Always);imgui.SetNextWindowSize({1100,280},ImGuiCond_Always);
    imgui.Begin('Native action artwork',true,ImGuiWindowFlags_NoResize+ImGuiWindowFlags_NoMove);
    local list=imgui.GetWindowDrawList();
    for row,art in ipairs({'Original FFXI','XI View'}) do
        list:AddText({30,40+(row-1)*125},0xFFFFFFFF,art..' - native shapes, actual local textures');
        for index,example in ipairs(examples) do
            local x,y=30+(index-1)*81,66+(row-1)*125;
            local ok=icons.draw(list,art,example[1],0,x,y,48,1);
            list:AddText({x,y+55},ok and 0xFFFFFFFF or 0xFF0000FF,example[2]);
            assert(ok,art..' shape '..example[1]..': '..tostring(icons.reason()));
        end;
    end;
    imgui.End();
end;
