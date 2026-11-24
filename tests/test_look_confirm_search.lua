-- Apply and Cancel of a look question show only while it waits, so a search while one is up doesn't put them in the
-- search index, where later searches would find buttons that are gone.
local imgui = require('imgui');
local defaults = require('ui.defaults');
local app = dofile(ADDON_DIR .. '/vantage.lua');
local window = require('ui.settings_window');
local index = require('ui.search_index');

local combo, query;
imgui.BeginCombo = function(label) return label == combo; end;
imgui.InputTextWithHint = function(label, _, value)
    if label == '##find_settings' and query ~= nil then value[1], query = query, nil; return true; end;
    return false;
end;
local function frame(click, opened)
    combo = opened;
    MOCK.imgui_calls = {};
    if click then MOCK.clicks[click] = true; end;
    window.draw(app.state.settings, { rows = {}, context = { valid = false } }, app.callbacks);
    if click then assert(not MOCK.clicks[click], 'The control is on screen: ' .. click); end;
    assert(#MOCK.font_stack == 0);
end;
local function drawn(label)
    for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'Button' and call[2] == label then return true; end; end;
    return false;
end;
local function found(text, label)
    for _, result in ipairs(window.search(text)) do if result.tab == 'Home' and result.label == label then return true; end; end;
    return false;
end;

local s = defaults.tidy(defaults.make());
s.overhead.countdown_color = { .2, .4, .6, 1 };
s.window.open, s.window.tab = true, 'Home';
app.state.settings = s;
frame();
-- The question waits, and a search for its words is typed while it does.
frame('Mint##Mint', '##main_skin');
query = 'look';
frame(); frame();
assert(drawn('Apply##look_main_skin') and drawn('Cancel##look_main_skin'), 'Fixture: the question shows Apply and Cancel while the search has text.');
local home = index.controls.Home or {};
assert(home.Apply == nil and home.Cancel == nil, 'Apply and Cancel stay out of the search index: ' .. tostring(home.Apply) .. ', ' .. tostring(home.Cancel));
frame('Cancel##look_main_skin');
query = 'cancel';
frame();
assert(not drawn('Cancel##look_main_skin') and not found('cancel', 'Cancel') and not found('apply', 'Apply'),
    'Once it is answered a search finds no Apply or Cancel on the main page.');
query = '';
frame();
MOCK.fire('unload');
return true;
