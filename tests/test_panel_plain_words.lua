-- The window says things in plain words. Nothing a player reads on a panel, the main page or a tool page, in a label, a
-- choice, a line or a tooltip, says native, strip, attached, anchor or dock, or stands in for a name with an id, a count
-- of what was left out or a question mark. Nor does a display's name, a kind of export or what a /vg command says.
-- Those words stay only as what finds a row.
local h = require('panel_fixture')();
local defaults, elements = require('ui.defaults'), require('ui.elements');
local imgui = h.imgui;
local banned = { 'native', 'strip', 'strips', 'attached', 'attach', 'anchor', 'anchors', 'anchored', 'dock', 'docked', 'docking', 'unknown' };

local function plain(text, where)
    local lower = (text:match('^(.-)##') or text):lower();
    for _, word in ipairs(banned) do
        assert(not lower:find('%f[%a]' .. word .. '%f[%A]'), where .. ' says ' .. word .. ': ' .. text);
    end;
    assert(not text:find('\226\128\147', 1, true) and not text:find('\226\128\148', 1, true), where .. ' has a long dash: ' .. text);
    assert(not lower:find('%+%d') and not lower:find('and %d+ more') and not lower:find('^%?') and not lower:find(' %? '), where .. ' stands in for what it left out: ' .. text);
    -- A recast's time is fine: Recast 2h. A bare number is an id.
    for _, name in ipairs({ 'entity %d', 'member %d', 'effect %d', 'status %d', 'spell %d', 'ability %d', 'skill %d', 'recast %d+[%s,%.]', 'recast %d+$' }) do
        assert(not lower:find(name), where .. ' shows an id: ' .. text);
    end;
end;

-- Every tooltip draws, as though the mouse were on every control.
imgui.IsItemHovered = function() return true; end;
local shown = { TextUnformatted = 2, TextWrapped = 2, BulletText = 2, TextColored = 3, Text = 2, Checkbox = 2, Button = 2, Selectable = 2, RadioButton = 2, CollapsingHeader = 2,
    BeginCombo = 3, SliderFloat = 6, ColorEdit4 = 2, InputTextWithHint = 3 };
local function read(where)
    for _, call in ipairs(MOCK.imgui_calls) do
        local at = shown[call[1]];
        local text = at and call[at];
        if type(text) == 'string' and text ~= '' then plain(text, where); end;
    end;
end;

local function states(s, mode)
    for _, id in ipairs(defaults.panel_order) do
        local p = s.panels[id];
        p.enabled, p.mode, p.dispel_light, p.gradient, p.bar_style = true, mode, true, true, 'rail';
        p.locked = mode ~= 'bars';
        p.order, p.pinned, p.exclude, p.include = { 33, 60000 }, { [33] = true }, { [33] = true }, { [33] = true };
        p.labels, p.effect_colors, p.members = { [33] = 'Speed' }, { [33] = { 1, 0, 0, 1 } }, { [9901] = true };
    end;
    s.panels.target.anchor.to, s.panels.self_buffs.anchor.to, s.panels.party.anchor.to = 'chat', 'screen', 'party';
    s.watch_ids = { 4101 };
    s.ready_pulse.enabled, s.ready_pulse.spot, s.ready_pulse.ignore = true, 'screen', { [1] = true };
    -- Party list buffs beside the game's list in one state and in panels in the others, with what shows on each.
    local party = s.party_ui;
    party.enabled, party.effects.timers, party.locked = true, true, mode == 'text';
    for group = 1, 3 do party.groups[group].native_detached = mode ~= 'bars'; end;
    party.effects.include, party.effects.exclude, party.effects.pinned = { 33, 60000 }, { 33 }, { 33 };
    s.party_cooldowns.enabled, s.party_cooldowns.list.enabled, s.party_cooldowns.overhead = true, true, true;
    s.party_cooldowns.list.locked, s.party_cooldowns.list.anchor.to = mode == 'text', 'party';
    s.rolls.enabled, s.rolls.locked, s.rolls.anchor.to = true, mode ~= 'text', 'chat';
    local o = s.overhead;
    o.enabled, o.head.offsets = true, { Crab = 1 };
    o.types.mob.layout = ({ bars = 'single', expanded = 'lines', icons = 'split', text = 'single' })[mode];
    o.types.mob.include, o.types.mob.exclude = { 33, 60000 }, { 33 };
    s.pet.enabled, s.pet.locked, s.pet.anchor.to = true, mode == 'text', 'chat';
    s.pet.include, s.pet.exclude = { 33, 60000 }, { 33 };
    -- An alert open with each of what it can say, and a hide rule of each kind, with an effect that has no name.
    local rule = defaults.rule('alert_words');
    rule.emphasis, rule.flash, rule.entity_id, rule.effect = true, true, 9901, 60000;
    rule.domain = mode == 'icons' and 'recast' or 'status';
    rule.event = ({ bars = 'remaining', expanded = 'missing', icons = 'ready', text = 'gain' })[mode];
    s.alerts.enabled, s.alerts.rules = true, { rule };
    require('ui.alert_panel').edit('alert_words');
    local hide = require('core.effect_filters').rule;
    local listed, unnamed, narrow = hide(), hide(), hide();
    listed.effect, unnamed.effect, narrow.enabled, narrow.effect, narrow.scope = 33, 900, false, 900, 'party';
    s.effect_filters.enabled, s.effect_filters.rules = mode ~= 'text', { listed, unnamed, narrow };
