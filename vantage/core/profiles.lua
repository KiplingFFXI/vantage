local store = require('core.store');
local profiles = {};
local excluded = { window = true, job_profiles = true, shared_layout = true, shared_scope = true,
    active_profile = true, profile_job = true, preview = true, watch_ids = true,
    -- It changes how the game draws on this computer, so it stays with the character who ticked it.
    replace_game_buffs = true };
local positions = { x = true, y = true, width = true, height_limit = true, auto_width = true, auto_height = true,
    stack_direction = true, growth = true, item_width = true,
    min_width = true, max_width = true, dock_match_width = true,
    -- A panel's anchor (core/anchors.lua) is part of where it sits.
    anchor = true };
local presentation = { style = true, window_style = true, panels = true, recast_display = true, effect_filters = true, visibility = true, chat_colors = true, party_ui = true,
    overhead = true, durations = true, recast_tints = true, ready_pulse = true, party_cooldowns = true, rolls = true, pet = true,
    edit_mode = true };
-- The alert notices' place, size, anchor and When to show.
local notice_fields = { notice_x = true, notice_y = true, notice_width = true, notice_height = true, max_notices = true,
    notice_anchor = true, notice_conditions = true };
-- Each character's own party list buff switches and lock.
local party_local = { enabled = true, strips = true, preview = true, locked = true };
-- And its own overhead icons switch and samples, as the main page has them.
local overhead_local = { enabled = true, preview = true };
-- And its own locks of the ready pulse spot, the party cooldown list and the Phantom Roll and pet displays, as each
-- panel keeps its lock, and their samples.
local function without_locals(content)
    if type(content.ready_pulse) == 'table' then content.ready_pulse.locked = nil; end
    if type(content.party_cooldowns) == 'table' then
        content.party_cooldowns.preview = nil;
        if type(content.party_cooldowns.list) == 'table' then content.party_cooldowns.list.locked = nil; end
    end
    for _, key in ipairs({ 'rolls', 'pet' }) do
        if type(content[key]) == 'table' then content[key].preview, content[key].locked = nil, nil; end
    end
end
local function keep_locals(candidate, settings)
    if type(candidate.ready_pulse) == 'table' and type(settings.ready_pulse) == 'table' then
        candidate.ready_pulse.locked = settings.ready_pulse.locked;
    end
    local into, from = candidate.party_cooldowns, settings.party_cooldowns;
    if type(into) == 'table' and type(from) == 'table' then
        into.preview = from.preview;
        if type(into.list) == 'table' and type(from.list) == 'table' then into.list.locked = from.list.locked; end
    end
    for _, key in ipairs({ 'rolls', 'pet' }) do
        if type(candidate[key]) == 'table' and type(settings[key]) == 'table' then
            candidate[key].preview, candidate[key].locked = settings[key].preview, settings[key].locked;
        end
    end
end
-- The times Vantage learned from this character's casts stay with it: profiles and shared files never hold them.
local function without_learned(value)
    if type(value) == 'table' and type(value.durations) == 'table' then value.durations.learned = nil; end
    return value;
end
local function keep_learned(candidate, settings)
    if type(candidate.durations) == 'table' then
        candidate.durations.learned = store.copy(type(settings.durations) == 'table' and settings.durations.learned or {});
    end
end
-- Where the party list strips sit: beside the game's party windows, or detached.
local party_positions = { native = true };
local party_group_positions = { native_x = true, native_y = true, native_side = true, native_detached = true,
    detached_x = true, detached_y = true, detached_width = true, detached_height = true };
-- Which way each strip fills.
local party_effect_positions = { growth = true };

local function party_placement(value)
    if (type(value) ~= 'table') then return nil; end
    local result = { groups = {} };
    for field in pairs(party_positions) do result[field] = store.copy(value[field]); end
    if (type(value.effects) == 'table') then
        result.effects = {};
        for field in pairs(party_effect_positions) do result.effects[field] = store.copy(value.effects[field]); end
    end
    for i = 1, 3 do
        if (type(value.groups) == 'table' and type(value.groups[i]) == 'table') then
            result.groups[i] = {};
            for field in pairs(party_group_positions) do result.groups[i][field] = store.copy(value.groups[i][field]); end
        end
    end
    return result;
end

