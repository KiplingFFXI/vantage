-- With a display's settings open, a refresh reads the recasts the displays need, and every kind only once a page lists
-- your recasts to pick from.
local h = require('panel_fixture')();
local defaults = require('ui.defaults');
local t = 10;

local function demand(id, tab)
    h.fresh(function(s)
        for key in pairs(defaults.recast_panels) do s.panels[key].enabled = false; end;
        s.ready_pulse.enabled, s.pet.enabled, s.alerts.enabled = false, false, false;
    end);
    if id then h.on(id, tab); end;
    if not id then h.s.window.open = false; end;
    t = t + 1; h.app.state.recast_demand = nil; h.app.refresh(t);
    return h.app.state.recast_demand;
end;

assert(demand() == 'falsefalsefalse', 'Fixture: with the window shut, nothing reads recasts.');
for _, panel in ipairs({ 'self_buffs', 'target', 'party' }) do
    for _, tab in ipairs({ 'show', 'look', 'filters' }) do
        local read = demand(panel, tab);
        assert(read == 'falsefalsefalse', ('%s %s lists no recasts, so none are read: %s'):format(panel, tab, tostring(read)));
    end;
end;
local read = demand('ability_recasts', 'filters');
assert(read == 'truetruetrue', 'A recast display\'s filters list your recasts, so every kind is read: ' .. tostring(read));
read = demand();
assert(read == 'falsefalsefalse', 'Once the window shuts, they stop: ' .. tostring(read));
