local defaults, hud, window = require('ui.defaults'), require('ui.hud'), require('ui.settings_window');
local imgui = require('imgui');
local s, view = defaults.make(), hud.sample(100);
s.panels.self_buffs.mode, s.panels.self_buffs.stack_direction = 'bars', 'vertical';
s.window.open = true;
local sliders, called = {}, {};
imgui.BeginCombo = function() return true; end;
imgui.SliderFloat = function(label, value)
    if sliders[label] ~= nil then value[1], sliders[label] = sliders[label], nil; return true; end
    return false;
end;
local cb = {
    save = function() return true; end, changed = function() end, now = function() return 100; end,
    profile_list = function() return {}; end, profile_status = function() return {}; end,
    sound_files = function() return {}; end,
    sharing = function(enabled, scope) called.sharing = { enabled, scope }; return false, 'Shared file unavailable'; end,
    copy_text = function(value) called.clipboard = value; return true; end,
};
local function frame(page, click)
    s.window.tab = page or s.window.tab;
    if click then MOCK.clicks[click] = true; end
    window.draw(s, view, cb);
    assert(#MOCK.font_stack == 0);
end
sliders['##main_text_size'] = 999;
frame('Home');
assert(s.style.font_size == 48, 'Typed slider input is clamped immediately, before saving.');
sliders['##main_text_size'] = 0 / 0;
frame();
assert(s.style.font_size == 48, 'Nonfinite slider input never enters live settings.');
sliders['##main_opacity'] = -2;
frame();
assert(s.style.opacity == 0.05);
-- Snap distance shows while Grid mode is on.
s.edit_mode.grid_mode = true;
sliders['##main_snap_distance'] = 40;
frame('Home');
assert(s.edit_mode.snap_distance == 32);
s.style.font_size = 16;
frame('Profiles', 'Share settings across my characters');
assert(called.sharing[1] == true and called.sharing[2] == 'placement');
assert(not s.shared_layout, 'A failed sharing import leaves sharing disabled.');
s.shared_layout = true;
frame(nil, 'Where things are and how they look##presentation');
assert(called.sharing[1] == true and called.sharing[2] == 'presentation' and s.shared_scope == 'placement');
assert(#MOCK.commands == 0);
return true;
