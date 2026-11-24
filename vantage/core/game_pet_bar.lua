-- The game's own pet bar, for Replace the game's pet bar on the main page (settings.replace_game_pet_bar). The game
-- draws your pet's name, its HP bar and its TP just above the party list, from one routine that the party list's
-- layout calls once. While the replacement is in effect that one call is skipped, so the party list is laid out as
-- it is with no pet out. Nothing else of the game's changes, and Vantage sends nothing.
--
-- The call is put back when the replacement stops being in effect and when Vantage unloads.
--
-- Nothing is changed unless both pieces are found once in the client, each one's bytes are the ones this was written
-- for, and the call still goes to the pet line's routine. Lua can't catch a crash inside the client's code, so each
-- check comes before the write it guards.
local game_pet_bar = {};
local memory = require('core.memory');
local finder = require('core.patterns');
local code_patch = require('core.code_patch');

-- Where each piece is found. pet_line is 0x3D into the pet line's routine, past its first bytes, which the routine for
-- an adventuring fellow's line shares. layout is in the party list's layout, 0x15 before its call to the pet line, and
-- that call's five bytes are ??, as they are Vantage's own while the replacement is in effect.
local patterns = {
    pet_line = '8B86A0000000538B5C241085C074608A8EEC0000008D4738884C2410508808',
    layout = '66897E5C6689565EE8????????84C08BCE75295557??????????84C0740766896E5E83ED1055578BCE',
};
-- The whole of the pet line's routine, and the layout from 0x12 before its pattern to past the fellow's line, as this
-- was written for them. ?? is an address the client fills in, and in the layout the five bytes of the call too.
local bodies = {
    pet_line = '56578BF9E8????????8BF085F675075F32C05EC208006A03E8????????83C40484C074075F32C05EC208008BCFE8????????84C074075F32C05EC208008B86A0000000538B5C241085C074608A8EEC0000008D4738884C24105088088B4C24188B44241483C107508D531A5152E8????????83C4108BCEE8????????84C0752C6A0068AE000000E8????????83C40884C07419E8????????508B44241883C00A8D4B3050518BCFE8????????6683BE1002000000A1????????760881C614020000EB0383C67C8B542414505652536A66E8????????83C414B0015B5F5EC20800',
    layout = '668B563C6A006A006A08B9????????83ED1766897E5C6689565EE8????????84C08BCE75295557??????????84C0740766896E5E83ED1055578BCEE8????????84C08BCE74085566896E5E57EB046AFF6AFF6A00E8????????',
};
local ORDER = { 'pet_line', 'layout' };
local LABELS = { pet_line = 'pet bar drawing', layout = 'party list layout' };
-- The one match inside the client module.
local RULE = { unique = true, within = true };

-- From each pattern's match: back to the pet line's routine, back to where the layout's body starts, and on to the call.
local LINE_START, LAYOUT_START, CALL = 0x3D, 0x12, 0x15;
-- The pet line's routine takes two arguments and clears them itself (it ends in ret 8), and says in al whether it drew
-- a line. In its place the stack pointer steps over the two and al says it drew none: add esp, 8, then xor al, al. The
-- layout then goes on as it does with no pet out.
local SKIP = string.char(0x83, 0xC4, 0x08, 0x32, 0xC0);

-- platform is how the client is read and written, nil where that can't be done. found holds what look() found, false
-- when this client can't be used, and refusal says why. on is whether the game's pet bar is replaced now. stopped is
-- set once the replacement could not start, and problem says why until it is out of effect again.
local platform, platform_tried;
local found, refusal, problem;
local on, stopped = false, nil;

-- The real client: page checks from core/memory.lua, the finder, and core/code_patch.lua for writing code.
-- The tests set their own, so no test ever writes anything in the process it runs in.
local function load_platform()
    if platform_tried then return platform; end
    platform_tried = true;
    if VANTAGE_TEST_MODE then return nil; end
    local ok, made = pcall(function()
        local ffi = require('ffi');
        if ffi.os ~= 'Windows' or not ffi.abi('32bit') or not ashita or not ashita.memory then return nil; end
        local write_code = code_patch.writer(ffi);
        local pages = memory.pages();
        return {
            readable = pages.readable,
            find = function(name) return finder.find('game_pet_bar', name, patterns[name], RULE); end,
            bytes = function(at, size) return ffi.string(ffi.cast('const char*', at), size); end,
            write_code = write_code,
        };
    end);
    platform = ok and made or nil;
    return platform;
end

