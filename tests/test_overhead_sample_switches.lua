-- The Overhead icons samples show the page's switches. A player's sample has one of your effects for each of the seven
-- groups, right after the debuffs: turning a switch off or on changes that group's icon and what the limit lets back in,
-- nothing else, with Only buffs I cast on or off. With all seven on the last is past a limit of 8, and shows as soon as
-- another goes. Regen is the buff someone else cast. A mob's sample has a Protect for Protect and Shell.
local event_scan, interface_scan, focus_scan = 0x110000, 0x120000, 0x130000;
local interface, event_flag = 0x210000, 0x220000;
local memory = { [event_scan + 1] = event_flag, [interface_scan + 10] = interface, [focus_scan] = interface + 0x54,
    [interface + 0xB4] = 0, [event_flag] = 0, [interface + 0x54] = 0 };
ashita.memory.find = function(_, _, pattern)
    return pattern:sub(1, 2) == 'A0' and event_scan or pattern:sub(1, 8) == '8B442404' and interface_scan or focus_scan;
end;
local function read(address) return memory[address]; end
ashita.memory.read_uint8, ashita.memory.read_uint32 = read, read;
require('core.client')._set_pages(function() return true; end);

local imgui = require('imgui');
local list = {};
for _, name in ipairs({ 'AddImage', 'AddRect', 'AddRectFilled', 'AddText', 'AddImageQuad', 'AddLine', 'AddPolyline' }) do list[name] = function() end; end
rawset(imgui, 'GetForegroundDrawList', function() return list; end);
rawset(imgui, 'GetBackgroundDrawList', function() return list; end);
rawset(imgui, 'CalcTextSize', function(text) return #tostring(text) * 7, 14; end);
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);

local W = require('overhead_fixture');
local draw = require('ui.overhead_icons');
local preview = require('ui.overhead_preview');
local switches = require('ui.overhead_defaults').switches;
local slots = draw._slots;
-- A WAR, who can take nothing off.
MOCK.player.main_job, MOCK.player.main_level = 1, 75;

local settings = W.settings();
local config = settings.overhead;
local snapshot, view = W.snapshot(), W.view();
config.enabled, config.preview = true, true;

-- The effect ids the sample draws, in order.
local function drawn()
    W.frame(view, settings, snapshot);
    preview.draw(settings, snapshot, W.now);
    local ids = {};
    for n = 1, slots[1].count do ids[n] = slots[1].effect[n].effect; end
    return ids;
