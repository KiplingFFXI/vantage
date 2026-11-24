-- Most shown goes no higher than 64, and at its top it says 64, not All. A full party with Include me on lists more
-- than 64 effects on Party members' timers, and the panel leaves the rest out even with room for them.
local defaults, hud = require('ui.defaults'), require('ui.hud');
local window, panels = require('ui.settings_window'), require('ui.panel_frame');
local imgui, icons = require('imgui'), require('ui.icons');
icons.status = function() return 1234; end;
MOCK.screen = { 1600, 4000 };

local cb = { now = function() return 100; end, save = function() return true; end, changed = function() end };

-- What the Most shown slider is drawn with: its top, and what it says, as ImGui puts the value in its format.
local MOST = '##frame_Most shown';
local slider;
imgui.SliderFloat = function(label, box, low, top, format)
    if label == MOST then slider = { value = box[1], top = top, says = format:format(box[1]) }; end;
    return false;
end;

-- A timer panel and a recast panel, each slid to the top.
for _, id in ipairs({ 'party', 'spell_recasts' }) do
    local s = defaults.make();
    s.window.open, s.window.tab = true, 'Display';
    s.panels[id].max_rows = 64;
    panels.open(id, 'show');
    slider = nil;
    window.draw(s, hud.sample(100), cb);
    assert(slider and slider.value == 64 and slider.top == 64, 'Fixture: ' .. id .. ' draws Most shown at its top, 64.');
    assert(slider.says == '64', id .. ': Most shown at its top says 64, the most rows the panel draws. It says ' .. slider.says .. '.');
end;

-- Six people with twelve effects each, with Include me on: 72 rows for Party members' timers.
local s = defaults.make();
for id, panel in pairs(s.panels) do panel.enabled = id == 'party'; end;
local p = s.panels.party;
p.mode, p.include_self, p.auto_height, p.height_limit, p.locked = 'icons', true, true, 4000, true;
local rows = {};
for member = 0, 5 do
    for _, effect in ipairs({ 40, 41, 33, 43, 42, 198, 214, 317, 321, 251, 113, 253 }) do
        rows[#rows + 1] = { key = member .. ':' .. effect, effect = effect, name = 'E' .. effect, kind = 'buff',
            scope = member == 0 and 'self' or 'party', entity_id = 1001 + member, entity_name = 'M' .. member,
            status = 'server', deadline = 200 + effect, present = true };
    end;
end;
local view = { valid = true, context = { id = 1001 }, rows = rows };
assert(#hud.filter_rows(view, p, 'party', s) == 72, 'Fixture: the panel lists all 72 effects.');
p.max_rows = 72;
assert(hud.bounds(p, s.style, 72, 1600, 4000).shown == 72, 'Fixture: the panel has room for all 72.');

p.max_rows = 64;
MOCK.imgui_calls = {};
hud.draw(view, s, 100, {});
local drawn = 0;
for _, call in ipairs(MOCK.imgui_calls) do
    if call[1] == 'draw:AddImage' and call[2] == 1234 then drawn = drawn + 1; end;
end;
assert(drawn == 64, 'At Most shown 64 the panel draws 64 of the 72 effects, as the slider says: ' .. drawn);
return 'Most shown says 64 at its top, the most rows a panel draws';
