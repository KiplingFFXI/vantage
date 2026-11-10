-- Only effects from job abilities in the settings: off to start, kept by a save, and off again after a reset. Its tick
-- is on the Filters tab of Party members' timers and Party list buffs and nowhere else, it writes there, and search
-- finds it by what it's about.
local defaults, custom = require('ui.defaults'), require('core.customization');
local TICK = 'Only effects from job abilities';

do
    local s = defaults.tidy(defaults.make());
    assert(s.panels.party.abilities_only == false and s.party_ui.effects.abilities_only == false, 'It starts off.');
    for id, panel in pairs(s.panels) do
        assert(id == 'party' or panel.abilities_only == nil, 'Party members\' timers has it, not ' .. id .. '.');
    end;
    s.panels.party.abilities_only, s.party_ui.effects.abilities_only = true, true;
    s = defaults.tidy(s);
    assert(s.panels.party.abilities_only == true and s.party_ui.effects.abilities_only == true, 'A save keeps it.');
    s.panels.party.abilities_only, s.party_ui.effects.abilities_only = 'yes', 1;
    s = defaults.tidy(s);
    assert(s.panels.party.abilities_only == false and s.party_ui.effects.abilities_only == false, 'A value that isn\'t true reads as off.');
    s.panels.party.abilities_only, s.party_ui.effects.abilities_only = nil, nil;
    s = defaults.tidy(s);
    assert(s.panels.party.abilities_only == false and s.party_ui.effects.abilities_only == false, 'A save from before it has it off.');

    s.panels.party.abilities_only, s.party_ui.effects.abilities_only = true, true;
    s = custom.reset(s, 'effects');
    assert(s.panels.party.abilities_only == false, 'Reset effects and groups turns it off on Party members\' timers.');
    assert(s.party_ui.effects.abilities_only == true, 'And leaves Party list buffs.');
    s = custom.reset(s, 'party_ui');
    assert(s.party_ui.effects.abilities_only == false, 'Reset Party list buffs turns theirs off.');
end;

do
    local h = require('panel_fixture')();
    local function ticked() return h.called('Checkbox', TICK .. '##frame'); end;
    local function found(text, panel)
        for _, entry in ipairs(h.window.search(text)) do
            if entry.panel == panel and entry.label == TICK then return true; end;
        end;
        return false;
    end;

    h.fresh(function(s) for _, panel in pairs(s.panels) do panel.enabled = true; end; end);
    for _, id in ipairs(defaults.panel_order) do
        h.on(id, 'filters');
        local open = h.called('Checkbox', 'Only effects with a known time##frame') or h.called('Checkbox', 'Only recasts with a known time##frame');
        assert(open and ticked() == (id == 'party'), 'The tick on ' .. id .. '.');
    end;
    h.on('party', 'filters');
    h.draw(TICK .. '##frame');
    assert(h.s.panels.party.abilities_only == true, 'The tick writes.');
    for _, text in ipairs({ 'job abilities', 'rolls', 'blood pacts', 'abilities only' }) do
        assert(found(text, 'party') and not found(text, 'target'), 'Search for ' .. text .. ' finds it on Party members\' timers.');
    end;

    h.fresh(function(s) s.party_ui.enabled = true; end);
    h.on('party_ui', 'filters');
    assert(ticked(), 'Party list buffs has it on Filters.');
    h.draw(TICK .. '##frame');
    assert(h.s.party_ui.effects.abilities_only == true, 'The tick writes there.');
    for _, text in ipairs({ 'job abilities', 'maneuvers' }) do
        assert(found(text, 'party_ui'), 'Search for ' .. text .. ' finds it on Party list buffs.');
    end;
    h.s.party_ui.effects.kind = 'none';
    h.bump();
    h.draw();
    assert(not ticked(), 'With None nothing shows, so the tick goes.');
end;
return 'Only effects from job abilities: its settings, pages and search';
