-- Two saves shaped like two real characters', written out here value by value, come through a load exactly as saved, and
-- a second tidy changes nothing. One font runs every display, the countdown keys and blink stay on each display, the
-- window opens on the main page whatever tab was saved, and no step touches a lock.
local defaults, store = require('ui.defaults'), require('core.store');
local custom, copy = require('core.customization'), store.copy;
local party_theme, theme, look = require('ui.party_theme'), require('ui.theme'), require('ui.shared_look');
local imgui = require('imgui');
local status = { 'self_buffs', 'self_debuffs', 'target', 'party', 'watch' };
local recasts = { 'spell_recasts', 'ability_recasts', 'item_recasts', 'recasts' };

-- The countdown keys both characters hold: outlines on the status timers and the party list.
local function countdowns(config, outline, blink)
    config.countdown_bold, config.countdown_shadow, config.countdown_outline = false, true, outline;
    config.countdown_outline_color = { 0, 0, 0, 1 };
    if blink then config.blink_icons, config.blink_seconds = true, 15; end;
end;
local function common(s, font)
    s.style.font, s.style.icon_art, s.style.gauge_art, s.style.recast_icon_art = font, font, font, font;
    s.style.theme, s.style.window_type, s.style.scale = 'Original FFXI', 1, 1;
    s.window_style.font_size = 17;
    s.window.peek = false;
    s.party_ui.style.icon_art, s.party_ui.style.opacity, s.party_ui.native.gap = font, 1, 26;
    for _, id in ipairs(status) do countdowns(s.panels[id], true, true); end;
    for _, id in ipairs(recasts) do countdowns(s.panels[id], false, false); end;
    countdowns(s.party_ui.effects, true, true);
    countdowns(s.overhead, false, true);
    countdowns(s.rolls, false, false);
    countdowns(s.pet, false, false);
    s.visibility.hide_events, s.visibility.hide_map, s.visibility.hide_ui = true, true, true;
    s.visibility.hide_typing = false;
    s.party_ui.enabled, s.overhead.enabled, s.rolls.enabled = true, true, true;
    s.party_cooldowns.enabled = true;
    s.rolls.locked, s.pet.locked = true, true;
end;
-- Original FFXI throughout, at text size 16, its overhead countdowns bold and outlined. Left on Profiles.
local function first()
    local s = defaults.make();
    common(s, 'Original FFXI');
    s.style.font_size = 16;
    s.overhead.countdown_bold, s.overhead.countdown_outline = true, true;
    s.window.tab, s.window.width, s.window.height = 'Profiles', 1234, 795;
    for _, id in ipairs(defaults.panel_order) do s.panels[id].locked, s.panels[id].enabled = true, true; end;
    s.panels.party.enabled, s.panels.watch.enabled = false, false;
    s.pet.enabled, s.party_cooldowns.list.enabled = true, true;
    return s;
end;
-- XI View with the Original FFXI skin, every panel unlocked. Left on Display.
local function second()
    local s = defaults.make();
    common(s, 'XI View');
    s.window.tab, s.window.width, s.window.height = 'Display', 960, 680;
    for _, id in ipairs(defaults.panel_order) do s.panels[id].locked, s.panels[id].enabled = false, false; end;
    s.panels.ability_recasts.enabled, s.panels.recasts.enabled = true, true;
    s.pet.enabled, s.party_cooldowns.list.enabled = false, false;
    return s;
end;

