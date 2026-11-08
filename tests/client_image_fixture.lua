-- Decoded client images for the native tests, mapped at a chosen base. The files are only read.
-- old is FFXiMain.dll f2245d1c (every test was verified on it), new is 04288488 (2026-10-18).
local fixture = {};
local root = (ADDON_DIR or 'vantage') .. '/..';
fixture.paths = {
    old = root .. '/tests/fixtures/clients/client-image-f2245d1c.bin',
    new = root .. '/tests/fixtures/clients/client-image-04288488.bin',
};
fixture.sha256 = {
    old = 'f2245d1c9d06e02c36624942483913f5120c0d40777fc1bb8703c6f4bda823e4',
    new = '042884888eea4fadac183e520f2ae9f8c4fa267860e685048e1880efd358e872',
};
local loaded = {};
-- Fixture checks raise errors, so the suite's assertion count stays the tests' own.
local function need(value, message) if not value then error(message, 2); end; return value; end;

local function u16(data, at) local a, b = data:byte(at, at + 1); return a + b * 256; end;
local function u32(data, at) return u16(data, at) + u16(data, at + 2) * 65536; end;
local function le32(value)
    value = value % 4294967296;
    local out = {};
    for index = 1, 4 do out[index] = string.char(value % 256); value = math.floor(value / 256); end;
    return table.concat(out);
end;
fixture.le32 = le32;

-- name -> {rva, virtual size}, as tools/client_check.py reads them.
local function sections(data)
    local pe = u32(data, 0x3D);
    local count, optional = u16(data, pe + 7), u16(data, pe + 21);
    local out = {};
    for index = 0, count - 1 do
        local at = pe + 24 + optional + index * 40;
        local name = data:sub(at + 1, at + 8):gsub('%z.*$', '');
        out[name] = out[name] or { rva = u32(data, at + 13), size = u32(data, at + 9) };
    end;
    return out;
end;
fixture.sections = sections;