end;
for _, mode in ipairs({ 'bars', 'expanded', 'icons', 'text' }) do
    h.fresh(function(s) states(s, mode); end);
    for _, id in ipairs({ 'self_buffs', 'self_debuffs', 'target', 'party', 'watch', 'spell_recasts', 'party_ui', 'overhead', 'cooldown_list', 'rolls', 'pet', 'notices', 'hidden' }) do
        for _, tab in ipairs({ 'show', 'place', 'look', 'filters', 'when' }) do
            h.on(id, tab);
            read(id .. '/' .. tab .. ' ' .. mode);
        end;
    end;
end;
require('ui.alert_panel').edit(nil);

-- And the rows the frame doesn't draw now: every row's label, help and choice, whatever it takes to show it.
local function walk(rows, where)
    for _, item in ipairs(rows) do
        for _, field in ipairs({ 'text', 'help', 'tip' }) do
            if type(item[field]) == 'string' then plain(item[field], where); end;
        end;
        for _, name in pairs(item.names or {}) do plain(name, where); end;
        if item.rows then walk(item.rows, where); end;
    end;
end;
for _, display in ipairs(h.panels._displays) do
    plain(display.name, 'A display name');
    for tab, rows in pairs(display.tabs) do walk(rows, display.id .. '/' .. tab); end;
    walk(display.header, display.id);
    walk(display.under or {}, display.id);
end;

-- The main page and the tool pages, in each state that changes what they say, with an action and an effect the game has
-- no name for on them.
local durations, share = require('core.durations'), require('core.share');
local main_page, timer_page, profile_page = require('ui.main_page'), require('ui.duration_settings'), require('ui.profiles_page');
local function timed(kind, id, mode, name)
    local rule = durations.override();
    rule.kind, rule.id, rule.mode, rule.name = kind, id, mode, name;
    return rule;
end;
local function page(name)
    h.s.window.tab = name;
    h.draw(); h.draw();
    read(name);
end;
local clipboard = '';
rawset(imgui, 'GetClipboardText', function() return clipboard; end);
h.view.context.target = { name = 'Crab' };
-- The client names every spell and ability a player can pick, and not 60000.
local client_resources = AshitaCore.GetResourceManager;
AshitaCore.GetResourceManager = function()
    return setmetatable({ GetSpellById = function(_, id) return id < 60000 and { Name = { 'Cure' } } or nil; end,
        GetAbilityById = function(_, id) return id < 60000 and { Name = { 'Provoke' } } or nil; end }, { __index = client_resources and client_resources() or nil });
end;
for _, mode in ipairs({ 'bars', 'expanded', 'icons', 'text' }) do
    h.fresh(function(s)
        states(s, mode);
        s.enabled, s.alerts.muted, s.edit_mode.grid_mode, s.preview = mode == 'icons', mode ~= 'icons', true, true;
        s.window.sections['Home/More look'], s.window.sections['Home/Colors'] = true, true;
        s.style.window_type = 2;
        s.durations.overrides = { timed('spell', 253, 'fixed', ''), timed('ability', 16, 'add', 'Crab'), timed('effect', 33, 'percent', ''),
            timed('effect', 60000, 'count_up', ''), timed('spell', 60000, 'fixed', ''), timed('ability', 60000, 'fixed', '') };
        s.durations.learned = { ['spell:253:2:crab'] = { samples = { 58, 60 }, unit = 'Crab', at = 5 }, ['ability:60000:60000:'] = { samples = { 30 }, unit = '', at = 5 },
            ['skill:60000:33:crab'] = { samples = { 30 }, unit = 'Crab', at = 5 }, ['pact:60000:33:crab'] = { samples = { 30 }, unit = 'Crab', at = 5 } };
    end);
    page('Home');
    page('Help');
    for number in ipairs(h.s.durations.overrides) do
        timer_page._pick.rule = number;
        page('Durations');
    end;
end;
AshitaCore.GetResourceManager = client_resources;
-- What only shows while edit mode is on, and while /vg hide holds.
MOCK.fire('command', { command = '/vg hide' });
h.app.callbacks.edit_mode(true);
page('Home');
h.app.callbacks.edit_mode(false);
MOCK.fire('command', { command = '/vg show' });
-- Each choice of the main page's lists draws only while it is open.
for _, entry in ipairs(main_page.labels) do
    plain(entry[1], 'The main page');
    if entry[2] then plain(entry[2], 'The main page'); end;
