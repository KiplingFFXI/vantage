-- One cast on several members as one row, for Party members' timers (One row for a cast on several members). Rows fold
-- when they are the same effect from the same caster and landed within a second of each other: a Protectra, a song, a
-- roll. Copies that nothing was seen to put on have no countdown to tell them apart, so those fold by effect. Copy
-- Image's icon says how many shadows are left, so its copies with other counts stay apart (together, below). A member
-- is in a row once, so two songs of one kind on each member make two rows. A folded row is a row of its own that stands
-- for its members' rows, which stay as the tracker made them.
local clear = require('table.clear');
local folds = {};

-- 'N members', made once for each count. It starts with a digit, so sorted by who it is on a folded row comes ahead of
-- the members' names.
local counts = {};
local function who(count)
    local text = counts[count];
    if not text then
        text = count .. ' members';
        counts[count] = text;
    end
    return text;
end

-- A Copy Image row's icon is how many shadows are left (core/tracker.lua as_copy_image, Phoenix
-- scripts/globals/spells/enhancing_ninjutsu.lua :47-61, :119 and src/map/utils/battleutils.cpp :3149-3168), so copies
-- that show other counts stay apart.
local function together(a, b)
    if a.icon ~= b.icon then return false end
    if a.start == nil or b.start == nil then
        return a.start == nil and b.start == nil and a.deadline == nil and b.deadline == nil;
    end
    return a.source == b.source and math.abs(a.start - b.start) <= 1;
end

-- This frame's buckets: each one's rows, the first bucket of each effect and the next one of the same effect, and the
-- bucket each row went to.
local buckets, used = {}, 0;
local first, after, bucket_of = {}, {}, {};

local function bucket_for(row)
    local at = first[row.effect];
    while at do
        local members = buckets[at];
        if together(row, members[1]) then
            local twice = false;
            for index = 1, #members do
                if members[index].entity_id == row.entity_id then twice = true; break; end
            end
            if not twice then return at; end
        end
        at = after[at];
    end
    used = used + 1;
    local members = buckets[used];
    if members then clear(members); else members = {}; buckets[used] = members; end
    after[used], first[row.effect] = first[row.effect], used;
    return used;
end

-- When a row's countdown ends, or nil for one that shows none (ui/hud.lua timer_text).
local function ends(row)
    return row.status ~= 'unknown' and row.deadline or nil;
end

-- The folded row for a bucket: a copy of the row of the copy that ends first, so its end, its time left and how sure
-- its time is all come from one copy, and it counts the bucket's members. A member's estimate doesn't move, and your
-- own copy goes by the game's timer, which can sit a moment either side of it. So your copy is the one copied only
-- when it ends over a second before every member's, or when no member's is timed. Its key is its first member's.
local function fill(fold, members, kept)
    local base, own;
    for index = 1, #members do
        local row = members[index];
        if row.scope == 'self' then own = row;
        elseif not base or ends(row) and (not ends(base) or ends(row) < ends(base)) then base = row; end
    end
    if own and ends(own) and (not ends(base) or ends(own) < ends(base) - 1) then base = own; end
    clear(fold);
    for key, value in pairs(base) do fold[key] = value; end
    local lead = members[1].key;
    if kept.from ~= lead then kept.from, kept.key = lead, 'fold:' .. tostring(lead); end
    fold.key, fold.entity_name, fold.folded = kept.key, who(#members), kept.members;
    clear(kept.members);
    for index = 1, #members do kept.members[index] = members[index]; end
    return fold;
end

-- Folds rows in place and returns it. pool keeps the folded rows from one frame to the next: with none, each call makes
-- its own.
function folds.apply(rows, pool)
    local count = #rows;
    if count < 2 then return rows; end
    used = 0;
    clear(first);
    for index = 1, count do
        local at = bucket_for(rows[index]);
        local members = buckets[at];
        members[#members + 1], bucket_of[index] = rows[index], at;
    end
    local out, made = 0, 0;
    for index = 1, count do
        local row, members = rows[index], buckets[bucket_of[index]];
        if #members > 1 then
            if members[1] == row then
                made = made + 1;
                local kept = pool and pool[made];
                if not kept then
                    kept = { row = {}, members = {} };
                    if pool then pool[made] = kept; end
                end
                row = fill(kept.row, members, kept);
            else
                row = nil;
            end
        end
        if row then
            out = out + 1;
            rows[out] = row;
        end
    end
    for index = out + 1, count do rows[index] = nil; end
    for index = 1, used do clear(buckets[index]); end
    return rows;
end

-- A line for each member of a folded row, with their time when they have one, added to a hover's lines. time_of gives
-- a row's time as text at now.
function folds.lines(row, out, time_of, now)
    for _, member in ipairs(row.folded) do
        local left = time_of(member, now);
        out[#out + 1] = '    ' .. (member.entity_name or 'A party member') .. (left ~= '' and '  ' .. left or '');
    end
end

return folds;
