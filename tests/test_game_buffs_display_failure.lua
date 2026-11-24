-- Replace the game's buff icons while Vantage's own display keeps failing. With the game's icons skipped and nothing
-- of Vantage's drawn in their place, no buff icons would show at all, so after three failed frames in a row the
-- game draws its own again, and they are replaced again once a frame draws. One bad frame changes nothing. The game
-- side (core/game_buffs.lua) is a stand-in here, as in test_self_panel_menu_pick.lua.
local wants = {};
package.loaded['core.game_buffs'] = {
    update = function(want) wants[#wants + 1] = want; return nil; end,
    release = function() return true; end,
    status = function() return { on = wants[#wants] == true, moved = 0, returned = 0 }; end,
    problem = function() return nil; end,
};
local h = require('self_panel_fixture')();
local s = h.settings;
h.both({ 40, 41, 3 });
h.run(3);
s.replace_game_buffs = true;
h.frame();
assert(wants[#wants] == true, 'Fixture: the game\'s icons are replaced.');

local hud = h.hud;
local draw = hud.draw;
local broken = false;
hud.draw = function(...)
    if broken then error('Panel failed', 0); end
    return draw(...);
end;
-- What the game side was last told in each of the next frames.
local function told(count)
    local out = {};
    for index = 1, count do
        h.frame();
        out[index] = wants[#wants];
    end
    return out;
end
local function said(text)
    local count = 0;
    for _, line in ipairs(MOCK.printed) do if line:find(text, 1, true) then count = count + 1; end end
    return count;
end

-- One bad frame, then two: the game's icons stay replaced, so nothing flickers.
broken = true;
local seen = told(1);
broken = false;
assert(seen[1] == true, 'In the frame that fails the game\'s icons are still replaced.');
seen = told(3);
assert(seen[1] == true and seen[2] == true and seen[3] == true, 'One bad frame leaves them replaced.');
broken = true;
told(2);
broken = false;
seen = told(3);
assert(seen[1] == true and seen[2] == true and seen[3] == true, 'Two bad frames in a row leave them replaced.');

-- It keeps failing: the third failed frame in a row gives the game its icons back, for as long as it fails.
broken = true;
seen = told(3);
assert(seen[1] == true and seen[2] == true, 'Fixture: two failed frames leave them replaced.');
assert(seen[3] == false, 'The third failed frame in a row gives the game its buff icons back.');
seen = told(40);
for index = 1, 40 do assert(seen[index] == false, 'While the display keeps failing the game draws its own buff icons: frame ' .. index); end
assert(said('The display could not update. Panel failed') == 1, 'The failure is said once.');
-- It draws again: one frame draws with the game's icons still showing, and the next replaces them.
broken = false;
seen = told(3);
assert(seen[1] == false and seen[2] == true and seen[3] == true, 'Once the display draws again the game\'s icons are replaced again.');

-- A failure before the game side is asked at all, in the hide rules, gives the game's icons back the same way.
local filters = require('core.effect_filters');
local compile = filters.compile;
filters.compile = function(...)
    if broken then error('Rules failed', 0); end
    return compile(...);
end;
broken = true;
local asked = #wants;
told(2);
assert(#wants == asked and wants[#wants] == true, 'Fixture: two failed frames ask the game side nothing.');
told(1);
assert(wants[#wants] == false, 'Three frames that fail before the game side is asked still give the game\'s icons back.');
asked = #wants;
told(20);
assert(#wants == asked, 'And it is told once, not every frame.');
broken = false;
seen = told(2);
assert(seen[1] == false and seen[2] == true, 'They are replaced again once a frame draws.');

-- What fails after the self panels have drawn, as edit mode's outlines do, leaves the game's icons replaced: the
-- panels still show your effects, so giving the game its icons back would show both.
told(3);
assert(wants[#wants] == true, 'Fixture: the icons are replaced.');
local edit = require('ui.edit_mode');
local edit_draw = edit.draw;
edit.draw = function() error('Edit failed', 0); end;
seen = told(10);
for index = 1, 10 do assert(seen[index] == true, 'A failure after the panels drew leaves the game\'s icons replaced: frame ' .. index); end
edit.draw = edit_draw;
-- And a frame that fails before them counts from none again after such frames.
broken = true;
seen = told(2);
assert(seen[1] == true and seen[2] == true, 'Two failed frames after that still leave them replaced.');
broken = false;
told(2);

-- With the tick off, a failing display asks for nothing it wasn't already asking for.
s.replace_game_buffs = false;
told(2);
broken = true;
seen = told(6);
for index = 1, 6 do assert(seen[index] == false, 'With the tick off the game draws its own icons throughout.'); end
broken = false;
filters.compile, hud.draw = compile, draw;
return 'A display that keeps failing gives the game its buff icons back';
