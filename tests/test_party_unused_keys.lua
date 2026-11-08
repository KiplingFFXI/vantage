-- What nothing reads: what the party list buffs have no use for, as they draw icons only, in one time format and in the
-- timer panels' look, each group's own look, and each display's time format, as every countdown has one. Fresh settings
-- hold none of them. An export, Add and Replace alike, for Party & alliance, a timer panel, the overhead icons,
-- Phantom Roll, the pet display and a whole profile brings none of them, the string's own values land as they are, and
-- a string of fresh settings changes nothing, so Profiles and sharing says so.
local defaults = require('ui.defaults');
local store, share = require('core.store'), require('core.share');
local equal = require('core.customization').equal;

-- The keys, as dotted paths; * is every panel or every party group.
local UNUSED = {
    'party_ui.effects.mode', 'party_ui.effects.names', 'party_ui.effects.bar_width', 'party_ui.effects.bar_height',
    'party_ui.effects.timer_format', 'party_ui.effects.warning_seconds', 'party_ui.effects.row_room',
    'party_ui.effects.labels', 'party_ui.effects.colors',
    'party_ui.style.theme', 'party_ui.style.window_type', 'party_ui.style.font', 'party_ui.style.gauge_art',
    'party_ui.style.font_size', 'party_ui.style.rounding', 'party_ui.style.border', 'party_ui.style.background',
    'party_ui.style.minimal', 'party_ui.style.colors', 'party_ui.groups.*.style',
    'panels.*.timer_format', 'overhead.timer_format', 'rolls.timer_format', 'pet.timer_format',
};
-- Where settings hold one of them.
local function places(settings, dotted)
    local parts, out = {}, {};
    for part in dotted:gmatch('[^.]+') do parts[#parts + 1] = part; end;
    local function join(path, part) return path == '' and tostring(part) or path .. '.' .. tostring(part); end;
    local function walk(node, index, path)
        if type(node) ~= 'table' then return; end;
        local part = parts[index];
        if part == '*' then
            for key, child in pairs(node) do walk(child, index + 1, join(path, key)); end;
        elseif index == #parts then
            if node[part] ~= nil then out[#out + 1] = join(path, part); end;
        else
            walk(node[part], index + 1, join(path, part));
        end;
    end;
    walk(settings, 1, '');
    return out;
end;
-- Every one settings hold, on one line; empty when there is none.
local function held(settings)
    local out = {};
    for _, dotted in ipairs(UNUSED) do
        for _, place in ipairs(places(settings, dotted)) do out[#out + 1] = place; end;
    end;
    return table.concat(out, ' ');
end;

-- Fresh settings hold none of them.
assert(held(defaults.make()) == '', 'Fresh settings hold none: ' .. held(defaults.make()));
assert(held(defaults.tidy(defaults.make())) == '', 'Nor once tidied.');

-- Exports. Each display's string carries values of its own, which land as they are.
local made = defaults.tidy(defaults.make());
local p, buffs = made.party_ui, made.panels.self_buffs;
p.effects.growth, p.effects.icon_size, p.style.opacity, p.native.gap, p.name_display = 'left', 40, 0.5, 12, 'short';
buffs.max_rows, buffs.show_source, buffs.warning_seconds = 9, true, 20;
made.overhead.max_units, made.overhead.distance_cap, made.overhead.hide_in_cities = 7, 25, false;
made.rolls.max_rolls, made.rolls.show_odds = 3, false;
made.pet.max_effects, made.pet.show_vitals = 5, false;
local function values(settings)
    local party, panel = settings.party_ui, settings.panels.self_buffs;
    return {
        party_ui = { party.effects.growth, party.effects.icon_size, party.style.opacity, party.native.gap, party.name_display },
        self_buffs = { panel.max_rows, panel.show_source, panel.warning_seconds },
        overhead = { settings.overhead.max_units, settings.overhead.distance_cap, settings.overhead.hide_in_cities },
        rolls = { settings.rolls.max_rolls, settings.rolls.show_odds },
        pet = { settings.pet.max_effects, settings.pet.show_vitals },
    };
end;
local wanted, plain = values(made), values(defaults.tidy(defaults.make()));
assert(equal(values(defaults.tidy(store.copy(made))), wanted), 'Fixture: the tidy keeps the values made has.');
for part, value in pairs(wanted) do assert(not equal(value, plain[part]), 'Fixture: fresh settings differ in ' .. part .. '.'); end;
-- The string of one display or a whole profile, as read.
local function string_of(settings, case)
    return assert(share.read(assert(share.export(settings, case[1], case[2], 'Tester'))), 'Fixture: the string is made.');
end;
for _, case in ipairs({ { 'element', 'party_ui' }, { 'element', 'self_buffs' }, { 'element', 'overhead' }, { 'element', 'rolls' },
    { 'element', 'pet' }, { 'profile' } }) do
    local name = case[2] or 'profile';
    local payload = string_of(made, case);
    for _, mode in ipairs({ 'add', 'replace' }) do
        local candidate = assert(share.candidate(defaults.tidy(defaults.make()), payload, mode));
        assert(held(candidate) == '', 'An import brings none of them: ' .. name .. ' ' .. mode .. ': ' .. held(candidate));
        local landed = values(candidate);
        for part, value in pairs(wanted) do
            if not case[2] or part == case[2] then
                assert(equal(landed[part], value), 'The string\'s own values land as they are: ' .. name .. ' ' .. mode .. ' ' .. part);
            end;
        end;
        -- A string of fresh settings changes nothing.
        local base = defaults.tidy(defaults.make());
        local lines = share.changes(base, assert(share.candidate(base, string_of(base, case), mode)));
        assert(#lines == 1 and lines[1] == 'Nothing changes.', 'Nothing changes: ' .. name .. ' ' .. mode .. ': ' .. table.concat(lines, ' | '));
    end;
end;
return 'Fresh settings hold none of what nothing reads, and an export\'s own values land as they are';
