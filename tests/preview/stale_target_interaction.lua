-- Preview tooling: a button drawn only in the first two frames, then another in its place. A replay step that
-- targets the first one after that must stop the run, not click whatever is drawn there now.
local imgui = require('imgui');
PREVIEW.gone_clicks, PREVIEW.other_clicks = 0, 0;
return function()
    imgui.SetNextWindowPos({ 100, 100 }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ 200, 100 }, ImGuiCond_Always);
    imgui.Begin('##stale_target_window', true, ImGuiWindowFlags_NoDecoration);
    if PREVIEW.frame <= 2 then
        if imgui.InvisibleButton('##gone', { 200, 100 }) then PREVIEW.gone_clicks = PREVIEW.gone_clicks + 1; end;
    elseif imgui.InvisibleButton('##other', { 200, 100 }) then
        PREVIEW.other_clicks = PREVIEW.other_clicks + 1;
    end;
    imgui.End();
end;
