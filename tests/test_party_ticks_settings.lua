-- Include me and One row for a cast on several members in the settings: off to start, kept by a save, off again after
-- Reset effects and groups and after a starter. Their ticks are on the Show tab of Party members' timers and nowhere
-- else, they write there, search finds them by what they're about, and Members lists you while Include me is on. A tick
-- left on you once it's off says so and hides nobody.
local defaults, custom, starters = require('ui.defaults'), require('core.customization'), require('core.starters');
local ME, FOLD = 'Include me', 'One row for a cast on several members';
local KEYS = { 'include_self', 'fold_casts' };

do
    local s = defaults.tidy(defaults.make());
    for _, key in ipairs(KEYS) do
        assert(s.panels.party[key] == false, key .. ' starts off.');
        for id, panel in pairs(s.panels) do
            assert(id == 'party' or panel[key] == nil, 'Party members\' timers has ' .. key .. ', not ' .. id .. '.');
        end;
        s.panels.party[key] = true;
        s = defaults.tidy(s);
        assert(s.panels.party[key] == true, 'A save keeps ' .. key .. '.');
        s.panels.party[key] = 'yes';
        s = defaults.tidy(s);
        assert(s.panels.party[key] == false, 'A value that isn\'t true reads as off: ' .. key);
        s.panels.party[key] = nil;
        s = defaults.tidy(s);
        assert(s.panels.party[key] == false, 'A save from before ' .. key .. ' has it off.');

        s.panels.party[key] = true;
        s = custom.reset(s, 'effects');
        assert(s.panels.party[key] == false, 'Reset effects and groups turns ' .. key .. ' off.');
    end;
    -- A starter says what the party panel shows, so each one turns them off.
    for _, entry in ipairs(starters.list) do
        local save = defaults.tidy(defaults.make());
        save.panels.party.include_self, save.panels.party.fold_casts = true, true;
        save = starters.apply(save, entry.name);
        assert(save.panels.party.include_self == false and save.panels.party.fold_casts == false, entry.name .. ' turns both off.');
    end;
end;

