-- Laying out a row's parts (ui/fields.lua) makes only what it gives back. fields.build works out each part's value and
-- whether it is known in tables kept from call to call, and fields.positions sorts the parts into its kept left, center
-- and right lists. What a call gives back stays as it was after the next call. Measured as
-- test_party_strip_allocation.lua does, with the collector stopped and the compiler off.
local defaults, fields = require('ui.defaults'), require('ui.fields');
local s = defaults.make();
local style = s.style;
local function time(value) return value and tostring(math.floor(value)) .. 's' or '--' end
local function unit(text) return #text end

local rows = {
    { effect = 33, name = 'Haste', entity_name = 'Member', source_name = 'Caster', status = 'server', deadline = 160, start = 40, total = 180 },
    { effect = 40, name = 'Protect', status = 'unknown' },
};
local p = defaults.copy(s.panels.party);
p.mode, p.show_target, p.show_source, p.show_elapsed, p.show_total, p.show_time = 'bars', true, true, true, true, true;

-- What a call gives back is its own, as a later call leaves it.
local function texts(entries)
    local out = {};
    for index, entry in ipairs(entries) do out[index] = entry.id .. '=' .. entry.text .. '=' .. tostring(entry.known); end
    return table.concat(out, '|');
end
local first = fields.build(rows[1], p, style, 100, time, '60s', 'Haste');
local first_text = texts(first);
assert(first_text:find('target=Member', 1, true) and first_text:find('source=by Caster', 1, true)
    and first_text:find('elapsed=Elapsed 60s', 1, true) and first_text:find('time=60s', 1, true), 'Every part shows: ' .. first_text);
local second = fields.build(rows[2], p, style, 100, time, '', 'Protect');
assert(texts(second) == 'name=Protect=true', 'An unknown row shows only its name: ' .. texts(second));
assert(texts(first) == first_text, 'A later call leaves what an earlier one gave back.');
assert(texts(fields.build(rows[1], p, style, 100, time, '60s', 'Haste')) == first_text, 'The same row lays out the same again.');

local line = { { id = 'name', text = 'long name', size = 10, alignment = 'left' }, { id = 'source', text = 'mid', size = 10, alignment = 'center' },
    { id = 'time', text = '10s', size = 10, alignment = 'right' } };
local placed = fields.positions(line, 40, ' ', unit);
local function places(result)
    local out = {};
    for index, item in ipairs(result) do out[index] = item.entry.text .. '@' .. item.x .. '+' .. item.width; end
    return table.concat(out, '|');
end
local placed_text = places(placed);
assert(placed_text == 'long name@0+9|mid@18.5+3|10s@37+3', 'Each part goes in its lane: ' .. placed_text);
local other = fields.positions({ line[3] }, 20, ' ', unit);
assert(places(other) == '10s@17+3', 'A later line has only its own parts: ' .. places(other));
assert(places(placed) == placed_text, 'A later call leaves what an earlier one gave back.');

-- What one call makes, in KB, over many calls. A panel with no part shown gives back an empty list, and an empty line
-- an empty one, so a call should make one table.
local q = defaults.copy(p);
for _, id in ipairs(defaults.field_ids) do q['show_' .. id] = false; end
local empty_line = {};
local function each(count, call)
    jit.off(); jit.flush();
    for _ = 1, 200 do call(); end
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    local before = collectgarbage('count');
    for _ = 1, count do call(); end
    local made = (collectgarbage('count') - before) / count;
    collectgarbage('restart');
    jit.on();
    return made;
end
local one_table = each(2000, function() return {} end);
local built = each(2000, function() return fields.build(rows[1], q, style, 100, time, '60s', 'Haste') end);
assert(built <= one_table * 1.5, ('fields.build makes %.1f B a call; what it gives back is %.1f B'):format(built * 1024, one_table * 1024));
local positioned = each(2000, function() return fields.positions(empty_line, 40, ' ', unit) end);
assert(positioned <= one_table * 1.5, ('fields.positions makes %.1f B a call; what it gives back is %.1f B'):format(positioned * 1024, one_table * 1024));
return true;
