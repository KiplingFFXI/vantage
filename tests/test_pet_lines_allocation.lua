-- The pet display's optional lines (core/pet_lines.lua) make nothing at a refresh once running, while nothing they
-- show changes: every tick on, with the notices asked for, for an automaton, an avatar, a wyvern and a jug pet. Measured
-- as test_party_strip_allocation.lua does, with the collector stopped and the compiler off. The resources here make a
-- new table at each lookup, so a lookup at each refresh shows, and they count the lookups too. Breath and Reward read
-- only the gear slots that can hold what they look for, and the build lines follow the build the server sent, whether
-- it comes in new tables or the same ones refilled.
local lines, pet = require('core.pet_lines'), require('core.pet');

local looked = 0;
local spells, skills, items = { [144] = 'Fire', [4] = 'Cure IV' }, { [1944] = 'Shield Bash' }, { [0x2100 + 3] = 'Inhibitor' };
local resources = {
    GetSpellById = function(_, id) looked = looked + 1; return spells[id] and { Name = { spells[id] } } or nil; end,
    GetAbilityById = function() looked = looked + 1; return nil; end,
    GetItemById = function(_, id) looked = looked + 1; return items[id] and { Name = { items[id] } } or nil; end,
    GetString = function(_, list, id) looked = looked + 1; return list == 'monsters.abilities' and skills[id + 256] or nil; end,
};
AshitaCore.GetResourceManager = function() return resources; end;

-- What you have on, by slot, and how many slots a fill read. These tables are kept, so the reads themselves make nothing.
local worn = { [3] = 17016, [4] = 12519, [6] = 13706, [8] = 15140 };
local reads, equipped, held = 0, {}, {};
for slot = 0, 15 do equipped[slot], held[slot] = { Index = worn[slot] and 0x100 + slot or 0 }, { Id = worn[slot] }; end
local inventory = { GetEquippedItem = function(_, slot) reads = reads + 1; return equipped[slot]; end,
    GetContainerItem = function(_, _, index) return held[index]; end };
local entity = { GetHPPercent = function() return 63; end, GetDistance = function() return 49; end,
    GetLocalPositionX = function() return 1; end, GetLocalPositionY = function() return 2; end, GetLocalPositionZ = function() return 3; end };
local party = { GetMemberHPPercent = function() return 100; end, GetMemberHP = function() return 1000; end, GetMemberIsActive = function() return 0; end,
    GetMemberTargetIndex = function() return 0; end, GetMemberName = function() return ''; end };
local player = { GetHPMax = function() return 1000; end, GetStat = function() return 50; end, GetStatModifier = function() return 10; end };
local memory = { GetEntity = function() return entity; end, GetParty = function() return party; end, GetPlayer = function() return player; end,
    GetInventory = function() return inventory; end };
AshitaCore.GetMemoryManager = function() return memory; end;

local every = pet.make();
for _, key in ipairs(pet.extras) do every[key] = true; end
local function announce() end
local CRAB = 0x1000301;
local crab = { id = CRAB, index = 0x301, name = 'Land Crab' };
local function snapshot(job, sub, mine)
    mine.target_id, mine.since = CRAB, 40;
    return { valid = true, id = 1001, job = job, sub_job = sub, mp = 479, ammo = worn[3], self_effects = { { effect = 300 } },
        entities = { [CRAB] = crab }, pet = mine };
end

-- Fills at one moment, so nothing on a line changes. A full collection shrinks the Lua stack, and the next fills grow
-- it back once, so a few run after it, with the collector stopped, before counting starts.
local made;
local function per_fill(watch, shown, now, config, state, count, leak)
    local function fills(times)
        for _ = 1, times do
            watch:track(now, state);
            watch:fill(shown, now, config, state, announce);
            if leak then made = {}; end
        end
    end
    jit.off(); jit.flush();
    fills(60);
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    fills(6);
    local before = collectgarbage('count');
    fills(count);
    local each = (collectgarbage('count') - before) / count;
    collectgarbage('restart');
    jit.on();
    return each;
end
-- What one more fill reads: resource lookups and gear slots.
local function one_fill(watch, shown, now, config, state)
    looked, reads = 0, 0;
    watch:track(now, state);
    watch:fill(shown, now, config, state, announce);
    return looked, reads;
end
local function names(shown)
    local out = {};
    for index = 1, shown.line_count do out[index] = shown.lines[index].name .. '=' .. tostring(shown.lines[index].value); end
    return table.concat(out, ', ');
end

-- An automaton with four attachments that fire, one the game names and two it doesn't, its skills and its stats.
local build = { head = 2, frame = 0x21, attachments = { 1, 97, 194, 230, 3, 107, 104, 0, 0, 0, 0, 0 },
    skills = { { 245, 269 }, { 0, 0 }, { 120, 203 } }, stats = { { 60, 5 }, { 55, 0 }, { 58, 2 }, { 50, 0 }, { 30, 0 }, { 28, 0 }, { 25, 0 } } };
