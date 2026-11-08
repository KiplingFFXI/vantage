-- The one finder for the client code Vantage looks for by byte patterns: core/clock.lua, client.lua, chat.lua,
-- native_party_ui.lua and name_anchor.lua each pass their own rule.
-- Each search of the client scans up to its whole 12 MB, so what is found is kept for the life of the game process
-- in a process environment variable (kernel32, VANTAGE_PATTERNS), which an /addon reload doesn't clear. A kept
-- address is used again only while it is inside the client module, its pages can be read and the pattern's fixed
-- bytes are still there; otherwise that one pattern is searched again. Nothing is kept on disk, and nothing is
-- kept when the game closes. Searches are timed as patterns.first and patterns.unique, and each owner's whole
-- find as patterns.<owner>.
local patterns = {};
local memory = require('core.memory');
local bit = require('bit');

local NAME, VERSION = 'VANTAGE_PATTERNS', '1';
-- The longest value the environment is read into; a longer one is ignored.
local LIMIT = 32768;

local performance;
do
    local ok, value = pcall(require, 'core.performance');
    if ok and type(value) == 'table' and type(value.now) == 'function' and type(value.record) == 'function' then performance = value; end
end
local stages = {};
local function stage(owner)
    local name = stages[owner];
    if not name then name = 'patterns.' .. owner; stages[owner] = name; end
    return name;
end

-- The store: read() the kept text or nil, write(text), process() this process's id. false with none: the tests
-- set their own, so no fixture leaves anything in the environment of the process the suite runs in.
local store;
-- What the store holds for this process and client module, by key; nil until the first find reads it. header is
-- nil while nothing can be kept, and base and size are the module's range the kept addresses must lie in.
local kept, header, base, size;
local pages;

-- The process environment, through kernel32 only.
local function environment(ffi, name)
    if type(ffi) ~= 'table' or ffi.os ~= 'Windows' then return nil; end
    pcall(ffi.cdef, 'unsigned long __stdcall GetEnvironmentVariableA(const char*, char*, unsigned long);');
    pcall(ffi.cdef, 'int __stdcall SetEnvironmentVariableA(const char*, const char*);');
    pcall(ffi.cdef, 'unsigned long __stdcall GetCurrentProcessId(void);');
    local get, set, process = ffi.C.GetEnvironmentVariableA, ffi.C.SetEnvironmentVariableA, ffi.C.GetCurrentProcessId;
    return {
        read = function()
            local buffer = ffi.new('char[?]', LIMIT);
            local length = tonumber(get(name, buffer, LIMIT));
            if not length or length <= 0 or length >= LIMIT then return nil; end
            return ffi.string(buffer, length);
        end,
        write = function(text) return set(name, text) ~= 0; end,
        process = function() return tonumber(process()); end,
    };
end

local function current_store()
    if store == nil then
        store = false;
        if not VANTAGE_TEST_MODE then
            local ok, made = pcall(function() return environment(require('ffi'), NAME); end);
            if ok and made then store = made; end
        end
    end
    return store or nil;
end

-- The same store over another variable, for another value kept for the game process: core/warmup.lua keeps a
-- reload's times in one. nil without kernel32, and in the tests.
function patterns.environment(name)
    if VANTAGE_TEST_MODE then return nil; end
    local ok, made = pcall(function() return environment(require('ffi'), name); end);
    if ok then return made; end
end

local function module_range()
    if not ashita or not ashita.memory or type(ashita.memory.get_base) ~= 'function' then return nil, nil; end
    local ok, b, n = pcall(function() return ashita.memory.get_base('FFXiMain.dll'), ashita.memory.get_size('FFXiMain.dll'); end);
    if ok then return b, n; end
end

