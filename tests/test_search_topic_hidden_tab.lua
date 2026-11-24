-- The search topics What a display moves with and When each display shows name no display. Clicked as a player does,
-- typed in the find box and then picked, they open the display open now when it shows that tab, and otherwise the first
-- that does. The ready pulse hides Size and place while it sits on its row and When to show while it is off, and Party
-- cooldowns hides both while its list is off (ui/pulse_settings.lua, ui/cooldown_settings.lua tab_on).
local h = require('panel_fixture')();
local frame = h.panels;

local function moves_drawn()
    for name in pairs(h.drawn()) do if name:find('^Moves with') then return true; end; end;
    return false;
end;

-- Opens from on Show, types query in the find box, clicks the topic, and returns what the player then sees.
local function click_topic(from, change, query, label)
    h.fresh(change);
    h.on(from, 'show');
    assert(frame.context() == from .. '/show', 'Fixture: ' .. from .. ' opens on Show: ' .. frame.context());
    h.typed['##find_settings'] = query;
    h.draw();
    h.draw(label .. '  /  Timers and recasts');
    h.draw(); h.draw();
    return frame.context(), moves_drawn(), h.called('Button', 'When to show##frame_tab');
end;

local MOVES, WHEN = 'What a display moves with', 'When each display shows';
local pulse_on_row = function(s) s.ready_pulse.enabled = true; s.ready_pulse.spot = 'row'; end;
local pulse_own_spot = function(s) s.ready_pulse.enabled = true; s.ready_pulse.spot = 'screen'; end;
local watch_no_list = function(s) s.party_cooldowns.enabled = true; s.party_cooldowns.list.enabled = false; end;
local list_on = function(s) s.party_cooldowns.enabled = true; s.party_cooldowns.list.enabled = true; end;

-- From, how it is set, what it's called, and where each topic lands: the display itself while it shows the tab.
local cases = {
    { 'self_buffs', nil, 'Self buffs', 'self_buffs', 'self_buffs' },
    { 'pulse', nil, 'Ready pulse off', 'self_buffs', 'self_buffs' },
    { 'pulse', pulse_on_row, 'Ready pulse on its row', 'self_buffs', 'pulse' },
    { 'pulse', pulse_own_spot, 'Ready pulse on a spot of its own', 'pulse', 'pulse' },
    { 'cooldown_list', nil, 'Party cooldowns off', 'self_buffs', 'self_buffs' },
    { 'cooldown_list', watch_no_list, 'Party cooldowns on, In a list unticked', 'self_buffs', 'self_buffs' },
    { 'cooldown_list', list_on, 'Party cooldowns on, In a list ticked', 'cooldown_list', 'cooldown_list' },
};

local lines, wrong = {}, 0;
for _, case in ipairs(cases) do
    local from, change, name, moves_to, when_to = case[1], case[2], case[3], case[4], case[5];
    local where, moves = click_topic(from, change, 'moves with', MOVES);
    local ok = moves and where == moves_to .. '/place';
    if not ok then wrong = wrong + 1; end;
    lines[#lines + 1] = ('%s: %s -> %s, Moves with drawn: %s%s'):format(name, MOVES, where, tostring(moves), ok and '' or ' (wrong)');
    local there, _, when_tab = click_topic(from, change, 'when each display shows', WHEN);
    ok = when_tab and there == when_to .. '/when';
    if not ok then wrong = wrong + 1; end;
    lines[#lines + 1] = ('%s: %s -> %s, When to show tab drawn: %s%s'):format(name, WHEN, there, tostring(when_tab), ok and '' or ' (wrong)');
end;
assert(wrong == 0, wrong .. ' topic clicks land where the topic is not shown:\n' .. table.concat(lines, '\n'));

-- Asking each display leaves ctx as it was, as a page can still be drawing with it.
h.fresh();
h.on('pulse', 'show');
local ctx = frame.ctx;
local display, p, id = ctx.display, ctx.p, ctx.id;
frame.route('Display', nil, 'when');
assert(frame.opened() == 'self_buffs', 'Fixture: the route went on to Self buffs: ' .. tostring(frame.opened()));
assert(ctx.display == display and ctx.p == p and ctx.id == id, 'The route left ctx on ' .. tostring(ctx.id) .. ', not ' .. tostring(id));
MOCK.fire('unload');
return 'The display topics land where their tab shows';
