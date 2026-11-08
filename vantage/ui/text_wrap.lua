local wrap = {};

local function characters(value)
    local out, at = {}, 1;
    while at <= #value do
        local byte, size = value:byte(at), 1;
        if byte >= 0xC2 and byte <= 0xDF then size = 2;
        elseif byte >= 0xE0 and byte <= 0xEF then size = 3;
        elseif byte >= 0xF0 and byte <= 0xF4 then size = 4; end;
        for offset = 1, size - 1 do
            local next_byte = value:byte(at + offset);
            if not next_byte or next_byte < 0x80 or next_byte > 0xBF then size = 1; break; end;
        end;
        out[#out + 1], at = value:sub(at, at + size - 1), at + size;
    end;
    return out;
end
-- Splits text into its UTF-8 characters; a byte that starts no complete character stands alone.
wrap.characters = characters;

function wrap.lines(value, width, measure)
    local lines = {};
    value, width = tostring(value or ''), math.max(1, width);
    local function paragraph(part)
        local line = '';
        local function emit()
            if line ~= '' then lines[#lines + 1], line = line:gsub('%s+$', ''), ''; end;
        end;
        for gap, word in part:gmatch('(%s*)(%S+)') do
            gap = line == '' and '' or gap;
            if line ~= '' and measure(line .. gap .. word) > width then emit(); gap = ''; end;
            if measure(word) <= width then line = line .. gap .. word;
            else
                for _, character in ipairs(characters(word)) do
                    if line ~= '' and measure(line .. character) > width then emit(); end;
                    line = line .. character;
                end;
            end;
        end;
        if line ~= '' then emit(); elseif part == '' then lines[#lines + 1] = ''; end;
    end;
    for part in (value:gsub('\r\n', '\n'):gsub('\r', '\n') .. '\n'):gmatch('(.-)\n') do paragraph(part); end;
    if #lines == 0 then lines[1] = ''; end;
    return lines;
end

return wrap;
