-- Row text's Up and Down on a recast panel move a part past the next one listed. A recast panel doesn't list Who it is on
-- or Who cast it, but they stay in the panel's order, so a move steps over them. A move with nowhere to go changes
-- nothing and makes no Undo step.
local h = require('panel_fixture')();
h.fresh(function(s)
    local p = s.panels.spell_recasts;
    p.enabled, p.show_elapsed = true, true;
    p.field_order = { 'target', 'name', 'elapsed', 'source', 'total', 'time' };
end);
h.on('spell_recasts', 'look');

-- The parts listed, in order.
local function listed()
    local out = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'Selectable' then
            local name = tostring(call[2]):gsub(' %(hidden%)$', '');
            if name == 'Name' or name == 'Time elapsed' or name == 'Full length' or name == 'Countdown' then out[#out + 1] = name; end;
        end;
    end;
    return table.concat(out, ',');
end;
local function order() return table.concat(h.s.panels.spell_recasts.field_order, ','); end;
local function press(part, button)
    h.draw(part);
    h.draw();
    local steps, was = #h.app.state.history, order();
    h.draw(button);
    h.draw();
    return #h.app.state.history - steps, was;
end;

h.draw('Time elapsed');
h.draw();
assert(listed() == 'Name,Time elapsed,Full length,Countdown', 'Fixture: the parts listed: ' .. listed());
assert(h.called('Button', 'Up##part'), 'Fixture: Up shows for the part picked.');

local steps = press('Time elapsed', 'Up##part');
assert(listed() == 'Time elapsed,Name,Full length,Countdown' and steps == 1,
    'Up moves Time elapsed above Name in one Undo step: ' .. listed() .. ' (order ' .. order() .. ', steps ' .. steps .. ')');

local was;
steps, was = press('Time elapsed', 'Up##part');
assert(order() == was and steps == 0, 'Up on the first part listed changes nothing and makes no Undo step: ' .. order() .. ', steps ' .. steps);

steps, was = press('Countdown', 'Down##part');
assert(order() == was and steps == 0, 'Down on the last part listed changes nothing: ' .. order() .. ', steps ' .. steps);

steps = press('Name', 'Down##part');
assert(listed() == 'Time elapsed,Full length,Name,Countdown' and steps == 1,
    'Down moves Name below Full length, past Who cast it: ' .. listed() .. ' (order ' .. order() .. ')');

-- A timer panel lists every part, so Up and Down move one place.
h.fresh(function(s) s.panels.self_buffs.mode, s.panels.self_buffs.wrap = 'bars', true; end);
h.on('self_buffs', 'look');
h.draw('Name');
h.draw();
steps = press('Name', 'Down##part');
assert(h.s.panels.self_buffs.field_order[2] == 'name' and steps == 1, 'On a timer panel Down moves a part one place.');
steps = press('Name', 'Up##part');
assert(h.s.panels.self_buffs.field_order[1] == 'name' and steps == 1, 'And Up moves it back.');
MOCK.fire('unload');
return 'ok';
