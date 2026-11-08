local app = assert(PREVIEW.addon);
local custom = require('core.customization');
local imgui = require('imgui');
local begin_child = imgui.BeginChild;
imgui.BeginChild = function(label, ...)
    local visible = begin_child(label, ...);
    if label == '##settings_page' then
        PREVIEW.page_scroll = imgui.GetScrollY();
    end;
    return visible;
end;
local s = app.state.settings;
-- This layout stands for saved settings, which a fresh install's first frame never places.
app.state.place_fresh = nil;
s.window.tab, s.window.open = 'Home', true;
s.enabled, s.preview, s.panels.self_buffs.enabled = true, false, false;
s.party_ui.enabled, s.party_ui.preview = false, false;
s.panels.self_buffs.x, s.panels.self_buffs.y, s.panels.self_buffs.filter = 321, 222, 'Haste';
s.panels.target.mode = 'expanded';
-- A custom Target timers look, which a Size pick leaves alone.
s.panels.target.colors = { background = { 0.6, 0.7, 0.8, 1 } };
s.window_style.font_size = PREVIEW.expected_menu_font_size or 16;
for key in pairs(s.window.sections) do if key:sub(1, 5) == 'Home/' then s.window.sections[key] = nil; end; end;
local baseline;
local function now() return custom.history_value(app.state.settings); end;
local function history() return #app.state.history, app.state.history[#app.state.history] and app.state.history[#app.state.history].label; end;
function PREVIEW.capture()
    app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
    baseline = now();
end;
function PREVIEW.check_baseline()
    assert(custom.equal(now(), baseline), 'Undo brings back the starting settings.');
end;
function PREVIEW.check_section(label, open)
    assert(app.state.settings.window.sections['Home/' .. label] == open, 'The real header remembers ' .. label .. ' as ' .. tostring(open));
    assert(custom.equal(now(), baseline) and #app.state.history == 0, 'Opening or closing a section is not a settings change.');
end;
function PREVIEW.check_toggle()
    local current = app.state.settings;
    assert(current.panels.self_buffs.enabled and current.enabled, 'The real checkbox turns Self buffs on.');
    local count, label = history();
    assert(count == 1 and label == 'Self buffs', 'The switch is one Undo step.');
end;
function PREVIEW.check_recast()
    local count, label = history();
    assert(app.state.settings.panels.spell_recasts.enabled and count == 1 and label == 'Spell recasts', 'Spell recasts turns on in one step.');
end;
function PREVIEW.check_party()
    local count, label = history();
    assert(app.state.settings.party_ui.enabled and count == 1 and label == 'Party list buffs', 'Party list buffs turns on in one step.');
end;
function PREVIEW.check_kind()
    local count, label = history();
    assert(app.state.settings.party_ui.effects.kind == 'buff' and count == 2 and label == 'Show buffs or debuffs', 'The real radio button picks Buffs only in one step.');
end;
function PREVIEW.check_size()
    local current = app.state.settings;
    assert(current.style.scale == 1.5, 'A Size button sets the scale.');
    assert(current.panels.self_buffs.x == 321 and current.panels.self_buffs.y == 222 and current.panels.self_buffs.filter == 'Haste'
        and current.panels.target.colors.background[1] == 0.6 and current.window_style.font_size == (PREVIEW.expected_menu_font_size or 16),
        'A Size button keeps positions, filters, colors and the menu text size.');
    local count, label = history();
    assert(count == 1 and label == 'Size 1.5x', 'A Size button is one Undo step.');
end;
local function inside(labels)
    local win = app.state.settings.window;
    for _, label in ipairs(labels) do
        local rect = PREVIEW_PY.item_bounds(label);
        assert(#rect == 4 and rect[1] >= win.x and rect[2] >= win.y
            and rect[3] <= win.x + win.width and rect[4] <= win.y + win.height,
            'Common controls stay inside the visible settings window: ' .. label);
    end;
end;
function PREVIEW.check_look_rows()
    inside({ 'More look', '##main_skin', '1x##main_size' });
end;
function PREVIEW.check_page(name)
    assert(app.state.settings.window.tab == name, 'Real navigation opens ' .. name);
end;
function PREVIEW.check_panel(place)
    assert(require('ui.panel_frame').context() == place, 'Real navigation opens ' .. place);
end;
function PREVIEW.check_top()
    PREVIEW.check_page('Home');
    assert(PREVIEW.page_scroll <= 1, 'Returning to the main page starts at its top instead of inheriting another page scroll.');
end;
return function()
    MOCK.frame(1 / 60);
    PREVIEW.settings = app.state.settings;
    if PREVIEW.frame == PREVIEW.last_frame then
        PREVIEW.check_page('Home');
        inside({ 'Undo', 'Redo', 'Self buffs##main_self_buffs', 'Edit##main_self_buffs' });
        assert(#MOCK.commands == 0);
        PREVIEW.log('Main page switches, folds, Size and navigation passed.');
    end;
end;
