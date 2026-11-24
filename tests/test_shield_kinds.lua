-- Physical Shield, Arrow Shield, Magic Shield, Damage Spikes and Shining Ruby (150 to 154) are buffs on whoever has
-- them, and Phoenix flags all five dispelable (data/status_effects.yaml). A mob's Magic Shield turns away Dispel, Magic
-- Finale, Blank Gaze and Dark Shot (scripts/combat/basic/magic_hit_rate.lua :547-550), and the only Arrow Shield a mob
-- is seen to get is Airy Shield's, which has its dispelable flag taken off (scripts/actions/mobskills/airy_shield.lua
-- :19-22), so neither is in the dispelable list. The one Magic Shield that lights is a Soulflayer's Immortal Shield
-- (test_magic_shield_light.lua). Through vantage.lua as the game drives it (live_fixture.lua): a RDM 75 with Dispel, your own Shining
-- Ruby and Protect from the client's buff list, Bob's Shining Ruby from his 0x076, and a mob that uses Energy Screen
-- (1522, Physical Shield) and Thornsong (650, Damage Spikes) and casts Protect, then uses Mana Screen (1523, Magic Shield),
-- after which none of its buffs light.
local L = require('live_fixture');
local W = L.W;
local theme = require('ui.theme');
MOCK.player.main_job, MOCK.player.main_level, MOCK.player.sub_job, MOCK.player.sub_level = 5, 75, 0, 0;
AshitaCore:GetMemoryManager():GetPlayer().HasSpell = function(_, id) return id == 260; end;
MOCK.player.buffs = { 154, 40 };
local MOB = 0x1000100;
W.unit(0x100, MOB, 'mob', 0, -5, { name = 'Proto-Ultima', hitbox = 1.2 });
W.target = 0x100;

-- The background draw list, for the overhead icons: each image, and whether the call after it is the lit border.
local calls = {};
local list = setmetatable({}, { __index = function(_, name)
    return function(_, a)
        if name == 'AddImage' then L.images[#L.images + 1] = a; calls[#calls + 1] = { 'image', a };
        elseif name == 'AddRect' then calls[#calls + 1] = { 'rect' }; end
    end;
end });
rawset(require('imgui'), 'GetBackgroundDrawList', function() return list; end);
local function frame() for i = #calls, 1, -1 do calls[i] = nil; end; MOCK.imgui_calls = {}; L.frame(); end
local function overhead()
    local drawn, lit = {}, {};
    for i, call in ipairs(calls) do
        if call[1] == 'image' then
            drawn[call[2] - 5000] = true;
            if calls[i + 1] and calls[i + 1][1] == 'rect' then lit[call[2] - 5000] = true; end
        end
    end
    return drawn, lit;
end
-- The icons each panel window draws, and which of Target timers' icons have a border in its light color.
local function panels(settings)
    local edge = theme.u32(settings.panels.target.dispel_color);
    local by_window, inside, images, edges = {}, nil, {}, {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Begin' then inside = call[2]; by_window[inside] = by_window[inside] or {};
        elseif call[1] == 'End' then inside = nil;
        elseif inside and call[1] == 'draw:AddImage' then
            local copy = MOCK.drawn[call];
            by_window[inside][copy[2] - 5000] = true;
            if inside == '##vantage_target' then images[#images + 1] = copy; end
        elseif inside == '##vantage_target' and call[1] == 'draw:AddRect' and MOCK.drawn[call][4] == edge then
            edges[#edges + 1] = MOCK.drawn[call];
        end
    end
    local lit = {};
    for _, rect in ipairs(edges) do
        for _, image in ipairs(images) do
            if rect[2][1] <= image[3][1] and rect[3][1] >= image[4][1] and rect[2][2] <= image[3][2] and rect[3][2] >= image[4][2] then
                lit[image[2] - 5000] = true;
            end
        end
    end
    return by_window, lit;
end
local function keys(set)
    local out = {};
    for k in pairs(set or {}) do out[#out + 1] = k; end
    table.sort(out);
    return table.concat(out, ',');
end

local app = L.start();
local settings = app.state.settings;
settings.panels.target.dispel_light = true;
L.listing({ { 1002, 0x401, { 154 } }, { 1003, 0x402, {} } });
L.action(11, 1522, MOB, { { id = MOB, rows = { { message = 186, param = 150 } } } });
L.action(11, 650, MOB, { { id = MOB, rows = { { message = 186, param = 153 } } } });
L.action(4, 43, MOB, { { id = MOB, rows = { { message = 230, param = 40 } } } });
frame(); frame(); frame();
assert(require('core.dispel').ready(MOCK.now) == true, 'Fixture: a RDM 75 with Dispel learned can take a buff off.');
local drawn, lit = overhead();
local windows, target_lit = panels(settings);
assert(lit[150] and lit[153] and lit[40], 'Over its head, its Physical Shield, Damage Spikes and Protect light: ' .. keys(lit));
assert(target_lit[150] and target_lit[153] and target_lit[40], 'Target timers lights the same: ' .. keys(target_lit));
L.action(11, 1523, MOB, { { id = MOB, rows = { { message = 186, param = 152 } } } });
frame(); frame(); frame();
for _, pair in ipairs({ { MOB, 150 }, { MOB, 152 }, { MOB, 153 }, { 1001, 154 }, { 1002, 154 } }) do
    local row = L.row(pair[1], pair[2]);
    assert(row and row.kind == 'buff', pair[2] .. ' on ' .. pair[1] .. ' is a buff: ' .. tostring(row and row.kind));
end
windows, target_lit = panels(settings);
local self_buffs, self_debuffs = windows['##vantage_self_buffs'] or {}, windows['##vantage_self_debuffs'] or {};
assert(self_buffs[154] and not self_debuffs[154], 'Your Shining Ruby is in Self buffs: ' .. keys(self_buffs) .. ' / Self debuffs '
    .. keys(self_debuffs));
drawn, lit = overhead();
assert(drawn[150] and drawn[152] and drawn[153], 'The mob\'s own shields show over its head: ' .. keys(drawn));
assert(next(lit) == nil, 'With its Magic Shield on, none of its buffs light over its head: ' .. keys(lit));
assert(next(target_lit) == nil, 'Nor on Target timers: ' .. keys(target_lit));
local dispel = require('core.dispel');
assert(dispel.buffs[150] and dispel.buffs[153] and dispel.buffs[154] and not dispel.buffs[151] and not dispel.buffs[152],
    'Arrow Shield and Magic Shield aren\'t in the dispelable list.');
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return 'Shields and Shining Ruby are buffs, and the ones Phoenix lets you take off light';
