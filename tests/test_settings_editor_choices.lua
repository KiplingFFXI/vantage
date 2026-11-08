local defaults, store, custom = require('ui.defaults'), require('core.store'), require('core.customization');
local window, imgui, hud = require('ui.settings_window'), require('imgui'), require('ui.hud');
local app = dofile(ADDON_DIR .. '/vantage.lua');
app.refresh(0);
local s, input, opened = app.state.settings, {}, false;
s.window.open = true;
s.enabled, s.party_ui.enabled = false, false;
imgui.SetNextItemOpen = function(value) opened = value; end;
imgui.CollapsingHeader = function() return opened; end;
imgui.BeginCombo = function() return true; end;
imgui.InputText = function(label, value)
    if input[label] then value[1], input[label] = input[label], nil; return true; end;
    return false;
end;
local writes, edits = 0, 0;
local original_write, original_changed = store.write, app.callbacks.changed;
store.write = function(...) writes = writes + 1; return original_write(...); end;
app.callbacks.changed = function(stage, label)
    if stage == 'before' then edits = edits + 1; end;
    return original_changed(stage, label);
end;
local function draw(page, click)
    s.window.tab = page;
    if click then MOCK.clicks[click] = true; end;
    window.draw(s, hud.sample(0), app.callbacks);
    if click then assert(not MOCK.clicks[click], 'The selection is reachable: ' .. click); end;
end;
local function browse(page, click, query_label, query)
    local before, old_writes, old_edits = store.copy(s), writes, edits;
    if query_label then input['##' .. query_label] = query; end;
    draw(page, click);
    before.window.tab = page;
    assert(custom.equal(s, before), 'Editor choices cannot change saved settings.');
    assert(writes == old_writes and edits == old_edits, 'Browsing does not write settings or begin an Undo transaction.');
end;

require('ui.panel_frame').open('party_ui', 'filters');
draw('Display');
browse('Display', nil, 'frame_Find an effect', 'Haste');
browse('Display', 'Haste##33');
draw('Display', 'Show only##frame');
assert(s.party_ui.effects.include[1] == 33, 'Edits still apply to the selected effect.');
assert(writes == 1 and edits == 1, 'Each actual edit saves once.');
store.write, app.callbacks.changed = original_write, original_changed;
assert(#MOCK.commands == 0);
return 'Preset and effect browsing stays local; real edits keep their selected context and Undo transaction';
