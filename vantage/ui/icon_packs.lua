-- Icon sets you add. Each is a folder in the icons folder of Vantage's settings folder, holding a picture for each effect
-- named by the effect's number, such as 33.png for Haste, or holding one folder that does. Each set is a choice beside
-- Original FFXI and XI View wherever status icons are picked (ui/icons.lua), and an effect a set has no picture for draws
-- as Original FFXI would. Vantage ships no pictures. It only reads the ones put there.
local packs = {};
local steady = require('core.steady');

-- The help of Reload icons and Open icons folder, on the main page and on Party list's Look tab.
packs.reload_help = 'Reads the icons folder in Vantage\'s settings folder again, so a set you added or changed shows without reloading Vantage. Put each set in a folder of its own there, with a picture per effect named by its number, such as 33.png for Haste. Vantage reads folders, not zip files, so extract a zipped set into a folder first.';
packs.open_help = 'Opens the folder your own icon sets go in. Put each set in a folder of its own, with a picture per effect named by its number, like 33.png for Haste. Vantage reads folders, not zip files, so extract a zipped set into a folder first. Then press Reload icons.';

-- The picture kinds D3DX reads, the most bytes a picture may have, the most pixels it may be each way, and the most a
-- set's usual texture is each way. A smaller picture is made at its own size.
local KINDS = { png = true, dds = true, bmp = true, tga = true, jpg = true, jpeg = true };
-- Packed files Vantage can't open. One in the icons folder with no folder of its name beside it is a set not extracted
-- yet, and the settings window says so.
local ARCHIVES = { zip = true, ['7z'] = true, rar = true };
local MOST_BYTES, MOST_SIDE, USUAL_SIDE = 1024 * 1024, 1024, 64;
-- Party list's icons are made at the size they are drawn (texture_at), as Original FFXI's are in ui/client_assets.lua:
-- a size is made once it has been asked for 0.25 s in a row, a set keeps 4 sizes at most, and a size let go of is
-- released at the start of a later Present (packs.frame).
local SIZES_KEPT, SIZE_WAIT = 4, 0.25;
-- D3DX reads and shrinks a whole picture to make each texture, which takes longer than the game's small icons do. So
-- at most 2 are made in a Present, and a picture over 256 KB has a Present to itself.
local BUILDS_PER_PRESENT, BIG_BYTES = 2, 256 * 1024;
-- A picture that couldn't be made is tried again after 5 s, as one still being saved may be whole by then.
local RETRY = 5;
-- A set can't have the name of a built-in choice, or Client, which was one. A Client saved before then draws as Original
-- FFXI, never as a set of that name.
local BUILT_IN = { client = true, ['original ffxi'] = true, ['xi view'] = true };

-- The sets found, in name order, by name, and their names. generation goes up each time the folder is read.
local sets, by_name, names, scanned, generation = {}, {}, {}, false, 0;
-- The sets by their names in lower case, as Windows finds a folder whatever the case of its name, and what each name
-- asked for found that way, so one in another case makes no new string each frame.
local sets_lower, looked, looked_count = {}, {}, 0;
-- Why the folder couldn't be read, and the folders in it that aren't sets, with why, for /vg report. archives and loose
-- are the packed files not extracted yet and the pictures put straight in it, nested the folders with no pictures named
-- by effect number but several folders inside that have some, and warning is what the settings window says about them.
local folder_reason, left_out, archives, loose, nested, warning = nil, {}, {}, {}, {}, nil;
local released, present, asked, builds = {}, 0, 0, 0;
local test_folder;

local function assets() return require('ui.client_assets'); end;

function packs.folder()
    return test_folder or require('core.identity').path('icons');
end;

