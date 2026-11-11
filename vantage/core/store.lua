local json = require('core.json');
local ffi = require('ffi');
local store = {};
local serial = 0;
local MAX_BYTES = 2097152;
local journal;

if (ffi.os == 'Windows') then
    pcall(ffi.cdef, [[
        unsigned long __stdcall GetCurrentProcessId(void);
        int __stdcall MoveFileExA(const char*, const char*, unsigned long);
    ]]);
    -- Each on its own, so a declaration another file made first doesn't stop the rest.
    pcall(ffi.cdef, 'void* __stdcall CreateFileA(const char*, unsigned long, unsigned long, void*, unsigned long, unsigned long, void*);');
    pcall(ffi.cdef, 'int __stdcall FlushFileBuffers(void*);');
    pcall(ffi.cdef, 'int __stdcall CloseHandle(void*);');
end

function store.copy(value, seen)
    if (type(value) ~= 'table') then return value; end
    seen = seen or {};
    if (seen[value]) then return seen[value]; end
    local result = {};
    seen[value] = result;
    for key, child in pairs(value) do result[store.copy(key, seen)] = store.copy(child, seen); end
    return result;
end

-- Puts in out a copy of each key of value that out doesn't have, so a tidy that builds its table anew keeps what a newer
-- Vantage saved there, as the rest of the settings keep it. retired, when given, holds keys an older Vantage saved there
-- that nothing reads now, and those are left out. Returns out.
function store.keep_unknown(out, value, retired)
    if type(value) ~= 'table' then return out; end
    for key, child in pairs(value) do
        if out[key] == nil and not (retired and retired[key]) then out[key] = store.copy(child); end
    end
    return out;
end

local function json_value(value, visiting)
    if type(value) ~= 'table' then return value; end
    visiting = visiting or {};
    if visiting[value] then error('Settings contain a circular table.'); end
    visiting[value] = true;
    local count, maximum, array = 0, 0, true;
    for key in pairs(value) do
        count = count + 1;
        if type(key) ~= 'number' or key < 1 or key ~= math.floor(key) then array = false;
        else maximum = math.max(maximum, key); end
    end
    array = array and maximum == count;
    local result = {};
    for key, child in pairs(value) do
        local target = array and key or tostring(key);
        if result[target] ~= nil then error('Settings contain conflicting map keys.'); end
        result[target] = json_value(child, visiting);
    end
    visiting[value] = nil;
    return result;
end

function store.encode(value)
    return json.encode(json_value(value));
end

local function same_value(a, b)
    if (type(a) ~= type(b)) then return false; end
    if (type(a) ~= 'table') then return a == b; end
    for key, value in pairs(a) do if (not same_value(value, b[key])) then return false; end end
    for key in pairs(b) do if (a[key] == nil) then return false; end end
    return true;
end

function store.equal(a, b)
    local ok_a, normalized_a = pcall(json_value, a);
    local ok_b, normalized_b = pcall(json_value, b);
    return ok_a and ok_b and same_value(normalized_a, normalized_b);
end

function store.ensure_folder(path)
    local ok, result = pcall(ashita.fs.create_dir, path);
    if (not ok or result == false) then return false, 'The Vantage settings folder could not be created.'; end
    return true;
end

-- How a saved file is named in a message: its path from the config folder on, else its file name.
function store.name(path)
    path = tostring(path or ''):gsub('[\\/]+', '/');
    return path:match('config/addons/.*$') or path:match('[^/]+$') or 'The saved file';
end

