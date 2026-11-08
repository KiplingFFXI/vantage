-- Per-frame Lua cost of the real vantage.lua and UI modules: real client art (read only), a mocked SDK and an
-- ImGui stand-in that keeps every draw argument reachable, as a C binding call needs it. Not FPS.
-- Argument: 'solo' (fresh defaults), 'party6' or 'alliance18'; or 'settings' (party6 with
-- the settings window open on the main page, every section drawn open), 'filters' (party6 with five shared hide rules on) or
-- 'overhead' (party6 with overhead icons on: the target, four mobs the party debuffed and the five members, ten units
-- with eight icons each), or 'cooldowns' (overhead with the party cooldown watch everywhere: each member's two-hour and
-- a key ability on their strip and overhead block and in the list, a ready pulse playing on a recast row and one at
-- the screen spot, and the player with Dispel learned, so the Target panel and the target's block light its buffs),
-- 'rolls' (party6 with the Phantom Roll display: your roll and a member's, their members and their Double-Up windows
-- ticking) or 'pet' (party6 with the pet display: a jug pet with its clock and bars, eight effects with countdowns, two
-- of them blinking, three lines of maneuvers and six pet command recasts), or 'edit' (party6 in edit mode: every display outlined over the grid with the
-- edit mode bar, Self debuffs anchored below Self buffs, Target at the screen's top right, the combined recasts above
-- the chat log and the notices above the game's party list, and every timer panel shown only as RDM in a field). The
-- harness player is Silenced and Amnesia'd in every scenario, so recast rows draw their locks where the tints are on.
-- The party cooldown watch, the ready pulse, the recast tints and the panels' buff light are off at first; the
-- cooldowns scenario turns them on.
-- The settings_ scenarios below are the settings scenario open on another page. A search_ scenario is one of those, or
-- the settings scenario as search_home, with `effects` held in the settings search box: a plural, which costs the
-- search most. 'search' is a player typing there: a new word every 25 frames, and a new page every 100.
-- 'main_closed' and 'main_open' are the settings scenario on the main page as a player has it, with More look closed
-- and open. The panel_ scenarios are the settings scenario on a tab of a panel as a player has it, its folds closed:
-- panel_show to panel_when on Watched enemy timers, in bars for the most rows, on a panel that draws nothing here so the
-- scene stays party6's; panel_recasts on Recasts' Show; and panel_look_open with Look's folds open. panel_party to
-- panel_party_when are the tabs of Party list buffs, panel_overhead and panel_overhead_filters those tabs of Overhead icons,
-- panel_cooldowns Party cooldowns' Show with the list on and Abilities to watch open, panel_rolls Phantom Roll's Show,
-- panel_pet and panel_pet_filters those tabs of Pet, panel_alerts Alerts' Show, panel_alerts_rule the same with a rule open,
-- and panel_hidden Hidden everywhere.
-- Used by test_draw_digest.py, benchmark_frame.py and jit_flush_guard.py, in the test runtime and in a plain x86
-- LuaJIT (x86_runtime.lua).
local SCENARIO = ...;
local NAME, HELD, TYPING = SCENARIO, SCENARIO:match('^search_(%a+)$'), SCENARIO == 'search';
if HELD or TYPING then SCENARIO = (TYPING or HELD == 'home') and 'settings' or 'settings_' .. HELD; end;
local MORE_LOOK = ({ main_closed = false, main_open = true, main_grid = false })[SCENARIO];
local GRID_FOLD = SCENARIO == 'main_grid';
if MORE_LOOK ~= nil then SCENARIO = 'settings'; end;
local PANEL_TAB = ({ panel_show = { 'watch', 'show' }, panel_look = { 'watch', 'look' },
    panel_look_open = { 'watch', 'look', true }, panel_filters = { 'watch', 'filters' }, panel_place = { 'watch', 'place' },
    panel_when = { 'watch', 'when' }, panel_recasts = { 'recasts', 'show' }, panel_party = { 'party_ui', 'show' },
    panel_party_look = { 'party_ui', 'look' }, panel_party_filters = { 'party_ui', 'filters' },
    panel_party_place = { 'party_ui', 'place' }, panel_party_when = { 'party_ui', 'when' }, panel_overhead = { 'overhead', 'show' },
    panel_overhead_filters = { 'overhead', 'filters' }, panel_cooldowns = { 'cooldown_list', 'show', true },
    panel_rolls = { 'rolls', 'show' }, panel_pet = { 'pet', 'show' }, panel_pet_filters = { 'pet', 'filters' },
    panel_alerts = { 'notices', 'show' }, panel_alerts_rule = { 'notices', 'show' }, panel_hidden = { 'hidden', 'show' } })[SCENARIO];
if PANEL_TAB then SCENARIO = 'settings_display'; end;
local PAGES = { settings_filters = 'Filters', settings_display = 'Display', settings_party = 'Party & alliance',
    settings_durations = 'Durations', settings_profiles = 'Profiles', settings_help = 'Help' };
local PAGE, PAGE_SCENARIO = PAGES[SCENARIO], PAGES[SCENARIO] and SCENARIO;
assert(SCENARIO == 'solo' or SCENARIO == 'party6' or SCENARIO == 'alliance18' or SCENARIO == 'settings'
    or SCENARIO == 'filters' or SCENARIO == 'overhead' or SCENARIO == 'cooldowns' or SCENARIO == 'rolls' or SCENARIO == 'pet'
    or SCENARIO == 'edit' or PAGE, 'unknown scenario');
local COOLDOWNS_ON, ROLLS_ON, PET_ON, EDIT_ON = SCENARIO == 'cooldowns', SCENARIO == 'rolls', SCENARIO == 'pet', SCENARIO == 'edit';
local SETTINGS_OPEN, FILTERS_ON, OVERHEAD_ON = SCENARIO == 'settings' or PAGE ~= nil, SCENARIO == 'filters', SCENARIO == 'overhead' or COOLDOWNS_ON;
if SETTINGS_OPEN or FILTERS_ON or OVERHEAD_ON or ROLLS_ON or PET_ON or EDIT_ON then SCENARIO = 'party6'; end;

-- The mock replaces ffi; the runtime's own one reads the clock.
local real_ffi = package.preload.ffi('ffi');
pcall(real_ffi.cdef, 'int __stdcall QueryPerformanceCounter(int64_t*); int __stdcall QueryPerformanceFrequency(int64_t*);');
local ticks = real_ffi.new('int64_t[1]');
real_ffi.C.QueryPerformanceFrequency(ticks);
local frequency = tonumber(ticks[0]);
local function clock() real_ffi.C.QueryPerformanceCounter(ticks); return tonumber(ticks[0]) / frequency; end;
H = { clock = clock };

-- ImGui stand-in. The digest folds every draw call: name, canonical texture, positions, UVs, colors and text.
local io_table = { DisplaySize = { x = 1920, y = 1080 }, MouseDelta = { x = 0, y = 0 }, KeyShift = false,
    KeyCtrl = false, KeyAlt = false, Fonts = {} };
local style_table = { WindowPadding = { x = 8, y = 8 }, FramePadding = { x = 4, y = 3 }, ItemSpacing = { x = 8, y = 4 },
    ItemInnerSpacing = { x = 4, y = 4 }, Alpha = 1, WindowRounding = 0, FrameRounding = 0, ScrollbarSize = 14,
    Colors = setmetatable({}, { __index = function() return { 1, 1, 1, 1 }; end }) };
local cx0, cy0, cx1, cy1, depth = {}, {}, {}, {}, 0;
local nx, ny, nw, nh = 0, 0, 100, 100;
local font_sizes, font_depth = { [0] = 14 }, 0;
local list = {};
local sink = {};
local escape = function(a, b, c, d) sink[1], sink[2], sink[3], sink[4] = a, b, c, d; return false; end;
local digest = { on = false, value = 0, count = 0, ids = {}, next_id = 0 };
local function fold(v)
    local kind = type(v);
    if kind == 'number' then digest.value = (digest.value * 31 + math.floor(v * 1000 + 0.5)) % 2147483647;
    elseif kind == 'table' then fold(v[1] or v.x); fold(v[2] or v.y); if v[3] then fold(v[3]); fold(v[4]); end;
    elseif kind == 'string' then for i = 1, #v do digest.value = (digest.value * 31 + v:byte(i)) % 2147483647; end;
    elseif kind == 'boolean' then digest.value = (digest.value * 31 + (v and 1 or 2)) % 2147483647; end;
end;
local function draw(name)
    local image = name == 'draw:AddImage' or name == 'draw:AddImageQuad';
    return function(_, a, b, c, d, e, f, g, h, i, j, k)
        if digest.on then
            digest.count = digest.count + 1;
            fold(name);
            if image then
                -- Texture ids depend on load order, so the digest numbers them as first drawn.
                local id = digest.ids[a];
                if not id then digest.next_id = digest.next_id + 1; id = digest.next_id; digest.ids[a] = id; end;
                fold(id);
            else fold(a); end;
            fold(b); fold(c); fold(d); fold(e); fold(f); fold(g); fold(h); fold(i); fold(j); fold(k);
        end;
        sink[1], sink[2], sink[3], sink[4], sink[5], sink[6], sink[7], sink[8], sink[9], sink[10], sink[11] = a, b, c, d, e, f, g, h, i, j, k;
    end;
end;
for _, name in ipairs({ 'AddImage', 'AddImageQuad', 'AddText', 'AddRect', 'AddRectFilled', 'AddLine', 'AddTriangleFilled',
    'AddPolyline', 'AddCircleFilled', 'AddCircle', 'AddRectFilledMultiColor', 'AddQuadFilled', 'AddQuad', 'AddImageRounded',
    'AddTriangle', 'AddNgonFilled', 'PathClear', 'PathLineTo', 'PathStroke', 'PathFillConvex', 'AddConvexPolyFilled' }) do
    list[name] = draw('draw:' .. name);
end;
local push_clip = draw('draw:PushClipRect');
list.PushClipRect = function(self, a, b, intersect)
    push_clip(self, a, b, intersect);
    local d = depth;
    local x0, y0, x1, y1 = a[1] or a.x, a[2] or a.y, b[1] or b.x, b[2] or b.y;
    if intersect ~= false and d > 0 then
        x0, y0 = math.max(x0, cx0[d]), math.max(y0, cy0[d]);
        x1, y1 = math.min(x1, cx1[d]), math.min(y1, cy1[d]);
    end;
    d = d + 1;
    cx0[d], cy0[d], cx1[d], cy1[d], depth = x0, y0, x1, y1, d;
end;
list.PopClipRect = function() if depth > 1 then depth = depth - 1; end; end;
list.GetClipRectMin = function() return cx0[depth] or 0, cy0[depth] or 0; end;
list.GetClipRectMax = function() return cx1[depth] or 1920, cy1[depth] or 1080; end;
setmetatable(list, { __index = function() return escape; end });

local bit = require('bit');
local F = {
    Begin = function() depth = 1; cx0[1], cy0[1], cx1[1], cy1[1] = nx, ny, nx + nw, ny + nh; return true; end,
    End = function() depth = 0; end,
    BeginChild = function() return true; end,
    BeginTooltip = function() return true; end,
    BeginTable = function() return true; end,
    SetNextWindowPos = function(v) sink[1] = v; nx, ny = v[1] or v.x, v[2] or v.y; end,
    SetNextWindowSize = function(v) sink[1] = v; nw, nh = v[1] or v.x, v[2] or v.y; end,
    GetWindowPos = function() return nx, ny; end,
    GetWindowSize = function() return nw, nh; end,
    GetWindowDrawList = function() return list; end,
    GetForegroundDrawList = function() return list; end,
    GetBackgroundDrawList = function() return list; end,
    GetIO = function() return io_table; end,
    GetStyle = function() return style_table; end,
    GetMousePos = function() return -1, -1; end,
    GetMouseDragDelta = function() return 0, 0; end,
    GetFont = function() return 1; end,
    GetFontSize = function() return font_sizes[font_depth]; end,
    PushFont = function(_, size) font_depth = font_depth + 1; font_sizes[font_depth] = size or 14; end,
    PopFont = function() if font_depth > 0 then font_depth = font_depth - 1; end; end,
    CalcTextSize = function(text) local s = font_sizes[font_depth]; return #tostring(text) * s * 0.5, s; end,
    GetScrollY = function() return 0; end, GetScrollX = function() return 0; end,
    GetScrollMaxY = function() return 0; end, GetScrollMaxX = function() return 0; end,
    GetCursorScreenPos = function() return nx, ny; end, GetCursorPos = function() return 0, 0; end,
    GetCursorPosX = function() return 0; end, GetCursorPosY = function() return 0; end,
    GetContentRegionAvail = function() return nw, nh; end,
    GetFrameHeight = function() return 20; end, GetTextLineHeight = function() return 14; end,
    GetTextLineHeightWithSpacing = function() return 18; end, GetFrameHeightWithSpacing = function() return 24; end,
    GetItemRectMin = function() return 0, 0; end, GetItemRectMax = function() return 10, 10; end,
    GetItemRectSize = function() return 10, 10; end,
    GetWindowWidth = function() return nw; end, GetWindowHeight = function() return nh; end,
    col32 = function(a, r, g, b) return bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r); end,
    AddFontFromFileTTF = function(path) return path; end,
    PushStyleVar = function(a, b) sink[1], sink[2] = a, b; end,
    SetCursorPos = function(a) sink[1] = a; end,
    InvisibleButton = function(a, b) sink[1], sink[2] = a, b; return false; end,
};
local imgui = setmetatable({}, { __index = function() return escape; end });
for name, fn in pairs(F) do rawset(imgui, name, fn); end;
package.loaded.imgui = imgui;
-- What the settings search box holds, in the scenarios that use it.
local box_text = HELD and 'effects' or '';
local function search_box(label, _, value)
    if label == '##find_settings' then value[1] = box_text; end;
    return false;
end;
if HELD or TYPING then rawset(imgui, 'InputTextWithHint', search_box); end;
local gui_manager = { GetVisible = function() return true; end };
AshitaCore.GetGuiManager = function() return gui_manager; end;

require('client_art_fixture')();

-- SDK: the party, self buffs with server timers, a target and recasts.
-- Members, effects on each member, on the player and on the target, by scenario.
local function shape(name)
    if name == 'alliance18' then return 18, 32, 32, 32; end;
    return name == 'party6' and 6 or 1, 12, 16, 8;
end;
local member_count, effects_each, self_effects, target_effects = shape(SCENARIO);
local members, party_icons, buffs, timers = {}, {}, {}, {};
-- The client's party and status icons, and the player's buffs with their server deadlines in 1/60 s ticks, as the
-- client lists them, counted from start (seconds).
local function fill(count, each, own, start)
    for slot = 0, 17 do
        members[slot] = slot < count and { id = 1001 + slot, index = 0x400 + slot, zone = 102,
            name = slot == 0 and 'Bench' or ('Member' .. slot) } or nil;
    end;
    for slot = 0, 31 do
        party_icons[slot] = slot < each and (slot + 40) or 255;
        buffs[slot] = slot < own and (slot + 1) or 255;
        timers[slot] = slot < own and ((1000000 + start + 240 + slot * 97) * 60) % 4294967296 or 0;
    end;
end;
fill(member_count, effects_each, self_effects, 10);
-- What these lists hold that the catalog leaves out: the client names them, and they show under those names.
for _, id in ipairs({ 17, 18, 19, 20, 21, 23, 24, 25, 26, 27, 53 }) do
    require('data.catalog')[id] = { id = id, name = 'Status ' .. id, kind = 'other', group = 'Other', priority = 0 };
end;
local mm = AshitaCore:GetMemoryManager();
local party, player = mm:GetParty(), mm:GetPlayer();
MOCK.player.server_id, MOCK.player.index, MOCK.player.zone = 1001, 0x400, 102;
MOCK.player.name, MOCK.player.main_job, MOCK.player.main_level = 'Bench', 5, 75;
for name, key in pairs({ GetMemberServerId = 'id', GetMemberTargetIndex = 'index', GetMemberZone = 'zone', GetMemberName = 'name' }) do
    party[name] = function(_, slot) local m = members[slot]; return m and m[key] or 0; end;
end;
for name, value in pairs({ GetMemberHP = 1234, GetMemberMP = 567, GetMemberTP = 1200, GetMemberHPPercent = 90,
    GetMemberMPPercent = 80, GetMemberMainJob = 5, GetMemberMainJobLevel = 75, GetMemberSubJob = 4, GetMemberSubJobLevel = 37,
    GetMemberLastUpdatedTimestamp = 1, GetAllianceLeaderServerId = 1001, GetAlliancePartyLeaderServerId1 = 1001 }) do
    party[name] = function() return value; end;
end;
party.GetMemberIsActive = function(_, slot) return members[slot] and 1 or 0; end;
party.GetStatusIconsServerId = function(_, entry) local m = members[entry + 1]; return m and m.id or 0; end;
party.GetStatusIconsTargetIndex = function(_, entry) return 0x401 + entry; end;
party.GetStatusIcons = function() return party_icons; end;
party.GetStatusIconsBitMask = function() return 0; end;
player.GetStatusIcons = function() return buffs; end;
package.loaded['core.clock'] = { available = function() return true; end, get_game_time_raw = function() return 1000000 + MOCK.now; end };
player.GetStatusTimers = function() return timers; end;
player.GetBuffs = function() return buffs; end;
-- Four more mobs at 501 to 504, which only the overhead scenario debuffs. Their ids' low 12 bits are their indexes,
-- as a mob's are. The pet scenario's jug pet is at 505, and only it gives you a pet.
local function extra_mob(index) return index >= 501 and index <= 504; end
local PET_INDEX, PET_ID = 505, 0x10011F9;
local pet_out = false;
local entity = {
    GetServerId = function(_, index)
        return index == 500 and 0x1001234 or extra_mob(index) and 0x1001000 + index or index == PET_INDEX and PET_ID
            or index >= 0x400 and index <= 0x411 and 1001 + index - 0x400 or 0;
    end,
    GetName = function(_, index) return index == 500 and 'Goblin Bandit' or extra_mob(index) and 'Goblin Thug' or index == PET_INDEX and 'Goblin Pet' or 'Member'; end,
    GetSpawnFlags = function(_, index) return (index == 500 or extra_mob(index)) and 0x10 or 0x01; end,
    GetDistance = function() return 25; end, GetHPPercent = function() return 64; end,
    GetStatus = function() return 1; end, GetActorPointer = function() return 0x2000000; end,
    -- Where the overhead icons look: you at the origin, the party a row ahead, the target further on and the other mobs
    -- in a row past it, all drawn.
    GetLocalPositionX = function(_, index)
        return index == 500 and 0 or extra_mob(index) and (index - 502.5) * 3 or index > 0x400 and index - 0x403 or 0;
    end,
    GetLocalPositionZ = function() return 0; end,
    GetLocalPositionY = function(_, index) return index == 500 and -8 or extra_mob(index) and -11 or index > 0x400 and -3 or 0; end,
    GetRenderFlags0 = function() return 0x200; end,
    GetType = function(_, index) return (index == 500 or extra_mob(index)) and 1 or 0; end,
    GetRace = function(_, index) return (index == 500 or extra_mob(index)) and 0 or 1; end, GetModelSize = function() return -1; end,
    GetModelHitboxSize = function(_, index) return (index == 500 or extra_mob(index)) and 1.2 or 0.4; end,
    GetPetTargetIndex = function(_, index) return pet_out and index == 0x400 and PET_INDEX or 0; end,
};
local target = {
    GetTargetIndex = function(_, which) return which == 0 and 500 or 0; end,
    GetServerId = function(_, which) return which == 0 and 0x1001234 or 0; end,
    GetIsSubTargetActive = function() return 0; end, GetIsActive = function() return 1; end,
    GetWindowServerId = function() return 0x1001234; end, GetWindowIsWindowLoaded = function() return 1; end,
    GetWindowDeathFlag = function() return 0; end, GetLockedOnFlags = function() return 0; end,
    GetActorPointer = function() return 0x2000000; end, GetEntityPointer = function() return 0x3000000; end,
};
local spell_timers = { [57] = 1200, [86] = 3000, [112] = 600 };
-- The client's names for those three spells. Vantage reads the timers of the spells the client names, and no others.
local spell_names = { [57] = { Name = { 'Haste' } }, [86] = { Name = { 'Barsleepra' } }, [112] = { Name = { 'Flash' } } };
local resources = { GetSpellById = function(_, id) return spell_names[id]; end };
AshitaCore.GetResourceManager = function() return resources; end;
-- With the pet out, slots 4 to 9 hold six of its commands' timers.
local pet_timers = { [4] = 102, [5] = 103, [6] = 104, [7] = 97, [8] = 100, [9] = 152 };
local recast = {
    GetSpellTimer = function(_, id) return spell_timers[id] or 0; end,
    GetAbilityTimerId = function(_, slot) return slot == 0 and 0 or slot < 4 and (slot + 10) or pet_out and pet_timers[slot] or 0; end,
    GetAbilityTimer = function(_, slot) return slot > 0 and slot < 4 and 1800 or pet_out and pet_timers[slot] and 600 + slot * 300 or 0; end,
};
player.GetPetMPPercent, player.GetPetTP = function() return 40; end, function() return 1250; end;
-- Dispel is learned only in the cooldowns scenario.
local dispel_learned = false;
player.HasSpell = function(_, id) return dispel_learned and id == 260; end;
player.GetStat, player.GetStatModifier = function() return 60; end, function() return 10; end;
mm.GetParty = function() return party; end;
mm.GetPlayer = function() return player; end;
mm.GetEntity = function() return entity; end;
mm.GetTarget = function() return target; end;
mm.GetRecast = function() return recast; end;
AshitaCore.GetMemoryManager = function() return mm; end;

-- The game's party list at the bottom right, a window for each party with a 20 px row for each member, so the strips
-- draw beside it. Its client reads have their own tests. The tables are reused, so the fixture adds no allocation.
local game_rows, game_frames, game_slots = { groups = {} }, {}, {};
for group = 1, 3 do
    local frame = { x = 1700, y = 950 - (group - 1) * 130, width = 200, height = 120, rows = {} };
    game_frames[group] = frame;
    for row = 0, 5 do
        local slot = (group - 1) * 6 + row;
        game_slots[slot] = { x = 1700, y = frame.y + row * 20, width = 200, height = 20, slot = slot };
    end;
end;
require('core.native_party_ui').geometry = function(roster)
    local groups = game_rows.groups;
    for group = 1, 3 do groups[group] = nil; for row = 0, 5 do game_frames[group].rows[(group - 1) * 6 + row] = nil; end; end;
    for _, member in ipairs(roster.members or {}) do
        local row = game_slots[member.slot];
        if row then
            local group = math.floor(member.slot / 6) + 1;
            groups[group] = game_frames[group];
            game_frames[group].rows[member.slot] = row;
        end;
    end;
    game_rows.available = next(groups) ~= nil;
    return game_rows;
end;

-- The app at its fresh defaults, plus the scenario's displays and four alert rules.
local app = dofile(ADDON_DIR .. '/vantage.lua');
H.app = app;
MOCK.now = 10;
MOCK.fire('load');
app.refresh(MOCK.now);
local settings = app.state.settings;
H.settings = settings;
settings.party_ui.enabled = SCENARIO ~= 'solo';
-- The overhead camera: 2 yalms up at Y = 10 looking along -Y, P22 1.7 at 16:9, read into the camera's own tables. An
-- addon folder without overhead icons (benchmark_frame.py --addon) has none.
local overhead_view = { 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, -1, 0, 0, -2, 10, 1 };
local overhead_projection = { 1.7 * 9 / 16, 0, 0, 0, 0, 1.7, 0, 0, 0, 0, 200 / 199.5, 1, 0, 0, -0.5 * 200 / 199.5, 0 };
local has_camera, overhead_camera = pcall(require, 'core.camera');
if has_camera then
    overhead_camera._set_reader(function(view, projection)
        for i = 1, 16 do view[i], projection[i] = overhead_view[i], overhead_projection[i]; end
        return true;
    end);
end;
assert(settings.overhead or not OVERHEAD_ON, 'This addon has no overhead icons.');
-- Overhead icons: the party's own buffs from the client have no caster, so its blocks show every buff.
local function overhead_on(config, on)
    if not config then return; end;
    config.enabled = on;
    if on then config.types.party.buffs_mine_only = false; end;
end;
overhead_on(settings.overhead, OVERHEAD_ON);
settings.alerts.enabled = true;
settings.diagnostics.record = false;
-- The target's effects and the effects tracked on alliance members (slots 6 on), as the tracker hears of them.
local function track(count, each, aimed, debuffed)
    local observations = {};
    for effect = 1, aimed do
        observations[#observations + 1] = { kind = 'apply', entity_id = 0x1001234, effect = 100 + effect, source = 1001, duration = 180 + effect * 7 };
    end;
    -- Eight debuffs you cast on each of the other mobs (Phoenix effect ids 2 to 9).
    for index = 501, debuffed and 504 or 0 do
        for effect = 2, 9 do
            observations[#observations + 1] = { kind = 'apply', entity_id = 0x1001000 + index, effect = effect, source = 1001,
                duration = 120 + effect * 11, scope = 'enemy' };
        end;
    end;
    for slot = 6, count - 1 do
        for effect = 1, each do
            observations[#observations + 1] = { kind = 'apply', entity_id = 1001 + slot, effect = 40 + effect, source = 1001, duration = 900 + effect };
        end;
    end;
    app.tracker:observe(observations, MOCK.now, app.state.snapshot);
end;
track(member_count, effects_each, target_effects, OVERHEAD_ON);
local rule_defaults = require('ui.defaults');
settings.alerts.rules = {};
for i = 1, 4 do
    local rule = rule_defaults.rule('bench' .. i);
    rule.scope, rule.effect, rule.event = 'self', i, i <= 2 and 'missing' or 'remaining';
    rule.chat, rule.sound = false, '';
    settings.alerts.rules[#settings.alerts.rules + 1] = rule;
end;
-- The settings scenario draws every section open.
local open_sections = { 'CollapsingHeader', 'TreeNode', 'TreeNodeEx', 'BeginTabBar', 'BeginTabItem' };
if SETTINGS_OPEN then
    for _, name in ipairs(open_sections) do
        rawset(imgui, name, function() return true; end);
    end;
    if MORE_LOOK ~= nil then
        rawset(imgui, 'CollapsingHeader', function(label) return MORE_LOOK and label == 'More look' or GRID_FOLD and label:find('Grid and snapping', 1, true) == 1; end);
    end;
    if GRID_FOLD then settings.edit_mode.grid_mode = true; end;
    if PANEL_TAB then
        settings.panels.watch.mode = 'bars';
        require('ui.panel_frame').open(PANEL_TAB[1], PANEL_TAB[2]);
        rawset(imgui, 'CollapsingHeader', function() return PANEL_TAB[3] == true; end);
        if NAME == 'panel_alerts_rule' then require('ui.alert_panel').edit('bench1'); end;
    end;
    settings.window.open, settings.window.tab = true, PAGE or 'Home';
end;
-- Rules a player would keep: Signet and Level Sync everywhere, debuffs on one member, one job rule (which reads the
-- roster's jobs) and one alliance-wide rule.
local function hide_rules()
    local effect_filters = require('core.effect_filters');
    local rules = {};
    for _, fields in ipairs({ { effect = 253 }, { effect = 269 }, { effect = 0, kind = 'debuff', name = 'Member3' },
        { effect = 41, job = 3 }, { effect = 0, kind = 'neutral', scope = 'alliance' } }) do
        local rule = effect_filters.rule();
        for key, value in pairs(fields) do rule[key] = value; end;
        rules[#rules + 1] = rule;
    end;
    return rules;
end;
if FILTERS_ON then
    settings.effect_filters = { enabled = true, rules = hide_rules() };
end;
app.refresh(MOCK.now);

-- The party cooldown watch everywhere and two ready pulses kept playing: each member's two-hour and a key ability,
-- the list on, the estimates over heads, the combined recast panel showing the harness's recasts (with their locks),
-- and the pulses held mid-way. An addon folder without them has none.
local cooldowns_playing = false;
local function cooldowns_on(on)
    local s = app.state.settings;
    if not s.party_cooldowns then assert(not on, 'This addon has no party cooldowns.'); return; end;
    s.party_cooldowns.list.enabled, s.party_cooldowns.overhead = on, on;
    s.recast_display = on and 'combined' or 'separate';
    cooldowns_playing, dispel_learned = on, on;
    if not on then return; end;
    -- The watch, the pulse, the tints and the panels' light are off at first, so this turns them on, and a long session
    -- keeps them on after it, so the numbers stay comparable.
    s.party_cooldowns.enabled, s.ready_pulse.enabled = true, true;
    s.recast_tints.mp, s.recast_tints.spell_lock, s.recast_tints.ability_lock = true, true, true;
    s.panels.target.dispel_light, s.panels.watch.dispel_light = true, true;
    local abilities = { { 18, 74 }, { 19, 75 }, { 20, 83 }, { 22, 48 }, { 29, 61 } };
    for slot = 1, 5 do
        for _, ability in ipairs(abilities[slot]) do
            app.cooldowns:observe({ kind = 'cooldown', entity_id = 1001 + slot, ability = ability, entity_name = 'Member' .. slot }, MOCK.now);
        end;
    end;
    s.ready_pulse.length = 5;
    app.pulses:test(s, MOCK.now);
    s.ready_pulse.spot = 'screen';
    app.pulses:test(s, MOCK.now);
    s.ready_pulse.spot = 'row';
end;
cooldowns_on(COOLDOWNS_ON);
if COOLDOWNS_ON then app.refresh(MOCK.now); end;

-- The Phantom Roll display with your Chaos Roll and a member's Hunter's Roll, kept in their Double-Up windows, and the
-- pet display with a jug pet, eight effects on it, two of them near their end, your maneuvers as a /PUP and six of its
-- command recasts. An addon folder without them has neither, and one without the jug's clock and the maneuvers gets a
-- charmed pet.
local rolling = false;
local function rolls_on(on)
    local s = app.state.settings;
    if not s.rolls then assert(not on, 'This addon has no Phantom Roll display.'); return; end;
    s.rolls.enabled, rolling = on, on;
    if not on then return; end;
    app.rolls:observe({ kind = 'roll', entity_id = 1001, ability = 105, total = 4, targets = { 1001, 1002, 1003, 1004 },
        results = { 'got', 'got', 'none', 'got' } }, MOCK.now);
    app.rolls:observe({ kind = 'roll', entity_id = 1002, ability = 108, total = 9, double_up = true, targets = { 1002, 1001, 1005 },
        results = { 'got', 'got', 'got' } }, MOCK.now);
end;
local function pet_on(on)
    local s = app.state.settings;
    if not s.pet then assert(not on, 'This addon has no pet display.'); return; end;
    s.pet.enabled, pet_out = on, on;
    MOCK.player.sub_job = on and 18 or 13;
    if not on then return; end;
    if app.pet.takes then
        app.pet:observe({ kind = 'call_beast', entity_id = 1001, item = 17864 }, MOCK.now, app.state.snapshot);
        app.refresh(MOCK.now);
    else
        app.pet:observe({ kind = 'check', entity_id = PET_ID, level = 72 }, MOCK.now);
        app.pet:observe({ kind = 'charm', entity_id = PET_ID, items = {} }, MOCK.now, app.state.snapshot);
    end;
    -- The pet comes, and then your maneuvers, after your effects: on you with their server timers, so any addon's timer
    -- panels draw them, and the chance the last Fire and Thunder reported, which last the whole of a measurement.
    for slot, effect in ipairs({ 300, 300, 304, 306 }) do
        buffs[slot + 15], timers[slot + 15] = effect, ((1000000 + math.floor(MOCK.now) + 300 + slot * 60) * 60) % 4294967296;
    end;
    if app.pet.takes then
        app.pet:observe({ kind = 'maneuver', entity_id = 1001, maneuver = 300, percent = 90 }, MOCK.now, app.state.snapshot);
        app.pet:observe({ kind = 'maneuver', entity_id = 1001, maneuver = 304, percent = 60 }, MOCK.now, app.state.snapshot);
    end;
    -- Blink starts early here, so the first two effects blink for as long as a measurement runs and the rest don't.
    s.pet.blink_seconds = 300;
    local observations = {};
    for effect = 1, 8 do
        observations[effect] = { kind = 'apply', entity_id = PET_ID, effect = effect <= 3 and 1 + effect or 31 + effect, source = 1001,
            duration = effect <= 2 and 280 or 600 + effect * 60, scope = 'pet' };
    end;
    app.tracker:observe(observations, MOCK.now, app.state.snapshot);
end;
rolls_on(ROLLS_ON);
pet_on(PET_ON);
-- Party cooldowns' list rows show with the watch and the list on. Nobody has used anything, so the scene stays party6's.
if NAME == 'panel_cooldowns' then
    app.state.settings.party_cooldowns.enabled, app.state.settings.party_cooldowns.list.enabled = true, true;
end;
if ROLLS_ON or PET_ON then app.refresh(MOCK.now); end;

-- Edit mode with anchors and show conditions that hold. An addon folder without edit mode has none.
local function editing_on(on)
    local s = app.state.settings;
    if not s.edit_mode then assert(not on, 'This addon has no edit mode.'); return; end;
    app.callbacks.edit_mode(on);
    local function anchor(fields)
        local value = require('core.anchors').make();
        for key, item in pairs(fields or {}) do value[key] = item; end;
        return value;
    end;
    local conditions = require('core.conditions');
    s.panels.self_debuffs.anchor = anchor(on and { to = 'element', element = 'self_buffs', side = 'below' });
    s.panels.target.anchor = anchor(on and { to = 'screen', point = 'top_right', dx = -20, dy = 20 });
    s.panels.recasts.anchor = anchor(on and { to = 'chat', side = 'above' });
    s.alerts.notice_anchor = anchor(on and { to = 'party', side = 'above', align = 'end' });
    for _, id in ipairs(rule_defaults.panel_order) do
        s.panels[id].conditions = conditions.tidy(on and { main_jobs = { 5 }, zones = { 'field' } } or nil);
    end;
end;
editing_on(EDIT_ON);
if EDIT_ON then app.refresh(MOCK.now); end;

-- The words and pages of a player typing.
local WORDS = { 'e', 'ef', 'eff', 'effe', 'effec', 'effects', 'haste', 'colors', 'window', 'font', 'recast', 'settings font' };
local TABS = { 'Home' };
for _, page in pairs(PAGES) do TABS[#TABS + 1] = page; end;
table.sort(TABS);
local typing, typed = TYPING, 0;
local function type_on()
    if typed % 25 == 0 then box_text = WORDS[typed / 25 % #WORDS + 1]; end;
    if typed % 100 == 0 then app.state.settings.window.tab = TABS[typed / 100 % #TABS + 1]; end;
    typed = typed + 1;
end;

local present = MOCK.events.d3d_present.vantage_present;
-- The game begins its scenes before it presents a frame, and overhead icons read the camera at the 2nd at first. An
-- addon folder without overhead icons registers no BeginScene.
local scene = MOCK.events.d3d_beginscene and MOCK.events.d3d_beginscene.vantage_overhead_scene;
local function frame()
    MOCK.now = MOCK.now + 1 / 60;
    if typing then type_on(); end;
    if cooldowns_playing then for _, entry in ipairs(app.pulses.active) do entry.started = MOCK.now - 1; end; end;
    if rolling then
        for _, roller in pairs(app.rolls.rollers) do for _, entry in pairs(roller.rolls) do entry.window_end = MOCK.now + 30; end; end;
    end;
    if scene then scene(true); scene(true); end;
    present();
end;
-- vantage.lua carries on without a window that failed to load or draw, and that would pass as a fast one.
function H.run(count)
    for _ = 1, count do frame(); end;
    if app.state.settings.window.open then
        assert(type(package.loaded['ui.settings_window']) == 'table' and not app.state.settings_stopped, 'The settings window did not draw.');
    end;
end;

-- Moves the running app to another scenario, as one long session moves between them: the party, the player's buffs
-- and timers (timed from now) and the party's icons that scenario starts with, its target and alliance effects added
-- to what the tracker already holds, and its party list buffs, settings window and hide rules set by the commands a
-- player types. Nothing removes what an earlier scene tracked: those effects stay until they wear off, so after
-- alliance18 every scene draws its 32 target effects. jit_flush_guard.py runs its mixed session with it.
local function always() return true; end;
local function command(text)
    local event = { command = text };
    MOCK.fire('command', event);
    assert(event.blocked, text);
end;
function H.scene(name)
    local listing, throwing, keeping, moving = name == 'cooldowns', name == 'rolls', name == 'pet', name == 'edit';
    local searching = name == 'search';
    local open, hiding, placing = name == 'settings' or searching, name == 'filters', name == 'overhead' or listing;
    local base = (open or hiding or placing or throwing or keeping or moving) and 'party6' or name;
    assert(base == 'solo' or base == 'party6' or base == 'alliance18', 'unknown scenario');
    local count, each, own, aimed = shape(base);
    fill(count, each, own, math.floor(MOCK.now));
    track(count, each, aimed, placing);
    command('/vg set party_ui.enabled ' .. tostring(base ~= 'solo'));
    for _, section in ipairs(open_sections) do rawset(imgui, section, open and always or nil); end;
    command('/vg set window.open ' .. tostring(open == true));
    -- The box stays in the stand-in once a session has typed, so the next window opens with it empty.
    if searching then rawset(imgui, 'InputTextWithHint', search_box); end;
    typing, box_text = searching, '';
    local rules = hiding and { enabled = true, rules = hide_rules() } or require('core.effect_filters').make();
    command('/vg set effect_filters ' .. require('core.store').encode(rules));
    overhead_on(app.state.settings.overhead, placing);
    cooldowns_on(listing);
    rolls_on(throwing);
    pet_on(keeping);
    editing_on(moving);
    app.refresh(MOCK.now);
    -- A set replaces the settings table.
    H.settings = app.state.settings;
end;

function H.info()
    local view = app.state.view;
    return #view.rows, app.state.roster and #(app.state.roster.members or {}) or 0, tostring(app.state.problem);
end;

function H.draw_digest(frames)
    digest.on, digest.value, digest.count, digest.ids, digest.next_id = true, 0, 0, {}, 0;
    for _ = 1, frames do frame(); end;
    digest.on = false;
    return digest.count, digest.value;
end;

-- KB allocated per frame, the collector stopped so nothing is freed while counting.
function H.alloc(count)
    collectgarbage('collect'); collectgarbage('collect');
    collectgarbage('stop');
    local before = collectgarbage('count');
    for _ = 1, count do frame(); end;
    local after = collectgarbage('count');
    collectgarbage('restart');
    collectgarbage('collect');
    return (after - before) / count;
end;

-- Milliseconds per frame with the collector running, or stopped (it then collects between repeats).
function H.time(count, stopped)
    collectgarbage('collect');
    if stopped then collectgarbage('stop'); end;
    local start = clock();
    for _ = 1, count do frame(); end;
    local elapsed = (clock() - start) / count * 1000;
    if stopped then collectgarbage('restart'); collectgarbage('collect'); end;
    return elapsed;
end;

local function median(values)
    local sorted = {};
    for index, value in ipairs(values) do sorted[index] = value; end;
    table.sort(sorted);
    return sorted[math.floor((#sorted + 1) / 2)];
end;

-- LuaJIT throws every compiled trace away when its trace cache is full and starts over. This counts those flushes
-- from the first call on (nil without the jit module). The harness only; the addon never attaches a handler.
local flushes;
local function count_flushes()
    if flushes == nil and jit and jit.attach then
        flushes = 0;
        jit.attach(function(what) if what == 'flush' then flushes = flushes + 1; end; end, 'trace');
    end;
    return flushes;
end;

-- Trace flushes in count frames after warm frames.
function H.flushes(warm, count)
    count_flushes();
    H.run(warm);
    local before = flushes;
    H.run(count);
    return before and flushes - before;
end;

-- Milliseconds of each of count frames, the collector running: mean, p95, p99 and max.
function H.tails(count)
    collectgarbage('collect');
    local times, sum = {}, 0;
    for index = 1, count do
        local start = clock();
        frame();
        times[index] = (clock() - start) * 1000;
        sum = sum + times[index];
    end;
    table.sort(times);
    local function pick(p) return times[math.min(count, math.floor(count * p) + 1)]; end;
    return sum / count, pick(0.95), pick(0.99), times[count];
end;

-- One measurement line: allocation (median of 3), then the median of repeats with the collector on and off, then
-- the tails of frames * 5 single frames (at least 1,500) with the collector on, and the trace flushes in all of it
-- after the warmup.
function H.measure(frames, repeats)
    H.run(300);
    local flushed = count_flushes();
    local allocs, running, stopped = {}, {}, {};
    for index = 1, 3 do allocs[index] = H.alloc(frames); end;
    for index = 1, repeats do running[index] = H.time(frames, false); end;
    for index = 1, repeats do stopped[index] = H.time(frames, true); end;
    local count = math.max(1500, frames * 5);
    local mean, p95, p99, max = H.tails(count);
    local function list(values)
        local out = {};
        for index, value in ipairs(values) do out[index] = string.format('%.3f', value); end;
        return table.concat(out, ' ');
    end;
    return string.format('%s: %.1f KB/frame | GC on %.3f ms (%s) | GC off %.3f ms (%s) | %d frames GC on mean %.3f '
        .. 'p95 %.3f p99 %.3f max %.3f ms | flushes %s', (HELD or TYPING or MORE_LOOK ~= nil) and NAME or PAGE_SCENARIO or SETTINGS_OPEN and 'settings' or FILTERS_ON and 'filters'
        or COOLDOWNS_ON and 'cooldowns' or OVERHEAD_ON and 'overhead' or ROLLS_ON and 'rolls' or PET_ON and 'pet' or EDIT_ON and 'edit' or SCENARIO,
        median(allocs), median(running), list(running), median(stopped), list(stopped), count, mean, p95, p99, max,
        flushed and tostring(flushes - flushed) or 'n/a');
end;
