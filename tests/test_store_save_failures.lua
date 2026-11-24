-- Saving (core/store.lua): store.write and store.create share their temporary file steps, and each way a save can fail
-- still says its own line and leaves the same files: the saved file as it was, and no temporary file behind.
local store = require('core.store');
local folder = MOCK_INSTALL_PATH .. '/config/addons/vantage/';
local function content(name)
    local file = io.open(name, 'rb');
    if not file then return nil; end
    local text = file:read('*a'); file:close(); return text;
end
local function put(name, text)
    local file = assert(io.open(name, 'wb')); file:write(text); file:close();
end

-- Notes each temporary file a save opens, and fails the open or the write when mode says so.
local open, made, mode, on_close = io.open, {}, nil, nil;
io.open = function(target, how)
    if type(target) == 'string' and target:match('%.tmp$') and how == 'wb' then
        made[#made + 1] = target;
        if mode == 'no_open' then return nil; end
        local real = open(target, how);
        return {
            write = function(_, text) if mode == 'no_write' then return nil, 'disk full'; end return real:write(text); end,
            close = function() local closed = real:close(); if on_close then on_close(); end return closed; end,
        };
    end
    return open(target, how);
end
local function left()
    local out = {};
    for _, name in ipairs(made) do if ashita.fs.exists(name) then out[#out + 1] = name; end end
    made = {};
    return table.concat(out, ', ');
end
local function say(...)
    local values = { ... };
    return tostring(values[1]) .. ' | ' .. tostring(values[2]) .. ' | ' .. tostring(values[3]);
end

local cases = {
    { 'the folder can\'t be made', function() MOCK_MKDIR = function() return false; end; end,
        'false | The Vantage settings folder could not be created. | nil',
        'false | The Vantage settings folder could not be created. | nil' },
    { 'the temporary file can\'t be opened', function() mode = 'no_open'; end,
        'false | The file could not be saved in the Vantage settings folder. | nil',
        'false | The file could not be saved in the Vantage settings folder. | nil' },
    { 'the temporary file can\'t be written', function() mode = 'no_write'; end,
        'false | The changes could not be saved. Your previous file was kept. | nil',
        'false | The file could not be saved. | nil' },
    { 'the move fails', function() MOCK.file_replace_error = true; end,
        'false | The saved file could not be replaced. Your previous file was kept. | nil',
        'false | The file could not be saved. | nil' },
};
for index, case in ipairs(cases) do
    local path, new = folder .. 'failed' .. index .. '.json', folder .. 'Made' .. index .. '.txt';
    put(path, '{"round":0}');
    made = {};
    case[2]();
    local wrote = say(store.write(path, { round = index }));
    local created = say(store.create(new, 'VG:1:00000000:{}'));
    MOCK_MKDIR, mode, MOCK.file_replace_error = nil, nil, nil;
    assert(wrote == case[3], 'A save says its own line when ' .. case[1] .. ': ' .. wrote);
    assert(created == case[4], 'and so does a new file: ' .. created);
    assert(content(path) == '{"round":0}' and content(new) == nil, 'The saved file stays and no new one is made when ' .. case[1] .. '.');
    assert(left() == '', 'No temporary file is left when ' .. case[1] .. '.');
end

do -- Section: a file that changes or turns up while the temporary file is written is kept.
    local path = folder .. 'failed.json';
    put(path, '{"round":0}');
    made = {};
    on_close = function() put(path, '{"round":99}'); end;
    local wrote = say(store.write(path, { round = 1 }));
    assert(wrote == 'false | The saved file changed while these changes were being saved. The newer file was kept. | changed', wrote);
    on_close = function() put(path, '{ broken'); end;
    wrote = say(store.write(path, { round = 2 }));
    assert(wrote == 'false | config/addons/vantage/failed.json contains invalid settings. It must be JSON saved as UTF-8. It was kept unchanged. | nil', wrote);
    assert(content(path) == '{ broken' and left() == '', 'The newer file stays and no temporary file is left.');

    local new = folder .. 'Race.txt';
    on_close = function() put(new, 'theirs'); end;
    local created = say(store.create(new, 'VG:1:00000000:{}'));
    on_close = nil;
    assert(created == 'false | config/addons/vantage/Race.txt already exists. | exists', created);
    assert(content(new) == 'theirs' and left() == '', 'A file made meanwhile stays and no temporary file is left.');
    created = say(store.create(new, 'VG:1:00000000:{}'));
    assert(created == 'false | config/addons/vantage/Race.txt already exists. | exists' and #made == 0, 'One already there is never written over: ' .. created);
end; -- end of section

do -- Section: a save that works leaves the file and no temporary file.
    local path, new = folder .. 'failed_done.json', folder .. 'Done.txt';
    made = {};
    assert(say(store.write(path, { round = 5 })) == 'true | nil | nil' and store.read(path).round == 5);
    assert(say(store.create(new, 'VG:1:00000000:{}')) == 'true | nil | nil' and content(new) == 'VG:1:00000000:{}');
    assert(#made == 2 and left() == '', 'Each makes one temporary file and moves it into place.');
end; -- end of section
io.open = open;
