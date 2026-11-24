-- While a mob has a Magic Shield, Phoenix turns away Dispel, Magic Finale, Blank Gaze and Dark Shot
-- (scripts/combat/basic/magic_hit_rate.lua :547-550), so none of its buffs light, over its head or on Target timers. It
-- checks a Magic Shield with subType 0. A Soulflayer's Immortal Shield (mob skill 1965) puts one on with subType 45
-- (scripts/actions/mobskills/Immortal_shield.lua :15), so it blocks nothing and can be dispelled itself
-- (data/status_effects.yaml :1471-1474). Through vantage.lua as the game drives it (live_fixture.lua): a RDM 75 with
-- Dispel, and a mob that casts Protect and uses Energy Screen (1522, Physical Shield), then Mana Screen (1523, Magic
-- Shield for 60 seconds), then Immortal Shield.
local L = require('live_fixture');
local W = L.W;
local theme = require('ui.theme');
MOCK.player.main_job, MOCK.player.main_level, MOCK.player.sub_job, MOCK.player.sub_level = 5, 75, 0, 0;
AshitaCore:GetMemoryManager():GetPlayer().HasSpell = function(_, id) return id == 260; end;
local MOB = 0x1000100;
W.unit(0x100, MOB, 'mob', 0, -5, { name = 'Psycheflayer', hitbox = 1.2 });
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
local function frame(seconds) for i = #calls, 1, -1 do calls[i] = nil; end; MOCK.imgui_calls = {}; L.frame(seconds); end
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
-- The icons Target timers draws, and which of them have a border in its light color.
local function target(settings)
    local edge = theme.u32(settings.panels.target.dispel_color);
    local inside, images, edges, drawn = nil, {}, {}, {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Begin' then inside = call[2];
        elseif call[1] == 'End' then inside = nil;
        elseif inside == '##vantage_target' and call[1] == 'draw:AddImage' then
            local copy = MOCK.drawn[call];
            images[#images + 1], drawn[copy[2] - 5000] = copy, true;
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
    return drawn, lit;
end
local function keys(set)
    local out = {};
    for k in pairs(set or {}) do out[#out + 1] = k; end
    table.sort(out);
    return table.concat(out, ',');
end
-- Both displays, after a few frames: what each drew and lit.
local function look(settings, seconds)
    frame(seconds); frame(); frame();
    local drawn, lit = overhead();
    local panel, panel_lit = target(settings);
    return drawn, lit, panel, panel_lit;
end

local app = L.start();
local settings = app.state.settings;
settings.panels.target.dispel_light = true;
L.listing({ { 1002, 0x401, {} }, { 1003, 0x402, {} } });
L.action(11, 1522, MOB, { { id = MOB, rows = { { message = 186, param = 150 } } } });
L.action(4, 43, MOB, { { id = MOB, rows = { { message = 230, param = 40 } } } });
local drawn, lit, panel, panel_lit = look(settings);
assert(require('core.dispel').ready(MOCK.now) == true, 'Fixture: a RDM 75 with Dispel learned can take a buff off.');
assert(keys(lit) == '40,150' and keys(panel_lit) == '40,150', 'With no Magic Shield, its Protect and Physical Shield light: '
    .. keys(lit) .. ' / Target timers ' .. keys(panel_lit));

-- Mana Screen: every buff still shows, and none lights.
L.action(11, 1523, MOB, { { id = MOB, rows = { { message = 186, param = 152 } } } });
drawn, lit, panel, panel_lit = look(settings);
assert(drawn[40] and drawn[150] and drawn[152] and panel[40] and panel[150] and panel[152],
    'Fixture: its buffs still show: ' .. keys(drawn) .. ' / Target timers ' .. keys(panel));
assert(keys(lit) == '' and keys(panel_lit) == '', 'While it has a Magic Shield, none of its buffs light: ' .. keys(lit)
    .. ' / Target timers ' .. keys(panel_lit));

-- Once the shield's 60 seconds are up, they light again.
drawn, lit, panel, panel_lit = look(settings, 61);
assert(keys(lit) == '40,150' and keys(panel_lit) == '40,150', 'After its Magic Shield\'s time, its buffs light again: '
    .. keys(lit) .. ' / Target timers ' .. keys(panel_lit));

-- Immortal Shield blocks nothing, and lights itself.
L.action(11, 1965, MOB, { { id = MOB, rows = { { message = 186, param = 152 } } } });
drawn, lit, panel, panel_lit = look(settings);
assert(L.row(MOB, 152) and L.row(MOB, 152).spell == 1965, 'Fixture: the Magic Shield row is Immortal Shield\'s.');
assert(keys(lit) == '40,150,152' and keys(panel_lit) == '40,150,152', 'Immortal Shield lights, and so do the others: '
    .. keys(lit) .. ' / Target timers ' .. keys(panel_lit));

-- Mana Screen over it blocks them all again.
L.action(11, 1523, MOB, { { id = MOB, rows = { { message = 186, param = 152 } } } });
drawn, lit, panel, panel_lit = look(settings);
assert(keys(lit) == '' and keys(panel_lit) == '', 'Mana Screen over Immortal Shield lights nothing: ' .. keys(lit)
    .. ' / Target timers ' .. keys(panel_lit));
assert(app.state.problem == nil, 'Nothing went wrong: ' .. tostring(app.state.problem));
return 'A mob\'s Magic Shield keeps its buffs from lighting, and Immortal Shield doesn\'t';
