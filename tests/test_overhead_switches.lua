-- Seven switches on each overhead unit type hide a group of effects. Ticked shows, unticked hides, and the include list
-- beats a switch while the other filters still apply. A save keeps the switches it holds, and an export of the whole look
-- or of the overhead icons alone reads back as it was.
local defaults, store = require('ui.defaults'), require('core.store');
local overhead_defaults = require('ui.overhead_defaults');
local overhead, catalog = require('core.overhead'), require('core.catalog');
local entries = require('data.catalog');
local share = require('core.share');
local switches = overhead_defaults.switches;

-- The ids of each group, in the order of the settings.
local function ids(...)
    local out = {};
    for _, value in ipairs({ ... }) do
        if type(value) == 'table' then for id = value[1], value[2] do out[#out + 1] = id; end;
        else out[#out + 1] = value; end;
    end;
    table.sort(out);
    return table.concat(out, ' ');
end;
local groups = {
    { 'show_rolls', 'Corsair rolls', ids({ 310, 327 }, 308) },
    { 'show_songs', 'Bard songs', ids({ 195, 203 }, { 205, 207 }, 209, 210, { 214, 216 }, { 218, 221 }) },
    { 'show_protect_shell', 'Protect and Shell', ids(40, 41) },
    { 'show_food', 'Food', ids(251) },
    { 'show_barspells', 'Barspells', ids({ 100, 112 }) },
    { 'show_stances', 'Stances', ids(353, 354, 61, 57, 56, 58, 63, 64) },
    { 'show_signet', 'Signet and similar', ids(253, 256, 269, 143, 113, 252, 254) },
};
assert(#switches == #groups, 'Seven switches.');
for index, group in ipairs(groups) do
    local switch, sorted = switches[index], {};
    assert(switch.key == group[1] and switch.label == group[2], 'Switch ' .. index .. ': ' .. tostring(switch.key));
    for at, id in ipairs(switch.ids) do
        sorted[at] = id;
        assert(entries[id], group[2] .. ' covers an effect in the catalog: ' .. id);
    end;
    table.sort(sorted);
    assert(table.concat(sorted, ' ') == group[3], group[2] .. ' covers ' .. group[3]);
end;
-- The help names what the catalog calls those ids.
assert(catalog.get(100).name == 'Barfire' and catalog.get(112).name == 'Barvirus' and #switches[5].ids == 13
    and switches[5].help == 'All 13, from Barfire to Barvirus.', 'Barspells help');
assert(catalog.get(308).name == 'Double Up Chance' and #switches[1].ids == 19 and switches[1].help:find('All 18 rolls and Double-Up Chance', 1, true), 'Rolls help');
for _, index in ipairs({ 6, 7 }) do
    for _, id in ipairs(switches[index].ids) do
        assert(switches[index].help:find(catalog.get(id).name, 1, true), switches[index].label .. ' help names ' .. catalog.get(id).name);
    end;
end;
for _, id in ipairs(switches[2].ids) do assert(catalog.get(id).kind == 'buff', 'Every song in the group helps you: ' .. id); end;
for _, spec in ipairs({ { 192, 'Requiem' }, { 194, 'Elegy' }, { 217, 'Threnody' } }) do
    assert(catalog.get(spec[1]).name == spec[2] and catalog.get(spec[1]).kind == 'debuff' and switches[2].help:find(spec[2], 1, true), spec[2] .. ' stays');
end;

-- Every id of a group, on every type: ticked shows, unticked hides, and no other id moves.
local fresh = defaults.make().overhead;
local function row(id, extra)
    local out = { effect = id, kind = catalog.get(id).kind, mine = true };
    for key, value in pairs(extra or {}) do out[key] = value; end;
    return out;
end;
local function open(id)
    local t = store.copy(fresh.types[id]);
    t.kinds, t.buffs_mine_only, t.debuffs_party_only = 'all', false, false;
    for _, switch in ipairs(switches) do t[switch.key] = true; end;
    return t;
end;
for _, kind in ipairs(overhead_defaults.types) do
    for _, switch in ipairs(switches) do
        local t = open(kind);
        for _, id in ipairs(switch.ids) do assert(overhead.keeps(t, row(id)), switch.label .. ' ticked shows ' .. id .. ' on ' .. kind); end;
        t[switch.key] = false;
        for _, id in ipairs(switch.ids) do assert(not overhead.keeps(t, row(id)), switch.label .. ' unticked hides ' .. id .. ' on ' .. kind); end;
        for _, other in ipairs(switches) do
            if other ~= switch then
                for _, id in ipairs(other.ids) do assert(overhead.keeps(t, row(id)), switch.label .. ' leaves ' .. id .. ' alone on ' .. kind); end;
            end;
        end;
    end;
    local t = open(kind);
    for _, switch in ipairs(switches) do t[switch.key] = false; end;
    -- Bust, the debuff songs and everything outside the groups stay.
    for _, id in ipairs({ 309, 192, 194, 217, 33, 42, 43, 4 }) do assert(overhead.keeps(t, row(id)), id .. ' has no switch, on ' .. kind); end;
end;
-- Show only beats a switch, and an exclude or a narrower include still hides what's ticked.
local t = open('party');
t.include, t.show_food = { 33, 251 }, false;
assert(overhead.keeps(t, row(251)) and overhead.keeps(t, row(33)), 'Show only beats Food off.');
t.show_food = true;
assert(overhead.keeps(t, row(251)) and not overhead.keeps(t, row(40)), 'Ticked, the include list decides.');
t = open('party');
t.exclude = { 251 };
assert(not overhead.keeps(t, row(251)), 'Ticked, the exclude list still hides it.');
t = open('party');
t.mine_only = true;
assert(not overhead.keeps(t, row(251, { mine = false })), 'Ticked, Only effects I applied still hides it.');
t = open('party');
t.kinds = 'debuff';
assert(not overhead.keeps(t, row(251)), 'Ticked, Debuffs only still hides a buff.');
-- Level Restriction is a debuff, and with the switches off the page they decide nothing.
assert(overhead.keeps(t, row(143)), 'Debuffs only keeps Level Restriction.');
t.show_signet = false;
assert(overhead.keeps(t, row(143)), 'Debuffs only: a switch that isn\'t listed hides nothing.');

-- A save keeps the switches it holds, and tidying again changes nothing.
local settings = defaults.make();
settings.overhead.types.party.show_food, settings.overhead.types.other.show_rolls = true, false;
settings = defaults.tidy(settings);
assert(settings.overhead.types.party.show_food == true and settings.overhead.types.other.show_rolls == false, 'A save: keys already there stay.');
assert(store.equal(defaults.tidy(store.copy(settings)).overhead, settings.overhead), 'A save tidied again is the same.');
-- A type missing its switches gets its defaults.
local bad = store.copy(fresh);
for _, switch in ipairs(switches) do bad.types.other[switch.key] = nil; end;
overhead_defaults.tidy(bad);
assert(bad.types.other.show_food == false and bad.types.other.show_rolls == true, 'A missing switch reads as the default.');

-- Exports: of the whole look, of the overhead icons alone.
local function string_of(payload)
    local body = store.encode(payload);
    return 'VG:1:' .. share.crc32(body) .. ':' .. body;
end;
local base = defaults.tidy(defaults.make());
local whole = assert(share.read(assert(share.export(base, 'profile', nil, 'Tester'))));
local alone_payload = assert(share.read(assert(share.export(base, 'element', 'overhead', 'Tester'))));
-- A key the string doesn't hold stays out of it.
local partial = store.copy(alone_payload);
partial.data.types.party.show_food, partial.data.types.party.show_rolls = nil, nil;
local read = assert(share.read(string_of(partial)));
assert(read.data.types.party.show_food == nil and read.data.types.party.show_rolls == nil and read.data.types.party.show_signet == false,
    'A string with a switch left out reads without it.');
-- And a whole string reads back unchanged.
assert(store.equal(assert(share.read(string_of(whole))), whole) and store.equal(assert(share.read(string_of(alone_payload))), alone_payload),
    'A string is left as it is.');
