-- Fills is one pick for the two keys the panels fill by: which way the rows stack and which way they grow. Each of its four
-- choices writes its own pair and only that pair, a saved pair shows as its choice, and there is no choice for going up.
local h = require('panel_fixture')();
local store, custom = require('core.store'), require('core.customization');
local choices = {
    { 'Down, then to the right', 'down_right', 'vertical', 'right' },
    { 'Down, then to the left', 'down_left', 'vertical', 'left' },
    { 'To the right, then down', 'right_down', 'horizontal', 'right' },
    { 'To the left, then down', 'left_down', 'horizontal', 'left' },
};
local function label(choice) return choice[1] .. '##' .. choice[2]; end;

for _, id in ipairs({ 'self_buffs', 'target', 'watch', 'spell_recasts' }) do
    h.fresh();
    local p = h.s.panels[id];
    h.on(id, 'place');
    assert(p.locked == true, 'Fixture: Fills stays live on a locked panel.');
    -- Every choice is offered, in order, and no other.
    h.combo = '##frame_Fills';
    h.draw();
    h.combo = nil;
    local offered = {};
    for _, call in ipairs(h.calls('Selectable')) do
        if tostring(call[2]):find('^[DT]o?[^#]*, then') then offered[#offered + 1] = call[2]; end;
    end;
    assert(#offered == 4 and offered[1] == label(choices[1]) and offered[2] == label(choices[2]) and offered[3] == label(choices[3])
        and offered[4] == label(choices[4]), 'Four choices, in order, on ' .. id);
    for _, choice in ipairs(choices) do
        p.stack_direction, p.growth = choice[3] == 'vertical' and 'horizontal' or 'vertical', choice[4] == 'right' and 'left' or 'right';
        h.bump();
        h.draw();
        local before = store.copy(p);
        h.pick('##frame_Fills', label(choice));
        p = h.s.panels[id];
        assert(p.stack_direction == choice[3] and p.growth == choice[4], choice[1] .. ' writes ' .. choice[3] .. ', ' .. choice[4] .. ' on ' .. id);
        before.stack_direction, before.growth = p.stack_direction, p.growth;
        assert(custom.equal(before, p), choice[1] .. ' writes those two keys and nothing else.');
        assert(h.previews['##frame_Fills'] == choice[1], 'And shows as it was picked.');
    end;
    -- A saved pair shows as its choice.
    for _, choice in ipairs(choices) do
        p.stack_direction, p.growth = choice[3], choice[4];
        h.bump();
        h.draw();
        assert(h.previews['##frame_Fills'] == choice[1], 'A saved ' .. choice[3] .. ', ' .. choice[4] .. ' reads ' .. choice[1]);
    end;
end;

-- One Undo step, and picking what it already is makes none.
h.fresh();
h.on('self_buffs', 'place');
local p = h.s.panels.self_buffs;
local stack, growth = p.stack_direction, p.growth;
local steps = #h.app.state.history;
h.pick('##frame_Fills', label(choices[stack == 'vertical' and growth == 'right' and 4 or 1]));
assert(#h.app.state.history == steps + 1, 'A pick is one Undo step.');
h.draw('Undo');
h.draw();
assert(h.s.panels.self_buffs.stack_direction == stack and h.s.panels.self_buffs.growth == growth, 'Undo puts both keys back.');
steps = #h.app.state.history;
for _, choice in ipairs(choices) do
    if choice[3] == stack and choice[4] == growth then h.pick('##frame_Fills', label(choice)); end;
end;
assert(#h.app.state.history == steps, 'What it already is makes no Undo step.');
MOCK.fire('unload');
return 'Fills maps its four choices to the stack and growth keys, both ways';