-- cache, when given, keeps the last text read and its decoded value, so reading the same text again skips
-- decoding it. The value is then shared, so only a caller that never changes it may pass one.
function store.read(path, cache)
    local file, _, code = io.open(path, 'rb');
    if (file == nil) then
        local checked, exists = pcall(ashita.fs.exists, path);
        if (checked and not exists and (code == nil or code == 2)) then return {}; end
        return nil, 'The saved file could not be opened. It was kept unchanged.';
    end
    local read_ok, text, read_error = pcall(file.read, file, MAX_BYTES + 1);
    local close_ok, closed = pcall(file.close, file);
    -- An empty file reads as nothing, with no error, and holds no settings, as a missing one.
    if (read_ok and text == nil and read_error == nil and close_ok and closed) then return {}; end
    if (not read_ok or type(text) ~= 'string' or not close_ok or not closed or #text > MAX_BYTES) then
        return nil, 'The saved file could not be read. It was kept unchanged.';
    end
    -- An editor that saves UTF-8 with a byte order mark puts one in front; the settings are the text after it.
    if (text:sub(1, 3) == '\239\187\191') then text = text:sub(4); end
    -- Blank space alone holds no settings either, as an empty file. An editor can save a file emptied by hand that way.
    if (text:find('^[ \t\r\n]*$')) then return {}; end
    if (cache and cache.text == text) then return cache.value; end
    local ok, value = pcall(json.decode, text);
    if (not ok or type(value) ~= 'table') then
        return nil, store.name(path) .. ' contains invalid settings. It must be JSON saved as UTF-8. It was kept unchanged.';
    end
    if (cache) then cache.text, cache.value = text, value; end
    return value;
end

-- Asks Windows to put what was written to the file at path on the disk. The move that puts a saved file in place
-- doesn't: MOVEFILE_WRITE_THROUGH only waits for a move made as a copy, and a power cut after the move could leave
-- the saved name on an empty file. It is a best try, so a save goes on when it fails. Returns whether it flushed.
local function flush(path)
    if (ffi.os ~= 'Windows') then return false; end
    local ok, flushed = pcall(function()
        local open, flush_buffers, close = ffi.C.CreateFileA, ffi.C.FlushFileBuffers, ffi.C.CloseHandle;
        -- GENERIC_WRITE (0x40000000), shared to read and write (3), OPEN_EXISTING (3), FILE_ATTRIBUTE_NORMAL (0x80).
        local handle = open(path, 0x40000000, 3, nil, 3, 0x80, nil);
        if (handle == nil or tonumber(ffi.cast('intptr_t', handle)) == -1) then return false; end
        local done, result = pcall(flush_buffers, handle);
        close(handle);
        return done and result ~= 0;
    end);
    return ok and flushed == true;
end
if (VANTAGE_TEST_MODE) then store.flush = flush; end

-- A third value says why it failed, where a caller tells the cases apart: 'changed' when the file changed since it was
-- read (expected) or while this was written, and 'full' when the settings would pass the size a saved file may have.
function store.write(path, value, expected)
    if (type(value) ~= 'table') then return false, 'Settings must be a table.'; end
    -- Both reads of the file share one cache, so the second decodes it again only when its text changed meanwhile.
    local file_cache = {};
    local previous, problem = store.read(path, file_cache);
    if (previous == nil) then return false, problem; end
    if (expected ~= nil and not store.equal(previous, expected)) then
        return false, 'The saved file changed while you were editing it. Review it again before saving.', 'changed';
    end
    local ok, encoded = pcall(store.encode, value);
    if (not ok or type(encoded) ~= 'string') then return false, 'These changes could not be saved.'; end
    if (#encoded > MAX_BYTES) then return false, 'These changes could not be saved.', 'full'; end
    local parent = path:match('^(.*)[\\/][^\\/]+$');
    if (parent) then
        local made, err = store.ensure_folder(parent);
        if (not made) then return false, err; end
    end
    local process = 0;
    if (ffi.os == 'Windows') then
        ok, process = pcall(ffi.C.GetCurrentProcessId);
        process = ok and tonumber(process) or 0;
    end
    local temp;
    repeat
        serial = serial + 1;
        temp = ('%s.%d.%d.tmp'):format(path, process, serial);
    until not ashita.fs.exists(temp)
    local file = io.open(temp, 'wb');
    if (file == nil) then return false, 'The file could not be saved in the Vantage settings folder.'; end
    local wrote, result = pcall(file.write, file, encoded);
    local closed, closing = pcall(file.close, file);
    if (not wrote or not result or not closed or not closing) then
        os.remove(temp);
        return false, 'The changes could not be saved. Your previous file was kept.';
    end
    flush(temp);
    local latest, latest_problem = store.read(path, file_cache);
    if (latest == nil or latest ~= previous and not store.equal(previous, latest)) then
        os.remove(temp);
        return false, latest_problem or 'The saved file changed while these changes were being saved. The newer file was kept.',
            latest ~= nil and 'changed' or nil;
    end
    local kept = journal and journal.paths[path] and (journal.files[path] or { value = previous, existed = ashita.fs.exists(path) == true });
    local moved;
    if (ffi.os == 'Windows') then
        -- 9 is MOVEFILE_REPLACE_EXISTING (1) with MOVEFILE_WRITE_THROUGH (8), so the move replaces the file. Write
        -- through only waits for a move made as a copy, so it's the flush above that asks for the new text to be on the
        -- disk before the move.
        ok, result = pcall(ffi.C.MoveFileExA, temp, path, 9);
        moved = ok and result ~= 0;
    else
        ok, result = pcall(os.rename, temp, path);
        moved = ok and result ~= nil;
    end
    if (not moved) then os.remove(temp); return false, 'The saved file could not be replaced. Your previous file was kept.'; end
    if (kept) then kept.written = encoded; journal.files[path] = kept; end
    return true;
end

-- Writes text as a new file at path, through a temporary file moved into place. It never replaces a file: when one
-- is there it writes nothing, and a third value of 'exists' says so.
function store.create(path, text)
    if (type(text) ~= 'string' or #text > MAX_BYTES) then return false, 'That text could not be saved.'; end
    if (ashita.fs.exists(path)) then return false, store.name(path) .. ' already exists.', 'exists'; end
    local parent = path:match('^(.*)[\\/][^\\/]+$');
    if (parent) then
        local made, err = store.ensure_folder(parent);
        if (not made) then return false, err; end
    end
    local process, ok, result = 0, nil, nil;
    if (ffi.os == 'Windows') then
        ok, process = pcall(ffi.C.GetCurrentProcessId);
        process = ok and tonumber(process) or 0;
    end
    local temp;
    repeat
        serial = serial + 1;
        temp = ('%s.%d.%d.tmp'):format(path, process, serial);
    until not ashita.fs.exists(temp)
    local file = io.open(temp, 'wb');
    if (file == nil) then return false, 'The file could not be saved in the Vantage settings folder.'; end
    local wrote, written = pcall(file.write, file, text);
    local closed, closing = pcall(file.close, file);
    if (not wrote or not written or not closed or not closing) then
        os.remove(temp);
        return false, 'The file could not be saved.';
    end
    flush(temp);
    -- Without MOVEFILE_REPLACE_EXISTING (1) the move fails when a file is there, so one made meanwhile stays.
    local moved;
    if (ffi.os == 'Windows') then
        ok, result = pcall(ffi.C.MoveFileExA, temp, path, 8);
        moved = ok and result ~= 0;
    elseif (not ashita.fs.exists(path)) then
        ok, result = pcall(os.rename, temp, path);
        moved = ok and result ~= nil;
    end
    if (not moved) then
        os.remove(temp);
        if (ashita.fs.exists(path)) then return false, store.name(path) .. ' already exists.', 'exists'; end
        return false, 'The file could not be saved.';
    end
    return true;
end

-- While a journal is open, a write to one of its paths keeps what the file held before the first
-- write and what was written last, so store.undo can put the file back.
function store.journal(value)
    journal = value;
end

-- Puts back each file a journal kept, unless something else wrote it since. Returns the paths it
-- couldn't put back, each as 'changed' (it reads as something else now) or 'failed' (it couldn't be
-- read, written or removed).
function store.undo(files)
    local missed;
    for path, kept in pairs(files) do
        local decoded, written = pcall(json.decode, kept.written);
        local current = store.read(path);
        local why = 'failed';
        if (decoded and current ~= nil and store.equal(current, written)) then
            local restored;
            if (kept.existed) then restored = store.write(path, kept.value, written);
            else restored = os.remove(path); end
            why = not restored and 'failed' or nil;
        elseif (decoded and current ~= nil) then why = 'changed'; end
        if (why) then missed = missed or {}; missed[path] = why; end
        files[path] = nil;
    end
    return missed;
end

return store;
