-- Who it is on names whose effect each row is. It starts on only for Party members' timers and Watched enemy timers, and
-- a self panel has no tick for it on Show. So Copy this tab to on Look leaves it as each panel has it between Self buffs
-- or Self debuffs and another panel, and carries it between the two self panels and among Target timers, Party members'
-- timers and Watched enemy timers, as it carries the rest of Look.
local h = require('panel_fixture')();
local fields = require('ui.fields');
local COPY = '##frame_Copy this tab to';
local IDS = { 'self_buffs', 'self_debuffs', 'target', 'party', 'watch' };

local function targets()
    local out = {};
    for _, id in ipairs(IDS) do out[#out + 1] = id .. '=' .. tostring(h.s.panels[id].show_target); end;
    return table.concat(out, ' ');
end;
-- What a row on the panel says, part by part.
local function parts(id, row)
    local list = {};
    for _, entry in ipairs(fields.build(row, h.s.panels[id], h.s.style, 0, function(value) return value and tostring(value) or ''; end, '1:00', 'Haste', nil, false)) do
        list[#list + 1] = entry.id .. '=' .. entry.text;
    end;
    return table.concat(list, ', ');
end;
local member = { effect = 33, name = 'Haste', entity_name = 'Member', scope = 'party', status = 'known', deadline = 100 };
local mine = { effect = 33, name = 'Haste', entity_name = 'You', scope = 'self', status = 'known', deadline = 100 };

-- From Self buffs at its first layout, Icons, to every other panel. Target has it on here, so it shows it stays.
h.fresh(function(s) s.panels.self_buffs.colors.fill_start = { 0.2, 0.4, 0.6, 1 }; s.panels.target.show_target = true; end);
local before = parts('party', member);
h.on('self_buffs', 'look');
h.pick(COPY, 'Every other panel##frame_copy_all');
assert(h.s.panels.party.colors.fill_start[1] == 0.2 and h.s.panels.watch.colors.fill_start[1] == 0.2, 'Fixture: the rest of Look came over.');
local after = parts('party', member);
assert(h.s.panels.party.show_target and h.s.panels.watch.show_target and h.s.panels.target.show_target and after == before,
    ('Copy Look from Self buffs to every other panel: a Party members\' timers row read [%s], now [%s]; Who it is on: %s'):format(before, after, targets()));

-- From Party members' timers to every other panel. Self buffs at Bars would name you on every row.
h.fresh(function(s) s.panels.self_buffs.mode, s.panels.party.gradient = 'bars', true; end);
before = parts('self_buffs', mine);
h.on('party', 'look');
h.pick(COPY, 'Every other panel##frame_copy_all');
assert(h.s.panels.self_buffs.gradient and h.s.panels.self_debuffs.gradient, 'Fixture: the rest of Look came over.');
after = parts('self_buffs', mine);
assert(not h.s.panels.self_buffs.show_target and not h.s.panels.self_debuffs.show_target and after == before,
    ('Copy Look from Party members\' timers to every other panel: a Self buffs row read [%s], now [%s]; Who it is on: %s'):format(before, after, targets()));
assert(h.s.panels.target.show_target and h.s.panels.watch.show_target, 'Target timers and Watched enemy timers take it: ' .. targets());

-- Among Target, Party and Watch it carries, off as well as on.
h.fresh(function(s) s.panels.party.show_target = false; end);
h.on('party', 'look');
h.pick(COPY, 'Watched enemy timers##frame_copy_watch');
assert(h.s.panels.watch.show_target == false, 'Party members\' timers with Who it is on off gives that to Watched enemy timers: ' .. targets());
h.fresh();
h.on('target', 'look');
h.pick(COPY, "Party members' timers##frame_copy_party");
assert(h.s.panels.party.show_target == false, 'Target timers gives Party members\' timers its Who it is on: ' .. targets());

-- Between the two self panels the parts still carry, Who it is on with them. Look's Parts of a row can tick it there, and
-- it names you on both.
h.fresh(function(s) s.panels.self_buffs.show_source, s.panels.self_buffs.show_target = true, true; end);
h.on('self_buffs', 'look');
h.pick(COPY, 'Self debuffs##frame_copy_self_debuffs');
assert(h.s.panels.self_debuffs.show_source == true, 'Self debuffs takes Who cast it from Self buffs.');
assert(h.s.panels.self_debuffs.show_target == true, 'Self debuffs takes Who it is on from Self buffs: ' .. targets());
MOCK.fire('unload');
return 'Who it is on stays each panel\'s own between a self panel and the others';
