local defaults, window, hud = require('ui.defaults'), require('ui.settings_window'), require('ui.hud');
local custom = require('core.customization');
local imgui = require('imgui');
local s, view = defaults.make(), hud.sample(100);
s.window.open = true;
s.window.sections = setmetatable({}, { __index = function() return true; end });
s.style.theme, s.style.font, s.style.font_size = 'Original FFXI', 'XI View', 21;
s.party_ui.style.icon_art, s.party_ui.effects.icon_size = 'XI View', 47;
s.panels.self_buffs.colors.text = {0.2,0.3,0.4,0.8};
s.panels.self_buffs.mode, s.panels.spell_recasts.mode = 'bars', 'bars';
local edits, saves, query, navigations = 0, 0, nil, 0;
local cb = {
    changed = function() edits = edits + 1; end,
    editor_changed = function() navigations = navigations + 1; end,
    save = function() saves = saves + 1; return true; end,
};
imgui.CollapsingHeader = function() return true; end;
imgui.InputTextWithHint = function(label, _, value)
    if label == '##find_settings' and query ~= nil then value[1], query = query, nil; return true; end;
    return false;
end;
local before = custom.history_value(s);
local controls = {Button=true,Checkbox=true, SliderFloat=true, InputText=true, InputTextWithHint=true, BeginCombo=true};
local function draw(page, button)
    s.window.tab, MOCK.imgui_calls = page, {};
    if button then MOCK.clicks[button] = true; end;
    window.draw(s, view, cb);
    if button then assert(not MOCK.clicks[button], 'Navigation button remains reachable: ' .. button); end;
    local seen = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if controls[call[1]] and type(call[2]) == 'string' then
            local label = call[2]:match('###(.*)$') or call[2];
            seen[label:gsub('^##','')] = true;
        end;
    end;
    assert(custom.equal(before, custom.history_value(s)), 'Browsing preserves every saved display setting and lock.');
    assert(edits == 0, 'Browsing never starts an Undo transaction.');
    assert(#MOCK.font_stack == 0, 'Settings navigation balances its fonts.');
    return seen;
end;
-- A panel's tabs: each shows its own rows, and Locked and the reset are on all of them.
local panels = require('ui.panel_frame');
local timer_rows = { show = 'frame_Layout', look = 'Show the bar##frame', filters = 'frame_Find an effect', place = 'frame_Across', when = 'frame_From_min' };
local recast_rows = { show = 'frame_Layout', look = 'Show the bar##frame', filters = 'frame_Find a recast', place = 'frame_Across', when = 'frame_From_min' };
local party_rows = { show = 'Countdowns##frame', look = 'frame_Opacity', filters = 'frame_Find an effect',
    place = "frame_Gap from the game's list", when = 'frame_From_min' };
for id, tab_rows in pairs({ self_buffs = timer_rows, spell_recasts = recast_rows, party_ui = party_rows }) do
    panels.open(id, 'show');
    for _, tab in ipairs(panels.tabs) do
        local seen = draw('Display', tab.key ~= 'show' and tab.button or nil);
        assert(panels.context():find('/' .. tab.key, 1, true), 'The click selects its tab: ' .. tab.key);
        assert(seen[tab_rows[tab.key]], 'The tab shows its rows: ' .. tab.key);
        for other, label in pairs(tab_rows) do
            if other ~= tab.key then assert(not seen[label], 'Other tabs are hidden: ' .. label); end;
        end;
        assert(seen['Locked##frame'] and seen['Reset this display##frame'], 'Locked and the reset are on every tab: ' .. tab.key);
    end;
    query = 'font';
    panels.open(id, 'place');
    local before_search = panels.context();
    draw('Display');
    assert(panels.context() == before_search, 'Searching keeps the selected tab.');
    draw('Display', 'Clear search');
end;
assert(saves == 0, 'Subpage browsing and search do not save settings.');
imgui.BeginCombo = function(label)
    MOCK.imgui_calls[#MOCK.imgui_calls + 1] = {'BeginCombo',label};
    return true;
end;
local shared_fonts = draw('Home');
assert(shared_fonts['main_font'] and shared_fonts['main_icon_art'], 'The main page has the shared font and artwork a panel\'s Look tab points to.');
window.main_helpers.open_page('Display', 'self_buffs', 'filters');
local seen = draw(s.window.tab);
assert(s.window.tab == 'Display' and seen['frame_Find an effect'], 'A link to a display\'s Filters tab opens it.');
panels.open('self_buffs', 'place');
panels.open('self_debuffs', 'look');
panels.open('self_buffs');
assert(panels.context() == 'self_buffs/place', 'Each status panel remembers its own editing tab.');
panels.open('self_debuffs');
assert(panels.context() == 'self_debuffs/look', 'Each status panel remembers its own editing tab.');
panels.open('self_buffs', 'invalid');
assert(panels.context() == 'self_buffs/show', 'A tab that does not exist opens Show.');
assert(s.party_ui.locked and s.panels.self_buffs.locked, 'Navigation never unlocks displays.');
assert(#MOCK.commands == 0, 'Settings navigation sends no game commands.');
return 'Display subpages isolate controls, search all tabs, and preserve customization, artwork and locks';
