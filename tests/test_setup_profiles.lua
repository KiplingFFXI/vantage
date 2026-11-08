-- The strips' sizing choices travel with full profiles and both shared layouts, while each character keeps the look
-- of its strips (placement only) and its lock.
local defaults, profiles = require('ui.defaults'), require('core.profiles');
local copy, equal = require('core.store').copy, require('core.customization').equal;
local saved = profiles.new(MOCK_INSTALL_PATH .. '/config/addons/vantage');
-- Snap panels of their own to game windows and Strip maximum width.
local cases = { { true, 420 }, { false, 300 } };
local function values(party)
    return { party.native.snap, party.native.width };
end;
local function matches(party, expected)
    for index, value in ipairs(values(party)) do assert(value == expected[index], 'Preserve independent sizing choice ' .. index); end;
end;
for _, case in ipairs(cases) do
    local source = defaults.make();
    source.party_ui.native.snap, source.party_ui.native.width = case[1], case[2];
    source.party_ui.style.icon_art, source.party_ui.style.opacity = 'XI View', .5;
    source.party_ui.locked = false;
    source.effect_filters.rules = { { enabled=true,effect=253,kind='all',name='',job=0,scope='all' } };
    matches(profiles.capture(source).party_ui, case);
    assert(saved:save_new('Setup sizing ' .. case[2], source));
    local target = defaults.make();
    assert(saved:load('Setup sizing ' .. case[2], target));
    matches(target.party_ui, case);
    assert(not target.party_ui.locked and target.party_ui.style.icon_art == 'XI View' and target.party_ui.style.opacity == .5,
        'Full profiles preserve the strip look and explicit lock choices.');
    for _, scope in ipairs({ 'placement', 'presentation' }) do
        local captured = profiles.capture_layout(source, scope);
        matches(scope == 'placement' and captured.party_ui or captured.presentation.party_ui, case);
        assert(saved:save_layout(source, scope));
        target = defaults.make();
        target.party_ui.style.icon_art, target.party_ui.style.opacity = 'Client', .8;
        local before = copy(target);
        assert(saved:load_layout(target, scope));
        matches(target.party_ui, case);
        assert(target.party_ui.locked, 'Shared layouts copy geometry but never unlock the receiving character.');
        if scope == 'placement' then
            assert(equal(target.party_ui.style, before.party_ui.style),
                'Placement sizing policies do not overwrite the look of the strips.');
            assert(equal(target.effect_filters, before.effect_filters), 'Placement sharing does not copy global hide rules.');
        else
            assert(target.party_ui.style.icon_art == 'XI View' and target.party_ui.style.opacity == .5,
                'Presentation sharing restores the strip look and sizing policies together.');
            assert(equal(target.effect_filters, source.effect_filters), 'Presentation sharing retains global hide rules.');
        end;
    end;
end;
assert(MOCK.saved == 0 and #MOCK.commands == 0, 'Fixture writes only its temporary profile store.');
