-- ImGui's resize corners take clicks in a square about a line of text tall at the settings window's bottom corners. The
-- page ends above them at any text size, and keeps all of its room when they're already below it.
local h = require('panel_fixture')();
local imgui = h.imgui;
local begin_child, page = imgui.BeginChild, nil;
imgui.BeginChild = function(label, size, ...)
    if label == '##settings_content' then page = { height = size[2], font = imgui.GetFontSize() }; end;
    return begin_child(label, size, ...);
end;

-- The mock puts the page's top at 14 and gives it 480 pixels down to the window's padding.
local function draw(text_size, height)
    h.fresh(function(s)
        s.window.x, s.window.y, s.window.width, s.window.height = 0, 0, 880, height;
        s.window_style.font_size = text_size;
    end);
    page = nil;
    h.draw(); h.draw();
    assert(page, 'The page is drawn.');
    local _, top = imgui.GetCursorScreenPos();
    return top + page.height, page.font;
end;

for _, text_size in ipairs({ 17, 24, 36 }) do
    local bottom, font = draw(text_size, 508);
    assert(bottom <= 508 - font, ('At text size %d the page reaches %d px from the bottom edge, inside the %d px corners.')
        :format(text_size, 508 - bottom, font));
    bottom = draw(text_size, 640);
    assert(bottom == 14 + 480, ('At text size %d, with the corners already below the page, it keeps all its room.'):format(text_size));
end;
