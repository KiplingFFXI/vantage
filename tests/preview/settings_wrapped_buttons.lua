local imgui, window, hud = require('imgui'), require('ui.settings_window'), require('ui.hud');
local s = PREVIEW.settings;
s.window.open, s.window.tab = true, 'Profiles';
s.window.x, s.window.y, s.window.height = 20, 20, 1000;
s.style.font, s.window_style.font_size = 'Agave', 36;
local button, ids, wrapped, unwrapped = imgui.Button, {}, false, false;
imgui.Button = function(label, ...)
    local caption = label:match('^(.-)##') or label;
    local identity = label:match('###(.*)$');
    if identity then
        assert(imgui.CalcTextSize(caption) + 16 <= imgui.GetContentRegionAvail(), 'Button caption fits: ' .. identity);
        local id = imgui.GetID(label);
        assert(id == imgui.GetID('Any caption###' .. identity), 'Wrapped and single-line labels share their ID.');
        if identity == 'Put every display back where it started' then
            if ids[identity] then assert(id == ids[identity], 'Resizing keeps the same actual button ID.'); end;
            ids[identity] = id;
            wrapped = wrapped or caption:find('\n', 1, true) ~= nil;
            unwrapped = unwrapped or caption:find('\n', 1, true) == nil;
        end;
    end;
    return button(label, ...);
end;
return function()
    s.window.width = PREVIEW.frame < 4 and 560 or 1000;
    window.draw(s, hud.sample(100), {});
    if PREVIEW.frame == PREVIEW.last_frame then
        assert(wrapped and unwrapped, 'The same button must be tested both wrapped and on one line.');
    end;
end;
