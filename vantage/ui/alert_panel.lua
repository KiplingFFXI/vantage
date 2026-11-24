-- The Alerts display (settings.alerts) on the panel frame: the rules core/alerts.lua runs, one open at a time in the editor
-- under the list, and the notices they put on the screen, which are what the other tabs set.
local conditions_ui = require('ui.condition_settings');
local controls = require('ui.controls');
local defaults = require('ui.defaults');
local frame = require('ui.panel_frame');
local status = require('ui.status_panel');
local page = {};
local ctx = frame.ctx;
local jobs = require('data.shared_ids').jobs;
-- The rule open in the editor, by id, as Undo puts new tables in place. It lasts the session, so nothing here is saved.
local open_rule;
local serial = 0;
-- What the thresholds box holds, while what is typed there can't be read yet. unread marks text with no threshold in it,
-- which goes once the box is left.
local thresholds = { id = nil, unit = nil, list = nil, value = { '' }, unread = false };
local tick = { false };
-- The alerts added this session, or switched to another Alert type while on, with nothing chosen to watch, by id. Each
-- starts off, as nothing chosen means every effect or recast, and the first choice turns it on.
local fresh = {};
local function unset(rule) return fresh[rule.id] and rule.effect == 0 and not rule.enabled; end;

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
local shows_notice = rule_is(function(rule) return rule.visual; end);
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
    -- A copy of an alert with nothing chosen yet has nothing chosen either, so it waits for a choice as that alert does.
    if not template or template.effect == nil or unset(template) then rule.enabled, fresh[id] = false, true; end;
    local rules = ctx.s.alerts.rules;
    c.changed(function()
        rules[#rules + 1] = rule;
        open_rule = id;
    end, true, 'Add alert: ' .. rule.name);
end;

-- Opens a rule in the editor, or closes the editor.
function page.edit(id) open_rule = id; end;

-- The presets, each an alert set up for one thing. Recast ready has no recast yet, so it adds one each time, off until
-- one is chosen.
local presets = {
    { 'Haste ending', { name = 'Haste ending', effect = 33, thresholds = { 30, 10 }, scope = 'self' }, 'Tells you before your Haste wears off.', 'Haste reminder' },
    { 'Sleep ending', { name = 'Sleep ending', effect = 2, thresholds = { 10 }, scope = 'target' }, 'Tells you before the sleep on your target wears off.', 'Sleep reminder' },
    { 'Silenced', require('core.starters').silenced, 'Tells you when you are silenced.', 'Silence notice silenced' },
    { 'Shadows gone', { name = 'Shadows gone', effect = 66, event = 'removed', scope = 'self' }, 'Tells you when your Utsusemi shadows are gone.', 'Copy Image Utsusemi' },
    { 'Recast ready', { name = 'Recast ready', domain = 'recast', event = 'ready', scope = 'self' },
        'Adds an alert for when a recast is ready. It stays off until you choose the recast.', 'A recast is ready' },
};

-- A preset clicked again turns on and opens the alert it added instead of adding a copy. An alert changed since in any
-- of these is the player's own, and the preset adds a new one beside it, unless it's now for anything, as a starter's
-- Sleep ending is, and so covers the preset. Returns false when the alert was there already, and then true if it was
-- off and this turned it back on.
local function add_preset(c, template)
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
for index, entry in ipairs(presets) do
    add_rows[index] = frame.button(entry[1], entry[3], function(c)
        if entry[2].effect == nil then page.new_rule(c, entry[2]); return; end;
        local added, again = add_preset(c, entry[2]);
        if not added then c.note(entry[1] .. (again and ' is on again.' or ' is already on.'), 'done_messages'); end;
    end, { alias = entry[4] });
end;
add_rows[#add_rows + 1] = frame.button('New alert', 'Adds an alert for you to set up below. It stays off until you choose what it watches.', function(c) page.new_rule(c); end, { alias = 'Add alert' });

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
        end, true, 'Delete alert');
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
        c.tip('Undo brings a deleted alert back.');
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
    local first = unset(rule);
    ctx.c.changed(function()
        rule.effect = id;
        if first then rule.enabled = true; end;
    end, true, 'Alert effect');
end;

-- A new alert reads Choose until something is picked, as its 0 would read as every effect.
local function draw_effect(imgui, c, item)
    local rule, recast = rule_of(ctx), rule_of(ctx).domain == 'recast';
    local choose = unset(rule);
    c.effect_picker(recast and 'Recast' or 'Effect', not choose and rule.effect or nil, set_effect, true, rule.domain,
        choose and (recast and 'Choose a recast' or 'Choose an effect') or status.plain_name(c, rule.effect, rule.domain));
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
    imgui.TextColored(ctx.s.style.warning_color, 'Choose an effect for an alert about a missing effect.');
end;

local job_rows = {};
for id, name in ipairs(jobs) do
    local text = tostring(id);
    job_rows[id] = frame.tick(name, nil, 'Runs this alert while this is your main job.', { tag = '_alert',
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
    frame.text('Alert name', 'name', 'A short name that says what it watches.', { of = rule_of, alias = 'Rule name',
        -- A name with nothing to read would leave a blank tick in the list, so it becomes Alert, as a rule with no name does
        -- when the settings are read.
        write = function(c, value) rule_of(c).name = value:find('%S') and value or 'Alert'; end }),
    frame.heading('What'),
    frame.pick('Alert type', 'domain', { 'status', 'recast' }, { status = 'Buff or debuff', recast = 'Recast' }, 'What this alert watches: an effect, or one of your recasts.', {
        of = rule_of,
        write = function(c, value)
            local rule = rule_of(c);
            -- Only an alert that's on, or still waiting for its first choice, waits for one now. One the player turned off stays off.
            fresh[rule.id] = rule.enabled or unset(rule) or nil;
            rule.domain, rule.effect, rule.scope, rule.entity_id = value, 0, 'self', 0;
            rule.event = 'remaining';
            rule.enabled = false;
        end }),
    frame.custom('Effect', nil, draw_effect, { find = 'Effect or recast', alias = 'Recast' }),
    frame.note('It stays off until you choose what it watches.', { only = rule_is(unset) }),
    frame.heading('Who'),
    frame.pick('Who to watch', 'scope', { 'self', 'party', 'alliance', 'target', 'watch', 'all' }, { self = 'Me', party = 'My party, including me', alliance = 'Other alliance parties',
        target = 'Current target', watch = 'Watched enemies', all = 'Anyone Vantage has seen' }, 'Only information the client received can be tracked. Anyone but you goes by estimates: the notice is marked estimated and may arrive after an effect ended early.', {
        of = rule_of, only = for_status, shown_by = 'Alert type', alias = 'Every observed subject',
        write = function(c, value)
            local rule = rule_of(c);
            rule.scope, rule.entity_id = value, 0;
        end }),
    frame.pick('Specific member', 'entity_id', nil, member_names, 'Optional: keeps the alert to one party member.', {
        of = rule_of, only = narrows, shown_by = 'Who to watch', choices_of = member_choices }),
    frame.note('Recast alerts watch your own recasts. A recast the game hasn\'t sent isn\'t counted as ready.', { only = for_recast }),
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
    frame.number('Repeat every', 'repeat_seconds', 0, 3600, 'Seconds between repeats. Zero gives one notice. It repeats while the effect is still missing or below a crossed threshold.', {
        of = rule_of, only = repeats, shown_by = 'Trigger', alias = 'Repeat reminder' }),
    frame.number('Minimum time between repeats', 'cooldown', 0, 3600, 'Seconds before this alert can go off again for the same one and the same application. A threshold still fires as it is crossed.', {
        of = rule_of, only = spaced, shown_by = { 'Trigger', 'Repeat every' } }),
    frame.pick('Combat state', 'combat', { 'any', 'in', 'out' }, { any = 'Any time', ['in'] = 'Only in combat', out = 'Only outside combat' },
        'Keeps this alert to those times. How effects are tracked doesn\'t change.', { of = rule_of, alias = 'Conditions' }),
    frame.fold('Only on these main jobs', 'Leave every job unticked for any job.', { frame.line(nil, nil, job_rows, { every = 6 }) }),
    frame.note(jobs_line, { live = true }),
    -- How it tells you, in groups: a notice, the chat log, the effect's bar and a sound.
    frame.heading('Notice', 'A short notice on the screen. It never sends a game message.', { alias = 'How to alert' }),
    frame.tick('Show a notice', 'visual', 'Shows a short on-screen notice without sending a game message.', { of = rule_of, alias = 'Show local notice' }),
    frame.number('Notice length', 'duration', 1, 30, 'How long its notice, and its bar standing out, stay up.', { of = rule_of }),
    frame.color('Notice color', 'text', 'The color of this alert\'s notice text. From Alerts uses Notice text color, above, for every notice.', {
        of = function(c) local rule = rule_of(c); return rule and rule.notice_colors; end, back = true, only = shows_notice, shown_by = 'Show a notice',
        unset = 'From Alerts', back_word = 'Use Alerts\' color',
        alias = 'Alert text color for this rule', fallback = function(c) return c.s.alerts.notice_colors.text or c.s.style.text_color; end }),
    frame.heading('Chat log'),
    frame.tick('Print in my chat log', 'chat', 'Prints locally. It never sends party, linkshell or other chat messages.', { of = rule_of }),
    frame.heading('Bar', 'Where a timer panel shows the effect.', { only = has_bar, shown_by = 'Trigger' }),
    frame.tick('Make the effect\'s bar stand out', 'emphasis', 'Briefly highlights its bar or icon, where a timer panel shows it.', { of = rule_of, alias = 'Emphasize the effect bar', only = has_bar, shown_by = 'Trigger' }),
    frame.tick('Flash the bar', 'flash', 'Briefly flashes it when this alert goes off.', { of = rule_of, only = stands_out, shown_by = 'Make the effect\'s bar stand out' }),
    frame.color('Flash color', 'flash_color', nil, { of = rule_of, only = flashes, shown_by = 'Flash the bar', fallback = function(c) return c.s.style.warning_color; end }),
    frame.number('Flash length', 'flash_seconds', 0.1, 30, 'How long the bar flash lasts.', { of = rule_of, only = flashes, shown_by = 'Flash the bar', whole = false }),
    frame.heading('Sounds'),
    frame.pick('Sound', 'sound', nil, sound_names, 'Put your WAV or MP3 files in the sounds folder, then refresh the list. No audio is downloaded.', {
        of = rule_of, choices_of = sound_choices, leaves = 'Refresh sounds', alias = 'Local sound' }),
    frame.button('Refresh sounds', 'Reads the sounds folder again.', function(c) c.call('refresh_sounds'); end, { beside = true }),
    frame.note('Sounds folder: ' .. require('core.identity').relative('sounds'), { find = 'Sounds folder', alias = 'Where to put sounds WAV MP3' }),
    frame.number('Volume', 'volume', -1, 100, 'Use -1 to follow Sound volume. Zero mutes this alert\'s sound.', { of = rule_of, only = has_sound, shown_by = 'Sound', special = { [-1] = 'Same as Sound volume' }, alias = 'This rule sound volume' }),
    frame.button('Test this alert', 'Does what this alert does once, so you can check it. With Alerts off or muted its notice doesn\'t show.', function(c) c.call('test_alert', rule_of(ctx)); end),
};

-- Your pet's alerts, kept with the pet display's settings. The Pet display raises them, so they fire only while it's on
-- (methods:refresh in core/pet.lua). Like the rest, they need Alerts on and not muted.
local function pet_of(c) return c.s.pet; end;
local pet_rows = {
    frame.heading('Your pet', 'Alerts about your pet. They all start off.'),
    frame.tick('Tell me when my pet\'s HP is low', 'alert_hp', 'A notice when your pet\'s HP falls to the percent under this or less.', { of = pet_of, alias = 'Pet HP alert notice low' }),
    frame.number('Pet HP is low at', 'alert_hp_percent', 1, 99, 'The HP percent the notice goes by.', {
        of = pet_of, only = function(c) return c.s.pet.alert_hp; end, shown_by = 'Tell me when my pet\'s HP is low' }),
    frame.tick('Tell me when my pet has 1000 TP', 'alert_tp', 'A notice when your pet\'s TP reaches 1000.', { of = pet_of, alias = 'Pet TP alert notice' }),
    frame.tick('Tell me when a charm or a jug pet is about to end', 'alert_ending', 'A notice when a charm\'s estimate or a jug pet\'s time has a minute left.', {
        of = pet_of, alias = 'Charm jug ending alert notice' }),
    frame.problem(function(c) local p = c.s.pet; return not p.enabled and (p.alert_hp or p.alert_tp or p.alert_ending); end,
        'The Pet display is off, so your pet\'s alerts don\'t fire.', 'Turn on the Pet display',
        'Your pet\'s alerts need the Pet display on. It shows while you have a pet out.', 'Tell me when my pet\'s HP is low',
        function(s) s.pet.enabled = true; end),
};

-- The notices' own text. At 0 the size is Text size on the main page, and with no color of its own the text has the
-- shared text color. A rule's Notice color beats the color here.
local text_rows = {
    frame.number('Notice text size', 'notice_text_size', 0, 48, 'How big the text in a notice is. Same as Text size follows Text size on the main page.', {
        special = { [0] = 'Same as Text size' }, alias = 'Alert text size bigger larger smaller font',
        write = function(c, value) c.p.notice_text_size = value == 0 and 0 or math.max(8, value); end }),
    frame.color('Notice text color', 'text', 'The color of the text in a notice. An alert can have a color of its own.', {
        of = function(c) return c.s.alerts.notice_colors; end, back = true, alias = 'Alert text color',
        fallback = function(c) return c.s.style.text_color; end }),
};

local show_rows = {
    frame.group({ frame.note('Alerts are muted, so none of them fires.', { tone = 'problem_messages' }) }, { only = function(c) return c.s.alerts.muted; end }),
    frame.tick('Quiet during cutscenes and while dead', 'quiet_events', 'No notices, chat lines, sounds or flashes during cutscenes and events, or while you are dead.', {
        alias = 'Quiet during events Quiet during cutscenes' }),
    frame.number('Sound volume', 'volume', 0, 100, 'Applies to the sound each rule plays.'),
    frame.group(text_rows),
    frame.line('Add', 'Each preset adds an alert set up for one thing. One clicked again turns its alert back on and opens it.', add_rows, { find = 'Add an alert' }),
    frame.custom('Your alerts', 'Tick an alert to run it. Sounds are always opt-in.', draw_rules, {
        only = function(c) return #c.s.alerts.rules > 0; end, shown_by = 'New alert', alias = 'Your alert rules Rule enabled Edit Done Copy Delete Duplicate rule Delete rule' }),
    frame.group(rule_rows, { only = rule_open, shown_by = { 'Your alerts', 'New alert' } }),
    frame.group(pet_rows),
};

local place_rows = {
    frame.scale_line,
    frame.number('Width', 'notice_width', 240, 900, 'Long messages wrap within this width.', { alias = 'Notice width' }),
    frame.number('Height', 'notice_height', 0, 16000, 'Fit follows what it shows. Any other value is a fixed height, at least 80 pixels and within the game window.', {
        edge = 'y', special = { [0] = 'Fit' }, alias = 'Tallest notice Notice height automatic fixed height resize edges corners Shift left drag',
        write = function(c, value) c.p.notice_height = value == 0 and 0 or math.max(80, value); end }),
    frame.number('Notices shown at once', 'max_notices', 1, 8, 'Shows the most recent notices when many alerts go off together.'),
    frame.resize_note,
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
        return count == 1 and ' This deletes your alert.' or ' This deletes all ' .. count .. ' alerts.';
    end,
});

return page;
