-- Always show: Copy Image and Third Eye have a tick of their own on Overhead icons and Party list buffs. Ticked shows the
-- effect whoever cast it, whatever Show says. Unticked hides it, unless it's on Show only, where the other filters decide
-- as for any effect. Hide here still hides it, Show only stays an only, and other players and pets, whose would never
-- change, have no tick and treat these effects like any other. Copy Image is one effect, 66, at every count, with the
-- count's icon beside it.
local defaults = require('ui.defaults');
local overhead, layout = require('core.overhead'), require('ui.party_layout');
local page = require('ui.overhead_settings');
-- Copy Image's icons by the shadows left: 66 for one, then 444, 445 and 446.
local ICONS, THIRD_EYE = { 66, 444, 445, 446 }, 67;

local function effect(id, mine, icon)
    return { effect = id, icon = icon ~= id and icon or nil, kind = 'buff', mine = mine, present = true, domain = 'status' };
end;
local function keeps(kind, id, mine, icon) return overhead.keeps(kind, effect(id, mine, icon)) == true; end;

-- How they start: on where they show now, off on party and alliance heads, and no tick where nothing would keep up.
do
    local types = defaults.tidy(defaults.make()).overhead.types;
    for _, id in ipairs({ 'mob', 'self' }) do
        assert(types[id].show_copy_image == true and types[id].show_third_eye == true, id .. ' starts ticked, as it shows them now.');
    end;
    for _, id in ipairs({ 'party', 'alliance' }) do
        assert(types[id].show_copy_image == false and types[id].show_third_eye == false, id .. ' starts unticked, so their heads stay clear.');
    end;
    for _, id in ipairs({ 'other', 'pet', 'other_pet' }) do
        assert(types[id].show_copy_image == nil and types[id].show_third_eye == nil, id .. ' has no tick.');
    end;
end;

-- Overhead icons: ticked beats who cast it and what the unit shows.
do
    local party = defaults.tidy(defaults.make()).overhead.types.party;
    assert(party.buffs_mine_only == true, 'Fixture: Only buffs I cast is on for party members.');
    for _, icon in ipairs(ICONS) do assert(not keeps(party, 66, false, icon), 'Unticked, a party member\'s own Copy Image stays hidden: ' .. icon); end;
    assert(not keeps(party, 66, true), 'Unticked hides it even when you cast it.');
    party.show_copy_image = true;
    for _, icon in ipairs(ICONS) do assert(keeps(party, 66, false, icon), 'Ticked, it shows with Only buffs I cast on, at every count: ' .. icon); end;
    assert(not keeps(party, THIRD_EYE, false), 'Third Eye has its own tick.');
    party.show_third_eye = true;
    assert(keeps(party, THIRD_EYE, false), 'Ticked, Third Eye shows too.');
    party.kinds = 'debuff';
    assert(keeps(party, 66, false) and keeps(party, THIRD_EYE, false), 'Ticked beats Debuffs only.');
    assert(not keeps(party, 33, true), 'Nothing else gets through Debuffs only.');
    party.kinds, party.mine_only = 'all', true;
    assert(keeps(party, 66, false), 'Ticked beats Only effects I cast.');
    party.mine_only = false;

    party.exclude = { 66 };
    for _, icon in ipairs(ICONS) do assert(not keeps(party, 66, false, icon), 'Hide here still hides it, at every count: ' .. icon); end;
    party.exclude, party.include = {}, { 33 };
    assert(not keeps(party, 66, false), 'While Show only has effects, ticked doesn\'t add to them.');
    party.include = { 66 };
    assert(keeps(party, 66, false), 'On Show only and ticked, it shows with Only buffs I cast on.');
    party.show_copy_image, party.buffs_mine_only = false, false;
    assert(keeps(party, 66, false), 'An effect on Show only shows unticked, as with any switch.');
    party.include = {};
    assert(not keeps(party, 66, false), 'Off Show only, unticked hides it whatever else is on.');

    party.show_copy_image = true;
    assert(overhead.keeps(party, { effect = 66, kind = 'buff', present = false }) == false, 'What isn\'t there doesn\'t show.');
    assert(overhead.keeps(party, { effect = 66, kind = 'buff', present = true, domain = 'recast' }) == false, 'A recast row is no effect.');
