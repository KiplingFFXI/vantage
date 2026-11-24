-- ImGui shows a label up to its first ## and starts its ID again at ###. A font file or an icon folder can have a # in
-- its name, so the main page's lists show such a name whole, with a space after a # where it would join another, and
-- give it an ID of its own by its place in the list. Picking it still picks that name.
local defaults = require('ui.defaults');
local page, imgui, fonts = require('ui.main_page'), require('imgui'), require('ui.fonts');
local combo;
imgui.BeginCombo = function(label) return label == combo; end;
local names = { 'Agave', 'MyFont#', 'Two##Hash', 'C#' };
fonts.names = function() return names; end;
local helper = { search = { '' }, look = {} };
helper.changed = function(fn) fn(); end;
helper.open_page, helper.note, helper.mark, helper.tip, helper.heading = function() end, function() end, function() end,
    function() end, function() end;
helper.section = function() return false; end;
helper.confirm_look = function(_, action) action(); end;
helper.confirm_line = function() end;
helper.ask = function(_, _, action) action(); end;
helper.profile = { apply_starter = function() return true; end };
local cb = { displays_hidden = function() return false; end, show_displays = function() end, edit_mode = function() end };
local s = defaults.make();
local function draw(click)
    combo, MOCK.imgui_calls = '##main_font', {};
    if click then MOCK.clicks[click] = true; end;
    page.draw(imgui, s, {}, cb, helper);
    MOCK.clicks = {};
    local shown, ids = {}, {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Selectable' then
            shown[#shown + 1] = call[2]:match('^(.-)##') or call[2];
            ids[#ids + 1] = call[2]:match('###(.*)$') or call[2];
        end;
    end;
    return shown, ids;
end;

local shown, ids = draw();
assert(#shown == #names, 'Fixture: every font is listed, got ' .. #shown);
assert(shown[1] == 'Ashita (Agave)' and shown[2] == 'MyFont# ' and shown[3] == 'Two# #Hash' and shown[4] == 'C# ',
    'Each name shows whole: ' .. table.concat(shown, '|'));
local seen = {};
for _, id in ipairs(ids) do assert(not seen[id], 'Each name has an ID of its own: ' .. table.concat(ids, '|')); seen[id] = true; end;
draw(ids[2]);
assert(s.style.font == 'MyFont#', 'Picking a name with a # picks it, got ' .. tostring(s.style.font));
draw(ids[3]);
assert(s.style.font == 'Two##Hash', 'Picking a name with ## picks it, got ' .. tostring(s.style.font));
return 'A name with a # shows whole in the main page\'s lists';
