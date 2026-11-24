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
    { 'ui/action_icons.lua', 'ui.action_icons', 'status' },
    { 'core/store.lua', 'core.store', 'flush' },
    { 'core/share.lua', 'core.share', 'windows_name' },
    { 'core/warmup.lua', 'core.warmup', 'wanted' },
    { 'core/roster.lua', 'core.roster', 'reset' },
};
for _, entry in ipairs(exports) do
    local path, name, key = entry[1], entry[2], entry[3];
    assert(type(require(name)[key]) == 'function', name .. '.' .. key .. ' is there for fixtures');
    assert(shipped(path)[key] == nil, name .. '.' .. key .. ' is not shipped');
end

-- The Help page's guide links are listed for tests/test_help_links.lua only.
assert(type(require('ui.settings_window').guide_topics) == 'table', 'The guide links are there for fixtures.');
assert(shipped('ui/settings_window.lua').guide_topics == nil, 'The guide links are not shipped.');

-- The chat reader's status and its whole load are for fixtures. tests/mock_ashita.lua puts a stand-in in core.chat,
-- so the file is loaded in both modes.
local function chat_file(test_mode)
    VANTAGE_TEST_MODE = test_mode;
    local ok, module = pcall(function() return assert(loadfile(ADDON_DIR .. '/core/chat.lua'))(); end);
    VANTAGE_TEST_MODE = true;
    assert(ok, module);
    return module, getmetatable(module.new());
end
local testing, test_reader = chat_file(true);
assert(type(testing.status) == 'function' and type(test_reader.status) == 'function' and type(test_reader.load) == 'function',
    'The chat reader\'s status and load are there for fixtures.');
local plain, plain_reader = chat_file(false);
assert(plain.status == nil and plain_reader.status == nil and plain_reader.load == nil, 'The chat reader ships no status or load.');
assert(type(plain.load) == 'function' and type(plain_reader.load_table) == 'function', 'The chat reader still loads in steps.');

-- save_layout writes a shared layout without publish_layout's merge; only fixtures seed layouts with it.
local folder = MOCK_INSTALL_PATH .. '/config/addons/vantage/shipped-exports';
assert(type(require('core.profiles').new(folder).save_layout) == 'function');
-- The constructor checks test mode each time it makes a profile set.
VANTAGE_TEST_MODE = false;
local made = require('core.profiles').new(folder);
VANTAGE_TEST_MODE = true;
assert(made.save_layout == nil, 'Profiles ship no save_layout.');
