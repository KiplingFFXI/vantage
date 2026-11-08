-- Overhead icons' Sample displays: with the icons and their samples on, one block of sample effects above your own
-- head, laid out as the unit type the page edits, through that type's filters and limits; in the middle of the
-- screen, a third of the way down, when you aren't on screen; nothing while they are off, the samples are off or
-- the blocks are hidden. The samples light their dispellable buffs whenever the light is on, keep /vg report's count
-- of real icons, go on the foreground draw list so the settings window doesn't cover them, hold their size through
-- 0.6 px as a block does, and make nothing per frame. A party or alliance sample shows sample party cooldowns when
-- they go over heads, and show conditions that hide the blocks leave the samples. Through vantage.lua, a frame draws
-- them and stops when they end.
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

local bit = require('bit');
local imgui = require('imgui');
-- A draw list that counts its calls and keeps nothing. The samples take it as the foreground list; the background
-- list is the real blocks', and the samples never ask for it.
local calls, list, behind = {}, {}, 0;
for _, name in ipairs({ 'AddImage', 'AddRect', 'AddRectFilled', 'AddText', 'AddImageQuad', 'AddLine', 'AddPolyline' }) do
    calls[name] = 0;
    list[name] = function() calls[name] = calls[name] + 1; end;
end
rawset(imgui, 'GetForegroundDrawList', function() return list; end);
rawset(imgui, 'GetBackgroundDrawList', function() behind = behind + 1; return list; end);
rawset(imgui, 'col32', function(a, r, g, b) return bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r); end);
rawset(imgui, 'CalcTextSize', function(text) return #tostring(text) * 7, 14; end);
-- The mock makes a record of every other call, so the ones a frame makes keep nothing here.
local function nothing() end
rawset(imgui, 'PushFont', nothing);
rawset(imgui, 'PopFont', nothing);
rawset(imgui, 'GetFont', function() return 1; end);
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);

local W = require('overhead_fixture');
local overhead = require('core.overhead');
local camera = require('core.camera');
local draw = require('ui.overhead_icons');
local preview = require('ui.overhead_preview');
local unit, sample_plan, slots = preview._unit, preview._plan, draw._slots;
-- A WAR, who can take nothing off.
MOCK.player.main_job, MOCK.player.main_level = 1, 75;

local settings = W.settings();
local config = settings.overhead;
local snapshot, view = W.snapshot(), W.view();
local function reset() for key in pairs(calls) do calls[key] = 0; end end
local function frame(hidden, seconds)
    reset();
    W.frame(view, settings, snapshot, hidden, seconds);
    return preview.draw(settings, snapshot, W.now);
end
local function texts(count)
    for n = 1, count do
        local text = slots[1].text[n];
        assert(not text:find('?', 1, true) and not text:lower():find('unknown', 1, true), 'No ? and no unknown: ' .. text);
    end
end
-- The middle of your name on screen as the camera has it: a Hume's head, 1.8 yalms, plus the type's offset, and the
-- name half a yalm over it, as You have it.
local function head(offset)
    local lift = config.types.self.name_lift;
    assert(lift == 0.5, 'Fixture: your name sits half a yalm over your head.');
    local sx, sy, depth = camera.project(overhead.world_point(AshitaCore:GetMemoryManager():GetEntity(), W.self, 1.8 + lift + (offset or 0)));
    return sx, sy, depth;
end
-- 10 yalms deep, 91.8 px a yalm: the name and the cursor are both at their largest, 24 and 16 px, with the gap of 3
-- over them. Half the name sits over its middle.
local above_target, above_name = 24 / 2 + 16 + 3, 24 / 2 + 3;

-- Off, and the samples off: nothing.
config.enabled, config.preview = false, true;
assert(frame() == 0 and calls.AddImage == 0, 'With overhead icons off the samples draw nothing.');
config.enabled, config.preview = true, false;
assert(frame() == 0 and calls.AddImage == 0, 'With the samples off nothing is drawn.');

