local policy = {};
local bit = require('bit');
local overlay;

-- The window flags the party list strips' windows take: no title bar, resizing, moving, collapsing, saved state or
-- background, no focus when it appears, no keyboard navigation and no docking. Worked out once, on the first call,
-- after ImGui's constants are set.
function policy.overlay_flags()
    overlay = overlay or bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoMove,
        ImGuiWindowFlags_NoCollapse, ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoBackground,
        ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoDocking or 0);
    return overlay;
end;

return policy;
