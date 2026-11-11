-- Exports: one display, where every display is, the Hidden everywhere list, the alert rules or a whole profile,
-- as text to copy and import. The text is the prefix VG, the version, a checksum of the data and then the data as JSON:
-- "VG:1:1a2b3c4d:{...}". It is data only. Reading it uses the strict JSON reader and never loads or runs anything, and
-- refuses another version, a checksum that doesn't match, text past share.MOST and any key the settings don't have.
-- It finds the string in what chat adds around it. The entries of a list or map, such as the effect ids a panel
-- shows, are cleaned by the tidy like a saved setting's.
-- An import is tidied like every saved setting, and keeps your own locks, samples and on and off switches of single
-- displays. The text never holds your character's name, character or entity ids, file paths or your Windows name, and
-- leaves out every hide rule that names a character. A whole profile also leaves out the names of the other
-- characters with settings on this PC. Names are looked for in text you typed and in sound and font names, not in the
-- settings' own keys or choices, so a character named Party keeps the party list buffs.
-- The text holds no display's lock either.
-- Replace puts what the string holds in place of yours; Add keeps what you changed and takes the rest, or adds the
-- string's rules after yours. This file builds and reads the text, and writes and reads it as a file in the shared
-- folder; Profiles and sharing copies and imports it.
local share = {};
local json = require('core.json');
local store = require('core.store');
local bit = require('bit');
local copy = store.copy;

share.PREFIX, share.VERSION, share.MOST, share.DEEPEST = 'VG', 1, 262144, 40;
share.kinds = { 'profile', 'element', 'layout', 'filters', 'alerts' };
share.kind_names = { element = 'One display', layout = 'Where everything is', filters = 'Hidden everywhere list',
    alerts = 'Alert rules', profile = 'Whole profile' };
share.modes = { 'add', 'replace' };
-- What a string from another version or with a setting Vantage doesn't have says.
share.NEWER = 'This was made with a newer Vantage. Update Vantage to read it.';

-- CRC-32 of the data, as eight hex digits.
local crc_table;
local function crc32(text)
    if not crc_table then
        crc_table = {};
        for index = 0, 255 do
            local value = index;
            for _ = 1, 8 do
                value = bit.band(value, 1) == 1 and bit.bxor(bit.rshift(value, 1), 0xEDB88320) or bit.rshift(value, 1);
            end
            crc_table[index] = value;
        end
    end
    local crc = 0xFFFFFFFF;
    for index = 1, #text do
        crc = bit.bxor(bit.rshift(crc, 8), crc_table[bit.band(bit.bxor(crc, text:byte(index)), 0xFF)]);
    end
    return bit.tohex(bit.bnot(crc), 8);
end
if VANTAGE_TEST_MODE then share.crc32 = crc32; end

-- What each kind of display holds that stays with the one who imports: its switch, lock and samples, and the members
-- a panel shows.
local function own_fields(id)
    if id == 'party_ui' then return { enabled = true, strips = true, preview = true, locked = true }; end
    if id == 'cooldown_list' then return { enabled = true, preview = true }; end
    return { enabled = true, locked = true, preview = true, members = true };
end

local notice_keys = { 'notice_x', 'notice_y', 'notice_width', 'notice_height', 'max_notices', 'notice_anchor', 'notice_conditions' };
local box_keys = { 'x', 'y', 'width', 'height', 'anchor' };

-- The settings an element's string holds, from settings. whole takes the notices' lock too.
local function element_root(settings, id, whole)
    local elements = require('ui.elements');
    local element = elements.by_id[id];
    if not element or element.strip then return nil; end
    if element.panel then return settings.panels[id]; end
    if id == 'notices' then
        local out = {};
        for _, key in ipairs(notice_keys) do out[key] = settings.alerts[key]; end
        if whole then out.notice_locked = settings.alerts.notice_locked; end
        return out;
    end
    if id == 'cooldown_list' then return settings.party_cooldowns; end
    if id == 'pulse' then return settings.ready_pulse; end
    return settings[id];
end

-- An element's data without what stays with the one who imports.
local function without_own(out, id)
    for key in pairs(own_fields(id)) do out[key] = nil; end
    if id == 'notices' then out.notice_locked = nil; end
    if id == 'cooldown_list' and type(out.list) == 'table' then out.list.enabled, out.list.locked = nil, nil; end
    return out;
end

-- whole keeps what stays with the one who imports, for the shape a string is checked against: a string may hold it,
-- and an import keeps the importer's own.
local function element_data(settings, id, whole)
    local root = element_root(settings, id, whole);
    if type(root) ~= 'table' then return nil; end
    if whole then return copy(root); end
    return without_own(copy(root), id);
end

