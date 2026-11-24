-- The display editors load one a frame while the settings window is open, from the frame after it first draws, in the
-- order Display lists them. The first visit to Display then finds them all loaded, with the list in the same order as
-- when that visit loads them all at once. A shut window loads none.
local h = require('panel_fixture')();
local FILES = { 'status_panel', 'recast_panel', 'party_settings', 'overhead_settings', 'cooldown_settings', 'roll_settings',
    'pet_settings', 'alert_panel', 'filter_settings', 'pulse_settings' };
-- The displays as the first visit to Display lists them when it loads them all in one frame.
local ORDER = 'self_buffs self_debuffs target party watch recasts party_ui overhead cooldown_list rolls pet notices hidden pulse';

local function loaded()
    local list = {};
    for _, name in ipairs(FILES) do if package.loaded['ui.' .. name] then list[#list + 1] = name; end; end;
    return list;
end;
local function listed()
    local ids = {};
    for _, display in ipairs(h.panels._displays) do ids[#ids + 1] = display.id; end;
    return table.concat(ids, ' ');
end;

assert(#loaded() == 0, 'Fixture: no display editor is loaded yet.');
h.fresh();
for _ = 1, 3 do h.window.draw(h.s, h.view, h.app.callbacks); end;
assert(not h.s.window.open and #loaded() == 0, 'A shut window loads no display editor.');

h.draw();
assert(h.s.window.tab == 'Home' and #loaded() == 0, 'The frame the window first draws loads none.');
for frame = 1, #FILES do
    h.draw();
    local now = loaded();
    assert(#now == frame and now[frame] == FILES[frame], ('Frame %d after the first loads %s, and only the ones before it: %s')
        :format(frame, FILES[frame], table.concat(now, ' ')));
end;
assert(h.s.window.tab == 'Home', 'Fixture: the window stayed on Home.');
h.draw(); h.draw();
assert(#loaded() == #FILES, 'Once they are all loaded nothing more happens.');

-- The first visit to Display loads nothing, and lists the displays in the usual order.
local requires, original = {}, require;
require = function(name)
    if not package.loaded[name] then requires[#requires + 1] = name; end;
    return original(name);
end;
h.panels.open('self_buffs', 'show');
h.s.window.tab = 'Display';
h.draw();
require = original;
local editors = {};
for _, name in ipairs(requires) do
    for _, file in ipairs(FILES) do if name == 'ui.' .. file then editors[#editors + 1] = name; end; end;
end;
assert(#editors == 0, 'The first visit to Display loads no display editor: ' .. table.concat(editors, ' '));
assert(listed() == ORDER, 'The displays are listed in the usual order: ' .. listed());
assert(h.called('Checkbox', 'On##frame_display'), 'Fixture: Self buffs\' page draws.');
MOCK.fire('unload');
return 'The display editors load while the window is open';
