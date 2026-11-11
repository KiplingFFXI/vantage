-- The self panels beside the real vantage.lua, client, observer, tracker and hud. The client memory (buff array,
-- icons and timers) and the status icons are fixture code. A frame is one Present. It reports which status icons
-- Present left visible inside its window and clip rects, and the text it drew.
return function()
    local h = {pictures=0, listed={}};
    package.loaded['ui.icons'] = {status=function(id) h.pictures = h.pictures + 1; return 5000 + id; end,
        prepare=function() end, clear=function() end, artwork_status=function() return {available=true}; end,
        reason=function() return nil; end};
    local base = 100000;
    package.preload['core.clock'] = function() return {available=function() return true; end,get_game_time_raw=function() return math.floor(base + MOCK.now); end}; end;
    local buffs, icons, timers = {}, {}, {};
    for slot = 0, 31 do buffs[slot], icons[slot], timers[slot] = -1, 255, 0; end
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    player.GetBuffs = function() return buffs; end;
    player.GetStatusIcons = function() return icons; end;
    player.GetStatusTimers = function() return timers; end;
    -- A settings page edit lands inside Present, before the panels are drawn.
    package.loaded['ui.settings_window'] = {blocks_input=function() return false; end,
        draw=function(settings, _, callbacks)
            local edit = h.page;
            h.page = nil;
            if edit then callbacks.changed('before', 'Fixture page'); edit(settings); callbacks.changed('after'); end
        end};
    local client = require('core.client');
    client.visibility = function(snapshot)
        if not snapshot or not snapshot.valid then return nil; end
        return {valid=true, id=MOCK.player.server_id, zone=MOCK.player.zone, hidden=false, map=false, chat_open=false, in_event=false};
    end;
    h.app = dofile(ADDON_DIR .. '/vantage.lua');
    h.hud = require('ui.hud');
    MOCK.screen = {1600, 1000};
    MOCK.now = 1;
    h.app.refresh(1);
    local s = h.app.state.settings;
    s.party_ui.enabled = false;
    s.style.font, s.style.font_size, s.style.scale = 'Ashita', 14, 1;
    for id, panel in pairs(s.panels) do panel.enabled = id == 'self_buffs' or id == 'self_debuffs'; end
    h.settings = s;

    -- Status icons left visible: texture 5000 + effect, inside its window and the clip rects pushed over it.
    local function painted()
        local counts, places, texts, stack, position, size = {}, {}, {}, {}, nil, nil;
        local open = {-1e9, -1e9, 1e9, 1e9};
        for _, call in ipairs(MOCK.imgui_calls) do
            local name = call[1];
            if name == 'SetNextWindowPos' then position = call[2];
            elseif name == 'SetNextWindowSize' then size = call[2];
            elseif name == 'Begin' then
                stack = {position and size and {position[1], position[2], position[1] + size[1], position[2] + size[2]} or open};
                position, size = nil, nil;
            elseif name == 'End' then stack = {};
            elseif name == 'draw:PushClipRect' then
                local drawn = MOCK.drawn[call];
                local a, b, top = drawn[2], drawn[3], stack[#stack] or open;
                local clip = {a[1], a[2], b[1], b[2]};
                if call[4] then clip = {math.max(clip[1], top[1]), math.max(clip[2], top[2]), math.min(clip[3], top[3]), math.min(clip[4], top[4])}; end
                stack[#stack + 1] = clip;
            elseif name == 'draw:PopClipRect' then stack[#stack] = nil;
            elseif name == 'draw:AddText' and type(call[6]) == 'string' then texts[#texts + 1] = call[6];
            elseif name == 'draw:AddImage' and type(call[2]) == 'number' and call[2] >= 5000 and call[2] < 6024 then
                -- The hud refills one pair of corners for every picture, so each is read as it was when drawn.
                local drawn = MOCK.drawn[call];
                local a, b, top = drawn[3], drawn[4], stack[#stack] or open;
                if math.min(b[1], top[3]) > math.max(a[1], top[1]) and math.min(b[2], top[4]) > math.max(a[2], top[2]) then
                    local effect = call[2] - 5000;
                    counts[effect] = (counts[effect] or 0) + 1;
                    places[#places + 1] = {effect=effect, x=a[1], y=a[2]};
                end
            end
        end
        return counts, places, texts;
    end
    -- elapsed is how long the frame takes, 1/60 s unless given.
    function h.frame(elapsed)
        MOCK.imgui_calls = {};
        MOCK.frame(elapsed or 1 / 60);
        local counts, places, texts = painted();
        return {icons=counts, places=places, texts=texts};
    end
    function h.run(count)
        local last;
        for _ = 1, count do last = h.frame(); end
        return last;
    end
    -- Lists effects in slot order, with their icons and timers, and sends the packets that report them. An end of
    -- false lists that effect with no timer.
    function h.both(list, ends)
        h.listed = list;
        for index = 0, 31 do
            local effect = list[index + 1];
            local ending = effect and ends and ends[effect];
            buffs[index], icons[index] = effect or -1, effect or 255;
            timers[index] = effect and ending ~= false and (math.floor(base + (ending or 600)) * 60) % 4294967296 or 0;
        end
        MOCK.fire('packet_in', MOCK.packet(0x037, MOCK.bytes(0x50)));
        local bytes = MOCK.bytes(200);
        MOCK.put(bytes, 4, 2, 9);
        MOCK.fire('packet_in', MOCK.packet(0x063, bytes));
    end
    function h.count(counts)
        local total = 0;
        for _, value in pairs(counts) do total = total + value; end
        return total;
    end
    -- The '+N more' line a frame drew, if any.
    function h.more(record)
        for _, text in ipairs(record.texts) do if text:match('^%+%d+ more$') then return text; end end
        return nil;
    end
    function h.describe(counts)
        local out = {};
        for effect, value in pairs(counts) do out[#out + 1] = effect .. (value > 1 and ('x' .. value) or ''); end
        table.sort(out);
        return '[' .. table.concat(out, ',') .. ']';
    end
    return h;
end
