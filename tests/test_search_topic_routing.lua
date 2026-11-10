-- A search topic about a tab or a row that names no display (ui/search_index.lua) opens the display open now when it has
-- that tab or row, and otherwise the first that does, never one without it (ui/panel_frame.lua frame.route). The topics
-- about a panel go to a timer or recast panel.
local store = require('core.store');
local SNAP = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, level = 75, self_known = true, self_effects = {},
    party = {}, entities = { [1001] = { id = 1001, index = 0x400, name = 'Tester', kind = 'player' } } };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(SNAP); end, accept = function() end,
    packet_size = function(e) return e.size or 0; end };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window, frame = require('ui.settings_window'), require('ui.panel_frame');

local function topic(query, label)
    for _, result in ipairs(window.search(query)) do
        if result.tab == 'Display' and result.label == label then return result; end
    end
end
assert(topic('fallback', 'What a display moves with').destination == 'Moves with', 'What a display moves with goes to the row.');
assert(topic('dynamis', 'When each display shows').destination == 'when', 'When each display shows goes to the tab.');
for _, label in ipairs({ 'What a panel moves with', 'Panel placement, locking and size' }) do
    local result = topic('attach', label) or topic('unlock', label);
    assert(result and result.timers == true, label .. ' goes to a timer or recast panel.');
end

frame.open('self_buffs');
local displays = frame._displays;
local function by(id) for _, display in ipairs(displays) do if display.id == id then return display; end end end
local function has(display, destination)
    if display.plain then return false; end
    if destination == 'when' then return display.tabs.when ~= nil; end
    return display.named[destination] ~= nil;
end
local lacking = 0;
for _, destination in ipairs({ 'Moves with', 'when' }) do
    for _, from in ipairs(displays) do
        frame.open(from.id);
        assert(frame.opened() == from.id, 'Fixture: ' .. from.id .. ' opens.');
        frame.route('Display', nil, destination);
        local to = by(frame.opened());
        assert(to and has(to, destination), 'From ' .. from.id .. ', ' .. destination .. ' opens a display that has it: ' .. tostring(frame.opened()));
        if has(from, destination) then
            assert(to == from, 'From ' .. from.id .. ', which has ' .. destination .. ', it stays there.');
        else lacking = lacking + 1; end
    end
end
assert(lacking > 0, 'Fixture: a display lacks one of them.');