do
    local h = require('panel_fixture')();
    local function ticked(label) return h.called('Checkbox', label .. '##frame'); end;
    local function found(text, panel, label)
        for _, entry in ipairs(h.window.search(text)) do
            if entry.panel == panel and entry.label == label then return true; end;
        end;
        return false;
    end;

    h.fresh(function(s) for _, panel in pairs(s.panels) do panel.enabled = true; end; end);
    for _, id in ipairs(defaults.panel_order) do
        for _, tab in ipairs({ 'show', 'filters' }) do
            h.on(id, tab);
            local here = id == 'party' and tab == 'show';
            assert(ticked(ME) == here and ticked(FOLD) == here, 'The ticks on ' .. id .. ' ' .. tab .. '.');
        end;
    end;

    h.on('party', 'show');
    h.draw(ME .. '##frame');
    assert(h.s.panels.party.include_self == true and h.s.panels.party.fold_casts == false, 'Include me writes its own setting.');
    h.draw(FOLD .. '##frame');
    assert(h.s.panels.party.fold_casts == true, 'The fold tick writes its own.');
    for _, text in ipairs({ 'include me', 'myself', 'my own' }) do
        assert(found(text, 'party', ME) and not found(text, 'target', ME), 'Search for ' .. text .. ' finds Include me on Party members\' timers.');
    end;
    for _, text in ipairs({ 'one row', 'protectra', 'fold', 'combine' }) do
        assert(found(text, 'party', FOLD) and not found(text, 'watch', FOLD), 'Search for ' .. text .. ' finds the fold tick.');
    end;

    -- The fold tick's help says a folded row lists its members only while Show details when I point at a timer is on.
    -- With that setting off, its tooltip still says so. The guide says that effects Vantage didn't see land fold by
    -- effect, and that members with different Copy Image counts keep their own rows (ui/cast_folds.lua together).
    local POINT = 'With Show details when I point at a timer on, point at the row for each member.';
    local UNSEEN = 'Effects Vantage only knows from the game\'s icons have no countdown to tell their casts apart, so those fold by effect.';
    local SHADOWS = 'Copy Image\'s icon shows how many shadows are left, so members with different counts keep their own rows.';
    local fold_help;
    for _, display in ipairs(h.panels._displays) do
        if display.id == 'party' then
            for _, entry in ipairs(display.entries) do if entry.row.key == 'fold_casts' then fold_help = entry.row.help; end; end;
        end;
    end;
    assert(type(fold_help) == 'string' and fold_help:find(POINT, 1, true), 'Pointing at a folded row needs details on: ' .. tostring(fold_help));
    local guide_file = assert(io.open(ADDON_DIR .. '/../docs/GUIDE.md', 'rb'));
    local guide = guide_file:read('*a');
    guide_file:close();
    assert(guide:find(UNSEEN, 1, true) and not fold_help:find('Hover the row', 1, true), 'Unseen copies fold by effect: ' .. fold_help);
    assert(guide:find(SHADOWS, 1, true), 'Copy Image with another shadow count keeps its own row.');
    h.fresh(function(s) s.style.hover = false; end);
    local hovered = h.imgui.IsItemHovered;
    h.imgui.IsItemHovered = function() return true; end;
    h.on('party', 'show');
    h.imgui.IsItemHovered = hovered;
    assert(h.says(fold_help), 'With Show details when I point at a timer off, the tooltip says what pointing needs.');

    -- Members lists you by name while Include me is on, so ticking a member can't hide you with no way back.
    h.fresh();
    h.view.context.id, h.view.context.name = 1001, 'Tester';
    h.view.context.party = { { id = 7001, name = 'Aerith', scope = 'party' } };
    h.on('party', 'show');
    assert(h.called('Checkbox', 'Aerith##member_7001') and not h.called('Checkbox', 'Tester##member_1001'), 'Off, Members lists only the others.');
    h.draw(ME .. '##frame');
    h.draw();
    assert(h.called('Checkbox', 'Tester##member_1001') and h.called('Checkbox', 'Aerith##member_7001'), 'On, you are on the list by name.');
    h.draw('Tester##member_1001');
    h.draw();
    local members = h.s.panels.party.members;
    assert(members[1001] == true or members['1001'] == true, 'Ticking yourself saves you.');
    assert(not h.says('Someone not in your party now'), 'And you aren\'t listed as someone who left.');

    -- Untick Include me with your tick left on. Members names you and says Include me is off, never that you left. That
    -- tick hides nobody while Include me is off, so Aerith's rows still show. Remove takes it off.
    local hud = require('ui.hud');
    local OWN = 'Tester is ticked, but Include me is off';
    local function aerith_rows()
        local row = { key = 'haste_aerith', effect = 33, name = 'Haste', kind = 'buff', scope = 'party', entity_id = 7001,
            entity_name = 'Aerith', source = 1001, mine = true, start = 0, deadline = 180, total = 180, status = 'estimated',
            present = true };
        return #hud.filter_rows({ rows = { row }, context = h.view.context }, h.s.panels.party, 'party', h.s);
    end;
    h.draw(ME .. '##frame');
    h.draw();
    assert(h.s.panels.party.include_self == false and h.says(OWN), 'Off, Members says your tick is yours and Include me is off.');
    assert(not h.says('Someone not in your party now'), 'You still aren\'t listed as someone who left.');
    assert(aerith_rows() == 1, 'Your tick hides nobody while Include me is off, so Aerith\'s rows show.');
    h.draw('Remove##member');
    h.draw();
    assert(next(h.s.panels.party.members) == nil and not h.says(OWN), 'Remove takes your tick off.');

    -- A starter turns Include me off and keeps who is ticked, so the same goes after one.
    h.fresh(function(s) s.panels.party.include_self = true; s.panels.party.members = { [1001] = true }; end);
    assert(h.app.callbacks.starter('healer', false), 'The Healer starter applies.');
    h.draw();
    h.on('party', 'show');
    assert(h.s.panels.party.include_self == false and h.says(OWN) and not h.says('Someone not in your party now'),
        'After a starter, Members says your tick is yours and Include me is off.');
    assert(aerith_rows() == 1, 'And your tick hides nobody.');

    -- Alone, with Include me on, you are who there is to tick.
    h.fresh(function(s) s.panels.party.include_self = true; end);
    h.view.context.party = {};
    h.on('party', 'show');
    assert(h.called('Checkbox', 'Tester##member_1001') and not h.says('Nobody in your party right now.'), 'Alone, the list holds you.');
end;
return 'Include me and the fold tick: their settings, page and search';
