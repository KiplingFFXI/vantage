-- An export pasted back over the very settings it was copied from, through the real vantage.lua, the settings window's
-- Profiles page and its buttons. An export keeps numbers to 14 digits, as a saved file does, so settings changed since
-- they were last read can hold more digits than the export gives back. The preview says nothing changes, so Import and
-- replace, or Import and add, makes no Undo step and no save, the page says nothing changed, and the next Undo takes back
-- the player's own last change.
local store, profiles = require('core.store'), require('core.profiles');
local imgui = require('imgui');
MOCK.screen = { 1920, 1080 };
local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, level = 75, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window = require('ui.settings_window');
rawset(imgui, 'GetClipboardText', function() return MOCK.clipboard; end);
-- Each write of the character's settings file.
local writes, write = 0, store.write;
store.write = function(path, ...)
    if path == app.state.path then writes = writes + 1; end;
    return write(path, ...);
end;
local view = { rows = {}, context = { valid = true, job = 3, entities = {} } };
local function draw(click)
    local s = app.state.settings;
    s.window.open, s.window.tab = true, 'Profiles';
    MOCK.imgui_calls = {};
    if click then MOCK.clicks[click] = true; end;
    window.draw(s, view, app.callbacks);
    assert(not click or not MOCK.clicks[click], 'Fixture: the control is on the page: ' .. tostring(click));
    MOCK.clicks = {};
end;
local function said(text)
    for _, call in ipairs(MOCK.imgui_calls) do
        if (call[1] == 'TextWrapped' or call[1] == 'Text' or call[1] == 'TextColored') and (call[2] == text or call[3] == text) then return true; end;
    end;
    return false;
end;
-- The bullet lines under "Import and replace ... It changes:".
local function mode_preview(mode)
    local lines, on = {}, false;
    local head = mode == 'add' and '^Import and add keeps' or '^Import and replace puts';
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'TextWrapped' then on = tostring(call[2]):find(head) ~= nil;
        elseif on and call[1] == 'BulletText' then lines[#lines + 1] = call[2]; end;
    end;
    return table.concat(lines, ' | ');
end;
-- Whether a and b hold the same, to the 14 digits a saved file or an export keeps.
local function compare(a, b)
    local s1, s2 = store.copy(a), store.copy(b);
    s1.window, s2.window = nil, nil;
    return profiles.same(s1, s2);
end;

local report, wrong = {}, {};
-- One case: change, the player's real last change, made as the settings window makes one. Then the export is copied
-- with the page's own Copy (share_copy) and pasted straight back.
local function case(name, change, kind, id, mode)
    app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
    app.callbacks.changed('before', 'My last change');
    change(app.state.settings);
    app.callbacks.changed('after');
    assert(app.callbacks.save(), name .. ': fixture, the change saves.');
    assert(#app.state.history == 1 and app.state.history[1].label == 'My last change', name .. ': fixture, one Undo step.');
    local mine = store.copy(app.state.settings);
    assert(app.callbacks.share_copy(kind, id), name .. ': fixture, the export copies.');
    draw('Import from clipboard'); draw();
    local preview = mode_preview(mode);
    assert(preview == 'Nothing changes.', name .. ': fixture, the preview says nothing changes: ' .. preview);
    local written = writes;
    draw('Import and ' .. mode .. '##share_' .. mode); draw();
    local done = (mode == 'add' and 'Added from the export.' or 'Replaced with the export.') .. ' Undo takes it back.';
    local nothing = said('Nothing changed, as nothing in the export differs from yours.');
    local status = app.callbacks.history_status();
    local same, saves = compare(mine, app.state.settings), writes - written;
    assert(app.callbacks.undo(), name .. ': Undo runs.');
    local undone = compare(mine, app.state.settings);
    report[#report + 1] = ('%s (%s): page says %s; Undo steps %d, top "%s"; saves %d; settings still mine %s; first Undo took back my change %s'):format(
        name, mode, nothing and '"Nothing changed ..."' or said(done) and ('"' .. done .. '"') or '(neither)', status.undo,
        tostring(status.undo_label), saves, tostring(same), tostring(not undone));
    return nothing and status.undo == 1 and status.undo_label == 'My last change' and saves == 0 and same and not undone;
end;

local function f32(x) local m, e = math.frexp(x); return math.ldexp(math.floor(m * 2 ^ 24 + 0.5) / 2 ^ 24, e); end
-- 1. A fresh install's first session: the change is the font size, a whole number, so only what the install itself
-- holds differs past 14 digits.
if not case('fresh, font size', function(s) s.style.font_size = s.style.font_size + 1; end, 'profile', nil, 'replace') then
    wrong[#wrong + 1] = 'fresh'; end;
-- 2. A color picked for Self buffs' background: ImGui gives back a 32-bit float. One display's export of Self buffs.
if not case('color, one display', function(s)
    s.panels.self_buffs.colors.background = { f32(184 / 255), f32(0.2), f32(0.3), f32(0.5) };
end, 'element', 'self_buffs', 'replace') then wrong[#wrong + 1] = 'element'; end;
-- 3. A color picked, then the whole profile pasted back with Import and add.
if not case('color, whole profile', function(s)
    s.panels.self_buffs.colors.background = { f32(120 / 255), f32(0.45), f32(0.3), f32(0.5) };
end, 'profile', nil, 'add') then wrong[#wrong + 1] = 'profile add'; end;
MOCK.screen = nil;
assert(#wrong == 0, 'An import that changes nothing made an Undo step or a save (' .. table.concat(wrong, ', ') .. '):\n'
    .. table.concat(report, '\n'));
return 'An import that changes nothing makes no step';
