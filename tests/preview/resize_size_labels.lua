-- Replay pointer input in the preview harness; no game interaction is involved.
local app = assert(PREVIEW.addon);
local imgui, hud, resize = require('imgui'), require('ui.hud'), require('ui.resize');
local fonts, defaults = require('ui.fonts'), require('ui.defaults');
local settings = defaults.make();
app.state.settings, PREVIEW.settings = settings, settings;
app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
require('ui.theme').apply(settings, 'Original FFXI');
local face = PREVIEW.test_font or 'Original FFXI';
settings.style.font, settings.style.icon_art, settings.style.gauge_art = face, face, face;
settings.style.scale, settings.style.font_size = 1, 16;
settings.style.icon_size = 32;
settings.enabled, settings.preview, settings.window.open, settings.alerts.enabled = true, false, false, false;
for _, panel in pairs(settings.panels) do panel.enabled = false; end;
local panel = settings.panels.self_buffs;
panel.enabled, panel.locked, panel.mode = true, true, 'icons';
panel.x, panel.y, panel.width, panel.height_limit = 200, 180, 320, 180;
panel.auto_width, panel.auto_height, panel.wrap, panel.stack_direction = false, false, true, 'horizontal';
require('ui.icons').prepare();
local view = hud.sample(100);
view.notices = {};
local actual_label, actual_draw, actual_button = resize.label, fonts.draw, imgui.InvisibleButton;
local active, latest, buttons, visible, checks = nil, nil, 0, false, 0;
imgui.InvisibleButton = function(...)
    buttons = buttons + 1;
    return actual_button(...);
end;
fonts.draw = function(list, font, text, ...)
    if active then active.texts[#active.texts + 1] = text; end;
    return actual_draw(list, font, text, ...);
end;
resize.label = function(list, rect, identity, look)
    local x, y = imgui.GetWindowPos();
    local width, height = imgui.GetWindowSize();
    local before = buttons;
    active = {x=x,y=y,width=width,height=height,texts={}};
    actual_label(list, rect, identity, look);
    assert(buttons == before, 'The badge does not add an invisible button');
    assert(active.texts[1] == 'Self buffs', 'The display identity remains the first line');
    local wanted = ('%d x %d px'):format(math.floor(width + 0.5), math.floor(height + 0.5));
    assert(active.texts[2] == wanted, 'The visible size must match the actual ImGui window: '..wanted);
    assert(#active.texts == 2, 'The ordinary identity and dimensions use exactly two lines');
    latest, active, visible = active, nil, true;
end;
function PREVIEW.verify_locked()
    assert(panel.locked and panel.x == 200 and panel.y == 180);
    assert(panel.width == 320 and panel.height_limit == 180, 'Shift never bypasses the saved lock');
    assert(not visible and buttons == 0, 'A locked display has no badge or placement input target');
    assert(#app.state.history == 0, 'Ignored locked input does not create layout history');
    checks = checks + 1;
    panel.locked = false;
end;
function PREVIEW.verify_size(width, height, held)
    assert(latest and visible, 'The badge is visible while arranging an unlocked display');
    assert(latest.width == width and latest.height == height, 'Rendered size updates in both directions');
    assert(panel.width == width and panel.height_limit == height, 'Saved geometry follows the actual resize');
    assert(latest.x == 200 and latest.y == 180, 'The corner resize preserves the opposite corner');
    assert(buttons == 1, 'Only the existing panel placement input target is present');
    assert((app.state.transaction ~= nil) == held, 'Size updates are tested during the active gesture');
    if not held then assert(#app.state.history == 1, 'A completed resize produces one history entry'); end;
    checks = checks + 1;
end;
function PREVIEW.verify_hidden()
    assert(not visible and buttons == 0, 'Releasing Shift hides the badge and placement input target');
    assert(panel.width == 400 and panel.height_limit == 240, 'Hiding the badge does not change geometry');
    checks = checks + 1;
end;
return function()
    buttons, visible = 0, false;
    app.callbacks.shift = imgui.GetIO().KeyShift == true;
    hud.draw(view, settings, 100, app.callbacks);
    assert(not fonts.failed(face), 'The selected client bitmap font must be available');
    if PREVIEW.frame == PREVIEW.last_frame then
        assert(checks == 5, 'All locked, live-size, released and hidden checks ran');
        assert(#MOCK.commands == 0, 'The replay never issues gameplay commands');
        PREVIEW.log('Live size badges passed: '..face..'; locked drag ignored; held 360 x 210 then 400 x 240; actual window bounds; no extra hit targets.');
    end;
end;
