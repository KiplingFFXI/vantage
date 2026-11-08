-- Functions only fixtures call are defined under VANTAGE_TEST_MODE, so the shipped addon can't call them.
-- Each module is loaded again from its file with test mode off; the fixtures keep their copies.
local function shipped(path)
    VANTAGE_TEST_MODE = false;
    local ok, module = pcall(function() return assert(loadfile(ADDON_DIR .. '/' .. path))(); end);
    VANTAGE_TEST_MODE = true;
    assert(ok, module);
    return module;
end

local exports = {
    { 'core/sound.lua', 'core.sound', 'is_open' },
    { 'ui/hud.lua', 'ui.hud', 'field_lines' },
    { 'ui/layout.lua', 'ui.layout', 'grip' },
    { 'ui/appearance.lua', 'ui.appearance', 'current' },
    { 'ui/client_fonts.lua', 'ui.client_fonts', 'draw_countdown' },
    { 'ui/action_icons.lua', 'ui.action_icons', 'status' },
    { 'core/store.lua', 'core.store', 'flush' },
    { 'core/share.lua', 'core.share', 'windows_name' },
    { 'core/warmup.lua', 'core.warmup', 'wanted' },
};
for _, entry in ipairs(exports) do
    local path, name, key = entry[1], entry[2], entry[3];
    assert(type(require(name)[key]) == 'function', name .. '.' .. key .. ' is there for fixtures');
    assert(shipped(path)[key] == nil, name .. '.' .. key .. ' is not shipped');
end

-- save_layout writes a shared layout without publish_layout's merge; only fixtures seed layouts with it.
local folder = MOCK_INSTALL_PATH .. '/config/addons/vantage/shipped-exports';
assert(type(require('core.profiles').new(folder).save_layout) == 'function');
-- The constructor checks test mode each time it makes a profile set.
VANTAGE_TEST_MODE = false;
local made = require('core.profiles').new(folder);
VANTAGE_TEST_MODE = true;
assert(made.save_layout == nil, 'Profiles ship no save_layout.');
