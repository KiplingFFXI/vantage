-- Import and add (core/share.lua) takes every setting you never changed, a spot as one setting. Party list's three
-- groups are a list, and Add judges each group's spot and other settings on their own, as profiles do
-- (core/profiles.lua by_group).
local share, defaults, store = require('core.share'), require('ui.defaults'), require('core.store');
local exporter = defaults.tidy(defaults.make());
exporter.party_ui.groups[1].native_x, exporter.party_ui.groups[1].native_y = 5, 6;
exporter.party_ui.groups[2].native_x, exporter.party_ui.groups[2].native_y = 30, -40;
exporter.party_ui.groups[2].order = { 5, 4, 3, 2, 1, 0 };
exporter.party_ui.groups[3].detached_x, exporter.party_ui.groups[3].detached_y = 700, 500;
exporter.party_ui.groups[3].native_side = 'right';
local mine = defaults.tidy(defaults.make());
mine.party_ui.groups[1].native_x = 12;
mine.party_ui.groups[3].order = { 1, 0, 2, 3, 4, 5 };
local fresh = defaults.make().party_ui.groups;
assert(mine.party_ui.groups[2].native_x == fresh[2].native_x and mine.party_ui.groups[3].detached_x == fresh[3].detached_x,
    'Fixture: Alliance 1 and Alliance 2 are where they started.');
-- A layout export holds no group's order, so for it only the spots and sides are judged.
for _, kind in ipairs({ 'element', 'profile', 'layout' }) do
    local payload = assert(share.read(assert(share.export(exporter, kind, kind == 'element' and 'party_ui' or nil, 'Moonfall'))));
    local groups = assert(share.candidate(store.copy(mine), payload, 'add')).party_ui.groups;
    assert(groups[1].native_x == 12 and groups[1].native_y == 0, kind .. ': your own move of Your party stays, both its numbers: '
        .. groups[1].native_x .. ',' .. groups[1].native_y);
    assert(groups[2].native_x == 30 and groups[2].native_y == -40, kind .. ': Add takes the export\'s spot for Alliance 1, which you'
        .. ' never moved, but it is at ' .. groups[2].native_x .. ',' .. groups[2].native_y);
    if kind ~= 'layout' then
        assert(table.concat(groups[2].order, ',') == '5,4,3,2,1,0', kind .. ': Add takes Alliance 1\'s order: ' .. table.concat(groups[2].order, ','));
    end;
    assert(groups[3].detached_x == 700 and groups[3].detached_y == 500 and groups[3].native_side == 'right',
        kind .. ': Add takes Alliance 2\'s own spot and side.');
    assert(table.concat(groups[3].order, ',') == '1,0,2,3,4,5', kind .. ': your own order for Alliance 2 stays.');
end;

-- Party list's Gap, width and icon size beside the game's list and which way its icons fill are each a setting of their
-- own too. One you changed stays, and the groups you never moved still take the export's spots.
local wider = store.copy(exporter);
wider.party_ui.native.width, wider.party_ui.native.gap = 500, 40;
for _, change in ipairs({ 'gap', 'icon_size', 'growth' }) do
    local yours = defaults.tidy(defaults.make());
    if change == 'growth' then yours.party_ui.effects.growth = 'left'; else yours.party_ui.native[change] = 30; end;
    for _, kind in ipairs({ 'element', 'profile', 'layout' }) do
        local payload = assert(share.read(assert(share.export(wider, kind, kind == 'element' and 'party_ui' or nil, 'Moonfall'))));
        local party = assert(share.candidate(store.copy(yours), payload, 'add')).party_ui;
        local groups = party.groups;
        local said = kind .. ' with your ' .. change .. ' changed: ';
        assert(groups[2].native_x == 30 and groups[2].native_y == -40 and groups[3].detached_x == 700 and groups[3].detached_y == 500,
            said .. 'the groups you never moved take the export\'s spots, but Alliance 1 is at ' .. groups[2].native_x .. ','
            .. groups[2].native_y .. ' and Alliance 2 at ' .. groups[3].detached_x .. ',' .. groups[3].detached_y);
        assert(party.native.width == 500, said .. 'Add takes the export\'s width, which you never changed: ' .. party.native.width);
        if change == 'growth' then assert(party.effects.growth == 'left' and party.native.gap == 40, said .. 'your own fill stays.');
        else assert(party.native[change] == 30, said .. 'your own setting stays: ' .. party.native[change]); end;
    end;
end;
