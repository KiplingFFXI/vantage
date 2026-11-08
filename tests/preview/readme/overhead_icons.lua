-- Overhead icons as /vg overhead preview draws them: the sample block over a mob you target, then over a party member,
-- five yalms away on a 1920 by 1080 screen. The game draws the units and their names; here a camera and your character
-- stand in for them, and a caption goes where the name would be.
local C = require('preview.readme.common');
local imgui = require('imgui');
local get_io = imgui.GetIO;
local W = require('overhead_fixture');
-- The fixture's screen is a fixed size; the preview's own screen is the one drawn on.
rawset(imgui, 'GetIO', get_io);
local preview = require('ui.overhead_preview');
require('ui.icons').prepare();
local settings = W.settings();
settings.overhead.preview = true;
local snapshot, view = W.snapshot(), W.view();
local blocks = { { 'mob', -1.05, 'Over a mob you target' }, { 'party', 1.05, 'Over a party member' } };
-- A moment when none of the sample countdowns is near its end, so none of them blinks.
local moment = C.now + 110;
local flags = ImGuiWindowFlags_NoDecoration + ImGuiWindowFlags_NoInputs + ImGuiWindowFlags_NoBackground
    + ImGuiWindowFlags_NoSavedSettings;
return function()
    -- Drawn outside any window, the preview shows ImGui's empty Debug window, so the blocks are drawn in a window of
    -- their own that shows nothing itself.
    local screen = imgui.GetIO().DisplaySize;
    imgui.SetNextWindowPos({ 0, 0 }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ screen.x, screen.y }, ImGuiCond_Always);
    imgui.Begin('##readme_overhead', true, flags);
    local places = {};
    for index, block in ipairs(blocks) do
        preview.show(block[1]);
        W.entities[W.self].x, W.entities[W.self].y = block[2], 5;
        W.frame(view, settings, snapshot, false, 0);
        preview.draw(settings, snapshot, moment);
        places[index] = { preview._unit.anchor_x, preview._unit.anchor_y };
    end;
    imgui.End();
    for index, block in ipairs(blocks) do
        local width = imgui.CalcTextSize(block[3]);
        if type(width) == 'table' then width = width.x or width[1]; end;
        C.caption(index, places[index][1] - width / 2 - 8, places[index][2] + 4, block[3]);
    end;
end;
