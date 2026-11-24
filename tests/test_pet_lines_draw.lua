-- How the pet display draws its optional lines (ui/pet_display.lua), over the pet fixture's game: a line with a
-- deadline shows its countdown over a fill, one that wants attention is in the warning color, the display grows to
-- hold every line, pointing at a line, the MP number or the Sic mark gives its tooltip, a value too wide for its row
-- starts at the row's left, and the Sic mark keeps clear of the TP number.
local fx = require('pet_fixture')();
local game, settings, display, theme = fx.game, fx.settings, require('ui.pet_display'), require('ui.theme');
local config = settings.pet;
local function shown() return fx.app.state.view.pet; end
AshitaCore.GetResourceManager = function()
    return { GetItemById = function() return nil; end, GetSpellById = function() return nil; end, GetAbilityById = function() return nil; end,
        GetString = function() return nil; end };
end;
local function page(build)
    local bytes = MOCK.bytes(0xA0);
    MOCK.put(bytes, 4, 1, 18);
    MOCK.put(bytes, 8, 1, build.head); MOCK.put(bytes, 9, 1, build.frame);
    for slot, byte in ipairs(build.attachments or {}) do MOCK.put(bytes, 0x09 + slot, 1, byte); end
    for i = 1, #build.name do bytes[0x57 + i] = build.name:byte(i); end
    MOCK.put(bytes, 0x68, 2, 780); MOCK.put(bytes, 0x6A, 2, 1000); MOCK.put(bytes, 0x6C, 2, build.mp or 0); MOCK.put(bytes, 0x6E, 2, build.max_mp or 0);
    for index = 1, 3 do MOCK.put(bytes, 0x6C + index * 4, 2, 200 + index); MOCK.put(bytes, 0x6E + index * 4, 2, 250 + index); end
    for index = 1, 7 do MOCK.put(bytes, 0x7C + index * 4, 2, 50 + index); end
    MOCK.fire('packet_in', MOCK.packet(0x044, bytes));
end
local function sync(index, name, hpp, mpp, tp, fighting)
    local bytes = MOCK.bytes(0x2C);
    MOCK.put(bytes, 8, 4, game.id); MOCK.put(bytes, 0x0C, 2, index); MOCK.put(bytes, 0x0E, 1, hpp); MOCK.put(bytes, 0x0F, 1, mpp or 0);
    MOCK.put(bytes, 0x10, 2, tp or 0); MOCK.put(bytes, 0x14, 4, fighting or 0);
    for i = 1, #name do bytes[0x17 + i] = name:byte(i); end
    MOCK.fire('packet_in', MOCK.packet(0x068, bytes));
end
-- What one frame drew: each text with its color, and how many filled boxes. spots holds where each text started.
local spots = {};
local function frame()
    local text = fx.draw();
    local inks, boxes = {}, 0;
    spots = {};
    for _, call in ipairs(MOCK.imgui_calls) do
        if call[1] == 'draw:AddText' then inks[call[6]] = call[5]; spots[call[6]] = MOCK.drawn[call][4][1];
        elseif call[1] == 'draw:AddRectFilled' then boxes = boxes + 1; end
    end
    return text, inks, boxes;
end
-- The tooltip spot of this kind under the pointer, trying each height of the display.
local function hover(kind, name)
    fx.moving.hover, fx.moving.mx = true, config.x + 40;
    local found;
    for y = config.y, config.y + 700 do
        fx.moving.my = y;
        fx.draw();
        if fx.spot and fx.spot.kind == kind and (not name or fx.spot.item.name == name) then found = fx.spot; break; end
    end
    fx.moving.hover, fx.moving.mx, fx.moving.my = false, -1, -1;
    return found;
end

