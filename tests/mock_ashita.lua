-- The tests keep game state and input here. Nothing is sent to the client.
MOCK = {
    now = 0, events = {}, printed = {}, commands = {}, saved = 0, fs = {},
    imgui_calls = {}, clicks = {}, font_stack = {}, positions = {}, window_pos = {},
    chat = { x = 12, y = 520, width = 900, height = 344, windows = {} },
    player = {
        name = 'Tester', server_id = 1001, index = 0x400, zone = 102, status = 0,
        main_job = 1, main_level = 50, sub_job = 13, sub_level = 25,
        exp = 4500, exp_needed = 7800, limit_points = 2500, merits = 2,
        merit_cap = 10, mode = 'exp', buffs = {},
    },
};

os.clock = function () return MOCK.now; end
-- Use the client's table wrapper so settings defaults must support :copy(true).
assert(loadfile(ASHITA_LIBS .. '/sugar/table.lua'))();
addon = { path = ADDON_DIR or '.' };
function string.args(value)
    local result, state, start = {}, 'none', 1;
    for i = 1, #value do
        local character = value:sub(i, i);
        if state == 'none' and character == '"' then
            state, start = 'quote', i + 1;
        elseif state == 'none' and character ~= ' ' then
            state, start = 'word', i;
        elseif (state == 'quote' and character == '"') or (state == 'word' and character == ' ') then
            result[#result + 1] = value:sub(start, i - 1);
            state = 'none';
        end
    end
    if state == 'word' then result[#result + 1] = value:sub(start); end
    return result;
end

struct = {};
function struct.unpack(format, data, position)
    if format == 'c16' then return data:sub(position, position + 15); end
    local size = ({ L = 4, H = 2, B = 1, b = 1 })[format];
    assert(size, 'Unsupported struct format: ' .. tostring(format));
    local result = 0;
    for i = 0, size - 1 do result = result + (data:byte(position + i) or 0) * 256 ^ i; end
    return result;
end

ashita = { events = {}, fs = {}, memory = {}, bits = {}, time = { get_tick64 = function () return MOCK.now * 1000; end } };
function ashita.events.register(name, alias, callback)
    MOCK.events[name] = MOCK.events[name] or {};
    MOCK.events[name][alias] = callback;
end
-- Ashita hands addon callbacks each event as userdata, not a table. This is one over a table: reading and setting a
-- field reach the table, and pairs, next or rawget on the event fail as they do in the game.
function MOCK.event(values)
    local event = newproxy(true);
    local meta = getmetatable(event);
    meta.__index, meta.__newindex = values, values;
    return event;
end
-- A table event reaches the callbacks as userdata over it, so a fixture can still read what they set on it.
function MOCK.fire(name, event)
    if type(event) == 'table' then event = MOCK.event(event); end
    for _, callback in pairs(MOCK.events[name] or {}) do callback(event); end
end
function MOCK.frame(seconds)
    MOCK.now = MOCK.now + (seconds or 1 / 60);
    MOCK.fire('d3d_present');
end
function ashita.fs.exists(path)
    if MOCK.fs[path] ~= nil then return MOCK.fs[path]; end
    local file = io.open(path, 'rb');
    if file then file:close(); return true; end
    return false;
end
function ashita.fs.create_dir(path) if MOCK_MKDIR then return MOCK_MKDIR(path); end return true; end
function ashita.fs.get_directory(path) return MOCK.dirs and MOCK.dirs[path] or {}; end
ashita.memory.find = function () return 0; end
ashita.memory.read_uint32 = function () return 0; end
ashita.memory.read_uint8 = function () return 0; end
-- A decoded client image ('old' f2245d1c or 'new' 04288488) mapped at base, backing ashita.memory
-- and core.native_client. See client_image_fixture.lua.
function MOCK.load_client(name, base)
    local image = require('client_image_fixture').load(name, base):install();
    local ok, native = pcall(require, 'core.native_client');
    if ok and native._set_memory then native._set_memory(image:memory()); end
    return image;
end
-- A stand-in for the process environment core/patterns.lua keeps found client addresses in, for
-- patterns._set_store: the text stays in this table, so no fixture reaches the suite's own environment. reads and
-- writes count the calls.
function MOCK.pattern_store(text, process)
    local store = { text = text, reads = 0, writes = 0 };
    function store.read() store.reads = store.reads + 1; return store.text; end
    function store.write(value) store.writes = store.writes + 1; store.text = value; return true; end
    function store.process() return process or 1234; end
    return store;
end
function ashita.bits.unpack_be(data, byte_offset, bit_offset, length)
    local result = 0;
    for i = 0, length - 1 do
        local offset = byte_offset * 8 + bit_offset + i;
        local byte = type(data) == 'string' and data:byte(math.floor(offset / 8) + 1) or data[math.floor(offset / 8)];
        result = result + math.floor((byte or 0) / 2 ^ (offset % 8)) % 2 * 2 ^ i;
    end
    return result;
end

local player = {
    GetLoginStatus = function () return MOCK.login_status or 2; end,
    GetMainJob = function () return MOCK.player.main_job; end,
    GetMainJobLevel = function () return MOCK.player.main_level; end,
    GetSubJob = function () return MOCK.player.sub_job; end,
    GetSubJobLevel = function () return MOCK.player.sub_level; end,
    GetExp = function () return MOCK.player.exp; end,
    GetExpCurrent = function () return MOCK.player.exp; end,
    GetJobLevel = function () return MOCK.player.main_level; end,
    GetExpNeeded = function () return MOCK.player.exp_needed; end,
    GetLimitPoints = function () return MOCK.player.limit_points; end,
    GetMeritPoints = function () return MOCK.player.merits; end,
    GetMeritPointsMax = function () return MOCK.player.merit_cap; end,
    GetLimitMode = function () return MOCK.player.mode == 'lp' and 1 or 0; end,
    GetIsLimitModeEnabled = function () return MOCK.player.mode == 'lp'; end,
    GetIsLimitBreaker = function () return MOCK.player.limit_breaker ~= false; end,
    GetIsExperiencePointsLocked = function () return MOCK.player.exp_locked or false; end,
    GetIsZoning = function () return MOCK.zoning or false; end,
    GetStatusIcons = function () return nil; end,
    GetStatusTimers = function () return nil; end,
    GetBuffs = function ()
        local buffs = {};
        for i = 0, 31 do buffs[i] = MOCK.player.buffs[i + 1] or 255; end
        return buffs;
    end,
};
local party = {
    GetMemberServerId = function () return MOCK.zoning and 0 or MOCK.player.server_id; end,
    GetMemberTargetIndex = function () return MOCK.player.index; end,
    GetMemberName = function () return MOCK.player.name; end,
    GetMemberZone = function () return MOCK.player.zone; end,
};
AshitaCore = {
    GetMemoryManager = function ()
        return {
            GetPlayer = function () return player; end,
            GetParty = function () return party; end,
            GetEntity = function () return { GetStatus = function () return MOCK.player.status; end }; end,
        };
    end,
    GetInstallPath = function () return MOCK_INSTALL_PATH or '.'; end,
    GetChatManager = function ()
        return { QueueCommand = function (_, mode, command) MOCK.commands[#MOCK.commands + 1] = command; end,
            IsInputOpen = function () return MOCK.typing and 1 or 0; end };
    end,
};
function GetPlayerEntity()
    if MOCK.zoning then return nil; end
    return { Name = MOCK.player.name, ServerId = MOCK.player.server_id,
        Status = MOCK.player.status, StatusServer = MOCK.player.status, ZoneId = MOCK.player.zone };
end
print = function (...)
    local parts = {};
    for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)); end
    MOCK.printed[#MOCK.printed + 1] = table.concat(parts, ' '):gsub('[\30\31].', '');
end
package.preload.common = function () return {}; end
package.preload.chat = function ()
    return { header = function (text) return text; end, message = function (text) return text; end,
        error = function (text) return text; end, color1 = function (_, text) return text; end };
end
-- This is already projected geometry. Native-memory reads have their own adapter tests.
package.preload['core.chat'] = function ()
    return {
        load = function () return true; end,
        read = function ()
            MOCK.chat_reads = (MOCK.chat_reads or 0) + 1;
            return MOCK.chat, MOCK.chat == nil and 'Chat fixture unavailable.' or nil;
        end,
        -- No read here gives the menu size, as before the real reader's first.
        menu_size = function () return nil; end,
    };
end
package.loaded.ffi = {
    os = 'Windows', cdef = function () end,
    new = function (kind) assert(kind == 'unsigned long[1]'); return { [0]=0 }; end,
    load = function (name)
        if name ~= 'winmm' or MOCK.no_winmm then error('Library unavailable'); end
        return {
            mciSendStringA = function (command)
                MOCK.mci = MOCK.mci or {};
                MOCK.mci[#MOCK.mci + 1] = command;
                return MOCK.mci_code and MOCK.mci_code(command) or 0;
            end,
        };
    end,
    C = {
        GetAsyncKeyState = function (key)
            return ((key == 0x10 and MOCK.key_shift) or (key == 0x1B and MOCK.key_escape)) and -32768 or 0;
        end,
        GetCurrentProcessId = function () return 1234; end,
        GetForegroundWindow = function () if MOCK.foreground_absent then return nil; end; return 0x10000; end,
        GetWindowThreadProcessId = function (_, process)
            process[0] = MOCK.foreground_pid or 1234;
            return MOCK.foreground_unreadable and 0 or 5678;
        end,
        MoveFileExA = function (source, target, flags)
            if MOCK.file_replace_error then return 0; end
            -- Without MOVEFILE_REPLACE_EXISTING (1), as on Windows, a file there stays and the move fails.
            if bit.band(tonumber(flags) or 0, 1) == 0 then
                local there = io.open(target, 'rb');
                if there then there:close(); return 0; end
            end
            os.remove(target);
            return os.rename(source, target) and 1 or 0;
        end,
    },
};

local function clone(value)
    if type(value) ~= 'table' then return value; end
    local copy = {};
    for key, child in pairs(value) do copy[key] = clone(child); end
    return copy;
end
local settings = { callbacks = {} };
function settings.load(defaults)
    assert(type(defaults.copy) == 'function', 'settings.load requires defaults wrapped with T().');
    settings.defaults = defaults;
    settings.current = T(clone(MOCK.settings_file or defaults));
    return settings.current;
end
function settings.save()
    MOCK.saved = MOCK.saved + 1;
    settings.last_saved = clone(settings.current);
    return true;
end
function settings.register(_, name, callback) settings.callbacks[name] = callback; end
function settings.switch_character(value)
    settings.current = clone(value);
    for _, callback in pairs(settings.callbacks) do callback(settings.current); end
end
MOCK.settings = settings;
package.preload.settings = function () return settings; end

-- The binding reads a vector when it is called and keeps nothing, so drawing code may refill one table for every
-- call. A spy that looks at a call later reads a copy taken at call time.
function MOCK.copy_vector(value)
    if type(value) ~= 'table' then return value; end;
    local copy = {};
    for key, item in pairs(value) do copy[key] = item; end;
    return copy;
end
function MOCK.copy_arguments(...)
    local copy = { ... };
    for index = 1, select('#', ...) do copy[index] = MOCK.copy_vector(copy[index]); end;
    return copy;
end
-- A recorded draw call keeps the caller's own tables; MOCK.drawn[call] holds the copy of its values.
MOCK.drawn = setmetatable({}, { __mode = 'k' });
-- A stand-in for core.native_status_ui answers state() from its own status(), as the real module does.
function MOCK.status_state(module)
    return function ()
        local status = module.status();
        return status.active, status.reason_code, status.selection;
    end;
end

local bit = require('bit');
local windows = {};
local draw_list = setmetatable({}, { __index = function (_, name)
    return function (_, ...)
        local call = { 'draw:' .. name, ... };
        MOCK.imgui_calls[#MOCK.imgui_calls + 1] = call;
        MOCK.drawn[call] = MOCK.copy_arguments('draw:' .. name, ...);
    end;
end });
local function click(label)
    label = label:match('###(.*)$') or label;
    if not MOCK.clicks[label] then return false; end
    MOCK.clicks[label] = nil;
    return true;
end
local functions = {
    Begin = function (name, open)
        windows[#windows + 1] = name;
        if MOCK.next_pos then MOCK.positions[name] = MOCK.next_pos; MOCK.next_pos = nil; end
        -- The X on a window's title bar, clicked like any control.
        if open and MOCK.clicks['Title bar X'] then MOCK.clicks['Title bar X'], open[1] = nil, false; end
        return true;
    end,
    End = function () table.remove(windows); end,
    SetNextWindowPos = function (pos) MOCK.next_pos = { pos[1], pos[2] }; end,
    SetNextWindowSize = function (size) MOCK.next_size = { size[1], size[2] }; end,
    GetWindowPos = function ()
        local pos = MOCK.window_pos[windows[#windows]] or MOCK.positions[windows[#windows]] or { 0, 0 };
        return pos[1], pos[2];
    end,
    GetWindowSize = function () local size = MOCK.window_size or MOCK.next_size or { 880, 640 }; return size[1], size[2]; end,
    GetWindowDrawList = function () return draw_list; end,
    GetCursorScreenPos = function () return 14, 14; end,
    GetCursorPos = function () return 14, 14; end,
    GetCursorPosX = function () return 14; end,
    GetCursorPosY = function () return 14; end,
    GetContentRegionAvail = function () return MOCK.content_width or 820, 480; end,
    GetIO = function () return {
        DisplaySize = { x = MOCK.screen and MOCK.screen[1] or 1600, y = MOCK.screen and MOCK.screen[2] or 900 },
        MouseDelta = { x = MOCK.mouse_dx or 0, y = MOCK.mouse_dy or 0 }, KeyShift = MOCK.key_shift or false,
    }; end,
    GetFont = function () return 'default'; end,
    GetFontSize = function () return MOCK.font_stack[#MOCK.font_stack] or 18; end,
    CalcTextSize = function (text) return #tostring(text) * 8, 18; end,
    GetFrameHeight = function () return 26; end,
    PushFont = function (_, size) MOCK.font_stack[#MOCK.font_stack + 1] = size or 18; end,
    PopFont = function () table.remove(MOCK.font_stack); end,
    AddFontFromFileTTF = function (path) return path; end,
    BeginChild = function () return true; end, BeginTable = function () return true; end,
    BeginTooltip = function () return true; end, CollapsingHeader = function () return true; end,
    IsItemHovered = function () return false; end, IsWindowHovered = function () return MOCK.hovered or false; end,
    IsItemActive = function () return false; end, IsMouseDown = function () return MOCK.mouse_down or false; end,
    IsMouseClicked = function () return false; end, IsMouseReleased = function () return MOCK.mouse_released or false; end,
    IsMouseDragging = function () return MOCK.dragging or false; end,
    GetMousePos = function () return MOCK.mouse_x or -1, MOCK.mouse_y or -1; end,
    GetMouseDragDelta = function () return MOCK.mouse_dx or 0, MOCK.mouse_dy or 0; end,
    GetItemRectMin = function () return 0, 0; end, GetItemRectMax = function () return 100, 26; end,
    Button = click, SmallButton = click, Selectable = click, InvisibleButton = click, RadioButton = click,
    Checkbox = function (label, value) if click(label) then value[1] = not value[1]; return true; end return false; end,
    SetClipboardText = function (value) MOCK.clipboard = value; end,
    -- Ashita's col32 (libs/imgui.lua) packs with bit.bor, so a color with alpha 128 or more is negative.
    col32 = function (a, r, g, b) return bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r); end,
};
local imgui = setmetatable({}, { __index = function (_, name)
    return function (...)
        local call = { name, ... };
        if name == 'Button' then call[2] = call[2]:match('###(.*)$') or call[2]; end;
        -- Checkboxes can share one value box, so each call keeps what it was drawn with.
        if name == 'Checkbox' then call[3] = { call[3][1] }; end;
        MOCK.imgui_calls[#MOCK.imgui_calls + 1] = call;
        if functions[name] then return functions[name](...); end
        return false;
    end;
end });
-- Ashita's drawing is shown unless a fixture sets MOCK.gui_visible to false, as /hideui does.
local gui_manager = setmetatable({ GetVisible = function () return MOCK.gui_visible ~= false; end }, { __index = imgui });
AshitaCore.GetGuiManager = function () return gui_manager; end;
package.preload.imgui = function () return imgui; end

-- Use the client's enum values when available. The renderer replaces these by name.
local client_imgui = loadfile(ASHITA_LIBS .. '/imgui.lua');
if client_imgui then client_imgui(); end
ImGuiCond_Always = ImGuiCond_Always or 1;
FLT_MAX = 3.402823466e+38;

function MOCK.bytes(size)
    local bytes = { n = size };
    for i = 0, size - 1 do bytes[i] = 0; end
    return bytes;
end
function MOCK.put(bytes, offset, size, value)
    for i = 0, size - 1 do bytes[offset + i] = math.floor(value / 256 ^ i) % 256; end
end
-- An incoming packet event, as userdata like Ashita's.
function MOCK.packet(id, bytes)
    local characters = {};
    for i = 0, bytes.n - 1 do characters[#characters + 1] = string.char(bytes[i] or 0); end
    return MOCK.event({ id = id, size = bytes.n, data_raw = bytes, data = table.concat(characters), injected = false, blocked = false });
end