end;
local function without(ids, others)
    local seen, out = {}, {};
    for _, id in ipairs(others) do seen[id] = true; end
    for _, id in ipairs(ids) do if not seen[id] then out[#out + 1] = id; end end
    return out;
end;
local function member(switch, id)
    for _, value in ipairs(switch.ids) do if value == id then return true; end end
    return false;
end;
local function same(a, b) return table.concat(a, ' ') == table.concat(b, ' '); end;

-- Flips one switch and back on the type, and gives what went and what came.
local function flip(t, switch)
    local before = drawn();
    t[switch.key] = not t[switch.key];
    local after = drawn();
    t[switch.key] = not t[switch.key];
    assert(same(drawn(), before), 'Turned back, the sample is as it was: ' .. switch.label);
    return without(before, after), without(after, before), before;
end;

-- Each switch, from one starting state: exactly its group's icon moves, and at most one other, the one the limit
-- let back in or pushed out. past names the switch whose row is over the limit.
local function every_switch(kind, state, past)
    local t = config.types[kind];
    for _, switch in ipairs(switches) do
        local label = kind .. ', ' .. state .. ', ' .. switch.label;
        local on = t[switch.key];
        local went, came = flip(t, switch);
        local own, other = on and went or came, on and came or went;
        if switch.key == past then
            assert(#went == 0 and #came == 0, 'Past the limit, it moves nothing: ' .. label);
        else
            assert(#own == 1 and member(switch, own[1]), 'The group\'s own icon moves: ' .. label);
            assert(#other <= 1, 'Only what the limit lets through moves with it: ' .. label);
            for _, id in ipairs(other) do assert(not member(switch, id), 'No other of the group: ' .. label); end
        end
    end
end;

local function all_on(t) for _, switch in ipairs(switches) do t[switch.key] = true; end end
for _, kind in ipairs({ 'party', 'self' }) do
    preview.show(kind);
    local t = config.types[kind];
    assert(t.layout == 'single' and t.limit == 8, 'Fixture: the default single bar of 8.');
    local fresh = {};
    for _, switch in ipairs(switches) do fresh[switch.key] = t[switch.key]; end
    local mine = t.buffs_mine_only;
    -- Ticked, the two Always show effects take the first places among the buffs, so the switches are tried without them.
    local copy_image, third_eye = t.show_copy_image, t.show_third_eye;
    t.show_copy_image, t.show_third_eye = false, false;

    -- As a new profile has them. Party leaves out the three usual long ones.
    every_switch(kind, 'fresh', kind == 'self' and 'show_signet' or nil);
    -- As the other way round on Only buffs I cast.
    t.buffs_mine_only = not mine;
    every_switch(kind, 'Only buffs I cast flipped', kind == 'self' and 'show_signet' or nil);
    t.buffs_mine_only = mine;
    -- With all seven on the eighth place goes to the sixth group, and a switch off lets the seventh in.
    all_on(t);
    every_switch(kind, 'all seven on', 'show_signet');
    local ids = drawn();
    assert(#ids == 8 and ids[1] == 3 and ids[2] == 13, 'The debuffs lead: ' .. table.concat(ids, ' '));
    assert(same({ ids[3], ids[4], ids[5], ids[6], ids[7], ids[8] }, { 310, 214, 40, 251, 100, 353 }), 'Then the groups in the page\'s order: ' .. table.concat(ids, ' '));
    t.show_rolls = false;
    assert(same(without(drawn(), ids), { 253 }), 'A switch off brings the last group in.');
    t.show_rolls = true;
    -- All off: Haste and Refresh, then Regen where the type shows what others cast.
    for _, switch in ipairs(switches) do t[switch.key] = false; end
    t.buffs_mine_only = true;
    assert(same(drawn(), { 3, 13, 33, 43 }), 'All off leaves the debuffs, Haste and Refresh.');
    t.buffs_mine_only = false;
    assert(same(drawn(), { 3, 13, 33, 43, 42 }), 'Regen is someone else\'s, so Only buffs I cast hides it.');
    -- The two Always show effects are someone else's too, and ticked they show with Only buffs I cast on.
    t.buffs_mine_only = true;
    t.show_copy_image = true;
    assert(same(drawn(), { 3, 13, 66, 33, 43 }), 'Copy Image ticked shows, whoever cast it.');
    t.show_third_eye = true;
    assert(same(drawn(), { 3, 13, 66, 67, 33, 43 }), 'So does Third Eye.');
    t.buffs_mine_only = mine;
    t.show_copy_image, t.show_third_eye = copy_image, third_eye;
    for key, value in pairs(fresh) do t[key] = value; end
end;

-- Only buffs I cast keeps all seven.
preview.show('party');
local party = config.types.party;
all_on(party);
party.buffs_mine_only = true;
party.limit = 12;
local ids = drawn();
assert(#ids == 11, 'All seven groups, the debuffs, Haste and Refresh stay with Only buffs I cast on: ' .. #ids);
party.limit = 8;
-- Ticked, a limit can't cut them: they come after the debuffs and before your own buffs.
party.show_copy_image, party.show_third_eye = true, true;
assert(same(drawn(), { 3, 13, 66, 67, 310, 214, 40, 251 }), 'The two Always show effects come first among the buffs.');
party.show_copy_image, party.show_third_eye = false, false;

-- A mob's Protect, as the first of its buffs. No other switch has a row there.
preview.show('mob');
for _, light in ipairs({ true, false }) do
    config.dispel_light = light;
    local mob = config.types.mob;
    for _, switch in ipairs(switches) do
        local went, came = flip(mob, switch);
        if switch.key == 'show_protect_shell' then
            assert(same(went, { 40 }) and #came == 1, 'Protect and Shell moves the mob\'s Protect.');
        else
            assert(#went == 0 and #came == 0, 'No row of a mob\'s moves for ' .. switch.label);
        end
    end
end;
