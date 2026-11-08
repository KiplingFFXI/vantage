-- Each reset scope restores only what it names, and the reset that would delete alert rules asks first.
local defaults, custom = require('ui.defaults'), require('core.customization');
local hud, window = require('ui.hud'), require('ui.settings_window');
local imgui = require('imgui');

-- What each reset scope restores, on settings that differ from the defaults everywhere these scopes look.
local function changed_settings()
    local s = defaults.make();
    s.style.font_size, s.style.icon_size, s.style.scale = 20, 40, 1.5;
    s.style.text_color = { 0.1, 0.2, 0.3, 1 };
    s.style.hover = false;
    s.window_style.font_size = 16;
    s.enabled, s.visibility.hide_events = false, false;
    s.tracking.stale_seconds = 600;
    s.window.peek = false;
    s.window.x, s.window.tab, s.window.sections['Home/Alerts'] = 333, 'Appearance', true;
    s.panels.self_buffs.colors = { text = { 0.5, 0.5, 0.5, 1 } };
    return s;
end
local fresh = defaults.make();
local function same(a, b) return custom.equal(a, b); end
local function reset(scope) return assert(custom.reset(changed_settings(), scope)); end
local base = changed_settings();

local menus = reset('window_style');
assert(same(menus.window_style, fresh.window_style) and same(menus.style, base.style), 'Settings menus restores only the menus.');

local navigation = reset('navigation');
assert(navigation.window.peek == true, 'Settings navigation restores peeking.');
assert(navigation.window.x == 333 and navigation.window.tab == 'Appearance' and navigation.window.sections['Home/Alerts'] == true
    and same(navigation.style, base.style) and same(navigation.window_style, base.window_style) and same(navigation.visibility, base.visibility),
    'Settings navigation keeps the window\'s place and open sections and every other setting.');

-- /vg reset appearance still restores the timers and the menus together.
local appearance = reset('appearance');
assert(same(appearance.style, fresh.style) and same(appearance.window_style, fresh.window_style), 'The appearance reset is unchanged.');

-- On the page the button passes its own scope.
local s, view = defaults.make(), hud.sample(100);
s.window.open, s.window.tab = true, 'Alerts';
local resets = {};
local cb = {
    now = function() return 100 end, save = function() return true end, changed = function() end,
    reset = function(scope) resets[#resets + 1] = scope; return true end,
    sound_files = function() return {} end,
};
imgui.BeginCombo = function() return true end;
local function frame(click)
    MOCK.imgui_calls = {};
    if click then MOCK.clicks[click] = true end;
    window.draw(s, view, cb);
    if click then assert(not MOCK.clicks[click], 'The control is on screen: ' .. click) end;
end
local function drawn(kind, label)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == kind and call[2] == label then return true end end
    return false;
end
-- Alerts has one reset, and its question says what it deletes.
s.window.tab = 'Display';
require('ui.panel_frame').open('notices', 'show');
s.alerts.rules = { defaults.rule('first'), defaults.rule('second') };
frame(); frame();
assert(drawn('Button', 'Reset this display##frame') and not drawn('Button', 'Reset this page') and not drawn('Button', 'Reset alert settings'),
    'Alerts has one reset, Reset this display.');
local RESET, CANCEL, DO_IT = 'Reset this display##frame', 'Cancel##look_frame_reset_notices', 'Reset##look_frame_reset_notices';
local asked = 'Reset Alerts? It goes back to how it started: locked, in its first spot.';
local count = #resets;
frame(RESET); frame();
assert(#resets == count and drawn('TextWrapped', asked .. ' This deletes all 2 alert rules.'), 'It asks first and resets nothing yet.');
frame(CANCEL); frame();
assert(#resets == count and not drawn('TextWrapped', asked .. ' This deletes all 2 alert rules.'), 'Cancel keeps the rules.');
frame(RESET); frame(DO_IT);
assert(#resets == count + 1 and resets[#resets] == 'alerts', 'Reset in the question resets the page.');
s.alerts.rules = { s.alerts.rules[1] };
frame(RESET); frame();
assert(drawn('TextWrapped', asked .. ' This deletes your alert rule.'), 'One rule is named as one rule.');
frame(CANCEL);
s.alerts.rules = {};
frame(); frame(RESET); frame();
assert(drawn('TextWrapped', asked), 'With no rules to lose it says nothing of them.');
frame(CANCEL);
return true;
