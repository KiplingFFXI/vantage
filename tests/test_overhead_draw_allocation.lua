-- Drawing overhead icons makes nothing per frame once running: ten units with eight icons each in all three layouts,
-- countdowns ticking, a lit mob buff, the crowd control slot, overlapping blocks and the shared hide rules. Measured as
-- test_overhead_allocation.lua does, with the collector stopped and the compiler off, on a draw list that keeps
-- nothing, after the frames that grow the stack back.
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

-- ImGui as the game gives it: a draw list whose calls keep nothing, col32 packing a color, text measured.
local bit = require('bit');
local imgui = require('imgui');
local function nothing() end
local list = { AddImage = nothing, AddRect = nothing, AddRectFilled = nothing, AddText = nothing, AddImageQuad = nothing,
    AddLine = nothing, AddPolyline = nothing };
rawset(imgui, 'GetBackgroundDrawList', function() return list; end);
rawset(imgui, 'col32', function(a, r, g, b) return bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r); end);
rawset(imgui, 'CalcTextSize', function(text) return #tostring(text) * 7, 14; end);
rawset(imgui, 'PushFont', nothing);
rawset(imgui, 'PopFont', nothing);
rawset(imgui, 'GetFont', function() return 1; end);
require('ui.icons')._set_loader_for_tests(function(id) return 5000 + id; end);

local W = require('overhead_fixture');
local overhead = require('core.overhead');
local draw = require('ui.overhead_icons');
local plan = overhead.plan;
local player = AshitaCore:GetMemoryManager():GetPlayer();
player.HasSpell = function(_, id) return id == 260; end;
MOCK.player.main_job, MOCK.player.main_level = 5, 75;

local settings = W.settings();
local types = settings.overhead.types;
types.party.buffs_mine_only = false;
types.mob.layout = 'single';
settings.effect_filters = { enabled = true, rules = { { enabled = true, effect = 253, kind = 'all', name = '', job = 0, scope = 'all' },
    { enabled = true, effect = 0, kind = 'buff', name = 'nobody', job = 0, scope = 'enemy' } } };
local compiled = require('core.effect_filters').compile(settings.effect_filters);
-- Six mobs (the target, one in Split with crowd control) close together so the blocks overlap, and four members.
local subjects, rows, members, sequence = {}, {}, {}, 0;
local function give(entity, scope, count, debuffs, source)
    local effects = {};
    for i = 1, count do
        sequence = sequence + 1;
        local debuff = i <= debuffs;
        local row = { entity_id = entity, effect = debuff and 100 + i or 30 + i, kind = debuff and 'debuff' or 'buff', present = true,
            status = 'server', priority = i == 1 and 80 or 0, first_seen = sequence, first_sequence = sequence,
            key = entity .. ':' .. i, remaining = 20 + i * 7, scope = scope, source = source, mine = source == 1001 };
        effects[i], rows[#rows + 1] = row, row;
    end
    subjects[entity] = { effects = effects };
end
for i = 0, 5 do
    W.unit(0x200 + i, 0x1000200 + i, 'mob', (i % 3) * 0.5, -5 - i * 0.3, { name = 'Mob ' .. i });
    give(0x1000200 + i, 'enemy', 10, 6, 1001);
end
for i = 1, 4 do
    W.unit(0x400 + i, 1001 + i, 'player', i - 2.5, -2, { name = 'Member' .. i, race = i });
    members[#members + 1] = { id = 1001 + i, index = 0x400 + i, scope = 'party' };
    give(1001 + i, 'party', 12, 6, 1001);
end
W.target = 0x200;
local snapshot, view = W.snapshot(members), W.view(rows);
local recipients = require('core.effect_filters').recipients(snapshot);

local leak, made, drawn = false, nil, 0;
local function frames(count)
    for i = 1, count do
        W.frame(view, settings, snapshot, false, 1 / 60);
        -- Timers tick down and start over, as rows do.
        for _, row in ipairs(rows) do
            row.remaining = row.remaining - 1 / 60;
            if row.remaining < 0 then row.remaining = row.remaining + 90; end
        end
        drawn = draw.draw(plan, subjects, settings, W.now, compiled, recipients);
        if leak and i % 6 == 0 then made = {}; end
    end
end
local function measure(count)
    jit.off(); jit.flush();
    frames(60);
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    -- After a full collection the Lua stack and the VM's own tables can grow back once, about 1.4 KB, in whichever
    -- window it lands. That is not a frame's own garbage, which shows in every window: so a second goes by first and
    -- the smaller of two windows counts.
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
-- Warm: every countdown each timer shows, measured once.
frames(90 * 60);
assert(plan.valid and plan.count == 10, 'Ten units placed: ' .. plan.count .. ' ' .. tostring(plan.hidden));
assert(drawn == 80, 'Eighty icons drawn: ' .. drawn);
local slots, lit, overlapping = draw._slots, 0, 0;
for index = 1, plan.count do
    for n = 1, slots[index].count do if slots[index].lit[n] then lit = lit + 1; end end
end
-- One frame drawn on a list that keeps where each icon goes: every block is drawn at its own anchor, in plan.order.
local corners = {};
list.AddImage = function(_, _, corner) corners[#corners + 1] = { corner[1], corner[2] }; end;
frames(1);
list.AddImage = nothing;
local at = 0;
for k = 1, plan.count do
    local index = plan.order[k];
    local slot, unit = slots[index], plan.units[index];
    for n = 1, slot.count do
        at = at + 1;
        assert(corners[at][1] == unit.anchor_x + slot.x[n] and corners[at][2] == unit.anchor_y + slot.y[n],
            'Each block is drawn at its own anchor: ' .. unit.name);
    end
    for other = 1, index - 1 do
        local held, owner = slots[other], plan.units[other];
        if held.count > 0 and slot.count > 0 and unit.anchor_x + slot.left < owner.anchor_x + held.right
            and owner.anchor_x + held.left < unit.anchor_x + slot.right and unit.anchor_y + slot.top < owner.anchor_y + held.bottom
            and owner.anchor_y + held.top < unit.anchor_y + slot.bottom then overlapping = overlapping + 1; end
    end
end
assert(at == #corners and lit > 0 and overlapping > 0, 'Lit buffs and overlapping blocks are drawn: ' .. lit .. ' ' .. overlapping);
local each = measure(600);
assert(each < 0.002, ('Drawing overhead icons makes %.4f KB a frame; nothing expected'):format(each));
leak = true;
each = measure(600);
leak = false;
assert(each >= 0.002 and made, ('One table made ten times a second shows as %.4f KB a frame'):format(each));
-- The other layouts too.
types.mob.layout, types.mob.cc_slot = 'split', true;
frames(90 * 60);
each = measure(600);
assert(drawn > 0 and each < 0.002, ('Split makes %.4f KB a frame'):format(each));
types.mob.layout, types.party.layout = 'lines', 'lines';
frames(90 * 60);
each = measure(600);
assert(drawn > 0 and each < 0.002, ('Two lines make %.4f KB a frame'):format(each));
