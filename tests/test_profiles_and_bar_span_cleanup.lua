-- With no profile in use, the Profiles page says so, and the main page has no line about it. The Profiles page reads the saved
-- list by itself, so it has no Refresh profiles button. Status timers and Recasts have no Bar span slider: a save keeps
-- the key's value, the bar and the hover read it and /vg set reaches it.
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
require('ui.party_hud').draw = function() return 0, {}; end;
require('ui.native_party_hud').draw = function() return 0, {}; end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, update = function() end,
    status = function() return { active = false }; end, restore = function() return true; end, suspend = function() return true; end };
local defaults = require('ui.defaults');
local app = dofile(ADDON_DIR .. '/vantage.lua');
local window = require('ui.settings_window');
MOCK.fire('load'); app.refresh(0);
local s = app.state.settings;
s.window.open = true;
s.window.sections = setmetatable({}, { __index = function() return true; end });
local function draw(page, clicks)
    s.window.tab, MOCK.imgui_calls = page, {};
    for _, label in ipairs(clicks or {}) do MOCK.clicks[label] = true; end;
    window.draw(s, app.state.view, app.callbacks);
    MOCK.clicks = {};
end;
local function said(text)
    for _, call in ipairs(MOCK.imgui_calls) do
        for index = 2, 4 do if call[index] == text then return call[1]; end; end;
    end;
end;
local function any(words)
    for _, call in ipairs(MOCK.imgui_calls) do
        for index = 2, 4 do
            if type(call[index]) == 'string' and call[index]:find(words, 1, true) then return call[index]; end;
        end;
    end;
    return nil;
end;

-- No profile in use, said on the Profiles page only, and Unsaved settings nowhere.
s.active_profile = '';
draw('Home');
assert(not said('No profile in use.'), 'The main page has no profile line.');
assert(not any('nsaved settings'), 'The main page has no Unsaved settings: ' .. tostring(any('nsaved settings')));
draw('Profiles');
assert(said('No profile in use.') == 'TextWrapped', 'The Profiles page says No profile in use.');
assert(not any('nsaved settings'), 'Nor does the Profiles page: ' .. tostring(any('nsaved settings')));

-- Refresh profiles.
assert(not said('Refresh profiles'), 'The Profiles page has no Refresh profiles.');
for _, result in ipairs(window.search('refresh profiles')) do assert(result.label ~= 'Refresh profiles', 'Search doesn\'t offer it.'); end;
for _, row in ipairs(require('ui.search_index').entries) do assert(row[2] ~= 'Refresh profiles', 'No topic names it.'); end;
-- The list follows the file without it.
assert(app.callbacks.profile_save('Support', false), 'Fixture: a saved profile.');
local names = app.callbacks.profile_summary().names;
assert(#names == 1 and names[1] == 'Support', 'A save updates the list at once.');

-- Bar span, on a bar panel and a recast panel. Both keep their other controls.
local panels = require('ui.panel_frame');
local function size(id)
    panels.open(id, 'place');
    draw('Display');
    draw('Display');
end;
s.panels.self_buffs.mode = 'bars';
size('self_buffs');
assert(said('##frame_Bar width'), 'Fixture: the Size and place tab of a bar panel is on screen.');
assert(not any('Bar span'), 'A bar panel has no Bar span: ' .. tostring(any('Bar span')));
size('spell_recasts');
assert(not any('Bar span'), 'A recast panel has none: ' .. tostring(any('Bar span')));
for _, query in ipairs({ 'bar span', 'original duration was not seen', 'full cooldown was not seen', 'horizon' }) do
    for _, result in ipairs(window.search(query)) do
        assert(not result.label:find('Bar span', 1, true), 'Search doesn\'t offer ' .. result.label);
    end;
end;
for _, row in ipairs(require('ui.search_index').entries) do assert(not row[3]:find('%f[%a]horizon%f[%A]'), 'No topic says horizon: ' .. row[2]); end;

-- Help says where to read the span, and points at no setting.
draw('Help');
assert(not any('configured time span'), 'Help has no configured time span.');
assert(any('the details say what time the bar covers'), 'Help says where to read it.');

-- The key's value is kept and clamped by tidy, read by the bar and the hover, and reached by /vg set.
assert(defaults.make().panels.self_buffs.horizon == 300, 'It starts at 300.');
local saved = defaults.make();
saved.panels.self_buffs.horizon = 80000;
assert(defaults.tidy(saved).panels.self_buffs.horizon == 80000, 'A saved value is kept.');
saved.panels.self_buffs.horizon = 90000;
assert(defaults.tidy(saved).panels.self_buffs.horizon == 86400, 'tidy holds it to its range.');
local event = { command = '/vg set panels.self_buffs.horizon 900' };
MOCK.fire('command', event);
assert(event.blocked, 'Fixture: the command ran.');
assert(app.state.settings.panels.self_buffs.horizon == 900, '/vg set reaches it.');
local row = { name = 'Protect', domain = 'status', effect = 40, deadline = 150, status = 'server' };
local details = hud.details(row, 100, { horizon = 900 });
assert(details:find('The bar spans the last 15m', 1, true), 'The hover names the span: ' .. details);
print('profiles and bar span cleanup passed');
return true;
