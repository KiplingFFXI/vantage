-- The Alerts display (settings.alerts) on the panel frame: the rules core/alerts.lua runs, one open at a time in the editor
-- under the list, and the notices they put on the screen, which are what the other tabs set.
local conditions_ui = require('ui.condition_settings');
local controls = require('ui.controls');
local defaults = require('ui.defaults');
local frame = require('ui.panel_frame');
local status = require('ui.status_panel');
local page = {};
local ctx = frame.ctx;
local jobs = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP' };
-- The rule open in the editor, by id, as Undo puts new tables in place. It lasts the session, so nothing here is saved.
local open_rule;
local serial = 0;
-- What the thresholds box holds, while what is typed there can't be read yet. unread marks text with no threshold in it,
-- which goes once the box is left.
local thresholds = { id = nil, unit = nil, list = nil, value = { '' }, unread = false };
local tick = { false };

local function rule_of(c)
    for _, rule in ipairs(c.s.alerts.rules) do
        if rule.id == open_rule then return rule; end;
    end;
end;

-- Whether the open rule passes test. A row under the editor is asked this for the search too, with no rule open.
local function rule_is(test)
    return function(c)
        local rule = rule_of(c);
        return rule ~= nil and test(rule);
    end;
end;

local function rule_open(c) return rule_of(c) ~= nil; end;
local for_status = rule_is(function(rule) return rule.domain ~= 'recast'; end);
local for_recast = rule_is(function(rule) return rule.domain == 'recast'; end);
local counting_down = rule_is(function(rule) return rule.event == 'remaining'; end);
local when_missing = rule_is(function(rule) return rule.event == 'missing'; end);
local missing_nothing = rule_is(function(rule) return rule.event == 'missing' and rule.effect == 0; end);
-- A missing effect, a recast that's ready and an effect that's gone have no row left to light.
local no_bar = { missing = true, ready = true, removed = true };
local has_bar = rule_is(function(rule) return not no_bar[rule.event]; end);
local stands_out = rule_is(function(rule) return rule.emphasis and not no_bar[rule.event]; end);
local flashes = rule_is(function(rule) return rule.emphasis and rule.flash and not no_bar[rule.event]; end);
local repeats = rule_is(function(rule) return rule.event == 'missing' or rule.event == 'remaining'; end);
-- A threshold crossed always fires, so the minimum only spaces out what comes again.
local spaced = rule_is(function(rule) return rule.event == 'missing' or rule.event == 'remaining' and rule.repeat_seconds > 0; end);
local has_sound = rule_is(function(rule) return rule.sound ~= ''; end);
-- Who can be narrowed to one member.
local of_members = { party = true, alliance = true, all = true };
local narrows = rule_is(function(rule) return rule.domain ~= 'recast' and of_members[rule.scope]; end);

