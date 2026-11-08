-- The game for the pet tests: the real addon takes the packets the server sends, over a client that shows your job,
-- skill, gear, own effects and pet as game holds them. A test sets game, sends packets and calls step, then reads what
-- came out with rows and row, and what the pet display drew with draw.
-- game.pet is { index, id, name, flags, hpp }; with away set the client's unit for it has gone, and with no_index its
-- pet index too. game.buffs is your own effects, each { effect, ends }, with ends on the test's clock.
return function()
    local game = { id = 1001, index = 0x400, zone = 102, name = 'Tester', job = 9, level = 75, sub = 0, sub_level = 0, skill = 0,
        chr = 60, chr_bonus = 10, items = {}, buffs = {}, members = {}, units = {} };
    local icons, timers = {}, {};
    package.loaded['core.clock'] = { available = function() return true; end, get_game_time_raw = function() return 1000000 + MOCK.now; end };
    local function listed()
        for slot = 0, 31 do
            local buff = game.buffs[slot + 1];
            icons[slot], timers[slot] = buff and buff.effect or 255, buff and buff.ends and (1000000 + buff.ends) * 60 % 4294967296 or 0;
        end
        return icons;
    end
    local function unit(index)
        if index == game.index then return game; end
        local pet = game.pet;
        if pet and pet.index == index then return not pet.away and pet or nil; end
        for _, member in ipairs(game.members) do if member.index == index then return member; end end
        return game.units[index];
    end
    local entity = {
        GetServerId = function(_, index) local found = unit(index); return found and found.id or 0; end,
        GetName = function(_, index) local found = unit(index); return found and found.name or nil; end,
        GetSpawnFlags = function(_, index) local found = unit(index); return found and found.flags or 0x01; end,
        GetHPPercent = function(_, index) local found = unit(index); return found and found.hpp or 0; end,
        GetPetTargetIndex = function(_, index) return index == game.index and game.pet and not game.pet.no_index and game.pet.index or 0; end,
        GetStatus = function() return 0; end, GetDistance = function() return 5; end, GetRenderFlags0 = function() return 0x200; end,
        GetActorPointer = function() return 0; end, GetType = function() return 0; end,
    };
    local skill = { GetSkill = function() return game.skill; end };
    local player = {
        GetMainJob = function() return game.job; end, GetMainJobLevel = function() return game.level; end,
        GetSubJob = function() return game.sub; end, GetSubJobLevel = function() return game.sub_level; end,
        GetIsZoning = function() return false; end, GetLoginStatus = function() return 2; end,
        GetBuffs = listed, GetStatusIcons = listed, GetStatusTimers = function() listed(); return timers; end,
        GetPetMPPercent = function() return 0; end, GetPetTP = function() return 0; end, GetCombatSkill = function() return skill; end,
        GetStat = function(_, index) return index == 6 and game.chr or 0; end, GetStatModifier = function(_, index) return index == 6 and game.chr_bonus or 0; end,
        HasSpell = function() return false; end,
    };
    local function member(slot) return slot == 0 and game or game.members[slot]; end
    local party = {
        GetMemberServerId = function(_, slot) local m = member(slot); return m and m.id or 0; end,
        GetMemberTargetIndex = function(_, slot) local m = member(slot); return m and m.index or 0; end,
        GetMemberZone = function(_, slot) return member(slot) and game.zone or 0; end,
        GetMemberName = function(_, slot) local m = member(slot); return m and m.name or ''; end,
        GetMemberIsActive = function(_, slot) return member(slot) and 1 or 0; end,
        GetMemberHPPercent = function() return 100; end, GetMemberMP = function() return 100; end,
        GetStatusIconsServerId = function() return 0; end, GetStatusIconsTargetIndex = function() return 0; end,
        GetStatusIcons = function() return nil; end, GetStatusIconsBitMask = function() return 0; end,
    };
    local inventory = { GetEquippedItem = function(_, slot) return { Index = game.items[slot] and 0x100 + slot or 0 }; end,
        GetContainerItem = function(_, _, index) return { Id = game.items[index] }; end };
    local target = { GetTargetIndex = function() return 0; end, GetIsSubTargetActive = function() return 0; end };
    local recast = { GetSpellTimer = function() return 0; end, GetAbilityTimerId = function() return 0; end, GetAbilityTimer = function() return 0; end };
    local memory = { GetEntity = function() return entity; end, GetPlayer = function() return player; end, GetParty = function() return party; end,
        GetInventory = function() return inventory; end, GetTarget = function() return target; end, GetRecast = function() return recast; end };
    AshitaCore.GetMemoryManager = function() return memory; end;
    GetPlayerEntity = function() return { Name = game.name, ServerId = game.id, Status = 0, StatusServer = 0, ZoneId = game.zone }; end;

    local app = dofile(ADDON_DIR .. '/vantage.lua');
    MOCK.now = 10;
    MOCK.fire('load');
    app.refresh(MOCK.now);
    local settings = app.state.settings;
    settings.pet.enabled = true;

    local fx = { game = game, app = app };
    function fx.step(seconds)
        MOCK.now = MOCK.now + (seconds or 0.1);
        app.refresh(MOCK.now);
    end
    local function putbits(bytes, offset, length, value)
        for i = 0, length - 1 do
            local at = offset + i;
            if math.floor(value / 2 ^ i) % 2 == 1 then bytes[math.floor(at / 8)] = bytes[math.floor(at / 8)] + 2 ^ (at % 8); end
        end
    end
    -- A 0x028: its actor, category and id, and for each target { id, message, param }.
    function fx.action(actor, category, id, targets)
        local bytes, at = MOCK.bytes(2048), 150;
        putbits(bytes, 40, 32, actor); putbits(bytes, 72, 6, #targets); putbits(bytes, 82, 4, category); putbits(bytes, 86, 32, id);
        for _, row in ipairs(targets) do
            putbits(bytes, at, 32, row[1]); putbits(bytes, at + 32, 4, 1); at = at + 36;
            putbits(bytes, at + 27, 17, row[3] or 0); putbits(bytes, at + 44, 10, row[2]); at = at + 87;
        end
        bytes.n = math.ceil(at / 8);
        MOCK.fire('packet_in', MOCK.packet(0x028, bytes));
    end
    -- A 0x029 battle message: actor, target, param and message.
    function fx.message(actor, target, param, number)
        local bytes = MOCK.bytes(28);
        MOCK.put(bytes, 4, 4, actor); MOCK.put(bytes, 8, 4, target); MOCK.put(bytes, 12, 4, param); MOCK.put(bytes, 24, 2, number);
        MOCK.fire('packet_in', MOCK.packet(0x029, bytes));
    end
    -- The 0x063 that gives your own effects' timers.
    function fx.status()
        local bytes = MOCK.bytes(200);
        MOCK.put(bytes, 4, 2, 9);
        MOCK.fire('packet_in', MOCK.packet(0x063, bytes));
    end
    -- A 0x068 pet sync, or with no index the empty one that says your pet has gone.
    function fx.sync(index, hpp, name)
        local bytes = MOCK.bytes(index and 0x2C or 0x1C);
        MOCK.put(bytes, 8, 4, game.id);
        if index then
            MOCK.put(bytes, 0x0C, 2, index); MOCK.put(bytes, 0x0E, 1, hpp or 100);
            for i = 1, #(name or '') do bytes[0x17 + i] = name:byte(i); end
        end
        MOCK.fire('packet_in', MOCK.packet(0x068, bytes));
    end
    -- A 0x00E of a unit: despawned with the flag, else an ordinary update.
    function fx.unit(id, index, despawn)
        local bytes = MOCK.bytes(32);
        MOCK.put(bytes, 4, 4, id); MOCK.put(bytes, 8, 2, index); MOCK.put(bytes, 10, 1, despawn and 0x20 or 0x01);
        MOCK.fire('packet_in', MOCK.packet(0x00E, bytes));
    end
    -- Your merits, as { [id] = ranks }.
    function fx.merits(list)
        local count = 0;
        for _ in pairs(list) do count = count + 1; end
        local bytes = MOCK.bytes(8 + count * 4);
        MOCK.put(bytes, 4, 2, count);
        local at = 8;
        for id, ranks in pairs(list) do MOCK.put(bytes, at, 2, id); MOCK.put(bytes, at + 3, 1, ranks); at = at + 4; end
        MOCK.fire('packet_in', MOCK.packet(0x08C, bytes));
    end
    -- The zone-in: gone from the old zone, then a read in the new one.
    function fx.zone(zone)
        game.zone = zone;
        local bytes = MOCK.bytes(0x100);
        MOCK.put(bytes, 4, 4, game.id); MOCK.put(bytes, 0x30, 2, zone);
        MOCK.fire('packet_in', MOCK.packet(0x00A, bytes));
        fx.status();
    end

    local subjects = function() return app.state.party_subjects or {}; end;
    function fx.rows(id) local subject = subjects()[id]; return subject and subject.effects or {}; end
    -- The row of one effect on a unit, by the action it came from if given.
    function fx.row(id, effect, spell)
        for _, row in ipairs(fx.rows(id)) do
            if row.effect == effect and (not spell or row.spell == spell) then return row; end
        end
    end

    local display = require('ui.pet_display');
    local moving = { shift = false, over_settings = false, mx = -1, my = -1, down = false, screen_width = 1600, screen_height = 900, hover = false };
    local callbacks = { changed = function() end };
    -- All the text the pet display drew, each piece between |.
    function fx.draw(at)
        MOCK.imgui_calls = {};
        fx.spot = display.draw(app.state.view, settings, at or MOCK.now, callbacks, moving);
        local out = {};
        for _, call in ipairs(MOCK.imgui_calls) do if call[1] == 'draw:AddText' then out[#out + 1] = call[6]; end end
        return '|' .. table.concat(out, '|') .. '|';
    end
    fx.moving, fx.settings = moving, settings;
    -- What the tooltip of the row says.
    function fx.details(row) return require('ui.hud').details(row, MOCK.now, { horizon = 300 }); end
    return fx;
end;