-- Every display's place and size, its anchor, the party list strips' placement and the edit mode grid.
local function layout_data(settings)
    local profiles = require('core.profiles');
    local out = { panels = {}, notices = {}, cooldown_list = {}, pulse = {}, rolls = {}, pet = {} };
    for id, panel in pairs(settings.panels) do
        out.panels[id] = {};
        for field in pairs(profiles.positions) do out.panels[id][field] = copy(panel[field]); end
    end
    for _, key in ipairs(notice_keys) do if key ~= 'notice_conditions' and key ~= 'max_notices' then out.notices[key] = copy(settings.alerts[key]); end end
    for _, key in ipairs(box_keys) do
        out.cooldown_list[key] = copy(settings.party_cooldowns.list[key]);
        out.rolls[key], out.pet[key] = copy(settings.rolls[key]), copy(settings.pet[key]);
    end
    for _, key in ipairs({ 'x', 'y', 'spot', 'size', 'anchor' }) do out.pulse[key] = copy(settings.ready_pulse[key]); end
    out.party_ui = profiles.party_placement(settings.party_ui);
    out.edit_mode = copy(settings.edit_mode);
    out.placement_screen = copy(settings.placement_screen);
    return out;
end

local function profile_data(settings, whole)
    local out = require('core.profiles').capture(settings);
    if whole then return out; end
    -- Each display's lock stays with the one who has it, so the string holds none.
    local elements = require('ui.elements');
    for _, element in ipairs(elements.movable) do
        local holder = elements.lock_holder(out, element.id);
        if element.lock and type(holder) == 'table' then holder[element.lock] = nil; end
    end
    out.party_ui = element_data(settings, 'party_ui');
    out.party_ui.enabled, out.party_ui.strips = settings.party_ui.enabled, copy(settings.party_ui.strips);
    return out;
end

local function data_of(settings, kind, id, whole)
    if kind == 'element' then return element_data(settings, id, whole); end
    if kind == 'layout' then return layout_data(settings); end
    if kind == 'filters' then return { effect_filters = copy(settings.effect_filters) }; end
    if kind == 'alerts' then return { rules = copy(settings.alerts.rules) }; end
    if kind == 'profile' then return profile_data(settings, whole); end
end

-- The shape a list of records takes, by the key that holds it: alert and hide rules, and duration overrides.
local function item_template(key, parent)
    if key == 'rules' then
        if parent == 'effect_filters' then return require('core.effect_filters').rule(); end
        return require('ui.defaults').rule('rule_1');
    end
    if key == 'overrides' then return require('core.durations').override(); end
end

local function record(value)
    if type(value) ~= 'table' or next(value) == nil then return false; end
    for key in pairs(value) do if type(key) == 'string' then return true; end end
    return false;
end

-- Walks data beside template. A record (a table with names) takes only the keys its template has, and a list of
-- records takes its items' shape from the template's first item or item_template. Any other table is a list or map
-- of values, which tidy cleans. prune drops what template doesn't have; otherwise the first such key is returned.
local function walk(data, template, path, prune, parent)
    if type(data) ~= 'table' or type(template) ~= 'table' then return nil; end
    if record(template) then
        for key, value in pairs(data) do
            local name = tostring(key);
            if template[key] == nil then
                if prune then data[key] = nil; else return path .. name; end
            else
                local found = walk(value, template[key], path .. name .. '.', prune, name);
                if found then return found; end
            end
        end
        return nil;
    end
    local item = type(template[1]) == 'table' and template[1] or item_template(parent, path:match('([%w_]*)%.[%w_]+%.$') or '');
    if type(item) == 'table' then
        for key, value in pairs(data) do
            if type(value) == 'table' then
                local found = walk(value, item, path .. tostring(key) .. '.', prune, nil);
                if found then return found; end
            elseif prune then data[key] = nil;
            else return path .. tostring(key); end
        end
    end
    return nil;
end

-- The template a kind's data is checked against: the same data from fresh settings, which have no placed screen yet.
local function template_of(kind, id)
    local fresh = require('ui.defaults').make();
    local template = data_of(fresh, kind, id, true);
    if type(template) == 'table' and (kind == 'layout' or kind == 'profile') then template.placement_screen = { width = 0, height = 0 }; end
    return template;
end

-- Text that would tell where your files are: a backslash, a drive, or a path from the root or your home folder.
local function path_like(value)
    return type(value) == 'string' and (value:find('\\', 1, true) or value:find('%a:/') or value:match('^/[^/%s]+/')
        or value:match('^~/')) ~= nil;
end

-- Where name is in text, from init on, as a whole word: with no letter right before or after it. A byte past 127, part
-- of a letter outside A to Z in UTF-8, counts as a letter. A digit doesn't, as FFXI names have none, so "Ayame2" holds
-- Ayame, and a name that ends in an accented letter is still found.
local function whole_word(text, name, init)
    local from, to = text:find(name, init or 1, true);
    while from do
        if not text:sub(from - 1, from - 1):find('[%a\128-\255]') and not text:sub(to + 1, to + 1):find('[%a\128-\255]') then
            return from, to;
        end
        from, to = text:find(name, from + 1, true);
    end
end

-- Text that holds one of names, your character's names, as a whole word.
local function named(value, names)
    if type(value) ~= 'string' then return false; end
    local lower = value:lower();
    for _, name in ipairs(names) do
        if #name >= 2 and whole_word(lower, name:lower()) then return true; end
    end
    return false;
