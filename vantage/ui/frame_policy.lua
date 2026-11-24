local policy = {};
local bit = require('bit');

-- The window flags of Vantage's own windows, by name. OVERLAY is the party list strips': no title bar, resizing, moving,
-- collapsing, saved state or background, no focus when it appears, no keyboard navigation and no docking. BOX adds no
-- scrollbar and no mouse wheel, for the timer panels, the boxed displays and the ready pulse. NOTICE is the alert
-- notices', which leave out the mouse wheel as they always have. HIT is edit mode's outlines', which never come to the
-- front when clicked.
policy.OVERLAY = { 'NoTitleBar', 'NoResize', 'NoMove', 'NoCollapse', 'NoSavedSettings', 'NoBackground', 'NoFocusOnAppearing',
    'NoNav', 'NoDocking' };
policy.BOX = { 'NoTitleBar', 'NoResize', 'NoMove', 'NoCollapse', 'NoScrollbar', 'NoScrollWithMouse', 'NoSavedSettings',
    'NoBackground', 'NoFocusOnAppearing', 'NoNav', 'NoDocking' };
policy.NOTICE = { 'NoTitleBar', 'NoResize', 'NoMove', 'NoCollapse', 'NoScrollbar', 'NoSavedSettings', 'NoBackground',
    'NoFocusOnAppearing', 'NoNav', 'NoDocking' };
policy.HIT = { 'NoTitleBar', 'NoResize', 'NoMove', 'NoCollapse', 'NoScrollbar', 'NoScrollWithMouse', 'NoSavedSettings',
    'NoBackground', 'NoFocusOnAppearing', 'NoNav', 'NoBringToFrontOnFocus', 'NoDocking' };
local open, closed = {}, {};

-- A list's flags, with NoInputs added unless inputs is set, so the mouse goes to the game. Each list is worked out on
-- its first use, once ImGui's constants are set, and kept.
function policy.flags(names, inputs)
    local flags = open[names];
    if not flags then
        flags = 0;
        for _, name in ipairs(names) do flags = bit.bor(flags, _G['ImGuiWindowFlags_' .. name] or 0); end
        open[names], closed[names] = flags, bit.bor(flags, ImGuiWindowFlags_NoInputs or 0);
    end
    if inputs then return flags; end
    return closed[names];
end;

-- The party list strips' flags.
function policy.overlay_flags()
    return policy.flags(policy.OVERLAY, true);
end;

return policy;
