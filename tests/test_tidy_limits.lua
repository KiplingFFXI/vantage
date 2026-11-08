-- Settings tidy (ui/defaults.lua, core/effect_filters.lua), as a load, an import or an undo runs it. A panel's lists and
-- maps keep 256 ids at most and an alert rule 16 thresholds, whatever a hand edit or an import holds. An effect id of
-- one of Copy Image's icons, 444, 445 or 446, reads as 66, the effect every copy is tracked as, in a timer panel's
-- lists, labels and colors, a status alert rule, a hide rule, the party list's and overhead icons' lists and an effect
-- duration override; a recast panel's and a recast rule's ids are recasts and stay, as does a spell override's. A
-- blank alert rule name reads as Alert.
local defaults, filters = require('ui.defaults'), require('core.effect_filters');
local equal = require('core.customization').equal;
local function count(map) local n = 0; for _ in pairs(map) do n = n + 1; end; return n; end;
local function keys(map)
    local out = {};
    for key in pairs(map) do out[#out + 1] = key; end
    table.sort(out);
    return out;
end;

do -- Section: how many ids a panel's lists and maps keep.
    local s = defaults.make();
    local p = s.panels.self_buffs;
    local list, map, labels, colors, members = {}, {}, {}, {}, {};
    for id = 2000, 1001, -1 do
        list[#list + 1], map[id], labels[id], colors[id] = id, true, 'Label ' .. id, { 1, 0, 0, 1 };
        members[3000000000 + id] = true;
    end
    p.include, p.exclude, p.pinned, p.order, p.labels, p.effect_colors, p.members = map, list, map, list, labels, colors, members;
    local t = defaults.tidy(s).panels.self_buffs;
    for _, field in ipairs({ 'include', 'exclude', 'pinned', 'labels', 'effect_colors' }) do
        local kept = keys(t[field]);
        assert(#kept == 256 and kept[1] == 1001 and kept[256] == 1256, field .. ' keeps the lowest 256 ids: ' .. #kept);
    end
    assert(t.labels[1001] == 'Label 1001' and equal(t.effect_colors[1256], { 1, 0, 0, 1 }), 'with their values.');
    assert(#t.order == 256 and t.order[1] == 2000 and t.order[256] == 1745, 'The order keeps its first 256: ' .. #t.order);
    local kept = keys(t.members);
    assert(#kept == 256 and kept[1] == 3000001001, 'The members kept are the lowest 256: ' .. #kept);

    -- At the limit, nothing is lost.
    s = defaults.make();
    list = {};
    for id = 1, 256 do list[id] = 1000 + id; end
    s.panels.self_buffs.order, s.panels.self_buffs.exclude = list, list;
    t = defaults.tidy(s).panels.self_buffs;
    assert(#t.order == 256 and count(t.exclude) == 256, 'A list of 256 keeps them all.');
end; -- end of section

do -- Section: how many thresholds a rule keeps.
    local s = defaults.make();
    local rule = defaults.rule('rule_1');
    rule.thresholds = {};
    for index = 1, 40 do rule.thresholds[index] = index * 10; end
    s.alerts.rules = { rule };
    local thresholds = defaults.tidy(s).alerts.rules[1].thresholds;
    assert(#thresholds == 16 and thresholds[1] == 160 and thresholds[16] == 10, 'A rule keeps its first 16 thresholds, longest first: ' .. #thresholds);
    rule.thresholds = { 5, 60, 30 };
    assert(table.concat(defaults.tidy(s).alerts.rules[1].thresholds, ' ') == '60 30 5', 'A few stay as they were.');
end; -- end of section

do -- Section: Copy Image's icons read as 66.
    local s = defaults.make();
    local p = s.panels.self_buffs;
    p.include, p.exclude, p.pinned = { [445] = true, [33] = true }, { 444 }, { [446] = true };
    p.order = { 445, 33, 66, 444 };
    p.labels, p.effect_colors = { [445] = 'Shadows', [33] = 'Haste' }, { [446] = { 0, 1, 0, 1 } };
    -- Where 66 has a label or color of its own, it keeps it.
    local q = s.panels.self_debuffs;
    q.labels, q.effect_colors = { [66] = 'Copy Image', [444] = 'Icon' }, { [444] = { 0, 0, 1, 1 }, [66] = { 1, 0, 0, 1 } };
    -- A recast panel's ids are recasts.
    local r = s.panels.ability_recasts;
    r.include, r.order, r.labels = { [445] = true }, { 444 }, { [446] = 'Recast' };
    local status, recast = defaults.rule('rule_1'), defaults.rule('rule_2');
    status.effect = 445;
    recast.domain, recast.event, recast.effect = 'recast', 'ready', 445;
    s.alerts.rules = { status, recast };
    s.effect_filters.rules = { { enabled = true, effect = 446, kind = 'all', name = '', job = 0, scope = 'all' } };
    local t = defaults.tidy(s);
    p = t.panels.self_buffs;
    assert(p.include[66] and p.include[33] and count(p.include) == 2, 'Show only takes 66 for an icon.');
    assert(p.exclude[66] and count(p.exclude) == 1 and p.pinned[66] and count(p.pinned) == 1, 'So do Hide and pinned.');
    assert(table.concat(p.order, ' ') == '66 33', 'The order has 66 once, where the first of them was: ' .. table.concat(p.order, ' '));
    assert(p.labels[66] == 'Shadows' and p.labels[33] == 'Haste' and count(p.labels) == 2, 'A label for an icon is 66\'s.');
    assert(equal(p.effect_colors[66], { 0, 1, 0, 1 }) and count(p.effect_colors) == 1, 'So is a color.');
    q = t.panels.self_debuffs;
    assert(q.labels[66] == 'Copy Image' and count(q.labels) == 1, '66\'s own label wins over an icon\'s.');
    assert(equal(q.effect_colors[66], { 1, 0, 0, 1 }) and count(q.effect_colors) == 1, 'and its own color.');
    r = t.panels.ability_recasts;
    assert(r.include[445] and r.order[1] == 444 and r.labels[446] == 'Recast', 'A recast panel keeps its ids.');
    assert(t.alerts.rules[1].effect == 66, 'A status alert rule for an icon is for 66.');
    assert(t.alerts.rules[2].effect == 445, 'A recast rule keeps its id.');
    assert(t.effect_filters.rules[1].effect == 66, 'A hide rule for an icon is for 66.');
    assert(filters.tidy({ rules = { { effect = 444 } } }).rules[1].effect == 66, 'when the hide rules are tidied alone too.');
end; -- end of section

do -- Section: a blank alert rule name reads as Alert.
    local s = defaults.make();
    local blank, spaces, marks, named = defaults.rule('rule_1'), defaults.rule('rule_2'), defaults.rule('rule_3'), defaults.rule('rule_4');
    blank.name, spaces.name, marks.name, named.name = '', '   ', '##', 'Haste';
    s.alerts.rules = { blank, spaces, marks, named };
    local rules = defaults.tidy(s).alerts.rules;
    assert(rules[1].name == 'Alert' and rules[2].name == 'Alert' and rules[3].name == 'Alert', 'A name with nothing to show is Alert.');
    assert(rules[4].name == 'Haste', 'A name stays.');
end; -- end of section

do -- Section: the party list, the overhead icons and the duration overrides read Copy Image's icons as 66 too.
    local s = defaults.make();
    s.party_ui.effects.include = { 445, 66, 444, 33 };
    s.overhead.types.mob.exclude = { [446] = true };
    s.durations.overrides = { { kind = 'effect', id = 445 }, { kind = 'spell', id = 445 } };
    local t = defaults.tidy(s);
    assert(equal(t.party_ui.effects.include, { 66, 33 }), 'The party list keeps one 66, where the first icon was.');
    assert(equal(t.overhead.types.mob.exclude, { 66 }), 'An overhead list holds 66 for an icon.');
    assert(t.durations.overrides[1].id == 66 and t.durations.overrides[2].id == 445,
        'An effect override for an icon is for 66; a spell override keeps its id.');
end; -- end of section
