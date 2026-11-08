-- A Skin pick over a custom look asks first. Its Apply and Cancel must sit inside the window.
local app = assert(PREVIEW.addon);
local custom = require('core.customization');
local s = app.state.settings;
-- These settings stand for a player's own, which a fresh install's first frame never places.
app.state.place_fresh = nil;
s.window.tab, s.window.open = 'Home', true;
s.window_style.font_size = PREVIEW.menu_font_size or 17;
s.party_ui.style.icon_art = 'XI View';
s.panels.self_buffs.colors = {text={.2,.4,.6,1}};
local baseline;
local function inside(label)
    local rect, win = PREVIEW_PY.item_bounds(label), app.state.settings.window;
    return #rect == 4 and rect[1] >= win.x and rect[2] >= win.y and rect[3] <= win.x + win.width and rect[4] <= win.y + win.height;
end;
function PREVIEW.capture()
    app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
    baseline = custom.history_value(app.state.settings);
end;
function PREVIEW.asked()
    assert(custom.equal(custom.history_value(app.state.settings), baseline) and #app.state.history == 0,
        'The first click asks and changes nothing.');
    assert(inside('Apply##look_main_skin') and inside('Cancel##look_main_skin'), 'Apply and Cancel are inside the window.');
end;
function PREVIEW.cancelled()
    assert(custom.equal(custom.history_value(app.state.settings), baseline) and #app.state.history == 0, 'Cancel keeps every look.');
end;
function PREVIEW.applied()
    assert(#app.state.history == 1 and app.callbacks.history_status().undo_label == 'Skin: Mint',
        'Apply in the question applies the skin as one Undo step.');
end;
return function()
    MOCK.frame(1 / 60);
    PREVIEW.settings = app.state.settings;
    if PREVIEW.frame == PREVIEW.last_frame then
        PREVIEW.log('Look question asked, cancelled and applied inside the window.');
    end;
end;
