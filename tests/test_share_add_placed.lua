-- Import and add (core/share.lua) takes what an export holds wherever yours is still as a fresh install has it, and
-- leaves what you changed. A value read back from the saved file counts as the one written, so after a reload a color
-- you never changed still takes the export's. Where a fresh install's first frame put a display counts as fresh too,
-- so one the first frame moved clear of the chat log still takes the export's place.
local share, defaults, store, json = require('core.share'), require('ui.defaults'), require('core.store'), require('core.json');
local setup = require('ui.setup_defaults');
local equal = require('core.customization').equal;
local function fresh() return defaults.tidy(defaults.make()); end;
-- Settings as a reload reads them back from the saved file.
local function reloaded(settings) return defaults.tidy(json.decode(store.encode(settings))); end;
local function export(settings, kind, id)
    local text, why = share.export(settings, kind, id, 'Tester');
    assert(text, 'Fixture: ' .. kind .. ' exports: ' .. tostring(why));
    return assert(share.read(text));
end;

do -- Section: after a reload, a color you never changed takes the export's.
    local yours, start = reloaded(fresh()), defaults.make();
    local colors = {};
    for key, value in pairs(yours.style) do
        if type(value) == 'table' and #value == 4 and not equal(value, start.style[key]) then colors[#colors + 1] = key; end
    end
    table.sort(colors);
    assert(#colors > 0, 'Fixture: a color read back from the saved file is not the fresh one to the last bit.');
    local theirs = fresh();
    for _, key in ipairs(colors) do theirs.style[key] = { 0.25, 0.5, 0.75, 1 }; end
    local candidate = assert(share.candidate(yours, export(theirs, 'profile'), 'add'));
    for _, key in ipairs(colors) do
        assert(equal(candidate.style[key], { 0.25, 0.5, 0.75, 1 }), 'Add takes the export\'s ' .. key .. ' for one you never changed.');
    end
    yours.style[colors[1]] = { 0.1, 0.2, 0.3, 1 };
    candidate = assert(share.candidate(yours, export(theirs, 'profile'), 'add'));
    assert(equal(candidate.style[colors[1]], { 0.1, 0.2, 0.3, 1 }), 'and keeps one you changed.');

    -- An alert rule with a color picked this session is the same rule as the one an export of it reads back.
    local mine = fresh();
    local rule = defaults.rule('rule_1');
    rule.name, rule.flash_color = 'Haste', { 1 / 3, 2 / 3, 1 / 7, 1 };
    mine.alerts.rules = { rule };
    mine = defaults.tidy(mine);
    local added = assert(share.candidate(mine, export(mine, 'alerts'), 'add'));
    assert(#added.alerts.rules == 1, 'Adding your own alert rules again adds none: ' .. #added.alerts.rules);
end; -- end of section

do -- Section: a display still where the first frame put it takes the export's place.
    for _, screen in ipairs({ { width = 1280, height = 720 }, { width = 1920, height = 1080 } }) do
        local on = screen.width .. 'x' .. screen.height;
        local yours = fresh();
        setup.place_fresh(yours, screen);
        yours = reloaded(yours);
        local start, moved = defaults.make(), {};
        for _, id in ipairs(defaults.panel_order) do
            if yours.panels[id].x ~= start.panels[id].x or yours.panels[id].y ~= start.panels[id].y then moved[#moved + 1] = id; end
        end
        assert(#moved > 0, 'Fixture: the first frame moved a panel on ' .. on);
        -- One you placed yourself.
        yours.panels.self_buffs.x, yours.panels.self_buffs.y = 222, 333;
        local theirs = fresh();
        for index, id in ipairs(defaults.panel_order) do theirs.panels[id].x, theirs.panels[id].y = 10 * index, 500 + index; end
        theirs.alerts.notice_x, theirs.alerts.notice_y = 15, 25;
        theirs.pet.x, theirs.pet.y = 35, 45;
        theirs.rolls.x, theirs.rolls.y = 55, 65;
        for _, kind in ipairs({ 'layout', 'profile' }) do
            local candidate = assert(share.candidate(yours, export(theirs, kind), 'add'));
            for index, id in ipairs(defaults.panel_order) do
                local panel = candidate.panels[id];
                if id == 'self_buffs' then
                    assert(panel.x == 222 and panel.y == 333, kind .. ' on ' .. on .. ': the panel you placed stays.');
                else
                    assert(panel.x == 10 * index and panel.y == 500 + index, kind .. ' on ' .. on .. ': ' .. id .. ' takes the export\'s place.');
                end
            end
            assert(candidate.alerts.notice_x == 15 and candidate.alerts.notice_y == 25, kind .. ' on ' .. on .. ': so do the alert notices.');
            assert(candidate.pet.x == 35 and candidate.pet.y == 45 and candidate.rolls.x == 55 and candidate.rolls.y == 65,
                kind .. ' on ' .. on .. ': and the Pet and Phantom Roll displays.');
        end
        -- One display at a time, the same.
        for _, id in ipairs(moved) do
            local candidate = assert(share.candidate(yours, export(theirs, 'element', id), 'add'));
            assert(candidate.panels[id].x == theirs.panels[id].x and candidate.panels[id].y == theirs.panels[id].y,
                'One display on ' .. on .. ': ' .. id .. ' takes the export\'s place.');
        end
        local candidate = assert(share.candidate(yours, export(theirs, 'element', 'self_buffs'), 'add'));
        assert(candidate.panels.self_buffs.x == 222, 'One display on ' .. on .. ': the panel you placed stays.');
    end
end; -- end of section

do -- Section: a spot goes in whole. A display you moved only across keeps both its numbers, and so does its anchor.
    local yours, theirs = fresh(), fresh();
    local start = defaults.make();
    yours.panels.self_buffs.x = start.panels.self_buffs.x + 40;
    yours.rolls.y = start.rolls.y + 30;
    yours.panels.self_debuffs.anchor.to, yours.panels.self_debuffs.anchor.point = 'screen', 'top_right';
    theirs.panels.self_buffs.x, theirs.panels.self_buffs.y = 111, 222;
    theirs.rolls.x, theirs.rolls.y = 333, 444;
    theirs.panels.self_debuffs.anchor.to, theirs.panels.self_debuffs.anchor.side = 'chat', 'above';
    theirs.panels.self_debuffs.anchor.dx, theirs.panels.self_debuffs.anchor.gap = 7, 9;
    for _, kind in ipairs({ 'profile', 'element' }) do
        local candidate = assert(share.candidate(yours, export(theirs, kind, kind == 'element' and 'self_buffs' or nil), 'add'));
        local panel = candidate.panels.self_buffs;
        assert(panel.x == start.panels.self_buffs.x + 40 and panel.y == start.panels.self_buffs.y,
            kind .. ': a display you moved across keeps your spot, never your x and their y: ' .. panel.x .. ', ' .. panel.y);
    end
    local candidate = assert(share.candidate(yours, export(theirs, 'profile'), 'add'));
    assert(candidate.rolls.x == start.rolls.x and candidate.rolls.y == start.rolls.y + 30, 'and one you moved down.');
    local anchor = candidate.panels.self_debuffs.anchor;
    assert(anchor.to == 'screen' and anchor.point == 'top_right' and anchor.dx == 0 and anchor.gap == start.panels.self_debuffs.anchor.gap,
        'An anchor you changed stays whole: ' .. tostring(anchor.to) .. ' ' .. tostring(anchor.dx) .. ' ' .. tostring(anchor.gap));
    yours.panels.self_buffs.x = start.panels.self_buffs.x;
    candidate = assert(share.candidate(yours, export(theirs, 'element', 'self_buffs'), 'add'));
    assert(candidate.panels.self_buffs.x == 111 and candidate.panels.self_buffs.y == 222, 'One you never moved takes their spot whole.');
end; -- end of section

do -- Section: a display's size and the way it fills are settings of their own, apart from its spot, in a layout too.
    for _, change in ipairs({ 'width', 'fills' }) do
        local yours, theirs = fresh(), fresh();
        if change == 'width' then
            yours.panels.target.width, yours.rolls.width, yours.pet.width = 420, yours.rolls.width + 50, yours.pet.width + 50;
            yours.alerts.notice_width, yours.party_cooldowns.list.width, yours.ready_pulse.size = 600, yours.party_cooldowns.list.width + 50, 96;
        else yours.panels.target.stack_direction, yours.panels.target.growth = 'vertical', 'left'; end;
        theirs.panels.target.x, theirs.panels.target.y = 900, 600;
        theirs.rolls.x, theirs.rolls.y, theirs.pet.x, theirs.pet.y = 55, 65, 35, 45;
        theirs.alerts.notice_x, theirs.alerts.notice_y = 15, 25;
        theirs.party_cooldowns.list.x, theirs.party_cooldowns.list.y = 75, 85;
        theirs.ready_pulse.spot, theirs.ready_pulse.x, theirs.ready_pulse.y = 'screen', 95, 105;
        for _, kind in ipairs({ 'profile', 'layout' }) do
            local candidate = assert(share.candidate(yours, export(theirs, kind), 'add'));
            local said = kind .. ' with your ' .. change .. ' changed: ';
            local panel = candidate.panels.target;
            assert(panel.x == 900 and panel.y == 600, said .. 'Target timers takes the export\'s spot: ' .. panel.x .. ',' .. panel.y);
            assert(panel.width == yours.panels.target.width and panel.stack_direction == yours.panels.target.stack_direction
                and panel.growth == yours.panels.target.growth, said .. 'and keeps your own size and fill.');
            assert(candidate.rolls.x == 55 and candidate.rolls.y == 65 and candidate.rolls.width == yours.rolls.width,
                said .. 'so does Phantom Roll: ' .. candidate.rolls.x .. ',' .. candidate.rolls.y);
            assert(candidate.pet.x == 35 and candidate.pet.y == 45 and candidate.pet.width == yours.pet.width,
                said .. 'and Pet: ' .. candidate.pet.x .. ',' .. candidate.pet.y);
            assert(candidate.alerts.notice_x == 15 and candidate.alerts.notice_y == 25 and candidate.alerts.notice_width == yours.alerts.notice_width,
                said .. 'and the alert notices: ' .. candidate.alerts.notice_x .. ',' .. candidate.alerts.notice_y);
            local list = candidate.party_cooldowns.list;
            assert(list.x == 75 and list.y == 85 and list.width == yours.party_cooldowns.list.width,
                said .. 'and the party cooldown list: ' .. list.x .. ',' .. list.y);
            local pulse = candidate.ready_pulse;
            assert(pulse.spot == 'screen' and pulse.x == 95 and pulse.y == 105 and pulse.size == yours.ready_pulse.size,
                said .. 'and the ready pulse: ' .. pulse.spot .. ' ' .. pulse.x .. ',' .. pulse.y);
        end;
    end;
end; -- end of section

do -- Section: the alert notices keep their anchor as notice_anchor, and it goes in whole too.
    local function spot(anchor)
        return table.concat({ anchor.to, anchor.point, anchor.dx, anchor.dy, anchor.side, anchor.align, anchor.gap, anchor.offset }, ' ');
    end;
    assert(spot(defaults.make().alerts.notice_anchor) == 'none top_left 0 0 below start 4 0', 'Fixture: the notices start with no anchor.');
    local theirs = fresh();
    local anchor = theirs.alerts.notice_anchor;
    anchor.to, anchor.side, anchor.align, anchor.gap, anchor.offset = 'party', 'left', 'end', 12, 30;
    -- Moves with: The chat log turns Side to Above. One who then set Side back to Below has only to changed.
    for _, side in ipairs({ 'above', 'below' }) do
        local yours = fresh();
        yours.alerts.notice_anchor.to, yours.alerts.notice_anchor.side = 'chat', side;
        for _, kind in ipairs({ 'element', 'profile', 'layout' }) do
            local got = assert(share.candidate(yours, export(theirs, kind, kind == 'element' and 'notices' or nil), 'add')).alerts.notice_anchor;
            assert(spot(got) == 'chat top_left 0 0 ' .. side .. ' start 4 0',
                kind .. ': an anchor you changed for the notices stays whole, never mixed with theirs: ' .. spot(got));
        end;
    end;
    for _, kind in ipairs({ 'element', 'profile', 'layout' }) do
        local got = assert(share.candidate(fresh(), export(theirs, kind, kind == 'element' and 'notices' or nil), 'add')).alerts.notice_anchor;
        assert(spot(got) == 'party top_left 0 0 left end 12 30', kind .. ': notices you never anchored take theirs whole: ' .. spot(got));
    end;
end; -- end of section
