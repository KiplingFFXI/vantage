-- Moves with on Place: what a panel can follow, the rows each choice brings, and the follow it refuses. It writes the same
-- anchor Moves with writes for the other displays, and a panel keeps following while locked.
local h = require('panel_fixture')();
local defaults, elements, anchors = require('ui.defaults'), require('ui.elements'), require('core.anchors');
local panels = h.panels;
local MOVES = '##frame_Moves with';
local function offered()
    h.combo = MOVES;
    h.draw();
    h.combo = nil;
    local found = {};
    for _, call in ipairs(h.calls('Selectable')) do
        local text = tostring(call[2]);
        if text:find('##none$') or text:find('##screen$') or text:find('##party$') or text:find('##chat$') or text:find('##element:', 1, true) then
            found[#found + 1] = text;
        end;
    end;
    return found;
end;

-- The four kinds, then every other display that can be followed, by name. Never itself, and no id on show.
for _, id in ipairs({ 'self_buffs', 'watch', 'spell_recasts' }) do
    h.fresh();
    h.on(id, 'place');
    local list = offered();
    assert(list[1] == 'Nothing##none' and list[2] == 'A spot on the screen##screen' and list[3] == "The game's party list##party"
        and list[4] == 'The chat log##chat', 'The kinds come first on ' .. id);
    local named = {};
    for index = 5, #list do named[list[index]] = true; end;
    local count = 0;
    for _, element in ipairs(elements.list) do
        if element.anchor and element.id ~= id then
            count = count + 1;
            assert(named[element.label .. '##element:' .. element.id], element.label .. ' can be followed from ' .. id);
        end;
    end;
    assert(#list == 4 + count and not named[elements.label(id) .. '##element:' .. id], 'And nothing else, and never itself: ' .. id);
    assert(panels.follow_choices(id) == panels.follow_choices(id), 'The list is made once.');
end;

-- Each choice writes the anchor and brings its own rows.
h.fresh();
h.s.panels.self_buffs.locked = false;
h.bump();
h.on('self_buffs', 'place');
local spot_rows = { '##frame_Spot', '##frame_Across from it', '##frame_Down from it' };
local beside_rows = { '##frame_Side', '##frame_Line up', '##frame_Gap', '##frame_Along the side' };
local function rows(list, shown, when)
    for _, label in ipairs(list) do
        local drawn = h.called('BeginCombo', label) or h.called('SliderFloat', label);
        assert(drawn == shown, when .. ': ' .. label);
    end;
end;
local function anchor() return h.s.panels.self_buffs.anchor; end;
assert(anchor().to == 'none' and h.previews[MOVES] == 'Nothing', 'Fresh, it moves with nothing.');
rows(spot_rows, false, 'Nothing'); rows(beside_rows, false, 'Nothing');
assert(not h.says('It follows even while locked.'));
h.pick(MOVES, 'A spot on the screen##screen');
assert(anchor().to == 'screen' and h.previews[MOVES] == 'A spot on the screen');
rows(spot_rows, true, 'A spot'); rows(beside_rows, false, 'A spot');
assert(h.says('It follows even while locked.'), 'It says a lock does not stop it.');
h.pick('##frame_Spot', 'Bottom right##bottom_right');
assert(anchor().point == 'bottom_right');
h.slide('##frame_Across from it', -30);
h.slide('##frame_Down from it', 25);
assert(anchor().dx == -30 and anchor().dy == 25, 'A spot keeps its distance.');
h.pick(MOVES, "The game's party list##party");
assert(anchor().to == 'party');
rows(spot_rows, false, 'The party list'); rows(beside_rows, true, 'The party list');
assert(not h.called('Checkbox', 'Same width as the chat log##frame'), 'That is for the chat log.');
h.pick(MOVES, 'The chat log##chat');
assert(anchor().to == 'chat' and h.called('Checkbox', 'Same width as the chat log##frame'));
h.draw('Same width as the chat log##frame');
h.draw();
assert(h.s.panels.self_buffs.dock_match_width == true, 'Same width writes the saved key.');
h.pick(MOVES, 'Target timers##element:target');
assert(anchor().to == 'element' and anchor().element == 'target' and h.previews[MOVES] == 'Target timers', 'A display goes by its name.');
rows(beside_rows, true, 'A display');
h.pick('##frame_Side', 'Above##above');
h.pick('##frame_Line up', 'End##end');
h.slide('##frame_Gap', 9);
h.slide('##frame_Along the side', 14);
assert(anchor().side == 'above' and anchor().align == 'end' and anchor().gap == 9 and anchor().offset == 14);
assert(elements.follows(h.s, 'self_buffs') == 'target', 'The drawing follows what was picked.');
h.pick(MOVES, 'Nothing##none');
assert(anchor().to == 'none' and elements.follows(h.s, 'self_buffs') == nil, 'Nothing ends it.');

-- It refuses what would follow itself round, directly or through others, with a note and no Undo step.
h.fresh(function(s)
    s.panels.self_debuffs.anchor.to, s.panels.self_debuffs.anchor.element = 'element', 'self_buffs';
    s.panels.target.anchor.to, s.panels.target.anchor.element = 'element', 'self_debuffs';
    s.panels.self_buffs.locked = false;
end);
h.on('self_buffs', 'place');
local steps = #h.app.state.history;
h.pick(MOVES, 'Self debuffs##element:self_debuffs');
assert(h.s.panels.self_buffs.anchor.to == 'none' and #h.app.state.history == steps, 'A loop is left out.');
assert(h.says("Self debuffs already follows Self buffs, so Self buffs can't follow it."), 'The note says why.');
h.pick(MOVES, 'Target timers##element:target');
assert(h.s.panels.self_buffs.anchor.to == 'none' and #h.app.state.history == steps, 'A longer loop is too.');
h.pick(MOVES, 'Watched enemy timers##element:watch');
assert(h.s.panels.self_buffs.anchor.element == 'watch' and #h.app.state.history == steps + 1, 'A display that follows nothing back is fine.');

-- Put it back where it started: the first spot, and it stops moving with anything.
h.fresh(function(s)
    local p = s.panels.watch;
    p.locked, p.x, p.y = false, 77, 88;
    p.anchor.to = 'chat';
end);
h.on('watch', 'place');
h.draw('Put it back where it started##frame');
h.draw();
local p, first = h.s.panels.watch, defaults.make().panels.watch;
assert(p.x == first.x and p.y == first.y and not anchors.active(p.anchor), 'It stops moving with anything.');

MOCK.fire('unload');
return 'Moves with offers what a panel can follow, brings each choice its rows and refuses a loop';
