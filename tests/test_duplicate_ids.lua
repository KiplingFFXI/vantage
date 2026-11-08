-- Two controls with one ID share their clicks in the game, so the lower one does nothing. The mock can't show that, so this
-- walks every tab and page of a save with every list filled, in every layout, and looks for an ID drawn twice in one frame.
local h = require('panel_fixture')();
local defaults = require('ui.defaults');

local ITEM = { Checkbox = true, Button = true, SmallButton = true, RadioButton = true, SliderFloat = true, InputText = true, InputTextWithHint = true,
    BeginCombo = true, ColorEdit4 = true, Selectable = true, CollapsingHeader = true, InvisibleButton = true };

-- The ID ImGui hashes: what follows ### alone, else the whole label.
local function id_of(label) return label:match('###(.*)$') or label; end;

-- Each control of the last frame by where it sits; a second one in the same place is a duplicate.
local function duplicates(where)
    local stack, windows, seen = {}, { '' }, {};
    for _, call in ipairs(MOCK.imgui_calls) do
        local name = call[1];
        if name == 'PushID' then stack[#stack + 1] = tostring(call[2]);
        elseif name == 'PopID' then stack[#stack] = nil;
        elseif name == 'BeginChild' then windows[#windows + 1] = tostring(call[2]);
        elseif name == 'EndChild' then windows[#windows] = nil;
        elseif name == 'BeginTable' then stack[#stack + 1] = 'table:' .. tostring(call[2]);
        elseif name == 'EndTable' then stack[#stack] = nil;
        elseif ITEM[name] and type(call[2]) == 'string' then
            local key = table.concat(windows, '>') .. '|' .. table.concat(stack, '/') .. '|' .. id_of(call[2]);
            assert(not seen[key], 'One ID is drawn twice on ' .. where .. ': ' .. key);
            seen[key] = true;
        end;
    end;
end;

-- Every list a page draws row by row, with two rows or more, and names that repeat.
local function rich(s)
    for _, p in pairs(s.panels) do
        p.enabled, p.include, p.exclude, p.pinned = true, { [40] = true, [41] = true }, { [42] = true, [43] = true }, { [40] = true, [44] = true };
        p.order, p.sort, p.labels = { 40, 41, 42 }, 'fixed', { [40] = 'Pro', [41] = 'Shl' };
        p.members, p.bar_style, p.gradient, p.dispel_light = { [2001] = true, [2002] = true, [9999] = true, [9998] = true }, 'rail', true, true;
    end;
    s.watch_ids = { 123, 456, 789 };
    s.party_ui.enabled, s.party_ui.effects.include, s.party_ui.effects.exclude = true, { 40, 41 }, { 42, 43 };
    s.pet.enabled, s.pet.include, s.pet.exclude = true, { 40, 41 }, { 42, 43 };
    for _, kind in pairs(s.overhead.types) do kind.include, kind.exclude = { 40, 41 }, { 42, 43 }; end;
    s.overhead.enabled, s.overhead.head.offsets = true, { Goblin = 1, Orc = 2, ['Big Orc'] = 0.5 };
    s.ready_pulse.enabled, s.ready_pulse.spot, s.ready_pulse.ignore = true, 'screen', { [1] = true, [2] = true, [3] = true };
    s.edit_mode.grid_mode, s.rolls.enabled = true, true;
    s.party_cooldowns.enabled, s.party_cooldowns.list.enabled = true, true;
    s.alerts.rules = { defaults.rule('probe'), defaults.rule('probe'), defaults.rule('probe') };
    s.alerts.rules[1].name, s.alerts.rules[2].name, s.alerts.rules[3].name = 'Same', 'Same', '';
    for index, rule in ipairs(s.alerts.rules) do rule.id = 'r' .. index; end;
    s.effect_filters.rules = { { enabled = true, effect = 40, kind = 'all', name = '', job = 0, scope = 'all' }, { enabled = true, effect = 41, kind = 'all', name = '', job = 0, scope = 'all' },
        { enabled = false, effect = 42, kind = 'all', name = '', job = 0, scope = 'self' }, { enabled = true, effect = 43, kind = 'all', name = 'Aa', job = 0, scope = 'all' } };
end;

local displays = { 'self_buffs', 'self_debuffs', 'target', 'party', 'watch', 'spell_recasts', 'recasts', 'party_ui', 'overhead', 'cooldown_list', 'rolls', 'pet', 'notices', 'hidden' };
local tabs = { 'show', 'place', 'look', 'filters', 'when' };
local frames = 0;
for _, mode in ipairs({ 'bars', 'expanded', 'icons', 'text' }) do
    for _, shape in ipairs({ 'separate', 'combined' }) do
        h.fresh(function(s)
            rich(s);
            for _, p in pairs(s.panels) do p.mode = mode; end;
            s.recast_display = shape;
        end);
        h.view.context.party = { { id = 2001, name = 'Aa' }, { id = 2002, name = 'Aa' } };
        for _, id in ipairs(displays) do
            for _, tab in ipairs(tabs) do
                h.on(id, tab);
                duplicates(mode .. ' ' .. shape .. ' ' .. id .. '/' .. tab);
                frames = frames + 1;
            end;
        end;
        for _, page in ipairs({ 'Home', 'Durations', 'Profiles', 'Help' }) do
            h.s.window.tab = page;
            h.draw(); h.draw();
            duplicates(mode .. ' ' .. shape .. ' ' .. page);
            frames = frames + 1;
        end;
    end;
end;
assert(frames > 580, 'Fixture: the walk reached every page: ' .. frames);

-- The list with the most rows on it, one Remove each, and the second list's Remove works on its own.
h.fresh(rich);
h.on('self_buffs', 'filters');
local removes = 0;
for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Button' and call[2] == 'Remove##effect' then removes = removes + 1; end; end;
assert(removes >= 6, 'Fixture: several lists are filled: ' .. removes);
return 'No page draws one ID twice, however full its lists are';
