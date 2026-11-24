-- /vg reset refuses a scope it doesn't have and names every scope it takes (core/customization.lua reset).
local defaults, custom = require('ui.defaults'), require('core.customization');
local refused, why = custom.reset(defaults.make(), 'typo');
assert(refused == nil and type(why) == 'string', 'A scope that isn\'t one is refused.');
for _, scope in ipairs({ 'appearance', 'panels', 'displays', 'party_ui', 'overhead', 'durations', 'recast_tints', 'ready_pulse',
    'party_cooldowns', 'rolls', 'pet', 'edit_mode', 'moves_with', 'layout', 'conditions', 'effects', 'alerts', 'effect_filters',
    'window', 'window_style', 'visibility', 'tracking', 'chat_colors', 'diagnostics', 'job_profiles', 'all' }) do
    assert(custom.reset(defaults.make(), scope), 'Fixture: ' .. scope .. ' is a reset scope.');
    assert(why:find('%f[%w_]' .. scope .. '%f[^%w_]'), 'The refusal names ' .. scope .. ': ' .. why);
end;
-- navigation and preview are gone: the Hold Shift tick, /vg reset window and /vg preview off do what they did. They are
-- refused like any other word, and the refusal doesn't name them.
for _, scope in ipairs({ 'navigation', 'preview' }) do
    local gone, said = custom.reset(defaults.make(), scope);
    assert(gone == nil and said == why, 'Reset ' .. scope .. ' is refused like any other word: ' .. tostring(said));
    assert(not why:find('%f[%w_]' .. scope .. '%f[^%w_]'), 'The refusal doesn\'t name ' .. scope .. '.');
end;