-- The kept entries, from text whose first fields are header: key=address, both checked, the rest ignored.
local function parse(text, expected)
    local list = {};
    if type(text) ~= 'string' or text:sub(1, #expected) ~= expected then return list; end
    local after = text:sub(#expected + 1, #expected + 1);
    if after ~= '' and after ~= ';' then return list; end
    for key, value in text:sub(#expected + 1):gmatch(';([^;=]*)=([^;]*)') do
        if key:match('^[%w_]+%.[%w_]+%.%x%x%x%x%x%x%x%x$') and value:match('^%x%x?%x?%x?%x?%x?%x?%x?$') then
            list[key] = tonumber(value, 16);
        end
    end
    return list;
end

local function held()
    if kept then return kept; end
    kept = {};
    local source = current_store();
    if not source then return kept; end
    local b, n = module_range();
    local ok, process = pcall(source.process);
    if not memory.address(b) or type(n) ~= 'number' or n <= 0 or n ~= math.floor(n) or not ok or type(process) ~= 'number' then
        return kept;
    end
    base, size, header = b, n, ('%s;%x;%x;%x'):format(VERSION, process, b, n);
    local read, text = pcall(source.read);
    if read then kept = parse(text, header); end
    return kept;
end

local function save()
    local source = current_store();
    if not source or not header then return; end
    local keys = {};
    for key in pairs(kept) do keys[#keys + 1] = key; end
    table.sort(keys);
    local parts = { header };
    for index, key in ipairs(keys) do parts[index + 1] = ('%s=%x'):format(key, kept[key]); end
    pcall(source.write, table.concat(parts, ';'));
end

-- FNV-1a over the text, 32 bits.
local function hash(text)
    local h = 2166136261;
    for index = 1, #text do
        h = bit.bxor(h, text:byte(index)) % 4294967296;
        h = (h * 403 + h % 256 * 16777216) % 4294967296;
    end
    return h;
end

-- The pattern's fixed bytes as offset, value pairs, with its length; nil for a pattern that can't be checked.
local parsed = {};
local function fixed(pattern)
    local spec = parsed[pattern];
    if spec ~= nil then return spec or nil; end
    spec = false;
    if type(pattern) == 'string' and #pattern > 0 and #pattern % 2 == 0 then
        spec = { length = #pattern / 2 };
        for index = 0, spec.length - 1 do
            local pair = pattern:sub(index * 2 + 1, index * 2 + 2);
            if pair ~= '??' then
                if not pair:match('^%x%x$') then spec = false; break; end
                local count = #spec;
                spec[count + 1], spec[count + 2] = index, tonumber(pair, 16);
            end
        end
        if spec and #spec == 0 then spec = false; end
    end
    parsed[pattern] = spec;
    return spec or nil;
end

local function readable(at, length)
    if pages == nil then
        local ok, value = pcall(memory.pages);
        pages = ok and type(value) == 'table' and value.readable or false;
    end
    return pages ~= false and pages(at, length) == true;
end

-- Whether the pattern's fixed bytes are at start, inside the module, on pages that can be read.
local function present(start, pattern)
    local spec = fixed(pattern);
    if not spec or not base or not memory.address(start) or start < base or start + spec.length > base + size then return false; end
    if not readable(start, spec.length) then return false; end
    local read = ashita.memory.read_uint8;
    for index = 1, #spec, 2 do
        local ok, value = pcall(read, start + spec[index]);
        if not ok or value ~= spec[index + 1] then return false; end
    end
    return true;
end

-- Why a first match fails the owner's own checks, or nil.
local function misplaced(at, rule)
    if not (rule.accept or memory.address)(at) then return 'is missing'; end
    if rule.within then
        local b, n = module_range();
        if memory.address(b) and type(n) == 'number' and (at < b or at >= b + n) then return 'is outside the client'; end
    end
    if rule.inside and not rule.inside(at) then return 'is outside the client'; end
end

local finders = {};
local function default_find(module)
    module = module or 'FFXiMain.dll';
    local find = finders[module];
    if not find then
        find = function(pattern, offset, usage) return ashita.memory.find(module, 0, pattern, offset, usage); end;
        finders[module] = find;
    end
    return find;
end

local function search(pattern, rule, offset)
    local find = rule.find or default_find(rule.module);
    local started = performance and performance.now();
    local ok, first = pcall(find, pattern, offset, 0);
    if performance then performance.record('patterns.first', started); end
    if not ok then return nil, 'is missing'; end
    local why = misplaced(first, rule);
    if why then return nil, why; end
    if rule.unique then
        started = performance and performance.now();
        local again, second = pcall(find, pattern, offset, 1);
        if performance then performance.record('patterns.unique', started); end
        local twice;
        if rule.lenient then twice = again and second and second ~= 0;
        else twice = not again or second ~= 0 and second ~= nil; end
        if twice then return nil, 'matches more than once'; end
    end
    return first;
end

local NONE = {};

-- The address of pattern in the client by its owner's rule, or nil and why: 'is missing', 'is outside the client' or
-- 'matches more than once'. The rule's fields, each optional:
--   offset   added to the first match by the search, as ashita.memory.find adds it (core/client.lua's map focus)
--   unique   a second search must find no other match
--   lenient  a second search that raises an error counts as finding none (core/native_party_ui.lua)
--   accept   accept(at), whether the first match is a usable value; an address in memory.address's range by default
--   within   the first match must lie inside the client module, when its range can be read
--   inside   inside(at), the owner's own check of where the first match lies
--   find     find(pattern, offset, usage) in place of ashita.memory.find over module ('FFXiMain.dll' by default)
-- owner and name, letters, digits and _, key what is kept with a hash of the pattern and the rule.
function patterns.find(owner, name, pattern, rule)
    rule = rule or NONE;
    local started = performance and performance.now();
    local offset = rule.offset or 0;
    local list = held();
    local key = ('%s.%s.%08x'):format(owner, name, hash(('%s/%d/%s'):format(pattern, offset,
        rule.unique and (rule.lenient and 'lenient' or 'unique') or 'first')));
    local at = list[key];
    if at ~= nil then
        local checked = performance and performance.now();
        local good = misplaced(at, rule) == nil and present(at - offset, pattern);
        if performance then performance.record('patterns.verify', checked); end
        if good then
            if performance then performance.record(stage(owner), started); end
            return at;
        end
        list[key] = nil;
        save();
    end
    local why;
    at, why = search(pattern, rule, offset);
    if at and header and present(at - offset, pattern) then list[key] = at; save(); end
    if performance then performance.record(stage(owner), started); end
    return at, why;
end

-- One warmup step, as an owner's warmup_steps() lists them: { name, run }. run calls work once, timed under name, and
-- does nothing after that, even when work raised an error; done is the owner's table of finished steps, which its
-- own reset empties. An error from work reaches run's caller.
function patterns.step(name, done, work)
    return { name = name, run = function()
        if done[name] then return; end
        done[name] = true;
        local started = performance and performance.now();
        local ok, why = pcall(work);
        if performance then performance.record(name, started); end
        if not ok then error(why, 0); end
    end };
end

if VANTAGE_TEST_MODE then
    -- A store in place of the environment: { read, write, process }. nil keeps nothing, as the tests start.
    function patterns._set_store(value) store, kept, header, base, size = value or false, nil, nil, nil, nil; end
    -- readable(at, size) in place of core/memory.lua's page check.
    function patterns._set_pages(value) pages = value or nil; end
    function patterns._set_performance(value) performance = value; end
    -- The environment store over an ffi, as the game makes it, under a name of the test's own.
    function patterns._environment(ffi, name) return environment(ffi, name or NAME); end
    patterns._NAME = NAME;
end

return patterns;