-- A new rule, from template if there is one, opens in the editor.
function page.new_rule(c, template)
    serial = serial + 1;
    local id = 'alert_' .. os.time() .. '_' .. serial;
    local rule = defaults.rule(id);
    if template then for key, value in pairs(template) do rule[key] = defaults.copy(value); end; end;
    rule.id = id;
    local rules = ctx.s.alerts.rules;
    c.changed(function()
        rules[#rules + 1] = rule;
        open_rule = id;
    end, true, 'Add alert: ' .. rule.name);
end;

-- Opens a rule in the editor, or closes the editor.
function page.edit(id) open_rule = id; end;

-- The common reminders.
local reminders = {
    { 'Haste reminder', { name = 'Haste ending', effect = 33, thresholds = { 30, 10 }, scope = 'self' }, 'Tells you before your Haste wears off.' },
    { 'Sleep reminder', { name = 'Sleep ending', effect = 2, thresholds = { 10 }, scope = 'target' }, 'Tells you before the sleep on your target wears off.' },
    { 'Silence notice', require('core.starters').silenced, 'Tells you when you are silenced.', 'silenced' },
};

-- A reminder clicked again turns on and opens the rule it added instead of adding a copy. A rule changed since in any of
-- these is the player's own, and the reminder adds a new one beside it, unless it's now for anything, as a starter's Sleep
-- ending is, and so covers the reminder. Returns false when the rule was there already, and then true if it was off and
-- this turned it back on.
local function add_reminder(c, template)
    local made, equal = defaults.rule(), require('core.customization').equal;
    for key, value in pairs(template) do made[key] = value; end;
    for _, rule in ipairs(ctx.s.alerts.rules) do
        local same = true;
        for _, key in ipairs({ 'domain', 'name', 'effect', 'scope', 'event', 'thresholds' }) do
            same = same and (equal(rule[key], made[key]) or key == 'scope' and rule.scope == 'all');
        end;
        if same then
            local off = not rule.enabled;
            if off then c.changed(function() rule.enabled = true; end, true, 'Turn on ' .. rule.name); end;
            open_rule = rule.id;
            return false, off;
        end;
    end;
    page.new_rule(c, template);
    return true;
end;

local add_rows = {};
for index, entry in ipairs(reminders) do
    add_rows[index] = frame.button(entry[1], entry[3], function(c)
        local added, again = add_reminder(c, entry[2]);
        if not added then c.note(entry[1] .. (again and ' is on again.' or ' is already on.'), 'done_messages'); end;
    end, { alias = entry[4] });
end;
add_rows[#add_rows + 1] = frame.button('New alert', 'Adds an alert for you to set up below.', function(c) page.new_rule(c); end, { alias = 'Add alert' });

-- The list of rules. Each row's words are worked out when the settings change; what a click does runs after the rows are
-- drawn, as it changes the list.
local listing = { memo = {}, say = function(c)
    local out = {};
    for index, rule in ipairs(c.s.alerts.rules) do out[index] = { label = rule.name .. '##alert_on', name = rule.name, scope = 'alert_' .. index }; end;
    return out;
end };

local function act(c, kind, rule)
    if kind == 'on' then
        local value = not rule.enabled;
        c.changed(function() rule.enabled = value; end, true, (value and 'Turn on ' or 'Turn off ') .. rule.name);
    elseif kind == 'edit' then
        open_rule = open_rule ~= rule.id and rule.id or nil;
    elseif kind == 'copy' then
        page.new_rule(c, rule);
    else
        local rules = ctx.s.alerts.rules;
        c.changed(function()
            for index, entry in ipairs(rules) do
                if entry == rule then table.remove(rules, index); break; end;
            end;
            if open_rule == rule.id then open_rule = nil; end;
        end, true, 'Delete rule');
    end;
end;

local function draw_rules(imgui, c, item)
    status.caption(imgui, c, item);
    local entries, rules = frame.said(listing), ctx.s.alerts.rules;
    local kind, chosen;
    for index = 1, math.min(#entries, #rules) do
        local entry, rule = entries[index], rules[index];
        imgui.PushID(entry.scope);
        tick[1] = rule.enabled == true;
        if controls.checkbox(imgui, c.look, entry.label, tick) then kind, chosen = 'on', rule; end;
        c.tip('Off, this alert keeps what you set and doesn\'t run.');
        local open = rule.id == open_rule;
        local used = imgui.CalcTextSize(entry.name) + imgui.GetFrameHeight() + 16;
        local buttons = imgui.CalcTextSize('Edit Copy Delete') + 60;
        if used + buttons <= imgui.GetContentRegionAvail() then imgui.SameLine(); end;
        if imgui.Button(open and 'Done##alert' or 'Edit##alert') then kind, chosen = 'edit', rule; end;
        c.tip(open and 'Closes this alert.' or 'Opens this alert below.');
        imgui.SameLine();
        if imgui.Button('Copy##alert') then kind, chosen = 'copy', rule; end;
        c.tip('Adds a copy of this alert and opens it.');
        imgui.SameLine();
        if imgui.Button('Delete##alert') then kind, chosen = 'delete', rule; end;
        c.tip('Undo restores a deleted rule.');
        imgui.PopID();
    end;
    if chosen then act(c, kind, chosen); end;
end;

-- The rule editor's member list reads the party as it is drawn, so a frame builds none of it. The choices are built only
-- while their menu is open.
local function party_of(c) return c.view and c.view.context and c.view.context.party or {}; end;

-- A member's name as the list can show it. Until the game sends it, the client has only the member's id, or nothing.
local function named(name) return type(name) == 'string' and name:find('%a') ~= nil; end;

local member_names = setmetatable({ [0] = 'Everyone in this scope' }, { __index = function(_, id)
    for _, member in ipairs(party_of(ctx)) do
        if member.id == id then return named(member.name) and member.name or 'A party member'; end;
    end;
    return 'Someone not in your party now';
end });

-- Only who the rule's Who to watch reaches, once their name is in.
local function member_choices(c)
    local choices, seen, scope = { 0 }, { [0] = true }, rule_of(c).scope;
    for _, member in ipairs(party_of(c)) do
        if not seen[member.id] and (scope == 'all' or member.scope == scope) and named(member.name) then
            choices[#choices + 1], seen[member.id] = member.id, true;
        end;
    end;
    local saved = rule_of(c).entity_id;
    if not seen[saved] then choices[#choices + 1] = saved; end;
    return choices;
end;

-- A sound is called by its file's name.
local sound_names = setmetatable({ [''] = 'No sound' }, { __index = function(_, name) return name; end });

local function sound_choices(c)
    local choices = { '' };
    local files = c.callbacks.sound_files and c.callbacks.sound_files() or {};
    for _, file in ipairs(files) do choices[#choices + 1] = type(file) == 'table' and file.name or file; end;
    return choices;
end;

local status_events, recast_events = { 'gain', 'remaining', 'removed', 'missing' }, { 'started', 'remaining', 'ready' };
local event_names = { gain = 'Effect gained', remaining = 'Time running low', removed = 'Effect removed / wore off', missing = 'Required effect missing',
    started = 'Recast started', ready = 'Recast ready' };

local function set_effect(id)
    local rule = rule_of(ctx);
    ctx.c.changed(function() rule.effect = id; end, true, 'Rule effect');
end;

local function draw_effect(imgui, c, item)
    local rule = rule_of(ctx);
    c.effect_picker(rule.domain == 'recast' and 'Recast' or 'Effect', rule.effect, set_effect, true, rule.domain, status.plain_name(c, rule.effect, rule.domain));
    frame.lit(c, item);
end;

local function draw_thresholds(imgui, c, item)
    local rule = rule_of(ctx);
    if thresholds.id ~= rule.id or thresholds.unit ~= rule.unit or thresholds.list ~= rule.thresholds then
        thresholds.id, thresholds.unit, thresholds.list, thresholds.unread = rule.id, rule.unit, rule.thresholds, false;
        thresholds.value[1] = table.concat(rule.thresholds, ', ');
        -- A box handed more text than its size writes past its memory, and takes the game with it.
        thresholds.size = math.max(81, #thresholds.value[1] + 1);
    end;
    controls.label(imgui, item.text);
    c.tip(item.help);
    imgui.SetNextItemWidth(-1);
    if imgui.InputText('##thresholds', thresholds.value, thresholds.size) then
        local list, seen, top = {}, {}, rule.unit == 'percent' and 100 or 86400;
        for word in thresholds.value[1]:gmatch('[^,%s]+') do
            local number = tonumber(word);
            -- A rule keeps 16 thresholds at most, as the tidy does (ui/defaults.lua).
            if number and number == math.floor(number) and number > 0 and number <= top and not seen[number] and #list < 16 then
                list[#list + 1], seen[number] = number, true;
            end;
        end;
        if #list > 0 then
            c.changed(function() rule.thresholds = list; end, false, 'Thresholds');
            thresholds.list = list;
        end;
        thresholds.unread = #list == 0;
    end;
    -- Left with nothing it can read, the box shows the rule's thresholds again the next frame, as the rule still uses them.
    if thresholds.unread and not imgui.IsItemActive() then thresholds.id = nil; end;
    frame.lit(c, item);
    c.tip(item.help);
end;

local function draw_warning(imgui)
    imgui.TextColored(ctx.s.style.warning_color, 'Choose a specific effect for a missing-effect rule.');
end;

local job_rows = {};
for id, name in ipairs(jobs) do
    local text = tostring(id);
    job_rows[id] = frame.tick(name, nil, 'Runs this rule while this is your main job.', { tag = '_alert',
        read = function(c)
            local chosen = rule_of(c).jobs;
            return chosen[id] == true or chosen[text] == true;
        end,
        write = function(c, on)
            local chosen = rule_of(c).jobs;
            chosen[id], chosen[text] = on or nil, nil;
        end });
end;

-- Which jobs a rule is kept to, as the fold that ticks them can be shut.
local function jobs_line(c)
    local chosen = rule_of(c).jobs;
    if next(chosen) == nil then return nil; end;
    local names = {};
    for id, job in ipairs(jobs) do
        if chosen[id] == true or chosen[tostring(id)] == true then names[#names + 1] = job; end;
    end;
    return 'Only on ' .. table.concat(names, ', ') .. '.';
end;

local rule_rows = {
    frame.text('Rule name', 'name', 'Use a short name that explains what you want to watch.', { of = rule_of,
        -- A name with nothing to read would leave a blank tick in the list, so it becomes Alert, as a rule with no name does
        -- when the settings are read.
        write = function(c, value) rule_of(c).name = value:find('%S') and value or 'Alert'; end }),
    frame.heading('What'),
    frame.pick('Alert type', 'domain', { 'status', 'recast' }, { status = 'Buff or debuff', recast = 'Recast' }, 'What this rule watches: an effect, or one of your recasts.', {
        of = rule_of,
        write = function(c, value)
            local rule = rule_of(c);
            rule.domain, rule.effect, rule.scope, rule.entity_id = value, 0, 'self', 0;
            rule.event = 'remaining';
        end }),
    frame.custom('Effect', nil, draw_effect, { find = 'Effect or recast', alias = 'Recast' }),
    frame.heading('Who'),
    frame.pick('Who to watch', 'scope', { 'self', 'party', 'alliance', 'target', 'watch', 'all' }, { self = 'Me', party = 'My party, including me', alliance = 'Other alliance parties',
        target = 'Current target', watch = 'Watched enemies', all = 'Anyone Vantage has seen' }, 'Only information the client received can be tracked. Anyone but you goes by estimates: the notice is marked estimated and may arrive after an effect ended early.', {
        of = rule_of, only = for_status, shown_by = 'Alert type', alias = 'Every observed subject',
        write = function(c, value)
            local rule = rule_of(c);
            rule.scope, rule.entity_id = value, 0;
        end }),
    frame.pick('Specific member', 'entity_id', nil, member_names, 'Optional: limit the rule to one known party member.', {
        of = rule_of, only = narrows, shown_by = 'Who to watch', choices_of = member_choices }),
    frame.note('Recast rules watch your own client cooldowns. Unavailable data is not treated as ready.', { only = for_recast }),
    frame.heading('When to alert'),
    frame.pick('Trigger', 'event', status_events, event_names, 'Removal requires evidence. An estimate reaching zero does not prove the effect wore off.', {
        of = rule_of, alias = 'Recast started Recast ready',
        choices_of = function(c) return rule_of(c).domain == 'recast' and recast_events or status_events; end }),
    frame.pick('Threshold unit', 'unit', { 'seconds', 'percent' }, { seconds = 'Seconds remaining', percent = 'Percent remaining' },
        'Percent rules require a known original total. A loaded remaining-time snapshot alone does not provide one.', { of = rule_of, only = counting_down, shown_by = 'Trigger',
        -- No percent is over 100, so a threshold over it goes, and 10 stands in when none is left, as reading the settings does.
        write = function(c, value)
            local rule = rule_of(c);
            rule.unit = value;
            if value ~= 'percent' then return; end;
            local kept = {};
            for _, threshold in ipairs(rule.thresholds) do
                if threshold <= 100 then kept[#kept + 1] = threshold; end;
            end;
            rule.thresholds = #kept > 0 and kept or { 10 };
        end }),
    frame.custom('Thresholds, separated by commas', 'For example: 30, 10, 5. Each threshold fires once per application. Slow frames still detect crossed thresholds.',
        draw_thresholds, { only = counting_down, shown_by = 'Trigger' }),
    frame.note('Missing alerts require a current complete status list. Silence from an enemy is never proof that a buff is absent.', { only = when_missing }),
    { kind = 'custom', draw = draw_warning, only = missing_nothing },
    frame.number('Repeat reminder', 'repeat_seconds', 0, 3600, 'Zero gives one notice. Repeats while the effect is still missing or below a crossed threshold.', { of = rule_of, only = repeats, shown_by = 'Trigger' }),
    frame.number('Minimum time between repeats', 'cooldown', 0, 3600, 'Seconds before this rule can notify again for the same subject and application. A threshold still fires as it is crossed.', {
        of = rule_of, only = spaced, shown_by = { 'Trigger', 'Repeat reminder' } }),
    frame.pick('Combat state', 'combat', { 'any', 'in', 'out' }, { any = 'Any time', ['in'] = 'Only in combat', out = 'Only outside combat' },
        'Restricts this rule without changing how effects are tracked.', { of = rule_of, alias = 'Conditions' }),
    frame.fold('Only on these main jobs', 'Leave every job unticked to use this rule on all jobs.', { frame.line(nil, nil, job_rows, { every = 6 }) }),
    frame.note(jobs_line, { live = true }),
    frame.heading('How to alert'),
    frame.tick('Show a notice', 'visual', 'Shows a short on-screen notice without sending a game message.', { of = rule_of, alias = 'Show local notice' }),
    frame.tick('Print in my chat log', 'chat', 'Prints locally. It never sends party, linkshell or other chat messages.', { of = rule_of }),
    frame.tick('Make the effect\'s bar stand out', 'emphasis', 'Briefly highlights its bar or icon, where a timer panel shows it.', { of = rule_of, alias = 'Emphasize the effect bar', only = has_bar, shown_by = 'Trigger' }),
    frame.tick('Flash the bar', 'flash', 'Briefly flashes it when this rule fires.', { of = rule_of, only = stands_out, shown_by = 'Make the effect\'s bar stand out' }),
    frame.color('Flash color', 'flash_color', nil, { of = rule_of, only = flashes, shown_by = 'Flash the bar', fallback = function(c) return c.s.style.warning_color; end }),
    frame.number('Flash length', 'flash_seconds', 0.1, 30, 'How long the bar flash lasts.', { of = rule_of, only = flashes, shown_by = 'Flash the bar', whole = false }),
    frame.pick('Sound', 'sound', nil, sound_names, 'Put your WAV or MP3 files in ' .. require('core.identity').relative('sounds') .. ', then refresh the list. No audio is downloaded.', {
        of = rule_of, choices_of = sound_choices, leaves = 'Refresh sounds', alias = 'Local sound' }),
    frame.button('Refresh sounds', 'Reads the sounds folder again.', function(c) c.call('refresh_sounds'); end, { beside = true }),
    frame.number('Notice length', 'duration', 1, 30, 'How long a visual notice and emphasis stay visible.', { of = rule_of }),
    frame.number('Volume', 'volume', -1, 100, 'Use -1 to follow Sound volume. Zero mutes this rule\'s sound.', { of = rule_of, only = has_sound, shown_by = 'Sound', special = { [-1] = 'Same as Sound volume' }, alias = 'This rule sound volume' }),
    frame.button('Test this alert', 'Plays the selected outputs once so you can check this rule. With Alerts off or muted its notice doesn\'t show.', function(c) c.call('test_alert', rule_of(ctx)); end),
};

local show_rows = {
    frame.problem(function(c) return c.s.alerts.muted; end, 'Alerts are muted, so none of them fires.', 'Unmute',
        'Notices and sounds come back. Old warnings are not replayed. /vg mute mutes them.', 'Show this display', function(s) s.alerts.muted = false; end),
    frame.tick('Quiet during cutscenes', 'quiet_events', 'No notices, chat lines, sounds or flashes during cutscenes and events, or while you are dead.', { alias = 'Quiet during events' }),
    frame.number('Sound volume', 'volume', 0, 100, 'Applies to the sound each rule plays.'),
    frame.line('Add', 'A reminder clicked again turns its rule back on and opens it.', add_rows, { find = 'Add an alert' }),
    frame.custom('Your alerts', 'Tick an alert to run it. Sounds are always opt-in.', draw_rules, {
        only = function(c) return #c.s.alerts.rules > 0; end, shown_by = 'New alert', alias = 'Your alert rules Rule enabled Edit Done Copy Delete Duplicate rule Delete rule' }),
    frame.group(rule_rows, { only = rule_open, shown_by = { 'Your alerts', 'New alert' } }),
};

local place_rows = {
    frame.locked_line,
    frame.number('Width', 'notice_width', 240, 900, 'Long messages wrap within this width.', { locks = true, alias = 'Notice width' }),
    frame.number('Tallest', 'notice_height', 0, 16000, 'Fit follows what it shows. A fixed height is at least 80 pixels and stays within the game window.', {
        locks = true, edge = 'y', special = { [0] = 'Fit' }, alias = 'Tallest notice Maximum notice height automatic fixed height resize edges corners Shift left drag',
        write = function(c, value) c.p.notice_height = value == 0 and 0 or math.max(80, value); end }),
    frame.number('Notices shown at once', 'max_notices', 1, 8, 'Shows the most recent notices when many rules fire together.'),
};
for _, item in ipairs(frame.place_rows('notices')) do place_rows[#place_rows + 1] = item; end;
place_rows[#place_rows + 1] = frame.put_back;

local header = {
    frame.line(nil, nil, {
        frame.tick('On', 'enabled', 'Runs your alerts. Off, none of them fires and each keeps what you set.', {
            tag = '_display', find = 'Show this display', alias = 'Alerts on Enable alert rules Show this panel display' }),
        frame.lock_row,
    }),
};

frame.register({
    id = 'notices', name = 'Alerts', fold_page = 'Alerts', reset_scope = 'alerts', reset_alias = 'Reset alert settings',
    tabs = { show = show_rows, place = place_rows, when = conditions_ui.rows },
    header = header,
    -- Resetting Alerts takes the whole of settings.alerts, so it says so.
    reset_note = function(c)
        local count = #c.s.alerts.rules;
        if count == 0 then return ''; end;
        return count == 1 and ' This deletes your alert rule.' or ' This deletes all ' .. count .. ' alert rules.';
    end,
});

return page;
