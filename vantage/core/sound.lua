local ffi = require('ffi');
pcall(ffi.cdef, 'unsigned long __stdcall mciSendStringA(const char *command, char *answer, unsigned int size, void *window);');
local loaded, winmm = pcall(ffi.load, 'winmm');
local sound = {};
sound.FOLDER = require('core.identity').path('sounds/');
-- Each sound keeps its own alias once it has played, so switching sounds doesn't open one again: an open
-- takes tens of milliseconds on the render thread, a play of an open sound one or two.
local LIMIT = 8;
local message = 'This sound could not be played. Choose a local WAV or MP3 file.';
local files, slots, by_name, current, failed, problem, used = {}, {}, {}, nil, {}, nil, 0;

local function mci(command)
    if (not loaded) then return false; end
    local ok, result = pcall(winmm.mciSendStringA, command, nil, 0, nil);
    return ok and result == 0;
end

local function valid(name)
    if (type(name) ~= 'string' or name == '' or #name > 200 or name:find('[%c"\\/:]') or name:find('..', 1, true)) then return false; end
    local lower = name:lower();
    return lower:match('%.mp3$') ~= nil or lower:match('%.wav$') ~= nil;
end

function sound.refresh()
    local made, result = pcall(ashita.fs.create_dir, sound.FOLDER);
    if (not made or result == false) then return sound.files(), 'The local sounds folder could not be opened.'; end
    local ok, found = pcall(ashita.fs.get_directory, sound.FOLDER, '.*', false);
    if (not ok or type(found) ~= 'table') then return sound.files(), 'The local sound files could not be listed.'; end
    files = {};
    local seen = {};
    for _, name in ipairs(found) do
        if (valid(name) and not seen[name:lower()]) then files[#files + 1] = name; seen[name:lower()] = true; end
    end
    table.sort(files, function(a, b) return a:lower() < b:lower(); end);
    failed, problem = {}, nil;
    return sound.files();
end

function sound.files()
    local result = {};
    for i, name in ipairs(files) do result[i] = name; end
    return result;
end

local function close(index)
    local slot = slots[index];
    if (slot == nil) then return; end
    mci('close ' .. slot.alias);
    slots[index], by_name[slot.name] = nil, nil;
    if (current == index) then current = nil; end
end

function sound.close()
    for index = 1, LIMIT do close(index); end
end

local function give_up(name)
    if (by_name[name] ~= nil) then close(by_name[name]); end
    current, failed[name], problem = nil, true, message;
    return false, problem;
end

-- A free alias, or else the one played longest ago.
local function free_alias()
    local oldest;
    for index = 1, LIMIT do
        if (slots[index] == nil) then return index; end
        if (oldest == nil or slots[index].used < slots[oldest].used) then oldest = index; end
    end
    close(oldest);
    return oldest;
end

local function open(name)
    if (not valid(name) or not ashita.fs.exists(sound.FOLDER .. name)) then return give_up(name); end
    local index = free_alias();
    local alias = 'vantage_alert' .. index;
    if (not mci(('open "%s" type mpegvideo alias %s'):format(sound.FOLDER .. name, alias))) then return give_up(name); end
    used = used + 1;
    slots[index], by_name[name] = { name = name, alias = alias, used = used }, index;
    current, failed[name], problem = index, nil, nil;
    return true;
end

function sound.use(name, retry)
    if (name == '') then sound.close(); failed, problem = {}, nil; return true; end
    if (by_name[name] ~= nil) then current = by_name[name]; return true; end
    if (failed[name] and not retry) then return false, message; end
    return open(name);
end

local function start(slot, volume)
    if (volume ~= slot.level) then
        if (not mci(('setaudio %s volume to %d'):format(slot.alias, volume))) then return false; end
        slot.level = volume;
    end
    return mci('play ' .. slot.alias .. ' from 0');
end

function sound.play(volume)
    local slot = current and slots[current];
    if (slot == nil) then return false, problem or 'Choose a sound first.'; end
    volume = tonumber(volume) or 70;
    if (volume ~= volume) then volume = 70; end
    volume = math.floor(math.max(0, math.min(100, volume)) * 10 + 0.5);
    used = used + 1;
    slot.used = used;
    if (start(slot, volume)) then return true; end
    local name = slot.name;
    close(current);
    if (open(name) and start(slots[current], volume)) then return true; end
    return give_up(name);
end

if VANTAGE_TEST_MODE then function sound.is_open(name) return by_name[name] ~= nil; end end
function sound.problem(name)
    if (name == nil) then return problem; end
    return failed[name] and message or nil;
end

return sound;
