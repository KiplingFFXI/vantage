local settings = require('ui.defaults').make();
local window, imgui = require('ui.settings_window'), require('imgui');
local summary_calls, fresh_names, fresh_status, requested = 0, 0, 0;
local callbacks = {
    save = function() return true; end, changed = function() end,
    profile_summary = function()
        summary_calls = summary_calls + 1;
        return { names = { 'Support' }, status = { source = 'Support', modified = true } };
    end,
    profile_list = function() fresh_names = fresh_names + 1; return { 'Support' }; end,
    profile_status = function(name)
        fresh_status = fresh_status + 1; requested = name;
        return { token = 'fresh-token', source = 'Support' };
    end,
};
settings.window.open, settings.window.tab = true, 'Profiles';
imgui.BeginCombo = function() return true; end;
imgui.CollapsingHeader = function() return false; end;
local function draw(click)
    if click then MOCK.clicks[click] = true; end;
    window.draw(settings, { rows = {}, context = {} }, callbacks);
    assert(#MOCK.font_stack == 0);
end;
draw(); draw();
assert(summary_calls == 2 and fresh_names == 0 and fresh_status == 0, 'Profile display uses one combined summary per draw.');
draw('Support'); draw('Overwrite##profile_overwrite');
assert(fresh_status == 1 and requested == 'Support', 'Overwrite confirmation obtains a fresh token for the selected saved file.');
draw('Cancel profile change'); draw('Delete##profile_delete');
assert(fresh_status == 2 and requested == 'Support', 'Delete confirmation also bypasses the display cache.');
settings.window.open = false; draw();
assert(summary_calls == 6, 'Closing settings stops profile summary polling.');
return true;
