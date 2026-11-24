-- The + menu line when no self panel draws and Self buffs Moves with something. The line goes by Self buffs where its
-- anchor puts it, not at the Across and Down it keeps for when the anchor's target isn't there. The game side of
-- Replace the game's buff icons is a stand-in, as in test_self_panel_menu_pick.lua.
local wants = {};
local pick;
package.loaded['core.game_buffs'] = {
    update = function(want) wants[#wants + 1] = want; return want and pick or nil, nil; end,
    release = function() return true; end,
    status = function() return { on = wants[#wants] == true, moved = 0, returned = 0 }; end,
    problem = function() return nil; end,
};
local h = require('self_panel_fixture')();
local imgui = require('imgui');
rawset(imgui, 'GetForegroundDrawList', function() return imgui.GetWindowDrawList(); end);
local elements = require('ui.elements');
local s = h.settings;

-- The + menu line's box, the filled rect drawn just before its text, and its text.
local function line_box()
    local last_fill;
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddRectFilled' then last_fill = MOCK.drawn[call]; end;
        if call[1] == 'draw:AddText' and type(call[6]) == 'string' and call[6]:find('^%+ menu: ') then
            return last_fill and last_fill[2][1], last_fill and last_fill[2][2], call[6];
        end;
    end;
end;
local function menu_on_protect()
    h.app.refresh(MOCK.now);
    pick = nil;
    h.run(2);
    pick = { effect = 40, copy = 1 };
    local record = h.frame();
    pick = nil;
    return record;
end;

-- Only Protect is on you, and Self buffs hides it, so neither self panel has a row.
h.both({ 40 });
h.run(3);
s.replace_game_buffs = true;
s.panels.self_buffs.exclude[40] = true;
assert(s.panels.self_buffs.x == 40 and s.panels.self_buffs.y == 120, 'Fixture: Self buffs\' own spot is 40,120.');
local anchor = s.panels.self_buffs.anchor;
anchor.to, anchor.point, anchor.dx, anchor.dy = 'screen', 'bottom_right', 0, 0;

-- Drawn empty, Self buffs sits at the screen's bottom right, and the line goes by it.
s.panels.self_buffs.empty = 'show';
menu_on_protect();
local drawn = elements.drawn('self_buffs');
assert(drawn and elements.anchored('self_buffs') and drawn.x >= 800 and drawn.y >= 500, 'Fixture: the empty Self buffs is at its anchored spot.');
local x, y, text = line_box();
assert(text and x >= 800 and y >= 500, 'With the panel drawn the line is by it: ' .. tostring(x) .. ',' .. tostring(y));

-- Hidden while empty, as at first, no self panel draws. The line still goes where Self buffs' anchor puts it.
s.panels.self_buffs.empty = 'hide';
local record = menu_on_protect();
assert(h.count(record.icons) == 0 and elements.drawn('self_buffs') == nil, 'Fixture: no self panel draws.');
x, y, text = line_box();
assert(text == '+ menu: ' .. require('core.catalog').get(40).name, 'The line shows with no self panel drawn: ' .. tostring(text));
assert(x >= 800 and y >= 500, ('The line is by Self buffs\' anchored spot at the bottom right, not at its own Across and Down: %s,%s')
    :format(tostring(x), tostring(y)));
assert(x + 1 <= MOCK.screen[1] and y + 1 <= MOCK.screen[2], 'The line stays on the screen.');

-- With the anchor's target not there, Self buffs falls back to its Across and Down, and so does the line.
anchor.to, anchor.element = 'element', 'pet';
assert(not s.pet.enabled, 'Fixture: the Pet display isn\'t drawn.');
menu_on_protect();
x, y, text = line_box();
assert(text and x == 40 and y < 200, 'With nothing to move with, the line stays by Self buffs\' own spot: ' .. tostring(x) .. ',' .. tostring(y));
return 'The + menu line follows Self buffs\' anchor';