end;

-- A type with no tick treats them like any other.
do
    local types = defaults.tidy(defaults.make()).overhead.types;
    assert(not keeps(types.other, 66, false) and keeps(types.other, 66, true), 'Other players go by Only buffs I cast.');
    types.other.buffs_mine_only = false;
    assert(keeps(types.other, 66, false), 'With that off they show.');
end;

-- The alliance has the ticks, as Vantage counts their shadows and follows their Third Eye, unticked at first.
do
    local alliance = defaults.tidy(defaults.make()).overhead.types.alliance;
    assert(alliance.kinds == 'debuff' and not keeps(alliance, 66, false), 'Fixture: the alliance starts on Debuffs only.');
    alliance.kinds = 'all';
    assert(not keeps(alliance, 66, false, 445) and not keeps(alliance, THIRD_EYE, false), 'Unticked hides them on Buffs and debuffs too.');
    alliance.kinds, alliance.show_copy_image, alliance.show_third_eye = 'debuff', true, true;
    for _, icon in ipairs(ICONS) do assert(keeps(alliance, 66, false, icon), 'Ticked beats Debuffs only, at every count: ' .. icon); end;
    assert(keeps(alliance, THIRD_EYE, false), 'And Third Eye\'s tick.');
end;

-- A save: values stay, a save from before them takes the start, and a type with no tick can't hold one.
do
    local s = defaults.tidy(defaults.make());
    s.overhead.types.party.show_copy_image, s.overhead.types.mob.show_third_eye = true, false;
    s.overhead.types.other.show_copy_image = true;
    s.party_ui.effects.show_copy_image = false;
    s = defaults.tidy(s);
    assert(s.overhead.types.party.show_copy_image == true and s.overhead.types.mob.show_third_eye == false, 'A save keeps the ticks.');
    assert(s.overhead.types.other.show_copy_image == nil, 'Other players can\'t hold one.');
    assert(s.party_ui.effects.show_copy_image == false, 'A save keeps Party list buffs\' tick.');
    s.overhead.types.party.show_copy_image, s.overhead.types.mob.show_copy_image = nil, nil;
    s.overhead.types.alliance.show_copy_image, s.overhead.types.alliance.show_third_eye = nil, nil;
    s.party_ui.effects.show_copy_image, s.party_ui.effects.show_third_eye = nil, nil;
    s = defaults.tidy(s);
    assert(s.overhead.types.party.show_copy_image == false and s.overhead.types.mob.show_copy_image == true
        and s.overhead.types.alliance.show_copy_image == false and s.overhead.types.alliance.show_third_eye == false,
        'A save from before the ticks takes how they start.');
    assert(s.party_ui.effects.show_copy_image == true and s.party_ui.effects.show_third_eye == true, 'So does Party list buffs.');
end;