-- A Stormwaker automaton with Strobe and Shock Absorber, out while Vantage watches, so both recasts have started.
local PUPPET, index = 0x1000703, 0x703;
local player = AshitaCore.GetMemoryManager().GetPlayer();
player.GetPetMPPercent, player.GetPetTP = function() return 40; end, function() return 300; end;
game.job = 18;
fx.step();
page({ name = 'Ironsides', head = 4, frame = 0x23, attachments = { 1, 97 }, mp = 168, max_mp = 420 });
game.pet = { index = index, id = PUPPET, name = 'Ironsides', flags = 0x02, hpp = 78 };
sync(index, 'Ironsides', 78, 40, 300);
fx.step();
local plain, _, plain_boxes = frame();
assert(not plain:find('|Strobe|', 1, true) and plain:find('|MP 40%|', 1, true), 'With no tick on, the display draws no line and the MP percent: ' .. plain);
assert(not hover('line') and not hover('mp') and not hover('sic'), 'And it has none of their tooltips.');

-- A line with a deadline: its name, its countdown and a fill behind them.
config.show_attachments = true;
fx.step();
local text, inks, boxes = frame();
assert(text:find('|Strobe|', 1, true) and text:find('|Shock Absorber|', 1, true), 'Each attachment has its line: ' .. text);
assert(text:find('|30s|', 1, true) or text:find('|29s|', 1, true), 'Strobe counts down from 30 seconds: ' .. text);
assert(text:find('|3m|', 1, true) or text:find('|2m|', 1, true), 'Shock Absorber counts down from 3 minutes: ' .. text);
assert(boxes == plain_boxes + 2, 'Each counting line has a fill: ' .. boxes .. ' against ' .. plain_boxes);
-- Past its recast with no maneuver up it wants attention, in the warning color, with no fill.
fx.step(31);
text, inks, boxes = frame();
local warning = theme.u32(settings.style.warning_color);
assert(text:find('|Needs Fire|', 1, true) and inks['Needs Fire'] == warning, 'A line that wants attention is in the warning color.');
assert(inks['Strobe'] ~= warning and boxes == plain_boxes + 1, 'Its name keeps its color, and only the line still counting has a fill.');
game.buffs = { { effect = 300, ends = MOCK.now + 60 } };
fx.status();
fx.step();
text, inks = frame();
assert(text:find('|Ready|', 1, true) and inks['Ready'] ~= warning, 'A ready one is in the plain color.');
-- Pointing at a line gives what it says about itself.
local spot = assert(hover('line', 'Strobe'), 'A line has a tooltip.');
assert(display.details(spot, MOCK.now) == spot.item.details and spot.item.details:find('provokes', 1, true), 'It says what the attachment does.');
config.show_attachments = false;

-- The MP number has a tooltip, and the percent has none.
config.exact_mp = true;
fx.step();
assert(fx.draw():find('|MP 168/420|', 1, true), 'The MP bar reads the number.');
spot = assert(hover('mp'), 'The MP number has a tooltip.');
assert(display.details(spot, MOCK.now):find('max MP', 1, true), 'It says where the number comes from.');
config.exact_mp = false;
fx.step();
assert(not hover('mp'), 'With the percent showing, the MP bar has no tooltip.');

-- The display grows to hold every line: with the build on, the last attachment line is drawn under all the rest.
config.show_build = true;
fx.step();
text = fx.draw();
assert(shown().line_count == 7 and text:find('|Build|', 1, true) and text:find('|Stormwaker / Stormwaker|', 1, true)
    and text:find('|Magic skill|', 1, true) and text:find('|Shock Absorber|', 1, true), 'Every build line is drawn: ' .. text);
-- A fixed height cuts what's past it.
config.height = 60;
fx.step();
assert(not fx.draw():find('|Shock Absorber|', 1, true), 'A display too short for them cuts the last lines.');
config.height = 0;
config.show_build = false;

