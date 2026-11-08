-- Short member names are cut between characters, so a non-ASCII name never ends in half a character.
local labels = require('ui.party_labels');

local function valid_utf8(value)
    local at = 1;
    while at <= #value do
        local byte, size = value:byte(at), 1;
        if byte >= 0xC2 and byte <= 0xDF then size = 2;
        elseif byte >= 0xE0 and byte <= 0xEF then size = 3;
        elseif byte >= 0xF0 and byte <= 0xF4 then size = 4;
        elseif byte >= 0x80 then return false; end
        for offset = 1, size - 1 do
            local next_byte = value:byte(at + offset);
            if not next_byte or next_byte < 0x80 or next_byte > 0xBF then return false; end
        end
        at = at + size;
    end
    return true;
end
local names = { '\195\137l\195\169onore Ch\195\162teau', '\227\131\135\227\130\163\227\130\185\227\131\134\227\130\163\227\131\179\227\130\175\227\131\136',
    'Zo\195\171 \240\159\152\128 Smile', 'Plain ASCII name' };

for limit = 3, 16 do
    for _, value in ipairs(names) do
        local short = labels.member_name({ name = value }, { name_display = 'short', name_length = limit });
        assert(valid_utf8(short) and #require('ui.text_wrap').characters(short) <= limit, 'short name at ' .. limit);
    end
end
assert(labels.member_name({ name = 'Longername' }, { name_display = 'short', name_length = 5 }) == 'Long.');
assert(labels.member_name({ name = '\195\137l\195\169onore' }, { name_display = 'short', name_length = 5 }) == '\195\137l\195\169o.');
