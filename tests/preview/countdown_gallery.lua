-- Draw all countdown styles with installed artwork; ordinary frame text stays unchanged.
local imgui, fonts = require('imgui'), require('ui.fonts');
local countdown, icons = require('ui.countdown_text'), require('ui.icons');
local faces = PREVIEW.countdown_native and { 'Original FFXI', 'XI View', 'Agave' } or { 'Agave' };
icons.prepare();
local function plain(list, face, text, x, y, size, color)
    if not fonts.draw(list, face, text, x, y, size, color) then list:AddText({ x, y }, color, text); end;
end;
return function()
    imgui.SetNextWindowPos({ 0, 0 }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ 1170, 750 }, ImGuiCond_Always);
    imgui.Begin('##countdown_combinations', true, ImGuiWindowFlags_NoDecoration + ImGuiWindowFlags_NoMove
        + ImGuiWindowFlags_NoResize + ImGuiWindowFlags_NoSavedSettings);
    local list = imgui.GetWindowDrawList();
    for column, face in ipairs(faces) do
        local x = 15 + (column - 1) * 390;
        if PREVIEW.countdown_native and face ~= 'Agave' then assert(not fonts.failed(face), face .. ' artwork must load.'); end;
        fonts.push(face, 16);
        plain(list, face, face, x + 10, 16, 16, 0xffffffff);
        for index = 0, 7 do
            local y = 52 + index * 85;
            local options = { countdown_bold = index % 2 == 1, countdown_shadow = math.floor(index / 2) % 2 == 1,
                countdown_outline = math.floor(index / 4) % 2 == 1, countdown_outline_color = { 0, 0, 0, 1 } };
            list:AddRectFilled({ x, y }, { x + 365, y + 74 }, 0xff282218);
            plain(list, face, 'Fennel HP 100%', x + 135, y + 12, 16, 0xffffffff);
            local label = ('Bold %s   Shadow %s   Outline %s'):format(options.countdown_bold and 'on' or 'off',
                options.countdown_shadow and 'on' or 'off', options.countdown_outline and 'on' or 'off');
            list:AddText({ x + 10, y + 52 }, 0xffd8d8d8, label);
            local icon = icons.status(33, face == 'Agave' and 'Client' or face);
            if icon then list:AddImage(icon, { x + 10, y + 8 }, { x + 42, y + 40 }); end;
            local width, height = countdown.measure(face, '1:23', 16, options);
            assert(width > 0 and width <= 80 and height > 0 and height <= 24, 'Styled bounds fit their reserved timer slot.');
            countdown.draw(list, face, '1:23', x + 55, y + 12, 16, 0xffffffff, options);
        end;
        fonts.pop();
    end;
    imgui.End();
    PREVIEW.log('Countdown combinations and unchanged frame text rendered');
end;
