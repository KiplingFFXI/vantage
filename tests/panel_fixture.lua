-- The real addon over the mock, for the tests of the panels: a save, a frame that clicks, types and picks as a player
-- does, and what that frame drew. It returns one table: fresh(change) starts a save, on(id, tab) opens a panel's tab.
local store, defaults = require('core.store'), require('ui.defaults');

return function()
    local snapshot = { valid = true, id = 1001, name = 'Tester', zone = 102, job = 3, self_known = true, self_effects = {},
        party = {}, entities = {} };
    package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end, resolve = function(id) return { id = id }; end };
    package.loaded['core.observer'] = { read = function() return {}; end };
    local app = dofile(ADDON_DIR .. '/vantage.lua');
    MOCK.fire('load'); app.refresh(0);
    local imgui = require('imgui');
    local h = { app = app, imgui = imgui, window = require('ui.settings_window'), panels = require('ui.panel_frame'), snapshot = snapshot,
        view = { rows = {}, context = { valid = true, job = 3, party = {}, entities = {} } }, typed = {}, slid = {}, previews = {} };

    local begin_combo, input_text, slider = imgui.BeginCombo, imgui.InputText, imgui.SliderFloat;
    imgui.BeginCombo = function(label, preview, ...)
        begin_combo(label, preview, ...);
        h.previews[label] = preview;
        return label == h.combo;
    end;
    imgui.InputText = function(label, box, ...)
        input_text(label, box, ...);
        if h.typed[label] == nil then return false; end;
        box[1], h.typed[label] = h.typed[label], nil;
        return true;
    end;
    imgui.SliderFloat = function(label, box, ...)
        slider(label, box, ...);
        if h.slid[label] == nil then return false; end;
        box[1], h.slid[label] = h.slid[label], nil;
        return true;
    end;

    -- h.s is the live save: Reset and Undo put a new table in its place.
    function h.draw(click)
        h.s = app.state.settings;
        h.s.window.open = true;
        MOCK.imgui_calls, h.previews = {}, {};
        if click then MOCK.clicks[click] = true; end;
        h.window.draw(h.s, h.view, app.callbacks);
        if click then assert(not MOCK.clicks[click], 'The control is on screen: ' .. click); end;
        MOCK.clicks = {};
        h.s = app.state.settings;
        assert(#MOCK.font_stack == 0, 'Each frame balances its fonts.');
    end;
    -- What a test set by hand reaches the rows the next frame.
    function h.bump() app.state.settings_revision = app.state.settings_revision + 1; end;
    function h.fresh(change)
        h.s = defaults.tidy(defaults.make());
        h.s.window.tab = 'Home';
        if change then change(h.s); end;
        app.state.settings, app.state.history, app.state.redo, app.state.transaction = h.s, {}, {}, nil;
        h.bump();
        return h.s;
    end;
    function h.on(id, tab)
        h.panels.open(id, tab);
        h.s.window.tab = 'Display';
        h.draw(); h.draw();
    end;
    -- Opens a combo, picks a choice from it and draws what that leaves.
    function h.pick(label, choice)
        h.combo = label;
        h.draw(choice);
        h.combo = nil;
        h.draw();
    end;
    function h.type(label, text) h.typed[label] = text; h.draw(); h.draw(); end;
    function h.slide(label, value) h.slid[label] = value; h.draw(); h.draw(); end;
    function h.calls(kind, label)
        local found = {};
        for _, call in ipairs(MOCK.imgui_calls) do
            if call[1] == kind and (label == nil or call[2] == label) then found[#found + 1] = call; end;
        end;
        return found;
    end;
    function h.called(kind, label) return #h.calls(kind, label) > 0; end;
    -- Text drawn anywhere on the frame, whole or in part.
    function h.says(text)
        for _, call in ipairs(MOCK.imgui_calls) do
            if (call[1] == 'TextUnformatted' or call[1] == 'TextWrapped' or call[1] == 'Text') and tostring(call[2]):find(text, 1, true) then return true; end;
            if call[1] == 'TextColored' and tostring(call[3]):find(text, 1, true) then return true; end;
        end;
        return false;
    end;
    -- What each control on the frame is called, without its id, and each line of text.
    function h.drawn()
        local names = {};
        for _, call in ipairs(MOCK.imgui_calls) do
            local value = call[1] == 'TextColored' and call[3] or call[2];
            if type(value) == 'string' then names[value:match('^##frame_(.+)$') or value:match('^(.-)##') or value] = true; end;
        end;
        return names;
    end;
    -- The same, over every tab of a display.
    function h.every_tab(id)
        local names = {};
        for _, tab in ipairs(h.panels.tabs) do
            h.on(id, tab.key);
            for name in pairs(h.drawn()) do names[name] = true; end;
        end;
        return names;
    end;
    -- The controls drawn in a grey span, by label. BeginDisabled(false) greys nothing, but its End still counts.
    function h.greyed()
        local grey, spans = {}, {};
        for _, call in ipairs(MOCK.imgui_calls) do
            if call[1] == 'BeginDisabled' then spans[#spans + 1] = call[2] ~= false;
            elseif call[1] == 'EndDisabled' then spans[#spans] = nil;
            elseif type(call[2]) == 'string' then
                for _, on in ipairs(spans) do if on then grey[call[2]] = true; end; end;
            end;
        end;
        assert(#spans == 0, 'Every grey span ends.');
        return grey;
    end;
    return h;
end;