-- Party list buffs: the same rule over Show, Hide here and Show only.
do
    local base = defaults.tidy(defaults.make()).party_ui.effects;
    assert(base.show_copy_image == true and base.show_third_eye == true, 'Party list buffs starts ticked, as it shows them now.');
    -- Two copies of Copy Image, at one shadow and at three, each drawn by its icon.
    local list = { { effect = 66, kind = 'buff', key = 'a', present = true }, { effect = 66, icon = 445, kind = 'buff', key = 'b', present = true },
        { effect = 67, kind = 'buff', key = 'c', present = true }, { effect = 33, kind = 'buff', key = 'd', present = true },
        { effect = 4, kind = 'debuff', key = 'e', present = true } };
    local function shown(change)
        local options = require('core.store').copy(base);
        if change then change(options); end;
        local out = {};
        for _, row in ipairs((layout.effects({ effects = list }, options))) do out[#out + 1] = row.icon or row.effect; end;
        table.sort(out);
        return table.concat(out, ' ');
    end;
    assert(shown() == '4 33 66 67 445', 'Buffs and debuffs shows all of it: ' .. shown());
    assert(shown(function(o) o.kind = 'buff'; end) == '33 66 67 445', 'Buffs only is as it was.');
    assert(shown(function(o) o.kind = 'debuff'; end) == '4 66 67 445', 'Ticked beats Debuffs only.');
    assert(shown(function(o) o.kind = 'none'; end) == '', 'None shows no effects, ticked or not.');
    assert(shown(function(o) o.show_copy_image = false; end) == '4 33 67', 'Unticked hides all of Copy Image.');
    assert(shown(function(o) o.show_third_eye = false; end) == '4 33 66 445', 'Unticked hides Third Eye.');
    assert(shown(function(o) o.kind, o.show_third_eye = 'debuff', false; end) == '4 66 445', 'Unticked under Debuffs only.');
    assert(shown(function(o) o.exclude = { 66 }; end) == '4 33 67', 'Hide here still hides it, at every count.');
    assert(shown(function(o) o.include = { 33 }; end) == '33', 'While Show only has effects, ticked doesn\'t add to them.');
    assert(shown(function(o) o.include, o.kind = { 66 }, 'debuff'; end) == '66 445', 'On Show only and ticked, it beats Debuffs only.');
    assert(shown(function(o) o.include, o.show_copy_image = { 66 }, false; end) == '66 445', 'An effect on Show only shows unticked.');
    -- No job ability gives Copy Image, and Third Eye is one.
    assert(shown(function(o) o.abilities_only = true; end) == '66 67 445', 'Ticked beats Only effects from job abilities.');
    assert(shown(function(o) o.abilities_only, o.show_copy_image, o.show_third_eye = true, false, false; end) == '',
        'Unticked hides them with it on too.');

    -- A kept selection follows a tick.
    local holder, subject, options = {}, { effects = list }, require('core.store').copy(base);
    local function count() return #layout.kept_effects(holder, subject, options); end;
    assert(count() == 5, 'All five to start.');
    options.show_copy_image = false;
    assert(count() == 3, 'A kept selection follows the tick.');
    options.show_copy_image = true;
    assert(count() == 5, 'And back.');
    -- And Only effects from job abilities, and what put an effect on.
    options.abilities_only = true;
    assert(count() == 3, 'A kept selection follows Only effects from job abilities.');
    list[4].action_kind = 'abilities';
    assert(count() == 4, 'And what put an effect on.');
    list[4].action_kind, options.abilities_only = nil, false;
    assert(count() == 5, 'And back.');
end;

-- The pages.
do
    local h = require('panel_fixture')();
    local function tick_shown(label) return h.called('Checkbox', label .. '##frame'); end;

    -- Overhead icons: the kinds that have it, under Debuffs only too, and the tick writes to the kind picked.
    h.fresh(function(s) s.overhead.enabled = true; end);
    h.on('overhead', 'filters');
    for kind, has in pairs({ mob = true, party = true, self = true, alliance = true, other = false, pet = false, other_pet = false }) do
        page._selection.kind = kind;
        h.draw();
        assert(h.says('Always show') == has and tick_shown('Copy Image') == has and tick_shown('Third Eye') == has, 'Always show on ' .. kind);
    end;
    page._selection.kind = 'party';
    h.draw();
    assert(h.s.overhead.types.party.show_copy_image == false, 'Fixture: unticked.');
    h.draw('Copy Image##frame');
    assert(h.s.overhead.types.party.show_copy_image == true, 'The tick writes to the kind picked.');
    assert(h.s.overhead.types.mob.show_copy_image == true and h.s.overhead.types.self.show_third_eye == true, 'The others stay.');
    h.s.overhead.types.party.kinds = 'debuff';
    h.bump();
    h.draw();
    assert(not h.says('Show these effects:'), 'Fixture: the switches go under Debuffs only.');
    assert(h.says('Always show') and tick_shown('Copy Image'), 'Always show stays, as it still works there.');

    -- A tick puts buffs on a kind on Debuffs only, so the rows for them stay, and with both unticked they go.
    local function buff_rows(layout, swap)
        return h.called('SliderFloat', '##frame_Buffs shown_' .. layout), tick_shown(swap);
    end;
    for layout, swap in pairs({ lines = 'Swap the lines', split = 'Swap the sides' }) do
        h.fresh(function(s) s.overhead.enabled = true; s.overhead.types.mob.kinds, s.overhead.types.mob.layout = 'debuff', layout; end);
        page._selection.kind = 'mob';
        h.on('overhead', 'show');
        local limit, swapped = buff_rows(layout, swap);
        assert(limit and swapped and tick_shown('Light up buffs you can remove'), 'Ticked, the buff rows stay on ' .. layout);
        h.s.overhead.types.mob.show_copy_image = false;
        h.bump();
        h.draw();
        limit, swapped = buff_rows(layout, swap);
        assert(limit and swapped, 'One tick is enough on ' .. layout);
        h.s.overhead.types.mob.show_third_eye = false;
        h.bump();
        h.draw();
        limit, swapped = buff_rows(layout, swap);
        assert(not limit and not swapped and not tick_shown('Light up buffs you can remove'), 'Unticked, no buffs can show, so the rows go on ' .. layout);
        h.s.overhead.types.mob.kinds, h.s.overhead.types.mob.show_third_eye = 'buff', true;
        h.bump();
        h.draw();
        limit, swapped = buff_rows(layout, swap);
        assert(limit and not swapped, 'Buffs only has one side, ticked or not, on ' .. layout);
    end;

    -- Party list buffs: on Filters, gone with None, and the tick writes.
    h.fresh(function(s) s.party_ui.enabled = true; end);
    h.on('party_ui', 'filters');
    assert(h.says('Always show') and tick_shown('Copy Image') and tick_shown('Third Eye'), 'Party list buffs has the line on Filters.');
    local function result(text, label)
        for _, entry in ipairs(h.window.search(text)) do
            if entry.panel == 'party_ui' and entry.label == label then return true; end;
        end;
        return false;
    end;
    for _, entry in ipairs({ { 'Always show', 'Always show' }, { 'Copy Image', 'Copy Image' }, { 'utsusemi', 'Copy Image' }, { 'samurai', 'Third Eye' } }) do
        assert(result(entry[1], entry[2]), 'Search for ' .. entry[1] .. ' finds it on Party list buffs.');
    end;
    h.draw('Third Eye##frame');
    assert(h.s.party_ui.effects.show_third_eye == false, 'The tick writes.');
    h.s.party_ui.effects.kind = 'none';
    h.bump();
    h.draw();
    assert(not h.says('Always show') and not tick_shown('Copy Image'), 'With None nothing shows, so the line goes.');
    assert(result('Third Eye', 'Show buffs or debuffs') and not result('Third Eye', 'Third Eye'), 'And its name finds the Show choice.');
end;

-- Samples: a party member in each party has each effect.
do
    local _, subjects = require('ui.party_hud').sample(18, 0);
    local function has(member, id)
        for _, row in ipairs(subjects[1000 + member].effects) do if row.effect == id then return true; end; end;
        return false;
    end;
    for _, first in ipairs({ 0, 6, 12 }) do
        assert(has(first + 5, 66) and has(first + 6, 67), 'Each party\'s samples have one of each.');
    end;
end;
return 'Always show: Copy Image and Third Eye show whoever cast them, on mobs, you, your party and your alliance';
