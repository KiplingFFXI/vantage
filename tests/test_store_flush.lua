-- Saving (core/store.lua): the temporary file is flushed to the disk before the move puts it in place, as a best try
-- that never stops a save, and a save decodes the saved file once unless it changed meanwhile. A save past the size
-- limit says so with 'full'.
local store, json = require('core.store'), require('core.json');
local ffi = require('ffi');
local folder = MOCK_INSTALL_PATH .. '/config/addons/vantage/';
local path = folder .. 'settings.json';
local function content(name)
    local file = io.open(name, 'rb');
    if not file then return nil; end
    local text = file:read('*a'); file:close(); return text;
end

-- Windows' calls, as the mock's ffi lacks them: each one is noted in events.
local events, handles, opened = {}, 0, {};
local behavior = {};
local move = ffi.C.MoveFileExA;
local function install()
    ffi.cast = function(_, value) return value; end;
    ffi.C.CreateFileA = function(name, access, share, _, disposition)
        events[#events + 1] = { 'open', name, access, share, disposition };
        if behavior.refuse then return -1; end
        handles = handles + 1;
        opened[handles] = name;
        return handles;
    end;
    ffi.C.FlushFileBuffers = function(handle)
        events[#events + 1] = { 'flush', opened[handle], content(opened[handle]) };
        if behavior.on_flush then behavior.on_flush(); end
        if behavior.throw then error('The flush failed.'); end
        return behavior.fail and 0 or 1;
    end;
    ffi.C.CloseHandle = function(handle) events[#events + 1] = { 'close', opened[handle] }; return 1; end;
    ffi.C.MoveFileExA = function(source, target, flags)
        events[#events + 1] = { 'move', source, target, flags };
        return move(source, target, flags);
    end;
end
local function uninstall()
    ffi.cast, ffi.C.CreateFileA, ffi.C.FlushFileBuffers, ffi.C.CloseHandle, ffi.C.MoveFileExA = nil, nil, nil, nil, move;
end
local function kinds()
    local out = {};
    for index, event in ipairs(events) do out[index] = event[1]; end
    return table.concat(out, ' ');
end

do -- Section: a save flushes the temporary file, whole, then moves it into place.
    install();
    assert(store.write(path, { enabled = true }));
    events = {};
    assert(store.write(path, { enabled = false, note = 'second' }));
    assert(kinds() == 'open flush close move', 'The temporary file is opened, flushed and closed before the move: ' .. kinds());
    local open, flushed, moved = events[1], events[2], events[4];
    assert(open[2]:find(path .. '.', 1, true) == 1 and open[2]:match('%.tmp$') and open[2] == moved[2] and moved[3] == path,
        'What is flushed is the temporary file the move puts in place.');
    assert(open[3] == 0x40000000 and open[4] == 3 and open[5] == 3, 'It opens the file there for writing, shared, never making one.');
    assert(flushed[3] == content(path) and json.decode(flushed[3]).note == 'second', 'The whole new text is in it when it is flushed.');
    assert(moved[4] == 9 and store.read(path).note == 'second', 'Then the move replaces the file, and the save is done.');

    -- A new file, as an export to the shared folder makes, the same way.
    events = {};
    local made = folder .. 'shared/Raid.txt';
    assert(store.create(made, 'VG:1:00000000:{}'));
    assert(kinds() == 'open flush close move' and events[1][2] == events[4][2] and events[4][3] == made and events[4][4] == 8,
        'A new file is flushed before the move too: ' .. kinds());
    assert(events[2][3] == 'VG:1:00000000:{}' and content(made) == 'VG:1:00000000:{}', 'with its whole text.');
    uninstall();
end; -- end of section

do -- Section: a flush that can't be done never stops a save.
    install();
    local cases = {
        { 'Windows refuses to open the file', function() behavior.refuse = true; end, 'open move' },
        { 'the flush fails', function() behavior.fail = true; end, 'open flush close move' },
        { 'the flush throws', function() behavior.throw = true; end, 'open flush close move' },
        { 'CreateFileA is missing', function() ffi.C.CreateFileA = nil; end, 'move' },
    };
    for index, case in ipairs(cases) do
        behavior, events = {}, {};
        case[2]();
        assert(store.write(path, { case = index }), 'The save goes on when ' .. case[1] .. '.');
        assert(kinds() == case[3] and store.read(path).case == index, 'and the file is replaced (' .. case[1] .. '): ' .. kinds());
        install();
    end
    behavior, events = {}, {};
    assert(store.flush(path) == true and kinds() == 'open flush close', 'store.flush says when it flushed.');
    behavior.fail = true;
    assert(store.flush(path) == false, 'and when it did not.');
    behavior = {};
    uninstall();
    assert(store.flush(path) == false and store.write(path, { case = 'none' }) and store.read(path).case == 'none',
        'Without the calls at all, as in the tests, nothing is flushed and the save is done.');
end; -- end of section

do -- Section: a save decodes the saved file once, and a change made meanwhile is still found.
    local decode, decodes = json.decode, 0;
    json.decode = function(...) decodes = decodes + 1; return decode(...); end;
    assert(store.write(path, { round = 1 }));
    decodes = 0;
    assert(store.write(path, { round = 2 }) and store.read(path).round == 2);
    assert(decodes == 2, 'A save decodes the file once, and the read after it once: ' .. decodes);
    -- Another character's save lands while this one is written.
    install();
    behavior.on_flush = function()
        local file = assert(io.open(path, 'wb')); file:write('{"round":99}'); file:close();
    end;
    decodes = 0;
    local ok, why, code = store.write(path, { round = 3 });
    assert(not ok and code == 'changed' and why:find('changed', 1, true) and decodes == 2,
        'A file that changed while this was written is decoded again and kept.');
    assert(store.read(path).round == 99, 'The newer file stays.');
    behavior.on_flush = function()
        local file = assert(io.open(path, 'wb')); file:write('{ "round" : 99 }'); file:close();
    end;
    assert(store.write(path, { round = 4 }) and store.read(path).round == 4, 'One that only reads differently is the same file.');
    behavior = {};
    uninstall();
    json.decode = decode;
end; -- end of section

do -- Section: settings past the size limit are too big for the file.
    local before = content(path);
    local ok, why, code = store.write(path, { text = ('x'):rep(2097152) });
    assert(not ok and why == 'These changes could not be saved.' and code == 'full', 'A save past 2 MB says so with full.');
    local cycle = {}; cycle.self = cycle;
    ok, why, code = store.write(path, cycle);
    assert(not ok and why == 'These changes could not be saved.' and code == nil, 'One that can\'t be written at all doesn\'t.');
    assert(content(path) == before, 'Neither touches the saved file.');
end; -- end of section