-- On: a mob block above your head, the target of a single bar of 8, the rest left out with nothing after.
config.preview = true;
local drawn = frame();
local sx, sy, depth = head();
assert(camera.pixels_per_yalm(depth) * 0.33 > 24 and camera.pixels_per_yalm(depth) * 0.4 > 16, 'Fixture: up close.');
assert(drawn == 8 and calls.AddImage == 8 and slots[1].count == 8, 'A single bar of 8 sample icons: ' .. drawn);
assert(behind == 0, 'The samples go on the foreground draw list, over the settings window.');
assert(sample_plan.units[1] == unit and unit.kind == 'mob' and unit.target, 'The mob sample is the target.');
assert(unit.anchor_x == math.floor(sx + 0.5) and unit.anchor_y == math.floor(sy - above_target + 0.5),
    'It sits over your head, above the name and the target cursor: ' .. unit.anchor_x .. ' ' .. unit.anchor_y);
assert(unit.size == math.floor(overhead.icon_size(false, 1, 0, '', depth, true, config, 1, 1) + 0.5) and unit.size == 26,
    'Sized as a target mob at your depth: ' .. unit.size);
local lit, blank = 0, 0;
for n = 1, slots[1].count do
    if slots[1].lit[n] then lit = lit + 1; end
    if slots[1].text[n] == '' then blank = blank + 1; end
end
assert(lit == 4, 'Its four dispellable buffs light even for a WAR: ' .. lit);
assert(blank == 2, 'Protect and Stoneskin, with no known time, have no countdown and their normal look: ' .. blank);
texts(slots[1].count);
assert(draw.drawn() == 0, '/vg report counts only the real icons.');
-- A little nearer, the raw size rounds up but is within 0.6 px: it holds, as a block's does.
W.entities[W.self].y = 0.11;
frame();
sx, sy, depth = head();
local raw = overhead.icon_size(false, 1, 0, '', depth, true, config, 1, 1);
assert(math.floor(raw + 0.5) == 27 and raw - 26 <= 0.6, ('Fixture: %.3f px rounds up within 0.6 px'):format(raw));
assert(unit.size == 26, 'The size holds through 0.6 px: ' .. unit.size);
-- Another type shows its own size at once, here the same raw size, and so does going back.
config.types.pet.size_scale = 1.2;
preview.show('pet');
frame();
assert(unit.kind == 'pet' and unit.size == 27, 'A new type takes its size at once: ' .. unit.size);
preview.show('mob');
frame();
assert(unit.kind == 'mob' and unit.size == 27, 'Back to Mobs, its size at once: ' .. unit.size);
-- Past 0.6 px it moves.
W.entities[W.self].y = -0.3;
frame();
assert(unit.size == 26, 'Past 0.6 px it takes the new size: ' .. unit.size);
W.entities[W.self].y, config.types.pet.size_scale = 0, 1;
assert(frame() == 8 and unit.size == 26, 'Back where it was.');
-- The type's own offsets move it; its size scale sizes it.
config.types.mob.world_offset, config.types.mob.screen_x, config.types.mob.size_scale = 1, 30, 1.5;
frame();
sx, sy, depth = head(1);
assert(unit.anchor_x == math.floor(sx + 30 + 0.5) and unit.anchor_y == math.floor(sy - above_target + 0.5)
    and unit.size == math.floor(overhead.icon_size(false, 1, 0, '', depth, true, config, 1, 1.5) + 0.5) and unit.size == 40,
    'The type\'s head offset, side offset and size scale: ' .. unit.anchor_x .. ' ' .. unit.anchor_y .. ' ' .. unit.size);
config.types.mob.world_offset, config.types.mob.screen_x, config.types.mob.size_scale = 0, 0, 1;
-- Split with the crowd control slot: buffs left of the middle, Sleep larger beside it.
config.types.mob.layout = 'split';
assert(frame() == 10, 'Split takes 4 buffs and 6 debuffs.');
local big = 0;
for n = 1, slots[1].count do
    local effect = slots[1].effect[n];
    if effect.kind == 'buff' then assert(slots[1].x[n] < 0, 'Buffs sit left of the middle.'); end
    if effect.effect == 2 then big = slots[1].size[n]; end