local function apply_party_placement(target, source)
    if (type(target) ~= 'table' or type(source) ~= 'table') then return; end
    for field in pairs(party_positions) do
        if (target[field] ~= nil and type(source[field]) == type(target[field])) then target[field] = store.copy(source[field]); end
    end
    if (type(target.effects) == 'table' and type(source.effects) == 'table') then
        for field in pairs(party_effect_positions) do
            if (type(source.effects[field]) == type(target.effects[field])) then target.effects[field] = store.copy(source.effects[field]); end
        end
    end
    for i = 1, 3 do
        local from = type(source.groups) == 'table' and (source.groups[i] or source.groups[tostring(i)]);
        local into = type(target.groups) == 'table' and target.groups[i];
        if (type(from) == 'table' and type(into) == 'table') then
            for field in pairs(party_group_positions) do
                if (into[field] ~= nil and type(from[field]) == type(into[field])) then into[field] = store.copy(from[field]); end
            end
        end
    end
end

-- Exports (core/share.lua) carry a layout as placement sharing does.
profiles.positions, profiles.party_placement, profiles.apply_party_placement = positions, party_placement, apply_party_placement;

local function clean_name(name)
    name = type(name) == 'string' and name:match('^%s*(.-)%s*$') or '';
    if (#name == 0 or #name > 40 or name:find('[^\32-\126]') or name:find('##', 1, true)
        or name:lower() == 'none' or name:lower() == '(none)') then
        return nil, 'Use 1 to 40 plain characters without ##. None is reserved for turning off a job profile.';
    end
    return name;
end

local function find_name(data, name)
    if (type(name) ~= 'string') then return nil; end
    name = name:match('^%s*(.-)%s*$');
    if (data[name] ~= nil) then return name; end
    local found;
    for key in pairs(data) do
        if (type(key) == 'string' and key:lower() == name:lower()) then
            if (found) then return nil, 'Several profiles have this name. Give them distinct names in the saved file.'; end
            found = key;
        end
    end
    return found;
end

