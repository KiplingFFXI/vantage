-- Show as, Icons show and the recast tints are one for every recast panel, so Reset this tab on a recast panel's Show
-- leaves them as Reset all of this display does, and puts back what the panel holds, such as Sort. On One panel for all
-- the panel stays on the screen.
local h = require('panel_fixture')();
local custom = require('core.customization');
local TINTS = { 'mp', 'spell_lock', 'ability_lock' };

local function setup(mode, id)
    return function(s)
        s.recast_display = mode;
        for _, key in ipairs(TINTS) do s.recast_tints[key], s.recast_tints[key .. '_color'] = true, { 0.1, 0.2, 0.3, 0.4 }; end;
        s.style.recast_icon_source = 'action';
        s.panels[id].enabled, s.panels[id].sort = true, 'name';
    end;
end;
local function said(id)
    local tints = {};
    for _, key in ipairs(TINTS) do
        tints[#tints + 1] = key .. ' ' .. tostring(h.s.recast_tints[key]) .. (custom.equal(h.s.recast_tints[key .. '_color'], { 0.1, 0.2, 0.3, 0.4 }) and ' kept color' or ' color back');
    end;
    return ('Show as %s, tints %s, Icons show %s, sort %s, %s on %s, editing %s'):format(h.s.recast_display, table.concat(tints, ', '),
        h.s.style.recast_icon_source, h.s.panels[id].sort, id, tostring(h.s.panels[id].enabled), h.panels.context());
end;
local function kept()
    for _, key in ipairs(TINTS) do
        if h.s.recast_tints[key] ~= true or not custom.equal(h.s.recast_tints[key .. '_color'], { 0.1, 0.2, 0.3, 0.4 }) then return false; end;
    end;
    return h.s.style.recast_icon_source == 'action';
end;

for _, case in ipairs({ { 'combined', 'recasts' }, { 'separate', 'spell_recasts' } }) do
    local mode, id = case[1], case[2];
    h.fresh(setup(mode, id));
    h.on(id, 'show');
    h.draw('Reset this tab##frame');
    h.draw();
    local now = said(id);
    assert(h.s.panels[id].sort == 'remaining' and h.app.callbacks.history_status().undo_label == 'Reset this tab', 'Fixture: Reset this tab ran: ' .. now);
    assert(h.s.recast_display == mode and kept() and h.s.panels[id].enabled and h.panels.context() == 'recasts/show',
        'Reset this tab on ' .. id .. ' Show changed what every recast panel shares: ' .. now);
end;
MOCK.fire('unload');
return 'Reset this tab on a recast panel\'s Show leaves what every recast panel shares';