-- Whether value can name a set: a folder name Windows allows that a label can show, and not a built-in choice's name.
-- A # at the end would join the ## that ends its label in a list, so it isn't allowed either.
-- Each name is checked once, as the icons ask each frame.
local valid, valid_count = {}, 0;
function packs.valid_name(value)
    if type(value) ~= 'string' then return false; end;
    local known = valid[value];
    if known ~= nil then return known; end;
    known = value ~= '' and #value <= 64 and not value:find('[%c<>:"/\\|%?%*]') and not value:find('##', 1, true)
        and not value:find('[%. #]$') and not BUILT_IN[value:lower()];
    if valid_count >= 64 then valid, valid_count = {}, 0; end;
    valid[value], valid_count = known, valid_count + 1;
    return known;
end;

-- The effect a file's picture is for, from the number its name starts with, as in 33.png or 33 Haste.png. The second
-- value says whether it is a picture at all, so a text file in the folder isn't called a problem.
local function picture_id(name)
    local stem, kind = name:match('^(.+)%.([^%.]+)$');
    if not stem or not KINDS[kind:lower()] then return nil, false; end;
    local digits = stem:match('^(%d+)$') or stem:match('^(%d+)[%s_%-%.]');
    local id = digits and #digits <= 4 and tonumber(digits);
    return id and id <= 1023 and id or nil, true;
end;

local function by_lower(a, b)
    local first, second = a.name:lower(), b.name:lower();
    if first ~= second then return first < second; end;
    return a.name < b.name;
end;

-- What a set says on the settings window while some of its pictures can't be used.
local function say_reason(set)
    local problems = #set.skipped + set.failures;
    set.reason = problems > 0 and ((problems == 1 and 'One picture in this set can\'t be used.' or problems .. ' pictures in this set can\'t be used.')
        .. ' /vg report says which and why.') or nil;
end;

local function release_textures(set)
    for _, texture in pairs(set.textures) do pcall(texture.release); end;
    for _, entry in pairs(set.sizes) do
        for _, texture in pairs(entry.textures) do pcall(texture.release); end;
    end;
    set.textures, set.sizes, set.failed, set.failures, set.size_failed = {}, {}, {}, 0, {};
    say_reason(set);
end;

local function release_later()
    for index = #released, 1, -1 do
        pcall(released[index]);
        released[index] = nil;
    end;
end;