end

-- Where the settings take text you type: fresh settings with one alert rule, hide rule and duration override, every
-- string set to MARK, then tidied. A choice from a list goes back to what tidy picks; typed text, such as a title, a
-- rule's name or a font, keeps MARK. Worked out once, then each kind's data of it.
local MARK = 'vantagesharemark';
local marked_settings;
local function marked()
    local defaults = require('ui.defaults');
    local value = defaults.make();
    value.alerts.rules, value.effect_filters.rules = { defaults.rule('rule_1') }, { require('core.effect_filters').rule() };
    value.durations.overrides = { require('core.durations').override() };
    local function mark(node)
        for key, child in pairs(node) do
            if type(child) == 'string' then node[key] = MARK; elseif type(child) == 'table' then mark(child); end
        end
    end
    mark(value);
    -- A display ticked for Grid mode is a choice from a list, by its id.
    value.edit_mode.grid_displays = { require('ui.elements').movable[1].id };
    return value;
end
local function typed_of(kind, id)
    if not marked_settings then
        local ok, kept = pcall(require('ui.defaults').tidy, marked());
        -- Were tidy to fail, every string would count as typed.
        marked_settings = ok and type(kept) == 'table' and kept or marked();
    end
    return data_of(marked_settings, kind, id, true);
end

-- Blanks each string that would tell who you are or where your files are, and drops each such key; with find, only
-- says whether there is one. A path is looked for everywhere. Your names are looked for in text you typed (MARK in
-- typed, the same data from typed_of), in sound and font names, which tidy reads as choices though each can be a
-- file you named, and in the entries of lists and maps, never in the settings' own keys, a key that reads as a number,
-- which is an id, or a choice from a list, which a character can share a name with.
local function scrub(value, typed, names, find)
    if type(value) ~= 'table' then return false; end
    local fields = record(typed);
    local item = not fields and type(typed) == 'table' and typed[1] or nil;
    for key, child in pairs(value) do
        local shape = fields and typed[key] or item;
        if path_like(key) or not (fields and typed[key] ~= nil) and not tonumber(key) and named(key, names) then
            if find then return true; end
            value[key] = nil;
        elseif type(child) == 'string' then
            if path_like(child) or (shape == nil or shape == MARK or key == 'sound' or key == 'font') and named(child, names) then
                if find then return true; end
                value[key] = '';
            end
        elseif scrub(child, shape, names, find) then return true; end
    end
    return false;
end