end
assert(big == math.floor(26 * 1.4 + 0.5), 'Sleep takes the crowd control slot: ' .. big);
-- Two lines, and no light when it is off.
config.types.mob.layout, config.dispel_light = 'lines', false;
local shown = frame();
for n = 1, slots[1].count do assert(not slots[1].lit[n], 'Nothing lights with the light off.'); end
assert(shown == 11, 'Two lines: all 7 debuffs and 4 buffs: ' .. shown);
config.types.mob.layout, config.dispel_light = 'single', true;

-- Another type: a party member at your size, through the party's filters (no one else's buffs, no usual long ones).
preview.show('party');
drawn = frame();
sx, sy, depth = head();
assert(drawn == 8 and not unit.target and unit.kind == 'party', 'Party: Poison, Slow, a roll, March, a Barspell, a stance, Haste and Refresh: ' .. drawn);
assert(unit.anchor_y == math.floor(sy - above_name + 0.5), 'Not the target, so no room for the cursor.');
assert(unit.size == math.floor(overhead.icon_size(true, 1, 0, '', depth, false, config, 1, 1) + 0.5), 'At a Hume\'s size.');
for n = 1, slots[1].count do
    local id = slots[1].effect[n].effect;
    assert(id ~= 42 and id ~= 40 and id ~= 251 and id ~= 253, 'The party filters leave out Regen, Protect, Food and Signet: ' .. id);
end
config.types.party.kinds = 'debuff';
assert(frame() == 2, 'Debuffs only.');
config.types.party.kinds = 'all';
-- With party cooldowns over heads, a party or alliance sample gains a line of the sample estimates
-- (core/party_cooldowns.lua); a mob sample gains none.
local function estimates()
    local count = 0;
    for n = 1, slots[1].count do if slots[1].cooldown[n] then count = count + 1; end end
    return count;
end
-- The party cooldown watch is off at first, and its line shows only while it is on.
settings.party_cooldowns.enabled = true;
settings.party_cooldowns.overhead = true;
drawn = frame();
assert(estimates() == 5 and drawn == 13, 'The party sample shows five sample estimates too: ' .. estimates() .. ' of ' .. drawn);
preview.show('alliance');
frame();
assert(estimates() == 5, 'So does an alliance sample.');
preview.show('mob');
frame();
assert(estimates() == 0, 'A mob sample has none.');
settings.party_cooldowns.overhead = false;
preview.show('party');
frame();
assert(estimates() == 0, 'With the line off, none.');
preview.show('mob');

-- Off screen: in first person, turned away, or with no camera, the block sits a third of the way down the middle,
-- with the room a near name and cursor take over it.
local function fixed(label)
    assert(unit.anchor_x == 960 and unit.anchor_y == 360 - above_target and unit.size == 26, label .. ': ' .. unit.anchor_x .. ' ' .. unit.anchor_y .. ' ' .. unit.size);
end
W.first_person = 1;
assert(frame() == 8, 'Drawn in first person.');
fixed('In first person');
-- With no cursor height in the world it leaves no room for one there either, only the name's.
config.layout.target_height = 0;
frame();
assert(unit.anchor_y == 360 - above_name and unit.arrow_px == 0, 'No room for the cursor: ' .. tostring(unit.anchor_y));
config.layout.target_height = 0.4;
W.first_person = 0;
W.entities[W.self].x = 400;
assert(frame() == 8 and overhead.plan.valid, 'Drawn with you off screen.');
fixed('Off screen');
W.entities[W.self].x = 0;
W.unreadable = true;
frame(false, 1);
assert(not overhead.plan.valid and frame() == 8, 'Drawn with no camera.');
fixed('With no camera');
W.unreadable = nil;
-- Hidden: nothing, as no block shows.
assert(frame(true) == 0 and calls.AddImage == 0, 'Nothing while the displays are hidden.');
W.zoning = 1;
assert(frame() == 0, 'Nothing while zoning.');
W.zoning = 0;
assert(frame() == 8, 'Back once they show.');
-- Their show conditions hide the real blocks, not the samples: those still sit over your head.
reset();
W.now = W.now + 0.125;
overhead.update(view, settings, snapshot, W.now, false, true);
sx, sy = head();
assert(preview.draw(settings, snapshot, W.now) == 8 and unit.anchor_x == math.floor(sx + 0.5) and unit.anchor_y == math.floor(sy - above_target + 0.5),
    'The samples still show over your head while the show conditions hide the blocks: ' .. unit.anchor_x .. ' ' .. unit.anchor_y);
