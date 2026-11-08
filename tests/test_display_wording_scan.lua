-- No string the addon can show says unknown, unconfirmed or not confirmed, or is a lone '?'. The words stay only as
-- internal names ('unknown' as a timer status or a saved key), so the scan leaves those out. The modules that draw
-- effects, recasts and notices also hold no '+N more' wording, and no help text tells of a hidden count or marks.
local function literals(text)
    local out, i, n = {}, 1, #text;
    while i <= n do
        local c = text:sub(i, i);
        if text:sub(i, i + 1) == '--' then
            local level = text:match('^%[(=*)%[', i + 2);
            if level then
                local close = text:find(']' .. level .. ']', i + 2, true);
                i = (close or n) + #level + 2;
            else
                i = (text:find('\n', i, true) or n) + 1;
            end;
        elseif c == '[' and text:match('^%[=*%[', i) then
            local level = text:match('^%[(=*)%[', i);
            local start = i + #level + 2;
            local close = text:find(']' .. level .. ']', start, true) or n + 1;
            out[#out + 1] = text:sub(start, close - 1);
            i = close + #level + 2;
        elseif c == '"' or c == "'" then
            local j, parts = i + 1, {};
            while j <= n do
                local d = text:sub(j, j);
                if d == '\\' then parts[#parts + 1] = text:sub(j, j + 1); j = j + 2;
                elseif d == c or d == '\n' then break;
                else parts[#parts + 1] = d; j = j + 1; end;
            end;
            out[#out + 1] = table.concat(parts);
            i = j + 1;
        else
            i = i + 1;
        end;
    end;
    return out;
end;
assert(#literals("local a = 'one' -- 'two'\nlocal b = [[three]] --[[ 'four' ]] .. \"fi\\\"ve\"") == 3, 'Fixture: the scanner reads strings, not comments.');

local words = { 'unknown', 'unconfirmed', 'not confirmed', 'not been confirmed' };
local dropped = { 'more matching effects', 'more alerts', 'additional effects', 'over the limit', 'drag taller', 'More text' };
local stale_help = { 'counted below', 'hidden count', 'uncertainty mark' };
local drawers = { ['ui/hud.lua'] = true, ['ui/party_hud.lua'] = true, ['ui/party_layout.lua'] = true, ['ui/native_party_hud.lua'] = true,
    ['ui/fields.lua'] = true, ['ui/recast_icons.lua'] = true, ['core/recasts.lua'] = true, ['core/tracker.lua'] = true,
    ['core/alerts.lua'] = true, ['core/catalog.lua'] = true, ['core/observer.lua'] = true };
local listing = io.popen('dir /b /s "' .. ADDON_DIR:gsub('/', '\\') .. '\\*.lua" 2>nul');
local files = {};
if listing then
    for line in listing:lines() do files[#files + 1] = line:gsub('\\', '/'):gsub('\r', ''); end;
    listing:close();
end;
assert(#files > 50, 'Fixture: the scan finds the addon files: ' .. #files);
local scanned, drawn = 0, 0;
for _, path in ipairs(files) do
    local name = path:sub(#ADDON_DIR + 2);
    local file = assert(io.open(path, 'rb'));
    local text = file:read('*a');
    file:close();
    for _, value in ipairs(literals(text)) do
        local lower = value:lower();
        -- An internal name: one lowercase word, such as 'unknown' or 'unknown_color', or a saved key's path. A label
        -- such as 'Unknown' is checked.
        if not value:match('^[%l%d_]+$') and not value:match('^[%l%d_]+%.[%l%d_.]+$') then
            for _, word in ipairs(words) do
                assert(not lower:find(word, 1, true), name .. ' still says ' .. word .. ': ' .. value);
            end;
        end;
        for _, phrase in ipairs(stale_help) do
            assert(not lower:find(phrase, 1, true), name .. ' still describes a hidden count or mark: ' .. value);
        end;
        -- The client patterns use '?' for any byte; no display text is a lone '?'.
        if drawers[name] or name:match('^ui/') then
            assert(value ~= '?', name .. ' shows a lone question mark.');
        end;
        if drawers[name] then
            for _, phrase in ipairs(dropped) do assert(not value:find(phrase, 1, true), name .. ' still says ' .. phrase .. ': ' .. value); end;
            assert(value ~= ' more' and value ~= ' more alerts' and not value:match('^%s*%+%s*$'), name .. ' still builds a count: ' .. value);
            drawn = drawn + 1;
        end;
        scanned = scanned + 1;
    end;
end;
assert(scanned > 1000 and drawn > 100, 'Fixture: the scan read the strings: ' .. scanned .. ', ' .. drawn);
return 'No string the addon shows says unknown or carries a dropped count';