-- Set name read from the files in folder path (entries), with each picture named by effect number and the ones left out
-- with why. numbered counts every picture named by effect number, used or not. entries are put in name order.
local function take(name, path, entries)
    local set = { name = name, path = path, files = {}, bytes = {}, count = 0, numbered = 0, skipped = {}, textures = {},
        failed = {}, failures = 0, sizes = {}, size_failed = {} };
    table.sort(entries, by_lower);
    for _, entry in ipairs(entries) do
        if not entry.folder then
            local id, picture = picture_id(entry.name);
            local skip;
            if id then set.numbered = set.numbered + 1; end;
            if id and set.files[id] then skip = 'Another picture in this set is already for effect ' .. id .. '.';
            elseif id and (tonumber(entry.size) or 0) > MOST_BYTES then skip = 'It is over 1 MB.';
            elseif id then set.files[id], set.bytes[id], set.count = entry.name, tonumber(entry.size) or 0, set.count + 1;
            elseif picture then skip = 'Its name doesn\'t start with an effect number.'; end;
            if skip then set.skipped[#set.skipped + 1] = { file = entry.name, reason = skip }; end;
        end;
    end;
    return set;
end;

-- A set from its folder's files, or nil and why it isn't one. A zip that held its set in a folder extracts one folder
-- too deep, as in Pack/Pack, so a folder with no pictures named by effect number and one folder in it that has some is
-- read from that one, under the outer folder's name. Several such folders in it can't be told apart, so it isn't a set,
-- and the third value is how many. Nothing deeper is looked in.
local function read_set(root, name)
    local path = root .. '/' .. name;
    local entries, why = assets().list_folder(path);
    if not entries then return nil, why; end;
    local set = take(name, path, entries);
    -- None can be a second picture for an effect while none is used, so each is too big.
    if set.count == 0 and set.numbered > 0 then return nil, 'Each of its pictures named by effect number is over 1 MB.'; end;
    if set.count == 0 then
        -- take put entries in name order, so the folders in it are too.
        local inside = {};
        for _, entry in ipairs(entries) do
            local listed = entry.folder and assets().list_folder(path .. '/' .. entry.name);
            local found = listed and take(name, path .. '/' .. entry.name, listed);
            if found and found.count > 0 then
                found.inner = entry.name;
                inside[#inside + 1] = found;
            end;
        end;
        if #inside > 1 then
            local folders = {};
            for index, found in ipairs(inside) do folders[index] = found.inner; end;
            return nil, 'It has no pictures named by effect number, but ' .. #inside .. ' folders inside it do: '
                .. table.concat(folders, ', ') .. '.', #inside;
        end;
        set = inside[1];
        if not set then return nil, 'It has no pictures named by effect number.'; end;
    end;
    say_reason(set);
    return set;
end;

-- What the settings window says while the icons folder holds a packed set not extracted yet, a folder of sets that
-- can't be told apart or pictures outside a set's folder, or nil. Made once a read, as it shows each frame.
local function say_folder()
    local parts = {};
    if #archives == 1 then
        parts[1] = archives[1].file .. ' is a ' .. archives[1].kind .. ' file. Vantage reads folders only, so extract it into'
            .. ' a folder of its own in the icons folder, then press Reload icons. If you already extracted it, delete it.';
    elseif #archives > 1 then
        local kind = archives[1].kind;
        for _, entry in ipairs(archives) do if entry.kind ~= kind then kind = 'compressed'; break; end; end;
        parts[1] = #archives .. ' ' .. kind .. ' files in the icons folder aren\'t read. Vantage reads folders only, so extract'
            .. ' each into a folder of its own, then press Reload icons. Delete any you already extracted.';
    end;
    if #nested == 1 then
        parts[#parts + 1] = nested[1].folder .. ' has no pictures named by effect number, but ' .. nested[1].count
            .. ' folders inside it do. Move each into the icons folder as a set of its own, then press Reload icons.';
    elseif #nested > 1 then
        parts[#parts + 1] = #nested .. ' folders in the icons folder have no pictures named by effect number, but several'
            .. ' folders inside each of them do. Move those into the icons folder as sets of their own, then press Reload icons.';
    end;
    if #loose == 1 then
        parts[#parts + 1] = loose[1] .. ' is loose in the icons folder. Put it in a folder named for its set, then press'
            .. ' Reload icons.';
    elseif #loose > 1 then
        parts[#parts + 1] = #loose .. ' pictures are loose in the icons folder. Put them in a folder named for their set,'
            .. ' then press Reload icons.';
    end;
    return parts[1] and table.concat(parts, ' ') or nil;
end;

-- Reads the icons folder: every set in it, by name, and the packed files and pictures in it that aren't in a set. What
-- the last read made is released. The folder is made when it isn't there yet, so there's a place to put sets.
local function scan()
    for _, set in ipairs(sets) do release_textures(set); end;
    release_later();
    sets, by_name, names, left_out, folder_reason, scanned = {}, {}, {}, {}, nil, true;
    archives, loose, nested, warning = {}, {}, {}, nil;
    sets_lower, looked, looked_count = {}, {}, 0;
    generation = generation + 1;
    local root = packs.folder();
    if not test_folder and ashita and ashita.fs and ashita.fs.create_dir then pcall(ashita.fs.create_dir, root); end;
    local entries, why = assets().list_folder(root);
    if not entries then folder_reason = why or 'The icons folder could not be read.'; return; end;
    table.sort(entries, by_lower);
    -- A packed file with a folder of its name beside it, whatever the case, has been extracted.
    local folders = {};
    for _, entry in ipairs(entries) do if entry.folder then folders[entry.name:lower()] = true; end; end;
    for _, entry in ipairs(entries) do
        if entry.folder then
            local name, problem = entry.name, nil;
            if not packs.valid_name(name) then
                problem = name:lower() == 'client' and 'Vantage keeps this name, as its old Client icons went by it.'
                    or BUILT_IN[name:lower()] and 'A built-in choice already has this name.' or 'Its name can\'t be shown as a choice.';
            else
                local set, inside;
                set, problem, inside = read_set(root, name);
                if set then
                    sets[#sets + 1], by_name[name], names[#names + 1] = set, set, name;
                    sets_lower[name:lower()] = sets_lower[name:lower()] or set;
                elseif inside then nested[#nested + 1] = { folder = name, count = inside }; end;
            end;
            if problem then left_out[#left_out + 1] = { folder = name, reason = problem }; end;
        else
            local stem, kind = entry.name:match('^(.+)%.([^%.]+)$');
            kind = kind and kind:lower();
            -- Windows drops spaces and dots from the end of the folder it extracts to.
            if ARCHIVES[kind] and not folders[(stem:gsub('[%s%.]+$', '')):lower()] then
                archives[#archives + 1] = { file = entry.name, kind = kind };
            elseif KINDS[kind] then loose[#loose + 1] = entry.name; end;
        end;
    end;
    warning = say_folder();
end;

local function find(name)
    if not scanned then scan(); end;
    local set = by_name[name];
    if set or type(name) ~= 'string' then return set; end;
    local known = looked[name];
    if known == nil then
        known = sets_lower[name:lower()] or false;
        if looked_count >= 64 then looked, looked_count = {}, 0; end;
        looked[name], looked_count = known, looked_count + 1;
    end;
    return known or nil;
end;

-- The names of the sets found, in order, and a number that changes each time the folder is read again.
function packs.names()
    if not scanned then scan(); end;
    return names;
end;

function packs.generation()
    if not scanned then scan(); end;
    return generation;
end;

function packs.found(name) return find(name) ~= nil; end;

-- The folder's own name for set name, which may differ from it in case alone.
function packs.name_of(name)
    local set = find(name);
    return set and set.name;
end;

-- Whether set name has a picture for effect id.
function packs.has(name, id)
    local set = find(name);
    return set ~= nil and set.files[id] ~= nil;
end;

-- What the settings window says about set name: why some of its pictures aren't used, or that it isn't there.
local missing = {};
function packs.reason(name)
    local set = find(name);
    if set then return set.reason; end;
    if type(name) ~= 'string' then return nil; end;
    local text = missing[name];
    if not text then
        text = 'The icon set ' .. name .. ' isn\'t in the icons folder, so the game\'s icons show. Put it back, then press Reload icons.';
        missing[name] = text;
    end;
    return text;
end;

-- A picture's width and height from its file's header, by its kind (the file's extension), or nil when it isn't one.
local function be16(bytes, at) local a, b = bytes:byte(at, at + 1); return a * 256 + b; end;
local function le16(bytes, at) local a, b = bytes:byte(at, at + 1); return a + b * 256; end;
local function be32(bytes, at) return be16(bytes, at) * 65536 + be16(bytes, at + 2); end;
local function le32(bytes, at) return le16(bytes, at) + le16(bytes, at + 2) * 65536; end;
local function jpeg_size(bytes)
    local at = 3;
    while at + 8 <= #bytes do
        if bytes:byte(at) ~= 0xFF then return nil; end;
        local marker = bytes:byte(at + 1);
        -- A start of frame holds the size. Huffman tables, arithmetic coding and the restart and fill markers don't.
        if marker >= 0xC0 and marker <= 0xCF and marker ~= 0xC4 and marker ~= 0xC8 and marker ~= 0xCC then
            return be16(bytes, at + 7), be16(bytes, at + 5);
        end;
        if marker == 0xFF then at = at + 1;
        elseif marker == 0x01 or marker >= 0xD0 and marker <= 0xD9 then at = at + 2;
        else at = at + 2 + be16(bytes, at + 2); end;
    end;
end;
function packs.picture_size(bytes, kind)
    if type(bytes) ~= 'string' then return nil; end;
    local width, height;
    if kind == 'png' and #bytes >= 24 and bytes:sub(1, 8) == '\137PNG\r\n\26\n' and bytes:sub(13, 16) == 'IHDR' then
        width, height = be32(bytes, 17), be32(bytes, 21);
    elseif kind == 'bmp' and #bytes >= 26 and bytes:sub(1, 2) == 'BM' then
        if le32(bytes, 15) == 12 then width, height = le16(bytes, 19), le16(bytes, 21);
        else
            width, height = le32(bytes, 19), le32(bytes, 23);
            -- A picture stored top row first gives its height below zero.
            if height >= 2147483648 then height = 4294967296 - height; end;
        end;
    elseif kind == 'dds' and #bytes >= 20 and bytes:sub(1, 4) == 'DDS ' then
        width, height = le32(bytes, 17), le32(bytes, 13);
    elseif kind == 'tga' and #bytes >= 18 then
        width, height = le16(bytes, 13), le16(bytes, 15);
    elseif (kind == 'jpg' or kind == 'jpeg') and #bytes >= 4 and bytes:byte(1) == 0xFF and bytes:byte(2) == 0xD8 then
        width, height = jpeg_size(bytes);
    end;
    if width and height and width >= 1 and height >= 1 then return width, height; end;
end;

-- Effect id's picture in set as a texture side px square, or nil and why. side nil makes the usual size: the picture's
-- own up to 64 px each way, with all its mip levels.
-- Whether a picture of set can be made in this Present, spending from its budget when it can.
local function spend(set, id)
    if builds >= BUILDS_PER_PRESENT or (set.bytes[id] or 0) > BIG_BYTES and builds > 0 then return false; end;
    if not assets().spend_upload() then return false; end;
    builds = (set.bytes[id] or 0) > BIG_BYTES and BUILDS_PER_PRESENT or builds + 1;
    return true;
end;

local function build(set, id, side, levels)
    local name = set.files[id];
    local bytes, why = assets().read_file(set.path .. '/' .. name, MOST_BYTES);
    if not bytes then return nil, why or 'It could not be read.'; end;
    local width, height = packs.picture_size(bytes, name:match('%.([^%.]+)$'):lower());
    if not width then return nil, 'It isn\'t a PNG, DDS, BMP, TGA or JPG picture Vantage can read.'; end;
    if width > MOST_SIDE or height > MOST_SIDE then return nil, 'It is over 1024 pixels across.'; end;
    side = side or math.max(1, math.min(USUAL_SIDE, math.max(width, height)));
    local uploaded, problem = assets().upload_picture(bytes, side, levels, 'pack.status');
    if not uploaded then return nil, problem or 'It could not be made into a texture.'; end;
    return { id = uploaded.id, release = uploaded.release, side = side };
end;

-- Set name's picture for effect id as its usual texture, made the first time it is drawn within this Present's budget
-- of new icon textures (client_assets.spend_upload). nil when the set has no picture for it, can't use it or isn't
-- there. While the budget is spent, nil and true: it is made in a later Present. One that couldn't be made is tried
-- again after RETRY, and the game's icon draws meanwhile.
function packs.texture(name, id)
    local set = find(name);
    local file = set and set.files[id];
    if not file then return nil; end;
    local made = set.textures[id];
    if made then return made.id; end;
    local failed = set.failed[id];
    if failed and steady() < failed.retry_at then return nil; end;
    if not spend(set, id) then
        if failed then return nil; end;
        return nil, true;
    end;
    local texture, why = build(set, id, nil, 0);
    if not texture then
        if not failed then set.failures = set.failures + 1; end;
        set.failed[id] = { reason = why, retry_at = steady() + RETRY };
        say_reason(set);
        return nil;
    end;
    if failed then
        set.failed[id], set.failures = nil, set.failures - 1;
        say_reason(set);
    end;
    set.textures[id] = texture;
    return texture.id;
end;

-- Effect id's picture made at size px for Party list, once its usual texture is made, or nil until then: the caller
-- draws the usual texture meanwhile. The usual texture's own size, and sizes past 128, always use that one.
function packs.texture_at(name, id, size)
    local set = find(name);
    local usual = set and set.textures[id];
    if not usual or type(size) ~= 'number' or size ~= math.floor(size) or size < 1 or size > 128 or size == usual.side then
        return nil;
    end;
    local sizes, now = set.sizes, steady();
    local entry = sizes[size];
    if not entry then
        -- A size past the 4 kept lets go of the one asked for least recently, never one asked for in this Present.
        local count, oldest = 0, nil;
        for _, other in pairs(sizes) do
            count = count + 1;
            if other.present ~= present and (not oldest or other.asked < oldest.asked) then oldest = other; end;
        end;
        if count >= SIZES_KEPT then
            if not oldest then return nil; end;
            for _, texture in pairs(oldest.textures) do released[#released + 1] = texture.release; end;
            sizes[oldest.size] = nil;
        end;
        entry = { size = size, textures = {}, failed = {}, since = now, present = present, asked = 0 };
        sizes[size] = entry;
    elseif entry.present < present - 1 then
        -- Not asked for in the Present before: the wait starts again.
        entry.since = now;
    end;
    asked = asked + 1;
    entry.present, entry.asked = present, asked;
    local texture = entry.textures[id];
    if texture then return texture.id; end;
    if entry.failed[id] and now < entry.failed[id] or now - entry.since < SIZE_WAIT or not spend(set, id) then return nil; end;
    local why;
    texture, why = build(set, id, size, 1);
    if not texture then
        -- It draws the usual texture scaled instead, and is tried again after RETRY. /vg report says so.
        entry.failed[id], set.size_failed[id] = now + RETRY, { size = size, reason = why };
        return nil;
    end;
    entry.failed[id] = nil;
    if set.size_failed[id] and set.size_failed[id].size == size then set.size_failed[id] = nil; end;
    entry.textures[id] = texture;
    return texture.id;
end;

-- At the start of each Present: the sizes let go of in an earlier one are released, after the frame that may still
-- have drawn them.
function packs.frame()
    present, builds = present + 1, 0;
    release_later();
end;

-- What the settings window says about the icons folder's packed files, folders of sets it can't tell apart and loose
-- pictures, or nil.
function packs.warning()
    if not scanned then scan(); end;
    return warning;
end;

-- Reads the icons folder again, for Reload icons: new sets and pictures show, and changed ones are made again.
function packs.reload()
    scan();
    return #sets;
end;

-- Opens the icons folder in File Explorer, made first if it isn't there yet, by starting explorer.exe with the folder.
-- ShellExecute isn't used: it runs Explorer's own code inside the game and can handle window messages before it
-- returns, and a click on Open icons folder with it crashed the frame it was in. Starting a process does neither, and
-- doesn't wait for Explorer, which opens the window itself.
local declared = false;
local function declare(ffi)
    if declared then return; end;
    if not pcall(ffi.typeof, 'vg_startup_info') then
        ffi.cdef[[
            typedef struct { unsigned long cb; char *reserved, *desktop, *title; unsigned long x, y, width, height, columns, rows,
                fill, flags; unsigned short show, reserved_size; unsigned char *reserved_bytes; void *input, *output, *error; } vg_startup_info;
            typedef struct { void *process, *thread; unsigned long process_id, thread_id; } vg_process_info;
        ]];
    end;
    pcall(ffi.cdef, 'int __stdcall CreateProcessA(const char*, char*, void*, void*, int, unsigned long, void*, const char*, vg_startup_info*, vg_process_info*);');
    pcall(ffi.cdef, 'unsigned int __stdcall GetWindowsDirectoryA(char*, unsigned int);');
    pcall(ffi.cdef, 'int __stdcall CloseHandle(void*);');
    declared = true;
end;

-- Starts program with the command line line, inheriting no handles, and lets go of the handles it gets back. Windows
-- shows no busy pointer for it (STARTF_FORCEOFFFEEDBACK). Returns whether it started.
local function start(program, line)
    local ffi = require('ffi');
    local command = ffi.new('char[?]', #line + 1, line);
    local startup, process = ffi.new('vg_startup_info'), ffi.new('vg_process_info');
    startup.cb, startup.flags = ffi.sizeof(startup), 0x80;
    if ffi.C.CreateProcessA(program, command, nil, nil, 0, 0, nil, nil, startup, process) == 0 then return false; end;
    ffi.C.CloseHandle(process.process);
    ffi.C.CloseHandle(process.thread);
    return true;
end;

local function explorer_open(path)
    local ffi = require('ffi');
    declare(ffi);
    local windows = ffi.new('char[260]');
    local length = ffi.C.GetWindowsDirectoryA(windows, 260);
    if length == 0 or length >= 260 then return false; end;
    local program = ffi.string(windows, length) .. '\\explorer.exe';
    return start(program, '"' .. program .. '" "' .. path .. '"');
end;
local opener = explorer_open;

function packs.open_folder()
    local root = packs.folder();
    if not test_folder and ashita and ashita.fs and ashita.fs.create_dir then pcall(ashita.fs.create_dir, root); end;
    local ok, opened = pcall(opener, (root:gsub('/', '\\')));
    return ok and opened == true;
end;

-- Lets go of every texture made, for a new graphics device or unload. The sets stay as they were read.
function packs.clear()
    for _, set in ipairs(sets) do release_textures(set); end;
    release_later();
end;

-- For /vg report: where the folder is, each set with how many pictures it has, the folder inside its own they were read
-- from when they are one folder down, how many are made, the files left out with why and the pictures Party list
-- couldn't make at a size, then the folders that aren't sets, and the packed files not extracted yet and the pictures
-- outside a set's folder.
function packs.report()
    if not scanned then scan(); end;
    local out = { folder = require('core.identity').relative('icons/'), reason = folder_reason, sets = {}, left_out = {},
        archives = {}, loose = {} };
    for index, entry in ipairs(left_out) do out.left_out[index] = { folder = entry.folder, reason = entry.reason }; end;
    for index, entry in ipairs(archives) do out.archives[index] = entry.file; end;
    for index, name in ipairs(loose) do out.loose[index] = name; end;
    for _, set in ipairs(sets) do
        local made, problems = 0, {};
        for _ in pairs(set.textures) do made = made + 1; end;
        for _, skipped in ipairs(set.skipped) do problems[#problems + 1] = { file = skipped.file, reason = skipped.reason }; end;
        for id, failed in pairs(set.failed) do problems[#problems + 1] = { file = set.files[id], reason = failed.reason }; end;
        table.sort(problems, function(a, b) return a.file < b.file; end);
        local sized = {};
        for id, failed in pairs(set.size_failed) do
            sized[#sized + 1] = { file = set.files[id], size = failed.size, reason = failed.reason };
        end;
        table.sort(sized, function(a, b) return a.file < b.file; end);
        out.sets[#out.sets + 1] = { name = set.name, inner_folder = set.inner, pictures = set.count, made = made, left_out = problems,
            sizes_failed = sized };
    end;
    return out;
end;

if VANTAGE_TEST_MODE then
    -- Tests never open a real File Explorer window. opener(path) stands in for it and says whether it opened.
    opener = function() return false; end;
    function packs._set_opener_for_tests(value) opener = value; end;
    function packs._set_folder_for_tests(value)
        test_folder = value;
        for _, set in ipairs(sets) do release_textures(set); end;
        sets, by_name, names, scanned, missing = {}, {}, {}, false, {};
        sets_lower, looked, looked_count = {}, {}, 0;
    end;
end;

return packs;
