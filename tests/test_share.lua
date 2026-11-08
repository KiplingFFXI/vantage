-- Exports (core/share.lua, ui/profiles_page.lua): one display, the layout, the shared hide rules, the alert
-- rules or a whole profile as data-only text, "VG:1:<checksum>:<JSON>", through ImGui's clipboard. The text never holds
-- the character's name, ids, file paths or the Windows user name, and leaves out hide rules that name any character.
-- Reading one uses the strict JSON reader and never runs anything, and refuses another version, a bad checksum, text
-- that is too long or too deep and any key the settings don't have, a newer one's in plain words; the entries of a
-- list are cleaned by the tidy. An import shows what Add and Replace would change, and either is one Undo step that
-- tidies every value and keeps your own locks and samples, and one display's switch. Names are looked for in typed
-- text and in sound and font names only, and a quote reads back.
local share, defaults, store, json = require('core.share'), require('ui.defaults'), require('core.store'), require('core.json');
local equal = require('core.customization').equal;
local imgui = require('imgui');
local NAME, MEMBER, OTHER, FRIEND = 'Tester', 3987654321, 3987654322, 'Brightwing';
local user = os.getenv('USERNAME') or 'nobody';

local function fresh() return defaults.tidy(defaults.make()); end;
local function string_of(payload)
    local body = store.encode(payload);
    return 'VG:1:' .. share.crc32(body) .. ':' .. body;
end;

