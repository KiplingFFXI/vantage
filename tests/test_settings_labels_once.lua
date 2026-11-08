-- A search opens every fold of a page at once, so two controls with one ImGui id on a page break each other: the one
-- on screen takes no click. Every color on the main page keeps an id of its own.
local defaults, hud = require('ui.defaults'), require('ui.hud');
local window, imgui = require('ui.settings_window'), require('imgui');
local s = defaults.tidy(defaults.make());
s.window.open, s.window.tab = true, 'Home';
s.style.text_outline = true;
s.window.sections = setmetatable({}, { __index = function() return true; end });
local view = hud.sample(100);
view.context = { valid = true, job = 3, party = {}, entities = {} };
local cb = { now = function() return 100; end, save = function() return true; end, editor_changed = function() end,
    changed = function() end, reset = function() return true; end, sound_files = function() return {}; end };
local real, seen = imgui.ColorEdit4, nil;
imgui.ColorEdit4 = function(label, ...)
    if seen then seen[label] = (seen[label] or 0) + 1; end;
    return real(label, ...);
end;
local input = imgui.InputTextWithHint;
imgui.InputTextWithHint = function(label, hint, value, ...)
    if label == '##find_settings' then value[1] = 'color'; end;
    return input(label, hint, value, ...);
end;
window.draw(s, view, cb);
window.draw(s, view, cb);
seen = {};
window.draw(s, view, cb);
for label, count in pairs(seen) do assert(count == 1, 'One color id, drawn twice: ' .. label); end;
assert(seen['Outline color##main_countdown_color'] and seen['Outline color##main_text_color'] and seen['Text##main_color'],
    'Fixture: the search shows both outline colors and the Colors fold together.');
return 'Colors keep their own ids';
