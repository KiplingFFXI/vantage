-- A visit to Display while the display editors are still loading one a frame loads the rest at once, and the displays
-- are listed in the same order as when that visit loads them all.
local h = require('panel_fixture')();
local FILES = { 'status_panel', 'recast_panel', 'party_settings', 'overhead_settings', 'cooldown_settings', 'roll_settings',
    'pet_settings', 'alert_panel', 'filter_settings', 'pulse_settings' };
local ORDER = 'self_buffs self_debuffs target party watch recasts party_ui overhead cooldown_list rolls pet notices hidden pulse';

local function count()
    local total = 0;
    for _, name in ipairs(FILES) do if package.loaded['ui.' .. name] then total = total + 1; end; end;
    return total;
end;

h.fresh();
for _ = 1, 4 do h.draw(); end;
local midway = count();
assert(midway > 0 and midway < #FILES, 'Fixture: the window is midway through loading them: ' .. midway);
h.on('overhead', 'show');
assert(count() == #FILES, 'Opening a display loads the rest.');
local ids = {};
for _, display in ipairs(h.panels._displays) do ids[#ids + 1] = display.id; end;
assert(table.concat(ids, ' ') == ORDER, 'The displays are listed in the usual order: ' .. table.concat(ids, ' '));
assert(h.called('Checkbox', 'On##frame_display'), 'Fixture: Overhead icons\' page draws.');
h.draw(); h.draw();
MOCK.fire('unload');
return 'A visit to Display midway through loading';