-- Rules that would reach further without a name or id they hold, which a string can't carry: an alert rule for one
-- member by id, a hide rule that names a character, yours or anyone's, and a duration override only on one of the
-- characters in names, which scrub would blank to one on everyone. An override on a mob keeps its name.
local function narrow_rules(data, names)
    local left = 0;
    local function keep(rules, test)
        if type(rules) ~= 'table' then return rules; end
        local out = {};
        for _, rule in ipairs(rules) do
            if type(rule) == 'table' and test(rule) then out[#out + 1] = rule; else left = left + 1; end
        end
        return out;
    end
    local alerts = data.rules and data or type(data.alerts) == 'table' and data.alerts;
    if alerts then alerts.rules = keep(alerts.rules, function(rule) return (tonumber(rule.entity_id) or 0) == 0; end); end
    local filters = type(data.effect_filters) == 'table' and data.effect_filters;
    if filters then filters.rules = keep(filters.rules, function(rule) return type(rule.name) ~= 'string' or rule.name == ''; end); end
    local durations = type(data.durations) == 'table' and data.durations;
    if durations then durations.overrides = keep(durations.overrides, function(rule) return not named(rule.name, names); end); end
    return left;
end

-- Your Windows user name in UTF-8, as text typed in the settings window is. os.getenv gives it in the ANSI code page,
-- where an accented letter is another byte, so it is read from Windows as it is kept and turned into UTF-8; os.getenv's
-- is the fallback.
local function windows_name()
    local read, name = pcall(function()
        local ffi = require('ffi');
        if ffi.os ~= 'Windows' then return nil; end
        pcall(ffi.cdef, 'unsigned long __stdcall GetEnvironmentVariableW(const unsigned short*, unsigned short*, unsigned long);');
        pcall(ffi.cdef, 'int __stdcall WideCharToMultiByte(unsigned int, unsigned long, const unsigned short*, int, char*, int, const char*, int*);');
        local key, wide = ffi.new('unsigned short[9]', { 85, 83, 69, 82, 78, 65, 77, 69, 0 }), ffi.new('unsigned short[257]');
        local length = tonumber(ffi.C.GetEnvironmentVariableW(key, wide, 257));
        if not length or length < 1 or length > 256 then return nil; end
        local size = tonumber(ffi.C.WideCharToMultiByte(65001, 0, wide, length, nil, 0, nil, nil));
        if not size or size < 1 then return nil; end
        local text = ffi.new('char[?]', size);
        if tonumber(ffi.C.WideCharToMultiByte(65001, 0, wide, length, text, size, nil, nil)) ~= size then return nil; end
        return ffi.string(text, size);
    end);
    if read and type(name) == 'string' and name ~= '' then return name; end
    local user = os.getenv and os.getenv('USERNAME');
    if type(user) == 'string' and user ~= '' then return user; end
end
if VANTAGE_TEST_MODE then share.windows_name = windows_name; end

-- The names a string must not hold: your character's, and your Windows user name.
local function private_names(character)
    local names = {};
    if type(character) == 'string' and character ~= '' then names[#names + 1] = character; end
    local user = windows_name();
    if user then names[#names + 1] = user; end
    return names;
end

-- The names of the characters with settings on this PC: each has a folder named after it and its id in folder, the
-- settings folder. Which listing of Ashita's gives a folder's folders isn't known here, so it is asked three ways, and
-- an entry counts as the folder it starts with, so a file listed inside one counts too.
function share.local_names(folder)
    local names, seen = {}, {};
    local function add(ok, found)
        for _, entry in ipairs(ok and type(found) == 'table' and found or {}) do
            local first = type(entry) == 'string' and entry:match('^[\\/]*([^\\/]+)');
            local name = first and first:match('^([%w_%-]+)_%d+$');
            if name and not seen[name:lower()] then seen[name:lower()], names[#names + 1] = true, name; end
        end
    end
    add(pcall(ashita.fs.get_directory, folder));
    add(pcall(ashita.fs.get_directory, folder, '.*', true));
    add(pcall(ashita.fs.get_directory, folder, '.*', false));
    return names;
end

-- Your names and those of the other characters with settings on this PC, which a whole profile and its file leave out.
local function all_names(character)
    local names = private_names(character);
    local ok, folder = pcall(require('core.identity').root);
    for _, name in ipairs(ok and share.local_names(folder) or {}) do names[#names + 1] = name; end
    return names;
end

-- The string for kind (and the display id for one display), or nil and why. The second value says what was left out.
function share.export(settings, kind, id, character)
    local elements = require('ui.elements');
    if kind == 'element' and not (elements.by_id[id] and not elements.by_id[id].strip) then return nil, 'Choose a display to share.'; end
    local data = data_of(settings, kind, id);
    if type(data) ~= 'table' then return nil, 'Choose what to share.'; end
    local names = kind == 'profile' and all_names(character) or private_names(character);
    local left = narrow_rules(data, names);
    walk(data, template_of(kind, id), '', true);
    local typed = typed_of(kind, id);
    scrub(data, typed, names);
    local payload = { kind = kind, data = data };
    if kind == 'element' then payload.element = id; end
    local ok, body = pcall(store.encode, payload);
    if not ok then return nil, 'Those settings could not be written as an export.'; end
    local text = share.PREFIX .. ':' .. share.VERSION .. ':' .. crc32(body) .. ':' .. body;
    if #text > share.MOST then return nil, 'Those settings are too long for an export.'; end
    -- A last look, at the data as a reader reads it back.
    local read, back = pcall(json.decode, body);
    if not read or type(back) ~= 'table' or scrub(back.data, typed, names, true) then
        return nil, 'The export would hold your name or a file path, so it was not made.';
    end
    return text, left > 0 and (left == 1 and '1 rule that names one character was left out.' or left .. ' rules that name one character were left out.') or nil;
end

-- How deep the data's brackets go, outside strings, so the reader never meets more than share.DEEPEST.
local function depth(body)
    local deepest, current, quoted, escaped = 0, 0, false, false;
    for index = 1, #body do
        local character = body:sub(index, index);
        if quoted then
            if escaped then escaped = false;
            elseif character == '\\' then escaped = true;
            elseif character == '"' then quoted = false; end
        elseif character == '"' then quoted = true;
        elseif character == '{' or character == '[' then
            current = current + 1;
            if current > deepest then deepest = current; end
        elseif character == '}' or character == ']' then current = current - 1; end
    end
    return deepest;
end

-- What chat and Discord add around a pasted string: text before and after it, code marks (`), quote marks (> ) and
-- line breaks. The string is taken from its VG: to the last }, without those marks before its data. The last } is
-- looked for from the start only: unanchored, text with none would take time by the square of its length.
local function unwrap(text)
    local from, to = text:find(share.PREFIX .. ':[`>%s]*%d'), text:match('^.*()}');
    if not from or not to or to < from then return nil; end
    local head, body = text:sub(from, to):match('^(.-)({.*)$');
    if not head then return nil; end
    return (head:gsub('[`>%s]', '')) .. body;
end

-- Reads a pasted string. Returns its payload ({ kind, element, data }), or nil and why. A string from a newer Vantage
-- says so in plain words; a third value then names what this one doesn't have.
function share.read(text)
    if type(text) ~= 'string' or text:match('^%s*$') then return nil, 'The clipboard holds no text.'; end
    if #text > share.MOST then return nil, 'That text is too long to be an export.'; end
    -- Trimmed a step at a time: the pattern '^%s*(.-)%s*$' takes time by the square of a long run of spaces inside.
    local first, last = text:find('%S'), #text;
    while text:find('^%s', last) do last = last - 1; end
    text = text:sub(first, last);
    local header = '^' .. share.PREFIX .. ':(%d+):(%x+):(.*)$';
    local version, sum, body = text:match(header);
    -- Text that doesn't read as it is may be a string chat wrapped; the checksum still finds any other change.
    if not version or #sum ~= 8 or crc32(body) ~= sum:lower() then
        local unwrapped = unwrap(text);
        local found = { (unwrapped or ''):match(header) };
        if found[1] then version, sum, body = found[1], found[2], found[3]; end
    end
    if not version then return nil, 'That text is not a Vantage export.'; end
    if tonumber(version) ~= share.VERSION then return nil, share.NEWER, 'version ' .. version; end
    if #sum ~= 8 or crc32(body) ~= sum:lower() then return nil, 'That export is damaged: its checksum does not match.'; end
    if depth(body) > share.DEEPEST then return nil, 'That export is damaged: its data is nested too deeply.'; end
    local ok, payload = pcall(json.decode, body);
    if not ok or type(payload) ~= 'table' or type(payload.data) ~= 'table' then return nil, 'That export is damaged: its data is not readable.'; end
    local kind = payload.kind;
    local known = false;
    for _, name in ipairs(share.kinds) do known = known or name == kind; end
    if not known then return nil, 'That export holds something this Vantage does not have.'; end
    for key in pairs(payload) do
        if key ~= 'kind' and key ~= 'data' and key ~= 'element' then return nil, share.NEWER, tostring(key); end
    end
    local elements = require('ui.elements');
    if kind == 'element' then
        local element = type(payload.element) == 'string' and elements.by_id[payload.element];
        if not element or element.strip then return nil, 'That export is for a display this Vantage does not have.'; end
    elseif payload.element ~= nil then return nil, 'That export holds element, which its kind does not have.'; end
    local unknown = walk(payload.data, template_of(kind, payload.element), '', false);
    if unknown then return nil, share.NEWER, unknown; end
    return payload;
end

-- Where a fresh install's first frame put the displays it places, the timer panels, the alert notices and the Pet and
-- Phantom Roll displays, on the screen settings were placed for, with the game's usual chat log there, as the Size
-- buttons count them. Add takes a display still there as one the player never moved. nil when they were never placed.
local function first_frame(settings)
    local placed = settings.placement_screen;
    if type(placed) ~= 'table' then return nil; end
    local first = require('ui.setup_defaults').first_frame({ width = placed.width, height = placed.height });
    return { panels = first.panels, alerts = first.alerts, rolls = first.rolls, pet = first.pet };
end

-- Whether every one of keys still has fresh's value in target, or every one first's, the first frame's, when given.
local function untouched(target, fresh, keys, first)
    local same = require('core.profiles').same;
    local function at(source)
        for _, key in ipairs(keys) do if not same(target[key], source[key]) then return false; end end
        return true;
    end
    return at(fresh) or type(first) == 'table' and at(first);
end

-- The two numbers of each spot, which go in together or not at all, so Add never puts a display at your x and the
-- string's y. A display's anchor goes in whole the same way.
local SPOTS = { x = 'y', y = 'x', notice_x = 'notice_y', notice_y = 'notice_x', native_x = 'native_y', native_y = 'native_x',
    detached_x = 'detached_y', detached_y = 'detached_x' };
local WHOLE = { 'anchor' };

-- Puts each of data's values in target where target still has fresh's value, or first's, the first frame's, when given.
-- A number is compared to the 14 digits a saved file keeps, so a color read back from one is still fresh's.
local function fill_unchanged(target, data, fresh, first)
    local same = require('core.profiles').same;
    -- Each spot is judged before either of its numbers changes.
    local spot = {};
    for key, other in pairs(SPOTS) do
        if data[key] ~= nil and spot[key] == nil then
            local kept = type(fresh) == 'table' and untouched(target, fresh, { key, other }, first);
            spot[key], spot[other] = kept, kept;
        end
    end
    for key, value in pairs(data) do
        local placed;
        if type(first) == 'table' then placed = first[key]; end
        if spot[key] ~= nil then
            if spot[key] then target[key] = copy(value); end
        elseif key == WHOLE[1] and record(value) then
            if type(fresh) == 'table' and untouched(target, fresh, WHOLE, first) then target[key] = copy(value); end
        elseif record(value) and record(target[key]) and type(fresh) == 'table' and record(fresh[key]) then
            fill_unchanged(target[key], value, fresh[key], placed);
        elseif type(fresh) == 'table' and (same(target[key], fresh[key]) or placed ~= nil and same(target[key], placed)) then
            target[key] = copy(value);
        end
    end
end

-- Puts data's values in target; a record goes in key by key, so what the string doesn't hold stays. Given fresh, the
-- defaults target has, only a record fresh holds too goes in key by key: any other table, a list or a map such as When
-- to show's zones, goes in whole.
local function merge_into(target, data, fresh)
    for key, value in pairs(data) do
        local default = fresh and fresh[key];
        if record(value) and record(target[key]) and (not fresh or record(default)) then merge_into(target[key], value, default);
        else target[key] = copy(value); end
    end
end

-- What stays yours through any import: every lock and the samples, which panels show which members, the watched
-- enemies, the settings window and the profile links, your diagnostics settings and chat colors, whether the game's
-- buff icons are replaced, and the times learned from your casts.
local function keep_own(candidate, settings)
    local elements = require('ui.elements');
    for _, element in ipairs(elements.movable) do
        local into, from = elements.lock_holder(candidate, element.id), elements.lock_holder(settings, element.id);
        if element.lock and type(into) == 'table' and type(from) == 'table' then into[element.lock] = from[element.lock]; end
    end
    if type(candidate.party_ui) == 'table' then candidate.party_ui.locked = settings.party_ui.locked; end
    candidate.preview = settings.preview;
    for _, key in ipairs({ 'party_ui', 'overhead', 'party_cooldowns', 'rolls', 'pet' }) do
        if type(candidate[key]) == 'table' and type(settings[key]) == 'table' then candidate[key].preview = settings[key].preview; end
    end
    for id, panel in pairs(candidate.panels or {}) do
        if type(panel) == 'table' and type(settings.panels[id]) == 'table' then panel.members = copy(settings.panels[id].members); end
    end
    for _, key in ipairs({ 'window', 'watch_ids', 'job_profiles', 'active_profile', 'profile_job', 'shared_layout', 'shared_scope',
        'diagnostics', 'chat_colors', 'replace_game_buffs' }) do
        candidate[key] = copy(settings[key]);
    end
    if type(candidate.durations) == 'table' then candidate.durations.learned = copy(settings.durations.learned); end
end

-- The rules of list not already in into, by every field but the id, after into's own. Neither holds more than 128, so
-- a longer list is cut there and a full one takes no more.
local function append_rules(into, list, fields)
    local same_value = require('core.profiles').same;
    for index, rule in ipairs(list or {}) do
        if index > 128 or #into >= 128 then break; end
        local same;
        for _, held in ipairs(into) do
            local equal = true;
            for _, field in ipairs(fields) do
                if not same_value(held[field], rule[field]) then equal = false; break; end
            end
            if equal then same = true; break; end
        end
        if not same then into[#into + 1] = copy(rule); end
    end
end

-- first, with mode 'add', is where the first frame put the displays.
local function element_apply(candidate, payload, mode, fresh, first)
    local id = payload.element;
    local data = without_own(copy(payload.data), id);
    local root = element_root(candidate, id);
    if id == 'notices' then root = candidate.alerts; end
    local fresh_root = id == 'notices' and fresh.alerts or element_root(fresh, id);
    if mode == 'replace' then merge_into(root, data, fresh_root);
    else fill_unchanged(root, data, fresh_root, first and (id == 'notices' and first.alerts or element_root(first, id))); end
end

local function layout_apply(candidate, data, mode, fresh, first)
    local profiles = require('core.profiles');
    local add = mode == 'add';
    first = add and first or {};
    local fields = {};
    for field in pairs(profiles.positions) do fields[#fields + 1] = field; end
    for id, panel in pairs(data.panels or {}) do
        local into = candidate.panels[id];
        if type(into) == 'table' and (not add or untouched(into, fresh.panels[id], fields, first.panels and first.panels[id])) then
            merge_into(into, panel);
        end
    end
    local function place(into, from, fresh_into, keys, first_into)
        if type(from) == 'table' and (not add or untouched(into, fresh_into, keys, first_into)) then merge_into(into, from); end
    end
    place(candidate.alerts, data.notices, fresh.alerts, { 'notice_x', 'notice_y', 'notice_width', 'notice_height', 'notice_anchor' },
        first.alerts);
    place(candidate.party_cooldowns.list, data.cooldown_list, fresh.party_cooldowns.list, box_keys);
    place(candidate.rolls, data.rolls, fresh.rolls, box_keys, first.rolls);
    place(candidate.pet, data.pet, fresh.pet, box_keys, first.pet);
    place(candidate.ready_pulse, data.pulse, fresh.ready_pulse, { 'x', 'y', 'spot', 'size', 'anchor' });
    if type(data.party_ui) == 'table' and (not add or profiles.same(profiles.party_placement(candidate.party_ui),
        profiles.party_placement(fresh.party_ui))) then profiles.apply_party_placement(candidate.party_ui, data.party_ui); end
    if type(data.edit_mode) == 'table' then
        if add then fill_unchanged(candidate.edit_mode, data.edit_mode, fresh.edit_mode); else merge_into(candidate.edit_mode, data.edit_mode); end
    end
    if not add and type(data.placement_screen) == 'table' then candidate.placement_screen = copy(data.placement_screen); end
end

local NOT_VALID = 'That export holds settings that are not valid.';

local function make_candidate(settings, payload, mode)
    local defaults = require('ui.defaults');
    local candidate, fresh, data = copy(settings), defaults.make(), payload.data;
    local kind = payload.kind;
    local first = mode == 'add' and (kind == 'element' or kind == 'layout' or kind == 'profile') and first_frame(settings) or nil;
    if kind == 'element' then element_apply(candidate, payload, mode, fresh, first);
    elseif kind == 'layout' then layout_apply(candidate, data, mode, fresh, first);
    elseif kind == 'filters' then
        local from = type(data.effect_filters) == 'table' and data.effect_filters or {};
        if mode == 'replace' then candidate.effect_filters = copy(from);
        else append_rules(candidate.effect_filters.rules, from.rules, { 'enabled', 'effect', 'kind', 'name', 'job', 'scope' }); end
    elseif kind == 'alerts' then
        if mode == 'replace' then candidate.alerts.rules = copy(data.rules or {});
        else
            local fields = {};
            for key in pairs(defaults.rule('rule_1')) do if key ~= 'id' then fields[#fields + 1] = key; end end
            append_rules(candidate.alerts.rules, data.rules, fields);
        end
    elseif kind == 'profile' then
        if mode == 'replace' then
            for key, value in pairs(data) do
                if type(candidate[key]) == type(value) then candidate[key] = copy(value); end
            end
        else
            local same = require('core.profiles').same;
            for key, value in pairs(data) do
                if record(value) and record(candidate[key]) then fill_unchanged(candidate[key], value, fresh[key], first and first[key]);
                elseif same(candidate[key], fresh[key]) then candidate[key] = copy(value); end
            end
        end
    else return nil; end
    keep_own(candidate, settings);
    local ok, tidied = pcall(defaults.tidy, candidate);
    if not ok or type(tidied) ~= 'table' then return nil, NOT_VALID; end
    return tidied;
end

-- The settings an import makes: payload as share.read gives it, mode 'add' or 'replace'. Returns them tidied, or nil and
-- why. share.read checks names, not types, so a number where a table goes is found here.
function share.candidate(settings, payload, mode)
    local ok, candidate, why = pcall(make_candidate, settings, payload, mode);
    if not ok then return nil, NOT_VALID; end
    return candidate, why;
end

-- The settings a whole profile string saves as a new profile: what Replace makes from settings, and with
-- keep_positions every display where settings have it and the screen they were placed for, as a layout string puts
-- them. Returns them, or nil and why.
function share.profile_of(settings, payload, keep_positions)
    if type(payload) ~= 'table' or payload.kind ~= 'profile' then return nil, 'That export is not a whole profile.'; end
    local candidate, why = share.candidate(settings, payload, 'replace');
    if not candidate or not keep_positions then return candidate, why; end
    local own = layout_data(settings);
    own.edit_mode = nil;
    layout_apply(candidate, own, 'replace', require('ui.defaults').make());
    return candidate;
end

-- How many values differ between a and b. A number is compared to the 14 digits a string keeps, so one read back is
-- the one written.
local function leaves(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return require('core.profiles').same(a, b) and 0 or 1; end
    local count = 0;
    for key, value in pairs(a) do count = count + leaves(value, b[key]); end
    for key, value in pairs(b) do if a[key] == nil then count = count + leaves(nil, value); end end
    return count;
end

-- Where an import changes things, by area, in plain words: one line each, or that nothing changes.
function share.changes(settings, candidate)
    local elements = require('ui.elements');
    local lines = {};
    local function line(label, count, unit)
        if count > 0 then lines[#lines + 1] = label .. ': ' .. count .. ' ' .. (count == 1 and unit or unit .. 's') .. ' change.'; end
    end
    local function rules(label, before, after)
        before, after = before or {}, after or {};
        if leaves(before, after) == 0 then return; end
        lines[#lines + 1] = label .. ': ' .. #before .. (#before == 1 and ' rule' or ' rules') .. ' now, ' .. #after .. ' after.';
    end
    local seen = { panels = true, alerts = true, effect_filters = true, window = true, watch_ids = true, job_profiles = true,
        active_profile = true, profile_job = true, shared_layout = true, shared_scope = true, preview = true,
        replace_game_buffs = true };
    for _, element in ipairs(elements.list) do
        if element.panel then line(element.label, leaves(settings.panels[element.id], candidate.panels[element.id]), 'setting'); end
    end
    local notices = 0;
    for _, key in ipairs(notice_keys) do notices = notices + leaves(settings.alerts[key], candidate.alerts[key]); end
    line('Alerts size and place', notices, 'setting');
    local other = 0;
    for key, value in pairs(settings.alerts) do
        if key ~= 'rules' and not tostring(key):find('^notice_') and key ~= 'max_notices' then other = other + leaves(value, candidate.alerts[key]); end
    end
    line('Alerts', other, 'setting');
    rules('Alert rules', settings.alerts.rules, candidate.alerts.rules);
    rules('Hidden everywhere list', settings.effect_filters.rules, candidate.effect_filters.rules);
    if settings.effect_filters.enabled ~= candidate.effect_filters.enabled then lines[#lines + 1] = 'Hidden everywhere list: turned ' .. (candidate.effect_filters.enabled and 'on.' or 'off.'); end
    local names = { style = 'Timer look', window_style = 'Settings window look', party_ui = 'Party list buffs', overhead = 'Overhead icons',
        party_cooldowns = 'Party cooldowns', ready_pulse = 'Ready pulse', rolls = 'Phantom Roll', pet = 'Pet', durations = 'Timer durations',
        recast_tints = 'Recast marks', visibility = 'When Vantage hides', chat_colors = 'Chat colors',
        edit_mode = 'Edit mode grid and snapping', tracking = 'Tracking', diagnostics = 'Diagnostics', placement_screen = 'Screen size placed for',
        recast_display = 'Recasts shown as', enabled = 'Timer panels on or off' };
    local keys = {};
    for key in pairs(candidate) do if not seen[key] then keys[#keys + 1] = key; end end
    for key in pairs(settings) do if not seen[key] and candidate[key] == nil then keys[#keys + 1] = key; end end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b); end);
    for _, key in ipairs(keys) do line(names[key] or key, leaves(settings[key], candidate[key]), 'setting'); end
    if #lines == 0 then lines[1] = 'Nothing changes.'; end
    return lines;
end

-- What a payload holds, in plain words.
function share.describe(payload)
    if payload.kind == 'element' then return 'One display: ' .. require('ui.elements').label(payload.element) .. '.'; end
    return (share.kind_names[payload.kind] or payload.kind) .. '.';
end

-- A file name made from a profile name: without names, the names a whole profile leaves out, as whole words, so it
-- doesn't say whose it is, and with its letters, digits, spaces, - and _ only, so it is never a path; or "profile". A
-- name Windows keeps for a device, such as CON, gets " profile" after it.
function share.file_name(name, names)
    local base = tostring(name or '');
    for _, private in ipairs(names or {}) do
        if #private >= 2 then
            local lower, wanted, kept, at = base:lower(), private:lower(), {}, 1;
            local from, to = whole_word(lower, wanted);
            while from do
                kept[#kept + 1], at = base:sub(at, from - 1), to + 1;
                from, to = whole_word(lower, wanted, at);
            end
            kept[#kept + 1] = base:sub(at);
            base = table.concat(kept);
        end
    end
    base = base:gsub('[^%w _%-]', ''):gsub('  +', ' '):match('^%s*(.-)%s*$');
    if base == '' then return 'profile'; end
    local upper = base:upper();
    if upper == 'CON' or upper == 'PRN' or upper == 'AUX' or upper == 'NUL' or upper:match('^COM%d$') or upper:match('^LPT%d$') then
        base = base .. ' profile';
    end
    return base;
end

-- Writes text to a new .txt file in folder, which is made when it is missing, named after a profile with any name of
-- yours, the Windows user's or another character's on this PC left out: the first of "Raid.txt", "Raid 2.txt",
-- "Raid 3.txt" and so on that isn't there yet, so no file is ever replaced. Returns the file's name, or nil and why.
function share.save_file(folder, name, text, character)
    local base = share.file_name(name, all_names(character));
    for count = 1, 99 do
        local file = base .. (count > 1 and ' ' .. count or '') .. '.txt';
        local ok, why, code = store.create(folder .. file, text);
        if ok then return file; end
        if code ~= 'exists' then return nil, why; end
    end
    return nil, 'The shared folder already has 99 files named after this profile.';
end

-- A file Import from a file reads: a .txt name in the shared folder, never a path.
local function plain_file(file)
    return type(file) == 'string' and #file <= 200 and not file:find('[%c\\/:]') and not file:find('..', 1, true)
        and file:lower():match('%.txt$') ~= nil;
end

-- The .txt files in folder, which is made when it is missing, by name. Returns them, or none and why.
function share.files(folder)
    local made, why = store.ensure_folder(folder);
    if not made then return {}, why; end
    local ok, found = pcall(ashita.fs.get_directory, folder, '.*\\.[tT][xX][tT]$', false);
    if not ok or type(found) ~= 'table' then return {}, 'The files in the shared folder could not be listed.'; end
    local files, seen = {}, {};
    for _, file in ipairs(found) do
        if plain_file(file) and not seen[file:lower()] then seen[file:lower()], files[#files + 1] = true, file; end
    end
    table.sort(files, function(a, b) return a:lower() < b:lower(); end);
    return files;
end

-- Reads the export in file, one of share.files(folder). It reads at most share.MOST + 1 bytes, which
-- share.read refuses as too long.
function share.read_file(folder, file)
    if not plain_file(file) then return nil, 'Choose a file from the list.'; end
    local handle = io.open(folder .. file, 'rb');
    if not handle then return nil, 'That file could not be opened.'; end
    local ok, text = pcall(handle.read, handle, share.MOST + 1);
    pcall(handle.close, handle);
    if not ok then return nil, 'That file could not be read.'; end
    if type(text) ~= 'string' or text:match('^%s*$') then return nil, 'That file is empty.'; end
    return share.read(text);
end

return share;