local cases = {
    { 'an automaton', snapshot(18, 0, { id = 77, index = 0x705, name = 'Ironsides', automaton = build }),
        { kind = 'pet_action', entity_id = 77, category = 11, id = 1944, amount = 120 }, 0 },
    { 'an avatar', snapshot(15, 0, { id = 78, index = 0x706, name = 'Ifrit' }),
        { kind = 'pet_start', entity_id = 78, category = 8, id = 144 }, 0 },
    { 'a wyvern', snapshot(14, 3, { id = 79, index = 0x707, name = 'Azure' }),
        { kind = 'pet_action', entity_id = 79, category = 4, id = 4, amount = 0 }, 1 },
    { 'a jug pet', snapshot(9, 0, { id = 80, index = 0x708, name = 'SheepFamiliar' }),
        { kind = 'pet_action', entity_id = 80, category = 4, id = 144, amount = 212 }, 4 },
};
local measured = {};
for _, case in ipairs(cases) do
    local state, action = case[2], case[3];
    local watch, shown = lines.new(), { name = 'Pet', hpp = 60, tp = 500 };
    watch:track(1, state);
    -- An avatar's MP goes down by 7 at each of the game's ticks before the counting.
    for step = 0, 3 do
        state.mp = 500 - step * 7;
        watch:track(88 + step * 3, state);
        watch:fill(shown, 88 + step * 3, every, state, announce);
    end
    watch:observe(action, 95);
    local each = per_fill(watch, shown, 100, every, state, 600);
    local lookups, slots_read = one_fill(watch, shown, 100, every, state);
    case.each, case.lookups, case.slots_read, case.watch, case.shown = each, lookups, slots_read, watch, shown;
    measured[#measured + 1] = ('%s %.4f KB, %d lookups, %d slots'):format(case[1], each, lookups, slots_read);
end
measured = table.concat(measured, '; ');
for _, case in ipairs(cases) do
    assert(case.each < 0.002, ('The lines for %s make %.4f KB a fill; nothing expected. All: %s'):format(case[1], case.each, measured));
    assert(case.lookups == 0, ('Nothing is looked up again for %s: %s'):format(case[1], measured));
    assert(case.slots_read == case[4], ('The lines for %s read %d gear slots, not %d'):format(case[1], case.slots_read, case[4]));
    assert(per_fill(case.watch, case.shown, 100, every, case[2], 600, true) >= 0.002 and made, 'Fixture: one table a fill shows.');
end

-- Each case shows what its lines are for, so the counting above covered them.
local function line_of(shown, name)
    for index = 1, shown.line_count do if shown.lines[index].name == name then return shown.lines[index]; end end
end
local function value(shown, name) local line = line_of(shown, name); return line and line.value; end
local function filled(case)
    local watch, shown = lines.new(), { name = 'Pet', hpp = 60, tp = 500 };
    watch:track(100, case[2]);
    watch:observe(case[3], 99);
    watch:fill(shown, 100, every, case[2], announce);
    return shown;
end
local automaton, avatar, wyvern, jug = filled(cases[1]), filled(cases[2]), filled(cases[3]), filled(cases[4]);
assert(value(automaton, 'Fighting') == 'Land Crab 63%' and value(automaton, 'Last move') == 'Shield Bash 120' and value(automaton, 'Distance') == '7.0'
    and value(automaton, 'Out for') == '1:00' and value(automaton, 'Economizer') == 'Not known yet' and line_of(automaton, 'Shield Bash')
    and value(automaton, 'Build') == 'Valoredge / Valoredge' and value(automaton, 'Inhibitor') == 'Attachment 107'
    and line_of(automaton, 'STR 65  DEX 55  VIT 60  AGI 50'), 'Fixture: the automaton\'s lines: ' .. names(automaton));
assert(value(avatar, 'Casting') == 'Fire' and value(avatar, 'MP cost'), 'Fixture: the avatar\'s lines: ' .. names(avatar));
assert(value(wyvern, 'Breath') == 'At 50% HP' and value(wyvern, 'Last move') == 'Cure IV', 'Fixture: the wyvern\'s lines: ' .. names(wyvern));
assert(value(jug, 'Reward') == 'Heals 162' and value(jug, 'Last move') == 'Fire 212', 'Fixture: the jug pet\'s lines: ' .. names(jug));

-- The build lines follow the build: a page in new tables, or the same tables refilled, makes them again, and they read
-- as a fresh set of lines made from that build does.
local only = pet.make();
only.show_build = true;
local function lines_of(shown)
    local out = {};
    for index = 1, shown.line_count do
        local line = shown.lines[index];
        out[index] = table.concat({ line.name, tostring(line.value), tostring(line.details) }, '|');
    end
    return table.concat(out, '\n');
end
local state = cases[1][2];
local kept, kept_shown = lines.new(), {};
local function compare(what)
    kept:fill(kept_shown, 200, only, state);
    local fresh, fresh_shown = lines.new(), {};
    fresh:fill(fresh_shown, 200, only, state);
    assert(lines_of(kept_shown) == lines_of(fresh_shown), what .. ':\n' .. lines_of(kept_shown) .. '\nagainst\n' .. lines_of(fresh_shown));
    return kept_shown;
end
compare('The first build');
build.attachments[5], build.attachments[8] = 0, 9;
compare('An attachment changed in place');
build.stats[1][2], build.skills[2][2] = 9, 180;
local changed = compare('A stat and a skill changed in place');
assert(line_of(changed, 'STR 69  DEX 55  VIT 60  AGI 50') and value(changed, 'Ranged skill') == '0 / 180', 'They read the new values: ' .. names(changed));
build.head, build.frame = 4, 0x23;
assert(value(compare('A head and a frame changed in place'), 'Build') == 'Stormwaker / Stormwaker', 'The build reads the new head.');
state.pet.automaton = { head = 4, frame = 0x23, attachments = { 1, 97 }, skills = build.skills, stats = { { 60, 5 }, { 55, 0 } } };
local short = compare('A new page with fewer attachments and stats');
assert(value(short, 'Strobe') == 'Shock Absorber' and short.line_count == 5, 'Two attachments, no stat lines: ' .. names(short));
state.pet.automaton = build;
compare('The first build again');
build.attachments = { 1, 97, 194, 230, 0, 107, 104 };
assert(not line_of(compare('The same attachments, less the last ones'), 'Strobe II'), 'An attachment that is no longer on goes.');
