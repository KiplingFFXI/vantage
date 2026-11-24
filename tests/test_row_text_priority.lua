-- Look > Row text > Priority when space is short shows the priority each part goes by. With none saved, that's the one
-- ui/fields.lua gives the part (Name 90, Countdown 100), not the slider's low end. A saved priority shows as it is, 0
-- too.
local defaults = require('ui.defaults');
local hud = require('ui.hud');
local window = require('ui.settings_window');
local panels = require('ui.panel_frame');
local imgui = require('imgui');

-- Party members' timers starts as bars with row text on, so Row text is there. Wrap long rows starts off.
local s, view = defaults.make(), hud.sample(100);
local p = s.panels.party;
s.window.open, s.window.tab = true, 'Display';
local cb = { now = function() return 100; end, save = function() return true; end, changed = function() end };

-- What the Priority slider is drawn with, each time it's drawn in a frame. Every number row shares one value box, so
-- it's read during the call.
local PRIORITY = '##frame_Priority when space is short_part';
local slider = {};
imgui.SliderFloat = function(label, box)
    if label == PRIORITY then slider[#slider + 1] = box[1]; end;
    return false;
end;

local function frame(click)
    slider = {};
    MOCK.imgui_calls = {};
    if click then MOCK.clicks[click] = true; end;
    window.draw(s, view, cb);
    if click then assert(MOCK.clicks[click] == nil, 'Fixture: the click on ' .. click .. ' landed.'); end;
end

-- Whether the part named name is the one open in Parts of a row, as its Selectable was drawn this frame.
local function part_open(name)
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Selectable' and call[2] == name then return call[3] == true; end;
    end;
    return nil;
end

assert(p.mode == 'bars' and p.show_text ~= false and p.wrap == false and p.priority_overflow == false,
    'Fixture: Party members\' timers starts as bars with row text, no wrap, and priority off.');
assert(next(p.field_priority) == nil, 'Fixture: no part has a saved priority.');

panels.open('party', 'look');
frame();
assert(part_open('Name') == true, 'Fixture: Name is the part open in Row text.');
assert(#slider == 0, 'Fixture: the Priority row waits for When space is short, keep the higher-priority parts.');

-- Tick When space is short, keep the higher-priority parts, as a player does.
frame('When space is short, keep the higher-priority parts##frame');
assert(p.priority_overflow == true, 'Fixture: the tick turned priority on.');

frame();
assert(part_open('Name') == true and #slider == 1, 'Fixture: the Priority slider is drawn once for Name.');
local shown = { name = slider[1] };

frame('Countdown');
frame();
assert(part_open('Countdown') == true and part_open('Name') == false, 'Fixture: Countdown is the part open now.');
assert(#slider == 1, 'Fixture: the Priority slider is drawn once for Countdown.');
shown.time = slider[1];
assert(next(p.field_priority) == nil, 'Fixture: drawing the sliders saved no priority.');

-- What the rows go by: a Protect on Ally with a known time, through the entries the panel draws its row text from.
local row = { effect = 40, name = 'Protect', domain = 'status', kind = 'buff', scope = 'party', status = 'known',
    entity_id = 1002, entity_name = 'Ally', start = 40, total = 1800, deadline = 1840 };
local function row_priorities()
    local out = {};
    for _, entry in ipairs(hud.entries(row, p, s.style, 100)) do out[entry.id] = entry.priority; end;
    return out;
end
local rows = row_priorities();
assert(type(rows.name) == 'number' and type(rows.time) == 'number', 'Fixture: the row shows its name and countdown.');
assert(rows.time > rows.name, 'Fixture: the row keeps Countdown over Name when space is short.');

assert(shown.name == rows.name and shown.time == rows.time,
    'With no saved priority, the Priority slider shows the priority the rows go by: Name ' .. tostring(rows.name)
    .. ' and Countdown ' .. tostring(rows.time) .. '. It shows Name ' .. tostring(shown.name) .. ' and Countdown '
    .. tostring(shown.time) .. '.');

-- A saved priority is what the rows go by, and the slider shows it, a 0 as well.
p.field_priority.time = 0;
frame();
assert(part_open('Countdown') == true and #slider == 1, 'Fixture: the Priority slider is drawn once for Countdown again.');
assert(row_priorities().time == 0 and slider[1] == 0, 'A saved 0 shows as 0, as the rows go by it: ' .. tostring(slider[1]));
return 'Row text\'s Priority slider shows the priority rows give each part, built in or saved';
