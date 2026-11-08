local labels = {};
local wrap = require('ui.text_wrap');
local jobs = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG',
    'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP' };

function labels.job_name(job)
    if type(job) ~= 'number' or job ~= math.floor(job) then return nil; end;
    return jobs[job];
end;

local function shorten(value, limit)
    if #value <= limit then return value; end;
    if not value:find('[\128-\255]') then return value:sub(1, limit - 1) .. '.'; end;
    local characters = wrap.characters(value);
    if #characters <= limit then return value; end;
    return table.concat(characters, '', 1, limit - 1) .. '.';
end;

function labels.member_name(member, config)
    member, config = member or {}, config or {};
    if member.available ~= false and member.same_zone ~= false
        and (config.name_display == 'job' or config.name_display == 'job_icon' or config.name_display == 'icon') then
        local job = labels.job_name(member.job);
        if job then return job; end;
    end;
    local name = type(member.name) == 'string' and member.name ~= '' and member.name or 'Member';
    if config.name_display ~= 'short' then return name; end;
    local limit = config.name_length;
    if type(limit) ~= 'number' or limit ~= limit or math.abs(limit) == math.huge then limit = 8; end;
    return shorten(name, math.max(3, math.min(16, math.floor(limit))));
end;

local function zone_label(value)
    if type(value) ~= 'string' or #value > 128 or value:find('[%c]') then return ''; end;
    value = value:match('^%s*(.-)%s*$');
    if value == '.' or value:lower() == 'unknown' then return ''; end;
    return value;
end;

function labels.full_zone_name(member)
    return zone_label(member and member.zone_name);
end;

return labels;