-- The format: prefix, version, checksum, then JSON data.
local s = fresh();
local text, left = share.export(s, 'element', 'rolls', NAME);
assert(type(text) == 'string' and left == nil, 'A display exports.');
local version, sum, body = text:match('^VG:(%d+):(%x+):(.+)$');
assert(version == '1' and #sum == 8 and sum == share.crc32(body), 'Prefix, version 1 and the checksum of the data.');
local payload = json.decode(body);
assert(payload.kind == 'element' and payload.element == 'rolls' and type(payload.data) == 'table', 'Then the data as JSON.');
assert(payload.data.enabled == nil and payload.data.locked == nil and payload.data.preview == nil, 'It leaves out the display\'s switch, lock and samples.');
assert(share.crc32('123456789') == 'cbf43926', 'The checksum is CRC-32.');
for _, kind in ipairs(share.kinds) do
    local exported = share.export(s, kind, 'self_buffs', NAME);
    assert(type(exported) == 'string' and share.read(exported), 'Every kind exports and reads back: ' .. kind);
end;
assert(share.export(s, 'element', 'strip_1', NAME) == nil and share.export(s, 'element', 'nothing', NAME) == nil,
    'Only whole displays export.');

-- Nothing that tells who you are or where your files are.
local private = fresh();
private.panels.self_buffs.title = NAME .. '\'s buffs';
private.panels.party.members = { [MEMBER] = true };
private.watch_ids = { MEMBER };
-- Paths built from their parts, so this file holds none.
local back, home = string.char(92), '/' .. 'home' .. '/';
private.style.font = 'C:' .. back .. 'Users' .. back .. user .. back .. 'Fonts' .. back .. 'mine.ttf';
private.panels.party.title = home .. user .. '/fonts/x.ttf';
private.overhead.head.offsets = { [NAME] = 0.5, Crab = 0.3 };
private.panels.target.labels = { [33] = 'From ' .. user };
local rule = defaults.rule('rule_1'); rule.entity_id, rule.scope = OTHER, 'party';
local plain = defaults.rule('rule_2'); plain.name = 'Haste for ' .. NAME;
private.alerts.rules = { rule, plain };
private.effect_filters.rules = { { enabled = true, effect = 33, kind = 'all', name = NAME, job = 0, scope = 'all' },
    { enabled = true, effect = 40, kind = 'all', name = FRIEND, job = 0, scope = 'party' },
    { enabled = true, effect = 253, kind = 'all', name = '', job = 0, scope = 'all' } };
private = defaults.tidy(private);
for _, kind in ipairs(share.kinds) do
    local exported, note = share.export(private, kind, 'party', NAME);
    assert(exported, 'It exports: ' .. kind);
    local lower = exported:lower();
    assert(not lower:find(NAME:lower(), 1, true) and not lower:find(FRIEND:lower(), 1, true), kind .. ' holds no character name, yours or another\'s.');
    assert(#user < 2 or not lower:find(user:lower(), 1, true), kind .. ' holds no Windows user name.');
    assert(not exported:find(tostring(MEMBER), 1, true) and not exported:find(tostring(OTHER), 1, true), kind .. ' holds no ids.');
    assert(not exported:find(':' .. back, 1, true) and not exported:find(home, 1, true) and not exported:find('mine.ttf', 1, true),
        kind .. ' holds no file paths.');
    if kind == 'alerts' or kind == 'filters' or kind == 'profile' then
        assert(note and note:find('left out', 1, true), kind .. ' says a rule naming one character was left out.');
    end;
end;
local kept = json.decode(share.export(private, 'filters', nil, NAME):match('^VG:1:%x+:(.+)$')).data.effect_filters.rules;
assert(#kept == 1 and kept[1].effect == 253, 'The hide rules that named you and another character are left out whole, never widened.');
assert(select(2, share.export(private, 'filters', nil, NAME)) == '2 rules that name one character were left out.', 'The page says how many.');
local alerts = json.decode(share.export(private, 'alerts', nil, NAME):match('^VG:1:%x+:(.+)$')).data.rules;
assert(#alerts == 1 and alerts[1].id == 'rule_2' and alerts[1].name == '', 'The rule for one member by id is left out, and a name that holds yours is blanked.');
-- Your name is looked for in text you typed, never in the settings' own keys or a choice from a list: a character
-- named Party keeps the party list buffs and party cooldowns in a whole profile, one named Style the looks, and one
-- named Mint the Mint theme. A title that holds the name is still blanked.
local named = fresh();
named.style.theme, named.panels.self_buffs.title = 'Mint', 'Party buffs';
for _, character in ipairs({ 'Party', 'Style', 'Mint' }) do
    local exported, why = share.export(named, 'profile', nil, character);
    assert(exported, character .. ' exports a whole profile: ' .. tostring(why));
    local data = json.decode(exported:match('^VG:1:%x+:(.+)$')).data;
    assert(data.party_ui and data.party_cooldowns and data.style and data.window_style, character .. ': every settings area is in it.');
    assert(data.style.theme == 'Mint', character .. ': the theme picked from the list stays: ' .. tostring(data.style.theme));
    assert(data.panels.self_buffs.title == (character == 'Party' and '' or 'Party buffs'), character .. ': the typed title is checked.');
    local back = share.candidate(fresh(), assert(share.read(exported)), 'replace');
    assert(back.style.theme == 'Mint' and type(back.party_ui) == 'table', character .. ': it reads back whole.');
end;
-- A setting whose JSON needs an escape exports and reads back: a quote in a panel title and in an alert rule's name.
local quoted = fresh();
quoted.panels.self_buffs.title = 'My "main" buffs';
local said = defaults.rule('rule_3'); said.name = 'Haste "short"';
quoted.alerts.rules = { said };
quoted = defaults.tidy(quoted);
for _, case in ipairs({ { 'element', 'self_buffs' }, { 'alerts' }, { 'profile' } }) do
    local exported, why = share.export(quoted, case[1], case[2], NAME);
    assert(exported, case[1] .. ' with a quote in it exports: ' .. tostring(why));
    local back = share.candidate(fresh(), assert(share.read(exported)), 'replace');
    if case[1] ~= 'alerts' then assert(back.panels.self_buffs.title == 'My "main" buffs', case[1] .. ': the title keeps its quote.'); end;
    if case[1] ~= 'element' then assert(back.alerts.rules[1].name == 'Haste "short"', case[1] .. ': the rule keeps its quote.'); end;
end;

-- Refused: another version, a bad checksum, too long, too deep, not JSON, unknown keys.
local good = share.export(s, 'element', 'rolls', NAME);
local function refused(value, words)
    local read, why = share.read(value);
    assert(read == nil and type(why) == 'string' and why:find(words, 1, true), 'Refused (' .. words .. '): ' .. tostring(why));
end;
-- Another version and a key the settings don't have are from a newer Vantage, which the reason says in plain words;
-- the third value names what this Vantage lacks.
local function newer(value, words)
    local read, why, what = share.read(value);
    assert(read == nil and why == 'This was made with a newer Vantage. Update Vantage to read it.' and type(what) == 'string'
        and what:find(words, 1, true), 'Refused as newer (' .. words .. '): ' .. tostring(why) .. ' / ' .. tostring(what));
end;
refused('', 'no text');
refused('Hello there', 'not a Vantage export');
newer(good:gsub('^VG:1:', 'VG:2:'), 'version 2');
local tampered = good:sub(1, -3) .. (good:sub(-2, -2) == '1' and '2' or '1') .. good:sub(-1);
refused(tampered, 'checksum');
refused(good:gsub('^(VG:1:)(%x+)', '%1' .. ('0'):rep(8)), 'checksum');
refused(good .. (' '):rep(share.MOST), 'too long');
local deep = '{"kind":"element","element":"rolls","data":' .. ('['):rep(50) .. (']'):rep(50) .. '}';
refused('VG:1:' .. share.crc32(deep) .. ':' .. deep, 'nested too deeply');
-- A Lua chunk where the data goes is never run.
PWNED = nil;
local chunk = 'return (function() PWNED = true; return {} end)()';
refused('VG:1:' .. share.crc32(chunk) .. ':' .. chunk, 'not readable');
assert(PWNED == nil, 'The text is never loaded or run.');
local source = assert(io.open(ADDON_DIR .. '/core/share.lua', 'rb')):read('*a');
assert(not source:find('loadstring', 1, true) and not source:find('load(', 1, true) and not source:find('dofile', 1, true),
    'The share code has no way to run text.');
refused(string_of({ kind = 'macro', data = {} }), 'does not have');
refused(string_of({ kind = 'element', element = 'radar', data = {} }), 'display this Vantage does not have');
newer(string_of({ kind = 'element', element = 'rolls', data = { x = 5, run = 'os.exit()' } }), 'run');
newer(string_of({ kind = 'element', element = 'rolls', data = { anchor = { to = 'screen', teleport = true } } }), 'anchor.teleport');
newer(string_of({ kind = 'alerts', data = { rules = { { name = 'X', shell = 'rm' } } } }), 'rules.1.shell');
newer(string_of({ kind = 'filters', data = { effect_filters = { rules = { { effect = 1, how = 2 } } } } }), 'how');
newer(string_of({ kind = 'layout', data = { panels = { self_buffs = { x = 5, colour = 1 } } } }), 'colour');
newer(string_of({ kind = 'profile', data = { style = { font_size = 20 }, hacks = {} } }), 'hacks');
newer(string_of({ kind = 'layout', extra = 1, data = {} }), 'extra');
-- A string may hold a lock, which the settings have, but an import keeps your own.
local with_lock = string_of({ kind = 'element', element = 'rolls', data = { x = 77, locked = false, enabled = true } });
local read = assert(share.read(with_lock), 'A lock is a key the settings have.');
local locked = fresh();
local candidate = share.candidate(locked, read, 'replace');
assert(candidate.rolls.x == 77 and candidate.rolls.locked == true and candidate.rolls.enabled == false, 'An import keeps your own lock and switch.');
-- The entries of a list or map are cleaned by the tidy, as a saved setting's are: what isn't one never lands.
read = assert(share.read(string_of({ kind = 'element', element = 'target', data = { include = { ['33'] = true, bad = { deep = 1 } },
    labels = { ['33'] = 'Haste', evil = { 'x' } }, pinned = { 33, { hack = 1 } } } })));
candidate = share.candidate(fresh(), read, 'replace');
local include, labels = candidate.panels.target.include, candidate.panels.target.labels;
assert(include[33] and include.bad == nil and labels[33] == 'Haste' and labels.evil == nil, 'Entries that aren\'t effects are cleaned away.');
for _, value in pairs(candidate.panels.target.pinned) do assert(type(value) ~= 'table', 'A list keeps only its own kind of entry.'); end;

-- A whole profile brings everything but your own locks and samples.
local unlocked = fresh();
unlocked.rolls.locked, unlocked.panels.target.locked, unlocked.alerts.notice_locked, unlocked.party_ui.locked = false, false, false, false;
unlocked.party_cooldowns.list.locked, unlocked.ready_pulse.locked, unlocked.pet.locked = false, false, false;
unlocked.panels.target.width, unlocked.overhead.enabled = 321, true;
local profile = assert(share.read(assert(share.export(unlocked, 'profile', nil, NAME))));
candidate = share.candidate(fresh(), profile, 'replace');
assert(candidate.panels.target.width == 321, 'Fixture: the profile is taken.');
assert(candidate.rolls.locked and candidate.panels.target.locked and candidate.alerts.notice_locked and candidate.party_ui.locked
    and candidate.party_cooldowns.list.locked and candidate.ready_pulse.locked and candidate.pet.locked, 'An import never unlocks a display.');
-- The pet display's options ride in its own string and in a profile, and a string without them gives them on.
do
    local chosen = fresh();
    chosen.pet.effects_as, chosen.pet.show_maneuvers, chosen.pet.blink_icons, chosen.pet.blink_seconds = 'list', false, false, 40;
    for _, made in ipairs({ { 'element', 'pet' }, { 'profile' } }) do
        local took = share.candidate(fresh(), assert(share.read(assert(share.export(chosen, made[1], made[2], NAME)))), 'replace').pet;
        assert(took.effects_as == 'list' and took.show_maneuvers == false and took.blink_icons == false and took.blink_seconds == 40, 'A ' .. made[1] .. ' string carries them.');
    end
    local older = assert(share.read(assert(share.export(chosen, 'element', 'pet', NAME))));
    for _, key in ipairs({ 'effects_as', 'show_maneuvers', 'blink_icons', 'blink_seconds' }) do older.data[key] = nil; end
    local took = share.candidate(fresh(), assert(share.read(string_of(older))), 'replace').pet;
    assert(took.effects_as == 'icons' and took.show_maneuvers == true and took.blink_icons == true and took.blink_seconds == 15, 'One without them gets them on.');
end
-- No string this build writes holds a display's lock, even with every display unlocked: each lock stays with the
-- one who has it. A whole profile that holds them all still reads, and the import keeps yours.
local elements = require('ui.elements');
local lock_names, open_all, written = {}, fresh(), 0;
for _, element in ipairs(elements.list) do
    local holder = elements.lock_holder(open_all, element.id);
    if element.lock and type(holder) == 'table' then lock_names[element.lock], holder[element.lock] = true, false; end;
end;
assert(lock_names.locked and lock_names.notice_locked and not open_all.party_ui.locked and not open_all.alerts.notice_locked
    and not open_all.party_cooldowns.list.locked and not open_all.panels.target.locked, 'Fixture: every display is unlocked.');
local function locks_in(value, path, found)
    for key, inner in pairs(value) do
        if lock_names[key] then found[#found + 1] = path .. key; end;
        if type(inner) == 'table' then locks_in(inner, path .. tostring(key) .. '.', found); end;
    end;
    return found;
end;
for _, kind in ipairs(share.kinds) do
    for _, element in ipairs(kind == 'element' and elements.list or { { id = 'party' } }) do
        local exported = assert(share.export(open_all, kind, element.id, NAME), 'It exports: ' .. kind .. ' ' .. element.id);
        local found = locks_in(json.decode(exported:match('^VG:1:%x+:(.+)$')), '', {});
        assert(#found == 0, kind .. ' ' .. element.id .. ' holds no lock: ' .. table.concat(found, ' '));
        written = written + 1;
    end;
end;
assert(written == #elements.list + 4, 'Every display and the four other kinds are written: ' .. written);
local older = assert(share.read(string_of({ kind = 'profile', data = { rolls = { locked = false }, alerts = { notice_locked = false },
    panels = { target = { locked = false, width = 322 } }, party_ui = { locked = false }, party_cooldowns = { list = { locked = false } },
    ready_pulse = { locked = false }, pet = { locked = false } } })), 'A whole profile that holds locks still reads.');
candidate = share.candidate(fresh(), older, 'replace');
assert(candidate.panels.target.width == 322 and candidate.rolls.locked and candidate.panels.target.locked and candidate.alerts.notice_locked
    and candidate.party_ui.locked and candidate.party_cooldowns.list.locked and candidate.ready_pulse.locked and candidate.pet.locked,
    'and the import keeps your own locks.');
local showing = fresh(); showing.overhead.enabled, showing.overhead.preview = true, true;
candidate = share.candidate(showing, profile, 'replace');
assert(candidate.overhead.enabled and candidate.overhead.preview == true, 'Your samples stay yours.');
local sampling = fresh(); sampling.preview = true;
assert(share.candidate(sampling, profile, 'replace').preview == true and share.candidate(fresh(), profile, 'replace').preview == false,
    'and so does Sample displays for every display.');
newer(string_of({ kind = 'profile', data = { preview = true } }), 'preview');
-- Every value is tidied as a save is.
read = assert(share.read(string_of({ kind = 'element', element = 'rolls', data = { width = 99999, max_rolls = 'many', lucky_color = { 2, -1 } } })));
candidate = share.candidate(fresh(), read, 'replace');
assert(candidate.rolls.width == 1400 and candidate.rolls.max_rolls == fresh().rolls.max_rolls and candidate.rolls.lucky_color[1] == 1
    and candidate.rolls.lucky_color[2] == 0, 'Out of range and wrong values are tidied.');

-- Round trips: each kind, exported from one set of settings and replaced into fresh ones.
local mine = fresh();
mine.rolls.x, mine.rolls.show_odds, mine.rolls.lucky_color = 222, false, { 0.1, 0.2, 0.3, 1 };
mine.rolls.anchor = { to = 'screen', point = 'top_right', dx = -5, dy = 9, element = '', side = 'below', align = 'start', gap = 4, offset = 0 };
mine.rolls.conditions.main_jobs = { [17] = true };
mine.panels.target.width, mine.panels.target.mode, mine.panels.target.include = 333, 'bars', { [33] = true };
mine.alerts.notice_x, mine.alerts.notice_width = 500, 600;
mine.party_cooldowns.list.x, mine.edit_mode.grid = 900, 24;
mine.alerts.rules = { defaults.rule('rule_9') };
mine.alerts.rules[1].name, mine.alerts.rules[1].effect = 'Protect reminder', 40;
mine.effect_filters.rules = { { enabled = true, effect = 253, kind = 'all', name = '', job = 0, scope = 'all' } };
mine = defaults.tidy(mine);
local function round(kind, id) return share.candidate(fresh(), assert(share.read(assert(share.export(mine, kind, id, NAME)))), 'replace'); end;
local got = round('element', 'rolls');
assert(got.rolls.x == 222 and not got.rolls.show_odds and got.rolls.lucky_color[1] == 0.1 and got.rolls.anchor.to == 'screen'
    and got.rolls.anchor.dx == -5 and got.rolls.conditions.main_jobs[17], 'A display brings its look, place, anchor and show conditions.');
got = round('element', 'target');
assert(got.panels.target.width == 333 and got.panels.target.mode == 'bars' and got.panels.target.include[33], 'A panel brings its own filters.');
got = round('element', 'notices');
assert(got.alerts.notice_x == 500 and got.alerts.notice_width == 600 and #got.alerts.rules == 0, 'The notices bring only their place.');
-- Replace puts what the string holds in place of yours: a map such as When to show's zones or the part labels comes
-- whole, never mixed with yours.
local theirs, own = fresh(), fresh();
theirs.panels.target.conditions.zones, theirs.panels.target.field_labels = { dungeon = true }, { name = 'Mob' };
own.panels.target.conditions.zones, own.panels.target.field_labels = { town = true }, { name = 'Foe', target = 'On' };
theirs, own = defaults.tidy(theirs), defaults.tidy(own);
got = share.candidate(own, assert(share.read(assert(share.export(theirs, 'element', 'target', NAME)))), 'replace').panels.target;
assert(equal(got.conditions.zones, { dungeon = true }) and equal(got.field_labels, { name = 'Mob' }),
    'Replace brings a display\'s zones and part labels as the string has them, never mixed with yours.');
got = round('layout');
assert(got.rolls.x == 222 and got.alerts.notice_x == 500 and got.party_cooldowns.list.x == 900 and got.edit_mode.grid == 24
    and got.panels.target.width == 333 and got.rolls.show_odds == true and got.panels.target.mode ~= 'bars', 'A layout brings places, not looks.');
got = round('filters');
assert(#got.effect_filters.rules == 1 and got.effect_filters.rules[1].effect == 253 and got.rolls.x ~= 222, 'Hide rules bring only the hide rules.');
got = round('alerts');
assert(#got.alerts.rules == 1 and got.alerts.rules[1].id == 'rule_9' and got.alerts.notice_x ~= 500, 'Alert rules bring only the rules.');
got = round('profile');
assert(got.rolls.x == 222 and not got.rolls.show_odds and #got.alerts.rules == 1 and got.panels.target.mode == 'bars' and got.edit_mode.grid == 24,
    'A profile brings everything.');

-- Add keeps what you changed and takes the rest; it adds rules after yours.
local yours = fresh();
yours.rolls.x = 10;
yours.alerts.rules = { defaults.rule('rule_1') };
yours.effect_filters.rules = { { enabled = true, effect = 253, kind = 'all', name = '', job = 0, scope = 'all' } };
yours = defaults.tidy(yours);
local function add(kind, id) return share.candidate(yours, assert(share.read(assert(share.export(mine, kind, id, NAME)))), 'add'); end;
got = add('element', 'rolls');
assert(got.rolls.x == 10 and not got.rolls.show_odds and got.rolls.anchor.to == 'screen', 'Add keeps your changed place and takes the rest.');
got = add('layout');
assert(got.rolls.x == 10 and got.alerts.notice_x == 500, 'Add moves only the displays still at their starting spot.');
got = add('alerts');
assert(#got.alerts.rules == 2 and got.alerts.rules[1].id == 'rule_1' and got.alerts.rules[2].id == 'rule_9', 'Add puts the rules after yours.');
yours.alerts.rules[1].name, yours.alerts.rules[1].effect = 'Protect reminder', 40;
got = add('alerts');
assert(#got.alerts.rules == 1, 'and skips one you already have.');
yours.alerts.rules[1].name, yours.alerts.rules[1].effect = 'New alert', 0;
got = add('filters');
assert(#got.effect_filters.rules == 1, 'Add skips a hide rule you already have.');

-- What would change, in plain words.
local lines = share.changes(yours, share.candidate(yours, assert(share.read(share.export(mine, 'element', 'rolls', NAME))), 'replace'));
assert(table.concat(lines, ' '):find('Phantom Roll: ', 1, true), 'The changes name the display: ' .. table.concat(lines, ' | '));
lines = share.changes(yours, share.candidate(yours, assert(share.read(share.export(yours, 'element', 'rolls', NAME))), 'replace'));
assert(#lines == 1 and lines[1] == 'Nothing changes.', 'A string of what you have changes nothing.');
lines = share.changes(yours, share.candidate(yours, assert(share.read(share.export(mine, 'alerts', nil, NAME))), 'add'));
assert(table.concat(lines, ' '):find('Alert rules: 1 rule now, 2 after.', 1, true), 'Rules are counted: ' .. table.concat(lines, ' | '));
-- A key that is a number, as /vg set can leave in the settings, is counted as any other.
local odd = fresh();
odd.alerts[1], odd[1] = 1, 1;
local counted, said = pcall(share.changes, odd, fresh());
assert(counted and table.concat(said, ' '):find('Alerts: 1 setting change.', 1, true),
    'A number key is counted: ' .. tostring(counted and table.concat(said, ' | ') or said));

-- Through the app and Profiles and sharing: copy to the clipboard, read it back, Import and add as one Undo step.
local snapshot = { valid = true, id = 1001, name = NAME, zone = 102, job = 17, level = 75, self_known = true, self_effects = {}, party = {}, entities = {} };
package.loaded['core.client'] = { load = function() end, read = function() return store.copy(snapshot); end };
package.loaded['core.observer'] = { read = function() return {}; end };
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(0);
local window = require('ui.settings_window');
local clipboard;
rawset(imgui, 'GetClipboardText', function() return clipboard; end);
local function draw(click)
    local settings = app.state.settings;
    settings.window.open, settings.window.tab = true, 'Profiles';
    if click then MOCK.clicks[click] = true; end;
    window.draw(settings, { rows = {}, context = { valid = true, entities = {} } }, app.callbacks);
    assert(not click or not MOCK.clicks[click], 'The control is on the page: ' .. tostring(click));
    MOCK.clicks = {};
end;
-- The page starts on a whole profile, and One display on Self buffs.
app.state.settings.panels.self_buffs.width = 444;
rawset(imgui, 'BeginCombo', function(label) return label == '##Export'; end);
rawset(imgui, 'EndCombo', function() end);
draw(); draw('One display##element');
rawset(imgui, 'BeginCombo', nil);
rawset(imgui, 'EndCombo', nil);
draw('Copy##share_copy');
assert(type(MOCK.clipboard) == 'string' and MOCK.clipboard:find('^VG:1:') and not MOCK.clipboard:find(NAME, 1, true),
    'Copy puts one on the clipboard through ImGui.');
assert(#MOCK.commands == 0, 'Nothing is sent to chat or the game.');
app.state.settings = defaults.tidy(defaults.make());
app.state.history, app.state.redo, app.state.transaction = {}, {}, nil;
clipboard = MOCK.clipboard;
draw('Import from clipboard'); draw();
assert(app.state.settings.panels.self_buffs.width ~= 444 and #app.state.history == 0, 'Reading changes nothing.');
local shown = {};
for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'BulletText' then shown[#shown + 1] = call[2]; end; end;
assert(table.concat(shown, ' '):find('Self buffs: 1 setting change.', 1, true), 'The page shows what would change: ' .. table.concat(shown, ' | '));
draw('Import and add##share_add');
assert(app.state.settings.panels.self_buffs.width == 444 and #app.state.history == 1 and app.state.history[1].label == 'Add from an export',
    'Import and add is one Undo step.');
MOCK.fire('command', { command = '/vg undo' });
assert(app.state.settings.panels.self_buffs.width ~= 444, 'Undo takes it back.');
-- A damaged string is refused on the page, and nothing changes.
clipboard = MOCK.clipboard:sub(1, -2) .. 'x';
local before = store.copy(app.state.settings);
draw('Import from clipboard'); draw();
assert(equal(before.panels, app.state.settings.panels) and #app.state.history == 0, 'A refused string changes nothing.');
rawset(imgui, 'GetClipboardText', nil);
MOCK.fire('unload');
return true;