assert(overhead.plan.count == 0 and overhead.plan.hidden == 'Its When to show choices hide it here.', 'and no real block is placed.');

-- Nothing made per frame, measured as test_overhead_draw_allocation.lua measures.
local leak, made = false, nil;
local function frames(count)
    for i = 1, count do
        W.frame(view, settings, snapshot, false, 1 / 60);
        preview.draw(settings, snapshot, W.now);
        if leak and i % 6 == 0 then made = {}; end
    end
end
-- Calls n deep, so the Lua stack is grown back past what the deepest frame needs.
local function regrow(n) if n > 0 then return 1 + regrow(n - 1); end return 0; end
local function measure(count)
    jit.off(); jit.flush();
    frames(60);
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    -- The collection shrinks the Lua stack, and the next call deep enough grows it back once, about 1.7 KB, which is
    -- LuaJIT's and not a frame's. The deepest call a frame makes can come seconds apart, so the stack grows back first.
    regrow(300);
    frames(60);
    local least = math.huge;
    for _ = 1, 2 do
        local before = collectgarbage('count');
        frames(count);
        least = math.min(least, (collectgarbage('count') - before) / count);
    end
    collectgarbage('restart');
    jit.on();
    return least;
end
frames(240 * 60);
local each = measure(600);
assert(each < 0.002, ('The samples make %.4f KB a frame; nothing expected'):format(each));
leak = true;
each = measure(600);
assert(each >= 0.002 and made, ('One table made ten times a second shows as %.4f KB a frame'):format(each));
leak = false;
-- A party or alliance sample makes nothing either: with the watch off its cooldown samples aren't made, and with
-- their line showing they are refilled, not made again.
settings.party_cooldowns.enabled, settings.party_cooldowns.overhead = false, true;
for _, kind in ipairs({ 'party', 'alliance' }) do
    preview.show(kind);
    assert(frame() > 0 and estimates() == 0, kind .. ' sample with the watch off: no estimates.');
    each = measure(600);
    assert(each < 0.002, ('The %s sample makes %.4f KB a frame with the watch off; nothing expected'):format(kind, each));
end
settings.party_cooldowns.enabled = true;
assert(frame() > 0 and estimates() == 5, 'With the watch on, the alliance sample has its line.');
each = measure(600);
assert(each < 0.002, ('The alliance sample makes %.4f KB a frame with its line; nothing expected'):format(each));
preview.show('mob');

-- Through vantage.lua: a frame draws the samples while they are on, and nothing once they end.
local app = dofile(ADDON_DIR .. '/vantage.lua');
MOCK.fire('load'); app.refresh(1);
local s = app.state.settings;
s.overhead.enabled, s.overhead.preview = true, true;
reset(); MOCK.frame();
assert(calls.AddImage == 8 and behind == 0, 'A frame draws the 8 sample icons, on the foreground list: ' .. calls.AddImage);
local event = { command = '/vg overhead preview' };
MOCK.fire('command', event);
reset(); MOCK.frame();
assert(not s.overhead.preview and calls.AddImage == 0, 'With the samples ended nothing is drawn: ' .. calls.AddImage);
return 'Overhead sample icons show over your head or in the middle of the screen, and nothing when off';
