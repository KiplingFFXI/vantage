local defaults, custom = require('ui.defaults'), require('core.customization');
local window, imgui, hud = require('ui.settings_window'), require('imgui'), require('ui.hud');
local panels = require('ui.panel_frame');
local s, view, opened = defaults.make(), hud.sample(100), false;
s.window.open = true;
imgui.SetNextItemOpen = function(value) opened = value; end;
imgui.CollapsingHeader = function() return opened; end;
local reset_scope, transactions, before, after = nil, 0;
local cb = { save = function() return true; end, changed = function(stage)
    if stage == 'before' then before = custom.history_value(s);
    else
        after = custom.history_value(s);
        if not custom.equal(before, after) then transactions = transactions + 1; end;
    end;
end, reset = function(scope) reset_scope = scope; return true; end };
local function frame(page, click)
    s.window.tab, MOCK.imgui_calls = page, {};
    if click then MOCK.clicks[click] = true; end;
    window.draw(s, view, cb);
    assert(#MOCK.font_stack == 0);
    if click then assert(not MOCK.clicks[click], 'The visible control receives input: ' .. click); end;
end;
-- The reset at the foot of a display's tabs, which asks first.
local function reset(id)
    frame('Display', 'Reset this display##frame');
    frame('Display', 'Reset##look_frame_reset_' .. id);
    assert(reset_scope == id, 'Reset goes to ' .. id .. ': ' .. tostring(reset_scope));
end;
local function called(kind, label)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == kind and call[2] == label then return true; end; end;
end;
local function all_locked()
    for _, panel in pairs(s.panels) do assert(panel.locked, 'Preview and visibility keep every panel locked.'); end;
    assert(s.party_ui.locked and s.alerts.notice_locked);
end;
for _, panel in pairs(s.panels) do panel.locked = true; end;
s.party_ui.locked, s.alerts.notice_locked = true, true;
local SAMPLES, SHOW, LOCK = 'Show samples##frame', 'On##frame_display', 'Locked##frame';
s.enabled, s.panels.self_buffs.enabled = false, false;
panels.open('self_buffs', 'show');
frame('Display');
assert(called('Checkbox', SHOW) and not called('Checkbox', 'Show timers and recasts'));
local count = transactions;
frame('Display', SAMPLES);
assert(not s.preview and not s.enabled and not s.panels.self_buffs.enabled and transactions == count, 'Samples turn nothing on.');
s.enabled, s.panels.self_buffs.enabled = true, true;
frame('Display', SAMPLES);
assert(s.preview and transactions == count + 1, 'Samples are one Undo transaction.');
all_locked();
frame('Display', SAMPLES);
assert(not s.preview and s.enabled and s.panels.self_buffs.enabled, 'Ending samples keeps the display available for live data.');
frame('Display', LOCK);
assert(not s.panels.self_buffs.locked and s.party_ui.locked);
frame('Display', LOCK); all_locked();
s.enabled, s.panels.self_buffs.enabled = false, true;
frame('Display', SHOW);
assert(s.enabled and s.panels.self_buffs.enabled, 'A paused panel enables on the first click.');
reset('self_buffs');
assert(not called('Button', 'Reset this page') and not called('Button', 'Free placement'));

s.recast_display, s.enabled = 'combined', false;
s.panels.recasts.enabled = false;
panels.open('recasts', 'show');
frame('Display', SHOW);
assert(s.enabled and s.panels.recasts.enabled);
frame('Display', SAMPLES);
assert(s.preview);
all_locked();
frame('Display', SAMPLES);
reset('recasts');
panels.open('recasts', 'look');
frame('Display');
assert(called('TextUnformatted', 'Ready soon') and not called('TextUnformatted', 'Ending soon'));
panels.open('self_buffs', 'look');
frame('Display');
assert(called('TextUnformatted', 'Ending soon') and not called('TextUnformatted', 'Ready soon'));
s.recast_display, s.enabled = 'separate', false;
panels.open('item_recasts', 'show');
frame('Display', SHOW); assert(s.enabled and s.panels.item_recasts.enabled);
frame('Display', SAMPLES);
assert(s.preview);
frame('Display', SAMPLES);
assert(not s.preview);
all_locked();

panels.open('self_debuffs', 'show');
reset('self_debuffs');
panels.open('recasts');
reset('item_recasts');
s.recast_display = 'combined'; reset('recasts');
s.recast_display = 'separate'; reset('item_recasts');
all_locked();

-- Show on Party list buffs shows the groups switched on, or Your party when none is, and samples then show on them.
panels.open('party_ui', 'show');
for _, strips in ipairs({ { party = false, alliance1 = false, alliance2 = false }, { party = false, alliance1 = true, alliance2 = true } }) do
    s.party_ui.enabled, s.party_ui.preview, s.party_ui.strips = false, false, strips;
    frame('Display', 'Show samples##frame');
    assert(not s.party_ui.enabled and not s.party_ui.preview, 'Samples turn nothing on.');
    frame('Display', SHOW);
    frame('Display', 'Show samples##frame');
    assert(s.party_ui.enabled and s.party_ui.preview);
    assert(s.party_ui.strips.party == not strips.alliance1, 'With every group off Show shows Your party.');
    assert(s.party_ui.strips.alliance1 == strips.alliance1 and s.party_ui.strips.alliance2 == strips.alliance2,
        'The groups already chosen stay saved.');
    assert(not called('Button', 'Preview') and not called('Button', 'Preview pane'));
    all_locked();
    frame('Display', LOCK);
    assert(not s.party_ui.locked and s.panels.self_buffs.locked);
    frame('Display', LOCK);
end;
panels.open('notices', 'show');
frame('Display', 'Locked##frame');
assert(not s.alerts.notice_locked and s.party_ui.locked);
frame('Display', 'Locked##frame'); all_locked();
assert(#MOCK.commands == 0);
