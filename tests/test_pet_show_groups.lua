-- Pet's Show tab (ui/pet_settings.lua) has what any pet shows first, then each pet job's settings under its own
-- heading, and the bar colors under the tick that shows the bars. Pet has no Look tab.
local h = require('panel_fixture')();
h.fresh(function(s) s.pet.enabled = true; end);
h.on('pet', 'show');
-- Where text is first drawn on the frame, as a label or a line.
local function at(text)
    for index, call in ipairs(MOCK.imgui_calls) do
        for _, value in ipairs({ call[2], call[3] }) do
            if type(value) == 'string' and (value == text or value:sub(1, #text + 2) == text .. '##') then return index; end;
        end;
    end;
end;
local function before(first, second)
    assert(at(first) and at(second) and at(first) < at(second), first .. ' comes before ' .. second);
end;
before('Show HP, MP and TP', 'HP bar');
before('TP bar', 'Effects');
-- The three colors share one line while it has the room: the last call that draws before each swatch is SameLine.
local function after_same_line(text)
    for index, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'ColorEdit4' and call[2] == text .. '##frame' then
            for back = index - 1, 1, -1 do
                local name = MOCK.imgui_calls[back][1];
                if not name:find('^Get') and not name:find('^Calc') then return name == 'SameLine'; end;
            end;
        end;
    end;
end;
assert(after_same_line('MP bar') and after_same_line('TP bar'), 'MP bar and TP bar sit beside HP bar.');
before('Show pet command recasts', 'More about any pet');
before('More about any pet', 'Automaton');
for _, name in ipairs({ 'Show maneuvers and overload risk', 'Show automaton HP as a number', 'Show automaton MP as a number',
    'Show attachment timers', 'Show the automaton\'s build' }) do before('Automaton', name); before(name, 'Charmed and jug pets'); end;
for _, name in ipairs({ 'Show charm and jug time', 'Mark where Sic is ready', 'Show what Reward would heal' }) do
    before('Charmed and jug pets', name); before(name, 'Avatar and wyvern');
end;
before('Avatar and wyvern', 'Show what my avatar costs');
before('Show when Healing Breath would fire', 'Pet alerts');
assert(h.drawn()['Size and place'] and not h.drawn().Look, 'Pet has no Look tab.');
MOCK.fire('unload');
return 'Pet groups its Show tab by pet job';