-- JSON changes sparse numeric keys to strings. Compare their saved meaning.
local function token(value)
    if (type(value) ~= 'table') then
        if (type(value) == 'string') then return 's' .. #value .. ':' .. value; end
        return type(value) .. ':' .. tostring(value);
    end
    local parts = {};
    for key, child in pairs(value) do
        local text = tostring(key);
        parts[#parts + 1] = #text .. ':' .. text .. '=' .. token(child);
    end
    table.sort(parts);
    local result = {};
    for _, part in ipairs(parts) do result[#result + 1] = #part .. ':' .. part; end
    return '{' .. table.concat(result) .. '}';
end

function profiles.capture(settings)
    local result = {};
    for key, value in pairs(settings) do
        if (not excluded[key]) then result[key] = store.copy(value); end
    end
    for _, panel in pairs(result.panels or {}) do
        if (type(panel) == 'table') then panel.members = nil; end
    end
    if (type(result.party_ui) == 'table') then
        result.party_ui = require('ui.party_defaults').tidy(result.party_ui);
        result.party_ui.preview = false;
    end
    if (type(result.overhead) == 'table') then result.overhead.preview = false; end
    if (type(result.party_cooldowns) == 'table') then result.party_cooldowns.preview = false; end
    for _, key in ipairs({ 'rolls', 'pet' }) do if (type(result[key]) == 'table') then result[key].preview = false; end end
    return without_learned(result);
end

function profiles.capture_layout(settings, scope)
    scope = scope or settings.shared_scope or 'placement';
    if (scope ~= 'placement' and scope ~= 'presentation') then return nil, 'Choose placement or full presentation.'; end
    if (scope == 'presentation') then
        local content = {};
        for key in pairs(presentation) do content[key] = store.copy(settings[key]); end
        for _, panel in pairs(content.panels or {}) do
            if (type(panel) == 'table') then panel.members, panel.locked = nil, nil; end
        end
        if (type(content.party_ui) == 'table') then
            for field in pairs(party_local) do content.party_ui[field] = nil; end
        end
        if (type(content.overhead) == 'table') then
            for field in pairs(overhead_local) do content.overhead[field] = nil; end
        end
        without_locals(content);
        without_learned(content);
        content.alerts = {};
        for field in pairs(notice_fields) do content.alerts[field] = store.copy(settings.alerts[field]); end
        content.placement_screen = store.copy(settings.placement_screen);
        return { scope = 'presentation', presentation = content };
    end
    local layout = {};
    for key, panel in pairs(settings.panels or {}) do
        if (type(panel) == 'table') then
            layout[key] = {};
            for field in pairs(positions) do layout[key][field] = store.copy(panel[field]); end
        end
    end
    layout.party_ui = party_placement(settings.party_ui);
    -- The screen these positions were placed for travels with them, so a Size button on another screen knows them.
    layout.placement_screen = store.copy(settings.placement_screen);
    return layout;
end

-- A presentation-form file with a placement layout laid over its content: the panel positions and the party list
-- strip placement.
local function placement_over(file, layout)
    local content = store.copy(file.presentation);
    for key, panel in pairs(type(content.panels) == 'table' and content.panels or {}) do
        if (type(panel) == 'table' and type(layout[key]) == 'table') then
            for field in pairs(positions) do
                if (type(layout[key][field]) == type(panel[field])) then panel[field] = store.copy(layout[key][field]); end
            end
        end
    end
    if (type(content.party_ui) == 'table' and type(layout.party_ui) == 'table') then apply_party_placement(content.party_ui, layout.party_ui); end
    if type(layout.placement_screen) == 'table' then content.placement_screen = store.copy(layout.placement_screen); end;
    return { scope = 'presentation', presentation = content };
end

-- Applies a shared layout, as publish_layout and save_layout write it, to settings in place. The third value
-- says whether anything changed.
function profiles.apply_layout(settings, layout, scope)
    local content = layout.scope == 'presentation' and type(layout.presentation) == 'table' and layout.presentation or nil;
    local source = content and content.panels or layout;
    local full = scope == 'presentation' and content ~= nil;
    local candidate = store.copy(settings);
    if (full) then
        for key in pairs(presentation) do
            if (key ~= 'panels' and type(content[key]) == type(settings[key])) then candidate[key] = store.copy(content[key]); end
        end
        if (type(candidate.party_ui) == 'table' and type(settings.party_ui) == 'table') then
            for field in pairs(party_local) do candidate.party_ui[field] = store.copy(settings.party_ui[field]); end
        end
        if (type(candidate.overhead) == 'table' and type(settings.overhead) == 'table') then
            for field in pairs(overhead_local) do candidate.overhead[field] = settings.overhead[field]; end
        end
        keep_locals(candidate, settings);
        keep_learned(candidate, settings);
        for field in pairs(notice_fields) do
            if (type(content.alerts) == 'table' and type(content.alerts[field]) == type(settings.alerts[field])) then
                candidate.alerts[field] = store.copy(content.alerts[field]);
            end
        end
    end
    for key, panel in pairs(candidate.panels or {}) do
        if (type(panel) == 'table' and type(source) == 'table' and type(source[key]) == 'table') then
            for field, value in pairs(source[key]) do
                if ((full and field ~= 'members' and field ~= 'locked' or positions[field]) and type(value) == type(panel[field])) then
                    panel[field] = store.copy(value);
                end
            end
        end
    end
    if (not full) then
        apply_party_placement(candidate.party_ui, content and content.party_ui or layout.party_ui);
    end
    local placed = (content or layout).placement_screen;
    if type(placed) == 'table' then candidate.placement_screen = store.copy(placed); end;
    local ok, result = pcall(require('ui.defaults').tidy, candidate);
    if (not ok) then return false, 'The shared layout could not be read. Your current layout was kept.'; end
    candidate = type(result) == 'table' and result or candidate;
    -- Nothing to write when the settings already match.
    local mode = full and 'presentation' or 'placement';
    if (token(profiles.capture_layout(candidate, mode)) == token(profiles.capture_layout(settings, mode))) then
        return true, nil, false;
    end
    settings.placement_screen = candidate.placement_screen;
    if (full) then
        for key in pairs(presentation) do settings[key] = candidate[key]; end
        for field in pairs(notice_fields) do settings.alerts[field] = candidate.alerts[field]; end
    else
        for key, panel in pairs(settings.panels or {}) do
            if (type(panel) == 'table' and type(candidate.panels[key]) == 'table') then
                for field in pairs(positions) do panel[field] = candidate.panels[key][field]; end
            end
        end
        apply_party_placement(settings.party_ui, candidate.party_ui);
    end
    return true, nil, true;
end

local function candidate_for(saved, settings)
    local candidate = store.copy(settings);
    for key, value in pairs(saved) do
        if (not excluded[key] and settings[key] ~= nil and type(value) == type(settings[key])) then candidate[key] = store.copy(value); end
    end
    -- The profile's positions bring the screen they were placed for, or none.
    candidate.placement_screen = store.copy(saved.placement_screen);
    if (type(saved.party_ui) == 'table' and type(candidate.party_ui) == 'table') then candidate.party_ui.preview = false; end
    if (type(saved.overhead) == 'table' and type(candidate.overhead) == 'table') then candidate.overhead.preview = false; end
    if (type(saved.party_cooldowns) == 'table' and type(candidate.party_cooldowns) == 'table') then candidate.party_cooldowns.preview = false; end
    for _, key in ipairs({ 'rolls', 'pet' }) do
        if (type(saved[key]) == 'table' and type(candidate[key]) == 'table') then candidate[key].preview = false; end
    end
    keep_learned(candidate, settings);
    local ok, result = pcall(require('ui.defaults').tidy, candidate);
    if (not ok) then return nil, 'That profile contains invalid settings. Your current settings were kept.'; end
    candidate = type(result) == 'table' and result or candidate;
    for id, panel in pairs(candidate.panels or {}) do
        if (type(panel) == 'table' and settings.panels and type(settings.panels[id]) == 'table') then panel.members = store.copy(settings.panels[id].members); end
    end
    return candidate;
end

local function guarded(value, expected)
    return type(expected) == 'string' and token(value) == expected;
end

local function profile_names(data)
    local names = {};
    for name, value in pairs(data) do
        if (clean_name(name) and type(value) == 'table') then names[#names + 1] = name; end
    end
    table.sort(names, function(a, b) if a:lower() == b:lower() then return a < b; end return a:lower() < b:lower(); end);
    return names;
end

local function profile_source(data, name, settings)
    local key, problem = find_name(data, name);
    if (problem) then return { name = name or '', exists = false, modified = false }, problem; end
    if (not key or type(data[key]) ~= 'table') then return { name = name or '', exists = false, modified = false }; end
    local modified = false;
    if (settings) then
        local candidate, why = candidate_for(data[key], settings);
        if (not candidate) then return { name = key, exists = true, token = token(data[key]), modified = true }, why; end
        modified = token(profiles.capture(candidate)) ~= token(profiles.capture(settings));
    end
    return { name = key, exists = true, token = token(data[key]), modified = modified };
end

local function same(a, b)
    -- The very same table, as a read of an unchanged file gives back, needs no walk.
    if (a == b) then return true; end
    if (type(a) ~= type(b)) then return false; end
    -- The file keeps 14 significant digits, as json.lua writes numbers, so a value read back is the one written.
    if (type(a) == 'number') then return a == b or ('%.14g'):format(a) == ('%.14g'):format(b); end
    if (type(a) ~= 'table') then return a == b; end
    for key, value in pairs(a) do if (not same(value, b[key])) then return false; end end
    for key in pairs(b) do if (a[key] == nil) then return false; end end
    return true;
end
-- Exports (core/share.lua) compare a value read back the same way.
profiles.same = same;
-- Three ways: what this character changed since base wins, else what the other one did. A list is one value.
local function merge(own, base, theirs)
    if (type(own) == 'table' and type(base) == 'table' and type(theirs) == 'table' and #own == 0 and #theirs == 0) then
        local result = {};
        for key, value in pairs(own) do result[key] = merge(value, base[key], theirs[key]); end
        for key, value in pairs(theirs) do
            if (own[key] == nil) then result[key] = merge(nil, base[key], value); end
        end
        return result;
    end
    if (not same(own, base)) then return own; end
    return theirs;
end

-- What a save says when the profiles file has no room left for it.
local FULL = 'The saved profiles file is full. Delete a profile to make room.';

function profiles.new(folder)
    folder = folder:gsub('[\\/]+$', '') .. '/';
    local self = { folder = folder, path = folder .. 'profiles.json', layout_path = folder .. 'shared_layout.json' };
    local history, owner, serial = {}, nil, 0;
    -- The shared layout file's text and value as last read, so a poll of an unchanged file doesn't decode it again.
    -- The value is shared, with layout_seen too, and nothing changes it: apply_layout copies what it takes.
    local layout_file = {};
    function self:set_owner(identity) owner = type(identity) == 'string' and identity ~= '' and identity or nil; end

    local function record(kind, name, to_name, changes, settings)
        serial = serial + 1;
        local entry = { kind = kind, name = name, to_name = to_name, changes = changes, serial = serial };
        if (settings) then
            entry.owner_identity = owner;
            entry.owner, entry.links_owner, entry.links = settings, settings.job_profiles, {};
            for job, linked in pairs(settings.job_profiles or {}) do
                if (linked == name) then
                    local replacement = kind == 'rename' and to_name or nil;
                    entry.links[job] = { before = linked, after = replacement };
                    settings.job_profiles[job] = replacement;
                end
            end
            if (settings.active_profile == name) then
                entry.active_before = name;
                entry.active_after = kind == 'rename' and to_name or '';
                settings.active_profile = entry.active_after;
            end
        end
        history[#history + 1] = entry;
        if (#history > 20) then table.remove(history, 1); end
    end

    -- Writes the profiles file, and says when it is full.
    local function write(data, original)
        local ok, why, code = store.write(self.path, data, original);
        if (code == 'full') then why = FULL; end
        return ok, why;
    end

    function self:list()
        local data, err = store.read(self.path);
        if (data == nil) then return {}, err; end
        return profile_names(data);
    end
    self.names = self.list;

    function self:source(name, settings)
        local data, err = store.read(self.path);
        if (data == nil) then return { name = name or '', exists = false, modified = false }, err; end
        return profile_source(data, name, settings);
    end
    function self:status(settings) return self:source(settings.active_profile, settings); end

    -- The summary only reads the file, so it decodes it again only when the text changed. Given a count of the
    -- settings' changes, it keeps the Modified check until the file text, the active profile or the settings change.
    local summary_file, summary_kept = {}, {};
    function self:summary(settings, revision)
        local data, err = store.read(self.path, summary_file);
        local name = settings and settings.active_profile or '';
        if (data == nil) then return { names = {}, problem = err, status = { name = name, exists = false, modified = false } }; end
        local kept, status, why = summary_kept;
        if (revision ~= nil and kept.revision == revision and kept.settings == settings and kept.name == name
            and kept.text == summary_file.text) then
            status, why = kept.status, kept.why;
        else
            status, why = profile_source(data, name, settings);
            if (revision ~= nil) then
                kept.revision, kept.settings, kept.name, kept.text, kept.status, kept.why =
                    revision, settings, name, summary_file.text, status, why;
            end
        end
        return { names = profile_names(data), status = status, problem = why };
    end

    local function save_profile(name, settings, mode, expected)
        local valid, problem = clean_name(name);
        if (not valid) then return false, problem; end
        local data, err = store.read(self.path);
        if (data == nil) then return false, err; end
        local found, why = find_name(data, valid);
        if (why) then return false, why; end
        if (found and type(data[found]) ~= 'table') then return false, 'That saved profile contains invalid settings. It was kept unchanged.'; end
        -- 'taken' after the reason lets a caller with no Overwrite say it its own way.
        if (mode == 'new' and found) then return false, 'That profile already exists. Choose a new name or use Overwrite.', 'taken'; end
        if (mode == 'overwrite' and (not found or not guarded(data[found], expected))) then
            return false, 'That profile changed or was removed. Review it again before overwriting.';
        end
        valid = found or valid;
        local original = store.copy(data);
        local before = data[valid];
        data[valid] = profiles.capture(settings);
        local ok, message = write(data, original);
        if (ok and before ~= nil) then
            record('overwrite', valid, nil, { [valid] = { before = store.copy(before), after = store.copy(data[valid]) } });
        end
        return ok, message;
    end
    function self:save_new(name, settings) return save_profile(name, settings, 'new'); end
    function self:overwrite(name, settings, expected) return save_profile(name, settings, 'overwrite', expected); end

    -- The settings that loading the profile called name would give, leaving settings as they are, and the name as saved.
    function self:settings_of(name, settings)
        local data, err = store.read(self.path);
        if (data == nil) then return nil, err; end
        local key, problem = find_name(data, name);
        if (problem) then return nil, problem; end
        if (not key or type(data[key]) ~= 'table') then return nil, 'That profile was not found.'; end
        local candidate, why = candidate_for(data[key], settings);
        if (not candidate) then return nil, why; end
        return candidate, nil, key;
    end

    function self:load(name, settings)
        local data, err = store.read(self.path);
        if (data == nil) then return false, err; end
        local key, problem = find_name(data, name);
        if (problem) then return false, problem; end
        if (not key or type(data[key]) ~= 'table') then return false, 'That profile was not found.'; end
        local candidate, why = candidate_for(data[key], settings);
        if (not candidate) then return false, why; end
        for field, value in pairs(candidate) do if (not excluded[field]) then settings[field] = value; end end
        settings.placement_screen = candidate.placement_screen;
        settings.active_profile = key;
        return true;
    end

    function self:delete(name, expected, settings)
        local data, err = store.read(self.path);
        if (data == nil) then return false, err; end
        local key, problem = find_name(data, name);
        if (problem) then return false, problem; end
        if (not key or type(data[key]) ~= 'table') then return false, 'That profile was not found.'; end
        if (expected ~= nil and not guarded(data[key], expected)) then return false, 'That profile changed. Review it again before deleting.'; end
        local original = store.copy(data);
        local before = data[key];
        data[key] = nil;
        local ok, why = store.write(self.path, data, original);
        if (ok) then record('delete', key, nil, { [key] = { before = before, after = false } }, settings); end
        return ok, why;
    end

    function self:rename(name, new_name, settings, expected)
        local valid, problem = clean_name(new_name);
        if (not valid) then return false, problem; end
        local data, err = store.read(self.path);
        if (data == nil) then return false, err; end
        local old, why = find_name(data, name);
        if (why) then return false, why; end
        if (not old or type(data[old]) ~= 'table') then return false, 'That profile was not found.'; end
        if (expected ~= nil and not guarded(data[old], expected)) then return false, 'That profile changed. Review it again before renaming.'; end
        local collision, conflict = find_name(data, valid);
        if (conflict) then return false, conflict; end
        if (collision and collision ~= old) then return false, 'That name is already used by another profile.'; end
        if (old == valid) then return true; end
        local original = store.copy(data);
        local saved = data[old];
        data[old], data[valid] = nil, saved;
        local ok, message = write(data, original);
        if (ok) then record('rename', old, valid, {
            [old] = { before = store.copy(saved), after = false },
            [valid] = { before = false, after = store.copy(saved) },
        }, settings); end
        return ok, message;
    end

    function self:recovery()
        local entry = history[#history];
        if (entry) then return { kind = entry.kind, name = entry.name, to_name = entry.to_name, serial = entry.serial }; end
    end
    function self:recover(settings)
        local entry = history[#history];
        if (not entry) then return false, 'There is no profile change to recover in this session.'; end
        local data, err = store.read(self.path);
        if (data == nil) then return false, err; end
        local folded, expected = {}, {};
        for name, change in pairs(entry.changes) do
            folded[name:lower()] = true;
            if (change.after ~= false) then expected[name] = change.after; end
        end
        local actual = {};
        for name, value in pairs(data) do
            if (type(name) == 'string' and folded[name:lower()]) then actual[name] = value; end
        end
        if (token(actual) ~= token(expected)) then return false, 'Those profiles changed outside this action. Recovery kept the current files unchanged.'; end
        local original = store.copy(data);
        for name, change in pairs(entry.changes) do data[name] = change.before ~= false and store.copy(change.before) or nil; end
        local ok, why = write(data, original);
        if (not ok) then return false, why; end
        local same_owner = entry.owner_identity ~= nil and entry.owner_identity == owner
            or entry.owner_identity == nil and settings == entry.owner and settings and settings.job_profiles == entry.links_owner;
        if (settings and same_owner and entry.links) then
            for job, change in pairs(entry.links) do
                if (settings.job_profiles[job] == change.after) then settings.job_profiles[job] = change.before; end
            end
            if (entry.active_before and settings.active_profile == entry.active_after) then settings.active_profile = entry.active_before; end
        end
        table.remove(history);
        return true;
    end
    -- A copy of the recovery list, put back when a settings page fails after changing profiles.
    function self:recovery_list()
        local list = {};
        for index, entry in ipairs(history) do list[index] = entry; end
        return list;
    end
    function self:restore_recovery(list)
        for index = #history, 1, -1 do history[index] = nil; end
        for index, entry in ipairs(list) do history[index] = entry; end
    end

    function self:link(settings, job, name)
        job = tonumber(job);
        if (not job or job ~= math.floor(job) or job < 1 or job > 18) then return false, 'Choose a valid job.'; end
        if (type(name) ~= 'string') then return false, 'Choose a profile from the list.'; end
        if (name ~= '') then
            local data, err = store.read(self.path);
            if (data == nil) then return false, err; end
            local key, problem = find_name(data, name);
            if (problem) then return false, problem; end
            if (not key or type(data[key]) ~= 'table') then return false, 'That profile was not found.'; end
            name = key;
        end
        settings.job_profiles = settings.job_profiles or {};
        settings.job_profiles[job] = nil;
        settings.job_profiles[tostring(job)] = name ~= '' and name or nil;
        return true;
    end

    -- Fixtures seed a shared layout with this. It writes without publish_layout's merge, so nothing else may.
    if VANTAGE_TEST_MODE then
        function self:save_layout(settings, scope)
            local layout, problem = profiles.capture_layout(settings, scope);
            if (not layout) then return false, problem; end
            return store.write(self.layout_path, layout);
        end
    end
    -- Writes this character's shared layout. base is the one it last read or wrote here. Another character's
    -- changes since then go into settings first, under this one's own, so publishing a move here doesn't put
    -- back a panel moved there. Returns the layout written and whether settings took changes from the file.
    -- When another character's write lands between this read and write, it reads, merges and writes once more.
    function self:publish_layout(settings, base)
        local scope = settings.shared_scope or 'placement';
        local own = profiles.capture_layout(settings, scope);
        local merged = false;
        for attempt = 1, 2 do
            local file, err = store.read(self.layout_path);
            if (file == nil) then return false, err; end
            if (base ~= nil and next(file) ~= nil and not same(file, self.layout_seen)) then
                local theirs = store.copy(settings);
                local ok, why = profiles.apply_layout(theirs, file, scope);
                if (not ok) then return false, why; end
                local layout = merge(own, base, profiles.capture_layout(theirs, scope));
                if (not same(layout, profiles.capture_layout(settings, scope))) then
                    ok, why = profiles.apply_layout(settings, layout, scope);
                    if (not ok) then return false, why; end
                    merged = true;
                end
            end
            local layout, problem = profiles.capture_layout(settings, scope);
            if (not layout) then return false, problem; end
            -- A placement publisher met a file in presentation form: the appearance shared there stays for the
            -- characters reading it, with this character's placement over it.
            if (scope == 'placement' and file.scope == 'presentation' and type(file.presentation) == 'table') then
                layout = placement_over(file, layout);
            end
            local ok, why, code = store.write(self.layout_path, layout, file);
            if (ok) then
                self.layout_seen = layout;
                return true, nil, layout, merged;
            end
            if (code ~= 'changed') then return false, why; end
        end
        return false, 'Another character saved it at the same moment, twice.';
    end
    -- The shared layout file, and whether it is the one last read or written here. When it is, the value read counts as
    -- the one seen from then on, so the next poll of the unchanged file knows it without a walk.
    function self:read_layout()
        local layout, err = store.read(self.layout_path, layout_file);
        if (layout == nil) then return nil, err; end
        local seen = same(layout, self.layout_seen);
        if (seen) then self.layout_seen = layout; end
        return layout, nil, seen;
    end
    -- layout is the file when the caller already read it.
    function self:load_layout(settings, scope, layout)
        scope = scope or settings.shared_scope or 'placement';
        if (scope ~= 'placement' and scope ~= 'presentation') then return false, 'Choose placement or full presentation.'; end
        local err;
        if (layout == nil) then layout, err = store.read(self.layout_path, layout_file); end
        if (layout == nil) then return false, err; end
        -- The fourth value says whether anything changed.
        local ok, why, changed = profiles.apply_layout(settings, layout, scope);
        if (not ok) then return false, why; end
        self.layout_seen = layout;
        return true, nil, next(layout) ~= nil, changed;
    end
    return self;
end

return profiles;
