local hud, imgui = require('ui.hud'), require('imgui');
local app = PREVIEW.addon;
local view = hud.sample(100);
view.notices = { { visual = true, test = true, ends = 1000, message = 'Haste is ending soon.' } };
function PREVIEW.reset(kind)
    hud.cancel_gesture(); hud.cancel_notice_gesture();
    local s = app.state.settings;
    for _, panel in pairs(s.panels) do panel.enabled = false; end
    s.window.open, s.style.scale = false, 1;
    local p = s.panels.self_buffs;
    p.enabled, p.locked = kind == 'timer', false;
    p.x, p.y, p.width, p.height_limit, p.auto_width, p.auto_height = 200, 200, 320, 280, false, false;
    s.alerts.enabled, s.alerts.muted, s.alerts.notice_locked = kind == 'notice', false, false;
    s.alerts.notice_x, s.alerts.notice_y, s.alerts.notice_width, s.alerts.notice_height = 200, 200, 320, 160;
    app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
end
function PREVIEW.verify(kind, edge)
    local s = app.state.settings;
    local p = kind == 'timer' and s.panels.self_buffs or s.alerts;
    local x, y = kind == 'timer' and p.x or p.notice_x, kind == 'timer' and p.y or p.notice_y;
    local w, h = kind == 'timer' and p.width or p.notice_width, kind == 'timer' and p.height_limit or p.notice_height;
    local horizontal, vertical = require('ui.resize').axes(edge);
    local left, top = edge:find('left', 1, true), edge:find('top', 1, true);
    assert(x == (left and 220 or 200) and y == (top and 215 or 200), kind .. ' origin ' .. edge .. ' ' .. x .. ',' .. y);
    assert(w == (horizontal and (left and 300 or 340) or 320), kind .. ' width ' .. edge);
    local start_height = kind == 'timer' and 280 or 160;
    assert(h == start_height + (vertical and (top and -15 or 15) or 0), kind .. ' height ' .. edge);
    assert(#app.state.history == 1 and app.state.transaction == nil, 'One drag is one completed history entry.');
    assert(app.callbacks.undo());
    s = app.state.settings; p = kind == 'timer' and s.panels.self_buffs or s.alerts;
    assert((kind == 'timer' and p.width or p.notice_width) == 320);
    assert((kind == 'timer' and p.height_limit or p.notice_height) == start_height);
    assert(app.callbacks.redo());
    s = app.state.settings; p = kind == 'timer' and s.panels.self_buffs or s.alerts;
    assert((kind == 'timer' and p.width or p.notice_width) == w);
    assert((kind == 'timer' and p.height_limit or p.notice_height) == h);
end
PREVIEW.reset('timer');
return function()
    PREVIEW.settings = app.state.settings;
    app.callbacks.shift = imgui.GetIO().KeyShift == true;
    hud.draw(view, PREVIEW.settings, 100, app.callbacks);
    PREVIEW.settings = app.state.settings;
end