end;
for _, names in ipairs({ require('ui.fonts').labels, require('ui.theme').window_type_labels, require('ui.shared_look').outline_labels }) do
    for _, name in pairs(names) do plain(name, 'A list on the main page'); end;
end;
for _, entry in ipairs(require('core.starters').list) do plain(entry.name, 'A starter'); plain(entry.about, 'A starter'); end;

-- Profiles and sharing: a saved profile, its job link, what waits for Confirm, and every kind of string read back.
h.fresh();
assert(h.app.callbacks.profile_save('Support', false) and h.app.callbacks.profile_save('Raid', false), 'Fixture: saved profiles.');
profile_page.pick('Support');
h.s.job_profiles[3], h.s.job_profiles[4] = 'Support', 'Gone';
page('Profiles');
for _, wait in ipairs({ 'Overwrite##profile_overwrite', 'Delete##profile_delete' }) do
    h.draw(wait); h.draw();
    read('Profiles, ' .. wait);
    h.draw('Cancel profile change');
end;
for _, kind in ipairs(share.kinds) do
    plain(share.kind_names[kind], 'A kind of export');
    h.pick('##Export', share.kind_names[kind] .. '##' .. kind);
    h.draw('Copy##share_copy'); h.draw();
    read('Copying ' .. kind);
    clipboard = MOCK.clipboard;
    h.s.style.font_size, h.s.alerts.volume, h.s.visibility.hide_typing = 20, 10, true;
    h.draw('Import from clipboard'); h.draw();
    assert(h.called('Button', 'Import and add##share_add'), 'A ' .. kind .. ' string can be imported.');
    read('Reading ' .. kind);
    h.draw('Clear##share_clear');
end;
rawset(imgui, 'GetClipboardText', nil);

-- Every string in these files with a space in it is text, or a word in one, whatever state it takes to show it. The rows
-- that use them are read above, and the search keeps its other words on purpose.
local function strings_of(path)
    local file = assert(io.open(ADDON_DIR .. path, 'rb'));
    local source = file:read('*a');
    file:close();
    local found, at = {}, 1;
    while true do
        at = source:find('[-\'"%[]', at);
        if not at then return found; end;
        local mark = source:sub(at, at);
        if source:sub(at, at + 1) == '--' then at = (source:find('\n', at, true) or #source) + 1;
        elseif source:sub(at, at + 1) == '[[' then
            local close = source:find(']]', at, true);
            found[#found + 1] = source:sub(at + 2, close - 1);
            at = close + 2;
        elseif mark == '\'' or mark == '"' then
            local stop = at + 1;
            while source:sub(stop, stop) ~= mark do stop = stop + (source:sub(stop, stop) == '\\' and 2 or 1); end;
            found[#found + 1] = source:sub(at + 1, stop - 1);
            at = stop + 1;
        else at = at + 1; end;
    end;
end;
for _, path in ipairs({ '/vantage.lua', '/core/customization.lua', '/core/share.lua', '/core/profiles.lua', '/core/native_party_ui.lua', '/core/overhead.lua',
    '/ui/main_page.lua', '/ui/duration_settings.lua', '/ui/profiles_page.lua', '/ui/settings_window.lua', '/ui/edit_mode.lua', '/ui/icons.lua', '/ui/party_size_widget.lua', '/core/chat.lua' }) do
    for _, text in ipairs(strings_of(path)) do
        -- No player reads a Lua pattern.
        if text:find(' ', 1, true) and text:sub(1, 1) ~= '^' then plain(text:gsub('%%d', '0'), path); end;
    end;
end;
-- The usage line lists the commands, joined words and all.
local printed = #MOCK.printed;
MOCK.fire('command', { command = '/vg nothing' });
local usage = MOCK.printed[#MOCK.printed];
assert(#MOCK.printed > printed and usage:find('chatsample', 1, true), 'Fixture: an unknown command prints the usage line.');
for _, word in ipairs({ 'native', 'strip', 'attach', 'anchor', 'dock' }) do
    assert(not usage:lower():find(word, 1, true), 'The usage line says ' .. word .. ': ' .. usage);
end;

-- What every display is called.
for _, element in ipairs(elements.list) do plain(element.label, 'Its name'); end;
for _, element in ipairs(elements.movable) do plain(element.label, 'Its name in edit mode'); end;
assert(elements.label('party') == "Party members' timers" and elements.label('watch') == 'Watched enemy timers' and elements.label('recasts') == 'Recasts (one panel)');
MOCK.fire('unload');
return 'The window says everything in plain words, with no ids or stand-ins';
