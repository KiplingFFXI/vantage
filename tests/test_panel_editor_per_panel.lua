-- Each panel's editor offers only what that panel uses. Every recast is your own, so a recast panel has no Only effects
-- I cast, and one saved on still shows its recasts; the timer panels keep it. Members is on Party members' timers only.
local defaults, hud, store = require('ui.defaults'), require('ui.hud'), require('core.store');
local window, imgui = require('ui.settings_window'), require('imgui');
local equal = require('core.customization').equal;
local function fresh() return defaults.tidy(defaults.make()); end;

-- The filter. A recast panel with Only effects I applied saved on shows every recast it shows without it.
local s, view = fresh(), hud.sample(100);
local function count(id) return #hud.filter_rows(view, s.panels[id], id, s); end;
for _, id in ipairs({ 'spell_recasts', 'ability_recasts', 'item_recasts' }) do
    local shown = count(id);
    assert(shown > 0, 'Fixture: the sample has ' .. id .. '.');
    s.panels[id].mine_only = true;
    assert(count(id) == shown, 'A saved Only effects I applied leaves the recasts: ' .. id);
end;
-- The timer panels still show only effects you applied with it on.
local cut = 0;
for _, id in ipairs({ 'self_buffs', 'self_debuffs', 'target', 'party', 'watch' }) do
    s.panels[id].mine_only = false;
    local mine = 0;
    for _, row in ipairs(hud.filter_rows(view, s.panels[id], id, s)) do if row.mine then mine = mine + 1; end; end;
    local all = count(id);
    s.panels[id].mine_only = true;
    assert(count(id) == mine, 'Only effects I applied still filters ' .. id .. '.');
    cut = cut + all - mine;
end;
assert(cut > 0, 'Fixture: the sample has effects someone else applied.');

-- Loading: a timer panel keeps Only effects I cast, and Party timers their selected members.
local saved = fresh();
saved.panels.target.mine_only = true;
saved.panels.party.members = { [1002] = true };
local loaded = defaults.tidy(store.copy(saved));
assert(loaded.panels.target.mine_only == true, 'A timer panel keeps a saved Only effects I cast.');
assert(equal(loaded.panels.party.members, { [1002] = true }), 'Party timers keep their selected members.');

-- The editor. Each panel's Filters tab, with a party member and a target to list.
s = fresh();
s.window.open = true;
s.window.sections = setmetatable({}, { __index = function() return true; end });
view = hud.sample(100);
view.context.party = { { id = 1002, name = 'Party member', scope = 'party' } };
local cb = { now = function() return 100; end, save = function() return true; end, editor_changed = function() end,
    changed = function() end, reset = function() return true; end, sound_files = function() return {}; end };
local opened, real_combo = nil, imgui.BeginCombo;
imgui.BeginCombo = function(label, ...) real_combo(label, ...); return label == opened; end;
local function draw(page, clicks, combo)
    s.window.tab, MOCK.imgui_calls, opened = page, {}, combo;
    for _, label in ipairs(clicks or {}) do MOCK.clicks[label] = true; end;
    window.draw(s, view, cb);
    MOCK.clicks, opened = {}, nil;
end;
-- Whether a call of kind drew label; TextColored takes its color first.
local function drawn(kind, label)
    for _, call in ipairs(MOCK.imgui_calls) do
        local text = kind == 'TextColored' and call[3] or call[2];
        if call[1] == kind and text == label then return true; end;
    end;
    return false;
end;
local panels = require('ui.panel_frame');
local function editor(id, tab)
    panels.open(id, tab);
    draw('Display');
end;
for _, id in ipairs({ 'self_buffs', 'self_debuffs', 'target', 'party', 'watch' }) do
    editor(id, 'filters');
    assert(drawn('Checkbox', 'Only effects I cast##frame') and drawn('Checkbox', 'Only effects with a known time##frame'),
        'A timer panel keeps Only effects I cast: ' .. id);
    editor(id, 'show');
    assert(drawn('TextUnformatted', 'Members') == (id == 'party') and drawn('Checkbox', 'Party member##member_1002') == (id == 'party'),
        'Members is on Party members\' timers only: ' .. id);
    assert(not drawn('Button', 'Show all members'), 'Clearing every tick shows all, so that needs no button: ' .. id);
    assert(drawn('TextUnformatted', 'Watching') == (id == 'watch'), 'Watching stays on its panel: ' .. id);
end;
for _, id in ipairs({ 'spell_recasts', 'ability_recasts', 'item_recasts' }) do
    editor(id, 'filters');
    assert(drawn('Checkbox', 'Only recasts with a known time##frame'), 'Fixture: the recast filters are drawn: ' .. id);
    assert(not drawn('Checkbox', 'Only effects I cast##frame'), 'A recast panel has no Only effects I cast: ' .. id);
    editor(id, 'show');
    assert(not drawn('TextUnformatted', 'Members'), 'Nor Members: ' .. id);
end;
imgui.BeginCombo = real_combo;
return 'Each panel editor offers only what the panel uses';
