-- TextWrapped, BulletText and SetTooltip hand their text to the game's printf as the format, so Vantage doubles every %.
-- A % that reached it alone printed junk, and one before an n closed the game.
local store = require('core.store');
local imgui = require('imgui');
local given = {};
for _, name in ipairs({ 'TextWrapped', 'BulletText', 'SetTooltip' }) do
    imgui[name] = function(...) given[name] = { n = select('#', ...), ... }; end;
end;
local SNAP = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 1, self_known = true, self_effects = {}, party = {}, entities = {
    [1001] = { id = 1001, name = 'Tester', hp = 100, mp = 100, tp = 0, level = 75, job = 1 } } };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(SNAP); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
require('ui.party_hud').draw = function() return 0, {}; end;
require('ui.native_party_hud').draw = function() return 0, {}; end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, update = function() end,
    status = function() return { active = false }; end, restore = function() return true; end, suspend = function() return true; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
for name in pairs(given) do given[name] = nil; end;
for _, name in ipairs({ 'TextWrapped', 'BulletText', 'SetTooltip' }) do
    imgui[name]('100% nin');
    assert(given[name][1] == '100%% nin' and given[name].n == 1, name .. ' gets its % doubled, and nothing else: ' .. tostring(given[name][1]));
    imgui[name]('Plain words');
    assert(given[name][1] == 'Plain words' and given[name].n == 1, name .. ' leaves other text alone.');
    imgui[name]('%n%s%');
    assert(given[name][1] == '%%n%%s%%', name .. ' doubles every %.');
end;

-- A learned time waits for the next save, a minute at most, not 0.6 s after each wear-off.
SNAP.self_known = true;
MOCK.fire('load');
app.refresh(0);
app.state.dirty, app.state.changed_at = false, -100;
app.state.settings.durations.learn = true;
local real = app.tracker.samples;
local learned = { { learn_key = 'spell:1:2:', learn_start = 10, time = 70, entity_name = '' } };
app.tracker.samples = function() local list = learned; learned = {}; return list; end;
app.refresh(200);
app.tracker.samples = real;
assert(app.state.learned_at == 200 and not app.state.dirty, 'A learned time waits for the next save: ' .. tostring(app.state.learned_at));
MOCK.now = 259; MOCK.frame(0);
assert(app.state.learned_at == 200 and not app.state.dirty, 'Within the minute nothing is saved.');
MOCK.frame(1);
assert(app.state.learned_at == nil and not app.state.dirty and store.read(app.state.path).durations.learned['spell:1:2:'],
    'A minute after the first, it is saved.');
return 'Percent signs reach printf as plain text';