-- The Sic mark: one more box on the TP bar for a BST with a jug pet out, with its own tooltip.
game.job = 9;
game.pet.name = 'SheepFamiliar';
sync(index, 'SheepFamiliar', 78, 40, 300);
fx.step();
local _, _, before = frame();
config.sic_mark = true;
fx.step();
local _, _, after = frame();
assert(after == before + 1, 'The mark is one box on the TP bar: ' .. after .. ' against ' .. before);
-- On a display so narrow that the mark would cross the TP number, it is a notch above and one below instead.
config.width = 160;
player.GetPetTP = function() return 3000; end;
fx.step();
local _, _, notched = frame();
assert(notched == before + 2, 'Over the number the mark is two notches: ' .. notched .. ' against ' .. before);
config.width = 280;
player.GetPetTP = function() return 300; end;
fx.step();
spot = assert(hover('sic'), 'The TP bar has the mark\'s tooltip.');
assert(display.details(spot, MOCK.now):find('1000 TP', 1, true), 'It says what the mark is.');
config.sic_mark = false;
fx.step();
assert(not hover('sic'), 'With the tick off, the TP bar has no tooltip.');
game.pet.name = 'Ironsides';

-- A value too wide for its row starts at the row's left and is cut at its right, where the name would have been.
-- With room, the name is on the left and the value ends at the right.
game.units[0x123] = { id = 0x1000123, index = 0x123, name = 'A Very Long Named Monster Of The Deep', flags = 0x10, hpp = 63 };
sync(index, 'Ironsides', 78, 40, 300, 0x1000123);
config.show_target, config.width = true, 160;
fx.step();
text = frame();
local wide = 'A Very Long Named Monster Of The Deep 63%';
assert(text:find('|' .. wide .. '|', 1, true) and spots[wide] >= config.x, 'A value wider than the display starts inside it: ' .. tostring(spots[wide])
    .. ' against ' .. config.x);
assert(not text:find('|Fighting|', 1, true), 'And its name, with no room left, isn\'t drawn.');
-- With room for only a letter or two of the name, the name is left out, not cut to a stub.
config.width = 372;
fx.step();
assert(not frame():find('|Fighting|', 1, true), 'A name with room for three letters isn\'t drawn.');
config.width = 600;
fx.step();
text = frame();
assert(text:find('|Fighting|', 1, true) and spots[wide] > spots['Fighting'] + 64, 'With room the name is on the left and the value after it.');
config.show_target, config.width = false, 280;
sync(index, 'Ironsides', 78, 40, 300, 0);
game.units[0x123] = nil;

-- Every line the ticks add is shown, however many: 12 attachments, 4 cooldowns, 12 lines of build, the distance and
-- the time out.
game.job = 18;
page({ name = 'Ironsides', head = 4, frame = 0x23, attachments = { 1, 6, 8, 71, 72, 97, 194, 197, 226, 230, 232, 234 }, mp = 168, max_mp = 420 });
config.show_attachments, config.show_cooldowns, config.show_build, config.show_distance, config.show_time_out = true, true, true, true, true;
fx.step();
assert(shown().line_count == 30, 'A display with every line holds them all: ' .. shown().line_count);
assert(fx.draw():find('|Regulator|', 1, true), 'Down to the last attachment.');

-- A page that stops part way through the stats gives the name and HP alone, with nothing of the build read from
-- it, so the automaton's lines go.
local short = MOCK.bytes(0x90);
MOCK.put(short, 4, 1, 18);
MOCK.put(short, 8, 1, 4); MOCK.put(short, 9, 1, 0x23); MOCK.put(short, 0x0A, 1, 1);
for i = 1, #'Ironsides' do short[0x57 + i] = ('Ironsides'):byte(i); end
MOCK.put(short, 0x68, 2, 780); MOCK.put(short, 0x6A, 2, 1000); MOCK.put(short, 0x6C, 2, 168); MOCK.put(short, 0x6E, 2, 420);
MOCK.fire('packet_in', MOCK.packet(0x044, short));
fx.step();
local held = fx.app.state.snapshot.pet.automaton;
assert(held and held.hp == 780 and held.max_hp == 1000, 'A short page still gives the HP.');
assert(held.attachments == nil and held.head == nil and held.frame == nil and held.mp == nil, 'It holds no build, not even the part that fits.');
assert(shown().line_count == 2, 'Only the distance and the time out are left: ' .. shown().line_count);
return 'How the pet display draws its optional lines';
