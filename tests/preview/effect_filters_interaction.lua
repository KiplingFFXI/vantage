local app = assert(PREVIEW.addon);
local custom = require('core.customization');
local s = app.state.settings;
s.window.tab, s.window.open = 'Home', true;
s.window_style.font_size = 16;
s.enabled, s.preview = false, false;
s.party_ui.enabled = false;
s.party_ui.locked = true;
s.effect_filters = require('core.effect_filters').make();
s.party_ui.effects.exclude = { 6 };
s.panels.self_buffs.include = { [33] = true };
-- Taken once a fresh install has placed its displays (its first refresh with a screen), before any edit.
local original;
local before_enabled;
local function difference(a, b, path)
    if type(a) ~= type(b) then return path .. ': ' .. type(a) .. ' ~= ' .. type(b); end;
    if type(a) ~= 'table' then return a ~= b and (path .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)) or nil; end;
    for key, value in pairs(a) do
        local found = difference(value, b[key], path .. '.' .. tostring(key));
        if found then return found; end;
    end;
    for key in pairs(b) do if a[key] == nil then return path .. '.' .. tostring(key) .. ': missing'; end; end;
end;

function PREVIEW.check_route()
    assert(original, 'The fresh placement is done before Hidden everywhere opens.');
    assert(require('ui.panel_frame').context() == 'hidden/show', 'The main page opens Hidden everywhere.');
    assert(#app.state.settings.effect_filters.rules == 0, 'Navigation cannot hide an effect.');
    assert(app.state.settings.party_ui.locked, 'Opening Hidden everywhere keeps the party lock intact.');
    app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
end;
function PREVIEW.check_sync()
    local rules = app.state.settings.effect_filters.rules;
    assert(#rules == 1 and rules[1].effect == 269 and rules[1].enabled and #app.state.history == 1, 'One click hides what the picker found, in one history entry.');
end;
function PREVIEW.check_added()
    local rules = app.state.settings.effect_filters.rules;
    -- Level Sync is still in the hide picker, so the new rule starts on it. test_effect_filter_settings.lua has one with nothing chosen.
    assert(#rules == 2 and not rules[2].enabled and rules[2].effect == 269, 'The new rule starts on the effect chosen above.');
end;
function PREVIEW.check_rule_effect(effect)
    assert(app.state.settings.effect_filters.rules[2].effect == effect, 'The real rule Effect control sets the rule effect.');
end;
function PREVIEW.check_conditions()
    local rule = app.state.settings.effect_filters.rules[2];
    assert(not rule.enabled and rule.effect == 0 and rule.kind == 'debuff' and rule.name == 'Fennel'
        and rule.job == 3 and rule.scope == 'alliance2', 'Real controls configure the affected member conditions.');
    before_enabled = custom.history_value(app.state.settings);
end;
function PREVIEW.check_enabled()
    assert(app.state.settings.effect_filters.rules[2].enabled);
    assert(app.callbacks.history_status().undo_label == 'Use this rule');
end;
function PREVIEW.check_signet(count)
    local rules, found = app.state.settings.effect_filters.rules, 0;
    for _, rule in ipairs(rules) do if rule.effect == 253 then found = found + 1; end; end;
    assert(found == count and #rules == 2 + count, 'Signet has one rule on the list, or none once it is removed.');
end;
function PREVIEW.check_undo()
    local current = custom.history_value(app.state.settings);
    assert(custom.equal(current, before_enabled), 'Undo restores the configured but disabled rule. '
        .. (difference(current, before_enabled, 'settings') or ''));
end;
function PREVIEW.check_final()
    assert(app.state.settings.effect_filters.rules[2].enabled);
    local current = app.state.settings;
    assert(custom.equal(current.panels, original.panels) and custom.equal(current.party_ui, original.party_ui)
        and custom.equal(current.alerts, original.alerts));
    assert(#MOCK.commands == 0);
end;

return function()
    MOCK.frame(1 / 60);
    if not original and not app.state.place_fresh then original = custom.history_value(app.state.settings); end;
    PREVIEW.settings = app.state.settings;
    if PREVIEW.frame == PREVIEW.last_frame then
        PREVIEW.check_final();
        local win = app.state.settings.window;
        for _, label in ipairs({'##frame_Player name', '##frame_Main job_rule', '##frame_Who', 'Use this rule##frame'}) do
            local rect = PREVIEW_PY.item_bounds(label);
            assert(#rect == 4 and rect[1] >= win.x and rect[2] >= win.y
                and rect[3] <= win.x + win.width and rect[4] <= win.y + win.height,
                'Rule editor control remains inside the visible settings window: ' .. label);
        end;
        PREVIEW.log('Hidden everywhere: main page route, one rule for each effect, recipient rules and Undo/Redo passed.');
    end;
end;