-- look()'s searches as warmup steps after a load (core/warmup.lua), one pattern a step, as a search can pass over the
-- whole client. The finder keeps what each step found (core/patterns.lua), and look() then only checks it. A step does
-- nothing where the client can't be reached.
local searched = {};
function game_pet_bar.warmup_steps()
    local list = {};
    for index, name in ipairs(ORDER) do
        list[index] = finder.step('game_pet_bar.' .. name, searched, function()
            if load_platform() then platform.find(name); end
        end);
    end
    return list;
end

local STAYS = ', so the game\'s pet bar stays as it is.';

-- Finds both pieces once. found is the call's address with the bytes it holds unchanged.
local function look()
    if found ~= nil then return found; end
    found = false;
    if not load_platform() then
        refusal = 'Vantage can\'t reach this game client\'s drawing code' .. STAYS;
        return false;
    end
    local ok, result, why = pcall(function()
        local at = {};
        for _, name in ipairs(ORDER) do
            local where, reason = platform.find(name);
            if not where then return nil, ('This game client\'s %s %s%s'):format(LABELS[name], reason or 'is missing', STAYS); end
            at[name] = where;
        end
        local routine, site = at.pet_line - LINE_START, at.layout + CALL;
        if not code_patch.matches(platform, routine, bodies.pet_line) then
            return nil, ('This game client\'s %s is not the code Vantage knows%s'):format(LABELS.pet_line, STAYS);
        end
        if not code_patch.matches(platform, at.layout - LAYOUT_START, bodies.layout) then
            return nil, ('This game client\'s %s is not the code Vantage knows%s'):format(LABELS.layout, STAYS);
        end
        local original = code_patch.call(site, routine);
        local now = code_patch.code(platform, site, 5);
        if now ~= original and now ~= SKIP then
            return nil, 'Something else already changed how the game draws its pet bar, so Vantage leaves it alone.';
        end
        return { site = site, original = original };
    end);
    if ok and result then found = result;
    else refusal = ok and why or 'Vantage could not check this game client\'s pet bar drawing' .. STAYS; end
    return found;
end

local PUT_BACK_FAILED = 'Vantage could not put the game\'s pet bar back. Restart the game to get it back.';

-- Puts the call back when it is Vantage's skip. False when it could not be put back, or holds something else.
local function put_back()
    if not found then return true; end
    local now = code_patch.code(platform, found.site, 5);
    if now == found.original then return true; end
    if now ~= SKIP then return false; end
    local ok, written = pcall(platform.write_code, found.site, found.original);
    return ok and written == true;
end

-- Skips the call. True, or false and why not.
local function start()
    if not look() then return false, refusal; end
    local now = code_patch.code(platform, found.site, 5);
    if now == SKIP then return true; end
    if now ~= found.original then return false, 'Something else changed how the game draws its pet bar, so Vantage leaves it alone.'; end
    local ok, written = pcall(platform.write_code, found.site, SKIP);
    if ok and written == true then return true; end
    return false, put_back() and 'Vantage could not change the game\'s pet bar drawing' .. STAYS or PUT_BACK_FAILED;
end

-- Each Present. want is whether the settings ask for the game's pet bar to be replaced now. Returns a line to say
-- when the replacement could not start or could not be put back. After it could not start it says nothing more until
-- want has been false once. Asked for again, it says why again: what look() found, or didn't, is kept until Vantage
-- loads again, so only a write that failed is tried again.
function game_pet_bar.update(want)
    if not want then
        stopped, problem = nil, nil;
        if not on then return nil; end
        on = false;
        if not put_back() then problem = PUT_BACK_FAILED; return PUT_BACK_FAILED; end
        return nil;
    end
    if stopped or on then return nil; end
    local ok, why = start();
    if not ok then stopped, problem = true, why; return why; end
    on, problem = true, nil;
    return nil;
end

-- Unload: the call put back. False and a line to say when it could not be.
function game_pet_bar.release()
    local clean = put_back();
    on, stopped = false, nil;
    if not clean then return false, PUT_BACK_FAILED; end
    return true;
end

-- Why the game's pet bar isn't replaced while the settings ask for it, for its tick on the main page. nil while it is.
function game_pet_bar.problem() return problem; end

-- For /vg report: whether the game's pet bar is replaced now, and why not when it should be.
function game_pet_bar.status()
    return { on = on, problem = problem };
end

if VANTAGE_TEST_MODE then
    -- A platform of the test's own in place of the client: { readable, find, bytes, write_code }. nil is a client that
    -- can't be reached.
    function game_pet_bar._set_platform(value)
        platform, platform_tried = value, true;
        found, refusal, problem, on, stopped = nil, nil, nil, false, nil;
        for name in pairs(searched) do searched[name] = nil; end
    end
    game_pet_bar._patterns, game_pet_bar._bodies, game_pet_bar._SKIP, game_pet_bar._RULE = patterns, bodies, SKIP, RULE;
end

return game_pet_bar;
