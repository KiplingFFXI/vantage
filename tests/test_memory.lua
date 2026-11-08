-- core.memory: the one page check the client readers share.
local memory = require('core.memory');

for _, value in ipairs({ 65536, 0x7FFF0000, 0xFFEFFFFF }) do assert(memory.address(value), 'address ' .. value); end
for _, value in ipairs({ 65535, 0xFFF00000, 70000.5, -1, math.huge, 0 / 0, '70000', nil }) do
    assert(not memory.address(value), 'not an address: ' .. tostring(value));
end

-- A Windows ffi over a list of regions: {base, size, state, protect}.
local regions, queries;
local function fake_ffi()
    local fake = { os = 'Windows', declared = {}, C = {} };
    fake.abi = function(name) return name == '32bit'; end;
    fake.typeof = function(name) if not fake.declared[name] then error('not declared'); end; return true; end;
    fake.cdef = function(source) for name in source:gmatch('}%s*([%w_]+)%s*;') do fake.declared[name] = true; end; end;
    fake.new = function() return { [0] = {} }; end;
    fake.sizeof = function() return 28; end;
    fake.cast = function(_, value) return value; end;
    fake.C.VirtualQuery = function(at, region)
        queries = queries + 1;
        for _, entry in ipairs(regions) do
            if at >= entry[1] and at < entry[1] + entry[2] then
                local info = region[0];
                info.BaseAddress, info.RegionSize, info.State, info.Protect = entry[1], entry[2], entry[3], entry[4];
                return 28;
            end
        end
        return 0;
    end;
    return fake;
end
local real_ffi = package.loaded.ffi;
package.loaded.ffi = fake_ffi();
regions, queries = {
    { 0x100000, 0x1000, 0x1000, 0x02 },     -- read only
    { 0x101000, 0x1000, 0x1000, 0x04 },     -- read/write
    { 0x102000, 0x1000, 0x1000, 0x20 },     -- execute/read
    { 0x103000, 0x1000, 0x1000, 0x104 },    -- read/write guard page
    { 0x104000, 0x1000, 0x2000, 0x04 },     -- reserved
    { 0x105000, 0x1000, 0x1000, 0x01 },     -- no access
    { 0x106000, 0x1000, 0x1000, 0x40 },     -- execute/read/write
    { 0x107000, 0x1000, 0x1000, 0x10 },     -- execute only
    { 0xFFEFF000, 0x1000, 0x1000, 0x04 },
}, 0;
local pages = memory.pages();
assert(package.loaded.ffi.declared.vg_client_region and pages.valid and pages.readable);
local rules = {
    { 0x100000, 4, false, true }, { 0x100000, 4, true, false }, { 0x101000, 4, true, true }, { 0x102000, 4, false, true },
    { 0x102000, 4, true, false }, { 0x103000, 4, false, false }, { 0x104000, 4, false, false }, { 0x105000, 4, false, false },
    { 0x106000, 4, true, true }, { 0x107000, 4, false, false }, { 0x108000, 4, false, false },
    -- A range must end inside the region it starts in, and below 0xFFF00000.
    { 0x100FFC, 4, false, true }, { 0x100FFD, 4, false, false }, { 0x101000, 0x1000, true, true }, { 0x101000, 0x1001, true, false },
    { 0xFFEFF000, 4, false, true }, { 0xFFEFFFFC, 4, false, false }, { 0x0FFFF, 4, false, false },
};
for _, rule in ipairs(rules) do
    assert(pages.valid(rule[1], rule[2], rule[3]) == rule[4],
        string.format('valid(0x%X, %d, %s) is %s', rule[1], rule[2], tostring(rule[3]), tostring(rule[4])));
end
-- readable walks on through the regions a range spans and stops at the first it can't read.
assert(pages.readable(0x100FF0, 0x1020) and pages.readable(0x100000, 0x3000));
assert(not pages.readable(0x102FF0, 0x20) and not pages.readable(0x101000, 0x6000));
queries = 0; assert(pages.readable(0x100000, 0x1000) and queries == 1);
queries = 0; assert(pages.readable(0x100000, 0x3000) and queries == 3);
queries = 0; assert(pages.valid(0x101000, 4, true) and pages.valid(0x101000, 4, true) and queries == 2,
    'Every check queries the pages again.');
package.loaded.ffi = real_ffi;