-- The whole .reloc section (its first blocks cover .text), applied as the loader and the client's
-- own unpacker do, and the header's image base set as the loader leaves it.
local function relocate(data, base)
    if base == 0x10000000 then return data; end;
    local reloc = sections(data)['.reloc'];
    local delta, entries = base - 0x10000000, {};
    local position, finish = reloc.rva, reloc.rva + reloc.size;
    while position + 8 <= finish do
        local page, block = u32(data, position + 1), u32(data, position + 5);
        if block < 8 then break; end;
        for index = 0, (block - 8) / 2 - 1 do
            local entry = u16(data, position + 9 + index * 2);
            local kind = math.floor(entry / 4096);
            if kind == 3 then entries[#entries + 1] = page + entry % 4096;
            elseif kind ~= 0 then error('unsupported relocation type ' .. kind); end;
        end;
        position = position + block;
    end;
    table.sort(entries);
    local header = u32(data, 0x3D) + 24 + 28;
    local pieces, last = { data:sub(1, header), le32(base) }, header + 4;
    for _, at in ipairs(entries) do
        need(at >= last, 'overlapping relocations');
        pieces[#pieces + 1] = data:sub(last + 1, at);
        pieces[#pieces + 1] = le32(u32(data, at + 1) + delta);
        last = at + 4;
    end;
    pieces[#pieces + 1] = data:sub(last + 1);
    return table.concat(pieces), #entries;
end;

local parsed = {};
local function parse(pattern)
    if parsed[pattern] then return parsed[pattern]; end;
    need(#pattern % 2 == 0 and not pattern:find('[^0-9A-F?]'), 'bad pattern ' .. pattern);
    local spec, start = { length = #pattern / 2, runs = {} }, nil;
    for index = 0, spec.length do
        local wild = index == spec.length or pattern:sub(index * 2 + 1, index * 2 + 2) == '??';
        if not wild and not start then start = index; end;
        if wild and start then
            local bytes = pattern:sub(start * 2 + 1, index * 2):gsub('..', function(pair) return string.char(tonumber(pair, 16)); end);
            spec.runs[#spec.runs + 1] = { offset = start, bytes = bytes };
            if not spec.anchor or #bytes > #spec.anchor.bytes then spec.anchor = spec.runs[#spec.runs]; end;
            start = nil;
        end;
    end;
    need(spec.anchor, 'a pattern needs a fixed byte');
    parsed[pattern] = spec;
    return spec;
end;

local Image = {};
Image.__index = Image;

function fixture.load(name, base)
    base = base or 0x10000000;
    local key = name .. '@' .. base;
    if not loaded[key] then
        if not loaded[name] then
            local file = need(io.open(need(fixture.paths[name], 'unknown client ' .. tostring(name)), 'rb'), 'no client image');
            loaded[name] = file:read('*a');
            file:close();
            need(#loaded[name] == 12665856, 'unexpected client image size');
        end;
        loaded[key] = relocate(loaded[name], base);
    end;
    return setmetatable({ name = name, base = base, data = loaded[key], reads = 0, finds = 0 }, Image);
end;

-- Another mapping of the same bytes; writes to one never show in the other.
function Image:copy() return setmetatable({ name = self.name, base = self.base, data = self.data, reads = 0, finds = 0 }, Image); end;

function Image:section(name)
    local found = sections(self.data)[name];
    return self.base + found.rva, self.base + found.rva + found.size;
end;

function Image:contains(at, size)
    return type(at) == 'number' and at >= self.base and at + size <= self.base + #self.data;
end;

function Image:bytes(at, size)
    if not self:contains(at, size) then return nil; end;
    self.reads = self.reads + 1;
    return self.data:sub(at - self.base + 1, at - self.base + size);
end;

function Image:read32(at)
    local bytes = self:bytes(at, 4);
    return bytes and u32(bytes, 1);
end;

function Image:write(at, bytes)
    need(self:contains(at, #bytes), 'write outside the image');
    local offset = at - self.base;
    self.data = self.data:sub(1, offset) .. bytes .. self.data:sub(offset + #bytes + 1);
end;

-- The usage-th match (from 0) wholly inside [start, start + size), or 0, as Ashita's FindPattern scans.
function Image:find(start, size, pattern, usage)
    self.finds = self.finds + 1;
    local spec = parse(pattern);
    local low = math.max(0, start - self.base);
    local high = math.min(#self.data, start - self.base + size);
    local position, count = low + spec.anchor.offset + 1, 0;
    while true do
        local hit = self.data:find(spec.anchor.bytes, position, true);
        if not hit then return 0; end;
        local at = hit - 1 - spec.anchor.offset;
        if at + spec.length > high then return 0; end;
        position = hit + 1;
        if at >= low then
            local matched = true;
            for _, run in ipairs(spec.runs) do
                if self.data:sub(at + run.offset + 1, at + run.offset + #run.bytes) ~= run.bytes then matched = false; break; end;
            end;
            if matched then
                if count == (usage or 0) then return self.base + at; end;
                count = count + 1;
            end;
        end;
    end;
end;

-- The memory core.native_client reads: the module range, section searches and byte reads.
function Image:memory()
    return {
        module = function() return self.base, #self.data; end,
        find = function(start, size, pattern, usage) return self:find(start, size, pattern, usage); end,
        read = function(at, size) return self:bytes(at, size); end,
    };
end;

-- ashita.memory over this image, for code that searches by module name or by address.
function Image:install()
    local image = self;
    local function scan(where, size, pattern, offset, usage)
        local start, length = image.base, #image.data;
        if type(where) == 'number' and where ~= 0 then start, length = where, size; end;
        if type(where) ~= 'number' and size and size ~= 0 then length = size; end;
        local found = image:find(start, length, pattern, usage);
        return found ~= 0 and found + (offset or 0) or 0;
    end;
    local function reader(size)
        return function(at)
            local bytes = image:bytes(at, size);
            if not bytes then return 0; end;
            local value = 0;
            for index = size, 1, -1 do value = value * 256 + bytes:byte(index); end;
            return value;
        end;
    end;
    ashita.memory.find = scan;
    ashita.memory.get_base = function() return image.base; end;
    ashita.memory.get_size = function() return #image.data; end;
    ashita.memory.read_uint8, ashita.memory.read_uint16, ashita.memory.read_uint32 = reader(1), reader(2), reader(4);
    return self;
end;

-- A 32-bit Windows ffi over this image: string reads and VirtualQuery, nothing else.
function Image:ffi()
    local image = self;
    local fake = { os = 'Windows', declared = {}, queries = 0, C = {} };
    fake.abi = function(name) return name == '32bit'; end;
    fake.typeof = function(name) if not fake.declared[name] then error('not declared'); end; return true; end;
    fake.cdef = function(source)
        for name in source:gmatch('}%s*([%w_]+)%s*;') do fake.declared[name] = true; end;
    end;
    fake.new = function() return { [0] = {} }; end;
    fake.sizeof = function() return 28; end;
    fake.cast = function(_, value) return value; end;
    fake.string = function(at, size) return need(image:bytes(at, size), 'read outside the image'); end;
    fake.C.VirtualQuery = function(at, region)
        fake.queries = fake.queries + 1;
        if not image:contains(at, 1) then return 0; end;
        local info = region[0];
        info.BaseAddress, info.RegionSize = image.base, #image.data;
        info.State, info.Protect = 0x1000, image.protect or 0x20;
        return 28;
    end;
    return fake;
end;

fixture.relocate = relocate;
return fixture;