local function walk(a, b, path, out)
    local keys = {};
    for key in pairs(a) do keys[key] = true; end;
    for key in pairs(b) do keys[key] = true; end;
    for key in pairs(keys) do
        local left, right, here = a[key], b[key], path .. '.' .. tostring(key);
        if type(left) == 'table' and type(right) == 'table' then walk(left, right, here, out);
        elseif left ~= right then out[#out + 1] = here; end;
    end;
    return out;
end;
-- The font each display draws in.
local function faces(s)
    local function own(config) return config.font ~= '' and config.font or s.style.font; end;
    return { timers = s.style.font, party = party_theme.party(s.party_ui, s.style).font, overhead = own(s.overhead), rolls = own(s.rolls),
        pet = own(s.pet), window = theme.window(s).font };
end;
local function locks(s)
    local out = { party = s.party_ui.locked, notices = s.alerts.notice_locked, cooldowns = s.party_cooldowns.list.locked,
        pulse = s.ready_pulse.locked, rolls = s.rolls.locked, pet = s.pet.locked };
    for _, id in ipairs(defaults.panel_order) do out[id] = s.panels[id].locked; end;
    return out;
end;

for _, case in ipairs({ { 'first', first, 'Original FFXI', 'mixed' }, { 'second', second, 'XI View', 'usual' } }) do
    local name, saved = case[1], case[2]();
    local once = defaults.tidy(copy(saved));
    local changed = walk(saved, once, '', {});
    table.sort(changed);
    assert(#changed == 0, name .. ': nothing changes on a load: ' .. table.concat(changed, ' '));
    assert(custom.equal(defaults.tidy(copy(once)), once), name .. ': a second tidy changes nothing.');
    for display, face in pairs(faces(once)) do assert(face == case[3], name .. ': ' .. display .. ' draws in ' .. tostring(face)); end;
    assert(look.outline(once) == case[4], name .. ': outlines read ' .. look.outline(once));
    assert(look.blink(once) == true and look.blink_seconds(once) == 15, name .. ': blinks at 15 seconds.');
    assert(custom.equal(locks(once), locks(saved)), name .. ': every lock stays.');
end;
-- The first save's bold overhead countdowns read as a difference, and nothing is written for reading it.
local mixed = defaults.tidy(first());
assert(look.bold(mixed) == nil and look.shadow(mixed) == true and look.outline(mixed) == 'mixed', 'Bold and Outline read Mixed.');
assert(mixed.overhead.countdown_bold == true and mixed.overhead.countdown_outline == true, 'The keys stay as saved.');

-- The party list draws in the main font, and a second pass finds nothing more to do.
local main_font = defaults.make();
main_font.style.font = 'Original FFXI';
local tidied = defaults.tidy(copy(main_font));
assert(party_theme.party(tidied.party_ui, tidied.style).font == 'Original FFXI', 'The party list draws in the main font.');
assert(custom.equal(defaults.tidy(copy(tidied)), tidied), 'A second tidy changes nothing.');
-- A fresh install and an empty table go through twice the same.
for _, start in ipairs({ defaults.make(), {} }) do
    local result = defaults.tidy(copy(start));
    assert(custom.equal(defaults.tidy(copy(result)), result), 'A second tidy changes nothing on new settings.');
end;
-- The window writes in the main font.
local written = defaults.make();
written.style.font = 'Original FFXI';
local kept = defaults.tidy(copy(written));
assert(theme.window(kept).font == 'Original FFXI', 'The window reads the main font.');
assert(custom.equal(defaults.tidy(copy(kept)), kept), 'A second tidy changes nothing.');

-- Locks: fresh displays are locked, and each saved lock stays whatever its neighbours hold.
for display, locked in pairs(locks(defaults.make())) do assert(locked == true, 'A fresh display starts locked: ' .. display); end;
local function chequered(start)
    local s = defaults.make();
    local value = start;
    local function next_lock() value = not value; return value; end;
    s.party_ui.locked, s.alerts.notice_locked, s.party_cooldowns.list.locked = next_lock(), next_lock(), next_lock();
    s.ready_pulse.locked, s.rolls.locked, s.pet.locked = next_lock(), next_lock(), next_lock();
    for _, id in ipairs(defaults.panel_order) do s.panels[id].locked = next_lock(); end;
    return s;
end;
for _, start in ipairs({ true, false }) do
    local saved = chequered(start);
    local once = defaults.tidy(copy(saved));
    local twice = defaults.tidy(copy(once));
    assert(custom.equal(locks(once), locks(saved)) and custom.equal(locks(twice), locks(saved)), 'Tidy, once or twice, leaves every lock.');
end;

-- Through a real load: the window opens on the main page, whichever tab was saved, and the picks there leave the locks.
local snapshot = { valid = true, id = 2002, name = 'First', zone = 102, job = 12, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local hud = require('ui.hud');
hud.draw, hud.draw_notices = function() end, function() end;
require('ui.native_party_hud').draw = function() return false, {}; end;
package.loaded['core.native_party_ui'] = { treasure_open = function() return false; end, status = function() return { available = false }; end };
local function save_file(name, id, settings)
    local folder = MOCK_INSTALL_PATH .. '/config/addons/vantage/' .. name .. '_' .. id;
    MOCK_MKDIR(folder);
    assert(store.write(folder .. '/settings.json', settings), 'Fixture: the save is written.');
    return folder .. '/settings.json';
end;
local first_path = save_file('First', 2002, first());
local second_path = save_file('Second', 2003, second());
local app = dofile(ADDON_DIR .. '/vantage.lua');
local window = require('ui.settings_window');
MOCK.fire('load'); app.refresh(0);
assert(app.state.path == first_path and not app.state.unread, 'Fixture: the first save loads.');
assert(app.state.settings.window.tab == 'Home', 'A saved tab reopens the main page.');
local width, height = app.state.settings.window.width, app.state.settings.window.height;
assert(width == 1234 and height == 795, 'The window keeps its size.');
snapshot.id, snapshot.name = 2003, 'Second';
app.refresh(0);
assert(app.state.path == second_path and app.state.settings.window.tab == 'Home', 'And for the second save.');

local combo;
local begin_combo = imgui.BeginCombo;
imgui.BeginCombo = function(label, ...) begin_combo(label, ...); return label == combo; end;
local function frame(click, opened)
    combo, MOCK.imgui_calls = opened, {};
    if click then MOCK.clicks[click] = true; end;
    window.draw(app.state.settings, { rows = {}, context = { valid = false } }, app.callbacks);
    if click then assert(not MOCK.clicks[click], 'The control is on screen: ' .. click); end;
    MOCK.clicks = {};
end;
local chequer = defaults.tidy(chequered(true));
chequer.window.open, chequer.window.tab = true, 'Home';
chequer.window.sections['Home/More look'] = true;
app.state.settings = chequer;
local before = locks(chequer);
frame();
frame('Mint##Mint', '##main_skin');
frame('1.5x##main_size');
frame('XI View##XI View', '##main_font');
frame('Bold##main_countdown_bold');
frame('None##none', '##main_countdown_outline');
frame('Show samples##main');
frame('End samples##main');
assert(custom.equal(locks(app.state.settings), before), 'Skin, Size, Font, countdown picks and samples leave every lock.');
MOCK.fire('unload');
assert(#MOCK.commands == 0, 'None of it sends a game command.');
return 'Saves load as they were, a second tidy changes nothing, and no step touches a lock';
