local defaults = require('ui.defaults');
local copy, custom = require('core.store').copy, require('core.customization');
local profiles = require('core.profiles');
local keys = { 'icon_countdown_position', 'icon_countdown_size', 'icon_countdown_gap' };
-- Every countdown Vantage draws: the party list strips and the timer panels.
local function targets(settings)
    local result = { settings.party_ui.effects };
    for _, id in ipairs(defaults.panel_order) do result[#result + 1] = settings.panels[id]; end;
    return result;
end;
local function matches(effect, expected)
    for index, key in ipairs(keys) do assert(effect[key] == expected[index], key .. ' keeps its expected value.'); end;
end;
local fresh = defaults.make();
for _, effect in ipairs(targets(fresh)) do matches(effect, { 'below', 0, 0 }); end;
local partial = copy(fresh);
for _, effect in ipairs(targets(partial)) do
    for _, key in ipairs(keys) do effect[key] = nil; end;
    effect.countdown_bold, effect.countdown_shadow, effect.countdown_outline = true, false, true;
end;
partial.style.font = 'XI View';
partial = defaults.tidy(partial);
for _, effect in ipairs(targets(partial)) do
    matches(effect, { 'below', 0, 0 });
    assert(effect.countdown_bold and not effect.countdown_shadow and effect.countdown_outline, 'A save\'s own styling stays as the missing keys fill in.');
end;
assert(partial.style.font == 'XI View');
for _, case in ipairs({
    { input={ 'inside', 6, 16 }, expected={ 'inside', 6, 16 } },
    { input={ 'below', 64, 0 }, expected={ 'below', 64, 0 } },
    { input={ 'side', 3, 22 }, expected={ 'below', 6, 16 } },
    { input={ 'inside', -4, -1 }, expected={ 'inside', 0, 0 } },
    { input={ 'below', 100, 2.9 }, expected={ 'below', 64, 3 } },
    { input={ 'inside', math.huge, 0/0 }, expected={ 'inside', 0, 0 } },
}) do
    local settings = defaults.make();
    for _, effect in ipairs(targets(settings)) do
        for index, key in ipairs(keys) do effect[key] = case.input[index]; end;
    end;
    for _, effect in ipairs(targets(defaults.tidy(settings))) do matches(effect, case.expected); end;
end;
local source = defaults.make();
for index, effect in ipairs(targets(source)) do
    effect.icon_countdown_position, effect.icon_countdown_size, effect.icon_countdown_gap = 'inside', index + 6, index;
end;
require('ui.shared_look').set_bold(source, true);
for index, effect in ipairs(targets(source)) do
    matches(effect, { 'inside', index + 6, index });
    assert(effect.countdown_bold, 'The shared Bold pick reaches every countdown and leaves where it sits alone.');
end;
local saved = profiles.new(MOCK_INSTALL_PATH .. '/config/addons/vantage');
assert(saved:save_new('Icon countdowns', source));
local restored = defaults.make();
assert(saved:load('Icon countdowns', restored));
for index, effect in ipairs(targets(restored)) do matches(effect, { 'inside', index + 6, index }); end;
for _, scope in ipairs({ 'presentation', 'placement' }) do
    assert(saved:save_layout(source, scope));
    restored = defaults.make();
    assert(saved:load_layout(restored, scope));
    for index, effect in ipairs(targets(restored)) do
        matches(effect, scope == 'presentation' and { 'inside', index + 6, index } or { 'below', 0, 0 });
    end;
    assert(restored.party_ui.locked and restored.panels.self_buffs.locked);
end;
restored = copy(source);
assert(custom.reset(restored, 'appearance'));
for _, id in ipairs(defaults.panel_order) do matches(restored.panels[id], { 'below', 0, 0 }); end;
matches(restored.party_ui.effects, { 'inside', 7, 1 });
for _, scope in ipairs({ 'party_ui', 'self_buffs' }) do
    restored = copy(source);
    assert(custom.reset(restored, scope));
    matches(scope == 'self_buffs' and restored.panels[scope] or restored[scope].effects, { 'below', 0, 0 });
end;
assert(custom.set(source, 'panels.self_buffs.icon_countdown_size', '5') == nil, 'Command editing rejects the invalid 1-5 pixel range.');
assert(custom.set(source, 'party_ui.effects.icon_countdown_size', '0').party_ui.effects.icon_countdown_size == 0);
assert(MOCK.saved == 0 and #MOCK.commands == 0, 'Tests use temporary profile files only.');
